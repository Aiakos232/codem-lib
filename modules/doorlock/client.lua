local STATE_UNLOCKED, STATE_LOCKED, STATE_RESET = 0, 1, 4

local TWO_32 = 4294967296
local INT32_MAX = 2147483647
local PUSH_RANGE = 8.0
local GARAGE_HOLD_RANGE = 35.0
local GARAGE_SEARCH = 12.0

local registered = {}
local lastLocked = {}
local idByKey = {}
local held = {}
local frozen = {}

local function gameModel(stored)
    local m = math.floor(tonumber(stored) or 0)
    if m > INT32_MAX then m = m - TWO_32 end
    return math.floor(m)
end

local function asVec(coords)
    if not coords then return nil end
    local x, y, z = coords.x, coords.y, coords.z
    if type(x) ~= 'number' then return nil end
    return vector3(x + 0.0, y + 0.0, z + 0.0)
end

local function provider()
    return exports['codem-lib']:GetDoorlockProvider()
end

local function existingSystemId(coords, model)
    local ok, a, b = pcall(function()
        return DoorSystemFindExistingDoor(coords.x, coords.y, coords.z, model)
    end)
    if not ok then return nil end
    if type(a) == 'boolean' then
        if a and type(b) == 'number' and b ~= 0 then return b end
        return nil
    end
    if type(a) == 'number' and a ~= 0 then return a end
    return nil
end

local function closestEntity(coords, model, radius)
    local ok, ent = pcall(GetClosestObjectOfType,
        coords.x, coords.y, coords.z, radius or 4.0, model, false, false, false)
    if ok and type(ent) == 'number' and ent ~= 0 and DoesEntityExist(ent) then
        if GetEntityModel(ent) == model then return ent end
    end
    return nil
end

local function inDoorSystem(hash)
    local ok, yes = pcall(IsDoorRegisteredWithSystem, hash)
    return ok and yes and true or false
end

local function resolveId(coords, model, ours, radius)
    local entity = closestEntity(coords, model, radius)
    local id = existingSystemId(coords, model)
    if id then return id, true, entity end
    if inDoorSystem(model) then
        return model, true, entity
    end
    return ours, false, entity
end

local function killAuto(id)
    pcall(DoorSystemSetAutomaticDistance, id, 0.0, false, false)
    pcall(DoorSystemSetAutomaticRate, id, 0.0, false, false)
    pcall(DoorSystemSetHoldOpen, id, false)
end

local function lockClosest(model, coords, locked)
    pcall(SetStateOfClosestDoorOfType,
        model, coords.x, coords.y, coords.z,
        locked and true or false, 0.0, false)
end

local function setFrozen(entity, freeze)
    if not entity or not DoesEntityExist(entity) then return end
    if freeze then
        frozen[entity] = true
        FreezeEntityPosition(entity, true)
    else
        frozen[entity] = nil
        FreezeEntityPosition(entity, false)
    end
end

local function isWide(model, entity)
    if entity and DoesEntityExist(entity) then
        local nameOk, name = pcall(GetEntityArchetypeName, entity)
        if nameOk and type(name) == 'string' then
            local n = name:lower()
            if n:find('garage', 1, true) or n:find('garagedoor', 1, true)
                or n:find('slide', 1, true) then
                return true
            end
        end
    end
    local ok, minDim, maxDim = pcall(GetModelDimensions, model)
    if not ok or not minDim or not maxDim then return false end
    return math.max(maxDim.x - minDim.x, maxDim.y - minDim.y) >= 2.2
end

local function seatOnHinge(entity, coords, heading)
    if not entity or not DoesEntityExist(entity) then return end
    local at = GetEntityCoords(entity)
    if #(at - coords) > 0.4 then
        SetEntityCoordsNoOffset(entity, coords.x, coords.y, coords.z, false, false, false)
        if heading then SetEntityHeading(entity, heading + 0.0) end
    end
    setFrozen(entity, true)
