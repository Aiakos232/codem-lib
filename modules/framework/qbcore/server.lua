--[[
    QBCore / Qbox Framework Integration - Server
    Exposes a framework-agnostic `Framework.Server` table used across the resource.
]]
-- Framework selection: LibConfig.Framework (codem-lib config) wins, then the
-- consumer's own Config.Framework, then auto-detection of the running core.
local FW = (type(LibConfig) == 'table' and LibConfig.Framework)
    or (type(Config) == 'table' and Config.Framework)
    or 'auto'
if FW == 'auto' then
    if GetResourceState('qbx_core') == 'started' then
        FW = 'qbox'
    elseif GetResourceState('qb-core') == 'started' then
        FW = 'qb'
    elseif GetResourceState('es_extended') == 'started' then
        FW = 'esx'
    end
end
if FW ~= 'qb' and FW ~= 'qbox' then return end

local isQbox = FW == 'qbox'
local QBCore = not isQbox and exports['qb-core']:GetCoreObject() or nil

Framework = Framework or {}
Framework.Server = Framework.Server or {}

-- Vehicle ownership table + column holding the saved vehicle properties.
Framework.Server.VehiclesTable = 'player_vehicles'
Framework.Server.VehPropsColumn = 'mods'

--------------------------------------------------------------------------------
-- Player object
--------------------------------------------------------------------------------

---@param src number
---@return table|nil
function Framework.Server.GetPlayer(src)
    if isQbox then
        return exports.qbx_core:GetPlayer(src)
    end
    return QBCore.Functions.GetPlayer(src)
end

---@param src number
---@return string|nil citizenid
function Framework.Server.GetIdentifier(src)
    local Player = Framework.Server.GetPlayer(src)
    if not Player then return nil end
    return Player.PlayerData and Player.PlayerData.citizenid or nil
end

---@param src number
---@return string character display name ("First Last"), falls back to the src.
function Framework.Server.GetName(src)
    local Player = Framework.Server.GetPlayer(src)
    local ci = Player and Player.PlayerData and Player.PlayerData.charinfo
    if ci and ci.firstname then
        return ("%s %s"):format(ci.firstname, ci.lastname or ""):gsub("%s+$", "")
    end
    return GetPlayerName(src) or ("Player %d"):format(src)
end

---@param src number
---@return table|nil { name, label, grade, onduty }
function Framework.Server.GetPlayerJob(src)
    local Player = Framework.Server.GetPlayer(src)
    if not Player or not Player.PlayerData or not Player.PlayerData.job then return nil end
    local job = Player.PlayerData.job
    return {
        name = job.name,
        label = job.label,
        grade = job.grade and job.grade.level or 0,
        onduty = job.onduty or false,
        isboss = job.isboss == true,
    }
end

--------------------------------------------------------------------------------
-- Character sheet
--------------------------------------------------------------------------------

---Identity fields the framework stores on the character.
---@param src number
---@return table|nil { firstname, lastname, birthdate, gender, nationality, phone, account, citizenid }
function Framework.Server.GetCharInfo(src)
    local Player = Framework.Server.GetPlayer(src)
    local data = Player and Player.PlayerData
    local info = data and data.charinfo
    if not info then return nil end

    return {
        firstname = info.firstname,
        lastname = info.lastname,
        birthdate = info.birthdate,
        -- QB stores gender as 0/1; normalised here so consumers never branch on it.
        gender = info.gender == 1 and 'female' or 'male',
        nationality = info.nationality,
        phone = info.phone,
        account = info.account,
        citizenid = data.citizenid,
    }
end

---@param src number
---@return table|nil { name, label, grade, gradeLabel, isboss } — nil when gangless
function Framework.Server.GetGang(src)
    local Player = Framework.Server.GetPlayer(src)
    local gang = Player and Player.PlayerData and Player.PlayerData.gang
    if not gang or not gang.name or gang.name == 'none' then return nil end

    return {
        name = gang.name,
        label = gang.label,
        grade = gang.grade and gang.grade.level or 0,
        gradeLabel = gang.grade and gang.grade.name or nil,
        isboss = gang.isboss == true,
    }
end

