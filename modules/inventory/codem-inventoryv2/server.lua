-- codem-lib inventory provider: codem-inventoryv2 (server)
-- Registered at load; the exports pick the active provider per call.
if LibConfig.Debug then
    print('[codem-lib] Inventory provider loaded: codem-inventoryv2')
end

local Inventory = {}
LibInventoryProviders['codem-inventoryv2'] = Inventory

--Whether an item can carry per-item metadata (info) through this bridge.
--Scripts that key an item to a thing (a room key, a vehicle key) ask this
--before trusting the item.
Inventory.supportsMetadata = true

--@return boolean [can the player carry itemCount of itemName]
Inventory.canCarry = function(playerId, itemName, itemCount)
    return exports['codem-inventoryv2']:CanCarryItem(playerId, itemName, itemCount) == true
end

--@param playerId: number [existing player id]
--@return items: table [{name: string, amount: number, metadata: table, slot: number}]
Inventory.getPlayerItems = function(playerId)
    return exports['codem-inventoryv2']:GetInventoryItems(playerId)
end

--@param prefix: string [prefix for the drop]
--@param items: table [name: string, count: number, metadata: table]
--@param coords: vector3 [drop coordinates]
Inventory.CustomDrop = function(prefix, items, coords)
    exports['codem-inventoryv2']:CustomDrop(prefix, items, coords)
end

--@param playerId: number [existing player id]
--@param itemName: string [item name]
--@param itemCount: number [amount of items to add]
--@param itemMetadata: table [item metadata, optional]
--@param itemSlot: number [item slot, optional]
Inventory.addItem = function(playerId, itemName, itemCount, itemMetadata, itemSlot)
    exports['codem-inventoryv2']:AddItem(playerId, itemName, itemCount, itemMetadata, itemSlot)
end

--@param playerId: number [existing player id]
--@param itemName: string [item name]
--@param itemCount: number [amount of items to add]
--@param itemMetadata: table [item metadata, optional]
--@param itemSlot: number [item slot, optional]
Inventory.removeItem = function(playerId, itemName, itemCount, itemMetadata, itemSlot)
    exports['codem-inventoryv2']:RemoveItem(playerId, itemName, itemCount, itemMetadata, itemSlot)
end

--@param playerId: number [existing player id]
--@param itemName: string [item name]
--@param itemMetadata: table [item metadata, optional]
--@return count: number [amount of items in inventory]
Inventory.getItemCount = function(playerId, itemName, itemMetadata)
    return exports['codem-inventoryv2']:Search(playerId, 'count', itemName, itemMetadata)
end

Inventory.getItemSlot = function(playerId, slot)
    return exports['codem-inventoryv2']:GetSlot(playerId, slot)
end

Inventory.createShop = function(shopName, data)
    while GetResourceState('codem-inventoryv2') ~= 'started' do
        Citizen.Wait(100)
    end

    Citizen.Wait(100)
    exports['codem-inventoryv2']:RegisterShop(shopName, data)
end
---Register a stash. groups: { [job] = minGrade } map.
Inventory.registerStash = function(stashId, label, slots, weight, groups, coords, opts)
    -- (ox_inventory has no item whitelist parameter; restrictions are
    -- inventory-specific and simply ignored here.)
    exports['codem-inventoryv2']:RegisterStash(stashId, label, slots, weight, nil, groups, coords)
    return true
end

---Server-side stash open; ox opens client-side, nothing to do.
Inventory.openStashServer = function(src, stashId, invData)
    return false
end

--@return catalog: table<string, { label: string, weight: number, image: string|nil }>
--Item metadata for every item the server knows, weight in kilograms. ox stores
--grams; the conversion belongs here so callers never have to ask which unit
--this particular inventory happens to use.
Inventory.itemCatalog = function()
    local items = exports['codem-inventoryv2']:Items()
    if type(items) ~= 'table' then return {} end

    local out = {}
    for name, item in pairs(items) do
        out[name] = {
            label = item.label or name,
            weight = (tonumber(item.weight) or 0) / 1000,
            image = LibItemImage('nui://codem-inventoryv2/web/images/', name, item.client),
        }
    end
    return out
end

--@param playerId: number
--@return capacity: { slots: number|nil, maxWeight: number|nil } [kg]
Inventory.capacity = function(playerId)
    local inv = exports['codem-inventoryv2']:GetInventory(playerId, false)
    if type(inv) ~= 'table' then return nil end

    return {
        slots = tonumber(inv.slots),
        maxWeight = (tonumber(inv.maxWeight) or 0) / 1000,
    }
end

--@param fromId: string [stash identifier]
--@param toId: string [stash identifier]
--@return ok: boolean, detail: table|nil  see exports_server.lua MoveStash
--Item by item, and every item already moved goes back if one will not fit:
--a tenant's things end up in one cupboard or the other, never split.
Inventory.moveStash = function(fromId, toId)
    local ox = exports['codem-inventoryv2']
    return LibMoveStashWith(fromId, toId, {
        items = function(id)
            local inv = ox:GetInventory(id, false)
            return type(inv) == 'table' and (inv.items or {}) or nil
        end,
        add = function(id, name, count, meta) return ox:AddItem(id, name, count, meta) == true end,
        remove = function(id, name, count, meta, slot) ox:RemoveItem(id, name, count, meta, slot) end,
    })
end

--@param stashId: string|number [stash identifier]
--@return items: table [same shape as getPlayerItems] or nil when the stash is unknown
Inventory.stashItems = function(stashId)
    local inv = exports['codem-inventoryv2']:GetInventory(stashId, false)
    if type(inv) ~= 'table' then return nil end
    return inv.items or {}
end
