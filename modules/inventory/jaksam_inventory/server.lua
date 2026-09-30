-- codem-lib inventory provider: jaksam_inventory (server)
-- Registered at load; the exports pick the active provider per call.
if LibConfig.Debug then
    print('[codem-lib] Inventory provider loaded: jaksam_inventory')
end

local Inventory = {}
LibInventoryProviders['jaksam_inventory'] = Inventory

--Whether an item can carry per-item metadata (info) through this bridge.
--Scripts that key an item to a thing (a room key, a vehicle key) ask this
--before trusting the item.
Inventory.supportsMetadata = true

--@param playerId: number [existing player id]
--@return items: table [{name: string, amount: number, metadata: table, slot: number}]
Inventory.getPlayerItems = function(playerId)
    return exports['jaksam_inventory']:getInventory(playerId)?.items or {}
end

--@param prefix: string [prefix for the drop]
--@param items: table [name: string, count: number, metadata: table]
--@param coords: vector3 [drop coordinates]
Inventory.CustomDrop = function(prefix, items, coords)
   print('[codem-lib] ' .. 'CustomDrop is not supported in jaksam_inventory, please change type in config')
end

--@param playerId: number [existing player id]
--@param itemName: string [item name]
--@param itemCount: number [amount of items to add]
--@param itemMetadata: table [item metadata, optional]
--@param itemSlot: number [item slot, optional]
Inventory.addItem = function(playerId, itemName, itemCount, itemMetadata, itemSlot)
    return exports['jaksam_inventory']:addItem(playerId, itemName, itemCount, itemMetadata, itemSlot)
end

--@param playerId: number [existing player id]
--@param itemName: string [item name]
--@param itemCount: number [amount of items to add]
--@param itemMetadata: table [item metadata, optional]
--@param itemSlot: number [item slot, optional]
Inventory.removeItem = function(playerId, itemName, itemCount, itemMetadata, itemSlot)
    return exports['jaksam_inventory']:removeItem(playerId, itemName, itemCount, itemMetadata, itemSlot)
end

--@param playerId: number [existing player id]
--@param itemName: string [item name]
--@param itemMetadata: table [item metadata, optional]
--@return count: number [amount of items in inventory]
Inventory.getItemCount = function(playerId, itemName, itemMetadata)
    return exports['jaksam_inventory']:getTotalItemAmount(playerId, itemName, itemMetadata)
end

Inventory.getItemSlot = function(playerId, slot)
    return exports['jaksam_inventory']:GetSlot(playerId, slot)
end

Inventory.createShop = function(shopName, data)
    while GetResourceState('jaksam_inventory') ~= 'started' do
        Citizen.Wait(100)
    end

    Citizen.Wait(100)
    exports['jaksam_inventory']:RegisterShop(shopName, data)
end
--@return catalog: table<string, { label: string, weight: number, image: string|nil }>
--Item metadata comes from the framework's shared table; only the picture
--folder is this inventory's own.
Inventory.itemCatalog = function()
    return LibFrameworkCatalog('nui://jaksam_inventory/html/images/')
end

--@param playerId: number
--@return capacity: { slots: number|nil, maxWeight: number|nil } [kg] or nil
Inventory.capacity = function(playerId)
    return LibPlayerCapacity(playerId)
end

--@param stashId: string|number
--@return items: table or nil when the stash is unknown
Inventory.stashItems = function(stashId)
    local inv = exports['jaksam_inventory']:getInventory(stashId)
    if type(inv) ~= 'table' then return nil end
    -- Sağlayıcıya göre ya doğrudan liste ya da `items` alanı dönüyor.
    return inv.items or inv
end

--jaksam takes an inventory id (player or stash) in addItem/removeItem.
Inventory.moveStash = function(fromId, toId)
    local jk = exports['jaksam_inventory']
    return LibMoveStashWith(fromId, toId, {
        items = function(id)
            local inv = jk:getInventory(id)
            return type(inv) == 'table' and (inv.items or inv) or nil
        end,
        add = function(id, name, count, meta) return jk:addItem(id, name, count, meta) ~= false end,
        remove = function(id, name, count, meta, slot) jk:removeItem(id, name, count, meta, slot) end,
    })
end

Inventory.openStashServer = function(src, stashId, invData)
    if type(stashId) ~= 'string' and type(stashId) ~= 'number' then return false end
    local jk = exports['jaksam_inventory']
    if not jk:getInventory(stashId) then
        local grams = invData and (invData.maxweight or invData.maxWeight or invData.weight)
        jk:createInventory(tostring(stashId), invData and invData.label or tostring(stashId), {
            maxWeight = grams and grams / 1000 or nil,
            maxSlots = invData and invData.slots or nil,
        }, nil, 'stash')
    end
    jk:forceOpenInventory(src, stashId)
    return true
end

Inventory.clearStash = function(stashId)
    return exports['jaksam_inventory']:clearInventory(stashId) == true
end

Inventory.resizeStash = function(stashId, slots, weight)
    if not weight then return false end
    return exports['jaksam_inventory']:setInventoryMaxWeight(stashId, weight / 1000) == true
end