end

local function unfreezeAround(coords, model)
    local ent = closestEntity(coords, model, GARAGE_SEARCH)
    if ent then setFrozen(ent, false) end
    for entity in pairs(frozen) do
        if not DoesEntityExist(entity) then
            frozen[entity] = nil
        elseif GetEntityModel(entity) == model
            and #(GetEntityCoords(entity) - coords) < GARAGE_SEARCH then
            setFrozen(entity, false)
        end
    end
end

local function pinShut(h)
    if not h or not h.key or held[h.key] ~= h then return end

    if h.wide then
        local ent = h.entity
        if not (ent and DoesEntityExist(ent)) then
            ent = closestEntity(h.coords, h.model, GARAGE_SEARCH)
            h.entity = ent
        end
        killAuto(h.id)
        if h.id ~= h.model and inDoorSystem(h.model) then
            killAuto(h.model)
        end
        if ent then
            local dist = #(GetEntityCoords(ent) - h.coords)
            if dist <= 0.4 then
                setFrozen(ent, true)
            elseif (GetGameTimer() - (h.lockedAt or 0)) > 900 then
                seatOnHinge(ent, h.coords, h.heading)
            end
        end
        return
    end

    local ent = h.entity
    if not (ent and DoesEntityExist(ent)) then
        ent = closestEntity(h.coords, h.model)
        h.entity = ent
    end

    killAuto(h.id)
    pcall(DoorSystemSetOpenRatio, h.id, 0.0, false, false)
    DoorSystemSetDoorState(h.id, STATE_LOCKED, false, false)
    lockClosest(h.model, h.coords, true)

    if ent then
        if h.heading then
            SetEntityHeading(ent, h.heading + 0.0)
        end
        setFrozen(ent, true)
    end
end

local function letGo(id, model, coords, entity, wide, doorKey)
    if doorKey then held[doorKey] = nil end
    unfreezeAround(coords, model)
    if entity then setFrozen(entity, false) end

    local at = coords
    if (not wide) and entity and DoesEntityExist(entity) then
        at = GetEntityCoords(entity)
    end

    DoorSystemSetDoorState(id, STATE_UNLOCKED, false, false)
    if inDoorSystem(model) then
        DoorSystemSetDoorState(model, STATE_UNLOCKED, false, false)
    end
    lockClosest(model, at, false)

    if wide then
        pcall(DoorSystemSetAutomaticDistance, id, 30.0, false, false)
        pcall(DoorSystemSetAutomaticRate, id, 10.0, false, false)
        if id ~= model and inDoorSystem(model) then
            pcall(DoorSystemSetAutomaticDistance, model, 30.0, false, false)
            pcall(DoorSystemSetAutomaticRate, model, 10.0, false, false)
        end
    end
end

local function writeNative(id, model, coords, entity, wide, locked, slam, heading, doorKey)
    if locked then
        killAuto(id)
        if slam and not wide then
            DoorSystemSetDoorState(id, STATE_RESET, false, false)
        end
        pcall(DoorSystemSetOpenRatio, id, 0.0, false, false)
        DoorSystemSetDoorState(id, STATE_LOCKED, false, false)
        if not wide then
            lockClosest(model, coords, true)
        end
        if wide and id ~= model and inDoorSystem(model) then
            killAuto(model)
        end
        if entity and not wide then
            if heading then SetEntityHeading(entity, heading + 0.0) end
            setFrozen(entity, true)
        end
        if doorKey then
            held[doorKey] = {
                key = doorKey,
                id = id,
                model = model,
                coords = coords,
                heading = heading,
                entity = entity,
                wide = wide,
                lockedAt = GetGameTimer(),
            }
        end
    else
        letGo(id, model, coords, entity, wide, doorKey)
    end
end

