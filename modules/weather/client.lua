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

CreateThread(function()
    Wait(2000)
    TriggerServerEvent('codem-lib:weather:sync')
end)
