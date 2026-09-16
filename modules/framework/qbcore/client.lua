--[[
    QBCore / Qbox Framework Integration - Client
    Exposes a framework-agnostic `Framework.Client` table used across the resource.
]]
-- Framework selection: LibConfig.Framework (codem-lib config) wins, then the
-- consumer's own Config.Framework, then auto-detection of the running core.
local FW = (type(LibConfig) == 'table' and LibConfig.Framework ~= 'auto' and LibConfig.Framework)
    or (type(Config) == 'table' and Config.Framework)
    or 'auto'
if FW == 'auto' then
    -- Two passes: whichever core is already running wins, and when none is (a
    -- consumer that starts before the core does) the one that is installed at
    -- all is taken. The bridge itself asks the core object for later.
    local CORES = { { 'qbx_core', 'qbox' }, { 'qb-core', 'qb' }, { 'es_extended', 'esx' } }
    local function pick(started)
        for _, core in ipairs(CORES) do
            local state = GetResourceState(core[1])
            if started and state == 'started' then return core[2] end
            if not started and state ~= 'missing' then return core[2] end
        end
        return nil
    end
    FW = pick(true) or pick(false) or FW
end
if FW ~= 'qb' and FW ~= 'qbox' then return end

local isQbox = FW == 'qbox'
--- The core object is asked for on first use, not while this file loads: a
--- server that starts a consumer before qb-core would hit an export that is not
--- there yet, and the whole bridge would be lost with the error.
local coreObject
local function resolveCore()
    if coreObject == nil then
        local ok, obj = pcall(function() return exports['qb-core']:GetCoreObject() end)
        coreObject = (ok and type(obj) == 'table') and obj or false
    end
    return coreObject or nil
end

local QBCore = not isQbox and setmetatable({}, {
    __index = function(_, key)
        local obj = resolveCore()
        return obj and obj[key] or nil
    end,
}) or nil

Framework = Framework or {}
Framework.Client = Framework.Client or {}

--------------------------------------------------------------------------------
-- Player data
--------------------------------------------------------------------------------

local loadedCallbacks = {}

---@return boolean
function Framework.Client.IsLoaded()
    return LocalPlayer.state.isLoggedIn == true
end

---Runs cb each time the player finishes loading (character selected / spawned).
---If the player is already loaded when registered, cb runs immediately.
---@param cb fun()
function Framework.Client.OnPlayerLoaded(cb)
    loadedCallbacks[#loadedCallbacks + 1] = cb
    if Framework.Client.IsLoaded() then CreateThread(cb) end
end

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    for _, cb in ipairs(loadedCallbacks) do CreateThread(cb) end
end)

---Event the framework fires when the character is unloaded (logout / switch).
Framework.Client.PlayerUnloadedEvent = isQbox and 'qbx_core:client:playerLoggedOut' or 'QBCore:Client:OnPlayerUnload'

local unloadedCallbacks = {}

---Runs cb each time the character is unloaded (logout / character switch).
---@param cb fun()
function Framework.Client.OnPlayerUnloaded(cb)
    unloadedCallbacks[#unloadedCallbacks + 1] = cb
end

RegisterNetEvent(Framework.Client.PlayerUnloadedEvent, function()
    for _, cb in ipairs(unloadedCallbacks) do CreateThread(cb) end
end)

---Announces the spawn after a character was loaded, the way the framework's
---own multicharacter does. Fires the OnPlayerLoaded callbacks as a side effect.
function Framework.Client.SpawnHandshake()
    TriggerServerEvent('QBCore:Server:OnPlayerLoaded')
    TriggerEvent('QBCore:Client:OnPlayerLoaded')
end

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
-- Routed through the lib's notify module (modules/notify), so the provider
-- configured in LibConfig.Notify decides how it looks — the framework's own
-- notification is just one of the providers ('framework').
--------------------------------------------------------------------------------

---@param message string
---@param nType? string 'success' | 'error' | 'inform' | 'warning'
---@param duration? number
function Framework.Client.FrameworkNotify(message, nType, duration)
    exports['codem-lib']:Notify(message, nType, duration)
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
    -- Trim both ends, not just the tail: the game pads plates to 8 characters
    -- and a leading space is a real character in a SQL comparison, so an
    -- untrimmed head would key the same car apart from the framework's own
    -- vehicle table (qbx.getVehiclePlate / ESX trim both ends too).
    return plate and (plate:gsub('^%s+', ''):gsub('%s+$', '')) or ''
end
