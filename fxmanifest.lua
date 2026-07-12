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
    'modules/**'
}

server_scripts {
    'modules/**'
}

files {
    'init.lua',
    'config.lua',
    'modules/framework/**/*.lua',
    'modules/target/client.lua',
}

lua54 'yes'
