-- codem-lib inventory provider: core_inventory (client)
-- Active only when this provider is selected.
if not LibInventoryActive('core_inventory', 'core_inventory') then return end

if LibConfig.Debug then
    print('[codem-lib] Inventory provider loaded: core_inventory')
end

Inventory = {}

Inventory.openInventory = function(invType, data)
    if invType == 'player' then
        TriggerServerEvent('core_inventory:server:openInventory', data, 'otherplayer', nil, nil, true)
    elseif invType == 'shop' then
        print('[codem-lib] ' .. 'core_inventory doesnt have export to open shop')
    elseif invType == 'stash' then
        TriggerServerEvent('core_inventory:server:openInventory', data.owner and ('%s_%s'):format(data.id, data.owner) or data.id, 'stash')
    end
end

Inventory.getItemCount = function(itemName)
    return exports.core_inventory:getItemCount(itemName)
end

Inventory.getItemData = function(itemName)
    print('[codem-lib] ' .. 'core_inventory doesnt have export to get item data')
    return nil
end