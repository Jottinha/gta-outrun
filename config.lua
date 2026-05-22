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

    -- ─── Limiares de ultrapassagem (PASS_DISTANCE dinâmico por lateral) ─────
    -- Carro à frente com lateral <= NEAR_LATERAL: precisa longitudinal > NEAR
    -- Carro à frente com lateral entre NEAR..MAX: precisa longitudinal > FAR
    -- Lateral > MAX: ignorado (carro em pista paralela / mão contrária visual)
    LEADER_PASS_DISTANCE_NEAR  = 2.0,
    LEADER_PASS_DISTANCE       = 4.0,   -- "FAR" (mantém o nome para retrocompat)
    LEADER_NEAR_LATERAL        = 3.0,
    LEADER_MAX_LATERAL_FOR_PASS = 8.0,
    -- Override "claro" (HARD): para fast-path e bypass de cooldown.
    LEADER_PASS_DISTANCE_HARD  = 10.0,
    LEADER_OVERRIDE_DISTANCE   = 15.0,  -- durante cooldown, só HARD com >=15m passa
    LEADER_MAX_Z_DIFF          = 8.0,

    -- ─── Filtros do candidato (anti carro parado / atravessado / contramão) ─
    -- Velocidade mínima do candidato para ser considerado ultrapassador.
    LEADER_MIN_SPEED_FOR_PASS  = 2.0,
    -- Alinhamento mínimo entre forward do candidato e direção da corrida do
    -- líder. dot >= 0.25 → ângulo ≤ ~75°. Filtra carro atravessado/contramão.
    LEADER_MIN_ALIGNMENT       = 0.25,

    -- ─── Histerese SOFT (separação grupo vs candidato atual) ─────────────────
    -- Grupo: enquanto HOUVER algum candidato pending por N ticks (tolerância
    -- a pelotão em que o id muda toda hora).
    LEADER_HOLD_TICKS              = 3,
    -- Atual: o candidato do tick também precisa estar pending há M ticks
    -- (evita que um candidato "novo" herde a histerese de outros).
    LEADER_MIN_CURRENT_TICKS       = 2,

    -- ─── Histerese HARD ──────────────────────────────────────────────────────
    -- HARD exige N ticks consecutivos com o MESMO candidato acima de
    -- PASS_DISTANCE_HARD. Filtra spikes instantâneos por giro de forward.
    LEADER_HARD_HOLD_TICKS         = 2,

    -- ─── Cooldown pós-troca ──────────────────────────────────────────────────
    -- Após uma troca, bloqueia novas trocas por N ticks. HARD com >= OVERRIDE
    -- (15m) é permitido mesmo em cooldown (anti-bloqueio em ultrapassagem
    -- clara que acontece logo após uma troca).
    LEADER_CHANGE_COOLDOWN_TICKS   = 12,

    -- ─── Direção da corrida (race direction) ─────────────────────────────────
    -- Quando o líder está acima dessa velocidade, usamos o vetor de VELOCIDADE
    -- como direção (em vez do forward visual). Velocidade é mais robusta a
    -- capotamento, rotação 180° e loop intencional do que forward do veículo.
    LEADER_MIN_SPEED_FOR_VELOCITY_FWD = 5.0,
    -- Abaixo dessa magnitude 2D do forward, mesmo o fallback é considerado
    -- inválido (carro vertical, capotando) e cai no cache.
    FORWARD_MIN_MAGNITUDE      = 0.2,
    -- Idade máxima do forward cacheado (ticks). 20 ticks = 1s. Expirado,
    -- voltamos a tratar como inválido (evita direção obsoleta).
    FORWARD_CACHE_MAX_AGE_TICKS = 20,

    -- ─── Win condition / IA ──────────────────────────────────────────────────
    WIN_CONFIRM_TICKS          = 4,
    EVADE_CHASERS_CONSIDERED   = 3,

    -- ─── Grid ────────────────────────────────────────────────────────────────
    GRID_ROW_SPACING           = 8.0,
    GRID_COLUMN_SPACING        = 4.5,
    GRID_STAGGER_SPACING       = 4.0,
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
    -- Histerese assimétrica: ENTRA em CHASER_CLOSE em <= DISTANCE,
    -- só SAI quando passa de EXIT_DISTANCE. Evita flapping na borda.
    CHASE_CLOSE_DISTANCE       = 10.0,
    CHASE_CLOSE_EXIT_DISTANCE  = 14.0,
    CHASE_CLOSE_AHEAD_DISTANCE = 30.0,
    CHASE_CLOSE_UPDATE_MS      = 500,
    -- Spread lateral entre chasers para evitar pile-up no mesmo carrot.
    CHASER_LATERAL_SPACING     = 2.5,
    -- Limita quantos slots de spread são usados (clamp). Em pista estreita,
    -- offsets grandes mandam o NPC para a via paralela / calçada.
    CHASER_MAX_LATERAL_STEP    = 2,
    CHASE_CLOSE_MAX_MISSES     = 3,   -- após N falhas de GetClosestVehicleNode, fallback wander
    -- Só reissua TaskVehicleDriveToCoord se o nó alvo mudou mais que isso (m).
    -- Evita destruir progresso do pathfinding a cada update.
    CHASE_CLOSE_REISSUE_DELTA  = 5.0,

    -- Anti-stuck
    STUCK_SPEED_THRESHOLD      = 2.0,
    STUCK_TIME_THRESHOLD_MS    = 3000,
    -- Stagger: cada NPC adiciona (slot * STUCK_TIME_STAGGER_MS) ms ao threshold,
    -- para que pelotão preso não entre em RECOVERY todos juntos.
    STUCK_TIME_STAGGER_MS      = 250,
    STUCK_WARMUP_MS            = 5000,
    RECOVERY_NODE_RADIUS       = 10.0,
    -- Cada NPC procura o k-ésimo nó mais próximo, com k = (slot % MAX) + 1.
    -- Garante destinos diferentes em RECOVERY simultâneo.
    RECOVERY_NODE_VARIANTS     = 4,

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
        PLAYER_ELIMINATED   = "outrun:server:PlayerEliminated",
        LEAVE_LOBBY         = "outrun:server:LeaveLobby",
        REQUEST_ROOMS_LIST  = "outrun:server:RequestRoomsList",
    },

    Client = {
        LOBBY_CREATED      = "outrun:client:LobbyCreated",
        LOBBY_UPDATED      = "outrun:client:LobbyUpdated",
        NO_ACTIVE_LOBBY    = "outrun:client:NoActiveLobby",
        FORCE_LOBBY_CLOSE  = "outrun:client:ForceLobbyClose",
        NOTIFY             = "outrun:client:Notify",
        SPAWN_VEHICLES     = "outrun:client:SpawnVehicles",
        BE_SPECTATOR       = "outrun:client:BeSpectator",
        ROOMS_LIST         = "outrun:client:RoomsList",
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
