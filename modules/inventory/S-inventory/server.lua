-- codem-lib inventory provider: S-inventory (server)
-- Active only when this provider is selected.
if not LibInventoryActive('S-inventory', 'S-inventory') then return end

if LibConfig.Debug then
    print('[codem-lib] Inventory provider loaded: S-inventory')
end

Inventory = {}

local ESX = exports['es_extended']:getSharedObject()

--@param playerId: number [existing player id]
--@return items: table [{name: string, amount: number, metadata: table, slot: number}]
Inventory.getPlayerItems = function(playerId)
    local xPlayer = ESX.GetPlayerFromId(playerId)
    return xPlayer.getInventory()
end

--@param prefix: string [prefix for the drop]
--@param items: table [name: string, count: number, metadata: table]
--@param coords: vector3 [drop coordinates]
Inventory.CustomDrop = function(prefix, items, coords)
    -- S-inventory does not support custom drops
end

--@param playerId: number [existing player id]
--@param itemName: string [item name]
--@param itemCount: number [amount of items to add]
--@param itemMetadata: table [item metadata, optional]
--@param itemSlot: number [item slot, optional]
Inventory.addItem = function(playerId, itemName, itemCount, itemMetadata, itemSlot)
    local xPlayer = ESX.GetPlayerFromId(playerId)
    xPlayer.addInventoryItem(itemName, itemCount)
end

--@param playerId: number [existing player id]
--@param itemName: string [item name]
--@param itemCount: number [amount of items to add]
--@param itemMetadata: table [item metadata, optional]
--@param itemSlot: number [item slot, optional]
Inventory.removeItem = function(playerId, itemName, itemCount, itemMetadata, itemSlot)
    local xPlayer = ESX.GetPlayerFromId(playerId)
    xPlayer.removeInventoryItem(itemName, itemCount, itemMetadata)
end

--@param playerId: number [existing player id]
--@param itemName: string [item name]
--@param itemMetadata: table [item metadata, optional]
--@return count: number [amount of items in inventory]
Inventory.getItemCount = function(playerId, itemName, itemMetadata)
    local xPlayer = ESX.GetPlayerFromId(playerId)
    return xPlayer.getInventoryItem(itemName)?.count or 0
end

Inventory.getItemSlot = function(playerId, slot)
    local xPlayer = ESX.GetPlayerFromId(playerId)
    local items = xPlayer.getInventory()
    return items[slot]
end

Inventory.createShop = function(shopName, data)
    -- S-inventory does not support shops
end

Inventory.itemsData = {}
GlobalState['codem-lib:itemsData'] = Inventory.itemsData

Citizen.CreateThread(function()
    while not MySQL?.ready do
        Citizen.Wait(100)
    end

    local result = MySQL.query.await('SELECT * FROM items')
    for k, v in pairs(result) do
        Inventory.itemsData[v.name] = {
            label = v.label,
            description = v.description or v.label,
        }
    end
    GlobalState['codem-lib:itemsData'] = Inventory.itemsData
end)