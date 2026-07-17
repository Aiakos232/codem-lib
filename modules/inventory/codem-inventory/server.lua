-- codem-lib inventory provider: codem-inventory (server)
-- Registered at load; the exports pick the active provider per call.
if LibConfig.Debug then
    print('[codem-lib] Inventory provider loaded: codem-inventory')
end

local Inventory = {}
LibInventoryProviders['codem-inventory'] = Inventory

--@return boolean [codem-inventory has no reliable carry-weight export; allow]
Inventory.canCarry = function(playerId, itemName, itemCount)
    return true
end

--@param playerId: number [existing player id]
--@return items: table [{name: string, amount: number, metadata: table, slot: number}]
Inventory.getPlayerItems = function(playerId)
    local identifier = LibGetUniqueId(playerId)
    return exports['codem-inventory']:GetInventory(identifier, playerId)
end

--@param prefix: string [prefix for the drop]
--@param items: table [name: string, count: number, metadata: table]
--@param coords: vector3 [drop coordinates]
Inventory.CustomDrop = function(prefix, items, coords)
    print('[codem-lib] ' .. 'CustomDrop is not supported in codem-inventory, please change type in config')
end

--@param playerId: number [existing player id]
--@param itemName: string [item name]
--@param itemCount: number [amount of items to add]
--@param itemMetadata: table [item metadata, optional]
--@param itemSlot: number [item slot, optional]
Inventory.addItem = function(playerId, itemName, itemCount, itemMetadata, itemSlot)
    exports['codem-inventory']:AddItem(playerId, itemName, itemCount, itemSlot, itemMetadata)
end

--@param playerId: number [existing player id]
--@param itemName: string [item name]
--@param itemCount: number [amount of items to remove]
--@param itemMetadata: table [item metadata, optional]
--@param itemSlot: number [item slot, optional]
Inventory.removeItem = function(playerId, itemName, itemCount, itemMetadata, itemSlot)
    exports['codem-inventory']:RemoveItem(playerId, itemName, itemCount, itemSlot)
end

--@param playerId: number [existing player id]
--@param itemName: string [item name]
--@param itemMetadata: table [item metadata, optional]
--@return count: number [amount of items in inventory]
Inventory.getItemCount = function(playerId, itemName, itemMetadata)
    if itemMetadata then
        local items = exports['codem-inventory']:GetInventory(playerId)
        for k, v in pairs(items) do
            if v.name == itemName and v.info and CodemTableMatches(v.info, itemMetadata) then
                return v.amount
            end
        end
    else
        return exports['codem-inventory']:GetItemsTotalAmount(playerId, itemName)
    end

    return 0
end

--@param playerId: number [existing player id]
--@param slot: number [item slot]
--@return item: {name: string, label: string, amount: number, metadata: table}
Inventory.getItemSlot = function(playerId, slot)
    local itemData = exports['codem-inventory']:GetItemBySlot(playerId, slot)
    return itemData and {name = itemData.name, label = itemData.label, amount = itemData.amount, metadata = itemData.info or {}} or nil
end