-- codem-lib inventory provider: jpr-inventory (client)
-- Registered at load; the exports pick the active provider per call.
if LibConfig.Debug then
    print('[codem-lib] Inventory provider loaded: jpr-inventory')
end

local Inventory = {}
LibInventoryProviders['jpr-inventory'] = Inventory

Inventory.openInventory = function(invType, data)
    if invType == 'stash' then
        if data.owner then
            TriggerServerEvent("inventory:server:OpenInventory", "stash", data.id..'_'..data.owner, {
                maxweight = 250000,
                slots = 100,
            })
            TriggerEvent("inventory:client:SetCurrentStash", data.id..'_'..data.owner)
        else
            TriggerServerEvent('codem-lib:inventory:openInventory', invType, data)
        end
    elseif invType == 'shop' then
        TriggerServerEvent('codem-lib:inventory:openInventory', invType, data)
    elseif invType == 'player' then
        TriggerServerEvent("inventory:server:OpenInventory", "otherplayer", data)
        TriggerEvent("inventory:client:SetCurrentStash", "otherplayer")
    end
end

Inventory.getItemCount = function(itemName)
    local core = LibGetQbCore()
    local items = core and core.PlayerData and core.PlayerData.items
    if not items then return 0 end
    for _, item in pairs(items) do
        if item.name == itemName then
            return item.amount
        end
    end
    return 0
end

Inventory.getItemData = function(itemName)
    local core = LibGetQbCore()
    local info = core and core.Shared.Items[itemName]
    return info and {name = itemName, label = info.label, description = info.description, image = ('https://cfx-nui-jpr-inventory/html/images/%s.png'):format(itemName)}
end