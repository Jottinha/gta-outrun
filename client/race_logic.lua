-- ============================================================
--  OUTRUN — Client: RaceLogic (adapter sobre OvertakeCore)
--
--  Camada fina entre FiveM e o módulo puro `shared/overtake_core.lua`.
--  Aqui:
--    * Coletamos coords/forward das entidades reais
--    * Montamos snapshots no formato esperado pelo core
--    * Despachamos para o tick do core e devolvemos o resultado
--
--  O core não conhece nada de FiveM, o que permite reaproveitar a mesma
--  lógica num adapter server-side (ver MULTIPLAYER_PLAN §3.1).
-- ============================================================

RaceLogic = {}

local overtakeState = nil
local loopGeneration = 0


-- ------------------------------------------------------------
-- Config: snapshot do que o core precisa, montado uma vez por tick
-- ------------------------------------------------------------

local function makeCfg()
    return {
        -- Limiares de ultrapassagem (PASS dinâmico)
        PASS_DISTANCE_NEAR           = Config.Race.LEADER_PASS_DISTANCE_NEAR,
        PASS_DISTANCE                = Config.Race.LEADER_PASS_DISTANCE,
        NEAR_LATERAL                 = Config.Race.LEADER_NEAR_LATERAL,
        MAX_LATERAL_FOR_PASS         = Config.Race.LEADER_MAX_LATERAL_FOR_PASS,
        PASS_DISTANCE_HARD           = Config.Race.LEADER_PASS_DISTANCE_HARD,
        OVERRIDE_DISTANCE            = Config.Race.LEADER_OVERRIDE_DISTANCE,
        MAX_Z_DIFF                   = Config.Race.LEADER_MAX_Z_DIFF,
        PASS_MAX_DISTANCE            = Config.Race.LEADER_PASS_MAX_DISTANCE,
        -- Filtros do candidato
        MIN_SPEED_FOR_PASS           = Config.Race.LEADER_MIN_SPEED_FOR_PASS,
        MIN_ALIGNMENT                = Config.Race.LEADER_MIN_ALIGNMENT,
        -- Histerese SOFT/HARD
        LEADER_HOLD_TICKS            = Config.Race.LEADER_HOLD_TICKS,
        LEADER_MIN_CURRENT_TICKS     = Config.Race.LEADER_MIN_CURRENT_TICKS,
        LEADER_HARD_HOLD_TICKS       = Config.Race.LEADER_HARD_HOLD_TICKS,
        LEADER_CHANGE_COOLDOWN_TICKS = Config.Race.LEADER_CHANGE_COOLDOWN_TICKS,
        -- Win / direção / cache
        WIN_DISTANCE                 = Config.Race.WIN_DISTANCE,
        ELIMINATION_DISTANCE         = Config.Race.ELIMINATION_DISTANCE,
        WIN_CONFIRM_TICKS            = Config.Race.WIN_CONFIRM_TICKS,
        MIN_SPEED_FOR_VELOCITY_FWD   = Config.Race.LEADER_MIN_SPEED_FOR_VELOCITY_FWD,
        FORWARD_MIN_MAGNITUDE        = Config.Race.FORWARD_MIN_MAGNITUDE,
        FORWARD_CACHE_MAX_AGE_TICKS  = Config.Race.FORWARD_CACHE_MAX_AGE_TICKS,
    }
end


-- ------------------------------------------------------------
-- Coleta de snapshots: traduz `RaceState.participants` → entries puras
-- ------------------------------------------------------------

local function collectSnapshots(participants)
    local snapshots = {}
    for _, p in ipairs(participants) do
        local valid = p.vehicle and DoesEntityExist(p.vehicle)
        if valid then
            local pos = GetEntityCoords(p.vehicle)
            local fwd = GetEntityForwardVector(p.vehicle)
            local vel = GetEntityVelocity(p.vehicle)
            local speed2d = math.sqrt(vel.x * vel.x + vel.y * vel.y)
            snapshots[#snapshots + 1] = {
                id         = p.id,
                isNPC      = p.isNPC,
                vehicle    = p.vehicle,
                valid      = true,
                eliminated = p.eliminated == true,
                x = pos.x, y = pos.y, z = pos.z,
                fx = fwd.x, fy = fwd.y,
                vx = vel.x, vy = vel.y,
                speed = speed2d,
            }
        else
            snapshots[#snapshots + 1] = {
                id         = p.id,
                isNPC      = p.isNPC,
                vehicle    = p.vehicle,
                valid      = false,
                eliminated = p.eliminated == true,
            }
        end
    end
    return snapshots
