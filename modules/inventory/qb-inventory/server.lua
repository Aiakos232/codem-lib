-- codem-lib inventory provider: qb-inventory (server)
-- Registered at load; the exports pick the active provider per call.
if LibConfig.Debug then
    print('[codem-lib] Inventory provider loaded: qb-inventory')
end

local Inventory = {}
LibInventoryProviders['qb-inventory'] = Inventory

--Whether an item can carry per-item metadata (info) through this bridge.
--Scripts that key an item to a thing (a room key, a vehicle key) ask this
--before trusting the item.
Inventory.supportsMetadata = true

--@return boolean [can the player carry itemCount of itemName]
Inventory.canCarry = function(playerId, itemName, itemCount)
    return exports['qb-inventory']:CanAddItem(playerId, itemName, itemCount) == true
end

RegisterNetEvent('codem-lib:inventory:openInventory', function(invType, data)
    local src = source
    if LibGetInventoryResource() ~= 'qb-inventory' then return end
    if type(data) ~= 'table' then return end

    if invType == 'shop' then
        exports['qb-inventory']:OpenShop(src, data.type)
    elseif invType == 'player' then
        exports['qb-inventory']:OpenInventoryById(src, data)
    else
        Inventory.openStashServer(src, data.id or data.name or data.stashId, data)
    end
end)

--@param playerId: number [existing player id]
--@return items: table [{name: string, amount: number, metadata: table, slot: number}]
Inventory.getPlayerItems = function(playerId)
    -- A player's items live on the core object; GetInventory only holds
    -- stashes/drops and returns nil for a player id. Keep it as the fallback.
    local Player = LibGetQbPlayer(playerId)
    if Player then return Player.PlayerData.items or {} end
    return exports['qb-inventory']:GetInventory(playerId)?.items or {}
end

--@param prefix: string [prefix for the drop]
--@param items: table [name: string, count: number, metadata: table]
--@param coords: vector3 [drop coordinates]
Inventory.CustomDrop = function(prefix, items, coords)
    print('[codem-lib] ' .. 'CustomDrop is not supported in qb-inventory, please change type in config')
end

--@param playerId: number [existing player id]
--@param itemName: string [item name]
--@param itemCount: number [amount of items to add]
--@param itemMetadata: table [item metadata, optional]
--@param itemSlot: number [item slot, optional]
Inventory.addItem = function(playerId, itemName, itemCount, itemMetadata, itemSlot)
    return exports['qb-inventory']:AddItem(playerId, itemName, itemCount, itemSlot, itemMetadata)
end

--@param playerId: number [existing player id]
--@param itemName: string [item name]
--@param itemCount: number [amount of items to remove]
--@param itemMetadata: table [item metadata, optional]
--@param itemSlot: number [item slot, optional]
Inventory.removeItem = function(playerId, itemName, itemCount, itemMetadata, itemSlot)
    return exports['qb-inventory']:RemoveItem(playerId, itemName, itemCount, itemSlot)
end

--@param playerId: number [existing player id]
--@param itemName: string [item name]
--@param itemMetadata: table [item metadata, optional]
--@return count: number [amount of items in inventory]
Inventory.getItemCount = function(playerId, itemName, itemMetadata)
    print('getItemCount', playerId, itemName, itemMetadata)
    local Player = itemMetadata and LibGetQbPlayer(playerId)
    if Player then
        for k, v in pairs(Player.PlayerData.items or {}) do
            if v.name == itemName and v.info and CodemTableMatches(v.info, itemMetadata) then
                return v.amount
            end
        end
    else
        print('itemname', itemName)
        print(exports['qb-inventory']:GetItemCount(playerId, itemName))
        return exports['qb-inventory']:GetItemCount(playerId, itemName) or 0
    end

    return 0
end

--@param playerId: number [existing player id]
--@param slot: number [item slot]
--@return item: {name: string, label: string, amount: number, metadata: table}
Inventory.getItemSlot = function(playerId, slot)
    local itemSlot = exports['qb-inventory']:GetItemBySlot(playerId, slot)
    return itemSlot and
        { name = itemSlot.name, label = itemSlot.label, amount = itemSlot.amount, metadata = itemSlot.info or {} } or nil
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
    exports['qb-inventory']:CreateShop({
        name = shopName,
        label = data.label,
        slots = #data.inventory,
        items = data.inventory
    })
end
---qb-inventory creates stashes lazily on open; nothing to pre-register.
Inventory.registerStash = function(stashId, label, slots, weight, groups, coords, opts)
    return true
end

local modernQb
local function ModernQb()
    if modernQb == nil then
        modernQb = pcall(function()
            return exports['qb-inventory']:GetInventory('__codem_lib_probe__')
        end)
    end
    return modernQb
end

