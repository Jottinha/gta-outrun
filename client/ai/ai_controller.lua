-- ============================================================
--  OUTRUN — Client/AI: Controller
--
--  Mantém o registro de NPCs e roda a FSM. Decisões de
--  comportamento (driving style, velocidades, thresholds) são
--  delegadas à Strategy associada a cada NPC.
--
--  Estados: GRID / CHASE / CHASER_CLOSE / EVADE / RECOVERY / ELIMINATED
-- ============================================================

AIController = {}

local AI = Config.States.AI
local npcs = {}
local raceStartTime = 0


-- ============================================================
-- Utilidades
-- ============================================================

local function normalize2D(x, y)
    local mag = math.sqrt((x * x) + (y * y))
    if mag <= 0.0001 then return 0.0, 1.0 end
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
-- Plano de fuga (EVADE)
-- ============================================================

local function getEvadePlan(strategy, vehicle, runnerUpVeh)
    local vehiclePos = GetEntityCoords(vehicle)
    local forward = GetEntityForwardVector(vehicle)
    local dirX, dirY = normalize2D(forward.x, forward.y)
    local runnerUpId = "none"

    if runnerUpVeh and DoesEntityExist(runnerUpVeh) then
        local runnerUpPos = GetEntityCoords(runnerUpVeh)
        local awayX, awayY = normalize2D(
            vehiclePos.x - runnerUpPos.x,
            vehiclePos.y - runnerUpPos.y)
        local runnerUpDist = RaceLogic.Dist2D(vehiclePos, runnerUpPos)
        local alignment = (dirX * awayX) + (dirY * awayY)
        local awayWeight = 0.35

        if runnerUpDist <= strategy.evadePressureDistance then
            awayWeight = 0.55
        end
        if alignment < 0.0 then
            awayWeight = 0.75
        end

        dirX, dirY = normalize2D(
            (dirX * (1.0 - awayWeight)) + (awayX * awayWeight),
            (dirY * (1.0 - awayWeight)) + (awayY * awayWeight))
        runnerUpId = tostring(runnerUpVeh)
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
                AI.EVADE, runnerUpId,
                bucketCoord(nodePos.x, bucketSize),
                bucketCoord(nodePos.y, bucketSize)),
            destination = nodePos,
        }
    end

    return {
        roleKey = ("%s:%s:wander"):format(AI.EVADE, runnerUpId),
        destination = nil,
    }
end


-- ============================================================
-- Plano de recuperação
-- ============================================================

local function getRecoveryDestination(vehicle)
    local vehiclePos = GetEntityCoords(vehicle)
    local forward = GetEntityForwardVector(vehicle)
    local radius = Config.AI.RECOVERY_NODE_RADIUS
    local probes = {
        vector3(vehiclePos.x - (forward.x * radius), vehiclePos.y - (forward.y * radius), vehiclePos.z),
        vector3(vehiclePos.x + (forward.x * radius), vehiclePos.y + (forward.y * radius), vehiclePos.z),
        vector3(vehiclePos.x, vehiclePos.y, vehiclePos.z),
    }

    local bestNode, bestDist = nil, nil
    for _, probe in ipairs(probes) do
        local found, nodePos = GetClosestVehicleNode(probe.x, probe.y, probe.z, 1, 3.0, 0)
        if found and type(nodePos) == "vector3" then
            local nodeDist = RaceLogic.Dist2D(vehiclePos, nodePos)
            if nodeDist <= radius and (not bestDist or nodeDist < bestDist) then
                bestNode, bestDist = nodePos, nodeDist
            end
        end
    end
    return bestNode
end


-- ============================================================
-- Transições de modo (enter*Role)
-- ============================================================

local function enterEvadeRole(data, runnerUpVeh)
    local strategy = data.strategy
    local plan = getEvadePlan(strategy, data.vehicle, runnerUpVeh)

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
    local leaderPed = getLeaderPed(leaderVeh)
    if not leaderPed then return end

    local roleKey = ("%s:%s"):format(AI.CHASE, leaderPed)
    if data.currentRole == roleKey then return end

    local strategy = data.strategy
    data.currentRole = roleKey
    data.currentMode = AI.CHASE

    Logger.debug("AI:" .. data.npcId,
        ("→ CHASE | style=%d"):format(strategy.chaseDrivingStyle))

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
        Logger.debug("AI:" .. data.npcId, "→ CHASER_CLOSE entry")
    end

    local now = GetGameTimer()
    if (now - data.chaseCloseLastIssued) < strategy.chaseCloseUpdateMs then
        return
    end

    local leaderPos     = GetEntityCoords(leaderVeh)
    local leaderForward = GetEntityForwardVector(leaderVeh)
    local rawTarget = vector3(
        leaderPos.x + (leaderForward.x * strategy.chaseCloseAhead),
        leaderPos.y + (leaderForward.y * strategy.chaseCloseAhead),
        leaderPos.z)

    local found, nodePos = GetClosestVehicleNode(rawTarget.x, rawTarget.y, rawTarget.z, 1, 3.0, 0)
    if not found or type(nodePos) ~= "vector3" then
        Logger.debug("AI:" .. data.npcId, "CHASER_CLOSE: nenhum nó encontrado")
        return
    end

    data.chaseCloseLastIssued = now
    Logger.debug("AI:" .. data.npcId, ("CHASER_CLOSE | carrot=%.0fm → node=(%.0f,%.0f)"):format(
        strategy.chaseCloseAhead, nodePos.x, nodePos.y))

    TaskVehicleDriveToCoord(
        data.ped, data.vehicle,
        nodePos.x, nodePos.y, nodePos.z,
        strategy.overtakeSpeed, 0, GetEntityModel(data.vehicle),
        strategy.chaseCloseDrivingStyle, 3.0, true)
