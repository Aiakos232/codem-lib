--[[
    Text UI (client) — persistent on-screen prompt ("Press E to ...").
    Selection via LibConfig.TextUI.provider ('auto' picks the first running
    resource, falling back to ox_lib, which is always present).

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
            lib.showTextUI(t, { position = (o and o.position) or 'left-center', icon = o and o.icon })
        end,
        hide = function() lib.hideTextUI() end,
    },
}

-- 'auto' detection order — dedicated text UI scripts win; ox_lib is the
-- final fallback (always running).
local CANDIDATES = { 'okokTextUI', 'cd_drawtextui' }

local function provider()
    local cfg = (LibConfig.TextUI and LibConfig.TextUI.provider) or 'auto'
    if cfg ~= 'auto' then return cfg end
    for _, res in ipairs(CANDIDATES) do
        if GetResourceState(res) == 'started' then return res end
    end
    return 'ox'
end

local function dispatch(verb, ...)
    local name = provider()
    local p = PROVIDERS[name]
    if not p then
        print(('[codem-lib] TextUI.%s: unknown provider "%s" - check LibConfig.TextUI.provider'):format(verb, name))
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
