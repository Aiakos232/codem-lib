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
    }
end

function Framework.Server.GetBalance(src, account)
    local xPlayer = Framework.Server.GetPlayer(src)
    if not xPlayer then return 0 end
    local map = { cash = 'money', bank = 'bank' }
    local acc = xPlayer.getAccount(map[account] or account)
    return acc and acc.money or 0
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

---Everyone employed at `job`, online or offline.
---@param job string
---@return { cid: string, name: string, grade: string|number }[]
function Framework.Server.GetJobEmployees(job)
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
