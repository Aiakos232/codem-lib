fx_version 'cerulean'
game 'gta5'

author 'Codem'
description 'Codem shared bridge library'
version '1.0.0'


-- ox_lib is OPTIONAL. When present, its interface is used via exports
-- (see modules/lib_compat.lua); when absent, each module falls back to a
-- dedicated provider or the framework native.

shared_scripts {
    'config.lua',
    'modules/lib_compat.lua',
    'modules/inventory/shared.lua',
    'modules/doorlock/shared.lua',
    'modules/garage/shared.lua',
    'modules/wardrobe/shared.lua',
}

client_scripts {
    'modules/vehiclekeys/client.lua',
    'modules/fuel/client.lua',
    'modules/notify/client.lua',
    'modules/textui/client.lua',
    'modules/progress/client.lua',
    'modules/skillcheck/client.lua',
    'modules/doorlock/client.lua',
    'modules/wardrobe/client.lua',
    'modules/inventory/ox_inventory/client.lua',
    'modules/inventory/qb-inventory/client.lua',
    'modules/inventory/ps-inventory/client.lua',
    'modules/inventory/qs-inventory/client.lua',
    'modules/inventory/codem-inventory/client.lua',
    'modules/inventory/core_inventory/client.lua',
    'modules/inventory/tgiann-inventory/client.lua',
    'modules/inventory/origen_inventory/client.lua',
    'modules/inventory/ak47_inventory/client.lua',
    'modules/inventory/jaksam_inventory/client.lua',
    'modules/inventory/jpr-inventory/client.lua',
    'modules/inventory/S-inventory/client.lua',
    'modules/inventory/exports_client.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'framework.lua',
    'modules/society/server.lua',
    'modules/medical/server.lua',
    'modules/billing/server.lua',
    'modules/vehiclekeys/server.lua',
    'modules/fuel/server.lua',
    'modules/notify/server.lua',
    'modules/inventory/ox_inventory/server.lua',
    'modules/inventory/qb-inventory/server.lua',
    'modules/inventory/ps-inventory/server.lua',
    'modules/inventory/qs-inventory/server.lua',
    'modules/inventory/codem-inventory/server.lua',
    'modules/inventory/core_inventory/server.lua',
    'modules/inventory/tgiann-inventory/server.lua',
    'modules/inventory/origen_inventory/server.lua',
    'modules/inventory/ak47_inventory/server.lua',
    'modules/inventory/jaksam_inventory/server.lua',
    'modules/inventory/jpr-inventory/server.lua',
    'modules/inventory/S-inventory/server.lua',
    'modules/inventory/exports_server.lua',
    'modules/garage/server.lua',
    -- Owned vehicle tables (player_vehicles / owned_vehicles), normalised.
    'modules/vehicles/server.lua',
    'modules/boot.lua',
}

files {
    'init.lua',
    'config.lua',
    'framework.lua',
    'modules/framework/**/*.lua',
    'modules/target/client.lua',
    'modules/garage/client.lua',
}

lua54 'yes'
