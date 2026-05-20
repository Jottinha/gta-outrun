fx_version 'cerulean'
game 'gta5'

author 'OUTRUN Dev'
description 'OUTRUN - Arcade racing Gato e Rato com IA e campeonato integrado ao QBCore'
version '1.0.0'

dependency 'qb-core'

shared_scripts {
    'config.lua'
}

client_scripts {
    'client/main.lua',
    'client/ai_controller.lua',
    'client/race_logic.lua',
    'client/spectator.lua'
}

server_scripts {
    'server/main.lua',
    'server/events.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js'
}
