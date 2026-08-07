--[[
    Owned vehicles — the framework's own table, behind one interface.

    qb/qbox writes `player_vehicles`, ESX writes `owned_vehicles`, and the two
    disagree about almost everything: the column that holds the model, how a
    stored car is marked, whether an impound exists at all. Scripts that want
    "this player's cars" should not have to know which of the two is running,
    and — more to the point — a script shipped under escrow cannot be edited
    when a server's schema turns out to differ. This file can.

    Everything returned is normalised:

      plate   trimmed
      model   spawn code (ESX keeps a hash; it is returned as a string)
      status  'garage' | 'impound' | 'outside'
      fuel    0-100
      engine  0-100        (both frameworks store 0-1000)
      body    0-100
      mods    { engine, brakes, transmission, suspension } as 0-4
      owner   display name when the players/users row still exists

    Writes take the same normalised words: `SetState(plate, 'impound')`, not
    `state = 2`.
]]

local Vehicles = {}

--------------------------------------------------------------------------------
-- Schema
--------------------------------------------------------------------------------

---@return 'qb'|'esx'|nil
local function framework()
    if GetResourceState('qbx_core') == 'started' then return 'qb' end
    if GetResourceState('qb-core') == 'started' then return 'qb' end
    if GetResourceState('es_extended') == 'started' then return 'esx' end
    return nil
end

---qb/qbox writes an integer for the state column; ESX only knows stored or not.
local QB_STATE = { [0] = 'outside', [1] = 'garage', [2] = 'impound' }
local STATE_TO_QB = { outside = 0, garage = 1, impound = 2 }

local SELECT_QB = [[
    SELECT v.id, v.plate, v.vehicle AS model, v.garage, v.state,
           v.fuel, v.engine, v.body, v.mods, v.citizenid,
           JSON_UNQUOTE(JSON_EXTRACT(p.charinfo, '$.firstname')) AS `first`,
           JSON_UNQUOTE(JSON_EXTRACT(p.charinfo, '$.lastname'))  AS `last`
    FROM `player_vehicles` v
    LEFT JOIN `players` p ON p.citizenid = v.citizenid
]]

local SELECT_ESX = [[
    SELECT o.plate, o.vehicle AS props, o.stored, o.parking AS garage, o.owner,
           u.firstname AS `first`, u.lastname AS `last`
    FROM `owned_vehicles` o
    LEFT JOIN `users` u ON u.identifier = o.owner
]]

local QUERIES = {
    qb = {
        list        = SELECT_QB .. ' ORDER BY v.id DESC LIMIT ?',
        byOwner     = SELECT_QB .. ' WHERE v.citizenid = ? ORDER BY v.id DESC LIMIT ?',
        one         = SELECT_QB .. ' WHERE v.plate = ? LIMIT 1',
        counts      = 'SELECT `state`, COUNT(*) AS `count` FROM `player_vehicles` GROUP BY `state`',
        setState    = 'UPDATE `player_vehicles` SET `state` = ? WHERE `plate` = ?',
        setPlate    = 'UPDATE `player_vehicles` SET `plate` = ? WHERE `plate` = ?',
        setOwner    = 'UPDATE `player_vehicles` SET `citizenid` = ?, `license` = ? WHERE `plate` = ?',
        remove      = 'DELETE FROM `player_vehicles` WHERE `plate` = ?',
        removeOwned = 'DELETE FROM `player_vehicles` WHERE `citizenid` = ?',
        repair      = 'UPDATE `player_vehicles` SET `engine` = 1000, `body` = 1000 WHERE `plate` = ?',
        refuel      = 'UPDATE `player_vehicles` SET `fuel` = 100 WHERE `plate` = ?',
        create      = [[
            INSERT INTO `player_vehicles`
                (`license`, `citizenid`, `vehicle`, `hash`, `mods`, `plate`, `garage`, `state`, `fuel`, `engine`, `body`)
            VALUES (?, ?, ?, ?, '{}', ?, ?, 1, 100, 1000, 1000)
        ]],
    },
    esx = {
        list        = SELECT_ESX .. ' ORDER BY o.plate LIMIT ?',
        byOwner     = SELECT_ESX .. ' WHERE o.owner = ? ORDER BY o.plate LIMIT ?',
        one         = SELECT_ESX .. ' WHERE o.plate = ? LIMIT 1',
        counts      = 'SELECT `stored`, COUNT(*) AS `count` FROM `owned_vehicles` GROUP BY `stored`',
        setState    = 'UPDATE `owned_vehicles` SET `stored` = ? WHERE `plate` = ?',
        setPlate    = 'UPDATE `owned_vehicles` SET `plate` = ? WHERE `plate` = ?',
        setOwner    = 'UPDATE `owned_vehicles` SET `owner` = ? WHERE `plate` = ?',
        remove      = 'DELETE FROM `owned_vehicles` WHERE `plate` = ?',
        removeOwned = 'DELETE FROM `owned_vehicles` WHERE `owner` = ?',
        -- ESX keeps condition inside the props blob rather than in columns, so
        -- there is nothing to reset here; the caller is told so by a nil.
        repair      = nil,
        refuel      = nil,
        create      = [[
            INSERT INTO `owned_vehicles` (`owner`, `plate`, `vehicle`, `type`, `stored`)
            VALUES (?, ?, ?, 'car', 1)
        ]],
    },
}

