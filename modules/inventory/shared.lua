--[[
    Inventory module shared helpers. Loaded before the provider files; each
    provider guards itself with LibInventoryActive and fills the global
    `Inventory` table (exports.lua exposes it).
]]

-- Every provider file registers its implementation here at load time; the
-- exports resolve the ACTIVE one per call (so start order never matters).
LibInventoryProviders = LibInventoryProviders or {}

-- 'auto' detection order — first running resource wins.
local CANDIDATES = {
    'codem-inventoryv2', 'ox_inventory', 'qb-inventory', 'ps-inventory', 'qs-inventory',
    'codem-inventory', 'core_inventory', 'tgiann-inventory', 'origen_inventory',
    'ak47_inventory', 'jaksam_inventory', 'jpr-inventory', 'S-inventory',
}

---Resolve the active inventory resource name, or nil when none is running.
---@return string|nil
function LibGetInventoryResource()
    local cfg = (LibConfig.Inventory and LibConfig.Inventory.provider) or 'auto'
    if cfg ~= 'auto' then
        return GetResourceState(cfg) == 'started' and cfg or nil
    end
    for _, res in ipairs(CANDIDATES) do
        if GetResourceState(res) == 'started' then return res end
    end
    return nil
end

exports('GetInventoryResource', LibGetInventoryResource)

--[[
    Move every item from one stash to another, with whichever three calls the
    provider has. Shared so each provider only says HOW to read, add and
    remove; the order, the rollback and the answer shape live here.

      ops.items(id)                          -> list|nil (nil = stash unknown)
      ops.add(id, name, count, meta, slot)   -> false when refused; nil/true = ok
      ops.remove(id, name, count, meta, slot)

    Item rows differ per inventory: count may be `count` or `amount`, metadata
    `metadata` or `info`. Both spellings are read.

    Returns true, or false plus { missing = id } / { blocked = itemName }.
    On a refusal everything already moved is put back, so a tenant's things
    end up in one cupboard or the other — never split.
]]
---@param fromId string
---@param toId string
---@param ops table
---@return boolean ok, table|nil detail
function LibMoveStashWith(fromId, toId, ops)
    local src = ops.items(fromId)
    if type(src) ~= 'table' then return false, { missing = fromId } end
    local dst = ops.items(toId)
    if type(dst) ~= 'table' then return false, { missing = toId } end

    local moved = {}
    for _, item in pairs(src) do
        local count = type(item) == 'table' and tonumber(item.count or item.amount) or 0
        if type(item) == 'table' and item.name and count > 0 then
            local meta = item.metadata or item.info
            if ops.add(toId, item.name, count, meta, nil) == false then
                for _, done in ipairs(moved) do
                    ops.remove(toId, done.name, done.count, done.meta, nil)
                    ops.add(fromId, done.name, done.count, done.meta, nil)
                end
                return false, { blocked = item.name }
            end
            ops.remove(fromId, item.name, count, meta, item.slot)
            moved[#moved + 1] = { name = item.name, count = count, meta = meta }
        end
    end
    return true
end

---Build an inventory icon url. Honors the item's OWN image field (kept with its
---extension, e.g. 'farming/wheat.webp') and passes absolute http/nui urls
---through untouched. Only when the item has no image do we fall back to
---"<base><itemName>.png".
---@param base string url/nui prefix incl. trailing slash (e.g. 'nui://inventory_images/images/')
---@param itemName string
---@param info? table item data from the provider
---@return string
function LibItemImage(base, itemName, info)
    local img = info and (info.image or info.img)
    if img and img ~= '' then
        if img:find('^nui://') or img:find('^http') then return img end
        return base .. img
    end
    return base .. itemName .. '.png'
end

if not IsDuplicityVersion() then
    local qbCore


    ---@return table|nil
    function LibGetQbCore()
        if qbCore then return qbCore end
        if GetResourceState('qb-core') ~= 'started' then return nil end
        local ok, core = pcall(function() return exports['qb-core']:GetCoreObject() end)
        qbCore = ok and type(core) == 'table' and core or nil
        return qbCore
    end
end

