-- codem-lib inventory provider: tgiann-inventory (client)
-- Active only when this provider is selected.
if not LibInventoryActive('tgiann-inventory', 'tgiann-inventory') then return end

if LibConfig.Debug then
    print('[codem-lib] Inventory provider loaded: tgiann-inventory')
end

Inventory = {}

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