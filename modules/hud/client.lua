--[[
    HUD (client) — hides other HUD resources while a full-screen interface is
    open and brings them back when the last caller is done.

    Several scripts may hold the HUD down at the same time (the inventory over
    the clothing shop, for example). Each caller is counted, so the HUD only
    returns once every one of them has released it. A caller that stops without
    releasing is dropped automatically.

    Exports:
      HideHud(token?)   -- token defaults to the calling resource
      ShowHud(token?)
      IsHudHidden()
]]

local KNOWN = {
    ['codem-supreme-hud'] = { hide = 'HideHud', show = 'ShowHud' },
    ['qbx_hud'] = { hideEvent = 'qbx_hud:client:hideHud', showEvent = 'qbx_hud:client:showHud' },
}

-- Read by HUDs that have no hide/show entry point of their own. qbx_hud and
-- qb-hud rebuild their visibility every tick, so an event cannot hold them
-- down; one line in their loop can (see LibConfig.Hud in config.lua).
local STATE = 'codemHudHidden'

local holders = {}
local count = 0
local hidden = false

local function cfg()
    return LibConfig and LibConfig.Hud or {}
end

local function callTarget(resource, methods, hide)
    if type(methods) ~= 'table' then return end
    if GetResourceState(resource) ~= 'started' then return end

    local event = hide and methods.hideEvent or methods.showEvent
    if type(event) == 'string' and event ~= '' then TriggerEvent(event) end

    local method = hide and methods.hide or methods.show
    if type(method) ~= 'string' or method == '' then return end
    local ok, err = pcall(function() exports[resource][method](exports[resource]) end)
    if not ok and LibConfig and LibConfig.Debug then
        print(('[codem-lib] Hud: %s:%s failed: %s'):format(resource, method, tostring(err)))
    end
end

local function fire(events)
    if type(events) ~= 'table' then return end
    for _, name in ipairs(events) do
        if type(name) == 'string' and name ~= '' then TriggerEvent(name) end
    end
end

local function targets()
    local out = {}
    for resource, methods in pairs(KNOWN) do out[resource] = methods end
    for resource, methods in pairs(cfg().resources or {}) do
        out[resource] = type(methods) == 'table' and methods or nil
    end
    return out
end

local function apply(hide)
    local settings = cfg()
    LocalPlayer.state:set(STATE, hide or nil, true)
    for resource, methods in pairs(targets()) do
        callTarget(resource, methods, hide)
    end
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