if IsDuplicityVersion() then
    ---Framework-agnostic unique player identifier (citizenid / identifier).
    ---Used by providers whose exports are keyed by identifier (codem-inventory).
    ---@param playerId number
    ---@return string|nil
    function LibGetUniqueId(playerId)
        if GetResourceState('qbx_core') == 'started' then
            local player = exports.qbx_core:GetPlayer(playerId)
            return player and player.PlayerData.citizenid
        elseif GetResourceState('qb-core') == 'started' then
            local player = exports['qb-core']:GetCoreObject().Functions.GetPlayer(playerId)
            return player and player.PlayerData.citizenid
        elseif GetResourceState('es_extended') == 'started' then
            local xPlayer = exports['es_extended']:getSharedObject().GetPlayerFromId(playerId)
            return xPlayer and xPlayer.identifier
        end
        return nil
    end

    ---ESX shared item table (`ESX.Items`), or nil.
    ---@return table|nil
    function LibGetEsxItems()
        if GetResourceState('es_extended') ~= 'started' then return nil end
        local ok, esx = pcall(function() return exports['es_extended']:getSharedObject() end)
        if ok and type(esx) == 'table' and type(esx.Items) == 'table' then return esx.Items end
        return nil
    end

    ---Item catalog from whichever framework is running, normalised.
    ---
    ---Every inventory except ox keeps item metadata in the framework's shared
    ---table rather than its own; only the folder the pictures live in differs.
    ---That folder is the one thing a provider passes in.
    ---
    ---Weight is returned in kilograms. Frameworks write grams (qb) or their own
    ---unit (esx), so anything above 100 is treated as grams — a single item
    ---heavier than 100 kg does not exist, and a value below it is already kg.
    ---@param imageBase string nui:// prefix incl. trailing slash
    ---@return table<string, { label: string, weight: number, image: string|nil }>
    function LibFrameworkCatalog(imageBase)
        local items = LibGetQbSharedItems() or LibGetEsxItems()
        if type(items) ~= 'table' then return {} end

        local out = {}
        for name, item in pairs(items) do
            if type(item) == 'table' then
                local weight = tonumber(item.weight) or 0
                if weight > 100 then weight = weight / 1000 end

                out[name] = {
                    label = item.label or name,
                    weight = weight,
                    image = LibItemImage(imageBase, name, item),
                }
            end
        end
        return out
    end

    ---Weight ceiling for a player, in kilograms, from the framework.
    ---
    ---Slot counts are not returned: qb-family inventories keep them in their own
    ---config rather than on the player, and a guessed ceiling would make a full
    ---inventory look half empty.
    ---@param playerId number
    ---@return { slots: number|nil, maxWeight: number|nil }|nil
    function LibPlayerCapacity(playerId)
        local player = LibGetQbPlayer(playerId)
        local max = player and tonumber(player.PlayerData.maxweight)
        if max then return { slots = nil, maxWeight = max / 1000 } end

        if GetResourceState('es_extended') == 'started' then
            local ok, esx = pcall(function() return exports['es_extended']:getSharedObject() end)
            local xPlayer = ok and type(esx) == 'table' and esx.GetPlayerFromId and esx.GetPlayerFromId(playerId)
            if xPlayer and xPlayer.getMaxWeight then
                local weight = tonumber(xPlayer.getMaxWeight())
                if weight then
                    if weight > 100 then weight = weight / 1000 end
                    return { slots = nil, maxWeight = weight }
                end
            end
        end

        return nil
    end

    ---qb/qbox shared item table (`QBCore.Shared.Items`), or nil.
    ---Every qb-family inventory keeps item metadata — label, weight, image —
    ---there rather than in its own store, so their providers read it from here
    ---instead of each reaching into the core themselves.
    ---@return table|nil
    function LibGetQbSharedItems()
        if GetResourceState('qbx_core') == 'started' then
            local ok, items = pcall(function() return exports.qbx_core:GetSharedItems() end)
            if ok and type(items) == 'table' then return items end
        end
        if GetResourceState('qb-core') == 'started' then
            local ok, core = pcall(function() return exports['qb-core']:GetCoreObject() end)
            if ok and type(core) == 'table' and type(core.Shared) == 'table' then
                return core.Shared.Items
            end
        end
        return nil
    end

    ---qb/qbox core Player object for a server id (nil on esx or when not found).
    ---qb-family inventories (qb/ps/jpr forks) keep a player's items on this
    ---object, not in the inventory's own tables, so their providers read through
    ---it. qbox-safe (mirrors LibGetUniqueId's resolution).
    ---@param playerId number
    ---@return table|nil
    function LibGetQbPlayer(playerId)
        if GetResourceState('qbx_core') == 'started' then
            return exports.qbx_core:GetPlayer(playerId)
        elseif GetResourceState('qb-core') == 'started' then
            return exports['qb-core']:GetCoreObject().Functions.GetPlayer(playerId)
        end
        return nil
    end
end
