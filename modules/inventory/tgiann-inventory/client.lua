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
    return info and
        {
            name = itemName,
            label = info.label,
            description = info.description,
            image = LibItemImage('nui://inventory_images/images/', itemName, info)
        }
end
---tgiann stashes open server-side; hand the id and size over and let the
---server call OpenInventory. Returns true: handled.
Inventory.openStash = function(stashId, invData)
    TriggerServerEvent('codem-lib:inventory:openStash', stashId, invData)
    return true
end
---Register display labels for custom metadata keys, e.g.
---{ CodemPhoneName = 'Phone Name' }. Cosmetic; tgiann shows them on the item.
Inventory.displayMetadata = function(map)
    exports['tgiann-inventory']:DisplayMetadata(map)
end
