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

-- A spot arrives as the database left it: heading can be NULL, a coordinate
-- can be a string. vector3/vector4 take numbers only, so coerce once here.
local function spawnOffset(spot)
    local heading = (tonumber(spot.heading) or 0.0) + 0.0
    local x = (tonumber(spot.x) or 0.0) + 0.0
    local y = (tonumber(spot.y) or 0.0) + 0.0
    local z = (tonumber(spot.z) or 0.0) + 0.0
    local rad = math.rad(heading)
    return x + math.sin(rad) * 3.5, y + math.cos(rad) * 3.5, z, heading
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

-- Config.VehicleClass['all'] in qb-garages. Only read when Config.ClassSystem
-- is on, and a nil category crashes its filter.
local QB_ALL_CLASSES = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22 }

local FUEL_RESOURCES = {
    'LegacyFuel', 'cdn-fuel', 'qb-fuel', 'lc_fuel', 'Renewed-Fuel', 'ox_fuel',
    'myFuel', 'okokGasStation', 'qs-fuelstations', 'rcore_fuel', 'x-fuel',
}

local function qbCore()
    if GetResourceState('qb-core') ~= 'started' then return nil end
    local ok, core = pcall(function() return exports['qb-core']:GetCoreObject() end)
    if ok and type(core) == 'table' then return core end
    return nil
end

local function qbAwait(core, name, ...)
    local p = promise.new()
    core.Functions.TriggerCallback(name, function(...) p:resolve(table.pack(...)) end, ...)
    local r = Citizen.Await(p)
    return table.unpack(r, 1, r.n)
end

local function readFuel(vehicle)
    for i = 1, #FUEL_RESOURCES do
        local res = FUEL_RESOURCES[i]
        if GetResourceState(res) == 'started' then
            local ok, level = pcall(function() return exports[res]:GetFuel(vehicle) end)
            if ok and type(level) == 'number' then return level end
        end
    end
    return GetVehicleFuelLevel(vehicle) + 0.0
end

-- qb-menu drives its entries through events, not closures.
local qbPick = nil
AddEventHandler('codem-lib:client:garagePick', function(index)
    if qbPick then qbPick(index) end
end)

local function qbList(id, title, entries, onPick)
    if lib and lib.registerContext then
        local options = {}
        for i, e in ipairs(entries) do
            options[i] = {
                title = e.title,
                description = e.description,
                icon = 'car',
                onSelect = function() onPick(i) end,
            }
        end
        lib.registerContext({ id = id, title = title, options = options })
        lib.showContext(id)
        return true
    end
    if GetResourceState('qb-menu') == 'started' then
        qbPick = onPick
        local menu = { { header = title, isMenuHeader = true } }
        for i, e in ipairs(entries) do
            menu[#menu + 1] = {
                header = e.title,
                txt = e.description,
                params = { event = 'codem-lib:client:garagePick', args = i },
            }
        end
        exports['qb-menu']:openMenu(menu)
        return true
    end
    return false
end

local function parkQb(spot, core, vehicle)
    local plate = core.Functions.GetPlate(vehicle)
    if not plate or plate == '' then return false, 'failed' end

    if not qbAwait(core, 'qb-garages:server:canDeposit', plate, 'public', spot.garageName, 1) then
        return false, 'not_owned'
    end

    TriggerServerEvent('qb-garages:server:updateVehicleStats', plate, readFuel(vehicle),
        math.ceil(GetVehicleEngineHealth(vehicle)), math.ceil(GetVehicleBodyHealth(vehicle)))
    if GetResourceState('qb-mechanicjob') == 'started' then
        TriggerServerEvent('qb-mechanicjob:server:SaveVehicleProps', core.Functions.GetVehicleProperties(vehicle))
    end
    TriggerServerEvent('qb-garages:server:UpdateOutsideVehicle', plate, 0)

    for seat = -1, 5 do
        local ped = GetPedInVehicleSeat(vehicle, seat)
        if ped ~= 0 then TaskLeaveVehicle(ped, vehicle, 0) end
    end
    Wait(1500)
    core.Functions.DeleteVehicle(vehicle)
    return true
end

local function openQb(spot)
    local core = qbCore()
    if not core then return false, 'failed' end

    local vehicle = currentVehicle()
    if vehicle then return parkQb(spot, core, vehicle) end

    local rows = qbAwait(core, 'qb-garages:server:GetGarageVehicles', spot.garageName, 'public', QB_ALL_CLASSES)
    if type(rows) ~= 'table' then return false, 'empty' end

    local vehicles, entries = {}, {}
    for _, v in ipairs(rows) do
        if tonumber(v.state) == 1 then
            local shared = core.Shared and core.Shared.Vehicles and core.Shared.Vehicles[v.vehicle]
            local name = (shared and shared.name) or v.vehicle
            if shared and shared.brand then name = shared.brand .. ' ' .. shared.name end
            vehicles[#vehicles + 1] = v
            entries[#entries + 1] = { title = name, description = v.plate }
        end
    end
    if #vehicles == 0 then return false, 'empty' end

    local sx, sy, sz, sh = spawnOffset(spot)
    local spawn = vector4(sx, sy, sz, sh)
    local id = ('codem_garage_%s'):format(tostring(spot.id or spot.garageName))
    local title = (spot.label ~= nil and spot.label ~= '') and spot.label or 'Garage'

    local shown = qbList(id, title, entries, function(index)
        local v = vehicles[index]
        if not v then return end
        TriggerEvent('qb-garages:client:takeOutGarage', {
            garage = { spawnPoint = { spawn } },
            plate = v.plate,
            vehicle = v.vehicle,
            type = 'public',
            stats = {
                fuel = tonumber(v.fuel) or 100.0,
                engine = tonumber(v.engine) or 1000.0,
                body = tonumber(v.body) or 1000.0,
            },
        })
    end)
    if not shown then return false, 'failed' end
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
            takeVehicle = { x = sx, y = sy, z = sz, w = sh },
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
