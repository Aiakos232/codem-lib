-- codem-lib inventory provider: ox_inventory (server)
-- Registered at load; the exports pick the active provider per call.
if LibConfig.Debug then
    print('[codem-lib] Inventory provider loaded: ox_inventory')
end

local Inventory = {}
LibInventoryProviders['ox_inventory'] = Inventory

--@param playerId: number [existing player id]
--@return items: table [{name: string, amount: number, metadata: table, slot: number}]
Inventory.getPlayerItems = function(playerId)
    return exports['ox_inventory']:GetInventoryItems(playerId)
end

--@param prefix: string [prefix for the drop]
--@param items: table [name: string, count: number, metadata: table]
--@param coords: vector3 [drop coordinates]
Inventory.CustomDrop = function(prefix, items, coords)
    exports['ox_inventory']:CustomDrop(prefix, items, coords)
end

--@param playerId: number [existing player id]
--@param itemName: string [item name]
--@param itemCount: number [amount of items to add]
--@param itemMetadata: table [item metadata, optional]
--@param itemSlot: number [item slot, optional]
Inventory.addItem = function(playerId, itemName, itemCount, itemMetadata, itemSlot)
    exports['ox_inventory']:AddItem(playerId, itemName, itemCount, itemMetadata, itemSlot)
end

--@param playerId: number [existing player id]
--@param itemName: string [item name]
--@param itemCount: number [amount of items to add]
--@param itemMetadata: table [item metadata, optional]
--@param itemSlot: number [item slot, optional]
Inventory.removeItem = function(playerId, itemName, itemCount, itemMetadata, itemSlot)
    exports['ox_inventory']:RemoveItem(playerId, itemName, itemCount, itemMetadata, itemSlot)
end

--@param playerId: number [existing player id]
--@param itemName: string [item name]
--@param itemMetadata: table [item metadata, optional]
--@return count: number [amount of items in inventory]
Inventory.getItemCount = function(playerId, itemName, itemMetadata)
    return exports['ox_inventory']:Search(playerId, 'count', itemName, itemMetadata)
end

Inventory.getItemSlot = function(playerId, slot)
    return exports['ox_inventory']:GetSlot(playerId, slot)
end

Inventory.createShop = function(shopName, data)
    while GetResourceState('ox_inventory') ~= 'started' do
        Citizen.Wait(100)
    end

    Citizen.Wait(100)
    exports['ox_inventory']:RegisterShop(shopName, data)
end
---Register a stash. groups: { [job] = minGrade } map.
Inventory.registerStash = function(stashId, label, slots, weight, groups, coords, opts)
    -- (ox_inventory has no item whitelist parameter; restrictions are
    -- inventory-specific and simply ignored here.)
    exports.ox_inventory:RegisterStash(stashId, label, slots, weight, nil, groups, coords)
    return true
end

---Server-side stash open; ox opens client-side, nothing to do.
Inventory.openStashServer = function(src, stashId, invData)
    return false
end
