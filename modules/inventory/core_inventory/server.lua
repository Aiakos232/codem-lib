-- codem-lib inventory provider: core_inventory (server)
-- Registered at load; the exports pick the active provider per call.
if LibConfig.Debug then
    print('[codem-lib] Inventory provider loaded: codem-inventory')
end

local Inventory = {}
LibInventoryProviders['core_inventory'] = Inventory

--Whether an item can carry per-item metadata (info) through this bridge.
--Scripts that key an item to a thing (a room key, a vehicle key) ask this
--before trusting the item.
Inventory.supportsMetadata = true

--@param playerId: number [existing player id]
--@return items: table [{name: string, amount: number, metadata: table, slot: number}]
Inventory.getPlayerItems = function(playerId)
    local items = exports['core_inventory']:getItems(playerId)
    return items
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
    return exports['core_inventory']:addItem(playerId, itemName, itemCount, itemMetadata)
end

--@param playerId: number [existing player id]
--@param itemName: string [item name]
--@param itemCount: number [amount of items to remove]
--@param itemMetadata: table [item metadata, optional]
--@param itemSlot: number [item slot, optional]
Inventory.removeItem = function(playerId, itemName, itemCount, itemMetadata, itemSlot)
    return exports['core_inventory']:removeItem(playerId, itemName, itemCount)
end

--@param playerId: number [existing player id]
--@param itemName: string [item name]
--@param itemMetadata: table [item metadata, optional]
--@return count: number [amount of items in inventory]
Inventory.getItemCount = function(playerId, itemName, itemMetadata)
    return exports.core_inventory:getItemCount(playerId, itemName)
end

--@param playerId: number [existing player id]
--@param slot: number [item slot]
--@return item: {name: string, label: string, amount: number, metadata: table}
Inventory.getItemSlot = function(playerId, slot)
    local itemData = exports.core_inventory:getItemBySlot(playerId, slot)
    return itemData and {name = itemData.name, label = itemData.label, amount = itemData.amount, metadata = itemData.metadata or {}} or nil
end
--@return catalog: table<string, { label: string, weight: number, image: string|nil }>
--Item metadata comes from the framework's shared table; only the picture
--folder is this inventory's own.
Inventory.itemCatalog = function()
    return LibFrameworkCatalog('nui://core_inventory/html/img/')
end

--@param playerId: number
--@return capacity: { slots: number|nil, maxWeight: number|nil } [kg] or nil
Inventory.capacity = function(playerId)
    return LibPlayerCapacity(playerId)
end

--@param stashId: string|number
--@return items: table or nil when the stash is unknown
Inventory.stashItems = function(stashId)
    local inv = exports['core_inventory']:getInventory(stashId)
    if type(inv) ~= 'table' then return nil end
    -- Sağlayıcıya göre ya doğrudan liste ya da `items` alanı dönüyor.
    return inv.items or inv
end

--core_inventory addresses a stash by its inventory name in the same
--addItem/removeItem it uses for players.
Inventory.moveStash = function(fromId, toId)
    local core = exports['core_inventory']
    return LibMoveStashWith(fromId, toId, {
        items = function(id)
            local inv = core:getInventory(id)
            return type(inv) == 'table' and (inv.items or inv) or nil
        end,
        add = function(id, name, count, meta) return core:addItem(id, name, count, meta) ~= false end,
        remove = function(id, name, count) core:removeItem(id, name, count) end,
    })
end

Inventory.openStashServer = function(src, stashId, invData)
    if type(stashId) ~= 'string' and type(stashId) ~= 'number' then return false end
    exports['core_inventory']:openInventory(src, tostring(stashId), 'stash', invData and invData.label or nil, nil, true)
    return true
end

Inventory.clearStash = function(stashId)
    exports['core_inventory']:clearInventory(tostring(stashId))
    return true
end

Inventory.resizeStash = function(stashId, slots, weight)
    if not slots then return false end
    exports['core_inventory']:updateInventorySize(tostring(stashId), slots, 10)
    return true
end

local function storedName(characterId)
    return 'content-' .. (characterId:gsub(':', ''))
end

local function storedContent(characterId)
    local inventory = exports['core_inventory']:getInventory(storedName(characterId))
    if type(inventory) ~= 'table' then return nil end
    return type(inventory.content) == 'table' and inventory.content or nil
end

--@param characterId: string [citizenid / identifier of a character that is not in the server]
--@return items: table|nil
Inventory.offlineItems = function(characterId)
    return storedContent(characterId)
end

--@param characterId: string
--@param verb: string ['add' | 'remove' | 'clear']
--@return done: boolean
Inventory.offlineAction = function(characterId, verb, itemName, count)
    if not storedContent(characterId) then return false end

    local name = storedName(characterId)
    if verb == 'add' then
        return exports['core_inventory']:addItem(name, itemName, count, nil, 'content') ~= false
    elseif verb == 'remove' then
        return exports['core_inventory']:removeItem(name, itemName, count, 'content') ~= false
    elseif verb == 'clear' then
        exports['core_inventory']:clearInventory(name)
        return true
    end
    return false
end
