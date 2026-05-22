-- ============================================================
--  OUTRUN — Client/AI: Controller
--
--  Mantém o registro de NPCs e roda a FSM. Decisões de
--  comportamento (driving style, velocidades, thresholds) são
--  delegadas à Strategy associada a cada NPC.
--
--  Estados: GRID / CHASE / CHASER_CLOSE / EVADE / RECOVERY / ELIMINATED
--
--  Multi-bot:
--    * chaseSlot:    índice estável por NPC para spread lateral (anti pile-up)
--    * recoverySalt: variante de nó em RECOVERY (anti-cascata em pelotão)
--    * staggered:    threshold de STUCK aumenta com o slot
--    * EVADE recebe a lista dos top-K chasers (não só runner-up)
-- ============================================================

AIController = {}

local AI = Config.States.AI
local npcs = {}
local nextChaseSlot = 0
local raceStartTime = 0
-- Generation token: incrementar invalida threads de loop ativas
-- (cancelamento cooperativo, igual ao RaceLogic.StopLoop).
local loopGeneration = 0


-- ============================================================
-- Utilidades
-- ============================================================

local function normalize2D(x, y)
    local mag = math.sqrt((x * x) + (y * y))
    if mag <= 0.0001 then return nil end
    return x / mag, y / mag
end

local function bucketCoord(value, bucketSize)
    return math.floor(value / bucketSize)
end

local function getLeaderPed(leaderVeh)
    if not leaderVeh or not DoesEntityExist(leaderVeh) then return nil end
    local leaderPed = GetPedInVehicleSeat(leaderVeh, -1)
    if leaderPed == 0 or not DoesEntityExist(leaderPed) then return nil end
    return leaderPed
end


-- ============================================================
-- Plano de fuga (EVADE) — considera top-K chasers
-- ============================================================

-- Vetor médio "para longe dos perseguidores", ponderado por 1/dist.
-- chasers: lista de vehicle handles (RaceState.topChasers).
local function computeAwayVector(vehiclePos, chasers)
    if not chasers or #chasers == 0 then return nil, nil, 0 end

    local sumX, sumY, totalWeight = 0.0, 0.0, 0.0
    local closestDist = math.huge

    for _, chaserVeh in ipairs(chasers) do
        if chaserVeh and DoesEntityExist(chaserVeh) then
            local cPos = GetEntityCoords(chaserVeh)
            local dx = vehiclePos.x - cPos.x
            local dy = vehiclePos.y - cPos.y
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist < 1.0 then dist = 1.0 end
            if dist < closestDist then closestDist = dist end

            local weight = 1.0 / dist  -- mais próximo = peso maior
            sumX = sumX + (dx / dist) * weight
            sumY = sumY + (dy / dist) * weight
            totalWeight = totalWeight + weight
        end
    end

    if totalWeight <= 0 then return nil, nil, 0 end
    local nx, ny = normalize2D(sumX, sumY)
    return nx, ny, closestDist
end

