---@type { hour: number, minute: number }|nil
local frozenTime = nil

RegisterNetEvent('codem-lib:weather:apply', function(data)
    if type(data) ~= 'table' or type(data.weather) ~= 'string' then return end
    local weather = data.weather

    CreateThread(function()
        SetWeatherTypeOverTime(weather, 15.0)
        Wait(15000)
        SetWeatherTypePersist(weather)
        SetWeatherTypeNow(weather)
        SetWeatherTypeNowPersist(weather)
    end)
end)

RegisterNetEvent('codem-lib:weather:time', function(data)
    if type(data) ~= 'table' or type(data.hour) ~= 'number' then return end

    if frozenTime then
        frozenTime = { hour = data.hour, minute = data.minute or 0 }
    end
    NetworkOverrideClockTime(data.hour, data.minute or 0, 0)
end)

RegisterNetEvent('codem-lib:weather:blackout', function(data)
    local enabled = type(data) == 'table' and data.state == true
    SetArtificialLightsState(enabled)
    SetArtificialLightsStateAffectsVehicles(false)
end)

RegisterNetEvent('codem-lib:weather:freeze', function(data)
    local enabled = type(data) == 'table' and data.state == true

    if not enabled then
        frozenTime = nil
        return
    end

    if frozenTime then return end
    frozenTime = { hour = GetClockHours(), minute = GetClockMinutes() }

    CreateThread(function()
        while frozenTime do
            NetworkOverrideClockTime(frozenTime.hour, frozenTime.minute, 0)
            Wait(200)
        end
    end)
end)

---@type { weather: string, hour: number, minute: number }|nil
local localOverride = nil

local PROVIDERS = {
    'Renewed-Weathersync', 'qbx_weathersync', 'qb-weathersync', 'cd_easytime', 'av_sync', 'av_weather',
    'wc_weathersync', 'nc_weathersync', 'ss-weathersync', 'weathersync', 'vSync', 'codem-dynamicweather',
}

local function activeProviders()
    local out = {}
    for _, name in ipairs(PROVIDERS) do
        if GetResourceState(name) == 'started' then out[#out + 1] = name end
    end
    return out
end

---@param pause boolean
local function pauseProviders(pause)
    for _, name in ipairs(activeProviders()) do
        if name == 'Renewed-Weathersync' then
            TriggerEvent(pause and 'Renewed:client:DisableSync' or 'Renewed:client:EnableSync')
        elseif name == 'qbx_weathersync' or name == 'qb-weathersync' then
            TriggerEvent(pause and 'qb-weathersync:client:DisableSync' or 'qb-weathersync:client:EnableSync')
        elseif name == 'cd_easytime' then
            TriggerEvent('cd_easytime:PauseSync', pause)
        elseif name == 'vSync' then
            TriggerEvent('vSync:toggle', pause)
        elseif name == 'weathersync' then
            TriggerEvent('weathersync:setSyncEnabled', not pause)
        elseif name == 'codem-dynamicweather' then
            pcall(function()
                local weather = exports['codem-dynamicweather']
                if pause then
                    weather:setLocalWeather(localOverride and localOverride.weather or 'EXTRASUNNY')
                    weather:setLocalTime(localOverride and localOverride.hour or 12, localOverride and localOverride.minute or 0)
                else
                    weather:clearLocalWeather()
                    weather:clearLocalTime()
                end
            end)
        elseif name == 'av_weather' or name == 'av_sync' then
            if pause then
                TriggerEvent('av_weather:freeze', true, localOverride and localOverride.hour or 12, localOverride and localOverride.minute or 0, localOverride and localOverride.weather or 'EXTRASUNNY', false, false, false)
            else
                TriggerEvent('av_weather:freeze', false)
            end
        end
    end
end

---@param enabled boolean
---@param opts? { weather?: string, hour?: number, minute?: number }
---@return boolean
local function setLocalOverride(enabled, opts)
    if not enabled then
        if not localOverride then return true end
        localOverride = nil
        ClearWeatherTypePersist()
        ClearOverrideWeather()
        NetworkClearClockTimeOverride()
        pauseProviders(false)
        TriggerServerEvent('codem-lib:weather:sync')
        return true
    end

    opts = type(opts) == 'table' and opts or {}
    local weather = type(opts.weather) == 'string' and opts.weather:upper() or 'EXTRASUNNY'
    local hour = tonumber(opts.hour) or 12
    local minute = tonumber(opts.minute) or 0
    local last = localOverride
    local wasActive = last ~= nil
    local moved = not last or last.weather ~= weather or last.hour ~= hour or last.minute ~= minute
    localOverride = { weather = weather, hour = hour, minute = minute }
    -- Pausing twice is harmless, and the providers that are handed the values
    -- (av_weather, codem-dynamicweather) need them again when they change.
    if moved then pauseProviders(true) end
    if wasActive then return true end

    CreateThread(function()
        while localOverride do
            local o = localOverride
            SetWeatherTypePersist(o.weather)
            SetWeatherTypeNow(o.weather)
            SetWeatherTypeNowPersist(o.weather)
            SetOverrideWeather(o.weather)
            NetworkOverrideClockTime(o.hour, o.minute, 0)
            Wait(500)
        end
    end)
    return true
end

exports('SetLocalWeatherOverride', setLocalOverride)
exports('GetLocalWeatherOverride', function() return localOverride end)
exports('GetLocalWeatherProviders', function() return PROVIDERS end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and localOverride then setLocalOverride(false) end
end)

CreateThread(function()
    Wait(2000)
    TriggerServerEvent('codem-lib:weather:sync')
end)
