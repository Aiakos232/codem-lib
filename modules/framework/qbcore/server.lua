--[[
    QBCore / Qbox Framework Integration - Server
    Exposes a framework-agnostic `Framework.Server` table used across the resource.
]]
-- Framework selection: LibConfig.Framework (codem-lib config) wins, then the
-- consumer's own Config.Framework, then auto-detection of the running core.
local FW = (type(LibConfig) == 'table' and LibConfig.Framework)
    or (type(Config) == 'table' and Config.Framework)
    or 'auto'
if FW == 'auto' then
    if GetResourceState('qbx_core') == 'started' then
        FW = 'qbox'
    elseif GetResourceState('qb-core') == 'started' then
        FW = 'qb'
    elseif GetResourceState('es_extended') == 'started' then
        FW = 'esx'
    end
end
if FW ~= 'qb' and FW ~= 'qbox' then return end

local isQbox = FW == 'qbox'
local QBCore = not isQbox and exports['qb-core']:GetCoreObject() or nil

Framework = Framework or {}
Framework.Server = Framework.Server or {}

-- Vehicle ownership table + column holding the saved vehicle properties.
Framework.Server.VehiclesTable = 'player_vehicles'
Framework.Server.VehPropsColumn = 'mods'

--------------------------------------------------------------------------------
-- Player object
--------------------------------------------------------------------------------

---@param src number
---@return table|nil
function Framework.Server.GetPlayer(src)
    if isQbox then
        return exports.qbx_core:GetPlayer(src)
    end
    return QBCore.Functions.GetPlayer(src)
end

---@param src number
---@return string|nil citizenid
function Framework.Server.GetIdentifier(src)
    local Player = Framework.Server.GetPlayer(src)
    if not Player then return nil end
    return Player.PlayerData and Player.PlayerData.citizenid or nil
end

---@param src number
---@return string character display name ("First Last"), falls back to the src.
function Framework.Server.GetName(src)
    local Player = Framework.Server.GetPlayer(src)
    local ci = Player and Player.PlayerData and Player.PlayerData.charinfo
    if ci and ci.firstname then
        return ("%s %s"):format(ci.firstname, ci.lastname or ""):gsub("%s+$", "")
    end
    return GetPlayerName(src) or ("Player %d"):format(src)
end

---@param src number
---@return table|nil { name, label, grade, onduty }
function Framework.Server.GetPlayerJob(src)
    local Player = Framework.Server.GetPlayer(src)
    if not Player or not Player.PlayerData or not Player.PlayerData.job then return nil end
    local job = Player.PlayerData.job
    return {
        name = job.name,
        label = job.label,
        grade = job.grade and job.grade.level or 0,
        onduty = job.onduty or false,
    }
end

--------------------------------------------------------------------------------
-- Money
--------------------------------------------------------------------------------

---@param src number
---@param account string 'cash' | 'bank'
---@return number
function Framework.Server.GetBalance(src, account)
    local Player = Framework.Server.GetPlayer(src)
    if not Player then return 0 end
    return (Player.PlayerData.money and Player.PlayerData.money[account]) or 0
end

---@param src number
---@param amount number
---@param account string
---@return boolean
function Framework.Server.RemoveMoney(src, amount, account)
    local Player = Framework.Server.GetPlayer(src)
    if not Player then return false end
    -- This file runs inside the consumer resource's context, so the money
    -- reason is whatever script pulled in the lib - not a hardcoded name.
    return Player.Functions.RemoveMoney(account, amount, GetCurrentResourceName()) and true or false
end

---@param src number
---@param amount number
---@param account string
---@return boolean
function Framework.Server.AddMoney(src, amount, account)
    local Player = Framework.Server.GetPlayer(src)
    if not Player then return false end
    return Player.Functions.AddMoney(account, amount, GetCurrentResourceName()) and true or false
end

--------------------------------------------------------------------------------
-- Items
--------------------------------------------------------------------------------

-- Item calls go through the codem-lib inventory module (the configured
-- inventory provider), NOT through the framework player object - inventory
-- scripts replace those player functions and fall out of sync with them.

---@param src number
---@param itemName string
---@param qty? number
---@return boolean
function Framework.Server.HasItem(src, itemName, qty)
    qty = qty or 1
    return (exports['codem-lib']:GetItemCount(src, itemName) or 0) >= qty
end

---@param src number
---@param itemName string
---@param qty? number
function Framework.Server.RemoveItem(src, itemName, qty)
    return exports['codem-lib']:RemoveItem(src, itemName, qty or 1)
end

---@param src number
---@param itemName string
---@param qty? number
---@return boolean
function Framework.Server.AddItem(src, itemName, qty)
    return exports['codem-lib']:AddItem(src, itemName, qty or 1) ~= false
end

---Register a server-side "use" handler for an inventory item (framework's
---CreateUseableItem, not the ox_inventory client-event hook). `cb` gets src.
---@param name string
---@param cb fun(src: number)
function Framework.Server.CreateUseableItem(name, cb)
    if not name or not cb then return end
    if isQbox then
        exports.qbx_core:CreateUseableItem(name, function(src)
            cb(src)
        end)
    elseif QBCore then
        QBCore.Functions.CreateUseableItem(name, function(src)
            cb(src)
        end)
    end
end

--------------------------------------------------------------------------------
-- Notifications
--------------------------------------------------------------------------------

---Routed through the lib's notify module so LibConfig.Notify picks the look.
---@param src number
---@param message string
---@param nType? string
function Framework.Server.Notify(src, message, nType)
    exports['codem-lib']:Notify(src, message, nType)
end

--------------------------------------------------------------------------------
-- Permissions
--------------------------------------------------------------------------------

---True if the player holds any permission group in Config.AdminPermissions, or
---the 'command' ace (txAdmin / server console admins). Falls back to 'god' when
---no groups are configured.
---@param src number
---@return boolean
function Framework.Server.IsAdmin(src)
    if not src then return false end

    local perms = Config.AdminPermissions
    if type(perms) ~= 'table' or next(perms) == nil then
        perms = { ['god'] = true }
    end

    if IsPlayerAceAllowed(src, 'command') then return true end

    for perm, enabled in pairs(perms) do
        if enabled then
            if isQbox then
                if exports.qbx_core:HasPermission(src, perm) then return true end
            elseif QBCore and QBCore.Functions.HasPermission(src, perm) then
                return true
            end
        end
    end

    return false
end
