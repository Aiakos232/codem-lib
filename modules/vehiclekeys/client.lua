--[[
    Vehicle keys (client) — every provider in one file. Selection via LibConfig.VehicleKeys.provider
    ('auto' picks the first running resource).

    Exports:
      GiveKeys(vehicle, plate?)
      RestoreKeys(vehicle, plate?)  -- a garage handing back a stored vehicle; falls back to give
      RemoveKeys(vehicle, plate?)

    Providers that need a server export (qbx_vehiclekeys, ND_Core) fall back
    to codem-lib's own server events.
]]

local function plateOf(vehicle, plate)
    if plate then return plate end
    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
        return GetVehicleNumberPlateText(vehicle)
    end
    return nil
end

local function trimmed(plate)
    return plate and tostring(plate):gsub('^%s+', ''):gsub('%s+$', ''):upper() or nil
end

local asked, answers = 0, {}

RegisterNetEvent('codem-lib:vkeys:plate', function(ticket, plate)
    answers[ticket] = plate or false
end)

local function serverPlate(netId)
    asked = asked + 1
    local ticket = asked
    TriggerServerEvent('codem-lib:vkeys:plate', netId, ticket)
    local deadline = GetGameTimer() + 1000
    while answers[ticket] == nil and GetGameTimer() < deadline do Wait(0) end
    local plate = answers[ticket]
    answers[ticket] = nil
    return plate or nil
end

local known = {}

RegisterNetEvent('codem-lib:vkeys:known', function(ticket, yes)
    known[ticket] = yes == true
end)

local function keyExists(plate)
    asked = asked + 1
    local ticket = asked
    TriggerServerEvent('codem-lib:vkeys:known', plate, ticket)
    local deadline = GetGameTimer() + 2000
    while known[ticket] == nil and GetGameTimer() < deadline do Wait(0) end
    local yes = known[ticket]
    known[ticket] = nil
    if yes == nil then return true end
    return yes
end

local function settled(vehicle, plate)
    local want = trimmed(plate)
    local deadline = GetGameTimer() + 8000
    while GetGameTimer() < deadline do
        if not DoesEntityExist(vehicle) then return false end
        local netId = NetworkGetNetworkIdFromEntity(vehicle)
        if netId ~= 0 and NetworkDoesEntityExistWithNetworkId(netId) then
            if not want then return true end
            if trimmed(GetVehicleNumberPlateText(vehicle)) == want then
                if trimmed(serverPlate(netId)) == want then return true end
            end
        end
        Wait(250)
    end
    return false
end

local function viaServer(event)
    return function(v)
        TriggerServerEvent(event, NetworkGetNetworkIdFromEntity(v))
    end
end

