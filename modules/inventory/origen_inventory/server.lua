-- codem-lib inventory provider: origen_inventory (server)
-- Registered at load; the exports pick the active provider per call.
if LibConfig.Debug then
    print('[codem-lib] Inventory provider loaded: origen_inventory')
end

local Inventory = {}
LibInventoryProviders['origen_inventory'] = Inventory

--Whether an item can carry per-item metadata (info) through this bridge.
--Scripts that key an item to a thing (a room key, a vehicle key) ask this
--before trusting the item.
Inventory.supportsMetadata = true

--@return boolean [can the player carry itemCount of itemName]
Inventory.canCarry = function(playerId, itemName, itemCount)
    return exports['origen_inventory']:canCarryItem(playerId, itemName, itemCount) ~= false
end

--@param playerId: number [existing player id]
--@return items: table [{name: string, amount: number, metadata: table, slot: number}]
Inventory.getPlayerItems = function(playerId)
    return exports['origen_inventory']:getInventoryItems(playerId)
end

--@param prefix: string [prefix for the drop]
--@param items: table [name: string, count: number, metadata: table]
--@param coords: vector3 [drop coordinates]
Inventory.CustomDrop = function(prefix, items, coords)
    print('[codem-lib] ' .. 'CustomDrop is not supported in origen_inventory, please change type in config')
end

Inventory.addItem = function(playerId, itemName, itemCount, itemMetadata, itemSlot)
    exports['origen_inventory']:addItem(playerId, itemName, itemCount, itemMetadata, itemSlot)
end

Inventory.removeItem = function(playerId, itemName, itemCount, itemMetadata, itemSlot)
    exports['origen_inventory']:removeItem(playerId, itemName, itemCount, itemMetadata, itemSlot)
end

Inventory.getItemCount = function(playerId, itemName, itemMetadata)
    return exports['origen_inventory']:getItemCount(playerId, itemName, itemMetadata)
end

Inventory.getItemSlot = function(playerId, slot)
    return exports['origen_inventory']:getSlot(playerId, slot)
end

Inventory.createShop = function(shopName, data)
    while GetResourceState('origen_inventory') ~= 'started' do
        Citizen.Wait(100)
    end
    exports['origen_inventory']:createShop(shopName, {
        label = data.name,
        slots = #data.inventory,
        items = data.inventory,
        locations = data.locations,
    })
end
--@return catalog: table<string, { label: string, weight: number, image: string|nil }>
--Item metadata comes from the framework's shared table; only the picture
--folder is this inventory's own.
Inventory.itemCatalog = function()
    return LibFrameworkCatalog('nui://origen_inventory/html/images/')
end

--@param playerId: number
--@return capacity: { slots: number|nil, maxWeight: number|nil } [kg] or nil
Inventory.capacity = function(playerId)
    return LibPlayerCapacity(playerId)
end

--@param stashId: string|number
--@return items: table or nil when the stash is unknown
Inventory.stashItems = function(stashId)
    local inv = exports['origen_inventory']:getInventoryItems(stashId)
    if type(inv) ~= 'table' then return nil end
    -- Sağlayıcıya göre ya doğrudan liste ya da `items` alanı dönüyor.
    return inv.items or inv
end

--origen takes an inventory id (player or stash) in addItem/removeItem.
Inventory.moveStash = function(fromId, toId)
    local og = exports['origen_inventory']
    return LibMoveStashWith(fromId, toId, {
        items = function(id) return og:getInventoryItems(id) end,
        add = function(id, name, count, meta) return og:addItem(id, name, count, meta) ~= false end,
        remove = function(id, name, count, meta, slot) og:removeItem(id, name, count, meta, slot) end,
    })
end
