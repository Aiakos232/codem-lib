-- ════════════════════════════════════════════════════════════════════════════
-- CODEM-LIB — provider selection in one place. Every codem script reads these
-- settings; there is no per-script banking/keys config.
-- 'auto' = the first running resource is detected automatically.
-- ════════════════════════════════════════════════════════════════════════════

LibConfig = {}

LibConfig.Debug = false

-- Framework. 'auto' detects the running core resource.
-- Supported: 'qbox' | 'qb' | 'esx' | 'auto'
LibConfig.Framework = 'auto'

-- Society / job fund (banking) provider.
-- Supported: 'qb-banking' | 'qb-management' | 'Renewed-Banking' | 'okokBanking'
-- | 'fd_banking' | 'tgg-banking' | 'tgiann-bank' | 'qs-banking' | 'wasabi_banking'
-- | 'snipe-banking' | 'crm-banking' | 'kartik-banking' | 'p_banking' | 'nfs-banking'
-- | 'nfs-billing' | 'RxBanking' | 'sd-multijob' | 'vms_bossmenu' | 'nass_bossmenu'
-- | 'xnr-bossmenu' | 'esx_addonaccount' | 'auto'
LibConfig.Society = {
    enabled  = true,
    provider = 'auto',
}

-- Ambulance / medical provider (reviving a downed player).
-- Supported: 'wasabi_ambulance_v2' | 'wasabi_ambulance' | 'qs-medical-creator'
-- | 'ars_ambulancejob' | 'tk_ambulancejob' | 'qbx_medical' | 'qb-ambulancejob'
-- | 'esx_ambulancejob' | 'auto'
LibConfig.Medical = {
    enabled  = true,
    provider = 'auto',
}

-- Billing provider (player invoices).
-- Supported: 'codem-phone' | 'codem-billingv2' | 'auto' | false (disabled)
--   maxDistance : how close the sender must be to the billed player, in metres.
--                 0 = no distance check.
LibConfig.Billing = {
    enabled     = true,
    provider    = 'auto',
    maxDistance = 0,
}

-- Phone number provider (reading / changing a character's number).
-- Supported: 'codem-phone' | 'lb-phone' | 'qs-smartphone' | 'qs-smartphone-pro'
-- | 'cylex_phone' | '17mov_Phone' | 'framework' (charinfo.phone / users.phone_number only) | 'auto'
--   minDigits / maxDigits : accepted digit count (spaces, dashes and parentheses are kept as typed)
--   generateDigits        : length used when the provider cannot generate one itself
--   codemTable / codemNumberColumn / codemIdentifierColumn :
--                           where codem-phone keeps the number; used only for changes,
--                           reads go through its exports.
LibConfig.Phone = {
    provider       = 'auto',
    minDigits      = 3,
    maxDigits      = 15,
    generateDigits = 7,

    codemTable            = 'codem_mphone_data',
    codemNumberColumn     = 'phone_number',
    codemIdentifierColumn = 'identifier',
}


-- Weather / time sync provider.
-- Supported: 'Renewed-Weathersync' | 'qbx_weathersync' | 'qb-weathersync'
-- | 'cd_easytime' | 'av_sync' | 'av_weather' | 'wc_weathersync'
-- | 'nc_weathersync' | 'ss-weathersync' | 'weathersync' | 'vSync' | 'auto'
-- | false (no provider: codem-lib applies weather/time/blackout/freeze itself)
LibConfig.Weather = {
    provider = 'auto',
}

-- Inventory provider.
-- Supported: 'ox_inventory' | 'qb-inventory' | 'ps-inventory' | 'qs-inventory'
-- | 'codem-inventory' | 'core_inventory' | 'tgiann-inventory' | 'origen_inventory'
-- | 'ak47_inventory' | 'jaksam_inventory' | 'jpr-inventory' | 'S-inventory' | 'auto'
LibConfig.Inventory = {
    provider = 'auto',
}

-- Text UI provider (persistent on-screen prompts).
-- Supported: 'okokTextUI' | 'cd_drawtextui' | 'ox' | 'auto'
LibConfig.TextUI = {
    provider = 'auto',
}

-- Progress bar provider (blocking timed actions).
-- Supported: 'progressbar' (qb) | 'ox' | 'auto'
LibConfig.Progress = {
    provider = 'auto',
}

-- Skill check / minigame provider.
-- Supported: 'ps-ui' | 'ox' | 'auto'
LibConfig.SkillCheck = {
    provider = 'auto',
}

-- Notification provider.
-- Supported: 'codem-notification' | 'okokNotify' | 'brutal_notify'
-- | 'g-notifications' | 'is_ui' | 'lation_ui' | 'vms_notifyv2' | 'wasabi_uikit'
-- | 'mythic_notify' | '17mov_Hud' | 'gs-notify' | 'ox' | 'framework' | 'auto'
LibConfig.Notify = {
    provider = 'auto',
}

-- Target provider (third-eye interaction).
-- Supported: 'ox_target' | 'qb-target' | 'auto'
LibConfig.Target = {
    provider = 'auto',
}

-- Vehicle fuel provider.
-- Supported: 'ox_fuel' | 'LegacyFuel' | 'cdn-fuel' | 'qb-fuel' | 'lc_fuel'
-- | 'Renewed-Fuel' | 'myFuel' | 'okokGasStation' | 'qs-fuelstations'
-- | 'rcore_fuel' | 'x-fuel' | 'auto'
LibConfig.Fuel = {
    provider = 'auto',
}

-- Vehicle key provider.
-- Supported: 'qbx_vehiclekeys' | 'qb-vehiclekeys' | 'wasabi_carlock'
-- | 'Renewed-Vehiclekeys' | 'MrNewbVehicleKeys' | 'vehicles_keys'
-- | 'tgiann-hotwire' | 'mVehicle' | 'okokGarage' | 'cd_garage' | 'ND_Core'
-- | '0r-vehiclekeys' | 'LifeSaver_KeySystem' | 'ak47_qb_vehiclekeys'
-- | 'ak47_vehiclekeys' | 'brutal_carkeys' | 'filo_vehiclekey'
-- | 'ic3d_vehiclekeys' | 'is_vehiclekeys' | 'mk_vehiclekeys' | 'mm_carkeys'
-- | 'p_carkeys' | 'qs-vehiclekeys' | 'rd_vehiclekeys' | 'auto'
LibConfig.VehicleKeys = {
    provider = 'auto',
    -- When tgiann-hotwire is installed, a key is also put in the ignition on
    -- top of the main provider (the ignition system is a separate layer).
    hotwireIgnition = true,
}

-- Admin permission groups for Framework.Server.IsAdmin checks.
-- qb/qbox: QBCore/qbx permission groups. ESX: player group names.
-- Players holding the 'command' ace (txAdmin / server console) always pass,
-- regardless of this list.
LibConfig.AdminPermissions = {
    ['god']        = true,
    ['admin']      = true,
    ['superadmin'] = true, -- ESX only; harmless on qb/qbox
}

LibConfig.Doorlock = {
    provider = 'auto',
}

LibConfig.Garage = {
    provider = 'auto',
}

LibConfig.Wardrobe = {
    provider = 'auto',
}
