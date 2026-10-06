--[[
    ESX Framework Integration - Server
    Mirrors the `Framework.Server` API. Only active when the resolved framework is 'esx'.
]]
-- Framework selection: LibConfig.Framework (codem-lib config) wins, then the
-- consumer's own Config.Framework, then auto-detection of the running core.
local FW = (type(LibConfig) == 'table' and LibConfig.Framework ~= 'auto' and LibConfig.Framework)
    or (type(Config) == 'table' and Config.Framework)
    or 'auto'
if FW == 'auto' then
    -- Two passes: whichever core is already running wins, and when none is (a
    -- consumer that starts before the core does) the one that is installed at
    -- all is taken. The bridge itself asks the core object for later.
    local CORES = { { 'qbx_core', 'qbox' }, { 'qb-core', 'qb' }, { 'es_extended', 'esx' } }
    local function pick(started)
        for _, core in ipairs(CORES) do
            local state = GetResourceState(core[1])
            if started and state == 'started' then return core[2] end
            if not started and state ~= 'missing' then return core[2] end
        end
        return nil
    end
    FW = pick(true) or pick(false) or FW
end
if FW ~= 'esx' then return end

--- Asked for on first use, so a consumer that starts before es_extended does
--- not lose this whole bridge to a missing export.
local sharedObject
local ESX = setmetatable({}, {
    __index = function(_, key)
        if sharedObject == nil then
            local ok, obj = pcall(function() return exports['es_extended']:getSharedObject() end)
            sharedObject = (ok and type(obj) == 'table') and obj or false
        end
        return sharedObject and sharedObject[key] or nil
    end,
})

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
        gradeLabel = xPlayer.job.grade_label,
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

-- CreateJob / RemoveJob / SetJobGrade live further down, next to the job
-- employee helpers, because they share the database helper and the cache.

--------------------------------------------------------------------------------
-- Character loaded
--------------------------------------------------------------------------------

--[[
    One event for "the character is in the game", whichever framework fires it.
    Consumers listen to `codem-lib:playerLoaded` and never learn the framework's
    own event name. ESX has no gang concept, so no CreateGang/SetGang here —
    a consumer that owns its own gang catalog keeps it on its side.
]]
AddEventHandler('esx:playerLoaded', function(playerId)
    local src = tonumber(playerId) or source
    if src then TriggerEvent('codem-lib:playerLoaded', src) end
end)

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

local jobCallbacks = {}
local jobPending = {}

