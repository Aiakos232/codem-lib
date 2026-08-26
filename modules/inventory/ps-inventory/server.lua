-- codem-lib inventory provider: ps-inventory (server)
-- Registered at load; the exports pick the active provider per call.
if LibConfig.Debug then
    print('[codem-lib] Inventory provider loaded: ps-inventory')
end

local Inventory = {}
LibInventoryProviders['ps-inventory'] = Inventory

--Whether an item can carry per-item metadata (info) through this bridge.
--Scripts that key an item to a thing (a room key, a vehicle key) ask this
--before trusting the item.
Inventory.supportsMetadata = true

--@return boolean [can the player carry itemCount of itemName]
Inventory.canCarry = function(playerId, itemName, itemCount)
    return exports['ps-inventory']:CanAddItem(playerId, itemName, itemCount) ~= false
end

RegisterNetEvent('codem-lib:inventory:openInventory', function(invType, data)
    if invType == 'shop' then
        exports['ps-inventory']:OpenShop(source, data.type)
    elseif invType == 'player' then
        exports['ps-inventory']:OpenInventoryById(source, data)
    else
        exports['ps-inventory']:OpenInventory(source, data)
    end
end)

--@param playerId: number [existing player id]
--@return items: table [{name: string, amount: number, metadata: table, slot: number}]
Inventory.getPlayerItems = function(playerId)
    -- A player's items live on the core object; GetInventory only holds
    -- stashes/drops and returns nil for a player id. Keep it as the fallback.
    local Player = LibGetQbPlayer(playerId)
    if Player then return Player.PlayerData.items or {} end
    return exports['ps-inventory']:GetInventory(playerId)?.items or {}
end

--@param prefix: string [prefix for the drop]
--@param items: table [name: string, count: number, metadata: table]
--@param coords: vector3 [drop coordinates]
Inventory.CustomDrop = function(prefix, items, coords)
    print('[codem-lib] ' .. 'CustomDrop is not supported in ps-inventory, please change type in config')
end

--@param playerId: number [existing player id]
--@param itemName: string [item name]
--@param itemCount: number [amount of items to add]
--@param itemMetadata: table [item metadata, optional]
--@param itemSlot: number [item slot, optional]
Inventory.addItem = function(playerId, itemName, itemCount, itemMetadata, itemSlot)
    exports['ps-inventory']:AddItem(playerId, itemName, itemCount, itemSlot, itemMetadata)
end

--@param playerId: number [existing player id]
--@param itemName: string [item name]
--@param itemCount: number [amount of items to remove]
--@param itemMetadata: table [item metadata, optional]
--@param itemSlot: number [item slot, optional]
Inventory.removeItem = function(playerId, itemName, itemCount, itemMetadata, itemSlot)
    exports['ps-inventory']:RemoveItem(playerId, itemName, itemCount, itemSlot)
end

--@param playerId: number [existing player id]
--@param itemName: string [item name]
--@param itemMetadata: table [item metadata, optional]
--@return count: number [amount of items in inventory]
Inventory.getItemCount = function(playerId, itemName, itemMetadata)
    local Player = itemMetadata and LibGetQbPlayer(playerId)
    if Player then
        for k, v in pairs(Player.PlayerData.items or {}) do
            if v.name == itemName and v.info and CodemTableMatches(v.info, itemMetadata) then
                return v.amount
            end
        end
    else
        local itemData = exports['ps-inventory']:GetItemByName(playerId, itemName)
        if itemData then
            return itemData.count
        end
    end

    return 0
end

--@param playerId: number [existing player id]
--@param slot: number [item slot]
--@return item: {name: string, label: string, amount: number, metadata: table}
Inventory.getItemSlot = function(playerId, slot)
    local itemSlot = exports['ps-inventory']:GetItemBySlot(playerId, slot)
    return itemSlot and {name = itemSlot.name, label = itemSlot.label, amount = itemSlot.amount, metadata = itemSlot.info or {}} or nil
end

---@param shopName: string [unique shop name]
---@param data: table [shop data]
Inventory.createShop = function(shopName, data)
    for i = 1, #data.inventory, 1 do
        if not data.inventory[i].slot then
            data.inventory[i].slot = i
        end
        
        if not data.inventory[i].amount then
            data.inventory[i].amount = 1000
        end
    end
    exports['ps-inventory']:CreateShop({
        name = shopName,
        label = data.label,
        slots = #data.inventory,
        items = data.inventory
    })
end
--@return catalog: table<string, { label: string, weight: number, image: string|nil }>
--Item metadata comes from the framework's shared table; only the picture
--folder is this inventory's own.
Inventory.itemCatalog = function()
    return LibFrameworkCatalog('nui://ps-inventory/html/images/')
end

--@param playerId: number
--@return capacity: { slots: number|nil, maxWeight: number|nil } [kg] or nil
Inventory.capacity = function(playerId)
    return LibPlayerCapacity(playerId)
end

--@param stashId: string|number
--@return items: table or nil when the stash is unknown
Inventory.stashItems = function(stashId)
    local inv = exports['ps-inventory']:GetInventory(stashId)
    if type(inv) ~= 'table' then return nil end
    -- Sağlayıcıya göre ya doğrudan liste ya da `items` alanı dönüyor.
    return inv.items or inv
end

--ps (qb lineage) takes a stash id wherever it takes a player id.
Inventory.moveStash = function(fromId, toId)
    local ps = exports['ps-inventory']
    return LibMoveStashWith(fromId, toId, {
        items = function(id)
            local inv = ps:GetInventory(id)
            return type(inv) == 'table' and (inv.items or inv) or nil
        end,
        add = function(id, name, count, meta) return ps:AddItem(id, name, count, false, meta) ~= false end,
        remove = function(id, name, count, _, slot) ps:RemoveItem(id, name, count, slot or false) end,
    })
end
