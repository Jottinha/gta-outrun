RaceLogic = {}

local function normalize2D(x, y)
    local magnitude = math.sqrt((x * x) + (y * y))
    if magnitude <= 0.0001 then
        return 0.0, 1.0
    end

    return x / magnitude, y / magnitude
end

local function getActiveParticipants(participants)
    local active = {}

    for _, participant in ipairs(participants) do
        if not participant.eliminated
        and participant.vehicle
        and DoesEntityExist(participant.vehicle) then
            active[#active + 1] = participant
        end
    end

    return active
end

local function findParticipantByVehicle(participants, vehicle)
    for _, participant in ipairs(participants) do
        if participant.vehicle == vehicle then
            return participant
        end
    end

    return nil
end

local function getVehicleFrame(vehicle)
    local position = GetEntityCoords(vehicle)
    local forward = GetEntityForwardVector(vehicle)
    local fx, fy = normalize2D(forward.x, forward.y)

    return position, fx, fy
end

function RaceLogic.Dist2D(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt((dx * dx) + (dy * dy))
end

function RaceLogic.ResolveLeader(participants, currentLeaderVeh)
    local active = getActiveParticipants(participants)
    if #active == 0 then
        return nil, nil
    end

    local leaderVeh = currentLeaderVeh
    if not leaderVeh or not DoesEntityExist(leaderVeh) then
        leaderVeh = active[1].vehicle
    end

    if not findParticipantByVehicle(active, leaderVeh) then
        leaderVeh = active[1].vehicle
    end

    for _ = 1, #active do
        local leaderPos, forwardX, forwardY = getVehicleFrame(leaderVeh)
        local bestCandidate = nil

        for _, participant in ipairs(active) do
            if participant.vehicle ~= leaderVeh then
                local participantPos = GetEntityCoords(participant.vehicle)
                local dx = participantPos.x - leaderPos.x
                local dy = participantPos.y - leaderPos.y
                local dz = math.abs(participantPos.z - leaderPos.z)
                local longitudinal = (dx * forwardX) + (dy * forwardY)
                local lateral = math.abs((dx * forwardY) - (dy * forwardX))

                if dz <= Config.Race.LEADER_MAX_Z_DIFF
                and longitudinal > Config.Race.LEADER_PASS_DISTANCE then
                    if not bestCandidate
                    or longitudinal > bestCandidate.longitudinal
                    or (
                        math.abs(longitudinal - bestCandidate.longitudinal) <= 0.5
                        and lateral < bestCandidate.lateral
                    ) then
                        bestCandidate = {
                            vehicle = participant.vehicle,
                            longitudinal = longitudinal,
                            lateral = lateral,
                        }
                    end
                end
            end
        end

        if not bestCandidate then
            break
        end

        leaderVeh = bestCandidate.vehicle
    end

    local leaderParticipant = findParticipantByVehicle(active, leaderVeh)
    return leaderVeh, leaderParticipant and leaderParticipant.id or nil
end

function RaceLogic.BuildStandings(participants, leaderVeh)
    local active = getActiveParticipants(participants)
    if #active == 0 or not leaderVeh or not DoesEntityExist(leaderVeh) then
        return {}
    end

    local leaderPos, forwardX, forwardY = getVehicleFrame(leaderVeh)
    local standings = {}

    for _, participant in ipairs(active) do
        local participantPos = GetEntityCoords(participant.vehicle)
        local dx = participantPos.x - leaderPos.x
        local dy = participantPos.y - leaderPos.y

        standings[#standings + 1] = {
            id = participant.id,
            vehicle = participant.vehicle,
            isNPC = participant.isNPC,
            dist = RaceLogic.Dist2D(leaderPos, participantPos),
            longitudinal = (dx * forwardX) + (dy * forwardY),
            lateral = math.abs((dx * forwardY) - (dy * forwardX)),
            isLeader = participant.vehicle == leaderVeh,
        }
    end

    table.sort(standings, function(a, b)
        if a.isLeader ~= b.isLeader then
            return a.isLeader
        end

        if math.abs(a.dist - b.dist) > 0.5 then
            return a.dist < b.dist
        end

        if math.abs(a.longitudinal - b.longitudinal) > 0.5 then
            return a.longitudinal > b.longitudinal
        end

        return a.lateral < b.lateral
    end)

    return standings
end

function RaceLogic.GetRaceSnapshot(participants, currentLeaderVeh)
    local leaderVeh, leaderId = RaceLogic.ResolveLeader(participants, currentLeaderVeh)
    local standings = RaceLogic.BuildStandings(participants, leaderVeh)

    return {
        leaderVeh = leaderVeh,
        leaderId = leaderId or (standings[1] and standings[1].id or nil),
        standings = standings,
        runnerUp = standings[2],
    }
end

function RaceLogic.StartLoop(getParticipants, getLeaderVeh, callback)
    Citizen.CreateThread(function()
        while RaceState.isActive() do
            local snapshot = RaceLogic.GetRaceSnapshot(getParticipants(), getLeaderVeh())
            if snapshot.leaderVeh and DoesEntityExist(snapshot.leaderVeh) then
                callback(snapshot)
            end
            Citizen.Wait(Config.Race.DISTANCE_UPDATE_INTERVAL)
        end
    end)
end
