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
-- Weight/space check. Providers without a canCarry method default to allowed
-- (true) silently — not every inventory exposes one, and blocking on absence
-- would break otherwise-valid actions.
exports('CanCarry', function(src, itemName, count, metadata)
    local res = LibGetInventoryResource()
    local provider = res and LibInventoryProviders[res]
    if not provider or not provider.canCarry then return true end
    local ok, out = pcall(provider.canCarry, src, itemName, count, metadata)
    if not ok then return true end
    return out ~= false
end)
--[[
    Item metadata, capacity and stash reads.

    Panels and admin tools need to describe an item (label, weight, picture)
    without owning one, and to say how full a bag is. Providers keep all three
    in different places, so the difference is resolved here rather than in
    every script that asks.

    A provider that cannot answer returns nil through `call`, and nil is a
    real answer: "this inventory does not expose it" is not the same as empty.
]]
exports('GetItemCatalog', function() return call('itemCatalog') end)
exports('GetCapacity', function(src) return call('capacity', src) end)
exports('GetStashItems', function(stashId) return call('stashItems', stashId) end)

exports('GetItemSlot', function(src, slot) return call('getItemSlot', src, slot) end)
exports('CustomDrop', function(prefix, items, coords) return call('CustomDrop', prefix, items, coords) end)
exports('CreateShop', function(shopName, data) return call('createShop', shopName, data) end)
exports('RegisterStash', function(stashId, label, slots, weight, groups, coords, opts)
    return call('registerStash', stashId, label, slots, weight, groups, coords, opts)
end)
exports('OpenStashServer', function(src, stashId, invData) return call('openStashServer', src, stashId, invData) end)

--[[
    Move every item from one stash to another.

    Returns `true`, or `false, detail` where detail is one of:
      { missing = stashId }   a stash the inventory does not know
      { blocked = itemName }  the destination would not take this item;
                              whatever was already moved has been put back
    Providers without a `moveStash` answer `false, { unsupported = true }` —
    callers treat that like any other refusal rather than crashing on a
    missing export.
]]
--[[
    Can an item carry per-item metadata on the running inventory?

    False when no inventory is running, or the provider does not say. An
    item that cannot hold metadata cannot be "the key to room 12" — it is
    the same item as every other key — so callers refuse item-keyed
    features rather than hand out a master key by accident.
]]
exports('SupportsItemMetadata', function()
    local res = LibGetInventoryResource()
    local provider = res and LibInventoryProviders[res]
    return provider ~= nil and provider.supportsMetadata == true
end)

exports('MoveStash', function(fromId, toId)
    local res = LibGetInventoryResource()
    local provider = res and LibInventoryProviders[res]
    if not provider or not provider.moveStash then
        print(('[codem-lib] Inventory.moveStash: not supported by "%s"'):format(tostring(res)))
        return false, { unsupported = true }
    end
    local ok, a, b = pcall(provider.moveStash, fromId, toId)
    if not ok then
        print(('[codem-lib] Inventory.moveStash via "%s" failed: %s'):format(res, tostring(a)))
        return false, { error = tostring(a) }
    end
    return a, b
end)
