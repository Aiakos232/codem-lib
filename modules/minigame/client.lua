
local function level(opts)
    local d = type(opts) == 'table' and opts.difficulty or nil
    if d == 'medium' then d = 'normal' end
    return (d == 'easy' or d == 'hard') and d or 'normal'
end

local OX_RUNS = {
    easy   = { 'easy', 'easy' },
    normal = { 'easy', 'medium', 'medium' },
    hard   = { 'medium', 'hard', 'hard' },
}

local function oxSkill(opts)
    return exports.ox_lib:skillCheck(OX_RUNS[level(opts)]) == true
end

local function awaitCallback(start)
    local done = nil
    start(function(success) done = success == true end)
    while done == nil do Wait(50) end
    return done
end

local PROVIDERS = {
    ['codem-supreme-minigames'] = {
        games = {
            lockpick = 'lockpick', hotwire = 'hotwire', wirecut = 'wirecut', drill = 'drill', lugnut = 'lugnut',
            mash = 'mash', sequence = 'sequence', safe = 'safe', thermite = 'thermite', hack = 'pincrack', skill = 'skillbar',
        },
        run = function(game, opts)
            local ok = exports['codem-supreme-minigames']:Play(game, { difficulty = level(opts) })
            return ok == true
        end,
    },

    -- every export takes 'easy'|'medium'|'hard' and returns { success = bool, reason = ... }
    ['fa_minigames'] = {
        games = { lockpick = 'Lockpick', drill = 'Drill', wirecut = 'Wires', sequence = 'Sequence', hack = 'Circuit', skill = 'Skillbar' },
        run = function(game, opts)
            local lv = level(opts)
            local r = exports.fa_minigames[game](exports.fa_minigames, lv == 'normal' and 'medium' or lv)
            return type(r) == 'table' and r.success == true
        end,
    },

    -- blocking, returns a boolean; (rounds, difficulty 1-100[, keys])
    ['bl_ui'] = {
        games = { mash = 'KeySpam', sequence = 'KeyCircle', hack = 'NumberSlide', skill = 'CircleProgress' },
        run = function(game, opts)
            local lv = level(opts)
            local rounds = lv == 'easy' and 1 or lv == 'hard' and 3 or 2
            local diff = lv == 'easy' and 30 or lv == 'hard' and 75 or 50
            if game == 'KeyCircle' or game == 'NumberSlide' then
                return exports.bl_ui[game](exports.bl_ui, rounds, diff, game == 'KeyCircle' and 4 or 5) == true
            end
            return exports.bl_ui[game](exports.bl_ui, rounds, diff) == true
        end,
    },

    -- blocking, returns a boolean; (title, 'easy'|'medium'|'hard')
    ['lation_ui'] = {
        games = { sequence = 'signalBreach', hack = 'patternLock', skill = 'skillCheck' },
        run = function(game, opts)
            local lv = level(opts)
            return exports.lation_ui[game](exports.lation_ui, nil, lv == 'normal' and 'medium' or lv) == true
        end,
    },

    -- callback export (opts, cb); skill_bar answers 'perfect' | 'success' | 'failed'
    ['boii_minigames'] = {
        games = { mash = 'button_mash', wirecut = 'wire_cut', safe = 'safe_crack', hack = 'chip_hack', skill = 'skill_bar' },
        run = function(game, opts)
            local lv = level(opts)
            local o = {}
            if game == 'safe_crack' then o.difficulty = lv == 'easy' and 1 or lv == 'hard' and 5 or 3
            elseif game == 'button_mash' then o.difficulty = lv == 'easy' and 3 or lv == 'hard' and 8 or 5 end
            return awaitCallback(function(cb)
                exports.boii_minigames[game](exports.boii_minigames, o, function(r) cb(r == true or r == 'success' or r == 'perfect') end)
            end)
        end,
    },

    -- callback exports; only Circle blocks, the rest return at once and answer through the callback
    ['ps-ui'] = {
        games = { thermite = 'thermite', hack = 'varhack', skill = 'circle' },
        run = function(game, opts)
            local lv = level(opts)
            if game == 'circle' then
                local count = lv == 'easy' and 2 or lv == 'hard' and 4 or 3
                return awaitCallback(function(cb) exports['ps-ui']:Circle(cb, count, 20) end)
            elseif game == 'thermite' then
                local grid = lv == 'easy' and 5 or lv == 'hard' and 7 or 6
                return awaitCallback(function(cb) exports['ps-ui']:Thermite(cb, 10, grid, 3) end)
            end
            local blocks = lv == 'easy' and 3 or lv == 'hard' and 7 or 5
            return awaitCallback(function(cb) exports['ps-ui']:VarHack(cb, blocks, 20) end)
        end,
    },

    -- one callback export: (cb, 'path'|'spot'|'math', settings?)
    ['glow_minigames'] = {
        games = { hack = 'path', sequence = 'spot', skill = 'spot' },
        run = function(game)
            return awaitCallback(function(cb) exports['glow_minigames']:StartMinigame(cb, game) end)
        end,
    },

    -- blocking, returns a boolean
    ['qb-minigames'] = {
        games = { lockpick = 'Lockpick', hack = 'Hacking', skill = 'Skillbar' },
        run = function(game, opts)
            local lv = level(opts)
            if game == 'Lockpick' then return exports['qb-minigames']:Lockpick(lv == 'easy' and 5 or lv == 'hard' and 2 or 3) == true end
            if game == 'Hacking' then return exports['qb-minigames']:Hacking(lv == 'easy' and 3 or lv == 'hard' and 6 or 4, 20) == true end
            return exports['qb-minigames']:Skillbar(lv == 'normal' and 'medium' or lv, '1234') == true
        end,
    },

    ['ox'] = {
        games = { skill = 'skill' },
        run = function(_, opts) return oxSkill(opts) end,
    },
}

local CANDIDATES = { 'codem-supreme-minigames', 'fa_minigames', 'bl_ui', 'lation_ui', 'boii_minigames', 'ps-ui', 'glow_minigames', 'qb-minigames' }

local function provider()
    local cfg = (LibConfig.Minigame and LibConfig.Minigame.provider) or 'auto'
    if cfg ~= 'auto' then return cfg end
    for _, res in ipairs(CANDIDATES) do
        if GetResourceState(res) == 'started' then return res end
    end
    if CodemOxReady() then return 'ox' end
    return 'none'
end

local function play(kind, opts)
    local name = provider()
    local p = PROVIDERS[name]
    if not p then
        print(('[codem-lib] Minigame: %s - install a minigame resource or set LibConfig.Minigame.provider'):format(
            name == 'none' and 'no provider running' or ('unknown provider "' .. tostring(name) .. '"')))
        return false
    end
    local game = p.games[kind] or p.games.skill
    local ok, res = pcall(p.run, game, opts)
    if not ok then
        print(('[codem-lib] Minigame via "%s" failed: %s'):format(name, tostring(res)))
        return false
    end
    if res == nil then
        if CodemOxReady() then return oxSkill(opts) end
        return true
    end
    return res == true
end

exports('Minigame', play)
exports('MinigameProvider', provider)
