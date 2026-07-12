--[[
    Target bridge (client) — ox_target and qb-target behind one API.
    The API contract is ox_target's; when qb-target is active, zones/options
    are converted on the fly.

    Loaded into the CONSUMER's own context (options carry functions, which
    should not cross resource exports):
        client_scripts { '@codem-lib/modules/target/client.lua' }
    then:
        Target.addBoxZone({ name, coords, size, rotation, options = {...} })
        Target.addLocalEntity(entity, options)
        Target.removeZone(id) ...

    Provider: LibConfig.Target.provider or the consumer's Config.Target,
    'auto' picks ox_target first, then qb-target.
]]

-- Pull the lib config into this context if the consumer did not load it.
if type(LibConfig) ~= 'table' then
    local cfg = LoadResourceFile('codem-lib', 'config.lua')
    if cfg then
        local fn = load(cfg, '@@codem-lib/config.lua')
        if fn then fn() end
    end
end

local FW_TARGET = (type(LibConfig) == 'table' and LibConfig.Target and LibConfig.Target.provider)
    or (type(Config) == 'table' and Config.Target)
    or 'auto'
if FW_TARGET == 'auto' then
    if GetResourceState('ox_target') == 'started' then
        FW_TARGET = 'ox_target'
    elseif GetResourceState('qb-target') == 'started' then
        FW_TARGET = 'qb-target'
    end
end

Target = Target or {}

