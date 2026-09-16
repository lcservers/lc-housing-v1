fx_version 'cerulean'
game 'gta5'

author 'LC'
description 'LC Housing - standalone property, interior, door, and furniture management for QBCore and QBox'
version '1.4.3'
license 'GPL-3.0-only'

ui_page 'html/index.html'

shared_scripts {
    'config.lua'
}

client_scripts {
    'client/main.lua',
    'client/furniture.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/furniture.lua'
}

files {
    'furniture.lua',
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/furniture.js'
}

dependency 'oxmysql'