--------------------------------------------------------------------------------
-- Plumbing
--------------------------------------------------------------------------------

local function query(sql, params)
    if not sql then return nil end

    local ok, result = pcall(MySQL.Sync.fetchAll, sql, params or {})
    if not ok then
        print(('[codem-lib] Vehicles query failed: %s'):format(tostring(result)))
        return nil
    end
    return result
end

local function execute(sql, params)
    if not sql then return false end

    local ok, result = pcall(MySQL.Sync.execute, sql, params or {})
    if not ok then
        print(('[codem-lib] Vehicles update failed: %s'):format(tostring(result)))
        return false
    end
    return (tonumber(result) or 0) > 0
end

local function trim(value)
    if type(value) ~= 'string' then return '' end
    return (value:gsub('^%s*(.-)%s*$', '%1'))
end

---GTA numbers mod levels -1..3 (stock..maximum); callers count 0..4 so that
---"nothing installed" is zero rather than minus one.
local MOD_KEYS = {
    engine = 'modEngine',
    brakes = 'modBrakes',
    transmission = 'modTransmission',
    suspension = 'modSuspension',
}

local function modLevels(raw)
    local out = { engine = 0, brakes = 0, transmission = 0, suspension = 0 }
    if type(raw) ~= 'string' or raw == '' then return out end

    local ok, props = pcall(json.decode, raw)
    if not ok or type(props) ~= 'table' then return out end

    for key, column in pairs(MOD_KEYS) do
        local level = tonumber(props[column])
        if level then out[key] = math.max(0, math.min(4, level + 1)) end
    end
    return out
end

---A row whose owner was deleted keeps the vehicle but loses the name; that is
---returned as nil rather than as an invented owner.
local function ownerName(row)
    local name = ('%s %s'):format(row.first or '', row.last or '')
    name = name:gsub('^%s+', ''):gsub('%s+$', '')
    return name ~= '' and name or nil
end

---ESX stores the whole vehicle as a props blob; the model lives inside it as a
---hash. Returned as a string so callers have one type to handle.
local function esxModel(raw)
    if type(raw) ~= 'string' or raw == '' then return nil end

    local ok, props = pcall(json.decode, raw)
    if not ok or type(props) ~= 'table' then return nil end

    return props.model and tostring(props.model) or nil
end

