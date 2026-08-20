local CANDIDATES = {
    'qbx_garages', 'qb-garages', 'cd_garage', 'qs-advancedgarages',
}

local function provider()
    local cfg = (LibConfig.Garage and LibConfig.Garage.provider) or 'auto'
    if cfg == false or cfg == 'none' then return 'none' end
    if cfg and cfg ~= 'auto' then return cfg end
    for i = 1, #CANDIDATES do
        if GetResourceState(CANDIDATES[i]) == 'started' then return CANDIDATES[i] end
    end
    return 'none'
end

local function garageName(id, pointId)
    if provider() == 'qbx_garages' then
        return ('motel_%s'):format(id)
    end
    return ('motel_%s_%s'):format(id, pointId or 0)
end

exports('GetGarageProvider', provider)
exports('GarageName', garageName)