---@param src number
---@param patch table
---@return boolean
function Framework.Server.SetCharInfo(src, patch)
    local Player = Framework.Server.GetPlayer(src)
    if not Player or type(patch) ~= 'table' then return false end

    local info = Player.PlayerData.charinfo
    if type(info) ~= 'table' then return false end

    -- Yalnizca kunye alanlari, degerleri framework'un bekledigi bicimde.
    local changes = {}
    for key, value in pairs(patch) do
        if key == 'gender' then
            changes.gender = (value == 'female' or value == 1) and 1 or 0
        elseif key == 'firstname' or key == 'lastname' or key == 'birthdate'
            or key == 'nationality' or key == 'phone' then
            changes[key] = value
        end
    end

    if next(changes) == nil then return false end

    --[[
        Qbox'in export'u tek alan aliyor: SetCharInfo(kaynak, alan, deger) ve
        ilk satirinda `type(charInfo) ~= 'string'` ise donuyor. Buraya tablo
        verilince sessizce hicbir sey yapmiyor, ustelik hata da dondurmuyordu:
        panel "kaydedildi" diyor, deger yerinde kaliyordu. Alan alan gonderiliyor.
    ]]
    if isQbox then
        for key, value in pairs(changes) do
            exports.qbx_core:SetCharInfo(src, key, value)
        end
        return true
    end

    local next_ = {}
    for key, value in pairs(info) do next_[key] = value end
    for key, value in pairs(changes) do next_[key] = value end

    if Player.Functions.SetCharInfo then
        Player.Functions.SetCharInfo(next_)
    else
        Player.PlayerData.charinfo = next_
        if Player.Functions.Save then Player.Functions.Save() end
    end
    return true
end

---Sets the gang. `name = 'none'` clears it.
---@param src number
---@param name string
---@param grade number
---@return boolean
function Framework.Server.SetGang(src, name, grade)
    local Player = Framework.Server.GetPlayer(src)
    if not Player or not Player.Functions or not Player.Functions.SetGang then return false end
    return Player.Functions.SetGang(name, tonumber(grade) or 0) and true or false
end

---Character metadata (hunger, thirst, stress, ...). Returned verbatim: servers
---add their own keys and a whitelist here would silently drop them.
---@param src number
---@return table
function Framework.Server.GetMetadata(src)
    local Player = Framework.Server.GetPlayer(src)
    local meta = Player and Player.PlayerData and Player.PlayerData.metadata
    if type(meta) ~= 'table' then return {} end

    local out = {}
    for key, value in pairs(meta) do
        -- Only scalars: nested tables here are inventory-shaped blobs, not stats.
        local kind = type(value)
        if kind == 'number' or kind == 'boolean' or kind == 'string' then
            out[key] = value
        end
    end
    return out
end

---Writes a single metadata key (hunger, thirst, stress, ...).
---@param src number
---@param key string
---@param value any
---@return boolean
function Framework.Server.SetMetadata(src, key, value)
    if not key then return false end

    -- Qbox exposes this as a resource export; the player-object variant is
    -- spelled SetMetaData there and marked deprecated.
    if isQbox then
        exports.qbx_core:SetMetadata(src, key, value)
        return true
    end

    local Player = Framework.Server.GetPlayer(src)
    if not Player or not Player.Functions or not Player.Functions.SetMetaData then return false end

    Player.Functions.SetMetaData(key, value)
    return true
end

--------------------------------------------------------------------------------
-- Jobs
--------------------------------------------------------------------------------

---@return table<string, table> job name -> definition
function Framework.Server.GetJobs()
    if isQbox then
        return exports.qbx_core:GetJobs() or {}
    end
    return (QBCore and QBCore.Shared.Jobs) or {}
end

