--[[
    tgiann-inventory export names, answered on behalf of codem-inventoryv2.

    Same mechanism as oxcompat.lua and qbcompat.lua: `exports['tgiann-inventory']:Name(...)`
    resolves through the event `__cfx_export_tgiann-inventory_Name`, and codem-lib
    answers it while the inventory's own runtime may be busy. tgiann's argument
    orders are its own, so every name maps to an adapter export `tgiann_<Name>`
    inside codem-inventoryv2 rather than to the ox export of the same name.

    Loaded on both sides; the list below is chosen by side.
]]

local TARGET = 'codem-inventoryv2'
local isServer = IsDuplicityVersion()

local NAMES = isServer and {
    'AddItem', 'RemoveItem', 'GetItem', 'HasItem', 'GetPlayerInventory', 'GetPlayerItems', 'GetClotheInventory',
    'GetPlayerCarryItem', 'GetInventory', 'AddItemToInventory', 'RemoveItemFromInventory', 'SetInventoryItem',
    'ClearInventory', 'ValidateItemSlot', 'RegisterStash', 'OpenStash', 'OpenShop', 'RegisterUsableItem',
    'registerUsableItem', 'CreateUsableItem', 'createUsableItem', 'UseItem', 'IsArmorItem', 'CreateDrop', 'RemoveDrop',
    'GetAllDrops', 'RegisterCraft', 'ConvertRawItemsJson', 'MigratePlayerInventory',
} or {
    'GetPlayerItems', 'GetPlayerClotheItems', 'GetPlayerWeight', 'GetPlayerMaxWeight', 'GetItemCount', 'GetItemByName',
    'GetItemsByName', 'GetSlotWithItem', 'GetSlotsWithItem', 'GetSlotIdWithItem', 'GetSlotIdsWithItem', 'Search',
    'HasItem', 'IsDecayableItem', 'OpenInventory', 'openInventory', 'CloseInventory', 'closeInventory', 'UseItem',
    'useItem', 'UseSlot', 'useSlot', 'GiveItemToTarget', 'giveItemToTarget', 'DisplayMetadata', 'displayMetadata',
    'DisplayItemMetadata', 'displayItemMetadata', 'GetCurrentWeapon', 'getCurrentWeapon', 'LastWeaponData',
    'ResetWeaponDataForDrop', 'SetCurrentWeapon', 'RemoveWeapon', 'IsInventoryOpen', 'IsInventoryActive',
    'SetInventoryActive', 'SetCanUseItem', 'IsCarryingItem', 'GetCarryItemData', 'throwIsActive', 'ToggleHotbar',
    'SetFastSlotsEnable', 'FastSlotAddItem', 'FastSlotRemoveItem', 'FastSlotRemoveAllSlots',
}

local active = false

--- Resolves every export once while nothing is on the stack, so later calls
--- never have to negotiate a function reference mid-call.
local function warm()
    if GetResourceState(TARGET) ~= 'started' then return end
    for _, name in ipairs(NAMES) do
        pcall(function() local _ = exports[TARGET]['tgiann_' .. name] end)
    end
end

local function install()
    if active then return end
    if GetResourceState(TARGET) == 'missing' then return end
    -- a real tgiann-inventory owns its own name; through `provide` the lookup
    -- answers with codem-inventoryv2's manifest, so the name tells them apart.
    -- A tgiann folder that is only lying there (stopped, kept for its items or
    -- its config) owns nothing: the names are still answered here.
    local owner = GetResourceMetadata('tgiann-inventory', 'name', 0)
    local foreign = owner and owner ~= '' and owner ~= TARGET
    if foreign and GetResourceState('tgiann-inventory') == 'started' then return end
    active = true
    for _, name in ipairs(NAMES) do
        AddEventHandler(('__cfx_export_tgiann-inventory_%s'):format(name), function(setCallback)
            -- the export proxy is method-style: the first argument is `self`
            setCallback(function(...) return exports[TARGET]['tgiann_' .. name](nil, ...) end)
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
