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
    'rcore_clothing',
    'illenium-appearance',
    'fivem-appearance',
    -- illenium forks with the same exports
    'qs-appearance',
    '4bit_appearance',
    'qf_skinmenu',
    'crm-appearance',
    'tgiann-clothing',
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
    ['crm-appearance'] = true, ['tgiann-clothing'] = true,
    ['rcore_clothing'] = GetCurrentResourceName(),
}

-- identifier: citizenid on QBCore / Qbox, users.identifier on ESX.
local STORED_APPEARANCE = {
    ['rcore_clothing'] = function(identifier)
        local data = exports['rcore_clothing']:getSkinByIdentifier(identifier)
        if type(data) ~= 'table' or data.skin == nil then return nil end
        return data.ped_model, data
    end,
}

---@param identifier string
local function storedAppearance(identifier)
    local name = provider()
    local read = STORED_APPEARANCE[name]
    if not read or GetResourceState(name) ~= 'started' then return nil end
    if type(identifier) ~= 'string' or identifier == '' then return false end

    local ok, model, data = pcall(read, identifier)
    if not ok then
        print(('[codem-lib] Wardrobe.StoredAppearance via "%s" failed: %s'):format(name, tostring(model)))
        return false
    end
    if not data then return false end
    return { model = model, skin = { provider = name, components = {}, props = {}, data = data } }
end

exports('GetStoredAppearance', storedAppearance)

local KNOWN = {}
for i = 1, #CANDIDATES do KNOWN[CANDIDATES[i]] = true end

local function appearanceExportOf(name)
    local answeredBy = APPEARANCE_EXPORT[name]
    if not answeredBy or GetResourceState(name) ~= 'started' then return nil end
    return answeredBy == true and name or answeredBy
end

local function appearanceScript(active)
    local name = appearanceExportOf(active)
    if name then return name end
    for i = 1, #CANDIDATES do
        name = appearanceExportOf(CANDIDATES[i])
        if name then return name end
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
