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
    'ox_inventory', 'qb-inventory', 'ps-inventory', 'qs-inventory',
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
end