local function applyOx(door)
    if GetResourceState('ox_doorlock') ~= 'started' then return false end
    local ok, existing = pcall(function()
        return exports.ox_doorlock:getDoorFromName(door.key)
    end)
    if not ok or type(existing) ~= 'table' or not existing.id then return false end
    local locked = door.locked and 1 or 0
    local setOk = pcall(function()
        exports.ox_doorlock:setDoorState(existing.id, locked)
    end)
    return setOk
end

local function applyQb(door)
    if GetResourceState('qb-doorlock') ~= 'started' then return false end
    local locked = door.locked and true or false
    local ok = pcall(function()
        TriggerEvent('qb-doorlock:client:setState', door.key, locked)
    end)
    return ok
end

local function applyNative(door)
    if not door.key or not door.model then return false end
    local coords = asVec(door.coords)
    if not coords then return false end

    local model = gameModel(door.model)
    local ours = joaat(door.key)
    local wideGuess = isWide(model)
    local id, inSystem, entity = resolveId(
        coords, model, ours, wideGuess and GARAGE_SEARCH or 4.0)
    local heading = tonumber(door.heading)
    local wide = isWide(model, entity)
    local settled = inSystem or (entity ~= nil)

    if not settled and not wide then
        return false
    end

    if inSystem and idByKey[door.key] and idByKey[door.key] ~= id then
        local stale = idByKey[door.key]
        if stale ~= id then
            pcall(RemoveDoorFromSystem, stale)
            registered[stale] = nil
            lastLocked[stale] = nil
        end
    end
    idByKey[door.key] = id

    if not registered[id] then
        if not inSystem then
            local at = coords
            if entity and not wide then
                at = GetEntityCoords(entity)
            end
            AddDoorToSystem(id, model, at.x, at.y, at.z, false, false, false)
        end
        registered[id] = true
    end

    local locked = door.locked and true or false
    local quiet = door.quiet and true or false
    local hashChanged = lastLocked[id] == nil

    if lastLocked[id] == locked then
        if locked and door.key then
            local prev = held[door.key]
            held[door.key] = {
                key = door.key,
                id = id, model = model, coords = coords,
                heading = heading, entity = entity, wide = wide,
                lockedAt = (prev and prev.lockedAt) or GetGameTimer(),
            }
            pinShut(held[door.key])
        else
            letGo(id, model, coords, entity, wide, door.key)
        end
        return true
    end

    writeNative(id, model, coords, entity, wide, locked, (not quiet) or hashChanged, heading, door.key)
    lastLocked[id] = locked
    return true
end

local function apply(door)
    if not door then return false end
    local ok = applyNative(door)

    local p = provider()
    if p == 'ox_doorlock' then
        applyOx(door)
    elseif p == 'qb-doorlock' then
        applyQb(door)
    end
    return ok
end

local function applyLeaves(leaves, locked)
    if type(leaves) ~= 'table' then return end
    for i = 1, #leaves do
        local leaf = leaves[i]
        apply({
            key = leaf.key,
            model = leaf.model,
            coords = leaf.coords,
            heading = leaf.heading,
            locked = locked,
        })
    end
end

local function clear()
    for entity in pairs(frozen) do
        if DoesEntityExist(entity) then
            FreezeEntityPosition(entity, false)
        end
    end
    frozen = {}
    registered = {}
    lastLocked = {}
    idByKey = {}
    held = {}
end

CreateThread(function()
    while true do
        if not next(held) then
            Wait(500)
        else
            local ped = PlayerPedId()
            local pos = ped ~= 0 and GetEntityCoords(ped) or nil
            local pushing = false
            if pos then
                for _, h in pairs(held) do
                    local range = h.wide and GARAGE_HOLD_RANGE or PUSH_RANGE
                    if #(pos - h.coords) <= range then
                        pushing = true
                        pinShut(h)
                    end
                end
            end
            Wait(pushing and 0 or 400)
        end
    end
end)

exports('ApplyDoorlock', apply)
exports('ApplyDoorlockLeaves', applyLeaves)
exports('ClearDoorlock', clear)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    clear()
end)