local function getEvadePlan(strategy, vehicle, chasers)
    local vehiclePos = GetEntityCoords(vehicle)
    local forward = GetEntityForwardVector(vehicle)
    local dirX, dirY = normalize2D(forward.x, forward.y)
    if not dirX then dirX, dirY = 0.0, 1.0 end

    local chasersTag = "none"
    local awayX, awayY, closestDist = computeAwayVector(vehiclePos, chasers)

    if awayX then
        local alignment = (dirX * awayX) + (dirY * awayY)
        local awayWeight = 0.35

        if closestDist <= strategy.evadePressureDistance then
            awayWeight = 0.55
        end
        if alignment < 0.0 then
            awayWeight = 0.75
        end

        local mx, my = normalize2D(
            (dirX * (1.0 - awayWeight)) + (awayX * awayWeight),
            (dirY * (1.0 - awayWeight)) + (awayY * awayWeight))
        if mx then dirX, dirY = mx, my end
        chasersTag = tostring(#chasers)
    end

    local rawTarget = vector3(
        vehiclePos.x + (dirX * strategy.evadeForwardDistance),
        vehiclePos.y + (dirY * strategy.evadeForwardDistance),
        vehiclePos.z)

    local found, nodePos = GetClosestVehicleNode(rawTarget.x, rawTarget.y, rawTarget.z, 1, 3.0, 0)
    if found and type(nodePos) == "vector3" then
        local bucketSize = Config.AI.EVADE_ROLE_BUCKET_SIZE
        return {
            roleKey = ("%s:%s:%s:%s"):format(
                AI.EVADE, chasersTag,
                bucketCoord(nodePos.x, bucketSize),
                bucketCoord(nodePos.y, bucketSize)),
            destination = nodePos,
        }
    end

    return {
        roleKey = ("%s:%s:wander"):format(AI.EVADE, chasersTag),
        destination = nil,
    }
end


-- ============================================================
-- Plano de recuperação — variante por salt evita pile-up
-- ============================================================

local function getRecoveryDestination(vehicle, salt)
    local vehiclePos = GetEntityCoords(vehicle)
    local forward    = GetEntityForwardVector(vehicle)
    local radius     = Config.AI.RECOVERY_NODE_RADIUS
    local variants   = math.max(1, Config.AI.RECOVERY_NODE_VARIANTS or 1)
    local nth        = (salt % variants) + 1

    local probes = {
        vector3(vehiclePos.x - (forward.x * radius), vehiclePos.y - (forward.y * radius), vehiclePos.z),
        vector3(vehiclePos.x + (forward.x * radius), vehiclePos.y + (forward.y * radius), vehiclePos.z),
        vector3(vehiclePos.x, vehiclePos.y, vehiclePos.z),
    }

    local bestNode, bestDist = nil, nil
    for _, probe in ipairs(probes) do
        local found, nodePos = GetNthClosestVehicleNode(probe.x, probe.y, probe.z, nth, 1, 3.0, 0)
        if found and type(nodePos) == "vector3" then
            local dx = vehiclePos.x - nodePos.x
            local dy = vehiclePos.y - nodePos.y
            local nodeDist = math.sqrt(dx * dx + dy * dy)
            if nodeDist <= radius * variants and (not bestDist or nodeDist < bestDist) then
                bestNode, bestDist = nodePos, nodeDist
            end
        end
    end
    return bestNode
end


-- ============================================================
-- Offset lateral por slot — spread de chasers
-- ============================================================

-- Retorna (offsetX, offsetY) perpendicular ao forward do líder, baseado no slot.
-- slot 0 → 0, slot 1 → +spacing, slot 2 → -spacing, slot 3 → +2*spacing, ...
-- mantém o slot 0 no centro (mira direta) e distribui em torno.
-- O step é clampado para evitar jogar NPCs em pista paralela em vias estreitas.
local function lateralOffset(leaderForward, slot)
    if slot == 0 then return 0.0, 0.0 end
    local spacing = Config.AI.CHASER_LATERAL_SPACING
    local maxStep = Config.AI.CHASER_MAX_LATERAL_STEP or 2
    local step    = math.min(math.ceil(slot / 2), maxStep)
    local sign    = (slot % 2 == 1) and 1.0 or -1.0
    local rightX  = -leaderForward.y
    local rightY  =  leaderForward.x
    return rightX * sign * step * spacing, rightY * sign * step * spacing
end


-- ============================================================
-- Transições de modo (enter*Role)
-- ============================================================

local function enterEvadeRole(data, chasers)
    local strategy = data.strategy
    local plan = getEvadePlan(strategy, data.vehicle, chasers)

    if data.currentRole == plan.roleKey then return end

    data.currentRole = plan.roleKey
    data.currentMode = AI.EVADE

    Logger.debug("AI:" .. data.npcId, ("→ EVADE | dest=%s | role=%s"):format(
        plan.destination and ("(%.0f,%.0f)"):format(plan.destination.x, plan.destination.y) or "wander",
        plan.roleKey))

    SetDriveTaskDrivingStyle(data.ped, strategy.evadeDrivingStyle)

    if plan.destination then
        TaskVehicleDriveToCoord(
            data.ped, data.vehicle,
            plan.destination.x, plan.destination.y, plan.destination.z,
            strategy.evadeSpeed, 0, GetEntityModel(data.vehicle),
            strategy.evadeDrivingStyle, 15.0, true)
    else
        TaskVehicleDriveWander(data.ped, data.vehicle,
            strategy.evadeSpeed, strategy.evadeDrivingStyle)
    end
end

local function enterChaseRole(data, leaderVeh)
    local strategy = data.strategy
    local leaderPed = getLeaderPed(leaderVeh)

    if not leaderPed then
        -- Líder sem ped no banco do motorista (capotou, ejetou, replicação atrasada).
        -- Em vez de retornar silenciosamente, mantém o NPC andando para não travar.
        if data.currentRole ~= "CHASE:nopilot" then
            data.currentRole = "CHASE:nopilot"
            data.currentMode = AI.CHASE
            Logger.debug("AI:" .. data.npcId, "→ CHASE (sem ped no líder) fallback wander")
            SetDriveTaskDrivingStyle(data.ped, strategy.chaseDrivingStyle)
            TaskVehicleDriveWander(data.ped, data.vehicle,
                strategy.overtakeSpeed, strategy.chaseDrivingStyle)
        end
        return
    end

    local roleKey = ("%s:%s"):format(AI.CHASE, leaderPed)
    if data.currentRole == roleKey then return end

    data.currentRole = roleKey
    data.currentMode = AI.CHASE

    Logger.debug("AI:" .. data.npcId,
        ("→ CHASE | slot=%d | style=%d"):format(data.chaseSlot, strategy.chaseDrivingStyle))

    SetDriveTaskDrivingStyle(data.ped, strategy.chaseDrivingStyle)
    TaskVehicleChase(data.ped, leaderPed)
    SetTaskVehicleChaseBehaviorFlag(data.ped, 1, true)
end

local function enterChaseCloseRole(data, leaderVeh)
    if not leaderVeh or not DoesEntityExist(leaderVeh) then return end

    local strategy = data.strategy

    if data.currentRole ~= AI.CHASER_CLOSE then
        data.currentRole          = AI.CHASER_CLOSE
        data.currentMode          = AI.CHASE
        data.chaseCloseLastIssued = 0
        data.chaseCloseMissCount  = 0
        data.chaseCloseLastNode   = nil
        Logger.debug("AI:" .. data.npcId, ("→ CHASER_CLOSE entry | slot=%d"):format(data.chaseSlot))
    end

    local now = GetGameTimer()
    if (now - data.chaseCloseLastIssued) < strategy.chaseCloseUpdateMs then
        return
    end

    local leaderPos     = GetEntityCoords(leaderVeh)
    local leaderForward = GetEntityForwardVector(leaderVeh)
    local offX, offY    = lateralOffset(leaderForward, data.chaseSlot)
    local rawTarget = vector3(
        leaderPos.x + (leaderForward.x * strategy.chaseCloseAhead) + offX,
        leaderPos.y + (leaderForward.y * strategy.chaseCloseAhead) + offY,
        leaderPos.z)

    local found, nodePos = GetClosestVehicleNode(rawTarget.x, rawTarget.y, rawTarget.z, 1, 3.0, 0)
    if not found or type(nodePos) ~= "vector3" then
        data.chaseCloseMissCount = (data.chaseCloseMissCount or 0) + 1
        if data.chaseCloseMissCount >= Config.AI.CHASE_CLOSE_MAX_MISSES then
            Logger.debug("AI:" .. data.npcId,
                ("CHASER_CLOSE: %d falhas → fallback wander"):format(data.chaseCloseMissCount))
            TaskVehicleDriveWander(data.ped, data.vehicle,
                strategy.overtakeSpeed, strategy.chaseCloseDrivingStyle)
            data.chaseCloseMissCount  = 0
            data.chaseCloseLastIssued = now
            data.chaseCloseLastNode   = nil
        end
        return
    end

    data.chaseCloseMissCount  = 0
    data.chaseCloseLastIssued = now

    -- Delta-check: só reissua a task se o nó alvo mudou o suficiente. Reissues
    -- consecutivos cancelam a task atual e destroem o pathfinding em curso.
    local last = data.chaseCloseLastNode
    if last then
        local ddx = nodePos.x - last.x
        local ddy = nodePos.y - last.y
        if (ddx * ddx + ddy * ddy) < (Config.AI.CHASE_CLOSE_REISSUE_DELTA ^ 2) then
            return
        end
    end
    data.chaseCloseLastNode = nodePos

    TaskVehicleDriveToCoord(
        data.ped, data.vehicle,
        nodePos.x, nodePos.y, nodePos.z,
        strategy.overtakeSpeed, 0, GetEntityModel(data.vehicle),
        strategy.chaseCloseDrivingStyle, 3.0, true)
end

local function enterRecoveryRole(data)
    if data.currentMode == AI.RECOVERY then return end

    local strategy = data.strategy
    local destination = getRecoveryDestination(data.vehicle, data.recoverySalt)

    data.currentRole = AI.RECOVERY
    data.currentMode = AI.RECOVERY

    Logger.debug("AI:" .. data.npcId, ("→ RECOVERY | salt=%d | dest=%s | speed=%.0f"):format(
        data.recoverySalt,
        destination and ("(%.0f,%.0f)"):format(destination.x, destination.y) or "wander",
        strategy.recoverySpeed))

    ClearPedTasks(data.ped)
    SetDriveTaskDrivingStyle(data.ped, strategy.recoveryDrivingStyle)

    if destination then
        TaskVehicleDriveToCoord(
            data.ped, data.vehicle,
            destination.x, destination.y, destination.z,
            strategy.recoverySpeed, 0, GetEntityModel(data.vehicle),
            strategy.recoveryDrivingStyle, 3.0, true)
    else
        TaskVehicleDriveWander(data.ped, data.vehicle,
            strategy.recoverySpeed, strategy.recoveryDrivingStyle)
    end
end

local function clearRecoveryState(data)
    Logger.debug("AI:" .. data.npcId, "RECOVERY → saindo (velocidade recuperada)")
    data.currentRole = nil
    data.currentMode = nil
    data.stuckTimer = 0
end


-- ============================================================
-- API pública
-- ============================================================

function AIController.RegisterNPC(npcId, vehicle, ped, personality)
    local slot = nextChaseSlot
    nextChaseSlot = nextChaseSlot + 1

    npcs[npcId] = {
        npcId                = npcId,
        vehicle              = vehicle,
        ped                  = ped,
        strategy             = AIStrategy.create(personality),
        currentRole          = AI.GRID,
        currentMode          = AI.GRID,
        chaseSlot            = slot,
        recoverySalt         = slot,  -- mesma base — variante de nó em RECOVERY
        stuckTimer           = 0,
        lastTickAt           = GetGameTimer(),
        chaseCloseLastIssued = 0,
        chaseCloseMissCount  = 0,
    }
    Logger.debug("AI:" .. tostring(npcId),
        ("REGISTRADO | slot=%d | personality=%s"):format(slot, personality or "balanced"))
end

function AIController.UnregisterAll()
    for _, data in pairs(npcs) do
        if DoesEntityExist(data.ped) then DeleteEntity(data.ped) end
        if DoesEntityExist(data.vehicle) then DeleteVehicle(data.vehicle) end
    end
    npcs = {}
    nextChaseSlot = 0
    raceStartTime = 0
end

function AIController.SetState(npcId, newState)
    local data = npcs[npcId]
    if not data then return end

    if newState == AI.ELIMINATED then
        -- Deferred delete: deletamos as entidades agora, mas marcamos o
        -- registro para o LOOP remover de `npcs`. Evita race cooperativa
        -- com `for npcId, _ in pairs(npcs)` em outra thread.
        Logger.debug("AI:" .. npcId, "→ ELIMINATED (deferred)")
        data.pendingDelete = true
        if DoesEntityExist(data.ped) then DeleteEntity(data.ped) end
        if DoesEntityExist(data.vehicle) then DeleteVehicle(data.vehicle) end
        return
    elseif newState == AI.GRID then
        data.currentRole = AI.GRID
        data.currentMode = AI.GRID
        data.stuckTimer  = 0
    end
end

function AIController.ReleaseGrid()
    raceStartTime = GetGameTimer()
    for _, data in pairs(npcs) do
        FreezeEntityPosition(data.vehicle, false)
        SetVehicleEngineOn(data.vehicle, true, true, false)
        data.currentRole = nil
        data.currentMode = nil
        data.stuckTimer  = 0
        data.lastTickAt  = raceStartTime
    end
end


-- ============================================================
-- Loop principal (FSM)
-- ============================================================

function AIController.Tick(npcId, leaderVeh, chasers)
    local data = npcs[npcId]
    if not data or data.pendingDelete then return "remove" end

    if not DoesEntityExist(data.vehicle) or not DoesEntityExist(data.ped) then
        return "remove"
    end

    if data.currentMode == AI.GRID then
        FreezeEntityPosition(data.vehicle, true)
        return
    end

    local now = GetGameTimer()
    local tickDelta = now - (data.lastTickAt or now)
    local raceElapsed = now - raceStartTime
    local speed = GetEntitySpeed(data.vehicle)
    local isLeader = (leaderVeh == data.vehicle)
    data.lastTickAt = now

    -- Recovery: aguarda velocidade voltar
    if data.currentMode == AI.RECOVERY then
        if speed > Config.AI.STUCK_SPEED_THRESHOLD then
            clearRecoveryState(data)
        end
        return
    end

    -- Anti-stuck (após warmup) — threshold com stagger por slot
    if raceElapsed >= Config.AI.STUCK_WARMUP_MS then
        local stuckThreshold = Config.AI.STUCK_TIME_THRESHOLD_MS
            + (data.chaseSlot * Config.AI.STUCK_TIME_STAGGER_MS)
        if speed < Config.AI.STUCK_SPEED_THRESHOLD then
            data.stuckTimer = data.stuckTimer + tickDelta
            if data.stuckTimer >= stuckThreshold then
                Logger.debug("AI:" .. npcId, ("STUCK → RECOVERY (thr=%dms)"):format(stuckThreshold))
                enterRecoveryRole(data)
                return
            end
        else
            data.stuckTimer = 0
        end
    else
        data.stuckTimer = 0
    end

    -- Líder → EVADE (considerando top-K chasers)
    if isLeader then
        enterEvadeRole(data, chasers)
        return
    end

    -- Perseguidor → CHASE ou CHASER_CLOSE (histerese assimétrica)
    local npcPos    = GetEntityCoords(data.vehicle)
    local leaderPos = GetEntityCoords(leaderVeh)
    local dx = npcPos.x - leaderPos.x
    local dy = npcPos.y - leaderPos.y
    local chaseDist = math.sqrt(dx * dx + dy * dy)

    local inClose = (data.currentRole == AI.CHASER_CLOSE)
    if inClose then
        if chaseDist > data.strategy.chaseCloseExit then
            enterChaseRole(data, leaderVeh)
        else
            enterChaseCloseRole(data, leaderVeh)
        end
    else
        if chaseDist <= data.strategy.chaseCloseThreshold then
            enterChaseCloseRole(data, leaderVeh)
        else
            enterChaseRole(data, leaderVeh)
        end
    end
end

function AIController.StartLoop(getLeaderVeh, getTopChasers)
    loopGeneration = loopGeneration + 1
    local myGen = loopGeneration

    Citizen.CreateThread(function()
        while RaceState.isActive() and loopGeneration == myGen do
            local leaderVeh = getLeaderVeh()
            local chasers   = getTopChasers() or {}

            -- Coleta a lista de ids ANTES de iterar — evita race com SetState
            -- removendo entradas durante o for-pairs.
            local snapshot = {}
            for npcId in pairs(npcs) do snapshot[#snapshot + 1] = npcId end

            if leaderVeh and DoesEntityExist(leaderVeh) then
                local toRemove = {}
                for _, npcId in ipairs(snapshot) do
                    if AIController.Tick(npcId, leaderVeh, chasers) == "remove" then
                        toRemove[#toRemove + 1] = npcId
                    end
                end
                for _, npcId in ipairs(toRemove) do
                    npcs[npcId] = nil
                end
            else
                -- Mesmo sem líder válido, limpa pendingDelete acumulado.
                for _, npcId in ipairs(snapshot) do
                    local data = npcs[npcId]
                    if data and data.pendingDelete then npcs[npcId] = nil end
                end
            end

            Citizen.Wait(Config.AI.DRIVE_UPDATE_INTERVAL)
        end
    end)
end

function AIController.StopLoop()
    loopGeneration = loopGeneration + 1
end
