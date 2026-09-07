--[[
    qb-inventory export names, answered on behalf of codem-inventoryv2.

    Same mechanism as oxcompat.lua: `exports['qb-inventory']:Name(...)` resolves
    through the event `__cfx_export_qb-inventory_Name`, and codem-lib answers it
    (the inventory's own runtime may be mid-call into the framework at that
    moment). qb's argument orders differ from ox's, so every name maps to an
    adapter export `qb_<Name>` inside codem-inventoryv2 rather than to the ox
    export of the same name.

    Loaded on both sides; the list below is chosen by side.
]]

local TARGET = 'codem-inventoryv2'
local isServer = IsDuplicityVersion()

local NAMES = isServer and {
    'AddItem', 'RemoveItem', 'HasItem', 'GetItemBySlot', 'GetItemByName', 'GetItemsByName', 'GetSlotsByItem',
    'GetFirstSlotByItem', 'GetTotalWeight', 'GetFreeWeight', 'GetSlots', 'CanAddItem', 'ClearInventory', 'SetInventory',
    'SetItemData', 'GetInventory', 'LoadInventory', 'SaveInventory', 'OpenInventory', 'OpenInventoryById',
    'CloseInventory', 'CreateInventory', 'RemoveInventory', 'RegisterStash', 'GetStashItems', 'CreateShop', 'OpenShop',
    'CreateUsableItem', 'UseItem',
} or {
    'HasItem', 'GetItemByName', 'GetPlayerItems',
}

local active = false

local function warm()
    if GetResourceState(TARGET) ~= 'started' then return end
    for _, name in ipairs(NAMES) do
        pcall(function() local _ = exports[TARGET]['qb_' .. name] end)
    end
end

local function install()
    if active then return end
    if GetResourceState(TARGET) == 'missing' then return end
    -- a real qb-inventory owns its own name; through `provide` the lookup
    -- answers with codem-inventoryv2's manifest, so the name tells them apart
    local owner = GetResourceMetadata('qb-inventory', 'name', 0)
    if owner and owner ~= '' and owner ~= TARGET then return end
    active = true
    for _, name in ipairs(NAMES) do
        AddEventHandler(('__cfx_export_qb-inventory_%s'):format(name), function(setCallback)
            -- the export proxy is method-style: the first argument is `self`
            setCallback(function(...) return exports[TARGET]['qb_' .. name](nil, ...) end)
        end)
    end
end

install()
warm()

AddEventHandler('onResourceStart', function(resource)
    if resource == TARGET then
        install()
        SetTimeout(0, warm)
    end
end)
