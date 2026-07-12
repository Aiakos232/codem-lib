--[[
    Vehicle fuel (server) — every provider in one file. Selection via LibConfig.Fuel.provider ('auto' picks
    the first running resource).

    Exports:
      SetFuel(src, vehicle, amount)

    Some fuel scripts only expose a client API; for those the amount is
    forwarded to the target player's client (codem-lib:fuel:set).
]]

---Forward to the given player's client, which applies the provider call.
local function viaClient(src, vehicle, amount)
    if not vehicle or not DoesEntityExist(vehicle) then return false end
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if not netId or netId <= 0 then return false end
    TriggerClientEvent('codem-lib:fuel:set', src, netId, amount)
    return true
end

-- s = src, v = vehicle entity, n = fuel amount (0-100).
local PROVIDERS = {
    ['ox_fuel'] = {
        set = function(_, v, n)
            local state = Entity(v).state
            if not state then return false end
            state.fuel = n
            return true
        end,
    },

    ['lc_fuel'] = {
        set = function(_, v, n)
            exports['lc_fuel']:SetFuel(v, n)
            return true
        end,
    },

    ['Renewed-Fuel'] = {
        set = function(_, v, n)
            if not v or not DoesEntityExist(v) then return false end
            exports['Renewed-Fuel']:SetFuel(v, n)
            return true
        end,
    },

    ['cdn-fuel']        = { set = viaClient },
    ['qb-fuel']         = { set = viaClient },
    ['LegacyFuel']      = { set = viaClient },
    ['myFuel']          = { set = viaClient },
    ['okokGasStation']  = { set = viaClient },
    ['qs-fuelstations'] = { set = viaClient },
    ['rcore_fuel']      = { set = viaClient },
    ['x-fuel']          = { set = viaClient },
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

local function setFuel(src, vehicle, amount)
    local name = provider()
    local p = PROVIDERS[name]
    if not p then
        print(('[codem-lib] Fuel.set: no fuel provider for "%s" - set LibConfig.Fuel.provider')
            :format(tostring(name)))
        return false
    end
    local ok, res = pcall(p.set, src, vehicle, amount)
    if not ok then
        print(('[codem-lib] Fuel.set via "%s" failed: %s'):format(name, tostring(res)))
        return false
    end
    return res ~= false
end

exports('SetFuel', setFuel)

-- Client-initiated set (client export falls back here for providers whose
-- API is server-side only).
RegisterNetEvent('codem-lib:fuel:setRequest', function(netId, amount)
    local src = source
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if vehicle ~= 0 then setFuel(src, vehicle, amount) end
end)
