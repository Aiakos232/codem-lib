-- codem-lib inventory provider: origen_inventory (client)
-- Registered at load; the exports pick the active provider per call.
if LibConfig.Debug then
    print('[codem-lib] Inventory provider loaded: origen_inventory')
end

local Inventory = {}
LibInventoryProviders['origen_inventory'] = Inventory

Inventory.openInventory = function(invType, data)
    exports['origen_inventory']:openInventory(invType, data)
end

Inventory.getItemCount = function(itemName)
    return exports['origen_inventory']:Search('count', itemName)
end

Inventory.getItemData = function(itemName)
    local info = exports['origen_inventory']:Items(itemName)
    return info and {name = itemName, label = info.label, description = info.description, image = LibItemImage('https://cfx-nui-origen_inventory/ui/images/', itemName, info)}
end