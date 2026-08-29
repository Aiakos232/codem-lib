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

CreateThread(function()
    -- Let the rest of the server finish starting so auto-detection is accurate.
    Wait(2000)

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
        'illenium-appearance', 'fivem-appearance', 'qb-clothing',
        'rcore_clothing', 'esx_skin', 'skinchanger',
    }, 'none')
    if LibConfig.Wardrobe and (LibConfig.Wardrobe.provider == 'none' or LibConfig.Wardrobe.provider == false) then
        wardrobe = 'none'
    elseif wardrobe == 'none' then
        local cfg = LibConfig.Wardrobe or {}
        if type(cfg.open) == 'function' or (type(cfg.event) == 'string' and cfg.event ~= '') then
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

    print(table.concat({
        '^2[codem-lib]^0 v' .. (GetResourceMetadata(GetCurrentResourceName(), 'version', 0) or '?') .. ' — providers:',
        '  framework   : ^3' .. framework .. '^0',
        '  inventory   : ^3' .. inventory .. '^0',
        '  society     : ^3' .. society .. '^0',
        '  vehiclekeys : ^3' .. vehiclekeys .. '^0',
        '  fuel        : ^3' .. fuel .. '^0',
        '  target      : ^3' .. target .. '^0',
        '  medical     : ^3' .. medical .. '^0',
        '  notify      : ^3' .. notify .. '^0',
        '  billing     : ^3' .. billing .. '^0',
        '  phone       : ^3' .. phone .. '^0',
        '  doorlock    : ^3' .. doorlock .. '^0',
        '  garage      : ^3' .. garage .. '^0',
        '  wardrobe    : ^3' .. wardrobe .. '^0',
        '  weather     : ^3' .. weather .. '^0',
        '  dispatch    : ^3' .. dispatch .. '^0',
        '  textui      : ^3' .. textui .. '^0',
        '  progress    : ^3' .. progress .. '^0',
        '  skillcheck  : ^3' .. skillcheck .. '^0',
    }, '\n'))
end)
