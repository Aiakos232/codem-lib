-- Which appearance script is on the server. Every wardrobe call (opening the
-- outfit menu, reading and dressing the ped, saving the skin) goes through the
-- adapter registered for this name in modules/wardrobe/client.lua.
local CANDIDATES = {
    -- codem-clothing first: it also answers to the illenium name, so looking for
    -- illenium would find it anyway, only through the compatibility layer instead
    -- of its own exports
    'codem-clothing',
    -- codem-appearance before esx_skin/skinchanger: skinchanger is its
    -- dependency, so it is always running next to it
    'codem-appearance',
    'illenium-appearance',
    'fivem-appearance',
    -- illenium forks with the same exports
    'qs-appearance',
    '4bit_appearance',
    'qf_skinmenu',
    'crm-appearance',
    'tgiann-clothing',
    'rcore_clothing',
    -- 0r-clothing speaks qb-clothing's events and has its own exports
    '0r-clothing',
    'qb-clothing',
    'esx_skin',
    'skinchanger',
}

local function provider()
    local cfg = LibConfig.Wardrobe or {}
    local name = cfg.provider or 'auto'
    if name == false or name == 'none' then return 'none' end
    if name ~= 'auto' then return name end
    for i = 1, #CANDIDATES do
        if GetResourceState(CANDIDATES[i]) == 'started' then return CANDIDATES[i] end
    end
    if type(cfg.open) == 'function' then return 'custom' end
    if type(cfg.event) == 'string' and cfg.event ~= '' then return 'custom' end
    if type(cfg.setClothing) == 'function' then return 'custom' end
    return 'none'
end

exports('GetWardrobeProvider', provider)

-- setPedAppearance(ped, appearance) in illenium's shape, on any ped: what a character preview needs.
local APPEARANCE_EXPORT = {
    ['codem-clothing'] = true, ['illenium-appearance'] = true, ['fivem-appearance'] = true,
    ['qs-appearance'] = true, ['4bit_appearance'] = true, ['qf_skinmenu'] = true,
    ['crm-appearance'] = true, ['tgiann-clothing'] = true, ['rcore_clothing'] = true,
}

local KNOWN = {}
for i = 1, #CANDIDATES do KNOWN[CANDIDATES[i]] = true end

local function appearanceScript(active)
    if APPEARANCE_EXPORT[active] and GetResourceState(active) == 'started' then return active end
    for i = 1, #CANDIDATES do
        local name = CANDIDATES[i]
        if APPEARANCE_EXPORT[name] and GetResourceState(name) == 'started' then return name end
    end
    return nil
end

---@return { provider: string, known: boolean, appearanceScript: string|nil }
local function info()
    local name = provider()
    return {
        provider = name,
        known = KNOWN[name] == true,
        appearanceScript = appearanceScript(name),
    }
end

exports('GetWardrobeInfo', info)
