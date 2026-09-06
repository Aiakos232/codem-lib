-- Which appearance script is on the server. Every wardrobe call (opening the
-- outfit menu, reading and dressing the ped, saving the skin) goes through the
-- adapter registered for this name in modules/wardrobe/client.lua.
local CANDIDATES = {
    -- codem-clothing first: it also answers to the illenium name, so looking for
    -- illenium would find it anyway, only through the compatibility layer instead
    -- of its own exports
    'codem-clothing',
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
