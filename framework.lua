--[[
    Framework bridge loader — the only line a consumer needs:

        shared_scripts { '@codem-lib/framework.lua' }

    Resolves the active framework (LibConfig.Framework > the consumer's
    Config.Framework > auto-detection) and loads ONLY that implementation
    into the consumer's own context, on the correct side (client/server).
    After this file runs, `CodemLib.Framework` points at the loaded side's
    bridge table (the internal `Framework.Client` / `Framework.Server`),
    so consumers call e.g. CodemLib.Framework.GetPlayerJob() on either side.
]]

-- Pull the lib config into this context if the consumer did not load it.
if type(LibConfig) ~= 'table' then
    local cfg = LoadResourceFile('codem-lib', 'config.lua')
    if cfg then
        local fn = load(cfg, '@@codem-lib/config.lua')
        if fn then fn() end
    end
end

local FW = (type(LibConfig) == 'table' and LibConfig.Framework)
    or (type(Config) == 'table' and Config.Framework)
    or 'auto'

if FW == 'auto' then
    if GetResourceState('qbx_core') == 'started' then
        FW = 'qbox'
    elseif GetResourceState('qb-core') == 'started' then
        FW = 'qb'
    elseif GetResourceState('es_extended') == 'started' then
        FW = 'esx'
    end
end

local DIR = (FW == 'qb' or FW == 'qbox') and 'qbcore' or FW == 'esx' and 'esx' or nil
if not DIR then
    print('[codem-lib] framework: no supported framework detected (qbx_core / qb-core / es_extended)')
    return
end

local side = IsDuplicityVersion() and 'server' or 'client'
local path = ('modules/framework/%s/%s.lua'):format(DIR, side)

local chunk = LoadResourceFile('codem-lib', path)
if not chunk then
    print(('[codem-lib] framework: could not read %s'):format(path))
    return
end

local fn, err = load(chunk, ('@@codem-lib/%s'):format(path))
if not fn then
    print(('[codem-lib] framework: %s'):format(err))
    return
end

fn()

-- Public alias: one namespace, no Client/Server split at the call site — the
-- right side's table was just loaded above. Shares the table reference, so
-- fields the implementation fills in later stay visible.
CodemLib = CodemLib or {}
CodemLib.Framework = IsDuplicityVersion() and Framework.Server or Framework.Client
