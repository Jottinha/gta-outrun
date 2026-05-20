AIController = {}

local npcs = {}
local raceStartTime = 0

local function normalize2D(x, y)
    local magnitude = math.sqrt((x * x) + (y * y))
    if magnitude <= 0.0001 then
        return 0.0, 1.0
    end

    return x / magnitude, y / magnitude
end

local function DebugLog(npcId, msg)
    if not Config.Debug.ENABLED then return end
    print(("%s [AI:%s] %s"):format(Config.Debug.LOG_PREFIX, tostring(npcId), msg))
end

local function bucketCoord(value, bucketSize)
    return math.floor(value / bucketSize)
end


local function getLeaderPed(leaderVeh)
    if not leaderVeh or not DoesEntityExist(leaderVeh) then
        return nil
    end

    local leaderPed = GetPedInVehicleSeat(leaderVeh, -1)
    if leaderPed == 0 or not DoesEntityExist(leaderPed) then
        return nil
    end

    return leaderPed
end

local function buildChaseRoleKey(leaderPed)
    return ("%s:%s"):format(Config.States.AI.CHASE, leaderPed)
end

local function getEvadePlan(vehicle, runnerUpVeh)
    local vehiclePos = GetEntityCoords(vehicle)
    local forward = GetEntityForwardVector(vehicle)
    local dirX, dirY = normalize2D(forward.x, forward.y)
    local runnerUpId = "none"

    if runnerUpVeh and DoesEntityExist(runnerUpVeh) then
        local runnerUpPos = GetEntityCoords(runnerUpVeh)
        local awayX, awayY = normalize2D(vehiclePos.x - runnerUpPos.x, vehiclePos.y - runnerUpPos.y)
        local runnerUpDist = RaceLogic.Dist2D(vehiclePos, runnerUpPos)
        local alignment = (dirX * awayX) + (dirY * awayY)
        local awayWeight = 0.35

        if runnerUpDist <= Config.AI.EVADE_PRESSURE_DISTANCE then
            awayWeight = 0.55
        end

        if alignment < 0.0 then
            awayWeight = 0.75
        end

        dirX, dirY = normalize2D(
            (dirX * (1.0 - awayWeight)) + (awayX * awayWeight),
            (dirY * (1.0 - awayWeight)) + (awayY * awayWeight)
        )
        runnerUpId = tostring(runnerUpVeh)
    end

    local rawTarget = vector3(
        vehiclePos.x + (dirX * Config.AI.EVADE_FORWARD_DISTANCE),
        vehiclePos.y + (dirY * Config.AI.EVADE_FORWARD_DISTANCE),
        vehiclePos.z
    )

    local found, nodePos = GetClosestVehicleNode(rawTarget.x, rawTarget.y, rawTarget.z, 1, 3.0, 0)
    if found and type(nodePos) == "vector3" then
        local bucketSize = Config.AI.EVADE_ROLE_BUCKET_SIZE
        return {
            roleKey = ("%s:%s:%s:%s"):format(
                Config.States.AI.EVADE,
                runnerUpId,
                bucketCoord(nodePos.x, bucketSize),
                bucketCoord(nodePos.y, bucketSize)
            ),
            destination = nodePos,
        }
    end

    return {
        roleKey = ("%s:%s:wander"):format(Config.States.AI.EVADE, runnerUpId),
        destination = nil,
    }
end

local function getRecoveryDestination(vehicle)
    local vehiclePos = GetEntityCoords(vehicle)
    local forward = GetEntityForwardVector(vehicle)
    local radius = Config.AI.RECOVERY_NODE_RADIUS
    local probes = {
        vector3(vehiclePos.x - (forward.x * radius), vehiclePos.y - (forward.y * radius), vehiclePos.z),
        vector3(vehiclePos.x + (forward.x * radius), vehiclePos.y + (forward.y * radius), vehiclePos.z),
        vector3(vehiclePos.x, vehiclePos.y, vehiclePos.z),
    }

    local bestNode = nil
    local bestDist = nil

    for _, probe in ipairs(probes) do
        local found, nodePos = GetClosestVehicleNode(probe.x, probe.y, probe.z, 1, 3.0, 0)
        if found and type(nodePos) == "vector3" then
            local nodeDist = RaceLogic.Dist2D(vehiclePos, nodePos)
            if nodeDist <= radius and (not bestDist or nodeDist < bestDist) then
                bestNode = nodePos
                bestDist = nodeDist
            end
        end
    end

    return bestNode
