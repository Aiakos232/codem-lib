--[[
    Boot summary (server) — prints one block with every resolved provider so
    the console shows the whole bridge picture at a glance. Detection mirrors
    the per-module resolvers (config override first, then first running
    resource).
]]

local function detect(cfg, candidates, fallback)
    if cfg and cfg ~= 'auto' then return cfg end
    for _, res in ipairs(candidates) do
        if GetResourceState(res) == 'started' then return res end
    end
    return fallback or 'none'
end

--- How many resources are running right now.
local function startedCount()
    local n = 0
    for i = 0, GetNumResources() - 1 do
        if GetResourceState(GetResourceByFindIndex(i)) == 'started' then n = n + 1 end
    end
    return n
end

--- The provider table as ordered { name, value } rows. Providers are looked
--- up again on every call anyway; this is only what the console shows.
local function summary()
    local framework = detect(LibConfig.Framework, { 'qbx_core', 'qb-core', 'es_extended' })
    if framework == 'qbx_core' then framework = 'qbox'
    elseif framework == 'qb-core' then framework = 'qb'
    elseif framework == 'es_extended' then framework = 'esx' end

    local inventory = detect(LibConfig.Inventory and LibConfig.Inventory.provider, {
        'ox_inventory', 'qb-inventory', 'ps-inventory', 'qs-inventory',
        'codem-inventory', 'core_inventory', 'tgiann-inventory', 'origen_inventory',
        'ak47_inventory', 'jaksam_inventory', 'jpr-inventory', 'S-inventory',
    })

    local society = detect(LibConfig.Society and LibConfig.Society.provider, {
        'qb-banking', 'qb-management', 'Renewed-Banking', 'okokBanking',
        'fd_banking', 'tgg-banking', 'tgiann-bank', 'qs-banking',
        'wasabi_banking', 'snipe-banking', 'crm-banking', 'kartik-banking',
        'p_banking', 'nfs-banking', 'nfs-billing', 'RxBanking',
        'sd-multijob', 'vms_bossmenu', 'nass_bossmenu', 'xnr-bossmenu',
        'esx_addonaccount',
    })
    if LibConfig.Society and LibConfig.Society.enabled == false then
        society = society .. ' (disabled)'
    end

    local vehiclekeys = detect(LibConfig.VehicleKeys and LibConfig.VehicleKeys.provider, {
        'qbx_vehiclekeys', 'qb-vehiclekeys', 'wasabi_carlock', 'Renewed-Vehiclekeys',
        'MrNewbVehicleKeys', 'vehicles_keys', 'tgiann-hotwire', 'mVehicle',
        'okokGarage', 'cd_garage', 'ND_Core',
        '0r-vehiclekeys', 'LifeSaver_KeySystem', 'ak47_qb_vehiclekeys', 'ak47_vehiclekeys',
        'brutal_carkeys', 'filo_vehiclekey', 'ic3d_vehiclekeys', 'is_vehiclekeys',
        'mk_vehiclekeys', 'mm_carkeys', 'p_carkeys', 'qs-vehiclekeys', 'rd_vehiclekeys',
    })

    local fuel = detect(LibConfig.Fuel and LibConfig.Fuel.provider, {
        'ox_fuel', 'LegacyFuel', 'cdn-fuel', 'qb-fuel', 'lc_fuel', 'Renewed-Fuel',
        'myFuel', 'okokGasStation', 'qs-fuelstations', 'rcore_fuel', 'x-fuel',
    })

    local target = detect(LibConfig.Target and LibConfig.Target.provider, {
        'ox_target', 'qb-target',
    })

    local billing = detect(LibConfig.Billing and LibConfig.Billing.provider, {
        'codem-phone', 'codem-billingv2',
    })
    if LibConfig.Billing and (LibConfig.Billing.enabled == false or LibConfig.Billing.provider == false) then
        billing = 'none (disabled)'
    end

    local phone = detect(LibConfig.Phone and LibConfig.Phone.provider, {
        'codem-phone', 'lb-phone', 'qs-smartphone-pro', 'qs-smartphone', 'cylex_phone', '17mov_Phone',
    }, 'framework')

    local medical = detect(LibConfig.Medical and LibConfig.Medical.provider, {
        'wasabi_ambulance_v2', 'wasabi_ambulance', 'qs-medical-creator',
        'ars_ambulancejob', 'tk_ambulancejob', 'qbx_medical', 'qb-ambulancejob',
        'esx_ambulancejob',
    })
    if LibConfig.Medical and LibConfig.Medical.enabled == false then
        medical = medical .. ' (disabled)'
    end

    local notify = detect(LibConfig.Notify and LibConfig.Notify.provider, {
        'codem-notification', 'okokNotify', 'brutal_notify', 'g-notifications',
        'is_ui', 'lation_ui', 'vms_notifyv2', 'wasabi_uikit',
        'mythic_notify', '17mov_Hud', 'gs-notify',
    }, 'ox')

    local doorlock = detect(LibConfig.Doorlock and LibConfig.Doorlock.provider, {
        'ox_doorlock', 'qb-doorlock',
    }, 'native')

    local garage = detect(LibConfig.Garage and LibConfig.Garage.provider, {
        'qbx_garages', 'qb-garages', 'cd_garage', 'qs-advancedgarages',
    }, 'none')
    if LibConfig.Garage and (LibConfig.Garage.provider == 'none' or LibConfig.Garage.provider == false) then
        garage = 'none'
    end

    local wardrobe = detect(LibConfig.Wardrobe and LibConfig.Wardrobe.provider, {
        'codem-clothing', 'illenium-appearance', 'fivem-appearance', 'qs-appearance', '4bit_appearance',
        'qf_skinmenu', 'crm-appearance', 'tgiann-clothing', 'rcore_clothing', '0r-clothing', 'qb-clothing',
        'esx_skin', 'skinchanger',
    }, 'none')
    if LibConfig.Wardrobe and (LibConfig.Wardrobe.provider == 'none' or LibConfig.Wardrobe.provider == false) then
        wardrobe = 'none'
    elseif wardrobe == 'none' then
        local cfg = LibConfig.Wardrobe or {}
        if type(cfg.open) == 'function' or (type(cfg.event) == 'string' and cfg.event ~= '') or type(cfg.setClothing) == 'function' then
            wardrobe = 'custom'
        end
    end

    local oxUp = GetResourceState('ox_lib') == 'started'

    local weather = detect(LibConfig.Weather and LibConfig.Weather.provider, {
        'Renewed-Weathersync', 'qbx_weathersync', 'qb-weathersync', 'cd_easytime', 'av_sync', 'av_weather',
        'wc_weathersync', 'nc_weathersync', 'ss-weathersync', 'weathersync', 'vSync',
    }, 'native')
    if LibConfig.Weather and LibConfig.Weather.provider == false then weather = 'native' end

    local dispatch = detect(LibConfig.Dispatch and LibConfig.Dispatch.provider, {
        'ps-dispatch', 'cd_dispatch', 'codem-dispatch', 'core_dispatch', 'aty_dispatch', 'rcore_dispatch',
        'tk_dispatch', 'lb-tablet', 'origen_police', 'tgiann-policealert',
    }, 'native')

    local textui = detect(LibConfig.TextUI and LibConfig.TextUI.provider, { 'okokTextUI', 'cd_drawtextui' }, oxUp and 'ox' or 'none')
    local progress = detect(LibConfig.Progress and LibConfig.Progress.provider, { 'progressbar' }, oxUp and 'ox' or 'none')
    local skillcheck = detect(LibConfig.SkillCheck and LibConfig.SkillCheck.provider, { 'ps-ui' }, oxUp and 'ox' or 'none')

    return {
        { 'framework', framework },
        { 'inventory', inventory },
        { 'society', society },
        { 'vehiclekeys', vehiclekeys },
        { 'fuel', fuel },
        { 'target', target },
        { 'medical', medical },
        { 'notify', notify },
        { 'billing', billing },
        { 'phone', phone },
        { 'doorlock', doorlock },
        { 'garage', garage },
        { 'wardrobe', wardrobe },
        { 'weather', weather },
        { 'dispatch', dispatch },
        { 'textui', textui },
        { 'progress', progress },
        { 'skillcheck', skillcheck },
    }
