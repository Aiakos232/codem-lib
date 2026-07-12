-- codem-lib inventory provider: origen_inventory (client)
-- Active only when this provider is selected.
if not LibInventoryActive('origen_inventory', 'origen_inventory') then return end

if LibConfig.Debug then
    print('[codem-lib] Inventory provider loaded: origen_inventory')
end

Inventory = {}

Inventory.openInventory = function(invType, data)
    exports['origen_inventory']:openInventory(invType, data)
end

Inventory.getItemCount = function(itemName)
    return exports['origen_inventory']:Search('count', itemName)
end

Inventory.getItemData = function(itemName)
    local info = exports['origen_inventory']:Items(itemName)
    return info and {name = itemName, label = info.label, description = info.description, image = ('https://cfx-nui-origen_inventory/ui/images/%s.png'):format(itemName)}
end