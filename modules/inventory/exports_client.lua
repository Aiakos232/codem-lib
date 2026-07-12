--[[
    Inventory exports (client) — proxies over the `Inventory` table filled by
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

exports('OpenInventory', function(invType, data) return call('openInventory', invType, data) end)
exports('GetItemCount', function(itemName, metadata) return call('getItemCount', itemName, metadata) end)
exports('GetItemData', function(itemName) return call('getItemData', itemName) end)
exports('GetPlayerItems', function() return call('getPlayerItems') end)
exports('OpenStash', function(stashId, invData) return call('openStash', stashId, invData) end)