-- v = vehicle entity, p = plate. `false` = action not supported.
local PROVIDERS = {
    ['qbx_vehiclekeys'] = {
        give   = viaServer('codem-lib:vkeys:give'),
        remove = viaServer('codem-lib:vkeys:remove'),
    },

    ['qb-vehiclekeys'] = {
        give   = function(v, p) TriggerServerEvent('qb-vehiclekeys:server:AcquireVehicleKeys', plateOf(v, p)) end,
        remove = function(v, p) TriggerEvent('qb-vehiclekeys:client:RemoveKeys', plateOf(v, p)) end,
    },

    ['wasabi_carlock'] = {
        give   = function(v, p) exports['wasabi_carlock']:GiveKey(plateOf(v, p)) end,
        remove = function(v, p) exports['wasabi_carlock']:RemoveKey(plateOf(v, p)) end,
    },

    ['Renewed-Vehiclekeys'] = {
        give   = function(v, p) exports['Renewed-Vehiclekeys']:addKey(plateOf(v, p)) end,
        remove = function(v, p) exports['Renewed-Vehiclekeys']:removeKey(plateOf(v, p)) end,
    },

    ['MrNewbVehicleKeys'] = {
        give   = function(v, p) exports.MrNewbVehicleKeys:GiveKeysByPlate(plateOf(v, p)) end,
        remove = function(v, p) exports.MrNewbVehicleKeys:RemoveKeysByPlate(plateOf(v, p)) end,
    },

    ['vehicles_keys'] = {
        give   = function(v, p) TriggerServerEvent('vehicles_keys:selfGiveVehicleKeys', plateOf(v, p)) end,
        remove = function(v, p) TriggerServerEvent('vehicles_keys:selfRemoveKeys', plateOf(v, p)) end,
    },

    ['tgiann-hotwire'] = {
        give    = function(v, p) exports['tgiann-hotwire']:GiveKeyPlate(plateOf(v, p), true) end,
        restore = function(v, p)
            if not settled(v, p) then return end
            local plate = plateOf(v, p)
            if not keyExists(trimmed(plate)) then
                exports['tgiann-hotwire']:GiveKeyPlate(plate, true)
                return
            end
            exports['tgiann-hotwire']:CheckKeyInIgnitionWhenSpawn(v)

            local deadline = GetGameTimer() + 3000
            while GetGameTimer() < deadline and DoesEntityExist(v) do
                if Entity(v).state.keyInIgnition then
                    SetVehicleDoorsLocked(v, 1)
                    return
                end
                Wait(100)
            end
        end,
        remove  = function(v) exports['tgiann-hotwire']:SetKeyInIgnition(v, false) end,
    },

    ['0r-vehiclekeys'] = {
        give   = function(v, p) exports['0r-vehiclekeys']:GiveKeys(plateOf(v, p)) end,
        remove = function(v, p) exports['0r-vehiclekeys']:RemoveKeys(plateOf(v, p)) end,
    },

    ['LifeSaver_KeySystem'] = {
        give   = function(v, p)
            exports['LifeSaver_KeySystem']:AddCarkey(plateOf(v, p), GetDisplayNameFromVehicleModel(GetEntityModel(v)))
        end,
        remove = function(v, p)
            exports['LifeSaver_KeySystem']:RemoveCarkey(plateOf(v, p), GetDisplayNameFromVehicleModel(GetEntityModel(v)))
        end,
    },

    ['ak47_qb_vehiclekeys'] = {
        give   = function(v, p) exports['ak47_qb_vehiclekeys']:GiveKey(plateOf(v, p), not NetworkGetEntityIsNetworked(v)) end,
        remove = function(v, p) exports['ak47_qb_vehiclekeys']:RemoveKey(plateOf(v, p), not NetworkGetEntityIsNetworked(v)) end,
    },

    ['ak47_vehiclekeys'] = {
        give   = function(v, p) exports['ak47_vehiclekeys']:GiveKey(plateOf(v, p), not NetworkGetEntityIsNetworked(v)) end,
        remove = function(v, p) exports['ak47_vehiclekeys']:RemoveKey(plateOf(v, p), not NetworkGetEntityIsNetworked(v)) end,
    },

    ['brutal_carkeys'] = {
        give   = function(v, p) exports.brutal_keys:addVehicleKey(plateOf(v, p), 'car') end,
        remove = function(v, p) exports.brutal_keys:removeKey(plateOf(v, p), true) end,
    },

    ['filo_vehiclekey'] = {
        give   = function(v, p) exports.filo_vehiclekey:GiveKeys(plateOf(v, p)) end,
        remove = function(v, p) exports.filo_vehiclekey:RemoveKeys(plateOf(v, p)) end,
    },

    ['ic3d_vehiclekeys'] = {
        give   = function(v, p) exports.ic3d_vehiclekeys:ClientInventoryKeys('add', plateOf(v, p)) end,
        remove = function(v, p) exports.ic3d_vehiclekeys:ClientInventoryKeys('remove', plateOf(v, p)) end,
    },

    ['is_vehiclekeys'] = {
        give   = function(v, p) exports['is_vehiclekeys']:GiveKey(plateOf(v, p)) end,
        remove = function(v, p) exports['is_vehiclekeys']:RemoveKey(plateOf(v, p)) end,
    },

    ['mk_vehiclekeys'] = {
        give   = function(v)
            if NetworkGetEntityIsNetworked(v) then
                exports['mk_vehiclekeys']:AddKey(v)
            else
                Entity(v).state:set('Keys', { LocalPlayer.state.mk_identifier }, true)
            end
        end,
        remove = function(v)
            if NetworkGetEntityIsNetworked(v) then
                exports['mk_vehiclekeys']:RemoveKey(v)
            else
                Entity(v).state:set('Keys', {}, true)
            end
        end,
    },

    ['mm_carkeys'] = {
        give   = function(v, p) exports.mm_carkeys:GiveKeyItem(plateOf(v, p), v) end,
        remove = function(v, p) exports.mm_carkeys:RemoveKeyItem(plateOf(v, p)) end,
    },

    ['p_carkeys'] = {
        give   = function(v, p) TriggerServerEvent('p_carkeys:CreateKeys', plateOf(v, p)) end,
        remove = function(v, p) TriggerServerEvent('p_carkeys:RemoveKeys', plateOf(v, p)) end,
    },

    ['qs-vehiclekeys'] = {
        give   = function(v, p)
            exports['qs-vehiclekeys']:GiveKeys(plateOf(v, p), GetDisplayNameFromVehicleModel(GetEntityModel(v)), true)
        end,
        remove = function(v, p)
            exports['qs-vehiclekeys']:RemoveKeys(plateOf(v, p), GetDisplayNameFromVehicleModel(GetEntityModel(v)))
        end,
    },

    ['rd_vehiclekeys'] = {
        give   = function(v, p) TriggerServerEvent('rd_vehiclekeys:server:GiveKeys', plateOf(v, p)) end,
        remove = function(v, p) TriggerServerEvent('rd_vehiclekeys:server:RemoveKeys', plateOf(v, p)) end,
    },

    ['mVehicle'] = {
        give   = function(v) exports.mVehicle:AddTemporalVehicleClient(v) end,
        remove = false, -- mVehicle does not support taking keys back
    },

    ['okokGarage'] = {
        give   = function(v, p) TriggerServerEvent('okokGarage:GiveKeys', plateOf(v, p)) end,
        remove = function(v, p) TriggerServerEvent('okokGarage:RemoveKeys', plateOf(v, p), GetPlayerServerId(PlayerId())) end,
    },

    ['cd_garage'] = {
        give   = function(v, p) TriggerEvent('cd_garage:AddKeys', plateOf(v, p)) end,
        remove = false, -- cd_garage does not support taking keys back
    },

    ['ND_Core'] = {
        give   = viaServer('codem-lib:vkeys:give'),
        remove = viaServer('codem-lib:vkeys:remove'),
    },
}

