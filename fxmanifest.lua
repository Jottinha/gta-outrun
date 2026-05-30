fx_version 'cerulean'
game 'gta5'

author 'OUTRUN Dev'
description 'OUTRUN - Arcade racing Gato e Rato com IA e campeonato integrado ao QBCore'
version '1.1.0'

dependency 'qb-core'

shared_scripts {
    'config.lua',
    'shared/logger.lua',
    'shared/overtake_core.lua',
}

server_scripts {
    'server/rooms.lua',
    'server/race_server.lua',
    'server/round_manager.lua',
    'server/disconnect.lua',
    'server/main.lua',
    'server/amphibious.lua', -- feature isolada: swap netId carro<->jetski
}

client_scripts {
    'client/race_state.lua',
    'client/nui_bridge.lua',
    'client/grid.lua',
    'client/race_logic.lua',
    'client/spawn.lua',
    'client/ai/ai_strategy.lua',
    'client/ai/ai_controller.lua',
    'client/spectator.lua',
    'client/leader_blip.lua',
    'client/chaser_blips.lua',
    'client/blip_sync.lua',
    'client/debug_overtake.lua',
    'client/vehicle_preview.lua',
    'client/race_orchestrator.lua',
    'client/main.lua',
    'client/amphibious.lua', -- feature isolada: swap carro<->jetski na água (MP)
    'client/dev_spawnpoint.lua', -- TEMP: captura de pontos de largada (remover depois)
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}
