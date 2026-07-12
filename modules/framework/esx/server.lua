--[[
    ESX Framework Integration - Server
    Mirrors the `Framework.Server` API. Only active when the resolved framework is 'esx'.
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
if FW ~= 'esx' then return end

local ESX = exports['es_extended']:getSharedObject()

Framework = Framework or {}
Framework.Server = Framework.Server or {}

-- Vehicle ownership table + column holding the saved vehicle properties.
Framework.Server.VehiclesTable = 'owned_vehicles'
Framework.Server.VehPropsColumn = 'vehicle'

function Framework.Server.GetPlayer(src)
    return ESX.GetPlayerFromId(src)
end

function Framework.Server.GetIdentifier(src)
    local xPlayer = Framework.Server.GetPlayer(src)
    return xPlayer and xPlayer.identifier or nil
end

function Framework.Server.GetName(src)
    local xPlayer = Framework.Server.GetPlayer(src)
    if xPlayer and xPlayer.getName then return xPlayer.getName() end
    return GetPlayerName(src) or ("Player %d"):format(src)
end

function Framework.Server.GetPlayerJob(src)
    local xPlayer = Framework.Server.GetPlayer(src)
    if not xPlayer or not xPlayer.job then return nil end
    return {
        name = xPlayer.job.name,
        label = xPlayer.job.label,
        grade = xPlayer.job.grade,
        onduty = true,
    }
end

function Framework.Server.GetBalance(src, account)
    local xPlayer = Framework.Server.GetPlayer(src)
    if not xPlayer then return 0 end
    local map = { cash = 'money', bank = 'bank' }
    local acc = xPlayer.getAccount(map[account] or account)
    return acc and acc.money or 0
end

function Framework.Server.RemoveMoney(src, amount, account)
    local xPlayer = Framework.Server.GetPlayer(src)
    if not xPlayer then return false end
    local map = { cash = 'money', bank = 'bank' }
    xPlayer.removeAccountMoney(map[account] or account, amount)
    return true
end

function Framework.Server.AddMoney(src, amount, account)
    local xPlayer = Framework.Server.GetPlayer(src)
    if not xPlayer then return false end
    local map = { cash = 'money', bank = 'bank' }
    xPlayer.addAccountMoney(map[account] or account, amount)
    return true
end

-- Item calls go through the codem-lib inventory module (the configured
-- inventory provider), NOT through the framework player object.

function Framework.Server.HasItem(src, itemName, qty)
    qty = qty or 1
    return (exports['codem-lib']:GetItemCount(src, itemName) or 0) >= qty
end

function Framework.Server.RemoveItem(src, itemName, qty)
    return exports['codem-lib']:RemoveItem(src, itemName, qty or 1)
end

---Register a server-side "use" handler for an inventory item. `cb` gets src.
---@param name string
---@param cb fun(src: number)
function Framework.Server.CreateUseableItem(name, cb)
    if not name or not cb then return end
    ESX.RegisterUsableItem(name, function(src)
        cb(src)
    end)
end

function Framework.Server.Notify(src, message, _nType)
    TriggerClientEvent('esx:showNotification', src, message)
end

--------------------------------------------------------------------------------
-- Permissions
--------------------------------------------------------------------------------

---True if the player's ESX group is enabled in Config.AdminPermissions, or the
---player holds the 'command' ace (txAdmin / server console admins).
---@param src number
---@return boolean
function Framework.Server.IsAdmin(src)
    if not src then return false end

    if IsPlayerAceAllowed(src, 'command') then return true end

    local xPlayer = Framework.Server.GetPlayer(src)
    if not xPlayer then return false end
    local grp = (xPlayer.getGroup and xPlayer.getGroup()) or xPlayer.group or 'user'

    local perms = Config.AdminPermissions
    if type(perms) ~= 'table' or next(perms) == nil then
        perms = { ['admin'] = true, ['superadmin'] = true }
    end

    return perms[grp] == true
end