end

local function clearRecoveryState(data)
    DebugLog(data.npcId, "RECOVERY → saindo (velocidade recuperada)")
    data.currentRole = nil
    data.currentMode = nil
    data.stuckTimer = 0
end

local function enterEvadeRole(data, runnerUpVeh)
    local vehicle = data.vehicle
    local ped = data.ped
    local plan = getEvadePlan(vehicle, runnerUpVeh)

    if data.currentRole == plan.roleKey then
        return
    end

    data.currentRole = plan.roleKey
    data.currentMode = Config.States.AI.EVADE

    local evadeDestStr = plan.destination
        and ("(%.0f, %.0f)"):format(plan.destination.x, plan.destination.y)
        or "wander"
    DebugLog(data.npcId, ("→ EVADE | dest=%s | role=%s"):format(evadeDestStr, plan.roleKey))

    SetDriveTaskDrivingStyle(ped, Config.AI.EVADE_DRIVING_STYLE)

    if plan.destination then
        TaskVehicleDriveToCoord(
            ped,
            vehicle,
            plan.destination.x,
            plan.destination.y,
            plan.destination.z,
            Config.AI.EVADE_SPEED,
            0,
            GetEntityModel(vehicle),
            Config.AI.EVADE_DRIVING_STYLE,
            15.0,
            true
        )
    else
        TaskVehicleDriveWander(ped, vehicle, Config.AI.EVADE_SPEED, Config.AI.EVADE_DRIVING_STYLE)
    end
end

local function enterChaseRole(data, leaderVeh)
    local leaderPed = getLeaderPed(leaderVeh)
    if not leaderPed then
        return
    end

    local roleKey = buildChaseRoleKey(leaderPed)
    if data.currentRole == roleKey then
        return
    end

    local vehicle = data.vehicle
    local ped = data.ped

    data.currentRole = roleKey
    data.currentMode = Config.States.AI.CHASE

    DebugLog(data.npcId, ("→ B1:CHASE | style=%d | TaskVehicleChase"):format(Config.AI.CHASE_DRIVING_STYLE))

    SetDriveTaskDrivingStyle(ped, Config.AI.CHASE_DRIVING_STYLE)
    TaskVehicleChase(ped, leaderPed)
    SetTaskVehicleChaseBehaviorFlag(ped, 1, true)
    SetDriveTaskDrivingStyle(ped, Config.AI.CHASE_DRIVING_STYLE)
end

