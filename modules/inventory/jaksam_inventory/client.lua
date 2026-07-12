-- codem-lib inventory provider: jaksam_inventory (client)
-- Registered at load; the exports pick the active provider per call.
if LibConfig.Debug then
    print('[codem-lib] Inventory provider loaded: jaksam_inventory')
end

local Inventory = {}
LibInventoryProviders['jaksam_inventory'] = Inventory

Inventory.openInventory = function(invType, data)
    local invId = nil
    if type(data) == 'table' then
        if data.owner then
            invId = ('%s_%s'):format(data.id, data.owner)
        else
            invId = data.id
        end
    elseif type(data) == 'string' then
        invId = data
    end
    exports['jaksam_inventory']:openInventory(invId)
end

Inventory.getItemCount = function(itemName)
    return exports['jaksam_inventory']:getTotalItemAmount(itemName)
end

Inventory.getItemData = function(itemName)
    local info = exports['jaksam_inventory']:getStaticItem(itemName)
    return info and {name = itemName, label = info.label, description = info.description, image = ('https://cfx-nui-jaksam_inventory/_images/%s.png'):format(itemName)}
end