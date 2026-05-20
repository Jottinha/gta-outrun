-- ============================================================
--  OUTRUN — Configuração Central
--  Carregado em: client + server (shared_script)
-- ============================================================

Config = {}


-- ============================================================
-- SEÇÃO 1: Config.Race — Regras de Corrida
-- ============================================================

Config.Race = {
    WIN_DISTANCE             = 500.0,
    ELIMINATION_DISTANCE     = 500.0,
    COUNTDOWN_SECONDS        = 5,
    POINT_TARGETS            = { 50, 100, 200 },
    DISTANCE_UPDATE_INTERVAL = 50,
    LEADER_PASS_DISTANCE     = 4.0,
    LEADER_MAX_Z_DIFF        = 8.0,
    GRID_ROW_SPACING         = 8.0,
    GRID_COLUMN_SPACING      = 4.5,
    GRID_STAGGER_SPACING     = 4.0,
}


-- ============================================================
-- SEÇÃO 2: Config.Scoring — Pontuação por Posição
-- ============================================================

Config.Scoring = {
    [1] = 10,
    [2] = 8,
    [3] = 6,
    [4] = 4,
    [5] = 2,
}


-- ============================================================
-- SEÇÃO 3: Config.BonusRound — Rodada Bônus (Polícia)
-- ============================================================

Config.BonusRound = {
    TRIGGER_PROBABILITY  = 0.15,
    WANTED_LEVEL         = 4,
    POLICE_IGNORE_OTHERS = true,
}


-- ============================================================
-- SEÇÃO 4: Config.AI — Controle de NPCs
-- ============================================================

Config.AI = {
    EVADE_DRIVING_STYLE           = 2883621,
    CHASE_DRIVING_STYLE           = 1074528293,
    RECOVERY_DRIVING_STYLE        = 786468,
    EVADE_SPEED                   = 80.0,
    RECOVERY_SPEED                = 12.0,
    EVADE_FORWARD_DISTANCE        = 1500.0,
    EVADE_PRESSURE_DISTANCE       = 120.0,
    EVADE_ROLE_BUCKET_SIZE        = 75.0,
    CHASE_CLOSE_DISTANCE       = 10.0,
    CHASE_CLOSE_AHEAD_DISTANCE = 30.0,
    CHASE_CLOSE_UPDATE_MS      = 500,
    STUCK_SPEED_THRESHOLD               = 2.0,
    STUCK_TIME_THRESHOLD_MS       = 3000,
    STUCK_WARMUP_MS               = 5000,
    RECOVERY_NODE_RADIUS          = 10.0,
    DRIVE_UPDATE_INTERVAL         = 250,
}


-- ============================================================
-- SEÇÃO 5: Config.HUD — Interface Visual
-- ============================================================

Config.HUD = {
    DANGER_THRESHOLD_PERCENT = 0.8,
    TRANSITION_SOUND         = "Swoosh",
    BAR_COLOR_LEADER         = { r = 0,   g = 255, b = 0,   a = 255 },
    BAR_COLOR_CHASER         = { r = 255, g = 0,   b = 0,   a = 255 },
    UPDATE_INTERVAL          = 50,
}


-- ============================================================
-- SEÇÃO 6: Config.States — Máquinas de Estado
-- ============================================================

Config.States = {
    Room = {
        LOBBY              = "LOBBY",
        SPAWN_GRID         = "SPAWN_GRID",
        COUNTDOWN          = "COUNTDOWN",
        RACING             = "RACING",
        ROUND_RESULT       = "ROUND_RESULT",
        CHECK_CHAMPIONSHIP = "CHECK_CHAMPIONSHIP",
        END_SCREEN         = "END_SCREEN",
    },
    AI = {
        GRID         = "GRID",
        CHASE        = "CHASE",
        CHASER_CLOSE = "CHASER_CLOSE",
        EVADE        = "EVADE",
        RECOVERY     = "RECOVERY",
        ELIMINATED   = "ELIMINATED",
    },
}


-- ============================================================
-- SEÇÃO 7: Config.Events — Nomes dos Eventos de Rede
-- ============================================================

Config.Events = {
    Server = {
        CREATE_LOBBY        = "outrun:server:CreateLobby",
        JOIN_LOBBY          = "outrun:server:JoinLobby",
        TOGGLE_READY        = "outrun:server:ToggleReady",
        START_RACE          = "outrun:server:StartRace",
        UPDATE_LEADER       = "outrun:server:UpdateLeader",
        ROUND_END           = "outrun:server:RoundEnd",
        RACE_STARTED        = "outrun:server:RaceStarted",
        REQUEST_LOBBY_STATE = "outrun:server:RequestLobbyState",
    },

    Client = {
        SPAWN_VEHICLES    = "outrun:client:SpawnVehicles",
        PLAYER_ELIMINATED = "outrun:client:PlayerEliminated",
        NO_ACTIVE_LOBBY   = "outrun:client:NoActiveLobby",
    },
}


-- ============================================================
-- SEÇÃO 8: Config.SpawnNodes — Pontos de spawn dinâmico
-- ============================================================

Config.SpawnNodes = {
    vector3(  -1729.55,  -2884.01,  13.94),
}


-- ============================================================
-- SEÇÃO 9: Config.Debug — Desenvolvimento
-- ============================================================

Config.Debug = {
    ENABLED    = true,
    LOG_PREFIX = "[OUTRUN]",
}
