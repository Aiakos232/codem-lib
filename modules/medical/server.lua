--[[
    Medical (server) — reviving a player through whatever ambulance script the
    server runs. One module, framework-agnostic: the provider is picked by
    LibConfig.Medical.provider ('auto' detects a running one).

    Global API:
      Medical.Revive(source)   -> bring a downed player back up

    Why this is not "set health to 200": the ambulance script owns the death
    state. A player whose ped is healthy but whose script still has them logged
    as dead cannot stand up, respawns at the hospital on the next tick, or keeps
    the death UI on screen. The revive has to go through the script that put
    them down.

    Adding an ambulance script = one PROVIDERS entry. Every call is pcall-guarded,
    so a wrong provider logs a warning instead of leaving someone on the floor.
]]

Medical = Medical or {}

---@type table<string, { revive: fun(source: number) }>
local PROVIDERS = {
    ['wasabi_ambulance_v2'] = {
        revive = function(src) return exports['wasabi_ambulance_v2']:RevivePlayer(src) end,
    },

    ['wasabi_ambulance'] = {
        revive = function(src) return exports.wasabi_ambulance:RevivePlayer(src) end,
    },

    ['qs-medical-creator'] = {
        revive = function(src) TriggerClientEvent('ambulance:revivePlayer', src, true, true) end,
    },

    ['ars_ambulancejob'] = {
        revive = function(src) TriggerClientEvent('ars_ambulancejob:healPlayer', src, { revive = true }) end,
    },

    ['tk_ambulancejob'] = {
        revive = function(src) return exports.tk_ambulancejob:revive(src, true) end,
    },

    -- Qbox's own medical resource. Its export, not qb's `hospital:client:Revive`
    -- event: qbx_medical does not listen for that one at all, and the export is
    -- what clears the death state bag the rest of the server reads.
    ['qbx_medical'] = {
        revive = function(src) return exports.qbx_medical:Revive(src) end,
    },

    ['qb-ambulancejob'] = {
        revive = function(src) TriggerClientEvent('hospital:client:Revive', src) end,
    },

    ['esx_ambulancejob'] = {
        revive = function(src)
            TriggerClientEvent('esx_ambulancejob:revive', src)
            -- Some ESX death scripts read this instead of the event.
            Player(src).state:set('isDead', false, true)
        end,
    },
}

-- Detection order matters: a server running both a standalone ambulance script
-- and the framework's own one wants the standalone, which is the one actually
-- handling deaths.
local CANDIDATES = {
    'wasabi_ambulance_v2',
    'wasabi_ambulance',
    'qs-medical-creator',
    'ars_ambulancejob',
    'tk_ambulancejob',
    'qbx_medical',
    'qb-ambulancejob',
    'esx_ambulancejob',
}

---@return string
local function provider()
    local cfg = (LibConfig.Medical and LibConfig.Medical.provider) or 'auto'
    if cfg ~= 'auto' then return cfg end
    for _, res in ipairs(CANDIDATES) do
        if GetResourceState(res) == 'started' then return res end
    end
    return 'none'
end

---@return boolean
local function enabled()
    return LibConfig.Medical ~= nil and LibConfig.Medical.enabled == true
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

---Revive a downed player.
---
---Returns true when a provider took the call. The client-side resurrection
---(health, blood, ragdoll) is the caller's job either way: a server with no
---ambulance script at all still has a ped to stand back up.
---@param source number
---@return boolean handled
function Medical.Revive(source)
    source = tonumber(source)
    if not source or not enabled() then return false end

    local name = provider()
    local p = PROVIDERS[name]
    if not p then
        print(('[codem-lib] Medical.Revive: no ambulance provider for "%s" - set LibConfig.Medical.provider')
            :format(tostring(name)))
        return false
    end

    local ok, err = pcall(p.revive, source)
    if not ok then
        print(('[codem-lib] Medical.Revive via "%s" failed: %s'):format(name, tostring(err)))
        return false
    end

    return true
end

---Which ambulance script is being used, or nil when none was found.
---@return string|nil
function Medical.Provider()
    local name = provider()
    return PROVIDERS[name] and name or nil
end

--------------------------------------------------------------------------------
-- Exports — consumer scripts call these (via the init.lua shim)
--------------------------------------------------------------------------------

exports('MedicalRevive', Medical.Revive)
exports('GetMedicalProvider', Medical.Provider)
