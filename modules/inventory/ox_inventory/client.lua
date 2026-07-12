-- codem-lib inventory provider: ox_inventory (client)
-- Registered at load; the exports pick the active provider per call.
if LibConfig.Debug then
    print('[codem-lib] Inventory provider loaded: ox_inventory')
end

local Inventory = {}
LibInventoryProviders['ox_inventory'] = Inventory

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
---Open a stash by id. Returns true when handled client-side.
Inventory.openStash = function(stashId, invData)
    exports.ox_inventory:openInventory('stash', stashId)
    return true
end
