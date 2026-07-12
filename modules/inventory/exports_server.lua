--[[
    Inventory exports (server) — proxies over the `Inventory` table filled by
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

exports('GetPlayerItems', function(src) return call('getPlayerItems', src) end)
exports('AddItem', function(src, itemName, count, metadata, slot) return call('addItem', src, itemName, count, metadata, slot) end)
exports('RemoveItem', function(src, itemName, count, metadata, slot) return call('removeItem', src, itemName, count, metadata, slot) end)
exports('GetItemCount', function(src, itemName, metadata) return call('getItemCount', src, itemName, metadata) end)
exports('GetItemSlot', function(src, slot) return call('getItemSlot', src, slot) end)
exports('CustomDrop', function(prefix, items, coords) return call('CustomDrop', prefix, items, coords) end)
exports('CreateShop', function(shopName, data) return call('createShop', shopName, data) end)