---Registers a job in the framework's live table.
---
---Memory only, on purpose: Qbox can also rewrite `qbx_core/shared/jobs.lua`,
---but its writer emits a fixed field list and silently drops `type` (the
---'leo' / 'ems' marker several jobs rely on). The caller is expected to keep
---its own persistent copy and re-register on boot.
---@param name string
---@param job table
---@return boolean
function Framework.Server.CreateJob(name, job)
    if type(name) ~= 'string' or type(job) ~= 'table' then return false end

    -- Grade keys per framework: qb-core keeps `Shared.Jobs[x].grades['0']`
    -- (string), qbox keeps `grades[0]` (number). A caller reloading from JSON
    -- arrives with strings; passing those to qbox breaks character load —
    -- CheckPlayerData indexes `grades[0]` and finds nothing.
    local grades = {}
    for id, grade in pairs(job.grades or {}) do
        local key = isQbox and tonumber(id) or tostring(tonumber(id) or id)
        if key ~= nil then grades[key] = grade end
    end
    local payload = {}
    for k, v in pairs(job) do payload[k] = v end
    payload.grades = grades

    if isQbox then
        local ok = exports.qbx_core:CreateJob(name, payload, false)
        return ok ~= false
    end

    if QBCore and QBCore.Functions.AddJob then
        QBCore.Functions.AddJob(name, payload)
        return true
    end
    return false
end

---@param name string
---@return boolean
function Framework.Server.RemoveJob(name)
    if type(name) ~= 'string' then return false end

    if isQbox then
        local ok = exports.qbx_core:RemoveJob(name, false)
        return ok ~= false
    end

    if QBCore and QBCore.Functions.RemoveJob then
        QBCore.Functions.RemoveJob(name)
        return true
    end
    return false
end

--------------------------------------------------------------------------------
-- Gangs (catalog)
--------------------------------------------------------------------------------

---Every gang the framework knows. Same shape as GetJobs: name -> { label, grades }.
---@return table<string, table>
function Framework.Server.GetGangs()
    if isQbox then return exports.qbx_core:GetGangs() or {} end
    return QBCore and QBCore.Shared and QBCore.Shared.Gangs or {}
end

---Registers a gang so `SetGang` accepts it. Memory only, like CreateJob: the
---caller keeps its own copy and re-applies on boot.
---@param name string
---@param gang { label: string, grades: table<number, { name: string, isboss?: boolean }> }
---@return boolean
function Framework.Server.CreateGang(name, gang)
    if type(name) ~= 'string' or type(gang) ~= 'table' then return false end

    -- qb wants grades keyed by string number; qbox by number. Both accept
    -- `isboss` on the grade.
    local grades = {}
    for id, grade in pairs(gang.grades or {}) do
        grades[isQbox and tonumber(id) or tostring(id)] = { name = grade.name, isboss = grade.isboss == true }
    end
    local payload = { label = gang.label or name, grades = grades }

    if isQbox then
        local ok = exports.qbx_core:CreateGang(name, payload, false)
        return ok ~= false
    end
    if QBCore and QBCore.Functions.AddGang then
        return QBCore.Functions.AddGang(name, payload) ~= false
    end
    return false
end

---@param name string
---@return boolean
function Framework.Server.RemoveGang(name)
    if type(name) ~= 'string' then return false end
    if isQbox then
        local ok = exports.qbx_core:RemoveGang(name, false)
        return ok ~= false
    end
    if QBCore and QBCore.Functions.RemoveGang then
        QBCore.Functions.RemoveGang(name)
        return true
    end
    return false
end

--------------------------------------------------------------------------------
-- Character loaded
--------------------------------------------------------------------------------

--[[
    One event for "the character is in the game", whichever framework fires it.
    Consumers that need to apply per-character state (a panel-owned faction, a
    stored flag) listen to `codem-lib:playerLoaded` and never learn the
    framework's own event name.
]]
-- Qbox keeps the QBCore event name for compatibility.
AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
    local src = type(player) == 'table' and player.PlayerData and player.PlayerData.source or source
    if src then TriggerEvent('codem-lib:playerLoaded', src) end
end)

--------------------------------------------------------------------------------
-- Money
--------------------------------------------------------------------------------

---Every money account the character holds, name -> amount. Not limited to
---cash/bank: a server that adds `crypto` or `coins` shows up without a change here.
---@param src number
---@return table<string, number>
function Framework.Server.GetAccounts(src)
    local Player = Framework.Server.GetPlayer(src)
    local money = Player and Player.PlayerData and Player.PlayerData.money
    if type(money) ~= 'table' then return {} end

    local out = {}
    for name, amount in pairs(money) do
        out[name] = tonumber(amount) or 0
    end
    return out
