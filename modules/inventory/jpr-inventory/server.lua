-- codem-lib inventory provider: jpr-inventory (server)
-- Registered at load; the exports pick the active provider per call.
if LibConfig.Debug then
    print('[codem-lib] Inventory provider loaded: jpr-inventory')
end

local Inventory = {}
LibInventoryProviders['jpr-inventory'] = Inventory

RegisterNetEvent('codem-lib:inventory:openInventory', function(invType, data)
    if invType == 'shop' then
        exports['jpr-inventory']:OpenShop(source, data.type)
    elseif invType == 'player' then
        exports['jpr-inventory']:OpenInventoryById(source, data)
    else
        exports['jpr-inventory']:OpenInventory(source, data)
    end
end)

--@param playerId: number [existing player id]
--@return items: table [{name: string, amount: number, metadata: table, slot: number}]
Inventory.getPlayerItems = function(playerId)
    -- A player's items live on the core object; GetInventory returns nil for a
    -- player id on this qb fork. Keep it as the fallback.
    local Player = LibGetQbPlayer(playerId)
    if Player then return Player.PlayerData.items or {} end
    return exports["jpr-inventory"]:GetInventory(playerId) or {}
end

--@param prefix: string [prefix for the drop]
--@param items: table [name: string, count: number, metadata: table]
--@param coords: vector3 [drop coordinates]
Inventory.CustomDrop = function(prefix, items, coords)
    print('[codem-lib] ' .. 'CustomDrop is not supported in jpr-inventory, please change type in config')
end

--@param playerId: number [existing player id]
--@param itemName: string [item name]
--@param itemCount: number [amount of items to add]
--@param itemMetadata: table [item metadata, optional]
--@param itemSlot: number [item slot, optional]
Inventory.addItem = function(playerId, itemName, itemCount, itemMetadata, itemSlot)
    exports['jpr-inventory']:AddItem(playerId, itemName, itemCount, itemSlot, itemMetadata)
end

--@param playerId: number [existing player id]
--@param itemName: string [item name]
--@param itemCount: number [amount of items to remove]
--@param itemMetadata: table [item metadata, optional]
--@param itemSlot: number [item slot, optional]
Inventory.removeItem = function(playerId, itemName, itemCount, itemMetadata, itemSlot)
    exports['jpr-inventory']:RemoveItem(playerId, itemName, itemCount, itemSlot)
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
        return exports['jpr-inventory']:GetItemCount(playerId, itemName) or 0
    end

    return 0
end

--@param playerId: number [existing player id]
--@param slot: number [item slot]
--@return item: {name: string, label: string, amount: number, metadata: table}
Inventory.getItemSlot = function(playerId, slot)
    local itemSlot = exports['jpr-inventory']:GetItemBySlot(playerId, slot)
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
    exports['jpr-inventory']:CreateShop({
        name = shopName,
        label = data.label or shopName,
        slots = #data.inventory,
        items = data.inventory
    })
end
--@return catalog: table<string, { label: string, weight: number, image: string|nil }>
--Item metadata comes from the framework's shared table; only the picture
--folder is this inventory's own.
Inventory.itemCatalog = function()
    return LibFrameworkCatalog('nui://jpr-inventory/html/images/')
end

--@param playerId: number
--@return capacity: { slots: number|nil, maxWeight: number|nil } [kg] or nil
Inventory.capacity = function(playerId)
    return LibPlayerCapacity(playerId)
end

--@param stashId: string|number
--@return items: table or nil when the stash is unknown
Inventory.stashItems = function(stashId)
    local inv = exports['jpr-inventory']:GetInventory(stashId)
    if type(inv) ~= 'table' then return nil end
    -- Sağlayıcıya göre ya doğrudan liste ya da `items` alanı dönüyor.
    return inv.items or inv
end

--jpr (qs lineage) takes a stash id in its stash exports.
Inventory.moveStash = function(fromId, toId)
    local jpr = exports['jpr-inventory']
    return LibMoveStashWith(fromId, toId, {
        items = function(id)
            local inv = jpr:GetInventory(id)
            return type(inv) == 'table' and (inv.items or inv) or nil
        end,
        add = function(id, name, count, meta) return jpr:AddItemIntoStash(id, name, count, nil, meta) ~= false end,
        remove = function(id, name, count, _, slot) jpr:RemoveItemIntoStash(id, name, count, slot) end,
    })
end
