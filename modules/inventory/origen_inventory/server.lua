-- codem-lib inventory provider: origen_inventory (server)
-- Registered at load; the exports pick the active provider per call.
if LibConfig.Debug then
    print('[codem-lib] Inventory provider loaded: origen_inventory')
end

local Inventory = {}
LibInventoryProviders['origen_inventory'] = Inventory

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