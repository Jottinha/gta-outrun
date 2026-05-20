-- ============================================================
--  OUTRUN — Configuração central
--  Carregado em client + server (shared_script)
--  Convenções:
--   * Tempos em milissegundos
--   * Distâncias em metros
--   * Velocidades em m/s (nativas do FiveM)
-- ============================================================

Config = {}


-- ============================================================
-- 1) Config.Debug
-- ============================================================

Config.Debug = {
    ENABLED    = true,
    LOG_PREFIX = "[OUTRUN]",
}


-- ============================================================
-- 2) Config.Race — Regras gerais da corrida
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
-- 3) Config.Scoring — Pontuação por posição final
-- ============================================================

Config.Scoring = {
    [1] = 10,
    [2] = 8,
    [3] = 6,
    [4] = 4,
    [5] = 2,
}

Config.DefaultPointTarget = 100


-- ============================================================
-- 4) Config.BonusRound — Rodada Bônus (Polícia)
-- ============================================================

Config.BonusRound = {
    TRIGGER_PROBABILITY  = 0.15,
    WANTED_LEVEL         = 4,
    POLICE_IGNORE_OTHERS = true,
}


-- ============================================================
-- 5) Config.AI — Limiares globais (cada Strategy pode override)
-- ============================================================

Config.AI = {
    -- Driving styles (fallback se Strategy não definir)
    EVADE_DRIVING_STYLE        = 2883621,
    CHASE_DRIVING_STYLE        = 1074528293,
    RECOVERY_DRIVING_STYLE     = 786468,

    -- Velocidades fallback
    EVADE_SPEED                = 80.0,
    RECOVERY_SPEED             = 12.0,

    -- Alvo de fuga
    EVADE_FORWARD_DISTANCE     = 1500.0,
    EVADE_PRESSURE_DISTANCE    = 120.0,
    EVADE_ROLE_BUCKET_SIZE     = 75.0,

    -- Ultrapassagem (CHASE → CHASER_CLOSE)
    CHASE_CLOSE_DISTANCE       = 10.0,
    CHASE_CLOSE_AHEAD_DISTANCE = 30.0,
    CHASE_CLOSE_UPDATE_MS      = 500,

    -- Anti-stuck
    STUCK_SPEED_THRESHOLD      = 2.0,
    STUCK_TIME_THRESHOLD_MS    = 3000,
    STUCK_WARMUP_MS            = 5000,
    RECOVERY_NODE_RADIUS       = 10.0,

    -- Loop principal da IA
    DRIVE_UPDATE_INTERVAL      = 250,
}


-- ============================================================
-- 6) Config.HUD — Interface
-- ============================================================

Config.HUD = {
    DANGER_THRESHOLD_PERCENT = 0.8,
    TRANSITION_SOUND         = "Swoosh",
    BAR_COLOR_LEADER         = { r = 0,   g = 255, b = 0,   a = 255 },
    BAR_COLOR_CHASER         = { r = 255, g = 0,   b = 0,   a = 255 },
    UPDATE_INTERVAL          = 50,
}


-- ============================================================
-- 7) Config.States — Máquinas de estado
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
-- 8) Config.Events — Nomes de eventos de rede
--    Toda comunicação client↔server passa por aqui.
-- ============================================================

Config.Events = {
    Server = {
        CREATE_LOBBY        = "outrun:server:CreateLobby",
        REQUEST_LOBBY_STATE = "outrun:server:RequestLobbyState",
        ADD_NPC             = "outrun:server:AddNPC",
        SET_CAR             = "outrun:server:SetCar",
        TOGGLE_READY        = "outrun:server:ToggleReady",
        START_RACE          = "outrun:server:StartRace",
        UPDATE_LEADER       = "outrun:server:UpdateLeader",
        ROUND_END           = "outrun:server:RoundEnd",
        RACE_STARTED        = "outrun:server:RaceStarted",
    },

    Client = {
        LOBBY_CREATED      = "outrun:client:LobbyCreated",
        LOBBY_UPDATED      = "outrun:client:LobbyUpdated",
        NO_ACTIVE_LOBBY    = "outrun:client:NoActiveLobby",
        FORCE_LOBBY_CLOSE  = "outrun:client:ForceLobbyClose",
        NOTIFY             = "outrun:client:Notify",
        SPAWN_VEHICLES     = "outrun:client:SpawnVehicles",
        PLAYER_ELIMINATED  = "outrun:client:PlayerEliminated",
        BE_SPECTATOR       = "outrun:client:BeSpectator",
        LEADER_CHANGED     = "outrun:client:LeaderChanged",
        CLEAR_WANTED       = "outrun:client:ClearWanted",
        ROUND_RESULT       = "outrun:client:RoundResult",
        SHOW_END_SCREEN    = "outrun:client:ShowEndScreen",
    },
}


-- ============================================================
-- 9) Config.Vehicles — Modelos selecionáveis no lobby
-- ============================================================

Config.Vehicles = {
    DEFAULT = "sultan",
    SELECTABLE = {
        "sultan", "elegy2", "adder", "t20", "zentorno",
        "kuruma", "comet2", "banshee",
    },
}


-- ============================================================
-- 10) Config.PedModels — Modelos de peds usados como motoristas NPC
-- ============================================================

Config.PedModels = {
    "a_m_y_musclbeac_01",
    "a_m_m_business_01",
    "a_m_y_skater_01",
    "a_m_y_hipster_01",
    "a_m_y_genstreet_01",
    "a_m_y_eastsa_01",
}


-- ============================================================
-- 11) Config.SpawnNodes — Pontos curados para largada
-- ============================================================

Config.SpawnNodes = {
    vector3(-1729.55, -2884.01, 13.94),
}
