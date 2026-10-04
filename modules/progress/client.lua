--[[
    Progress bar (client) — blocking timed-action indicator. Returns true when
    the bar completed, false when it was cancelled. Selection via
    LibConfig.Progress.provider ('auto' prefers a dedicated progressbar
    resource, then ox_lib if it is running). ox_lib is optional.

    Exports:
      Progress(opts)  -- { label, duration, canCancel?, useWhileDead?,
                      --   disable?: { move?, car?, combat?, mouse? },
                      --   anim?: table, prop?: table }  -> boolean completed
      ProgressActive() -- true while the provider shows a bar, whoever started it
      CancelProgress() -- stops the bar the provider is showing
]]

-- ox shape { model, bone, pos, rot } (or a list of them) to qb progressbar's prop/propTwo
local function qbProp(prop)
    if type(prop) ~= 'table' then return nil end
    if prop[1] then return qbProp(prop[1]), qbProp(prop[2]) end
    if not prop.model then return nil end
    local pos, rot = prop.pos, prop.rot
    return {
        model = prop.model,
        bone = prop.bone or 60309,
        coords = pos and vector3(pos.x or pos[1] or 0.0, pos.y or pos[2] or 0.0, pos.z or pos[3] or 0.0) or vector3(0.0, 0.0, 0.0),
        rotation = rot and vector3(rot.x or rot[1] or 0.0, rot.y or rot[2] or 0.0, rot.z or rot[3] or 0.0) or vector3(0.0, 0.0, 0.0),
    }
end

local PROVIDERS = {
    ['ox'] = {
        run = function(opts)
            return exports.ox_lib:progressBar({
                label        = opts.label,
                duration     = opts.duration,
                useWhileDead = opts.useWhileDead or false,
                canCancel    = opts.canCancel ~= false,
                disable      = opts.disable,
                anim         = opts.anim,
                prop         = opts.prop,
            }) == true
        end,
        active = function() return exports.ox_lib:progressActive() == true end,
        cancel = function() exports.ox_lib:cancelProgress() end,
    },

    -- qb progressbar (callback API, wrapped to a blocking boolean).
    ['progressbar'] = {
        run = function(opts)
            local done = nil
            local prop, propTwo = qbProp(opts.prop)
            exports['progressbar']:Progress({
                name = ('codemlib_%s'):format(GetGameTimer()),
                duration = opts.duration,
                label = opts.label,
                useWhileDead = opts.useWhileDead or false,
                canCancel = opts.canCancel ~= false,
                controlDisables = {
                    disableMovement    = opts.disable and opts.disable.move or false,
                    disableCarMovement = opts.disable and opts.disable.car or false,
                    disableCombat      = opts.disable and opts.disable.combat or false,
                    disableMouse       = opts.disable and opts.disable.mouse or false,
                },
                animation = opts.anim and {
                    animDict = opts.anim.dict,
                    anim = opts.anim.clip,
                    flags = opts.anim.flag,
                    task = opts.anim.scenario,
                } or nil,
                prop = prop,
                propTwo = propTwo,
            }, function(cancelled)
                done = not cancelled
            end)
            while done == nil do Wait(50) end
            return done
        end,
        active = function() return exports['progressbar']:isDoingSomething() == true end,
        cancel = function() ExecuteCommand('cancelprogress') end,
    },
}

local CANDIDATES = { 'progressbar' }

local function provider()
    local cfg = (LibConfig.Progress and LibConfig.Progress.provider) or 'auto'
    if cfg ~= 'auto' then return cfg end
    for _, res in ipairs(CANDIDATES) do
        if GetResourceState(res) == 'started' then return res end
    end
    -- ox_lib only if it is actually running; no native progressbar fallback.
    if CodemOxReady() then return 'ox' end
    return 'none'
end

exports('Progress', function(opts)
    local name = provider()
    local p = PROVIDERS[name]
    if not p then
        if name == 'none' then
            print('[codem-lib] Progress: no provider running - install ox_lib or qb progressbar, or set LibConfig.Progress.provider')
        else
            print(('[codem-lib] Progress: unknown provider "%s" - check LibConfig.Progress.provider'):format(name))
        end
        return false
    end
    local ok, res = pcall(p.run, opts)
    if not ok then
        print(('[codem-lib] Progress via "%s" failed: %s'):format(name, tostring(res)))
        return false
    end
    return res == true
end)

exports('ProgressActive', function()
    local p = PROVIDERS[provider()]
    if not p or not p.active then return false end
    local ok, active = pcall(p.active)
    return ok and active == true
end)

exports('CancelProgress', function()
    local p = PROVIDERS[provider()]
    if not p or not p.cancel then return false end
    return pcall(p.cancel)
end)
