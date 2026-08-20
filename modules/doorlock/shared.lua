local CANDIDATES = { 'ox_doorlock', 'qb-doorlock' }

local function provider()
    local cfg = (LibConfig.Doorlock and LibConfig.Doorlock.provider) or 'auto'
    if cfg and cfg ~= 'auto' then return cfg end
    for i = 1, #CANDIDATES do
        if GetResourceState(CANDIDATES[i]) == 'started' then return CANDIDATES[i] end
    end
    return 'native'
end

exports('GetDoorlockProvider', provider)
