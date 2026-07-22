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

    if isQbox then
        local ok = exports.qbx_core:CreateJob(name, job, false)
        return ok ~= false
    end

    if QBCore and QBCore.Functions.AddJob then
        QBCore.Functions.AddJob(name, job)
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
---CreateUseableItem, not the ox_inventory client-event hook). `cb` gets src.
---@param name string
---@param cb fun(src: number)
function Framework.Server.CreateUseableItem(name, cb)
    if not name or not cb then return end
    if isQbox then
        exports.qbx_core:CreateUseableItem(name, function(src)
            cb(src)
        end)
    elseif QBCore then
        QBCore.Functions.CreateUseableItem(name, function(src)
            cb(src)
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
        out[#out + 1] = {
            cid   = row.citizenid,
            name  = okC and ('%s %s'):format(info.firstname or '', info.lastname or '') or row.citizenid,
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
            if pd.job and pd.job.name == job then
                local ci = pd.charinfo or {}
                online[pd.citizenid] = {
                    cid   = pd.citizenid,
                    name  = ('%s %s'):format(ci.firstname or '', ci.lastname or ''):gsub('%s+$', ''),
                    grade = pd.job.grade and (pd.job.grade.name or pd.job.grade.level) or 0,
                }
            else
                online[pd.citizenid] = false
            end
        end
    end

    local out, added = {}, {}
    for _, row in ipairs(dbJobEmployees(job)) do
        local live = online[row.cid]
        if live == nil then
            out[#out + 1] = row -- offline: DB is the truth
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
local function playerByCid(cid)
    if isQbox then
        return exports.qbx_core:GetPlayerByCitizenId(cid)
    end
    return QBCore.Functions.GetPlayerByCitizenId(cid)
end

---Offline job change through the core's own objects, never raw SQL.
---qb-core: offline player object supports Functions.SetJob + Save.
---Qbox: the offline object's Functions.SetJob resolves a source internally
---and errors for offline players - build the job table on PlayerData from
---the shared jobs data and persist with SaveOffline instead.
local function setOfflineJob(cid, name, grade)
    if isQbox then
        local okGet, offline = pcall(function() return exports.qbx_core:GetOfflinePlayer(cid) end)
        if not okGet or not offline or not offline.PlayerData then return false end

        local okJobs, jobs = pcall(function() return exports.qbx_core:GetJobs() end)
        local jobData = okJobs and jobs and jobs[name] or nil
        local grades = jobData and jobData.grades or {}
        local gradeData = grades[grade] or grades[tostring(grade)] or {}

        offline.PlayerData.job = {
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
        local okSave, err = pcall(function() exports.qbx_core:SaveOffline(offline.PlayerData) end)
        if not okSave then
            print(('[codem-lib] SetJobGrade: SaveOffline failed for %s: %s'):format(cid, tostring(err)))
        end
        return okSave
    end

    local offline = QBCore.Functions.GetOfflinePlayerByCitizenId(cid)
    if not offline then return false end
    offline.Functions.SetJob(name, grade)
    offline.Functions.Save()
    return true
end

---Apply a job change to an online OR offline player. Returns false when the
---citizenid does not exist at all.
local function setJobFor(cid, name, grade)
    local player = playerByCid(cid)
    if player then
        player.Functions.SetJob(name, grade)
        return true
    end
    return setOfflineJob(cid, name, grade)
end

---Set an employee's grade (online via the core, offline via the offline
---player object + Save).
---@param cid string
---@param job string
---@param grade number
---@return boolean
function Framework.Server.SetJobGrade(cid, job, grade)
    local ok = setJobFor(cid, job, tonumber(grade) or 0)
    if ok then employeeCache[job] = nil end
    return ok
end

---Fire an employee from a job (falls back to unemployed).
---@param cid string
---@param job string
---@return boolean
function Framework.Server.FireFromJob(cid, job)
    local ok = setJobFor(cid, 'unemployed', 0)
    if ok then employeeCache[job] = nil end
    return ok
end

--------------------------------------------------------------------------------
-- Permissions
--------------------------------------------------------------------------------

---True if the player holds any permission group in Config.AdminPermissions, or
---the 'command' ace (txAdmin / server console admins). Falls back to 'god' when
---no groups are configured.
---@param src number
---@return boolean
function Framework.Server.IsAdmin(src)
    if not src then return false end

    local perms = Config.AdminPermissions
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
