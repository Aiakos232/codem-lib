-- Wardrobe: one face for every appearance script.
--
-- Two jobs. Opening the outfit menu (OpenWardrobe, the older half), and the
-- clothing bridge the inventory's clothing items use (the newer half):
--
--   GetPedClothing(ped)                     what the ped wears, read off the ped itself
--   SetPedClothing(ped, components, props)  dress the ped through the appearance
--                                           script, so its own idea of the skin
--                                           (esx skinchanger, qb-clothing, ...)
--                                           moves with the ped
--   SavePedClothing()                       persist the current look through the
--                                           appearance script's own save path
--   codem-lib:wardrobe:changed              local event fired when the appearance
--                                           script dressed the player on its own
--                                           (spawn, shop, outfit, creator)
--
-- Components are lists of { component_id, drawable, texture, palette? }, props
-- { prop_id, drawable, texture }; a drawable of -1 clears a prop. Drawables are
-- the game's plain indices.
--
-- A script codem-lib does not know: fill LibConfig.Wardrobe.setClothing /
-- saveClothing / changedEvents in config.lua, or add an ADAPTERS entry below.

local function started(name)
    return GetResourceState(name) == 'started'
end

local function tryExport(resource, method, ...)
    if not started(resource) then return false end
    local args = table.pack(...)
    local ok, result = pcall(function()
        return exports[resource][method](exports[resource], table.unpack(args, 1, args.n))
    end)
    if not ok then return false end
    return true, result
end

local function cfg()
    return LibConfig.Wardrobe or {}
end

local function currentProvider()
    return exports['codem-lib']:GetWardrobeProvider()
end

-- ---------------------------------------------------------------- opening the outfit menu

local OPENERS = {
    ['codem-clothing'] = function()
        if not started('codem-clothing') then return false end
        if tryExport('codem-clothing', 'OpenWardrobe') then return true end
        TriggerEvent('codem-clothing:client:openOutfitMenu')
        return true
    end,
    ['illenium-appearance'] = function()
        if not started('illenium-appearance') then return false end
        TriggerEvent('illenium-appearance:client:openOutfitMenu')
        return true
    end,
    ['fivem-appearance'] = function()
        if not started('fivem-appearance') then return false end
        if tryExport('fivem-appearance', 'openOutfitMenu') then return true end
        TriggerEvent('fivem-appearance:client:openOutfitMenu')
        return true
    end,
    -- illenium forks keep illenium's event names
    ['qs-appearance'] = function()
        if not started('qs-appearance') then return false end
        TriggerEvent('illenium-appearance:client:openOutfitMenu')
        return true
    end,
    ['4bit_appearance'] = function()
        if not started('4bit_appearance') then return false end
        TriggerEvent('illenium-appearance:client:openOutfitMenu')
        return true
    end,
    ['qf_skinmenu'] = function()
        if not started('qf_skinmenu') then return false end
        TriggerEvent('illenium-appearance:client:openOutfitMenu')
        return true
    end,
    ['crm-appearance'] = function()
        if not started('crm-appearance') then return false end
        if tryExport('crm-appearance', 'crm_open_outfits') then return true end
        TriggerEvent('crm-appearance:open-outfits')
        return true
    end,
    ['tgiann-clothing'] = function()
        if not started('tgiann-clothing') then return false end
        if tryExport('tgiann-clothing', 'OpenOutfitStash') then return true end
        TriggerEvent('qb-clothing:client:openOutfitMenu')
        return true
    end,
    ['0r-clothing'] = function()
        if not started('0r-clothing') then return false end
        TriggerEvent('qb-clothing:client:openOutfitMenu')
        return true
    end,
    ['qb-clothing'] = function()
        if not started('qb-clothing') then return false end
        TriggerEvent('qb-clothing:client:openOutfitMenu')
        return true
    end,
    ['esx_skin'] = function()
        if not started('esx_skin') then return false end
        TriggerEvent('esx_skin:openSaveableMenu')
        return true
    end,
    ['skinchanger'] = function()
        if started('esx_skin') then
            TriggerEvent('esx_skin:openSaveableMenu')
            return true
        end
        return false
    end,
    ['rcore_clothing'] = function()
        if not started('rcore_clothing') then return false end
        if tryExport('rcore_clothing', 'openChangingRoom') then return true end
        if tryExport('rcore_clothing', 'openOutfitMenu') then return true end
        if tryExport('rcore_clothing', 'openMenu') then return true end
        TriggerEvent('rcore_clothing:openChangingRoom')
        return true
    end,
}

