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

function Framework.Server.GetCharacterNames(identifiers)
    if type(identifiers) ~= 'table' or #identifiers == 0 then return {} end

    local placeholders = {}
    for index = 1, #identifiers do placeholders[index] = '?' end

    local rows = dbQuery(
        ('SELECT `identifier`, `firstname`, `lastname` FROM `users` WHERE `identifier` IN (%s)')
            :format(table.concat(placeholders, ',')),
        identifiers
    ) or {}

    local out = {}
    for _, row in ipairs(rows) do
        if row.identifier and row.firstname then
            local name = ('%s %s'):format(row.firstname, row.lastname or ''):gsub('%s+$', '')
            if name ~= '' then out[row.identifier] = name end
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