end

-- codem-lib starts before the scripts it bridges, and a `restart codem-lib`
-- stops the ones that depend on it until they are started again. So the table
-- waits until no resource has started for a while, prints, and prints again
-- whenever a later start changes what it says.
local printed = nil   -- name -> value of the last table shown

local function pad(name)
    return name .. string.rep(' ', 12 - #name)
end

local function settleAndPrint()
    local last, quietFor, waited = startedCount(), 0, 0
    while quietFor < 3000 do
        Wait(500)
        waited = waited + 500
        local now = startedCount()
        if now ~= last then last, quietFor = now, 0 else quietFor = quietFor + 500 end
        -- a server that keeps starting things forever still gets its table
        if waited >= 60000 then break end
    end
    local rows = summary()
    local version = GetResourceMetadata(GetCurrentResourceName(), 'version', 0) or '?'
    if not printed then
        -- the whole table once
        local out = { '^2[codem-lib]^0 v' .. version .. ' — providers:' }
        printed = {}
        for _, row in ipairs(rows) do
            out[#out + 1] = '  ' .. pad(row[1]) .. ': ^3' .. row[2] .. '^0'
            printed[row[1]] = row[2]
        end
        print(table.concat(out, '\n'))
        return
    end
    -- later only what a newly started resource changed
    local out = {}
    for _, row in ipairs(rows) do
        if printed[row[1]] ~= row[2] then
            out[#out + 1] = '  ' .. pad(row[1]) .. ': ^3' .. tostring(printed[row[1]]) .. '^0 -> ^3' .. row[2] .. '^0'
            printed[row[1]] = row[2]
        end
    end
    if #out > 0 then
        print('^2[codem-lib]^0 providers changed:\n' .. table.concat(out, '\n'))
    end
end

local settling = false

local function scheduleSummary()
    if settling then return end
    settling = true
    CreateThread(function()
        settleAndPrint()
        settling = false
    end)
end

scheduleSummary()

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then scheduleSummary() end
end)