local function enterChaseCloseRole(data, leaderVeh)
    if not leaderVeh or not DoesEntityExist(leaderVeh) then
        return
    end

    local vehicle = data.vehicle
    local ped = data.ped

    -- Primeira entrada em B2: abandona TaskVehicleChase e foca em ultrapassar
    if data.currentRole ~= Config.States.AI.CHASER_CLOSE then
        data.currentRole          = Config.States.AI.CHASER_CLOSE
        data.currentMode          = Config.States.AI.CHASE
        data.chaseCloseLastIssued = 0
        DebugLog(data.npcId, "→ B2:OVERTAKE entry | mirando à frente do líder")
    end

    -- Throttle: re-emite a task a cada CHASE_CLOSE_UPDATE_MS ms
    local now = GetGameTimer()
    if (now - data.chaseCloseLastIssued) < Config.AI.CHASE_CLOSE_UPDATE_MS then
        return
    end

    -- Carrot: ponto fixo à frente do líder na sua direção de movimento
    local leaderPos     = GetEntityCoords(leaderVeh)
    local leaderForward = GetEntityForwardVector(leaderVeh)

    local rawTarget = vector3(
        leaderPos.x + (leaderForward.x * Config.AI.CHASE_CLOSE_AHEAD_DISTANCE),
        leaderPos.y + (leaderForward.y * Config.AI.CHASE_CLOSE_AHEAD_DISTANCE),
        leaderPos.z
    )

    local found, nodePos = GetClosestVehicleNode(rawTarget.x, rawTarget.y, rawTarget.z, 1, 3.0, 0)
    if not found or type(nodePos) ~= "vector3" then
        DebugLog(data.npcId, "B2 node → NENHUM NÓ ENCONTRADO")
        return
    end

    data.chaseCloseLastIssued = now

    DebugLog(data.npcId, ("B2 overtake | carrot=%.0fm → node=(%.0f, %.0f, %.1f) | TaskVehicleDriveToCoord"):format(
        Config.AI.CHASE_CLOSE_AHEAD_DISTANCE, nodePos.x, nodePos.y, nodePos.z
    ))

    TaskVehicleDriveToCoord(
        ped,
        vehicle,
        nodePos.x,
        nodePos.y,
        nodePos.z,
        Config.AI.EVADE_SPEED,
        0,
        GetEntityModel(vehicle),
        Config.AI.CHASE_DRIVING_STYLE,
        3.0,
        true
    )
end

local function enterRecoveryRole(data)
    if data.currentMode == Config.States.AI.RECOVERY then
        return
    end

    local vehicle = data.vehicle
    local ped = data.ped
    local destination = getRecoveryDestination(vehicle)

    data.currentRole = Config.States.AI.RECOVERY
    data.currentMode = Config.States.AI.RECOVERY

    local recovDestStr = destination
        and ("(%.0f, %.0f)"):format(destination.x, destination.y)
        or "wander"
    DebugLog(data.npcId, ("→ RECOVERY | dest=%s | speed=%.0f"):format(recovDestStr, Config.AI.RECOVERY_SPEED))

    ClearPedTasks(ped)
    SetDriveTaskDrivingStyle(ped, Config.AI.RECOVERY_DRIVING_STYLE)

    if destination then
        TaskVehicleDriveToCoord(
            ped,
            vehicle,
            destination.x,
            destination.y,
            destination.z,
            Config.AI.RECOVERY_SPEED,
            0,
            GetEntityModel(vehicle),
            Config.AI.RECOVERY_DRIVING_STYLE,
            3.0,
            true
        )
    else
        TaskVehicleDriveWander(ped, vehicle, Config.AI.RECOVERY_SPEED, Config.AI.RECOVERY_DRIVING_STYLE)
    end
end

function AIController.RegisterNPC(npcId, vehicle, ped, personality)
    npcs[npcId] = {
        npcId = npcId,
        vehicle = vehicle,
        ped = ped,
        personality = personality or "balanced",
        currentRole = Config.States.AI.GRID,
        currentMode = Config.States.AI.GRID,
        stuckTimer = 0,
        lastTickAt           = GetGameTimer(),
        chaseCloseLastIssued = 0,
    }
    DebugLog(npcId, ("REGISTRADO | personality=%s"):format(personality or "balanced"))
end

function AIController.UnregisterAll()
    for _, data in pairs(npcs) do
        if DoesEntityExist(data.ped) then
            DeleteEntity(data.ped)
        end
        if DoesEntityExist(data.vehicle) then
            DeleteVehicle(data.vehicle)
        end
    end

    npcs = {}
    raceStartTime = 0
end

function AIController.SetState(npcId, newState)
    local data = npcs[npcId]
    if not data then
        return
    end

    if newState == Config.States.AI.ELIMINATED then
        data.currentRole = Config.States.AI.ELIMINATED
        data.currentMode = Config.States.AI.ELIMINATED
    elseif newState == Config.States.AI.GRID then
        data.currentRole = Config.States.AI.GRID
        data.currentMode = Config.States.AI.GRID
        data.stuckTimer = 0
    end