local function normalise(row, fw)
    if type(row) ~= 'table' then return nil end

    if fw == 'esx' then
        return {
            plate = trim(row.plate),
            model = esxModel(row.props),
            owner = ownerName(row),
            ownerId = row.owner,
            garage = row.garage,
            status = (tonumber(row.stored) or 0) == 1 and 'garage' or 'outside',
            -- ESX keeps condition in the props blob and every server writes it
            -- differently; unknown is returned as nil, never as zero.
            fuel = nil,
            engine = nil,
            body = nil,
            mods = modLevels(nil),
        }
    end

    return {
        plate = trim(row.plate),
        model = row.model,
        owner = ownerName(row),
        ownerId = row.citizenid,
        garage = row.garage,
        status = QB_STATE[tonumber(row.state) or 0] or 'outside',
        fuel = math.floor(tonumber(row.fuel) or 0),
        engine = math.floor((tonumber(row.engine) or 0) / 10),
        body = math.floor((tonumber(row.body) or 0) / 10),
        mods = modLevels(row.mods),
    }
end

local function normaliseAll(rows, fw)
    local out = {}
    for _, row in ipairs(rows or {}) do
        local item = normalise(row, fw)
        if item then out[#out + 1] = item end
    end
    return out
end

--------------------------------------------------------------------------------
-- Reads
--------------------------------------------------------------------------------

---@param limit number|nil
---@return table[]|nil nil when no supported framework is running
function Vehicles.list(limit)
    local fw = framework()
    if not fw then return nil end

    local rows = query(QUERIES[fw].list, { math.floor(tonumber(limit) or 100) })
    return rows and normaliseAll(rows, fw) or nil
end

---@param owner string citizenid (qb) / identifier (esx)
---@param limit number|nil
---@return table[]|nil
function Vehicles.byOwner(owner, limit)
    local fw = framework()
    if not fw or type(owner) ~= 'string' or owner == '' then return nil end

    local rows = query(QUERIES[fw].byOwner, { owner, math.floor(tonumber(limit) or 100) })
    return rows and normaliseAll(rows, fw) or nil
end

---@param plate string
---@return table|nil
function Vehicles.get(plate)
    local fw = framework()
    if not fw or type(plate) ~= 'string' then return nil end

    local rows = query(QUERIES[fw].one, { trim(plate) })
    local row = rows and rows[1]
    return row and normalise(row, fw) or nil
end

---Counts come from their own query rather than from a listing: a list is
---limited and counting a limited list gives a number that is quietly wrong.
---@return { total: number, garage: number, impound: number, outside: number }|nil
function Vehicles.counts()
    local fw = framework()
    if not fw then return nil end

    local rows = query(QUERIES[fw].counts)
    if not rows then return nil end

    local out = { total = 0, garage = 0, impound = 0, outside = 0 }
    for _, row in ipairs(rows) do
        local count = tonumber(row.count) or 0
        local key
        if fw == 'esx' then
            key = (tonumber(row.stored) or 0) == 1 and 'garage' or 'outside'
        else
            key = QB_STATE[tonumber(row.state) or 0] or 'outside'
        end
        out[key] = out[key] + count
        out.total = out.total + count
    end
    return out
end

--------------------------------------------------------------------------------
-- Writes
--------------------------------------------------------------------------------

---@param plate string
---@param state 'garage'|'impound'|'outside'
---@return boolean
function Vehicles.setState(plate, state)
    local fw = framework()
    if not fw or type(plate) ~= 'string' then return false end

    if fw == 'esx' then
        -- ESX has no impound column of its own; marking such a car as stored
        -- would put it in a garage it is not in, so the write is refused.
        if state == 'impound' then return false end
        return execute(QUERIES.esx.setState, { state == 'garage' and 1 or 0, trim(plate) })
    end

    local value = STATE_TO_QB[state]
    if not value then return false end
    return execute(QUERIES.qb.setState, { value, trim(plate) })
end

---@param plate string current plate
---@param next_ string new plate
---@return boolean
function Vehicles.setPlate(plate, next_)
    local fw = framework()
    if not fw or type(plate) ~= 'string' or type(next_) ~= 'string' or next_ == '' then return false end

    return execute(QUERIES[fw].setPlate, { trim(next_), trim(plate) })
end

---@param plate string
---@param owner string citizenid (qb) / identifier (esx)
---@param license string|nil qb also stores the account license on the row
---@return boolean
function Vehicles.setOwner(plate, owner, license)
    local fw = framework()
    if not fw or type(plate) ~= 'string' or type(owner) ~= 'string' then return false end

    if fw == 'esx' then
        return execute(QUERIES.esx.setOwner, { owner, trim(plate) })
    end
    return execute(QUERIES.qb.setOwner, { owner, license or '', trim(plate) })
end

---@param plate string
---@return boolean
function Vehicles.remove(plate)
    local fw = framework()
    if not fw or type(plate) ~= 'string' then return false end

    return execute(QUERIES[fw].remove, { trim(plate) })
end

---@param owner string
---@return boolean
function Vehicles.removeByOwner(owner)
    local fw = framework()
    if not fw or type(owner) ~= 'string' or owner == '' then return false end

    return execute(QUERIES[fw].removeOwned, { owner })
end

---Condition columns back to full. ESX keeps condition inside the props blob,
---so it answers false — the caller should say "not supported" rather than
---report a repair that did not happen.
---@param plate string
---@return boolean
function Vehicles.repair(plate)
    local fw = framework()
    if not fw or type(plate) ~= 'string' then return false end

    return execute(QUERIES[fw].repair, { trim(plate) })
end

---@param plate string
---@return boolean
function Vehicles.refuel(plate)
    local fw = framework()
    if not fw or type(plate) ~= 'string' then return false end

    return execute(QUERIES[fw].refuel, { trim(plate) })
end

---Writes a vehicle into a player's garage.
---@param data { owner: string, license: string|nil, model: string, plate: string, garage: string|nil }
---@return boolean
function Vehicles.create(data)
    local fw = framework()
    if not fw or type(data) ~= 'table' then return false end

    local owner = type(data.owner) == 'string' and data.owner or nil
    local model = type(data.model) == 'string' and data.model:lower() or nil
    local plate = type(data.plate) == 'string' and trim(data.plate) or nil
    if not owner or not model or not plate or plate == '' then return false end

    if fw == 'esx' then
        return execute(QUERIES.esx.create, { owner, plate, json.encode({ model = GetHashKey(model) }) })
    end

    return execute(QUERIES.qb.create, {
        data.license or '',
        owner,
        model,
        GetHashKey(model),
        plate,
        data.garage or 'pillboxgarage',
    })
end

--------------------------------------------------------------------------------
-- World
--------------------------------------------------------------------------------

--[[
    Plate -> spawned entity.

    Built in one pass over every vehicle on the server: doing the walk per row
    turns a list of four hundred cars into a freeze. Plates are padded to eight
    characters in game and stored trimmed, so both sides are trimmed.
]]
---@return table<string, number>
function Vehicles.spawned()
    local map = {}
    local ok, all = pcall(GetAllVehicles)
    if not ok or type(all) ~= 'table' then return map end

    for _, vehicle in ipairs(all) do
        local plate = GetVehicleNumberPlateText(vehicle)
        if type(plate) == 'string' then map[trim(plate)] = vehicle end
    end
    return map
end

--------------------------------------------------------------------------------
-- Exports
--------------------------------------------------------------------------------

exports('GetVehicles', function(limit) return Vehicles.list(limit) end)
exports('GetOwnerVehicles', function(owner, limit) return Vehicles.byOwner(owner, limit) end)
exports('GetVehicle', function(plate) return Vehicles.get(plate) end)
exports('GetVehicleCounts', function() return Vehicles.counts() end)
exports('SetVehicleState', function(plate, state) return Vehicles.setState(plate, state) end)
exports('SetVehiclePlate', function(plate, next_) return Vehicles.setPlate(plate, next_) end)
exports('SetVehicleOwner', function(plate, owner, license) return Vehicles.setOwner(plate, owner, license) end)
exports('DeleteVehicleRow', function(plate) return Vehicles.remove(plate) end)
exports('DeleteOwnerVehicles', function(owner) return Vehicles.removeByOwner(owner) end)
exports('RepairVehicleRow', function(plate) return Vehicles.repair(plate) end)
exports('RefuelVehicleRow', function(plate) return Vehicles.refuel(plate) end)
exports('CreateVehicleRow', function(data) return Vehicles.create(data) end)
exports('GetSpawnedVehicles', function() return Vehicles.spawned() end)