end

---@param src number
---@param account string 'cash' | 'bank'
---@return number
function Framework.Server.GetBalance(src, account)
    local Player = Framework.Server.GetPlayer(src)
    if not Player then return 0 end
    return (Player.PlayerData.money and Player.PlayerData.money[account]) or 0
end

---@param src number
---@param amount number
---@param account string
---@return boolean
function Framework.Server.RemoveMoney(src, amount, account)
    local Player = Framework.Server.GetPlayer(src)
    if not Player then return false end
    -- This file runs inside the consumer resource's context, so the money
    -- reason is whatever script pulled in the lib - not a hardcoded name.
    return Player.Functions.RemoveMoney(account, amount, GetCurrentResourceName()) and true or false
end

---@param src number
---@param amount number
---@param account string
---@return boolean
function Framework.Server.AddMoney(src, amount, account)
    local Player = Framework.Server.GetPlayer(src)
    if not Player then return false end
    return Player.Functions.AddMoney(account, amount, GetCurrentResourceName()) and true or false
end

--------------------------------------------------------------------------------
-- Items
--------------------------------------------------------------------------------

-- No item functions here on purpose: item operations belong to the inventory
-- module - use the CodemLib.Inventory.* API (Count/Add/Remove/...) instead.

---Register a server-side "use" handler for an inventory item (framework's
---CreateUseableItem, not the ox_inventory client-event hook). `cb` gets src and
---the used item (slot/name/amount + `info`/`metadata` when the inventory keeps
---per-item metadata). The second argument is optional for callers that only
---care about who used it.
---@param name string
---@param cb fun(src: number, item?: table)
function Framework.Server.CreateUseableItem(name, cb)
    if not name or not cb then return end
    if isQbox then
        exports.qbx_core:CreateUseableItem(name, function(src, item)
            cb(src, item)
        end)
    elseif QBCore then
        QBCore.Functions.CreateUseableItem(name, function(src, item)
            cb(src, item)
        end)
    end
end

--------------------------------------------------------------------------------
-- Vehicles
--------------------------------------------------------------------------------

---Vehicle base value from the core's own shared vehicle list - the same table
---the vehicle shop prices from (qbx_core/shared/vehicles.lua on Qbox,
---QBCore.Shared.Vehicles on QB). No SQL, no separate price table to maintain.
---@param model string|number Spawn/archetype name (any case) or model hash
---@return number price 0 when the model isn't listed
function Framework.Server.GetVehicleValue(model)
    if not model then return 0 end
    if isQbox then
        local veh
        if type(model) == 'number' then
            veh = exports.qbx_core:GetVehiclesByHash(model)
        else
            veh = exports.qbx_core:GetVehiclesByName(model:lower())
        end
        return (veh and veh.price) or 0
    end
    if not QBCore then return 0 end
    local list = QBCore.Shared.Vehicles
    if not list then return 0 end
    if type(model) == 'number' then
        -- QB keys by spawn name only, so find the matching hash.
        for _, veh in pairs(list) do
            if veh.hash == model then return veh.price or 0 end
        end
        return 0
    end
    local veh = list[model:lower()]
    return (veh and veh.price) or 0
end

--------------------------------------------------------------------------------
-- Notifications
--------------------------------------------------------------------------------

---Routed through the lib's notify module so LibConfig.Notify picks the look.
---@param src number
---@param message string
---@param nType? string
function Framework.Server.Notify(src, message, nType)
    exports['codem-lib']:Notify(src, message, nType)
end

--------------------------------------------------------------------------------
-- Job employees (personnel management)
--------------------------------------------------------------------------------

---Awaitable DB query that works whether or not the consumer loaded the
---oxmysql Lua wrapper (@oxmysql/lib/MySQL.lua).
local function dbQuery(sql, params)
    if MySQL and MySQL.query and MySQL.query.await then
        return MySQL.query.await(sql, params)
    end
    local p = promise.new()
    exports.oxmysql:query(sql, params, function(res) p:resolve(res) end)
    return Citizen.Await(p)
