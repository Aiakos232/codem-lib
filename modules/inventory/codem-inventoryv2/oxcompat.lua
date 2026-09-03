--[[
    ox_inventory export names, answered on behalf of codem-inventoryv2.

    FiveM resolves `exports.ox_inventory:Name(...)` through the event
    `__cfx_export_ox_inventory_Name`; whoever answers it hands back the
    function. codem-lib answers here instead of codem-inventoryv2 itself on
    purpose: when the inventory calls into the framework (money sync) and the
    framework immediately calls `exports.ox_inventory:SetItem` back, the
    inventory's own runtime is still inside that outgoing call and cannot hand
    out a function reference. codem-lib is idle at that moment, so it can.

    Loaded on both sides; the list below is chosen by side.
]]

local TARGET = 'codem-inventoryv2'
local isServer = IsDuplicityVersion()

local NAMES = isServer and {
    'AddItem', 'CanCarryAmount', 'CanCarryItem', 'CanCarryWeight', 'CanSwapItem', 'ClearInventory', 'ConfiscateInventory',
    'CreateDropFromPlayer', 'CreateTemporaryStash', 'CustomDrop', 'GetContainerFromSlot', 'GetCurrentWeapon', 'GetEmptySlot',
    'GetInventory', 'GetInventoryItems', 'GetItem', 'GetItemCount', 'GetItemSlots', 'GetSlot', 'GetSlotForItem',
    'GetSlotIdWithItem', 'GetSlotIdsWithItem', 'GetSlotWithItem', 'GetSlotsWithItem', 'InspectInventory', 'Inventory',
    'ItemList', 'Items', 'RegisterShop', 'RegisterStash', 'RemoveInventory', 'RemoveItem', 'ReturnInventory', 'Search',
    'SetDurability', 'SetItem', 'SetMaxWeight', 'SetMetadata', 'SetSlotCount', 'SwapSlots', 'UpdateVehicle', 'addCash',
    'forceOpenInventory', 'getBank', 'getCards', 'getCash', 'giveCard', 'registerHook', 'removeHooks', 'setPlayerInventory',
    'CreateUsableItem', 'GetPlayerItems', 'ConvertItems', 'setContainerProperties',
} or {
    'CancelProgress', 'GetItemCount', 'GetPlayerItems', 'GetPlayerMaxWeight', 'GetPlayerWeight', 'GetSlotIdWithItem',
    'GetSlotWithItem', 'GetSlotsWithItem', 'ItemList', 'Items', 'Keyboard', 'Progress', 'ProgressActive', 'Search',
    'closeInventory', 'displayMetadata', 'getCurrentWeapon', 'giveItemToTarget', 'notify', 'openInventory',
    'openNearbyInventory', 'setStashTarget', 'suppressItemNotifications', 'useItem', 'useSlot', 'weaponWheel',
}

local active = false

--- Resolves every export once while nothing is on the stack, so later calls
--- never have to negotiate a function reference mid-call.
local function warm()
    if GetResourceState(TARGET) ~= 'started' then return end
    for _, name in ipairs(NAMES) do
        pcall(function() local _ = exports[TARGET][name] end)
    end
end

local function install()
    if active then return end
    -- nothing to alias on servers that do not ship codem-inventoryv2 at all
    if GetResourceState(TARGET) == 'missing' then return end
    -- a real ox_inventory owns its own name; through `provide` the lookup
    -- answers with codem-inventoryv2's manifest, so the name tells them apart
    if GetResourceMetadata('ox_inventory', 'name', 0) == 'ox_inventory' then return end
    active = true
    for _, name in ipairs(NAMES) do
        AddEventHandler(('__cfx_export_ox_inventory_%s'):format(name), function(setCallback)
            -- the export proxy is method-style: the first argument is `self`
            setCallback(function(...) return exports[TARGET][name](nil, ...) end)
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
