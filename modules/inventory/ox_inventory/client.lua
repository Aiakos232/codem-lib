-- codem-lib inventory provider: ox_inventory (client)
-- Active only when this provider is selected.
if not LibInventoryActive('ox_inventory', 'ox_inventory') then return end

if LibConfig.Debug then
    print('[codem-lib] Inventory provider loaded: ox_inventory')
end

Inventory = {}

Inventory.openInventory = function(invType, data)
    exports['ox_inventory']:openInventory(invType, data)
end

Inventory.getItemCount = function(itemName, metadata)
    return exports['ox_inventory']:Search('count', itemName, metadata or nil)
end

Inventory.getItemData = function(itemName)
    local info = exports['ox_inventory']:Items(itemName)
    return info and {name = itemName, label = info.label, description = info.description, image = ('https://cfx-nui-ox_inventory/web/images/%s.png'):format(itemName)}
end

Inventory.getPlayerItems = function()
    return exports['ox_inventory']:GetPlayerItems()
end