end

-- The players table has no index on the JSON job column, so every lookup is a
-- full scan. Two mitigations for big tables: a LIKE prefilter so MySQL only
-- JSON-parses candidate rows, and a short TTL cache so repeated panel opens
-- don't rescan. SetJobGrade/FireFromJob invalidate the cache.
local employeeCache = {} -- [job] = { at = ms, rows = table }
local EMPLOYEE_CACHE_MS = 30000

---@param job string
function Framework.Server.ClearJobEmployeesCache(job)
    employeeCache[job] = nil
end

---Offline snapshot from the DB. The players table only updates on the save
---cycle (logout/interval), so this LAGS for anyone online - the live pass in
---GetJobEmployees overrides it. Cached per job (TTL) against rescans.
local function dbJobEmployees(job)
    local hit = employeeCache[job]
    if hit and (GetGameTimer() - hit.at) < EMPLOYEE_CACHE_MS then return hit.rows end

    -- LIKE narrows the scan cheaply (plain string match, catches the JSON
    -- key); JSON_EXTRACT then confirms exactly so 'mechanic' never matches
    -- 'mechanic2'. Only candidate rows pay the JSON parse.
    local rows = dbQuery(
        'SELECT citizenid, charinfo, job FROM players WHERE job LIKE ? AND JSON_EXTRACT(job, "$.name") = ?',
        { '%"name":"' .. job .. '"%', job }
    ) or {}

    local out = {}
    for _, row in ipairs(rows) do
        local okC, info  = pcall(json.decode, row.charinfo)
        local okJ, jdata = pcall(json.decode, row.job)
        out[#out + 1]    = {
            -- tostring: numeric citizenid columns come back as Lua numbers,
            -- while the live PlayerData may hold a string - the dedup in
            -- GetJobEmployees needs both sides on one key type.
            cid   = tostring(row.citizenid),
            name  = okC and ('%s %s'):format(info.firstname or '', info.lastname or '') or tostring(row.citizenid),
            grade = okJ and (jdata.grade and (jdata.grade.name or jdata.grade.level)) or 0,
        }
    end

    employeeCache[job] = { at = GetGameTimer(), rows = out }
    return out
end

local function onlinePlayers()
    if isQbox then
        return exports.qbx_core:GetQBPlayers()
    end
    return QBCore.Functions.GetQBPlayers()
end

