-- codem-lib inventory provider: S-inventory (client)
-- Active only when this provider is selected.
if not LibInventoryActive('S-Inventory', 'S-Inventory') then return end

local ESX = exports['es_extended']:getSharedObject()


if LibConfig.Debug then
    print('[codem-lib] Inventory provider loaded: S-Inventory')
end

Inventory = {}

Inventory.openInventory = function(invType, data)
    if invType == 'player' then
        TriggerEvent("SService:Server:SearchPlayer")
    elseif invType == 'stash' then
        exports["S-Inventory"]:OpenStashInventory(nil, data)
    elseif invType == 'shop' then
        print('[codem-lib] ' .. 'S-Inventory does not support external shops, create shop in inventory config')
    end
end

Inventory.getItemCount = function(itemName)
    local items = ESX.GetPlayerData().inventory
    if items then
        for k, v in pairs(items) do
            if v.name == itemName then
                return v.count or 0
            end
        end
    end
end

Inventory.getItemData = function(itemName)
    local info = GlobalState['codem-lib:itemsData'][itemName]
    return info and {name = itemName, label = info.label, description = info.description, image = ('https://cfx-nui-ox_inventory/web/images/%s.png'):format(itemName)}
end