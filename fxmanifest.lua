fx_version 'cerulean'
game 'gta5'

author 'Codem'
description 'Codem shared bridge library'
version '1.0.0'


dependencies {
    'ox_lib',
}

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'modules/inventory/shared.lua',
}

client_scripts {
    'modules/vehiclekeys/client.lua',
    'modules/fuel/client.lua',
    'modules/notify/client.lua',
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
    'modules/society/server.lua',
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
    'modules/boot.lua',
}

files {
    'init.lua',
    'config.lua',
    'framework.lua',
    'modules/framework/**/*.lua',
    'modules/target/client.lua',
}

lua54 'yes'
