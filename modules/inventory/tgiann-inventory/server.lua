-- codem-lib inventory provider: tgiann-inventory (server)
-- Registered at load; the exports pick the active provider per call.
if LibConfig.Debug then
    print('[codem-lib] Inventory provider loaded: tgiann-inventory')
end

local Inventory = {}
LibInventoryProviders['tgiann-inventory'] = Inventory

--Whether an item can carry per-item metadata (info) through this bridge.
--Scripts that key an item to a thing (a room key, a vehicle key) ask this
--before trusting the item.
Inventory.supportsMetadata = true

--@return boolean [can the player carry itemCount of itemName]
Inventory.canCarry = function(playerId, itemName, itemCount)
    return exports['tgiann-inventory']:CanCarryItem(playerId, itemName, itemCount) ~= false
end

--@param playerId: number [existing player id]
--@return items: table [{name: string, amount: number, metadata: table, slot: number}]
Inventory.getPlayerItems = function(playerId)
    return exports['tgiann-inventory']:GetPlayerItems(playerId)
end

--@param prefix: string [prefix for the drop]
--@param items: table [name: string, count: number, metadata: table]
--@param coords: vector3 [drop coordinates]
Inventory.CustomDrop = function(prefix, items, coords)
    exports['tgiann-inventory']:CustomDrop(prefix, items, coords)
end

--@param playerId: number [existing player id]
--@param itemName: string [item name]
--@param itemCount: number [amount of items to add]
--@param itemMetadata: table [item metadata, optional]
--@param itemSlot: number [item slot, optional]
Inventory.addItem = function(playerId, itemName, itemCount, itemMetadata, itemSlot)
    exports['tgiann-inventory']:AddItem(playerId, itemName, itemCount, itemSlot, itemMetadata)
end

--@param playerId: number [existing player id]
--@param itemName: string [item name]
--@param itemCount: number [amount of items to remove]
--@param itemMetadata: table [item metadata, optional]
--@param itemSlot: number [item slot, optional]
Inventory.removeItem = function(playerId, itemName, itemCount, itemMetadata, itemSlot)
    exports['tgiann-inventory']:RemoveItem(playerId, itemName, itemCount, itemSlot, itemMetadata)
end

--@param playerId: number [existing player id]
--@param itemName: string [item name]
--@param itemMetadata: table [item metadata, optional]
--@return count: number [amount of items in inventory]
Inventory.getItemCount = function(playerId, itemName, itemMetadata)
    if itemMetadata then
        local items = exports['tgiann-inventory']:GetPlayerItems(playerId)
        for k, v in pairs(items) do
            if v.name == itemName and v.info and CodemTableMatches(v.info, itemMetadata) then
                return v.amount
            end
        end
    else
        return exports['tgiann-inventory']:GetItemCount(playerId, itemName)
    end

    return 0
end

--@param playerId: number [existing player id]
--@param slot: number [item slot]
--@return item: {name: string, label: string, amount: number, metadata: table}
Inventory.getItemSlot = function(playerId, slot)
    local items = exports['tgiann-inventory']:GetPlayerItems(playerId)
    local itemData = nil
    for k, v in pairs(items) do
        if v.slot == slot then
            itemData = v
            break
        end
    end
    return itemData and
        { name = itemData.name, label = itemData.label, amount = itemData.amount, metadata = itemData.info or {} } or nil
end

Inventory.createShop = function(shopName, data)
    while GetResourceState('tgiann-inventory') ~= 'started' do
        Citizen.Wait(100)
    end

    for i = 1, #data.inventory, 1 do
        if not data.inventory[i].amount then
            data.inventory[i].amount = 9999
        end

        if not data.inventory[i].slot then
            data.inventory[i].slot = i
        end
        if data.inventory[i].name:find('WEAPON_') then
            data.inventory[i].type = 'weapon'
        else
            data.inventory[i].type = 'item'
        end
    end
    exports["tgiann-inventory"]:RegisterShop(shopName, data.inventory)
end

