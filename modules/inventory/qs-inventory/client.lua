-- codem-lib inventory provider: qs-inventory (client)
-- Active only when this provider is selected.
if not LibInventoryActive('qs-inventory', 'qs-inventory') then return end

if LibConfig.Debug then
    print('[codem-lib] Inventory provider loaded: qs-inventory')
end

Inventory = {}

Inventory.openInventory = function(invType, data)
    if invType == 'stash' then
        if data.owner then
            TriggerServerEvent("inventory:server:OpenInventory", "stash", data.id..'_'..data.owner, {
                maxweight = 250000,
                slots = 100,
            })
            TriggerEvent("inventory:client:SetCurrentStash", data.id..'_'..data.owner)
        else
            TriggerServerEvent('p_policejob/inventory/openInventory', invType, data)
        end
    elseif invType == 'shop' then
        if not data.label then
            data.label = data.type
        end
        
        if data.items then
            for i = 1, #data.items, 1 do
                data.items[i].slot = i
                if not data.items[i].amount then
                    data.items[i].amount = 1000
                end
                if not data.items[i].price then
                    data.items[i].price = 0
                end
            end
        end
        TriggerServerEvent("inventory:server:OpenInventory", "shop", data.type..'_'..data.id, {
            label = data.label,
            items = data.items
        })
    elseif invType == 'player' then
        TriggerServerEvent("inventory:server:OpenInventory", "otherplayer", data)
        TriggerEvent("inventory:client:SetCurrentStash", "otherplayer")
    end
end

Inventory.getItemCount = function(itemName)
    return exports['qs-inventory']:Search(itemName)
end

Inventory.getItemData = function(itemName)
    local info = exports['qs-inventory']:GetItemList()[itemName]
    return info and {name = itemName, label = info.label, description = info.description, image = ('https://cfx-nui-qs-inventory/html/images/%s.png'):format(itemName)}
end