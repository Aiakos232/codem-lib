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
    SELECT v.plate, v.vehicle AS model, v.garage, v.state,
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
        list        = SELECT_QB .. ' ORDER BY {order} LIMIT ? OFFSET ?',
        byOwner     = SELECT_QB .. ' WHERE v.citizenid = ? ORDER BY {order} LIMIT ?',
        search      = SELECT_QB .. ' WHERE v.plate LIKE ? OR v.vehicle LIKE ? OR v.citizenid LIKE ? ORDER BY {order} LIMIT ? OFFSET ?',
        one         = SELECT_QB .. ' WHERE v.plate = ? LIMIT 1',
        counts      = 'SELECT `state`, COUNT(*) AS `count` FROM `player_vehicles` GROUP BY `state`',
        setState    = 'UPDATE `player_vehicles` SET `state` = ? WHERE `plate` = ?',
        setPlate    = 'UPDATE `player_vehicles` SET `plate` = ? WHERE `plate` = ?',
        setOwner    = 'UPDATE `player_vehicles` SET `citizenid` = ?, `license` = ? WHERE `plate` = ?',
        remove      = 'DELETE FROM `player_vehicles` WHERE `plate` = ?',
        removeOwned = 'DELETE FROM `player_vehicles` WHERE `citizenid` = ?',
        stored      = SELECT_QB .. ' WHERE v.citizenid = ? AND v.state = 1 ORDER BY {order}',
        storedOne   = SELECT_QB .. ' WHERE v.citizenid = ? AND v.plate = ? AND v.state = 1 LIMIT 1',
        repair      = 'UPDATE `player_vehicles` SET `engine` = 1000, `body` = 1000 WHERE `plate` = ?',
        refuel      = 'UPDATE `player_vehicles` SET `fuel` = 100 WHERE `plate` = ?',
        create      = [[
            INSERT INTO `player_vehicles`
                (`license`, `citizenid`, `vehicle`, `hash`, `mods`, `plate`, `garage`, `state`, `fuel`, `engine`, `body`)
            VALUES (?, ?, ?, ?, '{}', ?, ?, 1, 100, 1000, 1000)
        ]],
    },
    esx = {
        list        = SELECT_ESX .. ' ORDER BY o.plate LIMIT ? OFFSET ?',
        byOwner     = SELECT_ESX .. ' WHERE o.owner = ? ORDER BY o.plate LIMIT ?',
        search      = SELECT_ESX .. ' WHERE o.plate LIKE ? OR o.owner LIKE ? ORDER BY o.plate LIMIT ? OFFSET ?',
        one         = SELECT_ESX .. ' WHERE o.plate = ? LIMIT 1',
        counts      = 'SELECT `stored`, COUNT(*) AS `count` FROM `owned_vehicles` GROUP BY `stored`',
        setState    = 'UPDATE `owned_vehicles` SET `stored` = ? WHERE `plate` = ?',
        setPlate    = 'UPDATE `owned_vehicles` SET `plate` = ? WHERE `plate` = ?',
        setOwner    = 'UPDATE `owned_vehicles` SET `owner` = ? WHERE `plate` = ?',
        remove      = 'DELETE FROM `owned_vehicles` WHERE `plate` = ?',
        removeOwned = 'DELETE FROM `owned_vehicles` WHERE `owner` = ?',
        stored      = SELECT_ESX .. ' WHERE o.owner = ? AND o.stored = 1 ORDER BY o.plate',
        storedOne   = SELECT_ESX .. ' WHERE o.owner = ? AND o.plate = ? AND o.stored = 1 LIMIT 1',
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

local qbOrder

local function resolveOrder(sql)
    if not sql:find('{order}', 1, true) then return sql end
    if not qbOrder then
        local ok, rows = pcall(MySQL.Sync.fetchAll, [[
            SELECT 1 FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'player_vehicles' AND COLUMN_NAME = 'id'
            LIMIT 1
        ]], {})
        qbOrder = (ok and type(rows) == 'table' and rows[1]) and 'v.id DESC' or 'v.plate'
    end
    return (sql:gsub('{order}', qbOrder))
end

local function query(sql, params)
    if not sql then return nil end
    sql = resolveOrder(sql)

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
---@param offset number|nil rows to skip, for reading the list a page at a time
---@return table[]|nil nil when no supported framework is running
function Vehicles.list(limit, offset)
    local fw = framework()
    if not fw then return nil end

    local rows = query(QUERIES[fw].list, { math.floor(tonumber(limit) or 100), math.max(0, math.floor(tonumber(offset) or 0)) })
    return rows and normaliseAll(rows, fw) or nil
end

---Rows whose plate, model (qb) or owner id contains the text.
---@param text string
---@param limit number|nil
---@param offset number|nil rows to skip
---@return table[]|nil
function Vehicles.search(text, limit, offset)
    local fw = framework()
    if not fw or type(text) ~= 'string' or text == '' then return nil end

    local like = '%' .. text:gsub('[%%_\\]', '\\%0') .. '%'
    local max = math.floor(tonumber(limit) or 100)
    local skip = math.max(0, math.floor(tonumber(offset) or 0))
    local params = fw == 'esx' and { like, like, max, skip } or { like, like, like, max, skip }

    local rows = query(QUERIES[fw].search, params)
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

---The normalised row plus what a garage needs to put the car back on the
---road: the row id (qb only; ESX has none) and the props blob, decoded.
local function spawnable(row, fw)
    local item = normalise(row, fw)
    if not item then return nil end

    local raw = fw == 'esx' and row.props or row.mods
    local ok, props = pcall(json.decode, type(raw) == 'string' and raw ~= '' and raw or '{}')
    item.id = row.id
    item.props = (ok and type(props) == 'table') and props or {}
    return item
end

---Cars the owner has stored, ready to spawn.
---@param owner string citizenid (qb) / identifier (esx)
---@return table[]|nil
function Vehicles.stored(owner)
    local fw = framework()
    if not fw or type(owner) ~= 'string' or owner == '' then return nil end

    local rows = query(QUERIES[fw].stored, { owner })
    if not rows then return nil end

    local out = {}
    for _, row in ipairs(rows) do
        local item = spawnable(row, fw)
        if item then out[#out + 1] = item end
    end
    return out
end

---One stored car, only when it belongs to the owner and is still stored.
---@param owner string
---@param plate string
---@return table|nil
function Vehicles.storedOne(owner, plate)
    local fw = framework()
    if not fw or type(owner) ~= 'string' or type(plate) ~= 'string' then return nil end

    local rows = query(QUERIES[fw].storedOne, { owner, trim(plate) })
    local row = rows and rows[1]
    return row and spawnable(row, fw) or nil
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

--[[
    A new car has to land where the server's garage script looks for it, and
    the garage scripts disagree: most add their own columns to the framework
    table, several keep their garages in the database under ids no other
    server shares. So the row is written the framework's way first and then
    moved into a garage with whatever the running script reads:

      qb-garages, qbx_garages, okokGarage   garage + state = 1
      cd_garage                             in_garage, garage_id, garage_type
      jg-advancedgarages                    in_garage, impound, garage_id
      mGarage                               stored, type, garage / parking
      esx_garage                            stored = 1; no parking = any garage
      op-garages                            stored / state 0 means parked
      codem-garagesv2                       its own CreateVehicle export

    A garage id is taken from the script when it can name one, otherwise from
    the garage most cars on this server already stand in.
]]

---@param name string
---@return boolean
local function running(name)
    return GetResourceState(name) == 'started'
end

---@param tbl string
---@return table<string, boolean>
local function columnsOf(tbl)
    local rows = query([[
        SELECT `COLUMN_NAME` AS `name` FROM information_schema.COLUMNS
        WHERE `TABLE_SCHEMA` = DATABASE() AND `TABLE_NAME` = ?
    ]], { tbl }) or {}

    local set = {}
    for _, row in ipairs(rows) do set[tostring(row.name)] = true end
    return set
end

---@param tbl string
---@param column string  one of the fixed names used below, never caller input
---@return string|nil  the value most rows hold
local function mostUsed(tbl, column)
    local rows = query(([[
        SELECT `%s` AS `value` FROM `%s`
        WHERE `%s` IS NOT NULL AND `%s` <> '' AND `%s` <> 'OUT'
        GROUP BY `%s` ORDER BY COUNT(*) DESC LIMIT 1
    ]]):format(column, tbl, column, column, column, column))

    local value = rows and rows[1] and rows[1].value
    return value ~= nil and tostring(value) or nil
end

---@return string|nil
local function cdGarageId()
    local ok, id = pcall(function()
        return exports['cd_garage']:GetDefaultGarageIdForVehicleType('car')
    end)
    return ok and type(id) == 'string' and id ~= '' and id or nil
end

---@param fw 'qb'|'esx'
---@param tbl string
---@param columns table<string, boolean>
---@param asked string|nil  garage the caller named
---@return table<string, any>
local function garagePlacement(fw, tbl, columns, asked)
    local set = {}
    local mono = running('mGarage')
    local named = fw == 'qb' and 'garage' or 'parking'

    local anyGarage = fw == 'esx' and running('esx_garage') and not asked

    if columns[named] and not anyGarage then
        local garage = asked or mostUsed(tbl, named)
        if not garage and fw == 'qb' then
            garage = (mono and 'Pillbox Hill') or (running('okokGarage') and 'legion') or 'pillboxgarage'
        elseif not garage and mono then
            garage = 'Pillbox Hill'
        end
        if garage then set[named] = garage end
    end

    if columns.in_garage then set.in_garage = 1 end
    if columns.impound and running('jg-advancedgarages') then set.impound = 0 end

    if columns.garage_id then
        local id = (running('cd_garage') and cdGarageId()) or mostUsed(tbl, 'garage_id')
        if id then set.garage_id = id end
    end

    if columns.garage_type and running('cd_garage') then set.garage_type = 'car' end

    if mono then
        if columns.stored then set.stored = 1 end
        if columns.type then set.type = 'automobile' end
    end

    if running('vms_garagesv2') and columns.type then set.type = 'vehicle' end

    if running('op-garages') then
        local parked = fw == 'qb' and 'state' or 'stored'
        if columns[parked] then set[parked] = 0 end
    end

    return set
end

---@param tbl string
---@param plate string
---@param set table<string, any>
local function place(tbl, plate, set)
    local names, values = {}, {}
    for column, value in pairs(set) do
        names[#names + 1] = ('`%s` = ?'):format(column)
        values[#values + 1] = value
    end
    if #names == 0 then return end

    values[#values + 1] = plate
    execute(('UPDATE `%s` SET %s WHERE `plate` = ?'):format(tbl, table.concat(names, ', ')), values)
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

    if running('codem-garagesv2') then
        local ok, row = pcall(function()
            return exports['codem-garagesv2']:CreateVehicle(owner, model, plate, data.garage)
        end)
        if ok and row then return true end
    end

    local tbl = fw == 'esx' and 'owned_vehicles' or 'player_vehicles'
    local columns = columnsOf(tbl)
    local set = garagePlacement(fw, tbl, columns, data.garage)

    local created
    if fw == 'esx' then
        created = execute(QUERIES.esx.create, { owner, plate, json.encode({ model = GetHashKey(model) }) })
    else
        created = execute(QUERIES.qb.create, {
            data.license or '',
            owner,
            model,
            GetHashKey(model),
            plate,
            set.garage or data.garage or 'pillboxgarage',
        })
        set.garage = nil
    end
    if not created then return false end

    place(tbl, plate, set)
    return true
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

exports('GetVehicles', function(limit, offset) return Vehicles.list(limit, offset) end)
exports('SearchVehicles', function(text, limit, offset) return Vehicles.search(text, limit, offset) end)
exports('GetOwnerVehicles', function(owner, limit) return Vehicles.byOwner(owner, limit) end)
exports('GetVehicle', function(plate) return Vehicles.get(plate) end)
exports('GetStoredVehicles', function(owner) return Vehicles.stored(owner) end)
exports('GetStoredVehicle', function(owner, plate) return Vehicles.storedOne(owner, plate) end)
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
