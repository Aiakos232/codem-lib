--[[
    Text UI (client) — persistent on-screen prompt ("Press E to ...").
    Selection via LibConfig.TextUI.provider ('auto' picks the first running
    resource, then ox_lib if it is running). ox_lib is optional; with no
    provider the calls no-op with a console warning.

    Exports:
      ShowTextUI(text, opts?)   -- opts: { position?: string, icon?: string }
      HideTextUI()
]]

-- t = text, o = opts.
local PROVIDERS = {
    ['okokTextUI'] = {
        show = function(t) exports['okokTextUI']:Open(t, 'lightblue', 'left') end,
        hide = function() exports['okokTextUI']:Close() end,
    },

    ['cd_drawtextui'] = {
        show = function(t) TriggerEvent('cd_drawtextui:ShowUI', 'show', t) end,
        hide = function() TriggerEvent('cd_drawtextui:HideUI') end,
    },

    ['ox'] = {
        show = function(t, o)
            exports.ox_lib:showTextUI(t, { position = (o and o.position) or 'left-center', icon = o and o.icon })
        end,
        hide = function() exports.ox_lib:hideTextUI() end,
    },
}

-- 'auto' detection order — dedicated text UI scripts win; then ox_lib if running.
local CANDIDATES = { 'okokTextUI', 'cd_drawtextui' }

local function provider()
    local cfg = (LibConfig.TextUI and LibConfig.TextUI.provider) or 'auto'
    if cfg ~= 'auto' then return cfg end
    for _, res in ipairs(CANDIDATES) do
        if GetResourceState(res) == 'started' then return res end
    end
    -- ox_lib only if it is actually running; no native TextUI fallback.
    if CodemOxReady() then return 'ox' end
    return 'none'
end

local function dispatch(verb, ...)
    local name = provider()
    local p = PROVIDERS[name]
    if not p then
        if name == 'none' then
            print(('[codem-lib] TextUI.%s: no provider running - install ox_lib or a dedicated TextUI resource, or set LibConfig.TextUI.provider'):format(verb))
        else
            print(('[codem-lib] TextUI.%s: unknown provider "%s" - check LibConfig.TextUI.provider'):format(verb, name))
        end
        return false
    end
    local ok, err = pcall(p[verb], ...)
    if not ok then
        print(('[codem-lib] TextUI.%s via "%s" failed: %s'):format(verb, name, tostring(err)))
        return false
    end
    return true
end

exports('ShowTextUI', function(text, opts) return dispatch('show', text, opts) end)
exports('HideTextUI', function() return dispatch('hide') end)
