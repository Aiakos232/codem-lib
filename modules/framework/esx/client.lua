--[[
    ESX Framework Integration - Client
    Mirrors the `Framework.Client` API. Only active when the resolved framework is 'esx'.
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
if FW ~= 'esx' then return end

--- Asked for on first use, so a consumer that starts before es_extended does
--- not lose this whole bridge to a missing export.
local sharedObject
local ESX = setmetatable({}, {
    __index = function(_, key)
        if sharedObject == nil then
            local ok, obj = pcall(function() return exports['es_extended']:getSharedObject() end)
            sharedObject = (ok and type(obj) == 'table') and obj or false
        end
        return sharedObject and sharedObject[key] or nil
    end,
})

Framework = Framework or {}
Framework.Client = Framework.Client or {}

local loadedCallbacks = {}

---@return boolean
function Framework.Client.IsLoaded()
    return ESX.IsPlayerLoaded() == true
end

---Runs cb each time the player finishes loading (character selected / spawned).
---If the player is already loaded when registered, cb runs immediately.
---@param cb fun()
function Framework.Client.OnPlayerLoaded(cb)
    loadedCallbacks[#loadedCallbacks + 1] = cb
    if Framework.Client.IsLoaded() then CreateThread(cb) end
end

RegisterNetEvent('esx:playerLoaded', function()
    for _, cb in ipairs(loadedCallbacks) do CreateThread(cb) end
end)

---Event the framework fires when the character is unloaded (logout / switch).
Framework.Client.PlayerUnloadedEvent = 'esx:onPlayerLogout'

local unloadedCallbacks = {}

---Runs cb each time the character is unloaded (logout / character switch).
---@param cb fun()
function Framework.Client.OnPlayerUnloaded(cb)
    unloadedCallbacks[#unloadedCallbacks + 1] = cb
end

RegisterNetEvent(Framework.Client.PlayerUnloadedEvent, function()
    for _, cb in ipairs(unloadedCallbacks) do CreateThread(cb) end
end)

---Announces the spawn after a character was loaded, the way esx_multicharacter
---does (server spawn event, loadout restore, loading screen off).
function Framework.Client.SpawnHandshake()
    TriggerServerEvent('esx:onPlayerSpawn')
    TriggerEvent('esx:onPlayerSpawn')
    TriggerEvent('esx:restoreLoadout')
    TriggerEvent('esx:loadingScreenOff')
end

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

-- Routed through the lib's notify module (modules/notify), so the provider
-- configured in LibConfig.Notify decides how it looks.
function Framework.Client.FrameworkNotify(message, nType, duration)
    exports['codem-lib']:Notify(message, nType, duration)
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
    -- Trim both ends, not just the tail: the game pads plates to 8 characters
    -- and a leading space is a real character in a SQL comparison, so an
    -- untrimmed head would key the same car apart from the framework's own
    -- vehicle table (qbx.getVehiclePlate / ESX trim both ends too).
    return plate and (plate:gsub('^%s+', ''):gsub('%s+$', '')) or ''
end
