--[[
    Medical (client) — whether the local player is down (dead or in last stand).

    Ambulance scripts keep the ped alive while the player is "dead" (they play a
    downed animation instead), so IsEntityDead alone misses them. Every known
    signal is checked, none of them needs a provider to be configured.

    Exports:
      IsPlayerDead() -> boolean
]]

local QBCore

local function metadataDown()
    local data
    if GetResourceState('qbx_core') == 'started' then
        local ok, result = pcall(function() return exports.qbx_core:GetPlayerData() end)
        data = ok and result or nil
    elseif GetResourceState('qb-core') == 'started' then
        if not QBCore then
            local ok, core = pcall(function() return exports['qb-core']:GetCoreObject() end)
            QBCore = ok and core or nil
        end
        data = QBCore and QBCore.Functions.GetPlayerData() or nil
    elseif GetResourceState('es_extended') == 'started' then
        local ok, esx = pcall(function() return exports.es_extended:getSharedObject() end)
        data = ok and esx and esx.PlayerData or nil
        if data and data.dead then return true end
        return false
    end
    local meta = data and data.metadata
    return meta ~= nil and (meta.isdead == true or meta.inlaststand == true)
end

local function isPlayerDead()
    if IsEntityDead(PlayerPedId()) then return true end
    local state = LocalPlayer.state
    if state.isDead == true or state.dead == true then return true end
    local deathState = tonumber(state['qbx_medical:deathState'])
    if deathState and deathState > 1 then return true end
    return metadataDown()
end

exports('IsPlayerDead', isPlayerDead)
