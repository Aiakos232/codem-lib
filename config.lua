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
