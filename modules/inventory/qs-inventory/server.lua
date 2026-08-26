-- codem-lib inventory provider: qs-inventory (server)
-- Registered at load; the exports pick the active provider per call.
if LibConfig.Debug then
    print('[codem-lib] Inventory provider loaded: qs-inventory')
end

local Inventory = {}
LibInventoryProviders['qs-inventory'] = Inventory

--Whether an item can carry per-item metadata (info) through this bridge.
--Scripts that key an item to a thing (a room key, a vehicle key) ask this
--before trusting the item.
Inventory.supportsMetadata = true

--@return boolean [can the player carry itemCount of itemName]
Inventory.canCarry = function(playerId, itemName, itemCount)
    return exports['qs-inventory']:CanCarryItem(playerId, itemName, itemCount) ~= false
end

--@param playerId: number [existing player id]
--@return items: table [{name: string, amount: number, metadata: table, slot: number}]
Inventory.getPlayerItems = function(playerId)
    return exports['qs-inventory']:GetInventory(playerId) or {}
end

--@param prefix: string [prefix for the drop]
--@param items: table [name: string, count: number, metadata: table]
--@param coords: vector3 [drop coordinates]
Inventory.CustomDrop = function(prefix, items, coords)
    print('[codem-lib] ' .. 'CustomDrop is not supported in qs-inventory, please change type in config')
end

--@param playerId: number [existing player id]
--@param itemName: string [item name]
--@param itemCount: number [amount of items to add]
--@param itemMetadata: table [item metadata, optional]
--@param itemSlot: number [item slot, optional]
Inventory.addItem = function(playerId, itemName, itemCount, itemMetadata, itemSlot)
    exports['qs-inventory']:AddItem(playerId, itemName, itemCount, itemSlot, itemMetadata)
end

--@param playerId: number [existing player id]
--@param itemName: string [item name]
--@param itemCount: number [amount of items to remove]
--@param itemMetadata: table [item metadata, optional]
--@param itemSlot: number [item slot, optional]
Inventory.removeItem = function(playerId, itemName, itemCount, itemMetadata, itemSlot)
    exports['qs-inventory']:RemoveItem(playerId, itemName, itemCount, itemSlot, itemMetadata)
end

--@param playerId: number [existing player id]
--@param itemName: string [item name]
--@param itemMetadata: table [item metadata, optional]
--@return count: number [amount of items in inventory]
Inventory.getItemCount = function(playerId, itemName, itemMetadata)
    if itemMetadata then
        local items = exports['qs-inventory']:GetInventory(playerId)
        for k, v in pairs(items) do
            if v.name == itemName and v.info and CodemTableMatches(v.info, itemMetadata) then
                return v.amount
            end
        end
    else
        return exports['qs-inventory']:GetItemTotalAmount(playerId, itemName)
    end

    return 0
end

--@param playerId: number [existing player id]
--@param slot: number [item slot]
--@return item: {name: string, label: string, amount: number, metadata: table}
Inventory.getItemSlot = function(playerId, slot)
    local items = exports['qs-inventory']:GetInventory(playerId)
    local itemData = items[slot]
    return itemData and {name = itemData.name, label = itemData.label, amount = itemData.amount, metadata = itemData.info or {}} or nil
end
--@return catalog: table<string, { label: string, weight: number, image: string|nil }>
--Item metadata comes from the framework's shared table; only the picture
--folder is this inventory's own.
Inventory.itemCatalog = function()
    return LibFrameworkCatalog('nui://qs-inventory/html/images/')
end

--@param playerId: number
--@return capacity: { slots: number|nil, maxWeight: number|nil } [kg] or nil
Inventory.capacity = function(playerId)
    return LibPlayerCapacity(playerId)
end

--@param stashId: string|number
--@return items: table or nil when the stash is unknown
Inventory.stashItems = function(stashId)
    local inv = exports['qs-inventory']:GetStashItems(stashId)
    if type(inv) ~= 'table' then return nil end
    -- Sağlayıcıya göre ya doğrudan liste ya da `items` alanı dönüyor.
    return inv.items or inv
end

--Stash items in and out through qs's own stash exports.
Inventory.moveStash = function(fromId, toId)
    local qs = exports['qs-inventory']
    return LibMoveStashWith(fromId, toId, {
        items = function(id) return qs:GetStashItems(id) end,
        add = function(id, name, count, meta) return qs:AddItemIntoStash(id, name, count, nil, meta) ~= false end,
        remove = function(id, name, count, _, slot) qs:RemoveItemIntoStash(id, name, count, slot) end,
    })
end
