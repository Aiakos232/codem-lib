--[[
    ESX Framework Integration - Server
    Mirrors the `Framework.Server` API. Only active when the resolved framework is 'esx'.
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
if FW ~= 'esx' then return end

local ESX = exports['es_extended']:getSharedObject()

Framework = Framework or {}
Framework.Server = Framework.Server or {}

-- Vehicle ownership table + column holding the saved vehicle properties.
Framework.Server.VehiclesTable = 'owned_vehicles'
Framework.Server.VehPropsColumn = 'vehicle'

function Framework.Server.GetPlayer(src)
    return ESX.GetPlayerFromId(src)
end

function Framework.Server.GetIdentifier(src)
    local xPlayer = Framework.Server.GetPlayer(src)
    return xPlayer and xPlayer.identifier or nil
end

function Framework.Server.GetName(src)
    local xPlayer = Framework.Server.GetPlayer(src)
    if xPlayer and xPlayer.getName then return xPlayer.getName() end
    return GetPlayerName(src) or ("Player %d"):format(src)
end

function Framework.Server.GetPlayerJob(src)
    local xPlayer = Framework.Server.GetPlayer(src)
    if not xPlayer or not xPlayer.job then return nil end
    return {
        name = xPlayer.job.name,
        label = xPlayer.job.label,
        grade = xPlayer.job.grade,
        onduty = true,
        -- ESX has no isboss flag; the 'boss' grade name is the convention.
        isboss = xPlayer.job.grade_name == 'boss',
    }
end

function Framework.Server.GetBalance(src, account)
    local xPlayer = Framework.Server.GetPlayer(src)
    if not xPlayer then return 0 end
    local map = { cash = 'money', bank = 'bank' }
    local acc = xPlayer.getAccount(map[account] or account)
    return acc and acc.money or 0
end

---Identity fields. ESX keeps these in the `users` row and mirrors part of it on
---the player object; anything the server did not set comes back nil rather than
---being invented.
---@param src number
---@return table|nil
function Framework.Server.GetCharInfo(src)
    local xPlayer = Framework.Server.GetPlayer(src)
    if not xPlayer then return nil end

    local get = xPlayer.get
    local function field(name)
        if not get then return nil end
        local ok, value = pcall(get, name)
        return ok and value or nil
    end

    local sex = field('sex')
    return {
        firstname = field('firstName'),
        lastname = field('lastName'),
        birthdate = field('dateofbirth'),
        gender = (sex == 'f' or sex == 'F' or sex == 1) and 'female' or 'male',
        nationality = nil,
        phone = field('phoneNumber'),
        account = nil,
        citizenid = xPlayer.identifier,
    }
end

---ESX has no gang concept; gang UI stays empty rather than showing job data.
---@return nil
function Framework.Server.GetGang()
    return nil
end

---Status values (hunger, thirst) live in esx_status, which is optional.
---@param src number
---@return table
function Framework.Server.GetMetadata(src)
    local xPlayer = Framework.Server.GetPlayer(src)
    if not xPlayer then return {} end

    local out = {}
    if GetResourceState('esx_status') == 'started' then
        -- esx_status is client-authoritative; the server copy is only what the
        -- last tick reported, so this is a best-effort read.
        local ok, statuses = pcall(function()
            return xPlayer.get and xPlayer.get('status') or nil
        end)
        if ok and type(statuses) == 'table' then
            for _, status in pairs(statuses) do
                if status.name and status.val then
                    out[status.name] = math.floor(status.val / 10000)
                end
            end
        end
    end
    return out
end

---ESX keeps hunger/thirst in esx_status, which is driven from the client; the
---server can only ask it to change, and only if that resource is running.
---@param src number
---@param key string
---@param value number 0-100
---@return boolean
function Framework.Server.SetMetadata(src, key, value)
    if GetResourceState('esx_status') ~= 'started' then return false end
    if type(value) ~= 'number' then return false end

    TriggerClientEvent('esx_status:set', src, key, math.floor(value * 10000))
    return true
end

--------------------------------------------------------------------------------
-- Jobs
--------------------------------------------------------------------------------

---@return table<string, table>
function Framework.Server.GetJobs()
    return (ESX.GetJobs and ESX.GetJobs()) or {}
end

---ESX keeps jobs in the `jobs` / `job_grades` tables, so registering one is a
---database write the framework owns. Only newer builds expose it; older ones
---return false rather than half-registering a job that vanishes on restart.
---@param name string
---@param job table { label, grades }
---@return boolean
function Framework.Server.CreateJob(name, job)
    if type(name) ~= 'string' or type(job) ~= 'table' then return false end
    if not ESX.CreateJob then return false end

    local grades = {}
    for gradeId, grade in pairs(job.grades or {}) do
        grades[#grades + 1] = {
            grade = tonumber(gradeId) or 0,
            name = grade.name,
            label = grade.label or grade.name,
            salary = grade.payment or grade.salary or 0,
        }
    end

    ESX.CreateJob(name, job.label or name, grades)
    return true
end

---@return boolean
function Framework.Server.RemoveJob()
    -- ESX has no removal API; deleting the rows behind its back would leave
    -- every player holding that job in an unknown state.
    return false
end

---@param src number
---@return table<string, number>
function Framework.Server.GetAccounts(src)
    local xPlayer = Framework.Server.GetPlayer(src)
    if not xPlayer or not xPlayer.getAccounts then return {} end

    local out = {}
    for _, account in pairs(xPlayer.getAccounts() or {}) do
        if account.name then
            -- Renamed so consumers see the same key on both frameworks.
            local key = account.name == 'money' and 'cash' or account.name
            out[key] = account.money or 0
        end
    end
    return out
end

function Framework.Server.RemoveMoney(src, amount, account)
    local xPlayer = Framework.Server.GetPlayer(src)
    if not xPlayer then return false end
    local map = { cash = 'money', bank = 'bank' }
    xPlayer.removeAccountMoney(map[account] or account, amount)
    return true
end

function Framework.Server.AddMoney(src, amount, account)
    local xPlayer = Framework.Server.GetPlayer(src)
    if not xPlayer then return false end
    local map = { cash = 'money', bank = 'bank' }
    xPlayer.addAccountMoney(map[account] or account, amount)
    return true
end

-- No item functions here on purpose: item operations belong to the inventory
-- module - use the CodemLib.Inventory.* API (Count/Add/Remove/...) instead.

---Register a server-side "use" handler for an inventory item. `cb` gets src.
---@param name string
---@param cb fun(src: number)
function Framework.Server.CreateUseableItem(name, cb)
    if not name or not cb then return end
    ESX.RegisterUsableItem(name, function(src)
        cb(src)
    end)
end

---Vehicle base value. ESX ships no shared price list (prices live in whatever
---vehicle shop you run), so this returns 0 and the consumer falls back to its own
---pricing. Override here if your shop exposes a lookup.
---@param _model string|number
---@return number
function Framework.Server.GetVehicleValue(_model)
    return 0
end

---Routed through the lib's notify module so LibConfig.Notify picks the look.
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

local function dbUpdate(sql, params)
    if MySQL and MySQL.update and MySQL.update.await then
        return MySQL.update.await(sql, params)
    end
    local p = promise.new()
    exports.oxmysql:update(sql, params, function(res) p:resolve(res) end)
    return Citizen.Await(p)
end

-- users.job is a plain column (no JSON parse); the TTL cache still avoids
-- rescanning big tables on every panel refresh.
local employeeCache = {} -- [job] = { at = ms, rows = table }
local EMPLOYEE_CACHE_MS = 30000

---@param job string
function Framework.Server.ClearJobEmployeesCache(job)
    employeeCache[job] = nil
end

---Offline snapshot from the DB. users only updates on the save cycle, so it
---LAGS for anyone online - the live pass in GetJobEmployees overrides it.
local function dbJobEmployees(job)
    local hit = employeeCache[job]
    if hit and (GetGameTimer() - hit.at) < EMPLOYEE_CACHE_MS then return hit.rows end

    local rows = dbQuery(
        'SELECT u.identifier, u.firstname, u.lastname, u.job_grade, g.label AS gradeLabel '
        .. 'FROM users u LEFT JOIN job_grades g ON g.job_name = u.job AND g.grade = u.job_grade '
        .. 'WHERE u.job = ?',
        { job }
    ) or {}

    local out = {}
    for _, row in ipairs(rows) do
        out[#out + 1] = {
            cid   = row.identifier,
            name  = ('%s %s'):format(row.firstname or '', row.lastname or ''):gsub('%s+$', ''),
            grade = row.gradeLabel or row.job_grade or 0,
        }
    end

    employeeCache[job] = { at = GetGameTimer(), rows = out }
    return out
end

---Everyone employed at `job`, online or offline. Online players are read from
---memory every call and their CURRENT job overrides the stale DB row.
---@param job string
---@return { cid: string, name: string, grade: string|number }[]
function Framework.Server.GetJobEmployees(job)
    -- Live pass: [identifier] = entry when on this job, false when online
    -- with a different job (their DB row may still say this job - drop it).
    local online = {}
    for _, xPlayer in pairs(ESX.GetExtendedPlayers() or {}) do
        if xPlayer and xPlayer.identifier then
            if xPlayer.job and xPlayer.job.name == job then
                online[xPlayer.identifier] = {
                    cid   = xPlayer.identifier,
                    name  = (xPlayer.getName and xPlayer.getName()) or xPlayer.identifier,
                    grade = xPlayer.job.grade_label or xPlayer.job.grade or 0,
                }
            else
                online[xPlayer.identifier] = false
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
        added[row.cid] = true
    end
    for cid, live in pairs(online) do
        if live and not added[cid] then out[#out + 1] = live end
    end
    return out
end

---Grade list for a job (job_grades table), sorted by level.
---@param job string
---@return { level: number, label: string }[]
function Framework.Server.GetJobGrades(job)
    local rows = dbQuery(
        'SELECT grade, label FROM job_grades WHERE job_name = ? ORDER BY grade ASC', { job }
    ) or {}
    local out = {}
    for _, row in ipairs(rows) do
        out[#out + 1] = { level = row.grade, label = row.label or tostring(row.grade) }
    end
    return out
end

---Set an employee's grade (online via xPlayer, offline via the users table).
---@param cid string identifier
---@param job string
---@param grade number
---@return boolean
function Framework.Server.SetJobGrade(cid, job, grade)
    grade = tonumber(grade) or 0
    local xPlayer = ESX.GetPlayerFromIdentifier(cid)
    if xPlayer then
        xPlayer.setJob(job, grade)
    else
        dbUpdate(
            'UPDATE users SET job = ?, job_grade = ? WHERE identifier = ?',
            { job, grade, cid }
        )
    end
    employeeCache[job] = nil
    return true
end

---Fire an employee from a job (falls back to unemployed).
---@param cid string identifier
---@param job string
---@return boolean
function Framework.Server.FireFromJob(cid, job)
    local xPlayer = ESX.GetPlayerFromIdentifier(cid)
    if xPlayer then
        xPlayer.setJob('unemployed', 0)
    else
        dbUpdate(
            'UPDATE users SET job = "unemployed", job_grade = 0 WHERE identifier = ? AND job = ?',
            { cid, job }
        )
    end
    employeeCache[job] = nil
    return true
end

--------------------------------------------------------------------------------
-- Permissions
--------------------------------------------------------------------------------

---True if the player's ESX group is enabled in Config.AdminPermissions, or the
---player holds the 'command' ace (txAdmin / server console admins).
---@param src number
---@return boolean
function Framework.Server.IsAdmin(src)
    if not src then return false end

    if IsPlayerAceAllowed(src, 'command') then return true end

    local xPlayer = Framework.Server.GetPlayer(src)
    if not xPlayer then return false end
    local grp = (xPlayer.getGroup and xPlayer.getGroup()) or xPlayer.group or 'user'

    local perms = Config.AdminPermissions
    if type(perms) ~= 'table' or next(perms) == nil then
        perms = { ['admin'] = true, ['superadmin'] = true }
    end

    return perms[grp] == true
end
