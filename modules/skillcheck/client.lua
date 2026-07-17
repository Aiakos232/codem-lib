--[[
    Skill check (client) — blocking minigame gate. Returns true on pass.
    Selection via LibConfig.SkillCheck.provider ('auto' prefers a dedicated
    minigame resource, then ox_lib's skill check if it is running). ox_lib
    is optional.

    Exports:
      SkillCheck(difficulty, inputs?)
        difficulty: string | string[] (ox format: 'easy' | 'medium' | 'hard'
                    or a sequence like { 'easy', 'easy', 'medium' })
        inputs:     string[] keys, e.g. { 'w', 'a', 's', 'd' }
]]

local PROVIDERS = {
    ['ox'] = {
        run = function(difficulty, inputs)
            return exports.ox_lib:skillCheck(difficulty, inputs) == true
        end,
    },

    -- ps-ui circle minigame (count/speed derived from the ox difficulty).
    ['ps-ui'] = {
        run = function(difficulty)
            local count = type(difficulty) == 'table' and #difficulty or 1
            local done = nil
            exports['ps-ui']:Circle(function(success)
                done = success == true
            end, count, 20)
            while done == nil do Wait(50) end
            return done
        end,
    },
}

local CANDIDATES = { 'ps-ui' }

local function provider()
    local cfg = (LibConfig.SkillCheck and LibConfig.SkillCheck.provider) or 'auto'
    if cfg ~= 'auto' then return cfg end
    for _, res in ipairs(CANDIDATES) do
        if GetResourceState(res) == 'started' then return res end
    end
    -- ox_lib only if it is actually running; no native skill check fallback.
    if CodemOxReady() then return 'ox' end
    return 'none'
end

exports('SkillCheck', function(difficulty, inputs)
    local name = provider()
    local p = PROVIDERS[name]
    if not p then
        if name == 'none' then
            print('[codem-lib] SkillCheck: no provider running - install ox_lib or ps-ui, or set LibConfig.SkillCheck.provider')
        else
            print(('[codem-lib] SkillCheck: unknown provider "%s" - check LibConfig.SkillCheck.provider'):format(name))
        end
        return false
    end
    local ok, res = pcall(p.run, difficulty, inputs)
    if not ok then
        print(('[codem-lib] SkillCheck via "%s" failed: %s'):format(name, tostring(res)))
        return false
    end
    return res == true
end)
