-- codem-lib inventory provider: ak47_inventory (client)
-- Registered at load; the exports pick the active provider per call.
if LibConfig.Debug then
    print('[codem-lib] Inventory provider loaded: ak47_inventory')
end

local Inventory = {}
LibInventoryProviders['ak47_inventory'] = Inventory

Inventory.openInventory = function(invType, data)
    exports['ak47_inventory']:OpenInventory(data)
end

Inventory.getItemCount = function(itemName)
    return exports['ak47_inventory']:Search('amount', itemName)
end

Inventory.getItemData = function(itemName)
    local info = exports['ak47_inventory']:Items(itemName)
    return info and {name = itemName, label = info.label, description = info.description, image = ('https://cfx-nui-ak47_inventory/web/images/%s.png'):format(itemName)} or nil
end