end

function AIController.Tick(npcId, leaderVeh, runnerUpVeh)
    local data = npcs[npcId]
    if not data then
        return "remove"
    end

    local vehicle = data.vehicle
    local ped = data.ped

    if not DoesEntityExist(vehicle) or not DoesEntityExist(ped) then
        return "remove"
    end

    if data.currentMode == Config.States.AI.GRID then
        FreezeEntityPosition(vehicle, true)
        return
    end

    if data.currentMode == Config.States.AI.ELIMINATED then
        if DoesEntityExist(ped) then
            DeleteEntity(ped)
        end
        if DoesEntityExist(vehicle) then
            DeleteVehicle(vehicle)
        end
        return "remove"
    end

    local now = GetGameTimer()
    local tickDelta = now - (data.lastTickAt or now)
    local raceElapsed = now - raceStartTime
    local speed = GetEntitySpeed(vehicle)
    local isLeader = (leaderVeh == vehicle)

    data.lastTickAt = now

    DebugLog(npcId, ("tick | speed=%.2fm/s | mode=%s | role=%s"):format(speed, tostring(data.currentMode), tostring(data.currentRole)))

    if data.currentMode == Config.States.AI.RECOVERY then
        if speed > Config.AI.STUCK_SPEED_THRESHOLD then
            clearRecoveryState(data)
        else
            DebugLog(npcId, ("RECOVERY aguardando | speed=%.2fm/s"):format(speed))
        end
        return
    end

    if raceElapsed >= Config.AI.STUCK_WARMUP_MS then
        if speed < Config.AI.STUCK_SPEED_THRESHOLD then
            data.stuckTimer = data.stuckTimer + tickDelta
            DebugLog(npcId, ("STUCK | speed=%.2fm/s | timer=%dms / %dms"):format(speed, data.stuckTimer, Config.AI.STUCK_TIME_THRESHOLD_MS))
            if data.stuckTimer >= Config.AI.STUCK_TIME_THRESHOLD_MS then
                DebugLog(npcId, "STUCK → limite atingido, entrando em RECOVERY")
                enterRecoveryRole(data)
                return
            end
        else
            data.stuckTimer = 0
        end
    else
        data.stuckTimer = 0
    end

    if isLeader then
        enterEvadeRole(data, runnerUpVeh)
        return
    end

    -- Estado B: Perseguidor — subfase por distância 2D
    local npcPos    = GetEntityCoords(vehicle)
    local leaderPos = GetEntityCoords(leaderVeh)
    local chaseDist = RaceLogic.Dist2D(npcPos, leaderPos)

    DebugLog(npcId, ("dist2D=%.1fm | threshold=%.1fm → %s"):format(
        chaseDist,
        Config.AI.CHASE_CLOSE_DISTANCE,
        chaseDist > Config.AI.CHASE_CLOSE_DISTANCE and "B1:CHASE" or "B2:OVERTAKE"
    ))

    if chaseDist > Config.AI.CHASE_CLOSE_DISTANCE then
        -- B1: Aproximação — persegue normalmente
        enterChaseRole(data, leaderVeh)
    else
        -- B2: Ultrapassagem — carrot on a stick à frente do líder
        enterChaseCloseRole(data, leaderVeh)
    end
end

function AIController.StartLoop(getLeaderVeh, getRunnerUpVeh)
    Citizen.CreateThread(function()
        while RaceState and RaceState.active do
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

function AIController.ReleaseGrid()
    raceStartTime = GetGameTimer()

    for _, data in pairs(npcs) do
        FreezeEntityPosition(data.vehicle, false)
        SetVehicleEngineOn(data.vehicle, true, true, false)
        data.currentRole = nil
        data.currentMode = nil
        data.stuckTimer = 0
        data.lastTickAt = raceStartTime
    end
end