Inventory.openStashServer = function(src, stashId, invData)
    if type(stashId) ~= 'string' and type(stashId) ~= 'number' then return false end
    local id = tostring(stashId)

    local data = {
        label     = invData and invData.label or id,
        maxweight = invData and (invData.maxweight or invData.maxWeight) or 100000,
        slots     = invData and invData.slots or 50,
    }

    if ModernQb() then
        exports['qb-inventory']:OpenInventory(src, id, data)
    else
        TriggerClientEvent('codem-lib:inventory:qb:openStashLegacy', src, id, data)
    end
    return true
end

RegisterNetEvent('codem-lib:inventory:qb:openStash', function(stashId, invData)
    local src = source
    if LibGetInventoryResource() ~= 'qb-inventory' then return end
    if invData ~= nil and type(invData) ~= 'table' then invData = nil end
    Inventory.openStashServer(src, stashId, invData)
end)

--@return catalog: table<string, { label: string, weight: number, image: string|nil }>
--Item metadata comes from the framework's shared table; only the picture
--folder is this inventory's own.
Inventory.itemCatalog = function()
    return LibFrameworkCatalog('nui://qb-inventory/html/images/')
end

--@param playerId: number
--@return capacity: { slots: number|nil, maxWeight: number|nil } [kg] or nil
Inventory.capacity = function(playerId)
    return LibPlayerCapacity(playerId)
end

--@param fromId: string
--@param toId: string
--@return ok: boolean, detail: table|nil  see exports_server.lua MoveStash
--qb-inventory (2024+) takes a stash id wherever it takes a player id.
Inventory.moveStash = function(fromId, toId)
    local qb = exports['qb-inventory']
    return LibMoveStashWith(fromId, toId, {
        items = function(id)
            local inv = qb:GetInventory(id)
            return type(inv) == 'table' and (inv.items or inv) or nil
        end,
        add = function(id, name, count, meta)
            return qb:AddItem(id, name, count, false, meta, 'codem-lib:moveStash') ~= false
        end,
        remove = function(id, name, count, _, slot)
            qb:RemoveItem(id, name, count, slot or false, 'codem-lib:moveStash')
        end,
    })
end

--@param stashId: string|number
--@return items: table or nil when the stash is unknown
Inventory.stashItems = function(stashId)
    local inv = exports['qb-inventory']:GetInventory(stashId)
    if type(inv) ~= 'table' then return nil end
    return inv.items or inv
end

local function QbVersion()
    local a, b, c = (GetResourceMetadata('qb-inventory', 'version', 0) or ''):match('^(%d+)%.?(%d*)%.?(%d*)')
    return (tonumber(a) or 1) * 10000 + (tonumber(b) or 0) * 100 + (tonumber(c) or 0)
end

Inventory.clearStash = function(stashId)
    local id = tostring(stashId)
    if QbVersion() >= 20000 then
        local qb = exports['qb-inventory']
        local holder
        pcall(function()
            local inv = qb:GetInventory(id)
            if type(inv) == 'table' and type(inv.isOpen) == 'number' then holder = inv.isOpen end
        end)
        if not pcall(function() qb:ClearStash(id) end) then return false end
        if holder then pcall(function() qb:CloseInventory(holder, id) end) end
        return true
    end
    MySQL.update.await('UPDATE stashitems SET items = ? WHERE stash = ?', { '[]', id })
    return true
end

Inventory.resizeStash = function(stashId, slots, weight)
    if QbVersion() < 20200 then return false end
    exports['qb-inventory']:CreateInventory(tostring(stashId), { slots = slots, maxweight = weight })
    return true
end

local guards, guardSeq, guardHook = {}, 0, nil

local function GuardHook(_, payload)
    if type(payload) ~= 'table' or type(payload.inventoryId) ~= 'string' then return end
    for _, g in pairs(guards) do
        if payload.inventoryId:match(g.pattern) then
            local ok, yes = pcall(g.allow, payload.source, payload.inventoryId)
            if not ok or yes ~= true then return false end
        end
    end
end

local function EnsureGuardHook()
    if guardHook or not next(guards) then return guardHook ~= nil end
    local ok, idx = pcall(function() return exports['qb-inventory']:AddHook('InventoryOpened', GuardHook) end)
    guardHook = ok and idx or nil
    return guardHook ~= nil
end

Inventory.guardStashes = function(pattern, allow)
    if type(pattern) ~= 'string' or not allow then return nil end
    guardSeq = guardSeq + 1
    guards[guardSeq] = { pattern = pattern, allow = allow }
    if not EnsureGuardHook() then
        guards[guardSeq] = nil
        return nil
    end
    return guardSeq
end

Inventory.unguardStashes = function(handle)
    guards[handle] = nil
    if guardHook and not next(guards) then
        pcall(function() exports['qb-inventory']:RemoveHook('InventoryOpened', guardHook) end)
        guardHook = nil
    end
    return true
end

AddEventHandler('onResourceStart', function(res)
    if res ~= 'qb-inventory' then return end
    guardHook = nil
    EnsureGuardHook()
end)

Inventory.offlineItems, Inventory.offlineAction = LibStoredInventory(nil, nil, 'amount')
