--[[
    ox_lib compatibility bridge — codem-lib no longer HARD-depends on ox_lib.

    ox_lib registers its interface functions as resource exports
    (exports.ox_lib:notify / showTextUI / hideTextUI / progressBar / skillCheck),
    so codem-lib can use them WITHOUT including '@ox_lib/init.lua' and without the
    global `lib`. When ox_lib is not running, each module falls back to a
    dedicated provider or the framework native instead of crashing.

    Loaded as a shared_script, so both client and server see these globals.
]]

---True only while ox_lib is actually running. Checked lazily (resource state
---can still be 'starting' at load time), so call this at dispatch time.
---@return boolean
function CodemOxReady()
    return GetResourceState('ox_lib') == 'started'
end

---Deep table equality — replacement for ox_lib's `lib.table.matches`, used by the
---inventory providers to compare item metadata. Order-independent, recursive.
---@param t1 any
---@param t2 any
---@return boolean
function CodemTableMatches(t1, t2)
    if t1 == t2 then return true end

    local ty1, ty2 = type(t1), type(t2)
    if ty1 ~= ty2 then return false end
    if ty1 ~= 'table' then return t1 == t2 end

    for k, v1 in pairs(t1) do
        if not CodemTableMatches(v1, t2[k]) then return false end
    end
    for k in pairs(t2) do
        if t1[k] == nil then return false end
    end

    return true
end
