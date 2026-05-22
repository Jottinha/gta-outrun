-- ============================================================
--  OUTRUN — Client/AI: Strategy Pattern
--
--  Cada NPC tem uma Strategy. O AIController só conhece a
--  interface; comportamento concreto (driving style, velocidades,
--  thresholds) vive aqui. Para adicionar uma nova personalidade,
--  veja docs/AI_SYSTEM.md §5.
-- ============================================================

AIStrategy = {}


-- ===== Base: defaults globais (fallback) =====
-- Outras strategies estendem este perfil via makeFrom.

AIStrategy.Base = {
    name                   = "Base",

    -- Driving styles (bitmask) por modo
    chaseDrivingStyle      = Config.AI.CHASE_DRIVING_STYLE,
    chaseCloseDrivingStyle = Config.AI.CHASE_DRIVING_STYLE,
    evadeDrivingStyle      = Config.AI.EVADE_DRIVING_STYLE,
    recoveryDrivingStyle   = Config.AI.RECOVERY_DRIVING_STYLE,

    -- Velocidades-alvo (m/s)
    evadeSpeed             = Config.AI.EVADE_SPEED,
    recoverySpeed          = Config.AI.RECOVERY_SPEED,
    overtakeSpeed          = Config.AI.EVADE_SPEED,

    -- Limiares de transição (histerese assimétrica entre CHASE e CHASER_CLOSE)
    chaseCloseThreshold    = Config.AI.CHASE_CLOSE_DISTANCE,        -- entra CHASER_CLOSE em <= threshold
    chaseCloseExit         = Config.AI.CHASE_CLOSE_EXIT_DISTANCE,   -- só sai de CHASER_CLOSE em >  exit
    chaseCloseAhead        = Config.AI.CHASE_CLOSE_AHEAD_DISTANCE,
    chaseCloseUpdateMs     = Config.AI.CHASE_CLOSE_UPDATE_MS,
    evadeForwardDistance   = Config.AI.EVADE_FORWARD_DISTANCE,
    evadePressureDistance  = Config.AI.EVADE_PRESSURE_DISTANCE,

    -- Rubber-banding (ainda não aplicado — ver docs/AI_SYSTEM.md §7)
    rubberBand = {
        leaderSlowFactor  = 0.8,
        chaserBoostFactor = 1.5,
        leaderThreshold   = 300.0,
        chaserThreshold   = 250.0,
    },
}


-- ===== Helper: criar uma Strategy a partir de outra (composition) =====

function AIStrategy.makeFrom(parent, overrides)
    local result = {}
    for k, v in pairs(parent) do
        if type(v) == "table" then
            result[k] = {}
            for kk, vv in pairs(v) do result[k][kk] = vv end
        else
            result[k] = v
        end
    end
    if overrides then
        for k, v in pairs(overrides) do
            if type(v) == "table" and type(result[k]) == "table" then
                for kk, vv in pairs(v) do result[k][kk] = vv end
            else
                result[k] = v
            end
        end
    end
    return result
end


-- ===== Personalities padrão =====

AIStrategy.Balanced = AIStrategy.makeFrom(AIStrategy.Base, {
    name = "Balanced",
})

AIStrategy.Aggressive = AIStrategy.makeFrom(AIStrategy.Base, {
    name                = "Aggressive",
    evadeSpeed          = 90.0,
    overtakeSpeed       = 90.0,
    chaseCloseThreshold = 15.0,
    chaseCloseExit      = 20.0,
    chaseCloseAhead     = 36.0,
    rubberBand = {
        leaderSlowFactor  = 0.85,
        chaserBoostFactor = 1.65,
        leaderThreshold   = 280.0,
        chaserThreshold   = 230.0,
    },
})

AIStrategy.Precise = AIStrategy.makeFrom(AIStrategy.Base, {
    name                = "Precise",
    evadeSpeed          = 72.0,
    overtakeSpeed       = 75.0,
    recoverySpeed       = 10.0,
    chaseCloseThreshold = 8.0,
    chaseCloseExit      = 12.0,
    chaseCloseAhead     = 24.0,
    rubberBand = {
        leaderSlowFactor  = 0.85,
        chaserBoostFactor = 1.35,
        leaderThreshold   = 320.0,
        chaserThreshold   = 280.0,
    },
})


-- ===== Factory =====

local STRATEGY_BY_NAME = {
    balanced   = AIStrategy.Balanced,
    aggressive = AIStrategy.Aggressive,
    precise    = AIStrategy.Precise,
}

function AIStrategy.create(name)
    local strategy = STRATEGY_BY_NAME[name or "balanced"]
    if not strategy then
        Logger.warn("AI", ("Personality desconhecida '%s' → fallback balanced"):format(tostring(name)))
        return AIStrategy.Balanced
    end
    return strategy
end
