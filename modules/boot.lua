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

    local notify = detect(LibConfig.Notify and LibConfig.Notify.provider, {
        'codem-notification', 'okokNotify', 'brutal_notify', 'g-notifications',
        'is_ui', 'lation_ui', 'vms_notifyv2', 'wasabi_uikit',
        'mythic_notify', '17mov_Hud', 'gs-notify',
    }, 'ox')

    print(table.concat({
        '^2[codem-lib]^0 v' .. (GetResourceMetadata(GetCurrentResourceName(), 'version', 0) or '?') .. ' — providers:',
        '  framework   : ^3' .. framework .. '^0',
        '  inventory   : ^3' .. inventory .. '^0',
        '  society     : ^3' .. society .. '^0',
        '  vehiclekeys : ^3' .. vehiclekeys .. '^0',
        '  fuel        : ^3' .. fuel .. '^0',
        '  target      : ^3' .. target .. '^0',
        '  notify      : ^3' .. notify .. '^0',
    }, '\n'))
end)
