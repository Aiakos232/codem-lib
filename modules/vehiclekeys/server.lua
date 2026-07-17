--[[
    Vehicle keys (server) — every provider in one file. Selection via LibConfig.VehicleKeys.provider
    ('auto' picks the first running resource).

    Exports:
      GiveKeys(src, vehicle, plate?)
      RemoveKeys(src, vehicle, plate?)
]]

local function plateOf(vehicle, plate)
    if plate then return plate end
    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
        return GetVehicleNumberPlateText(vehicle)
    end
    return nil
end

-- ND_Core init is loaded lazily, only when the provider is actually used.
-- (Reads ND_Core's own init.lua directly, so it works without ox_lib.)
local ndLoaded = false
local function ndInit()
    if ndLoaded then return end
    NDCore = NDCore or {}
    local chunk = LoadResourceFile('ND_Core', 'init.lua')
    if chunk then
        local fn = load(chunk, '@@ND_Core/init.lua')
        if fn then fn() end
    end
    ndLoaded = true
end

-- a = src, v = vehicle entity, p = plate. `false` = action not supported.
local PROVIDERS = {
    ['qbx_vehiclekeys'] = {
        give   = function(a, v) exports['qbx_vehiclekeys']:GiveKeys(a, v) end,
        remove = function(a, v) exports['qbx_vehiclekeys']:RemoveKeys(a, v) end,
    },

    ['qb-vehiclekeys'] = {
        give   = function(a, v, p) exports['qb-vehiclekeys']:GiveKeys(a, plateOf(v, p)) end,
        remove = function(a, v, p) exports['qb-vehiclekeys']:RemoveKeys(a, plateOf(v, p)) end,
    },

    ['wasabi_carlock'] = {
        give   = function(a, v, p) exports['wasabi_carlock']:GiveKey(plateOf(v, p), a) end,
        remove = function(a, v, p) exports['wasabi_carlock']:RemoveKey(plateOf(v, p), a) end,
    },

    ['Renewed-Vehiclekeys'] = {
        give   = function(a, v, p) exports['Renewed-Vehiclekeys']:addKey(a, plateOf(v, p)) end,
        remove = function(a, v, p) exports['Renewed-Vehiclekeys']:removeKey(a, plateOf(v, p)) end,
    },

    ['MrNewbVehicleKeys'] = {
        give   = function(a, v, p) exports.MrNewbVehicleKeys:GiveKeysByPlate(a, plateOf(v, p)) end,
        remove = function(a, v, p) exports.MrNewbVehicleKeys:RemoveKeysByPlate(a, plateOf(v, p)) end,
    },

    ['vehicles_keys'] = {
        give   = function(a, v, p) exports['vehicles_keys']:giveVehicleKeysToPlayerId(a, plateOf(v, p), 'temporary') end,
        remove = function(a, v, p) exports['vehicles_keys']:removeKeysFromPlayerId(a, plateOf(v, p)) end,
    },

    ['tgiann-hotwire'] = {
        give   = function(_, v) exports['tgiann-hotwire']:SetKeyInIgnition(nil, v, true) end,
        remove = function(_, v) exports['tgiann-hotwire']:SetKeyInIgnition(nil, v, false) end,
    },

    ['mVehicle'] = {
        give   = function(a, v) exports.mVehicle.AddTemporalVehicle(a, v) end,
        remove = false, -- mVehicle does not support taking keys back
    },

    ['okokGarage'] = {
        give   = function(a, v, p) TriggerEvent('okokGarage:GiveKeys', plateOf(v, p)) end,
        remove = function(a, v, p) TriggerEvent('okokGarage:RemoveKeys', plateOf(v, p), a) end,
    },

    ['cd_garage'] = {
        give   = function(a, v, p) TriggerClientEvent('cd_garage:AddKeys', a, plateOf(v, p)) end,
        remove = false, -- cd_garage does not support taking keys back
    },

    ['ND_Core'] = {
        give   = function(a, v) ndInit() NDCore.giveVehicleAccess(a, v, true) end,
        remove = function(a, v) ndInit() NDCore.giveVehicleAccess(a, v, false) end,
    },
}

-- 'auto' detection order — first running resource wins. Entries without a
-- server implementation above are forwarded to the target player's client.
local CANDIDATES = {
    'qbx_vehiclekeys', 'qb-vehiclekeys', 'wasabi_carlock', 'Renewed-Vehiclekeys',
    'MrNewbVehicleKeys', 'vehicles_keys', 'tgiann-hotwire', 'mVehicle',
    'okokGarage', 'cd_garage', 'ND_Core',
    '0r-vehiclekeys', 'LifeSaver_KeySystem', 'ak47_qb_vehiclekeys', 'ak47_vehiclekeys',
    'brutal_carkeys', 'filo_vehiclekey', 'ic3d_vehiclekeys', 'is_vehiclekeys',
    'mk_vehiclekeys', 'mm_carkeys', 'p_carkeys', 'qs-vehiclekeys', 'rd_vehiclekeys',
}

local function provider()
    local cfg = (LibConfig.VehicleKeys and LibConfig.VehicleKeys.provider) or 'auto'
    if cfg ~= 'auto' then return cfg end
    for _, res in ipairs(CANDIDATES) do
        if GetResourceState(res) == 'started' then return res end
    end
    return 'none'
end

local function dispatch(verb, src, vehicle, plate)
    local name = provider()
    if name == 'none' then
        print(('[codem-lib] Keys.%s: no vehicle key provider running - set LibConfig.VehicleKeys.provider'):format(verb))
        return false
    end

    local p = PROVIDERS[name]
    if not p then
        -- Provider only has a client API (0r, ak47, brutal, qs...): apply it
        -- on the target player's client instead.
        if not src or not vehicle or not DoesEntityExist(vehicle) then return false end
        local netId = NetworkGetNetworkIdFromEntity(vehicle)
        if not netId or netId <= 0 then return false end
        TriggerClientEvent('codem-lib:vkeys:apply', src, verb, netId, plate)
        return true
    end
    local fn = p[verb]
    if not fn then
        print(('[codem-lib] Keys.%s: provider "%s" does not support this action'):format(verb, name))
        return false
    end
    local ok, err = pcall(fn, src, vehicle, plate)
    if not ok then
        print(('[codem-lib] Keys.%s via "%s" failed: %s'):format(verb, name, tostring(err)))
        return false
    end
    return true
end

---tgiann-hotwire's ignition system is a separate layer: put a key in the
---ignition on top of the main provider (when installed and not already it).
local function applyIgnition(vehicle)
    if LibConfig.VehicleKeys and LibConfig.VehicleKeys.hotwireIgnition == false then return end
    if provider() == 'tgiann-hotwire' then return end
    if GetResourceState('tgiann-hotwire') ~= 'started' then return end
    local netid = NetworkGetNetworkIdFromEntity(vehicle)
    pcall(function() exports['tgiann-hotwire']:SetKeyInIgnition(netid, vehicle, true) end)
end

local function giveKeys(src, vehicle, plate)
    local ok = dispatch('give', src, vehicle, plate)
    if ok and vehicle and vehicle ~= 0 then applyIgnition(vehicle) end
    return ok
end

local function removeKeys(src, vehicle, plate)
    return dispatch('remove', src, vehicle, plate)
end

exports('GiveKeys', giveKeys)
exports('RemoveKeys', removeKeys)

-- Providers that need a server export fall back to these events from the
-- client side (qbx_vehiclekeys / ND_Core): net id -> entity + source player.
RegisterNetEvent('codem-lib:vkeys:give', function(netId)
    local src = source
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if vehicle ~= 0 then giveKeys(src, vehicle) end
end)

RegisterNetEvent('codem-lib:vkeys:remove', function(netId)
    local src = source
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if vehicle ~= 0 then removeKeys(src, vehicle) end
end)