-- 'auto' detection order — first running resource wins.
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

local function dispatch(verb, vehicle, plate)
    local name = provider()
    local p = PROVIDERS[name]
    if not p then
        print(('[codem-lib] Keys.%s: no vehicle key provider for "%s" - set LibConfig.VehicleKeys.provider')
            :format(verb, tostring(name)))
        return false
    end
    if verb == 'restore' and not p.restore then verb = 'give' end
    local fn = p[verb]
    if not fn then
        print(('[codem-lib] Keys.%s: provider "%s" does not support this action'):format(verb, name))
        return false
    end
    local ok, err = pcall(fn, vehicle, plate)
    if not ok then
        print(('[codem-lib] Keys.%s via "%s" failed: %s'):format(verb, name, tostring(err)))
        return false
    end
    return true
end

exports('GiveKeys', function(vehicle, plate) return dispatch('give', vehicle, plate) end)
exports('RestoreKeys', function(vehicle, plate) return dispatch('restore', vehicle, plate) end)
exports('RemoveKeys', function(vehicle, plate) return dispatch('remove', vehicle, plate) end)

-- The server forwards here when the active provider only has a client API.
RegisterNetEvent('codem-lib:vkeys:apply', function(verb, netId, plate)
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if vehicle ~= 0 and (verb == 'give' or verb == 'remove') then
        dispatch(verb, vehicle, plate)
    end
end)
