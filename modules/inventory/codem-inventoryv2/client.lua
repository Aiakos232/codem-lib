-- codem-lib inventory provider: codem-inventoryv2 (client)
-- Registered at load; the exports pick the active provider per call.
if LibConfig.Debug then
    print('[codem-lib] Inventory provider loaded: codem-inventoryv2')
end

local Inventory = {}
LibInventoryProviders['codem-inventoryv2'] = Inventory

Inventory.openInventory = function(invType, data)
    exports['codem-inventoryv2']:openInventory(invType, data)
end

Inventory.getItemCount = function(itemName, metadata)
    return exports['codem-inventoryv2']:Search('count', itemName, metadata or nil)
end

Inventory.getItemData = function(itemName)
    local info = exports['codem-inventoryv2']:Items(itemName)
    return info and {name = itemName, label = info.label, description = info.description, image = LibItemImage('https://cfx-nui-codem-inventoryv2/web/images/', itemName, info)}
end

Inventory.getPlayerItems = function()
    return exports['codem-inventoryv2']:GetPlayerItems()
end
---Open a stash by id. Returns true when handled client-side.
Inventory.openStash = function(stashId, invData)
    exports['codem-inventoryv2']:openInventory('stash', stashId)
    return true
end
---Register display labels for custom metadata keys, e.g.
---{ CodemPhoneName = 'Phone Name' }. Cosmetic; ox shows them in the tooltip.
Inventory.displayMetadata = function(map)
    exports['codem-inventoryv2']:displayMetadata(map)
end
