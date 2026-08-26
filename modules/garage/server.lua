local sent = {}

local function running(name)
    return GetResourceState(name) == 'started'
end

local function provider()
    return exports['codem-lib']:GetGarageProvider()
end

local function garageName(id, pointId)
    return exports['codem-lib']:GarageName(id, pointId)
end

-- Rows arrive as the database left them: heading can be NULL, a coordinate
-- can be a string. vector3/vector4 take numbers only, so coerce once here.
local function spawnOf(x, y, z, heading)
    local h = (tonumber(heading) or 0.0) + 0.0
    local px = (tonumber(x) or 0.0) + 0.0
    local py = (tonumber(y) or 0.0) + 0.0
    local pz = (tonumber(z) or 0.0) + 0.0
    local rad = math.rad(h)
    return px + math.sin(rad) * 3.5, py + math.cos(rad) * 3.5, pz, h
end

local function pack4(x, y, z, w)
    if vector4 then return vector4(x, y, z, w) end
    return { x = x, y = y, z = z, w = w }
end

local function vehicleTypeOf(opts)
    return (opts and opts.vehicleType) or 'car'
end

local function qbxConfig(label, points, opts)
    local accessPoints = {}
    for i, p in ipairs(points) do
        local sx, sy, sz, sh = spawnOf(p.x, p.y, p.z, p.heading)
        accessPoints[i] = {
            coords = pack4(p.x, p.y, p.z, p.heading),
            spawn = pack4(sx, sy, sz, sh),
            dropPoint = pack4(sx, sy, sz, sh),
            useRadius = 0.05,
            dropUseRadius = 0.05,
            drawRadius = 0.05,
            dropDrawRadius = 0.05,
        }
    end
    local first = accessPoints[1]
    return {
        label = label or 'Garage',
        type = 'public',
        vehicleType = vehicleTypeOf(opts),
        accessPoints = accessPoints,
        coords = first and first.coords,
        spawn = first and first.spawn,
    }
end

local function registerQbx(lot, opts)
    if not running('qbx_garages') then return false end
    local name = garageName(lot.id or lot.motelId)
    if sent[name] then return true end
    local ok = pcall(function()
        exports.qbx_garages:RegisterGarage(name, qbxConfig(lot.label or lot.motelName, lot.points, opts))
    end)
    if not ok then return false end
    sent[name] = true
    return true
end

local function registerQb(point, opts)
    if not running('qb-garages') then return false end
    local name = garageName(point.motelId or point.lotId, point.id)
    if sent[name] then return true end
    local sx, sy, sz, sh = spawnOf(point.x, point.y, point.z, point.heading)
    -- qb-garages ignores spawnPoint and derives the spawn from takeVehicle,
    -- where `w` is not optional: vector4(x, y, z, nil) errors.
    TriggerClientEvent('qb-garages:client:addHouseGarage', -1, name, {
        takeVehicle = { x = sx, y = sy, z = sz, w = sh },
        spawnPoint = { { x = sx, y = sy, z = sz, w = sh } },
        label = (point.label ~= nil and point.label ~= '') and point.label or (point.motelName or 'Garage'),
        type = 'public',
        category = vehicleTypeOf(opts),
    })
    sent[name] = true
    return true
end

local function registerCd(point, opts)
    if not running('cd_garage') then return false end
    local name = garageName(point.motelId or point.lotId, point.id)
    if sent[name] then return true end
    local sx, sy, sz, sh = spawnOf(point.x, point.y, point.z, point.heading)
    local vtype = vehicleTypeOf(opts)
    TriggerEvent('cd_garage:PropertyGarage:Create', {
        garage_label = (point.label ~= nil and point.label ~= '') and point.label or (point.motelName or 'Garage'),
        allowed_vehicle_types = { vtype == 'car' and 'car' or vtype },
        coords = {
            open = {
                x = point.x, y = point.y, z = point.z,
                interact_distance = 0.05, view_distance = 15,
            },
            spawn = { x = sx, y = sy, z = sz, heading = sh },
        },
        blip = { enabled = false },
    })
    sent[name] = true
    return true
end

local function registerQs(point)
    if not running('qs-advancedgarages') then return false end
    local name = garageName(point.motelId or point.lotId, point.id)
    if sent[name] then return true end
    local sx, sy, sz, sh = spawnOf(point.x, point.y, point.z, point.heading)
    local ok = pcall(function()
        exports['qs-advancedgarages']:CreateGarage(name, {
            owner = false,
            available = true,
            type = 'vehicle',
            coords = {
                menuCoords = { x = point.x, y = point.y, z = point.z },
                spawnCoords = { x = sx, y = sy, z = sz, w = sh },
            },
            price = 0,
        })
    end)
    if not ok then return false end
    sent[name] = true
    return true
end

local function registerLot(lot, opts)
    local p = provider()
    if p == 'none' then return end
    local points = lot.points or {}
    if #points == 0 then return end
    lot.id = lot.id or lot.motelId
    if p == 'qbx_garages' then
        registerQbx(lot, opts)
        return
    end
    for i = 1, #points do
        local point = points[i]
        point.motelId = point.motelId or lot.motelId or lot.id
        point.motelName = point.motelName or lot.motelName or lot.label
        if p == 'qb-garages' then
            registerQb(point, opts)
        elseif p == 'cd_garage' then
            registerCd(point, opts)
        elseif p == 'qs-advancedgarages' then
            registerQs(point)
        end
    end
end

local function registerGarages(lots, opts)
    if provider() == 'none' then return false end
    if type(lots) ~= 'table' then return false end
    if lots.points then
        registerLot(lots, opts)
        return true
    end
    for i = 1, #lots do
        registerLot(lots[i], opts)
    end
    return true
end

local function reset()
    sent = {}
end

exports('RegisterGarages', registerGarages)
exports('ResetGarageRegistry', reset)

AddEventHandler('onResourceStop', function(resource)
    if resource == provider() then sent = {} end
end)
