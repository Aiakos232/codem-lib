--[[
    Progress bar (client) — blocking timed-action indicator. Returns true when
    the bar completed, false when it was cancelled. Selection via
    LibConfig.Progress.provider ('auto' prefers a dedicated progressbar
    resource, falling back to ox_lib).

    Exports:
      Progress(opts)  -- { label, duration, canCancel?, useWhileDead?,
                      --   disable?: { move?, car?, combat?, mouse? },
                      --   anim?: table, prop?: table }  -> boolean completed
]]

local PROVIDERS = {
    ['ox'] = {
        run = function(opts)
            return lib.progressBar({
                label        = opts.label,
                duration     = opts.duration,
                useWhileDead = opts.useWhileDead or false,
                canCancel    = opts.canCancel ~= false,
                disable      = opts.disable,
                anim         = opts.anim,
                prop         = opts.prop,
            }) == true
        end,
    },

    -- qb progressbar (callback API, wrapped to a blocking boolean).
    ['progressbar'] = {
        run = function(opts)
            local done = nil
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
                } or nil,
            }, function(cancelled)
                done = not cancelled
            end)
            while done == nil do Wait(50) end
            return done
        end,
    },
}

local CANDIDATES = { 'progressbar' }

local function provider()
    local cfg = (LibConfig.Progress and LibConfig.Progress.provider) or 'auto'
    if cfg ~= 'auto' then return cfg end
    for _, res in ipairs(CANDIDATES) do
        if GetResourceState(res) == 'started' then return res end
    end
    return 'ox'
end

exports('Progress', function(opts)
    local name = provider()
    local p = PROVIDERS[name]
    if not p then
        print(('[codem-lib] Progress: unknown provider "%s" - check LibConfig.Progress.provider'):format(name))
        return false
    end
    local ok, res = pcall(p.run, opts)
    if not ok then
        print(('[codem-lib] Progress via "%s" failed: %s'):format(name, tostring(res)))
        return false
    end
    return res == true
end)
