-- codem-lib inventory provider: tgiann-inventory (client)
-- Registered at load; the exports pick the active provider per call.
if LibConfig.Debug then
    print('[codem-lib] Inventory provider loaded: tgiann-inventory')
end

local Inventory = {}
LibInventoryProviders['tgiann-inventory'] = Inventory

Inventory.openInventory = function(invType, data)
    TriggerServerEvent('codem-lib:inventory:openInventory', invType, data)
end

Inventory.getItemCount = function(itemName)
    return exports['tgiann-inventory']:Search('count', itemName)
end

Inventory.getItemData = function(itemName)
    local info = exports["tgiann-inventory"]:Items(itemName)
    return info and {name = itemName, label = info.label, description = info.description, image = ('nui://inventory_images/images/%s.png'):format(itemName)}
end
---tgiann stashes are opened server-side; the caller must route through its
---own (validated) server event and call OpenStashServer there.
Inventory.openStash = function(stashId, invData)
    return false
end
