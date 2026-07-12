--[[
    ESX Framework Integration - Client
    Mirrors the `Framework.Client` API. Only active when the resolved framework is 'esx'.
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
Framework.Client = Framework.Client or {}

function Framework.Client.GetPlayerData()
    return ESX.GetPlayerData()
end

function Framework.Client.GetPlayerJob()
    local data = Framework.Client.GetPlayerData()
    if not data or not data.job then return nil end
    return {
        name = data.job.name,
        label = data.job.label,
        grade = data.job.grade,
        onduty = true,
    }
end

function Framework.Client.GetBalance(account)
    local data = Framework.Client.GetPlayerData()
    if not data or not data.accounts then return 0 end
    local map = { cash = 'money', bank = 'bank' }
    local target = map[account] or account
    for _, acc in pairs(data.accounts) do
        if acc.name == target then return acc.money end
    end
    return 0
end

-- Only the framework-native notify lives here; the public Framework.Client.Notify
-- (plus ShowTextUI / ProgressBar) is built once in modules/ui/client.lua.
function Framework.Client.FrameworkNotify(message, nType, duration)
    ESX.ShowNotification(message, nType, duration or 5000)
end

function Framework.Client.ToggleHud(toggle)
    DisplayRadar(toggle)
end

function Framework.Client.GetVehicleValue(_model)
    -- ESX has no shared vehicle price list by default; override as needed.
    return 0
end

function Framework.Client.GetVehicleLabel(model)
    return tostring(model)
end

function Framework.Client.GetPlate(vehicle)
    if not vehicle or vehicle == 0 then return '' end
    local plate = GetVehicleNumberPlateText(vehicle)
    return plate and plate:gsub('%s+$', '') or ''
end
