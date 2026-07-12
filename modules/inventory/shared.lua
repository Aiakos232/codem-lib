--[[
    Inventory module shared helpers. Loaded before the provider files; each
    provider guards itself with LibInventoryActive and fills the global
    `Inventory` table (exports.lua exposes it).
]]

---True when the given provider should load: explicit config match, or
---('auto') the provider's resource is running.
---@param resource string resource name to detect
---@param key string config key (usually the same as resource)
---@return boolean
function LibInventoryActive(resource, key)
    local cfg = (LibConfig.Inventory and LibConfig.Inventory.provider) or 'auto'
    if cfg == 'auto' then
        return GetResourceState(resource) == 'started'
    end
    return cfg == key or cfg == resource
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
end
