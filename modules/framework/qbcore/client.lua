--[[
    QBCore / Qbox Framework Integration - Client
    Exposes a framework-agnostic `Framework.Client` table used across the resource.
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
Framework.Client = Framework.Client or {}

--------------------------------------------------------------------------------
-- Player data
--------------------------------------------------------------------------------

---@return table
function Framework.Client.GetPlayerData()
    if isQbox then
        return exports.qbx_core:GetPlayerData()
    end
    return QBCore.Functions.GetPlayerData()
end

---@return table|nil { name, label, grade, onduty }
function Framework.Client.GetPlayerJob()
    local data = Framework.Client.GetPlayerData()
    if not data or not data.job then return nil end
    return {
        name = data.job.name,
        label = data.job.label,
        grade = data.job.grade and data.job.grade.level or 0,
        onduty = data.job.onduty or false,
    }
end

--------------------------------------------------------------------------------
-- Money
--------------------------------------------------------------------------------

---@param account string 'cash' | 'bank'
---@return number
function Framework.Client.GetBalance(account)
    local data = Framework.Client.GetPlayerData()
    return (data and data.money and data.money[account]) or 0
end

--------------------------------------------------------------------------------
-- Notifications / HUD
-- Only the framework-native notify lives here. The public Framework.Client.Notify
-- (plus ShowTextUI / ProgressBar) is built once in modules/ui/client.lua and
-- falls back to this when no UI resource is selected.
--------------------------------------------------------------------------------

---@param message string
---@param nType? string 'success' | 'error' | 'inform' | 'warning'
---@param duration? number
function Framework.Client.FrameworkNotify(message, nType, duration)
    if isQbox then
        exports.qbx_core:Notify(message, nType or 'inform', duration or 5000)
    else
        QBCore.Functions.Notify(message, nType or 'primary', duration or 5000)
    end
end

---@param toggle boolean
function Framework.Client.ToggleHud(toggle)
    DisplayRadar(toggle)
end

--------------------------------------------------------------------------------
-- Vehicles
--------------------------------------------------------------------------------

---@param model string|number Spawn/archetype name (any case) or model hash
---@return number Vehicle base value (0 if unknown)
function Framework.Client.GetVehicleValue(model)
    local key = type(model) == 'string' and model:lower() or model
    if isQbox then
        local vehicles = exports.qbx_core:GetVehiclesByName()
        local veh = vehicles and vehicles[key]
        return (veh and veh.price) or 0
    end
    local veh = QBCore.Shared.Vehicles[key]
    return (veh and veh.price) or 0
end

---@param model string|number
---@return string
function Framework.Client.GetVehicleLabel(model)
    local key = type(model) == 'string' and model:lower() or model
    if isQbox then
        local vehicles = exports.qbx_core:GetVehiclesByName()
        local veh = vehicles and vehicles[key]
        return (veh and veh.name) or tostring(model)
    end
    local veh = QBCore.Shared.Vehicles[key]
    return (veh and veh.name) or tostring(model)
end

---@param vehicle number
---@return string trimmed plate
function Framework.Client.GetPlate(vehicle)
    if not vehicle or vehicle == 0 then return '' end
    local plate = GetVehicleNumberPlateText(vehicle)
    return plate and plate:gsub('%s+$', '') or ''
end
