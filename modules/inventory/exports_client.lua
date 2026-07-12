--[[
    Inventory exports (client) — proxies over the `Inventory` table filled by
    whichever provider file activated. Loaded after every provider.
]]

local function call(fnName, ...)
    if not Inventory or not Inventory[fnName] then
        print(('[codem-lib] Inventory.%s: no inventory provider active - set LibConfig.Inventory.provider'):format(fnName))
        return nil
    end
    local ok, res = pcall(Inventory[fnName], ...)
    if not ok then
        print(('[codem-lib] Inventory.%s failed: %s'):format(fnName, tostring(res)))
        return nil
    end
    return res
end

exports('OpenInventory', function(invType, data) return call('openInventory', invType, data) end)
exports('GetItemCount', function(itemName, metadata) return call('getItemCount', itemName, metadata) end)
exports('GetItemData', function(itemName) return call('getItemData', itemName) end)
exports('GetPlayerItems', function() return call('getPlayerItems') end)