end

local function enterRecoveryRole(data)
    if data.currentMode == AI.RECOVERY then return end

    local strategy = data.strategy
    local destination = getRecoveryDestination(data.vehicle)

    data.currentRole = AI.RECOVERY
    data.currentMode = AI.RECOVERY

    Logger.debug("AI:" .. data.npcId, ("→ RECOVERY | dest=%s | speed=%.0f"):format(
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
    npcs[npcId] = {
        npcId                = npcId,
        vehicle              = vehicle,
        ped                  = ped,
        strategy             = AIStrategy.create(personality),
        currentRole          = AI.GRID,
        currentMode          = AI.GRID,
        stuckTimer           = 0,
        lastTickAt           = GetGameTimer(),
        chaseCloseLastIssued = 0,
    }
    Logger.debug("AI:" .. tostring(npcId),
        ("REGISTRADO | personality=%s"):format(personality or "balanced"))
end

function AIController.UnregisterAll()
    for _, data in pairs(npcs) do
        if DoesEntityExist(data.ped) then DeleteEntity(data.ped) end
        if DoesEntityExist(data.vehicle) then DeleteVehicle(data.vehicle) end
    end
    npcs = {}
    raceStartTime = 0
end

function AIController.SetState(npcId, newState)
    local data = npcs[npcId]
    if not data then return end

    if newState == AI.ELIMINATED then
        data.currentRole = AI.ELIMINATED
        data.currentMode = AI.ELIMINATED
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

function AIController.Tick(npcId, leaderVeh, runnerUpVeh)
    local data = npcs[npcId]
    if not data then return "remove" end

    if not DoesEntityExist(data.vehicle) or not DoesEntityExist(data.ped) then
        return "remove"
    end

    if data.currentMode == AI.GRID then
        FreezeEntityPosition(data.vehicle, true)
        return
    end

    if data.currentMode == AI.ELIMINATED then
        if DoesEntityExist(data.ped) then DeleteEntity(data.ped) end
        if DoesEntityExist(data.vehicle) then DeleteVehicle(data.vehicle) end
        return "remove"
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

    -- Anti-stuck (após warmup)
    if raceElapsed >= Config.AI.STUCK_WARMUP_MS then
        if speed < Config.AI.STUCK_SPEED_THRESHOLD then
            data.stuckTimer = data.stuckTimer + tickDelta
            if data.stuckTimer >= Config.AI.STUCK_TIME_THRESHOLD_MS then
                Logger.debug("AI:" .. npcId, "STUCK → entrando em RECOVERY")
                enterRecoveryRole(data)
                return
            end
        else
            data.stuckTimer = 0
        end
    else
        data.stuckTimer = 0
    end

    -- Líder → EVADE
    if isLeader then
        enterEvadeRole(data, runnerUpVeh)
        return
    end

    -- Perseguidor → CHASE ou CHASER_CLOSE
    local npcPos    = GetEntityCoords(data.vehicle)
    local leaderPos = GetEntityCoords(leaderVeh)
    local chaseDist = RaceLogic.Dist2D(npcPos, leaderPos)

    if chaseDist > data.strategy.chaseCloseThreshold then
        enterChaseRole(data, leaderVeh)
    else
        enterChaseCloseRole(data, leaderVeh)
    end
end

function AIController.StartLoop(getLeaderVeh, getRunnerUpVeh)
    Citizen.CreateThread(function()
        while RaceState.isActive() do
            local leaderVeh = getLeaderVeh()
            local runnerUpVeh = getRunnerUpVeh()

            if leaderVeh and DoesEntityExist(leaderVeh) then
                local toRemove = {}
                for npcId, _ in pairs(npcs) do
                    if AIController.Tick(npcId, leaderVeh, runnerUpVeh) == "remove" then
                        toRemove[#toRemove + 1] = npcId
                    end
                end
                for _, npcId in ipairs(toRemove) do
                    npcs[npcId] = nil
                end
            end

            Citizen.Wait(Config.AI.DRIVE_UPDATE_INTERVAL)
        end
    end)
end
