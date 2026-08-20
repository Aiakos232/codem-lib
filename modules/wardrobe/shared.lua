local CANDIDATES = {
    'illenium-appearance',
    'fivem-appearance',
    'qb-clothing',
    'rcore_clothing',
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
    return 'none'
end

exports('GetWardrobeProvider', provider)