---Everyone employed at `job`, online or offline. Online players are read from
---memory every call (cheap) and their CURRENT job overrides the stale DB row:
---someone hired seconds ago shows up, someone who just switched jobs drops.
---@param job string
---@return { cid: string, name: string, grade: string|number }[]
function Framework.Server.GetJobEmployees(job)
    -- Live pass: [cid] = entry when on this job, false when online with a
    -- different job (their DB row may still say this job - must be dropped).
    local online = {}
    for _, player in pairs(onlinePlayers() or {}) do
        local pd = player and player.PlayerData
        if pd and pd.citizenid then
            -- tostring matches the DB pass: on servers with numeric citizenids
            -- the two sides otherwise key as number vs string and the dedup
            -- misses, listing every online employee twice.
            local cid = tostring(pd.citizenid)
            if pd.job and pd.job.name == job then
                local ci = pd.charinfo or {}
                online[cid] = {
                    cid   = cid,
                    name  = ('%s %s'):format(ci.firstname or '', ci.lastname or ''):gsub('%s+$', ''),
                    grade = pd.job.grade and (pd.job.grade.name or pd.job.grade.level) or 0,
                }
            else
                online[cid] = false
            end
        end
    end

    local out, added = {}, {}
    for _, row in ipairs(dbJobEmployees(job)) do
        local live = online[row.cid]
        if live == nil then
            out[#out + 1] = row  -- offline: DB is the truth
        elseif live then
            out[#out + 1] = live -- online, same job: live data wins
        end
        -- live == false: online but no longer on this job - drop the row.
        added[row.cid] = true
    end
    for cid, live in pairs(online) do
        if live and not added[cid] then out[#out + 1] = live end
    end
    return out
end

---Grade list for a job from the shared jobs data, sorted by level.
---@param job string
---@return { level: number, label: string }[]
function Framework.Server.GetJobGrades(job)
    local jobs
    if isQbox then
        local ok, j = pcall(function() return exports.qbx_core:GetJobs() end)
        jobs = ok and j or {}
    else
        jobs = QBCore.Shared.Jobs or {}
    end
    local data = jobs[job]
    local out = {}
    for k, g in pairs(data and data.grades or {}) do
        out[#out + 1] = { level = tonumber(k) or 0, label = g.name or g.label or tostring(k) }
    end
    table.sort(out, function(a, b) return a.level < b.level end)
    return out
end

---Online player object by citizenid, or nil when offline.
---Retries with the numeric form: GetJobEmployees hands out string cids, but a
---core with numeric citizenids compares them as numbers.
local function playerByCid(cid)
    local function get(c)
        if isQbox then
            return exports.qbx_core:GetPlayerByCitizenId(c)
        end
        return QBCore.Functions.GetPlayerByCitizenId(c)
    end
    local player = get(cid)
    if not player and tonumber(cid) then
        player = get(tonumber(cid))
    end
    return player
end

---Full job table for the players.job column, built from the shared jobs
---data so the player loads with a valid grade structure next time.
local function buildJobObject(name, grade)
    local jobs
    if isQbox then
        local ok, j = pcall(function() return exports.qbx_core:GetJobs() end)
        jobs = ok and j or {}
    else
        jobs = QBCore.Shared.Jobs or {}
    end
    local jobData = jobs[name]
    local grades = jobData and jobData.grades or {}
    local gradeData = grades[grade] or grades[tostring(grade)] or {}
    return {
        name = name,
        type = jobData and jobData.type or nil,
        label = jobData and jobData.label or name,
        isboss = gradeData.isboss == true,
        onduty = (jobData and jobData.defaultDuty) == true,
        payment = gradeData.payment or 0,
        grade = {
            name = gradeData.name or tostring(grade),
            level = grade,
        },
    }
end

---Last-resort offline job change: write the players.job JSON column
---directly. Used when the core exposes no working offline-player API
---(same approach as codem-phone's jobby app).
local function setOfflineJobSql(cid, name, grade)
    local encoded = json.encode(buildJobObject(name, grade))
    local affected
    if MySQL and MySQL.update and MySQL.update.await then
        affected = MySQL.update.await('UPDATE players SET job = ? WHERE citizenid = ?', { encoded, cid })
    else
        local p = promise.new()
        exports.oxmysql:update('UPDATE players SET job = ? WHERE citizenid = ?', { encoded, cid },
            function(n) p:resolve(n) end)
        affected = Citizen.Await(p)
    end
    return (tonumber(affected) or 0) > 0
end

---Offline job change through the core's own objects when available.
---qb-core: offline player object supports Functions.SetJob + Save.
---Qbox: the offline object's Functions.SetJob resolves a source internally
---and errors for offline players - build the job table on PlayerData from
---the shared jobs data and persist with SaveOffline instead.
---Either path missing or failing falls back to a direct SQL update.
local function setOfflineJob(cid, name, grade)
    if isQbox then
        local okGet, offline = pcall(function() return exports.qbx_core:GetOfflinePlayer(cid) end)
        if okGet and offline and offline.PlayerData then
            offline.PlayerData.job = buildJobObject(name, grade)
            local okSave, err = pcall(function() exports.qbx_core:SaveOffline(offline.PlayerData) end)
            if okSave then return true end
            print(('[codem-lib] setOfflineJob: SaveOffline failed for %s: %s'):format(cid, tostring(err)))
        end
        return setOfflineJobSql(cid, name, grade)
    end

    local okGet, offline = pcall(function()
        return QBCore.Functions.GetOfflinePlayerByCitizenId(cid)
    end)
    if okGet and offline then
        local okSet, err = pcall(function()
            offline.Functions.SetJob(name, grade)
            offline.Functions.Save()
        end)
        if okSet then return true end
        print(('[codem-lib] setOfflineJob: save failed for %s: %s'):format(cid, tostring(err)))
    elseif not okGet then
        print(('[codem-lib] setOfflineJob: offline lookup failed for %s: %s'):format(cid, tostring(offline)))
    end
    return setOfflineJobSql(cid, name, grade)
end

---Apply a job change to an online OR offline player. Returns false when the
---citizenid does not exist at all.
---@return boolean success
---@return table|nil errorResult the framework's own reason, when it gave one
local function setJobFor(cid, name, grade)
    local player = playerByCid(cid)
    if player then
        local ok, err = player.Functions.SetJob(name, grade)
        return ok == true, err
    end
    return setOfflineJob(cid, name, grade), nil
end

---Set an employee's grade (online via the core, offline via the offline
---player object + Save).
---@param cid string
---@param job string
---@param grade number
---@return boolean success
---@return table|nil errorResult `{ code, message }` when the framework refused
function Framework.Server.SetJobGrade(cid, job, grade)
    local ok, err = setJobFor(cid, job, tonumber(grade) or 0)
    if ok then employeeCache[job] = nil end
    return ok, err
end

---Fire an employee from a job (falls back to unemployed).
---Some servers define unemployed grades starting at 1 instead of 0, so the
---lowest grade actually defined in the shared jobs data is used; 0 only when
---the job has no grade list at all.
---@param cid string
---@param job string
---@return boolean
function Framework.Server.FireFromJob(cid, job)
    local grades = Framework.Server.GetJobGrades('unemployed')
    local lowest = grades[1] and grades[1].level or 0
    local ok = setJobFor(cid, 'unemployed', lowest)
    if ok then employeeCache[job] = nil end
    return ok
end

---Removes everyone from a job. Call this before deleting the job itself.
---@param name string
---@return boolean
function Framework.Server.ReleaseJobMembers(name)
    if type(name) ~= 'string' or name == '' or name == 'unemployed' then return false end

    employeeCache[name] = nil

    if isQbox then
        for _, player in pairs(onlinePlayers() or {}) do
            local data = player and player.PlayerData
            if data and data.jobs and data.jobs[name] ~= nil then
                pcall(function() exports.qbx_core:RemovePlayerFromJob(data.citizenid, name) end)
            end
        end

        local ok = pcall(dbQuery, 'DELETE FROM `player_groups` WHERE `type` = ? AND `group` = ?', { 'job', name })
        return ok
    end

    if not QBCore then return false end

    for _, player in pairs(onlinePlayers() or {}) do
        local job = player and player.PlayerData and player.PlayerData.job
        if type(job) == 'table' and job.name == name then
            player.Functions.SetJob('unemployed', 0)
        end
    end
    return true
end

---Job memberships pointing at a job the framework no longer knows.
---@return { cid: string, job: string, grade: number }[]
function Framework.Server.GetOrphanJobMembers()
    if not isQbox then return {} end

    local known = Framework.Server.GetJobs() or {}
    local rows = dbQuery('SELECT `citizenid`, `group`, `grade` FROM `player_groups` WHERE `type` = ?', { 'job' })

    local out = {}
    for _, row in ipairs(rows or {}) do
        if row.group and not known[row.group] then
            out[#out + 1] = { cid = row.citizenid, job = row.group, grade = tonumber(row.grade) or 0 }
        end
    end
    return out
end

--------------------------------------------------------------------------------
-- Permissions
--------------------------------------------------------------------------------

---True if the player holds any permission group in LibConfig.AdminPermissions,
---or the 'command' ace (txAdmin / server console admins). Falls back to 'god'
---when no groups are configured.
---@param src number
---@return boolean
function Framework.Server.IsAdmin(src)
    if not src then return false end

    local perms = LibConfig and LibConfig.AdminPermissions
    if type(perms) ~= 'table' or next(perms) == nil then
        perms = { ['god'] = true }
    end

    if IsPlayerAceAllowed(src, 'command') then return true end

    for perm, enabled in pairs(perms) do
        if enabled then
            if isQbox then
                if exports.qbx_core:HasPermission(src, perm) then return true end
            elseif QBCore and QBCore.Functions.HasPermission(src, perm) then
                return true
            end
        end
    end

    return false
end
