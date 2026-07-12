--[[
    Vehicle fuel (client) — applies fuel for providers whose API lives on the
    client, and receives forwarded sets from the server (codem-lib:fuel:set).

    Exports:
      SetFuel(vehicle, amount)
]]

---Simple client SetFuel export wrapper.
local function viaExport(resource, fnName)
    return function(v, n)
        exports[resource][fnName or 'SetFuel'](exports[resource], v, n)
        return true
    end
end

-- v = vehicle entity, n = fuel amount (0-100). Providers missing here are
-- server-side only; the client export forwards to the server for them.
local PROVIDERS = {
    ['ox_fuel'] = {
        set = function(v, n)
            SetVehicleFuelLevel(v, n + 0.0)
            Entity(v).state.fuel = n
            return true
        end,
    },

    ['cdn-fuel']         = { set = viaExport('cdn-fuel') },
    ['qb-fuel']          = { set = viaExport('qb-fuel') },
    ['LegacyFuel']       = { set = viaExport('LegacyFuel') },
    ['lc_fuel']          = { set = viaExport('lc_fuel') },
    ['Renewed-Fuel']     = { set = viaExport('Renewed-Fuel') },
    ['myFuel']           = { set = viaExport('myFuel') },
    ['okokGasStation']   = { set = viaExport('okokGasStation') },
    ['qs-fuelstations']  = { set = viaExport('qs-fuelstations') },
    ['rcore_fuel']       = { set = viaExport('rcore_fuel', 'SetVehicleFuel') },
    ['x-fuel']           = { set = viaExport('x-fuel') },
}

-- 'auto' detection order — first running resource wins.
local CANDIDATES = {
    'ox_fuel', 'LegacyFuel', 'cdn-fuel', 'qb-fuel', 'lc_fuel', 'Renewed-Fuel',
    'myFuel', 'okokGasStation', 'qs-fuelstations', 'rcore_fuel', 'x-fuel',
}

local function provider()
    local cfg = (LibConfig.Fuel and LibConfig.Fuel.provider) or 'auto'
    if cfg ~= 'auto' then return cfg end
    for _, res in ipairs(CANDIDATES) do
        if GetResourceState(res) == 'started' then return res end
    end
    return 'none'
end

local function setFuel(vehicle, amount)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end

    local p = PROVIDERS[provider()]
    if p then
        local ok, res = pcall(p.set, vehicle, amount)
        if not ok then
            print(('[codem-lib] Fuel.set via "%s" failed: %s'):format(provider(), tostring(res)))
            return false
        end
        return res ~= false
    end

    -- Server-side provider (ox_fuel, lc_fuel, Renewed-Fuel...): forward.
    TriggerServerEvent('codem-lib:fuel:setRequest', NetworkGetNetworkIdFromEntity(vehicle), amount)
    return true
end

exports('SetFuel', setFuel)

-- The server forwards sets here for client-side providers.
RegisterNetEvent('codem-lib:fuel:set', function(netId, amount)
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if vehicle ~= 0 then setFuel(vehicle, amount) end
end)
