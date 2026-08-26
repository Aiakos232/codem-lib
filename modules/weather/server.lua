local CANDIDATES = {
    'Renewed-Weathersync',
    'qbx_weathersync',
    'qb-weathersync',
    'cd_easytime',
    'av_sync',
    'av_weather',
    'wc_weathersync',
    'nc_weathersync',
    'ss-weathersync',
    'weathersync',
    'vSync',
}

---@type table<string, string[]> capability -> export names to try, in order
local EXPORTS = {
    weather  = { 'setWeather', 'SetWeather', 'setWeatherType', 'changeWeather' },
    time     = { 'setTime', 'SetTime', 'setGameTime' },
    blackout = { 'setBlackout', 'SetBlackout', 'setBlackoutState', 'toggleBlackout' },
    freeze   = { 'setTimeFreeze', 'SetTimeFreeze', 'FreezeTime', 'freezeTime', 'setFreezeTime' },
    dynamic  = { 'setDynamicWeather', 'SetDynamicWeather', 'toggleDynamicWeather' },
}

---@type string|nil
local resolved = nil
---@type boolean
local looked = false

---@return string|nil
local function provider()
    local cfg = (LibConfig.Weather and LibConfig.Weather.provider)
    if cfg == false then return nil end

    if cfg and cfg ~= 'auto' then
        return GetResourceState(cfg) == 'started' and cfg or nil
    end

    if looked then return resolved end
    looked = true

    for _, name in ipairs(CANDIDATES) do
        if GetResourceState(name) == 'started' then
            resolved = name
            if LibConfig.Debug then
                print(('[codem-lib] weather provider: %s'):format(name))
            end
            return resolved
        end
    end

    resolved = nil
    return nil
end

local function forget()
    looked = false
    resolved = nil
end

AddEventHandler('onResourceStart', forget)
AddEventHandler('onResourceStop', forget)

---@param capability string
---@vararg any
---@return boolean handled
local function call(capability, ...)
    local resource = provider()
    if not resource then return false end

    for _, fn in ipairs(EXPORTS[capability] or {}) do
        local ok, err = pcall(function(...)
            return exports[resource][fn](exports[resource], ...)
        end, ...)

        if ok then return true end
        if not tostring(err):find('No such export') then
            print(('[codem-lib] weather bridge: %s:%s failed (%s)'):format(resource, fn, tostring(err)))
            return false
        end
    end

    return false
end

---@param names string[]
---@return any|nil
local function read(names)
    local resource = provider()
    if not resource then return nil end

    for _, fn in ipairs(names) do
        local ok, value = pcall(function()
            return exports[resource][fn](exports[resource])
        end)
        if ok then return value end
    end
    return nil
end

local state = {
    weather = 'EXTRASUNNY',
    blackout = false,
    freezeTime = false,
    dynamic = true,
}

---@type { weather: string|nil, time: { hour: number, minute: number }|nil, blackout: boolean|nil, freeze: boolean|nil }
local fallback = {}

---@return string|nil
local function getProvider()
    return provider()
end

---@return table
local function getState()
    local weather = read({ 'getWeatherState', 'GetWeatherState', 'getWeather' })
    local blackout = read({ 'getBlackoutState', 'GetBlackoutState', 'getBlackout' })
    local freeze = read({ 'getTimeFreezeState', 'GetTimeFreezeState', 'getFreezeTime' })
    local dynamic = read({ 'getDynamicWeather', 'GetDynamicWeather' })

    if type(weather) == 'string' then state.weather = weather:upper() end
    if type(blackout) == 'boolean' then state.blackout = blackout end
    if type(freeze) == 'boolean' then state.freezeTime = freeze end
    if type(dynamic) == 'boolean' then state.dynamic = dynamic end

    return {
        weather = state.weather,
        blackout = state.blackout,
        freezeTime = state.freezeTime,
        dynamic = state.dynamic,
        provider = provider(),
    }
end

---@param weather string
---@return boolean
local function setWeather(weather)
    if type(weather) ~= 'string' or weather == '' then return false end
    weather = weather:upper()
    state.weather = weather

    call('dynamic', false)
    state.dynamic = false

    if call('weather', weather) then
        fallback.weather = nil
        return true
    end

    fallback.weather = weather
    TriggerClientEvent('codem-lib:weather:apply', -1, { weather = weather })
    return true
end

---@param hour number
---@param minute number
---@return boolean
local function setGameTime(hour, minute)
    hour = tonumber(hour)
    minute = tonumber(minute) or 0
    if not hour or hour < 0 or hour > 23 or minute < 0 or minute > 59 then return false end
    hour = math.floor(hour)
    minute = math.floor(minute)

    if call('time', hour, minute) then
        fallback.time = nil
        return true
    end

    fallback.time = { hour = hour, minute = minute }
    TriggerClientEvent('codem-lib:weather:time', -1, { hour = hour, minute = minute })
    return true
end

---@param enabled boolean
---@return boolean
local function setBlackout(enabled)
    enabled = enabled == true
    state.blackout = enabled

    if call('blackout', enabled) then
        fallback.blackout = nil
        return true
    end

    fallback.blackout = enabled
    TriggerClientEvent('codem-lib:weather:blackout', -1, { state = enabled })
    return true
end

---@param enabled boolean
---@return boolean
local function setTimeFreeze(enabled)
    enabled = enabled == true
    state.freezeTime = enabled

    if call('freeze', enabled) then
        fallback.freeze = nil
        return true
    end

    fallback.freeze = enabled
    TriggerClientEvent('codem-lib:weather:freeze', -1, { state = enabled })
    return true
end

---@param enabled boolean
---@return boolean
local function setDynamicWeather(enabled)
    enabled = enabled == true
    state.dynamic = enabled
    call('dynamic', enabled)
    return true
end

exports('GetWeatherProvider', getProvider)
exports('GetWeatherState', getState)
exports('SetWeather', setWeather)
exports('SetGameTime', setGameTime)
exports('SetBlackout', setBlackout)
exports('SetTimeFreeze', setTimeFreeze)
exports('SetDynamicWeather', setDynamicWeather)

RegisterNetEvent('codem-lib:weather:sync', function()
    local src = source
    if provider() then return end

    if fallback.weather then
        TriggerClientEvent('codem-lib:weather:apply', src, { weather = fallback.weather })
    end
    if fallback.time then
        TriggerClientEvent('codem-lib:weather:time', src, fallback.time)
    end
    if fallback.blackout then
        TriggerClientEvent('codem-lib:weather:blackout', src, { state = true })
    end
    if fallback.freeze then
        TriggerClientEvent('codem-lib:weather:freeze', src, { state = true })
    end
end)