end


-- ------------------------------------------------------------
-- Helpers públicos
-- ------------------------------------------------------------

function RaceLogic.Dist2D(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

function RaceLogic.resetState()
    overtakeState = OvertakeCore.newState()
end

-- Exposto para o módulo de debug visual consumir EXATAMENTE a mesma cfg que
-- o tick consome — assim qualquer alteração em Config.Race.LEADER_* reflete
-- nos desenhos sem duplicação de constantes (single source of truth).
function RaceLogic.getCfg()
    return makeCfg()
end

-- Host: corre o algoritmo completo (histerese, eliminação, vitória).
function RaceLogic.tick(participants)
    if not overtakeState then RaceLogic.resetState() end
    return OvertakeCore.tick(overtakeState, collectSnapshots(participants), makeCfg())
end

-- Não-host: só constrói standings em torno de um líder já decidido.
--
-- ATENÇÃO (multiplayer): hoje o servidor só envia SPAWN_VEHICLES ao host
-- (round_manager.lua:52), então não-host fica com participants={} e este
-- branch produz standings vazias na prática. É o placeholder do
-- MULTIPLAYER_PLAN §3.1 — quando a sincronização de participants chegar
-- ao non-host, o branch passa a funcionar sem mais mudanças.
function RaceLogic.buildView(participants, leaderId)
    return OvertakeCore.buildView(collectSnapshots(participants), leaderId, makeCfg())
end


-- ------------------------------------------------------------
-- Loop principal — host roda tick(), demais buildView()
-- Geração token: nova `StartLoop` invalida a thread anterior.
-- ------------------------------------------------------------

function RaceLogic.StartLoop(getParticipants, getLeaderId, callback)
    loopGeneration = loopGeneration + 1
    local myGen = loopGeneration
    RaceLogic.resetState()

    Citizen.CreateThread(function()
        while RaceState.isActive() and loopGeneration == myGen do
            local participants = getParticipants()
            local result
            if RaceState.isHost then
                result = RaceLogic.tick(participants)
            else
                result = RaceLogic.buildView(participants, getLeaderId())
            end
            if result and result.leaderId then
                callback(result)
            end
            Citizen.Wait(Config.Race.DISTANCE_UPDATE_INTERVAL)
        end
    end)
end

function RaceLogic.StopLoop()
    loopGeneration = loopGeneration + 1
end


-- ------------------------------------------------------------
-- Loop de snapshots para modo multiplayer.
-- Não calcula liderança localmente — apenas envia posição ao servidor
-- a cada tick para que RaceServer.lua rode OvertakeCore.
-- ------------------------------------------------------------

function RaceLogic.StartSnapshotLoop()
    loopGeneration = loopGeneration + 1
    local myGen = loopGeneration
    local myVeh = RaceState.myVehicle

    Citizen.CreateThread(function()
        while RaceState.isActive() and loopGeneration == myGen do
            if myVeh and DoesEntityExist(myVeh) then
                local pos   = GetEntityCoords(myVeh)
                local fwd   = GetEntityForwardVector(myVeh)
                local vel   = GetEntityVelocity(myVeh)
                local speed = math.sqrt(vel.x * vel.x + vel.y * vel.y)
                TriggerServerEvent(Config.Events.Server.POSITION_SNAPSHOT, {
                    x          = pos.x,
                    y          = pos.y,
                    z          = pos.z,
                    heading    = GetEntityHeading(myVeh),
                    fx         = fwd.x,
                    fy         = fwd.y,
                    vx         = vel.x,
                    vy         = vel.y,
                    speed      = speed,
                    valid      = true,
                    eliminated = RaceState.eliminated,
                })
            end
            Citizen.Wait(Config.Race.DISTANCE_UPDATE_INTERVAL)
        end
    end)
end
