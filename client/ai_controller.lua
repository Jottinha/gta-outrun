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

local function bucketCoord(value, bucketSize)
    return math.floor(value / bucketSize)
end

local function resetPowerMultiplier(vehicle)
    SetVehicleEnginePowerMultiplier(vehicle, 0.0)
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

    resetPowerMultiplier(vehicle)
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

    SetDriveTaskDrivingStyle(ped, Config.AI.CHASE_DRIVING_STYLE)
    SetVehicleEnginePowerMultiplier(vehicle, Config.AI.CHASE_ENGINE_POWER_MULTIPLIER)
    TaskVehicleChase(ped, leaderPed)
    SetTaskVehicleChaseBehaviorFlag(ped, 1, true)
    SetDriveTaskDrivingStyle(ped, Config.AI.CHASE_DRIVING_STYLE)
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

    resetPowerMultiplier(vehicle)
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
        vehicle = vehicle,
        ped = ped,
        personality = personality or "balanced",
        currentRole = Config.States.AI.GRID,
        currentMode = Config.States.AI.GRID,
        stuckTimer = 0,
        lastTickAt = GetGameTimer(),
    }
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

    if data.currentMode == Config.States.AI.RECOVERY then
        if speed > Config.AI.STUCK_SPEED_THRESHOLD then
            clearRecoveryState(data)
        end
        return
    end

    if raceElapsed >= Config.AI.STUCK_WARMUP_MS then
        if speed < Config.AI.STUCK_SPEED_THRESHOLD then
            data.stuckTimer = data.stuckTimer + tickDelta
            if data.stuckTimer >= Config.AI.STUCK_TIME_THRESHOLD_MS then
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

    enterChaseRole(data, leaderVeh)
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
        resetPowerMultiplier(data.vehicle)
    end
end