local function open()
    local c = cfg()

    if type(c.open) == 'function' then
        c.open()
        return true
    end

    if type(c.event) == 'string' and c.event ~= '' then
        TriggerEvent(c.event)
        return true
    end

    local opener = OPENERS[currentProvider()]
    if not opener then return false end
    return opener() == true
end

exports('OpenWardrobe', open)

-- ---------------------------------------------------------------- reading the ped

-- Every drawable a garment can live on. 0 (head) and 2 (hair) belong to the
-- character, not the wardrobe.
local COMPONENTS = { 1, 3, 4, 5, 6, 7, 8, 9, 10, 11 }
local PROPS = { 0, 1, 2, 6, 7 }

---@return { components: table<number, {drawable:number, texture:number, palette:number}>, props: table<number, {drawable:number, texture:number}> }
local function getClothing(ped)
    ped = ped or PlayerPedId()
    local out = { components = {}, props = {} }
    for _, id in ipairs(COMPONENTS) do
        out.components[id] = {
            drawable = GetPedDrawableVariation(ped, id),
            texture = GetPedTextureVariation(ped, id),
            palette = GetPedPaletteVariation(ped, id),
        }
    end
    for _, id in ipairs(PROPS) do
        out.props[id] = {
            drawable = GetPedPropIndex(ped, id),
            texture = GetPedPropTextureIndex(ped, id),
        }
    end
    return out
end

-- ---------------------------------------------------------------- dressing

-- Plain natives: what every adapter falls back to, and all a script needs when
-- it reads the ped back before saving (illenium and its forks do).
local function nativeSet(ped, components, props)
    for _, c in ipairs(components or {}) do
        SetPedComponentVariation(ped, c.component_id, c.drawable, c.texture or 0, c.palette or 0)
    end
    for _, p in ipairs(props or {}) do
        if (p.drawable or -1) < 0 then
            ClearPedProp(ped, p.prop_id)
        else
            SetPedPropIndex(ped, p.prop_id, p.drawable, p.texture or 0, true)
        end
    end
end

-- skinchanger (esx_skin, tgiann, rcore, codem-appearance) names every drawable
local SKIN_COMPONENT = {
    [1] = { 'mask_1', 'mask_2' },
    [3] = { 'arms', 'arms_2' },
    [4] = { 'pants_1', 'pants_2' },
    [5] = { 'bags_1', 'bags_2' },
    [6] = { 'shoes_1', 'shoes_2' },
    [7] = { 'chain_1', 'chain_2' },
    [8] = { 'tshirt_1', 'tshirt_2' },
    [9] = { 'bproof_1', 'bproof_2' },
    [10] = { 'decals_1', 'decals_2' },
    [11] = { 'torso_1', 'torso_2' },
}
local SKIN_PROP = {
    [0] = { 'helmet_1', 'helmet_2' },
    [1] = { 'glasses_1', 'glasses_2' },
    [2] = { 'ears_1', 'ears_2' },
    [6] = { 'watches_1', 'watches_2' },
    [7] = { 'bracelets_1', 'bracelets_2' },
}

