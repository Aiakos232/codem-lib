--[[
    Inventory exports (server) — proxies over the `Inventory` table filled by
    whichever provider file activated. Loaded after every provider.
]]

local function call(fnName, ...)
    local res = LibGetInventoryResource()
    local provider = res and LibInventoryProviders[res]
    if not provider then
        print(('[codem-lib] Inventory.%s: no supported inventory running (active: %s) - set LibConfig.Inventory.provider')
            :format(fnName, tostring(res)))
        return nil
    end
    if not provider[fnName] then
        print(('[codem-lib] Inventory.%s: not supported by "%s"'):format(fnName, res))
        return nil
    end
    local ok, out = pcall(provider[fnName], ...)
    if not ok then
        print(('[codem-lib] Inventory.%s via "%s" failed: %s'):format(fnName, res, tostring(out)))
        return nil
    end
    return out
end

exports('GetPlayerItems', function(src) return call('getPlayerItems', src) end)
exports('AddItem', function(src, itemName, count, metadata, slot) return call('addItem', src, itemName, count, metadata, slot) end)
exports('RemoveItem', function(src, itemName, count, metadata, slot) return call('removeItem', src, itemName, count, metadata, slot) end)
exports('GetItemCount', function(src, itemName, metadata) return call('getItemCount', src, itemName, metadata) end)
exports('GetItemSlot', function(src, slot) return call('getItemSlot', src, slot) end)
exports('CustomDrop', function(prefix, items, coords) return call('CustomDrop', prefix, items, coords) end)
exports('CreateShop', function(shopName, data) return call('createShop', shopName, data) end)
exports('RegisterStash', function(stashId, label, slots, weight, groups, coords, opts)
    return call('registerStash', stashId, label, slots, weight, groups, coords, opts)
end)
exports('OpenStashServer', function(src, stashId, invData) return call('openStashServer', src, stashId, invData) end)
