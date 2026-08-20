local function started(name)
    return GetResourceState(name) == 'started'
end

local function tryExport(resource, method)
    if not started(resource) then return false end
    local ok = pcall(function()
        return exports[resource][method](exports[resource])
    end)
    return ok
end

local OPENERS = {
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
    local cfg = LibConfig.Wardrobe or {}

    if type(cfg.open) == 'function' then
        cfg.open()
        return true
    end

    if type(cfg.event) == 'string' and cfg.event ~= '' then
        TriggerEvent(cfg.event)
        return true
    end

    local name = exports['codem-lib']:GetWardrobeProvider()
    local opener = OPENERS[name]
    if not opener then return false end
    return opener() == true
end

exports('OpenWardrobe', open)