--- { key = value } list in skinchanger's words, drawables before textures so a
--- texture never lands on the previous drawable.
local function skinChanges(components, props)
    local list = {}
    for _, c in ipairs(components or {}) do
        local keys = SKIN_COMPONENT[c.component_id]
        if keys then
            list[#list + 1] = { keys[1], c.drawable }
            list[#list + 1] = { keys[2], c.texture or 0 }
        end
    end
    for _, p in ipairs(props or {}) do
        local keys = SKIN_PROP[p.prop_id]
        if keys then
            list[#list + 1] = { keys[1], p.drawable }
            list[#list + 1] = { keys[2], p.texture or 0 }
        end
    end
    return list
end

-- qb-clothing keeps an outfit table keyed by garment name
local QB_COMPONENT = { [1] = 'mask', [3] = 'arms', [4] = 'pants', [5] = 'bag', [6] = 'shoes', [7] = 'accessory', [8] = 't-shirt', [9] = 'vest', [10] = 'decals', [11] = 'torso2' }
local QB_PROP = { [0] = 'hat', [1] = 'glass', [2] = 'ear', [6] = 'watch', [7] = 'bracelet' }

local function qbOutfit(components, props)
    local outfit = {}
    for _, c in ipairs(components or {}) do
        local key = QB_COMPONENT[c.component_id]
        if key then outfit[key] = { item = c.drawable, texture = c.texture or 0 } end
    end
    for _, p in ipairs(props or {}) do
        local key = QB_PROP[p.prop_id]
        if key then outfit[key] = { item = p.drawable, texture = p.texture or 0 } end
    end
    return outfit
end

-- illenium's shape, which its forks share
local function illeniumSet(resource)
    return function(ped, components, props)
        local comps, ps = {}, {}
        for i, c in ipairs(components or {}) do comps[i] = { component_id = c.component_id, drawable = c.drawable, texture = c.texture or 0 } end
        for i, p in ipairs(props or {}) do ps[i] = { prop_id = p.prop_id, drawable = p.drawable, texture = p.texture or 0 } end
        local okC = #comps == 0 or tryExport(resource, 'setPedComponents', ped, comps)
        local okP = #ps == 0 or tryExport(resource, 'setPedProps', ped, ps)
        if not (okC and okP) then nativeSet(ped, components, props) end
    end
end

local function illeniumSave(resource)
    return function()
        local ok, appearance = tryExport(resource, 'getPedAppearance', PlayerPedId())
        if not ok or type(appearance) ~= 'table' then return false end
        TriggerServerEvent('illenium-appearance:server:saveAppearance', appearance)
        return true
    end
end

-- Events after which the appearance script has dressed the player itself.
-- Every framework's "character loaded" is in the shared list; each adapter adds
-- the ones its script fires after a shop or an outfit.
local LOADED_EVENTS = {
    'QBCore:Client:OnPlayerLoaded',
    'qbx_core:client:playerLoggedIn',
    'esx:playerLoaded',
    'ND:characterLoaded',
    'ox:playerLoaded',
}

local ADAPTERS = {
    ['codem-clothing'] = {
        set = illeniumSet('codem-clothing'),
        -- only the clothes are written, the rest of the stored skin is left alone
        save = function()
            if tryExport('codem-clothing', 'savePedClothing') then return true end
            return illeniumSave('codem-clothing')()
        end,
        events = { 'codem-clothing:client:appearanceChanged' },
    },
    ['illenium-appearance'] = {
        set = illeniumSet('illenium-appearance'),
        save = illeniumSave('illenium-appearance'),
        events = { '17mov_CharacterSystem:SkinMenuClosed' },
    },
    ['fivem-appearance'] = {
        set = illeniumSet('fivem-appearance'),
        save = function()
            local ok, appearance = tryExport('fivem-appearance', 'getPedAppearance', PlayerPedId())
            if not ok or type(appearance) ~= 'table' then return false end
            TriggerServerEvent('fivem-appearance:server:saveAppearance', appearance)
            return true
        end,
        events = {},
    },
    ['qs-appearance'] = {
        set = illeniumSet('qs-appearance'),
        save = illeniumSave('qs-appearance'),
        events = { '17mov_CharacterSystem:SkinMenuClosed' },
    },
    ['4bit_appearance'] = {
        set = illeniumSet('4bit_appearance'),
        save = illeniumSave('4bit_appearance'),
        events = { '17mov_CharacterSystem:SkinMenuClosed' },
    },
    ['qf_skinmenu'] = {
        set = illeniumSet('qf_skinmenu'),
        save = illeniumSave('qf_skinmenu'),
        events = { '17mov_CharacterSystem:SkinMenuClosed' },
    },
    ['crm-appearance'] = {
        set = function(ped, components, props)
            local clothing, accessories = {}, {}
            for i, c in ipairs(components or {}) do clothing[i] = { crm_id = c.component_id, crm_style = c.drawable, crm_texture = c.texture or 0 } end
            for i, p in ipairs(props or {}) do accessories[i] = { crm_id = p.prop_id, crm_style = p.drawable, crm_texture = p.texture or 0 } end
            local okC = #clothing == 0 or tryExport('crm-appearance', 'crm_set_ped_clothing', ped, clothing)
            local okA = #accessories == 0 or tryExport('crm-appearance', 'crm_set_ped_accessories', ped, accessories)
            if not (okC and okA) then nativeSet(ped, components, props) end
        end,
        save = function()
            return tryExport('crm-appearance', 'crm_save_appearance', nil, function() end, true) == true
        end,
        events = { 'crm-appearance:outfit-changed' },
    },
    ['tgiann-clothing'] = {
        set = function(ped, components, props)
            local changes = skinChanges(components, props)
            local ok = true
            for _, change in ipairs(changes) do
                if not tryExport('tgiann-clothing', 'ChangeComponentValue', change[1], change[2]) then ok = false end
            end
            if not ok or #changes == 0 then nativeSet(ped, components, props) end
        end,
        save = function()
            return tryExport('tgiann-clothing', 'SaveSkin') == true
        end,
        events = { 'qb-clothing:client:loadPlayerClothing' },
    },
    ['rcore_clothing'] = {
        set = function(ped, components, props)
            local partial = {}
            for _, change in ipairs(skinChanges(components, props)) do partial[change[1]] = change[2] end
            if next(partial) then
                TriggerEvent('skinchanger:loadSkin', partial)
            else
                nativeSet(ped, components, props)
            end
        end,
        save = function()
            TriggerEvent('rcore_clothing:saveCurrentSkin')
            return true
        end,
        events = { 'rcore_clothing:charcreator:done', 'rcore_clothing:onClothingShopClosed', 'rcore_clothing:outfitChanged' },
    },
    ['0r-clothing'] = {
        set = function(ped, components, props)
            local outfit = qbOutfit(components, props)
            if next(outfit) then
                TriggerEvent('0r-clothing:loadOutfit:client', { outfitData = outfit })
            else
                nativeSet(ped, components, props)
            end
        end,
        save = function()
            local ok, clothing = tryExport('0r-clothing', 'getPlayerClothing')
            if not ok or type(clothing) ~= 'table' then return false end
            TriggerServerEvent('qb-clothing:saveSkin', GetEntityModel(PlayerPedId()), json.encode(clothing))
            return true
        end,
        events = { '0r-clothing:client:loadPlayerClothing', 'qb-clothing:client:loadPlayerClothing' },
    },
    ['qb-clothing'] = {
        set = function(ped, components, props)
            local outfit = qbOutfit(components, props)
            if next(outfit) then
                TriggerEvent('qb-clothing:client:loadOutfit', { outfitData = outfit })
            else
                nativeSet(ped, components, props)
            end
        end,
        save = function()
            local ok, skin = tryExport('qb-clothing', 'GetSkinData')
            if not ok or type(skin) ~= 'table' then return false end
            TriggerServerEvent('qb-clothing:saveSkin', GetEntityModel(PlayerPedId()), json.encode(skin))
            return true
        end,
        events = { 'qb-clothing:client:loadPlayerClothing', 'qb-clothing:client:loadOutfit' },
    },
    ['esx_skin'] = {
        set = function(ped, components, props)
            local changes = skinChanges(components, props)
            for _, change in ipairs(changes) do TriggerEvent('skinchanger:change', change[1], change[2]) end
            if #changes == 0 then nativeSet(ped, components, props) end
        end,
        save = function()
            local ok, skin = tryExport('skinchanger', 'GetSkin')
            if not ok or type(skin) ~= 'table' then
                -- older skinchanger: the skin comes back through a callback event
                local done = false
                TriggerEvent('skinchanger:getSkin', function(current) skin = current done = true end)
                local waited = 0
                while not done and waited < 1000 do Wait(10) waited = waited + 10 end
                if type(skin) ~= 'table' then return false end
            end
            TriggerServerEvent('esx_skin:save', skin)
            return true
        end,
        events = { 'esx_skin:onSkinSaved' },
    },
}
ADAPTERS['skinchanger'] = ADAPTERS['esx_skin']
ADAPTERS['codem-appearance'] = ADAPTERS['esx_skin']

local function adapter()
    local c = cfg()
    if type(c.setClothing) == 'function' or type(c.saveClothing) == 'function' then
        return {
            set = type(c.setClothing) == 'function' and c.setClothing or nativeSet,
            save = type(c.saveClothing) == 'function' and c.saveClothing or function() return false end,
            events = type(c.changedEvents) == 'table' and c.changedEvents or {},
        }
    end
    return ADAPTERS[currentProvider()]
end

local function setClothing(ped, components, props)
    ped = ped or PlayerPedId()
    local a = adapter()
    if a and a.set then
        a.set(ped, components, props)
    else
        nativeSet(ped, components, props)
    end
    return true
end

local function saveClothing()
    local a = adapter()
    if not a or not a.save then return false end
    local ok, result = pcall(a.save)
    return ok and result == true
end

exports('GetPedClothing', getClothing)
exports('SetPedClothing', setClothing)
exports('SavePedClothing', saveClothing)

-- ---------------------------------------------------------------- "the script dressed me"

local CHANGED = 'codem-lib:wardrobe:changed'
local announced = {}

local function announce(reason)
    -- one event per burst: a spawn fires three of these within a few frames
    if announced[reason] then return end
    announced[reason] = true
    SetTimeout(250, function()
        announced[reason] = nil
        TriggerEvent(CHANGED, reason)
    end)
end

local function listen(event)
    if announced['listening:' .. event] then return end
    announced['listening:' .. event] = true
    RegisterNetEvent(event, function() announce(event) end)
end

CreateThread(function()
    -- the provider is only known once everything has started
    Wait(2500)
    for _, event in ipairs(LOADED_EVENTS) do listen(event) end
    local a = adapter()
    for _, event in ipairs(a and a.events or {}) do listen(event) end
    for _, event in ipairs(cfg().changedEvents or {}) do listen(event) end
end)