RegisterNetEvent('codem-lib:inventory:openInventory', function(invType, data)
    if invType == 'stash' then
        if data.owner then
            exports['tgiann-inventory']:OpenInventory(source, "stash", data.id .. '_' .. data.owner)
        else
            exports['tgiann-inventory']:OpenInventory(source, "stash", data)
        end
    elseif invType == 'player' then
        exports["tgiann-inventory"]:OpenInventoryById(source, data)
    elseif invType == 'shop' then
        exports["tgiann-inventory"]:OpenShop(source, data.type)
    end
end)
---Register a stash. Uses the table form (the positional whitelist slot is
---unreliable); tgiann supports item whitelist/blacklist restrictions.
Inventory.registerStash = function(stashId, label, slots, weight, groups, coords, opts)
    local jobs
    if groups then
        jobs = {}
        for jobName in pairs(groups) do jobs[#jobs + 1] = jobName end
    end
    -- tgiann's table form keys the stash on `stashName` (see its own
    -- policejob/ambulance callers); `name` is only accepted by the internal
    -- function, not the export - registering with it drops the whitelist.
    exports['tgiann-inventory']:RegisterStash({
        stashName = stashId,
        name      = stashId,
        label     = label,
        slots     = slots,
        maxWeight = weight,
        whitelist = opts and opts.whitelist,
        blacklist = opts and opts.blacklist,
        jobs      = jobs,
        coords    = coords,
    })
    return true
end

---tgiann stashes open server-side. The size travels with the open call
---(`maxweight`/`slots` — tgiann-core passes the same keys). tgiann locks a
---registered stash's capacity at first registration and ignores the data
---param afterwards, so when the stash is already loaded push the new size
---straight into it (vland-stashhouse does the same via UpdateInventoryData).
Inventory.openStashServer = function(src, stashId, invData)
    local data
    if type(invData) == 'table' then
        data = {
            maxweight = invData.maxweight or invData.maxWeight or invData.weight,
            slots     = invData.slots,
            label     = invData.label,
        }
        local ok, inv = pcall(function()
            return exports['tgiann-inventory']:GetInventory(stashId, 'stash')
        end)
        if ok and inv and inv.Functions and inv.Functions.UpdateInventoryData
            and (data.maxweight or data.slots) then
            inv.Functions.UpdateInventoryData({
                MaxWeight = data.maxweight,
                MaxSlots  = data.slots,
            })
        end
    end
    exports['tgiann-inventory']:OpenInventory(src, 'stash', stashId, data)
    return true
end

RegisterNetEvent('codem-lib:inventory:openStash', function(stashId, invData)
    local src = source
    if type(stashId) ~= 'string' and type(stashId) ~= 'number' then return end
    if invData ~= nil and type(invData) ~= 'table' then invData = nil end
    Inventory.openStashServer(src, stashId, invData)
end)

--@return catalog: table<string, { label: string, weight: number, image: string|nil }>
--Item metadata comes from the framework's shared table; only the picture
--folder is this inventory's own.
Inventory.itemCatalog = function()
    return LibFrameworkCatalog('nui://inventory_images/images/')
end

--@param playerId: number
--@return capacity: { slots: number|nil, maxWeight: number|nil } [kg] or nil
Inventory.capacity = function(playerId)
    return LibPlayerCapacity(playerId)
end

--@param stashId: string|number
--@return items: table or nil when the stash is unknown
--tgiann has no GetStashItems export; stashes are "secondary inventories".
Inventory.stashItems = function(stashId)
    local ok, items = pcall(function()
        return exports['tgiann-inventory']:GetSecondaryInventoryItems('stash', stashId)
    end)
    if not ok or type(items) ~= 'table' then return nil end
    return items
end

--Stash items in and out through tgiann's secondary-inventory exports.
Inventory.moveStash = function(fromId, toId)
    local tg = exports['tgiann-inventory']
    return LibMoveStashWith(fromId, toId, {
        items = function(id) return Inventory.stashItems(id) end,
        add = function(id, name, count, meta)
            return tg:AddItemToSecondaryInventory('stash', id, name, count, nil, meta) ~= false
        end,
        remove = function(id, name, count, meta, slot)
            tg:RemoveItemFromSecondaryInventory('stash', id, name, count, slot, meta)
        end,
    })
end
