local function provider()
    if CodemLib and CodemLib.Garage and CodemLib.Garage.Provider then
        return CodemLib.Garage.Provider()
    end
    return 'none'
end

local function currentVehicle()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh and veh ~= 0 then return veh end
    return nil
end

local function tryExport(resource, method, ...)
    if GetResourceState(resource) ~= 'started' then return false end
    local ok, result = pcall(function(...)
        return exports[resource][method](exports[resource], ...)
    end, ...)
    return ok and result ~= false
end

local function spawnOffset(spot)
    local heading = spot.heading or 0.0
    local sx = spot.x + math.sin(math.rad(heading)) * 3.5
    local sy = spot.y + math.cos(math.rad(heading)) * 3.5
    return sx, sy, spot.z, heading
end

local function parkQbx(garageName)
    local veh = currentVehicle()
    if not veh then return false, 'failed' end
    if not lib or not lib.callback then return false, 'failed' end
    local netId = NetworkGetNetworkIdFromEntity(veh)
    local parkable = lib.callback.await('qbx_garages:server:isParkable', false, garageName, netId)
    if not parkable then return false, 'not_owned' end
    local props = lib.getVehicleProperties and lib.getVehicleProperties(veh) or {}
    lib.callback.await('qbx_garages:server:parkVehicle', false, netId, props, garageName)
    return true
end

local function openQbx(spot)
    if currentVehicle() then
        return parkQbx(spot.garageName)
    end
    if not lib or not lib.callback then return false, 'failed' end
    local vehicles = lib.callback.await('qbx_garages:server:getGarageVehicles', false, spot.garageName)
    if type(vehicles) ~= 'table' or #vehicles == 0 then
        return false, 'empty'
    end
    local options = {}
    for i, vehicle in ipairs(vehicles) do
        local plate = vehicle.props and vehicle.props.plate or ''
        options[i] = {
            title = vehicle.modelName or plate or ('#' .. tostring(vehicle.id)),
            description = plate,
            icon = 'car',
            onSelect = function()
                lib.callback.await('qbx_garages:server:spawnVehicle', false,
                    vehicle.id, spot.garageName, spot.accessIndex or 1)
            end,
        }
    end
    local title = (spot.label ~= nil and spot.label ~= '') and spot.label or 'Garage'
    lib.registerContext({
        id = ('codem_garage_%s'):format(tostring(spot.id or spot.garageName)),
        title = title,
        options = options,
    })
    lib.showContext(('codem_garage_%s'):format(tostring(spot.id or spot.garageName)))
    return true
end

local function openQb(spot)
    if tryExport('qb-garages', 'openGarage', spot.garageName) then return true end
    if tryExport('qb-garages', 'OpenGarage', spot.garageName) then return true end
    TriggerEvent('qb-garages:client:openGarage', spot.garageName)
    TriggerEvent('qb-garage:client:openGarage', spot.garageName)
    if currentVehicle() then
        TriggerEvent('qb-garages:client:putInGarage')
        TriggerEvent('qb-garage:client:putAwayVehicle')
    end
    return true
end

local function openCd(spot)
    local sx, sy, sz, sh = spawnOffset(spot)
    local spawn = vector4 and vector4(sx, sy, sz, sh)
        or { x = sx, y = sy, z = sz, w = sh, h = sh }
    if currentVehicle() then
        TriggerEvent('cd_garage:PropertyGarage:StoreVehicle')
        return true
    end
    TriggerEvent('cd_garage:PropertyGarage:Open', spawn)
    return true
end

local function openQs(spot)
    if currentVehicle() then
        if tryExport('qs-advancedgarages', 'StoreVehicle') then return true end
        if tryExport('qs-advancedgarages', 'OpenGarageMenu', spot.garageName) then return true end
        return true
    end
    if tryExport('qs-advancedgarages', 'OpenGarageMenu', spot.garageName) then return true end
    return false, 'failed'
end

CodemLib = CodemLib or {}
CodemLib.Garage = CodemLib.Garage or {}

local function ensureName(spot)
    if spot.garageName then return end
    if CodemLib.Garage.Name then
        spot.garageName = CodemLib.Garage.Name(spot.motelId or spot.id, spot.id)
    end
end

function CodemLib.Garage.Bind(spot)
    if type(spot) ~= 'table' then return false end
    ensureName(spot)
    local p = spot.provider or provider()
    local sx, sy, sz, sh = spawnOffset(spot)
    if p == 'qb-garages' then
        TriggerEvent('qb-garages:client:addHouseGarage', spot.garageName, {
            takeVehicle = { x = spot.x, y = spot.y, z = spot.z },
            spawnPoint = { { x = sx, y = sy, z = sz, w = sh } },
            label = (spot.label ~= nil and spot.label ~= '') and spot.label or 'Garage',
            type = 'public',
        })
        return true
    elseif p == 'qs-advancedgarages' then
        pcall(function()
            exports['qs-advancedgarages']:CreateGarage(spot.garageName, {
                owner = false,
                available = true,
                type = 'vehicle',
                coords = {
                    menuCoords = vector3(spot.x, spot.y, spot.z),
                    spawnCoords = vector4(sx, sy, sz, sh),
                },
                price = 0,
            })
        end)
        return true
    end
    return true
end

function CodemLib.Garage.Open(spot)
    if type(spot) ~= 'table' then return false, 'failed' end
    ensureName(spot)
    local p = spot.provider or provider()
    if p == 'none' then return false, 'missing' end
    if GetResourceState(p) ~= 'started' then return false, 'missing' end
    if p == 'qbx_garages' then
        return openQbx(spot)
    elseif p == 'qb-garages' then
        return openQb(spot)
    elseif p == 'cd_garage' then
        return openCd(spot)
    elseif p == 'qs-advancedgarages' then
        return openQs(spot)
    end
    return false, 'failed'
end
