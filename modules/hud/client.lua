--[[
    HUD (client) — hides the running HUD while a full-screen interface is open
    and brings it back afterwards. Selection via LibConfig.Hud.provider ('auto'
    picks the first running HUD from the list below).

    Several scripts may hold the HUD down at once (the inventory over the
    clothing shop). Each caller is counted, so the HUD only returns once every
    one of them has released it; a caller that stops without releasing is
    dropped automatically.

    Exports:
      HideHud(token?)   -- token defaults to the calling resource
      ShowHud(token?)
      IsHudHidden()
]]

local PROVIDERS = {
    ['codem-supreme-hud'] = {
        hide = function() exports['codem-supreme-hud']:HideHud() end,
        show = function() exports['codem-supreme-hud']:ShowHud() end,
    },
}

-- 'auto' detection order.
local CANDIDATES = { 'codem-supreme-hud' }

-- Written on every hide, cleared on every show. A HUD that reads this state
-- hides with no provider entry and no configuration at all.
local STATE = 'codemHudHidden'

local holders = {}
local count = 0
local hidden = false
local warned = false

local function cfg()
    return (LibConfig and LibConfig.Hud) or {}
end

local function provider()
    local want = cfg().provider or 'auto'
    if want ~= 'auto' then return want end
    for _, res in ipairs(CANDIDATES) do
        if GetResourceState(res) == 'started' then return res end
    end
    return 'none'
end

local function fire(events)
    if type(events) ~= 'table' then return end
    for _, name in ipairs(events) do
        if type(name) == 'string' and name ~= '' then TriggerEvent(name) end
    end
end

local function dispatch(verb)
    local name = provider()
    local p = PROVIDERS[name]
    if not p then
        if name ~= 'none' then
            print(('[codem-lib] Hud.%s: unknown provider "%s" - check LibConfig.Hud.provider'):format(verb, name))
        elseif not warned then
            warned = true
            print('[codem-lib] Hud: no supported HUD is running, so nothing is hidden.')
            print('[codem-lib] Hud: a HUD can also hide itself by reading')
            print('[codem-lib] Hud: LocalPlayer.state.codemHudHidden in its draw loop.')
        end
        return false
    end
    local ok, err = pcall(p[verb])
    if not ok then
        print(('[codem-lib] Hud.%s via "%s" failed: %s'):format(verb, name, tostring(err)))
        return false
    end
    return true
end

local function apply(hide)
    local settings = cfg()
    LocalPlayer.state:set(STATE, hide or nil, true)
    dispatch(hide and 'hide' or 'show')
    fire(hide and (settings.events or {}).hide or (settings.events or {}).show)
    local custom = hide and settings.onHide or settings.onShow
    if type(custom) == 'function' then pcall(custom) end
end

local function keyFor(token)
    if type(token) == 'string' and token ~= '' then return token end
    return GetInvokingResource() or GetCurrentResourceName()
end

local function hideFor(token)
    if cfg().enable == false then return false end
    local key = keyFor(token)
    if not holders[key] then
        holders[key] = true
        count = count + 1
    end
    if not hidden then
        hidden = true
        apply(true)
    end
    return true
end

local function showFor(token)
    local key = keyFor(token)
    if not holders[key] then return hidden end
    holders[key] = nil
    count = count - 1
    if count <= 0 then
        count = 0
        if hidden then
            hidden = false
            apply(false)
        end
    end
    return hidden
end

AddEventHandler('onClientResourceStop', function(resource)
    if holders[resource] then showFor(resource) end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if hidden then apply(false) end
end)

exports('HideHud', function(token) return hideFor(token) end)
exports('ShowHud', function(token) return showFor(token) end)
exports('IsHudHidden', function() return hidden end)