---Runs cb(src, job) after a character's job, grade, duty or gang changes. Bursts
---are coalesced per player: cb fires once, 250 ms later, with the job read from
---the framework.
---@param cb fun(src: number, job: table)
function Framework.Server.OnJobChanged(cb)
    jobCallbacks[#jobCallbacks + 1] = cb
end

local function jobChanged(src)
    src = tonumber(src)
    if not src or jobPending[src] or #jobCallbacks == 0 then return end
    jobPending[src] = true
    SetTimeout(250, function()
        jobPending[src] = nil
        if not GetPlayerName(src) then return end
        local job = Framework.Server.GetPlayerJob(src)
        for _, cb in ipairs(jobCallbacks) do
            local ok, err = pcall(cb, src, job)
            if not ok then print(('[codem-lib] OnJobChanged: %s'):format(err)) end
        end
    end)
end

AddEventHandler('esx:setJob', jobChanged)

local moneyChanged = {}
local SHARED_NAMES = { money = 'cash' }

---Runs cb(src, account, amount, operation, reason) whenever a character's money
---changes, from any script. account uses the shared names ('cash' | 'bank');
---operation is 'add' | 'remove' | 'set', and for 'set' amount is the new total.
---@param cb fun(src: number, account: string, amount: number, operation: string, reason?: string)
function Framework.Server.OnMoneyChange(cb)
    moneyChanged[#moneyChanged + 1] = cb
end

for event, operation in pairs({ ['esx:addAccountMoney'] = 'add', ['esx:removeAccountMoney'] = 'remove', ['esx:setAccountMoney'] = 'set' }) do
    AddEventHandler(event, function(src, account, amount, reason)
        if type(account) ~= 'string' then return end
        for _, cb in ipairs(moneyChanged) do cb(src, SHARED_NAMES[account] or account, tonumber(amount) or 0, operation, reason) end
    end)
end

-- No item functions here on purpose: item operations belong to the inventory
-- module - use the CodemLib.Inventory.* API (Count/Add/Remove/...) instead.

---Register a server-side "use" handler for an inventory item. `cb` gets src and,
---when the inventory passes it (ox_inventory does), the used slot with `metadata`.
---@param name string
---@param cb fun(src: number, item?: table)
function Framework.Server.CreateUseableItem(name, cb)
    if not name or not cb then return end
    ESX.RegisterUsableItem(name, function(src, _, item)
        cb(src, type(item) == 'table' and item or nil)
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

---Character names keyed by what was asked for. Accepts character identifiers
---as they are, and 'license:<hash>' account identifiers: ESX Legacy stores the
---license without its prefix, with a 'charN:' slot in front when multicharacter
---is on, so those are matched both ways.
---@param identifiers string[]
---@return table<string, string>
function Framework.Server.GetCharacterNames(identifiers)
    if type(identifiers) ~= 'table' or #identifiers == 0 then return {} end

    local clauses, params, askedAs = {}, {}, {}
    for _, identifier in ipairs(identifiers) do
        if type(identifier) == 'string' and identifier ~= '' then
            clauses[#clauses + 1] = '`identifier` = ?'
            params[#params + 1] = identifier
            askedAs[identifier] = identifier

            local bare = identifier:match('^license:(.+)$')
            if bare then
                clauses[#clauses + 1] = '`identifier` = ? OR `identifier` LIKE ?'
                params[#params + 1] = bare
                params[#params + 1] = '%:' .. bare
                askedAs[bare] = identifier
            end
        end
    end
    if #clauses == 0 then return {} end

    local rows = dbQuery(
        ('SELECT `identifier`, `firstname`, `lastname` FROM `users` WHERE %s'):format(table.concat(clauses, ' OR ')),
        params
    ) or {}

    local out = {}
    for _, row in ipairs(rows) do
        if row.identifier and row.firstname then
            local key = askedAs[row.identifier] or askedAs[row.identifier:match('^[^:]+:(.+)$') or '']
            local name = ('%s %s'):format(row.firstname, row.lastname or ''):gsub('%s+$', '')
            if key and name ~= '' and not out[key] then out[key] = name end
        end
    end
    return out
end

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
            cid        = row.identifier,
            name       = ('%s %s'):format(row.firstname or '', row.lastname or ''):gsub('%s+$', ''),
            grade      = row.gradeLabel or row.job_grade or 0,
            firstname  = row.firstname,
            lastname   = row.lastname,
            level      = tonumber(row.job_grade) or 0,
            gradeLabel = row.gradeLabel,
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
                local info = Framework.Server.GetCharInfo(xPlayer.source) or {}
                online[xPlayer.identifier] = {
                    cid        = xPlayer.identifier,
                    name       = (xPlayer.getName and xPlayer.getName()) or xPlayer.identifier,
                    grade      = xPlayer.job.grade_label or xPlayer.job.grade or 0,
                    firstname  = info.firstname,
                    lastname   = info.lastname,
                    level      = tonumber(xPlayer.job.grade) or 0,
                    gradeLabel = xPlayer.job.grade_label,
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
            out[#out + 1] = row  -- offline: DB is the truth
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

---ESX grade names are identifiers ('boss', 'recruit'); the readable text is the label.
---@param text any
---@return string
local function gradeKey(text)
    local key = tostring(text or ''):lower():gsub('[^%w]+', '_'):gsub('^_+', ''):gsub('_+$', '')
    return key ~= '' and key or 'grade'
end

---@param job table { label, grades }
---@return table[] grades in the shape ESX.CreateJob takes, lowest first
local function esxGrades(job)
    local grades = {}
    for gradeId, grade in pairs(job.grades or {}) do
        if type(grade) == 'table' then
            local label = grade.label or grade.name or tostring(gradeId)
            grades[#grades + 1] = {
                grade = tonumber(gradeId) or 0,
                -- ESX has no isboss flag; the 'boss' grade name is the convention.
                name = grade.isboss and 'boss' or gradeKey(grade.name or label),
                label = label,
                salary = math.floor(tonumber(grade.payment or grade.salary) or 0),
            }
        end
    end
    table.sort(grades, function(a, b) return a.grade < b.grade end)
    return grades
end

---@return boolean true when the registered job already equals what is asked for
local function sameJob(existing, label, grades)
    if type(existing) ~= 'table' or existing.label ~= label or type(existing.grades) ~= 'table' then return false end

    local count = 0
    for _ in pairs(existing.grades) do count = count + 1 end
    if count ~= #grades then return false end

    for _, grade in ipairs(grades) do
        local row = existing.grades[tostring(grade.grade)]
        if type(row) ~= 'table' or row.name ~= grade.name or row.label ~= grade.label
            or (tonumber(row.salary) or 0) ~= grade.salary then
            return false
        end
    end
    return true
end

---Drops a job's rows and makes the core read its job list again.
---@param name string
---@return boolean
local function deleteJobRows(name)
    local ok = pcall(function()
        dbQuery('DELETE FROM `job_grades` WHERE `job_name` = ?', { name })
        dbQuery('DELETE FROM `jobs` WHERE `name` = ?', { name })
    end)
    if not ok then return false end

    employeeCache[name] = nil
    if ESX.RefreshJobs then ESX.RefreshJobs() end
    return true
end

---ESX keeps jobs in the `jobs` / `job_grades` tables, so registering one is a
---database write the framework owns. A job that is already registered the same
---way is left alone (ESX would refuse it and print an error on every boot); one
---that changed is rewritten. Builds without ESX.CreateJob return false.
---@param name string
---@param job table { label, grades }
---@return boolean
function Framework.Server.CreateJob(name, job)
    if type(name) ~= 'string' or name == '' or type(job) ~= 'table' then return false end
    if not ESX.CreateJob then return false end

    local grades = esxGrades(job)
    if #grades == 0 then return false end

    local label = job.label or name
    local existing = ((ESX.GetJobs and ESX.GetJobs()) or {})[name]
    if existing then
        if sameJob(existing, label, grades) then return true end
        if not ESX.RefreshJobs or not deleteJobRows(name) then return false end
    end

    return ESX.CreateJob(name, label, grades) ~= false
end

---Deletes a job from the core. Release its members first (ReleaseJobMembers),
---otherwise they keep a job name the core no longer knows.
---@param name string
---@return boolean
function Framework.Server.RemoveJob(name)
    if type(name) ~= 'string' or name == '' or name == 'unemployed' then return false end
    if not ESX.RefreshJobs then return false end
    if not ((ESX.GetJobs and ESX.GetJobs()) or {})[name] then return false end

    return deleteJobRows(name)
end

---Sets a character's job and grade: through the core while they are online,
---in their `users` row while they are not.
---@param cid string
---@param job string
---@param grade number
---@return boolean success
---@return table|nil errorResult `{ code, message }` when the job or grade does not exist
function Framework.Server.SetJobGrade(cid, job, grade)
    if type(cid) ~= 'string' or cid == '' or type(job) ~= 'string' or job == '' then return false end
    grade = math.floor(tonumber(grade) or 0)

    if ESX.DoesJobExist and not ESX.DoesJobExist(job, grade) then
        return false, { code = 'job_refused', message = ('job "%s" has no grade %d'):format(job, grade) }
    end

    local xPlayer = ESX.GetPlayerFromIdentifier and ESX.GetPlayerFromIdentifier(cid) or nil
    if xPlayer and xPlayer.setJob then
        local previous = xPlayer.job and xPlayer.job.name or nil
        xPlayer.setJob(job, grade)

        employeeCache[job] = nil
        if previous then employeeCache[previous] = nil end
        return true
    end

    local ok, result = pcall(dbQuery,
        'UPDATE `users` SET `job` = ?, `job_grade` = ? WHERE `identifier` = ?', { job, grade, cid })
    if not ok or type(result) ~= 'table' or (tonumber(result.affectedRows) or 0) < 1 then return false end

    -- The job they left is unknown here, so every cached list is dropped.
    for cached in pairs(employeeCache) do employeeCache[cached] = nil end
    return true
end

---Fires an employee (back to unemployed).
---@param cid string
---@param job string
---@return boolean
function Framework.Server.FireFromJob(cid, job)
    local ok = Framework.Server.SetJobGrade(cid, 'unemployed', 0)
    if ok and type(job) == 'string' then employeeCache[job] = nil end
    return ok
end

---Removes everyone from a job, online or offline. Call this before deleting the job.
---@param name string
---@return boolean
function Framework.Server.ReleaseJobMembers(name)
    if type(name) ~= 'string' or name == '' or name == 'unemployed' then return false end

    employeeCache[name] = nil

    for _, xPlayer in pairs((ESX.GetExtendedPlayers and ESX.GetExtendedPlayers()) or {}) do
        if xPlayer and xPlayer.setJob and xPlayer.job and xPlayer.job.name == name then
            xPlayer.setJob('unemployed', 0)
        end
    end

    local ok = pcall(dbQuery,
        'UPDATE `users` SET `job` = ?, `job_grade` = ? WHERE `job` = ?', { 'unemployed', 0, name })
    return ok
end

---Edits the identity esx_identity keeps: the `users` row first, then the loaded
---player, so a failed write changes nothing. Fields ESX does not have are ignored.
---@param src number
---@param patch table { firstname?, lastname?, birthdate?, gender? }
---@return boolean
function Framework.Server.SetCharInfo(src, patch)
    local xPlayer = Framework.Server.GetPlayer(src)
    if not xPlayer or type(patch) ~= 'table' then return false end

    local columns, values, variables = {}, {}, {}
    local function field(column, variable, value)
        columns[#columns + 1] = ('`%s` = ?'):format(column)
        values[#values + 1] = value
        variables[variable] = value
    end

    if type(patch.firstname) == 'string' then field('firstname', 'firstName', patch.firstname) end
    if type(patch.lastname) == 'string' then field('lastname', 'lastName', patch.lastname) end
    if type(patch.birthdate) == 'string' then field('dateofbirth', 'dateofbirth', patch.birthdate) end
    if patch.gender ~= nil then
        field('sex', 'sex', (patch.gender == 'female' or patch.gender == 1) and 'f' or 'm')
    end
    if #columns == 0 then return false end

    values[#values + 1] = xPlayer.identifier
    local ok = pcall(dbQuery,
        ('UPDATE `users` SET %s WHERE `identifier` = ?'):format(table.concat(columns, ', ')), values)
    if not ok then return false end

    if xPlayer.set then
        for variable, value in pairs(variables) do xPlayer.set(variable, value) end
    end

    if (variables.firstName or variables.lastName) and xPlayer.setName then
        local get = xPlayer.get
        local first = variables.firstName or (get and get('firstName')) or ''
        local last = variables.lastName or (get and get('lastName')) or ''
        local name = ('%s %s'):format(first, last):gsub('^%s+', ''):gsub('%s+$', '')
        if name ~= '' then xPlayer.setName(name) end
    end

    return true
end

--------------------------------------------------------------------------------
-- Permissions
--------------------------------------------------------------------------------

---True if the player's ESX group is in LibConfig.AdminPermissions, or the
---player holds the 'command' ace (txAdmin / server console admins).
---@param src number
---@return boolean
function Framework.Server.IsAdmin(src)
    if not src then return false end
    if IsPlayerAceAllowed(src, 'command') then return true end

    local perms = LibConfig and LibConfig.AdminPermissions
    if type(perms) ~= 'table' or next(perms) == nil then
        perms = { ['superadmin'] = true }
    end
    local xPlayer = ESX.GetPlayerFromId(src)
    local group = xPlayer and xPlayer.getGroup and xPlayer.getGroup()
    return group ~= nil and perms[group] == true
end

--------------------------------------------------------------------------------
-- Account / character session (multicharacter, spawn selectors, logout)
--------------------------------------------------------------------------------

---Account identifier (rockstar license, without a character prefix).
---@param src number
---@return string|nil primary
---@return string[] all
function Framework.Server.GetLicense(src)
    local id = ESX.GetIdentifier(src)
    return id, id and { id } or {}
end

---@param src number
---@return boolean true while a character is loaded for this player
function Framework.Server.IsLoggedIn(src)
    return ESX.GetPlayerFromId(src) ~= nil
end

---Online player object for a character identifier, nil when not loaded.
---@param identifier string
---@return table|nil
function Framework.Server.GetPlayerByCharacter(identifier)
    return ESX.GetPlayerFromIdentifier(identifier)
end

local characterLoaded = {}

---Runs cb(src) every time a character finishes loading on the server.
---@param cb fun(src: number)
function Framework.Server.OnCharacterLoaded(cb)
    characterLoaded[#characterLoaded + 1] = cb
end

AddEventHandler('esx:playerLoaded', function(playerId)
    local src = tonumber(playerId)
    if not src then return end
    for _, cb in ipairs(characterLoaded) do cb(src) end
end)

---Loads a character into the session. ESX multicharacter convention: the slot
---id ('char1') is handed to esx:onPlayerJoined, es_extended prefixes it to the
---license and creates the row when newData ({ firstname, lastname, dateofbirth,
---sex, height }) is given.
---@param src number
---@param slot string
---@param newData table|nil
---@return boolean
function Framework.Server.Login(src, slot, newData)
    TriggerEvent('esx:onPlayerJoined', src, slot, newData)
    return true
end

---Unloads the current character (back to character selection).
---@param src number
function Framework.Server.Logout(src)
    TriggerEvent('esx:playerLogout', src)
end

---ESX has no delete API: the caller owns the identifier rows.
---@return boolean handled always false
function Framework.Server.DeleteCharacter()
    return false
end

---No command cache on ESX.
function Framework.Server.RefreshCommands() end

---Current position of the loaded character.
---@param src number
---@return table|nil { x, y, z, w }
function Framework.Server.GetLastPosition(src)
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return nil end
    local c = xPlayer.getCoords(true)
    return c and { x = c.x, y = c.y, z = c.z, w = c.heading or 0.0 } or nil
end

---ESX hands out no starter items through the framework.
---@return table
function Framework.Server.GetStarterItems()
    return {}
end

--------------------------------------------------------------------------------
-- Money for a character who may be offline
--------------------------------------------------------------------------------

--[[
    Charging somebody who is not connected.

    Anything on a timer — rent that renews itself, a bill falling due — has to
    move money for a character nobody is playing at that moment, and the
    `src`-shaped functions above cannot: there is no source to pass.

    Online FIRST, always. A loaded character's accounts live on the xPlayer
    object and reach `users.accounts` on ESX's own save cycle, so an SQL write
    made while they are playing is undone the next time they are saved. The
    table is the truth only for a character who is not loaded.

    ESX names the wallet `money`; consumers say `cash`, the same mapping the
    online functions above use.
]]

local ACCOUNT_NAMES = { cash = 'money', bank = 'bank' }

---The stored `users.accounts` object, or nil when there is no such character.
---@param identifier string
---@return table|nil
local function storedAccounts(identifier)
    local rows = dbQuery('SELECT `accounts` FROM `users` WHERE `identifier` = ? LIMIT 1', { identifier })
    local row = rows and rows[1]
    if not row then return nil end

    local accounts = row.accounts
    if type(accounts) == 'string' then
        local ok, decoded = pcall(json.decode, accounts)
        accounts = ok and decoded or nil
    end
    if type(accounts) ~= 'table' then return nil end
    return accounts
end

---@param identifier string
---@param accounts table
---@return boolean written
local function writeAccounts(identifier, accounts)
    local encoded = json.encode(accounts)
    local sql = 'UPDATE `users` SET `accounts` = ? WHERE `identifier` = ?'

    if MySQL and MySQL.update and MySQL.update.await then
        return (tonumber(MySQL.update.await(sql, { encoded, identifier })) or 0) > 0
    end

    local p = promise.new()
    exports.oxmysql:update(sql, { encoded, identifier }, function(affected) p:resolve(affected) end)
    return (tonumber(Citizen.Await(p)) or 0) > 0
end

---Balance of a character by identifier, online or not.
---@param cid string ESX character identifier
---@param account string 'cash' | 'bank'
---@return number
function Framework.Server.GetSourceByCid(cid)
    if type(cid) ~= 'string' or cid == '' then return nil end
    local xPlayer = ESX.GetPlayerFromIdentifier(cid)
    return xPlayer and tonumber(xPlayer.source) or nil
end

function Framework.Server.GetCharacter(cid)
    if type(cid) ~= 'string' or cid == '' then return nil end
    local xPlayer = ESX.GetPlayerFromIdentifier(cid)
    if xPlayer then
        local info = Framework.Server.GetCharInfo(xPlayer.source) or {}
        local bank = xPlayer.getAccount('bank')
        local cash = xPlayer.getAccount('money')
        return {
            citizenid = cid,
            source = tonumber(xPlayer.source),
            online = true,
            firstname = info.firstname,
            lastname = info.lastname,
            birthdate = info.birthdate,
            gender = info.gender,
            nationality = nil,
            phone = info.phone,
            job = {
                name = xPlayer.job and xPlayer.job.name,
                label = xPlayer.job and xPlayer.job.label,
                grade = tonumber(xPlayer.job and xPlayer.job.grade) or 0,
                gradeLabel = xPlayer.job and xPlayer.job.grade_label,
            },
            bank = bank and tonumber(bank.money) or 0,
            cash = cash and tonumber(cash.money) or 0,
        }
    end

    local rows = dbQuery('SELECT * FROM `users` WHERE `identifier` = ? LIMIT 1', { cid })
    local row = rows and rows[1]
    if not row then return nil end

    local accounts = row.accounts
    if type(accounts) == 'string' then
        local ok, decoded = pcall(json.decode, accounts)
        accounts = ok and decoded or nil
    end
    accounts = type(accounts) == 'table' and accounts or {}

    local jobs = Framework.Server.GetJobs() or {}
    local jobData = row.job and jobs[row.job] or nil
    local grades = jobData and jobData.grades or {}
    local gradeData = grades[tostring(row.job_grade)] or grades[tonumber(row.job_grade)]
    local sex = row.sex

    return {
        citizenid = cid,
        source = nil,
        online = false,
        firstname = row.firstname,
        lastname = row.lastname,
        birthdate = row.dateofbirth,
        gender = (sex == 'f' or sex == 'F' or sex == 1) and 'female' or 'male',
        nationality = nil,
        phone = row.phone_number,
        job = {
            name = row.job,
            label = jobData and jobData.label or row.job,
            grade = tonumber(row.job_grade) or 0,
            gradeLabel = gradeData and (gradeData.label or gradeData.name) or nil,
        },
        bank = tonumber(accounts.bank) or 0,
        cash = tonumber(accounts.money) or 0,
    }
end

function Framework.Server.GetBalanceByCid(cid, account)
    if type(cid) ~= 'string' or cid == '' then return 0 end
    local name = ACCOUNT_NAMES[account] or account or 'bank'

    local xPlayer = ESX.GetPlayerFromIdentifier(cid)
    if xPlayer then
        local acc = xPlayer.getAccount(name)
        return acc and acc.money or 0
    end

    local accounts = storedAccounts(cid)
    return accounts and tonumber(accounts[name]) or 0
end

---Take money from a character by identifier, online or not. False when the
---account cannot cover it, and then nothing was taken.
---@param cid string
---@param amount number
---@param account string 'cash' | 'bank'
---@return boolean
function Framework.Server.RemoveMoneyByCid(cid, amount, account)
    amount = tonumber(amount) or 0
    if amount <= 0 or type(cid) ~= 'string' or cid == '' then return false end
    local name = ACCOUNT_NAMES[account] or account or 'bank'

    local xPlayer = ESX.GetPlayerFromIdentifier(cid)
    if xPlayer then
        local acc = xPlayer.getAccount(name)
        if not acc or (acc.money or 0) < amount then return false end
        xPlayer.removeAccountMoney(name, amount)
        return true
    end

    local accounts = storedAccounts(cid)
    if not accounts then return false end

    local have = tonumber(accounts[name]) or 0
    if have < amount then return false end

    accounts[name] = have - amount
    return writeAccounts(cid, accounts)
end

---Give money to a character by identifier, online or not.
---@param cid string
---@param amount number
---@param account string 'cash' | 'bank'
---@return boolean
function Framework.Server.AddMoneyByCid(cid, amount, account)
    amount = tonumber(amount) or 0
    if amount <= 0 or type(cid) ~= 'string' or cid == '' then return false end
    local name = ACCOUNT_NAMES[account] or account or 'bank'

    local xPlayer = ESX.GetPlayerFromIdentifier(cid)
    if xPlayer then
        xPlayer.addAccountMoney(name, amount)
        return true
    end

    local accounts = storedAccounts(cid)
    if not accounts then return false end

    accounts[name] = (tonumber(accounts[name]) or 0) + amount
    return writeAccounts(cid, accounts)
end