--------------------------------------------------------------------------------
-- ox_target — straight proxy (the API contract is ox_target's own)
--------------------------------------------------------------------------------

if FW_TARGET == 'ox_target' then
    local ox_target = exports.ox_target

    function Target.removeZone(zoneId) ox_target:removeZone(zoneId) end
    function Target.addBoxZone(payload) return ox_target:addBoxZone(payload) end
    function Target.addSphereZone(payload) return ox_target:addSphereZone(payload) end
    function Target.addLocalEntity(entities, options) return ox_target:addLocalEntity(entities, options) end
    function Target.removeLocalEntity(entities, optionNames) return ox_target:removeLocalEntity(entities, optionNames) end
    function Target.addEntity(netIds, options) ox_target:addEntity(netIds, options) end
    function Target.removeEntity(netIds, optionNames) ox_target:removeEntity(netIds, optionNames) end
    function Target.addGlobalPed(options) ox_target:addGlobalPed(options) end
    function Target.removeGlobalPed(optionNames) ox_target:removeGlobalPed(optionNames) end
    function Target.addGlobalPlayer(options) ox_target:addGlobalPlayer(options) end
    function Target.removeGlobalPlayer(optionNames) ox_target:removeGlobalPlayer(optionNames) end
    function Target.addGlobalVehicle(options) ox_target:addGlobalVehicle(options) end
    function Target.removeGlobalVehicle(optionNames) ox_target:removeGlobalVehicle(optionNames) end
    function Target.addModel(models, options) ox_target:addModel(models, options) end
    function Target.removeModel(models, optionNames) ox_target:removeModel(models, optionNames) end
    function Target.disableTargeting(disable) ox_target:disableTargeting(disable) end

    return
end

--------------------------------------------------------------------------------
-- qb-target — ox-shaped payloads converted to qb-target's format
--------------------------------------------------------------------------------

if FW_TARGET ~= 'qb-target' then
    print('[codem-lib] Target: no target provider running (ox_target / qb-target) - set LibConfig.Target.provider')
    return
end

local qb_target = exports['qb-target']

-- qb-target removes options by LABEL while the ox contract removes by NAME;
-- remember every name -> label mapping we register.
local namesToLabels = {}

local function generateUUID()
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return (template:gsub('[xy]', function(c)
        local v = (c == 'x') and math.random(0, 15) or math.random(8, 11)
        return string.format('%x', v)
    end))
end

local function split(inputstr, sep)
    sep = sep or '%s'
    local t = {}
    for str in string.gmatch(inputstr, '([^' .. sep .. ']+)') do
        t[#t + 1] = str
    end
    return t
end

---Accepts a value, an array or a key-value table; returns an array.
local function convertToArray(data)
    if type(data) ~= 'table' then
        return { data }
    end
    local key = next(data)
    if type(key) == 'string' then
        local arr = {}
        for k in pairs(data) do arr[#arr + 1] = k end
        return arr
    end
    return data
end

---Collect the qb labels registered for the given ox option name(s).
local function labelsFor(optionNames)
    local labels = {}
    if type(optionNames) == 'string' then
        if namesToLabels[optionNames] then labels[#labels + 1] = namesToLabels[optionNames] end
    else
        for i = 1, #optionNames do
            if namesToLabels[optionNames[i]] then labels[#labels + 1] = namesToLabels[optionNames[i]] end
        end
    end
    return labels
end

local function convertOptionsFromOxTarget(payload)
    local options = {}

    local function formatQbOption(zone, o)
        local option = {
            type = o.event and 'client' or o.serverEvent and 'server' or o.export and 'export' or 'client',
            event = o.event or o.serverEvent,
            icon = o.icon,
            item = o.items,
            label = o.label,
        }

        if o.canInteract then
            option.canInteract = o.canInteract
        end

        if o.onSelect then
            option.action = function(entity)
                local coords = zone.coords
                if entity and DoesEntityExist(entity) then
                    coords = GetEntityCoords(entity)
                end
                local distance = #(GetEntityCoords(PlayerPedId()) - coords)
                o.onSelect({
                    entity = entity,
                    coords = coords,
                    distance = distance,
                    zone = zone.name,
                })
            end
        end

        if not o.onSelect and o.export then
            option.action = function(entity)
                local coords = zone.coords
                if entity and DoesEntityExist(entity) then
                    coords = GetEntityCoords(entity)
                end
                local distance = #(GetEntityCoords(PlayerPedId()) - coords)
                local exportInfo = split(o.export, '.')
                exports[exportInfo[1]][exportInfo[2]](nil, {
                    entity = entity,
                    coords = coords,
                    distance = distance,
                    zone = zone.name,
                })
            end
        end

        return option
    end

    for i = 1, #payload.options do
        local o = payload.options[i]

        namesToLabels[o.name] = o.label

        if o.groups then
            local jobs = convertToArray(o.groups)
            for j = 1, #jobs do
                local index = #options + 1
                options[index] = formatQbOption(payload, o)
                options[index].job = jobs[j]
            end
        else
            options[#options + 1] = formatQbOption(payload, o)
        end
    end

    return options
end

function Target.removeZone(zoneId)
    qb_target:RemoveZone(zoneId)
end

function Target.addBoxZone(payload)
    local sizeZ = payload.size.z / 2.0
    local minZ, maxZ = (payload.coords.z - sizeZ), (payload.coords.z + sizeZ)

    qb_target:AddBoxZone(payload.name, payload.coords, payload.size.x, payload.size.y, {
        name = payload.name,
        heading = payload.rotation or 0,
        debugPoly = payload.debug,
        minZ = minZ,
        maxZ = maxZ,
    }, {
        options = convertOptionsFromOxTarget(payload),
        distance = 2.5,
    })

    return payload.name
end

function Target.addSphereZone(payload)
    local size = payload.radius / 2.0
    local minZ, maxZ = (payload.coords.z - size), (payload.coords.z + size)

    qb_target:AddBoxZone(payload.name, payload.coords, size, size, {
        name = payload.name,
        heading = 0,
        debugPoly = payload.debug,
        minZ = minZ,
        maxZ = maxZ,
    }, {
        options = convertOptionsFromOxTarget(payload),
        distance = 2.5,
    })

    return payload.name
end

function Target.addLocalEntity(entities, options)
    qb_target:AddTargetEntity(entities, {
        options = convertOptionsFromOxTarget({ name = generateUUID(), options = options }),
        distance = 2.5,
    })
end

function Target.removeLocalEntity(entities, optionNames)
    local labels = labelsFor(optionNames)
    if #labels == 0 then return end
    qb_target:RemoveTargetEntity(entities, labels)
end

local function netIdsToEntities(netIds)
    local entities = {}
    if type(netIds) ~= 'table' then
        entities[1] = NetworkGetEntityFromNetworkId(netIds)
    else
        for i = 1, #netIds do
            entities[i] = NetworkGetEntityFromNetworkId(netIds[i])
        end
    end
    return entities
end

function Target.addEntity(netIds, options)
    qb_target:AddTargetEntity(netIdsToEntities(netIds), {
        options = convertOptionsFromOxTarget({ name = generateUUID(), options = options }),
        distance = 2.5,
    })
end

function Target.removeEntity(netIds, optionNames)
    local labels = labelsFor(optionNames)
    if #labels == 0 then return end
    qb_target:RemoveTargetEntity(netIdsToEntities(netIds), labels)
end

function Target.addGlobalPed(options)
    qb_target:AddGlobalPed({
        options = convertOptionsFromOxTarget({ name = generateUUID(), options = options }),
        distance = 2.5,
    })
end

function Target.removeGlobalPed(optionNames)
    local labels = labelsFor(optionNames)
    if #labels == 0 then return end
    qb_target:RemoveGlobalPed(labels)
end

function Target.addGlobalPlayer(options)
    qb_target:AddGlobalPlayer({
        options = convertOptionsFromOxTarget({ name = generateUUID(), options = options }),
        distance = 2.5,
    })
end

function Target.removeGlobalPlayer(optionNames)
    local labels = labelsFor(optionNames)
    if #labels == 0 then return end
    qb_target:RemoveGlobalPlayer(labels)
end

function Target.addGlobalVehicle(options)
    qb_target:AddGlobalVehicle({
        options = convertOptionsFromOxTarget({ name = generateUUID(), options = options }),
        distance = 2.5,
    })
end

function Target.removeGlobalVehicle(optionNames)
    local labels = labelsFor(optionNames)
    if #labels == 0 then return end
    qb_target:RemoveGlobalVehicle(labels)
end

function Target.addModel(models, options)
    qb_target:AddTargetModel(models, {
        options = convertOptionsFromOxTarget({ name = generateUUID(), options = options }),
        distance = 2.5,
    })
end

function Target.removeModel(models, optionNames)
    local labels = labelsFor(optionNames)
    if #labels == 0 then return end
    qb_target:RemoveTargetModel(models, labels)
end

function Target.disableTargeting(disable)
    qb_target:AllowTargeting(not disable)
end
