--[[
    Phone (server) — reading and changing a character's phone number through
    whichever phone resource the server runs. One module, provider-agnostic:
    the resource is picked by LibConfig.Phone.provider ('auto' detects a
    running one, 'framework' uses only the framework's own charinfo field).

    Global API:
      Phone.Get(src)             -> number string | nil
      Phone.Set(src, number)     -> true | false, reason
      Phone.Exists(number)       -> true | false | nil (nil = provider cannot tell)
      Phone.Generate()           -> number string | nil
      Phone.Provider()           -> active provider name

    Why the framework field alone is not enough: every phone resource keeps
    the number in its own store (a table, a SIM record, item metadata) and the
    framework's charinfo.phone / users.phone_number is only a mirror. Writing
    the mirror leaves the phone app on the old number. Each provider entry
    writes the real store and this module then mirrors the framework field so
    HUDs and ID cards agree with the phone.

    Provider notes:
      codem-phone     GetPhoneNumberBySource / ByIdentifier for reads. No setter
                      export is published, so Set writes the phone's own table
                      (LibConfig.Phone.codemTable / codemNumberColumn /
                      codemIdentifierColumn, defaults codem_mphone_data,
                      phone_number, identifier). Adjust those to the real schema.
      lb-phone        number lives in `phone_phones` (id = framework identifier).
                      Unique-phone mode keeps it in item metadata instead; that
                      row is not touched, Set returns 'no_phone'. The client is
                      told to ReloadPhone() afterwards.
      qs-smartphone   no setter export; the number IS the framework field, so
      qs-smartphone-pro the framework path is the real write. The phone reads it
                      again on the next open / relog.
      cylex_phone     getUserData / setUserData keyed by the framework
                      identifier. Exists() only sees cached users.
      17mov_Phone     SIM based: a new SIM is added with the number, then the
                      old one ejected. Numbers are unique per the resource.

    Set reasons: 'offline' | 'invalid_number' | 'number_taken' | 'no_phone'
                 | 'no_identifier' | 'provider_error' | 'unsupported'
]]

Phone = Phone or {}

local function started(res)
    return GetResourceState(res) == 'started'
end

local function isEsx()
    return started('es_extended')
end

local function server()
    return type(Framework) == 'table' and Framework.Server or nil
end

---@param src number
---@return string|nil
local function identifierOf(src)
    local fw = server()
    if not fw or not fw.GetIdentifier then return nil end
    local ok, id = pcall(fw.GetIdentifier, src)
    return ok and id or nil
end

---@param value any
---@return string|nil
local function normalise(value)
    if type(value) == 'number' then value = tostring(math.floor(value)) end
    if type(value) ~= 'string' then return nil end

    local number = value:gsub('^%s+', ''):gsub('%s+$', '')
    if number == '' or number:find('[^%d%s%-%(%)]') then return nil end

    local digits = select(2, number:gsub('%d', ''))
    local cfg = LibConfig.Phone or {}
    if digits < (cfg.minDigits or 3) or digits > (cfg.maxDigits or 15) then return nil end

    return number
end

local function query(sql, params)
    local ok, rows = pcall(function() return MySQL.query.await(sql, params) end)
    return ok and rows or nil
end

local function update(sql, params)
    local ok, affected = pcall(function() return MySQL.update.await(sql, params) end)
    return ok and tonumber(affected) or nil
end

--------------------------------------------------------------------------------
-- Framework store (used directly by qs and as the mirror for everyone else)
--------------------------------------------------------------------------------

local function frameworkGet(src)
    local fw = server()
    if not fw or not fw.GetCharInfo then return nil end
    local ok, info = pcall(fw.GetCharInfo, src)
    if not ok or type(info) ~= 'table' then return nil end
    return info.phone
end

local function frameworkSet(src, number)
    local fw = server()
    if not fw then return false, 'unsupported' end

    if isEsx() then
        local xPlayer = fw.GetPlayer and fw.GetPlayer(src)
        if not xPlayer then return false, 'offline' end
        if xPlayer.set then pcall(xPlayer.set, 'phoneNumber', number) end
        update('UPDATE `users` SET `phone_number` = ? WHERE `identifier` = ?', { number, xPlayer.identifier })
        return true
    end

    if not fw.SetCharInfo then return false, 'unsupported' end
    local ok, done = pcall(fw.SetCharInfo, src, { phone = number })
    if not ok or done ~= true then return false, 'provider_error' end
    return true
end

local function frameworkExists(number)
    local rows
    if isEsx() then
        rows = query('SELECT 1 AS hit FROM `users` WHERE `phone_number` = ? LIMIT 1', { number })
    else
        rows = query("SELECT 1 AS hit FROM `players` WHERE JSON_UNQUOTE(JSON_EXTRACT(`charinfo`, '$.phone')) = ? LIMIT 1", { number })
    end
    if rows == nil then return nil end
    return rows[1] ~= nil
end

--------------------------------------------------------------------------------
-- Providers
--------------------------------------------------------------------------------

local function qsGet(res, src)
    local ex = exports[res]
    local tries = {
        function() return ex:GetCurrentPhoneNumber(src) end,
        function() return ex:GetPlayerPhone(src) end,
        function()
            local id = identifierOf(src)
            return id and ex:GetPhoneNumberFromIdentifier(id) or nil
        end,
    }
    for _, try in ipairs(tries) do
        local ok, number = pcall(try)
        if ok and number ~= nil and number ~= '' and number ~= false then return tostring(number) end
    end
    return nil
end

local function codemStore()
    local cfg = LibConfig.Phone or {}
    return {
        table = cfg.codemTable or 'codem_mphone_data',
        number = cfg.codemNumberColumn or 'phone_number',
        identifier = cfg.codemIdentifierColumn or 'identifier',
    }
end

---Each entry: get(src) -> number|nil, set(src, number) -> ok, reason,
---exists?(number) -> true|false|nil, generate?() -> number|nil, mirror boolean.
---@type table<string, table>
local PROVIDERS = {
    ['codem-phone'] = {
        mirror = true,
        get = function(src)
            local number = exports['codem-phone']:GetPhoneNumberBySource(src)
            if number == nil or number == '' then
                local id = identifierOf(src)
                number = id and exports['codem-phone']:GetPhoneNumberByIdentifier(id) or nil
            end
            return number ~= nil and number ~= '' and tostring(number) or nil
        end,
        exists = function(number)
            local online = exports['codem-phone']:GetSourceFromNumber(number)
            if online ~= nil then return true end
            local store = codemStore()
            local rows = query(('SELECT 1 AS hit FROM `%s` WHERE `%s` = ? LIMIT 1'):format(store.table, store.number), { number })
            if rows == nil then return nil end
            return rows[1] ~= nil
        end,
        set = function(src, number)
            local id = identifierOf(src)
            if not id then return false, 'no_identifier' end
            local store = codemStore()
            local changed = update(('UPDATE `%s` SET `%s` = ? WHERE `%s` = ?'):format(store.table, store.number, store.identifier), { number, id })
            if changed == nil then return false, 'provider_error' end
            if changed == 0 then return false, 'no_phone' end
            return true
        end,
    },

    ['lb-phone'] = {
        mirror = true,
        get = function(src)
            local number = exports['lb-phone']:GetEquippedPhoneNumber(src)
            return number ~= nil and number ~= '' and tostring(number) or nil
        end,
        exists = function(number)
            local rows = query('SELECT `id` FROM `phone_phones` WHERE `phone_number` = ? LIMIT 1', { number })
            if rows == nil then return nil end
            if rows[1] then return true end
            rows = query('SELECT `identifier` FROM `phone_last_phone` WHERE `phone_number` = ? LIMIT 1', { number })
            return rows ~= nil and rows[1] ~= nil
        end,
        set = function(src, number)
            local id = identifierOf(src)
            if not id then return false, 'no_identifier' end

            local changed = update('UPDATE `phone_phones` SET `phone_number` = ? WHERE `id` = ?', { number, id })
            if changed == nil then return false, 'provider_error' end
            if changed == 0 then return false, 'no_phone' end

            TriggerClientEvent('codem-lib:phone:reload', src)
            return true
        end,
    },

    ['qs-smartphone'] = {
        mirror = false,
        get = function(src) return qsGet('qs-smartphone', src) or frameworkGet(src) end,
        exists = frameworkExists,
        set = frameworkSet,
    },

    ['qs-smartphone-pro'] = {
        mirror = false,
        get = function(src) return qsGet('qs-smartphone-pro', src) or frameworkGet(src) end,
        exists = frameworkExists,
        set = frameworkSet,
    },

    ['cylex_phone'] = {
        mirror = true,
        get = function(src)
            local data = exports.cylex_phone:getUserDataBySource(src)
            local number = type(data) == 'table' and data.phoneNumber or nil
            return number ~= nil and number ~= '' and tostring(number) or nil
        end,
        exists = function(number)
            local list = exports.cylex_phone:getUserDataList()
            if type(list) ~= 'table' then return nil end
            for _, user in pairs(list) do
                if type(user) == 'table' and tostring(user.phoneNumber) == number then return true end
            end
            return false
        end,
        set = function(src, number)
            local id = identifierOf(src)
            if not id then return false, 'no_identifier' end
            local done = exports.cylex_phone:setUserData(id, 'phoneNumber', number)
            if done ~= true then return false, 'provider_error' end
            return true
        end,
    },

    ['17mov_Phone'] = {
        mirror = true,
        get = function(src)
            local number = exports['17mov_Phone']:GetNumberFromPlayer(src)
            return number ~= nil and number ~= '' and tostring(number) or nil
        end,
        exists = function(number)
            local id = exports['17mov_Phone']:GetIdentifierFromNumber(number)
            return id ~= nil and id ~= ''
        end,
        generate = function()
            local number = exports['17mov_Phone']:GeneratePhoneNumber()
            return number ~= nil and tostring(number) or nil
        end,
        set = function(src, number)
            local current = exports['17mov_Phone']:GetNumberFromPlayer(src)
            local added = exports['17mov_Phone']:AddSimcard(src, number)
            if added ~= true then return false, 'provider_error' end
            if current ~= nil and current ~= '' and tostring(current) ~= number then
                pcall(function() exports['17mov_Phone']:EjectSimCard(src, tostring(current)) end)
            end
            return true
        end,
    },

    ['framework'] = {
        mirror = false,
        get = frameworkGet,
        exists = frameworkExists,
        set = frameworkSet,
    },
}

local CANDIDATES = {
    'codem-phone',
    'lb-phone',
    'qs-smartphone-pro',
    'qs-smartphone',
    'cylex_phone',
    '17mov_Phone',
}

---@return string
local function provider()
    local cfg = (LibConfig.Phone and LibConfig.Phone.provider) or 'auto'
    if cfg ~= 'auto' then return PROVIDERS[cfg] and cfg or 'framework' end
    for _, res in ipairs(CANDIDATES) do
        if started(res) then return res end
    end
    return 'framework'
end

local function guarded(fn, ...)
    local ok, a, b = pcall(fn, ...)
    if not ok then
        print(('[codem-lib] Phone: provider call failed: %s'):format(tostring(a)))
        return nil, 'provider_error'
    end
    return a, b
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

---@return string active provider name ('framework' when no phone resource runs)
function Phone.Provider()
    return provider()
end

---@param src number online player server id
---@return string|nil
function Phone.Get(src)
    src = tonumber(src)
    if not src or GetPlayerName(src) == nil then return nil end

    local number = guarded(PROVIDERS[provider()].get, src)
    if number ~= nil and number ~= '' then return tostring(number) end
    return frameworkGet(src)
end

---@param number string
---@return boolean|nil
function Phone.Exists(number)
    number = normalise(number)
    if not number then return false end

    local p = PROVIDERS[provider()]
    if p.exists then
        local hit = guarded(p.exists, number)
        if hit ~= nil then return hit end
    end
    return frameworkExists(number)
end

---@param src number online player server id
---@param value string|number
---@return boolean, string|nil reason
function Phone.Set(src, value)
    src = tonumber(src)
    if not src or GetPlayerName(src) == nil then return false, 'offline' end

    local number = normalise(value)
    if not number then return false, 'invalid_number' end

    local name = provider()
    local p = PROVIDERS[name]

    local current = Phone.Get(src)
    if current == number then return true end

    if Phone.Exists(number) == true then return false, 'number_taken' end

    local done, reason = guarded(p.set, src, number)
    if done ~= true then return false, reason or 'provider_error' end

    if p.mirror then pcall(frameworkSet, src, number) end

    return true
end

---@return string|nil
function Phone.Generate()
    local p = PROVIDERS[provider()]
    if p.generate then
        local number = guarded(p.generate)
        if number then return number end
    end

    local cfg = LibConfig.Phone or {}
    local digits = math.max(cfg.minDigits or 3, math.min(cfg.maxDigits or 15, cfg.generateDigits or 7))

    for _ = 1, 25 do
        local out = {}
        out[1] = tostring(math.random(1, 9))
        for i = 2, digits do out[i] = tostring(math.random(0, 9)) end
        local candidate = table.concat(out)
        if Phone.Exists(candidate) ~= true then return candidate end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Exports — consumer scripts call these (via the init.lua shim)
--------------------------------------------------------------------------------

exports('GetPhoneNumber', Phone.Get)
exports('SetPhoneNumber', function(src, number)
    local ok, reason = Phone.Set(src, number)
    return { ok = ok == true, error = ok == true and nil or reason }
end)
exports('PhoneNumberExists', Phone.Exists)
exports('GeneratePhoneNumber', Phone.Generate)
exports('GetPhoneProvider', Phone.Provider)
