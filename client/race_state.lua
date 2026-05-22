-- ============================================================
--  OUTRUN — Client: RaceState
--
--  Container do estado local da corrida. Outros módulos LEEM,
--  só este modifica via funções nomeadas.
-- ============================================================

RaceState = {
    active           = false,
    isHost           = false,
    isMultiplayer    = false,
    roomId           = nil,
    leaderId         = nil,
    leaderVeh        = nil,
    runnerUpId       = nil,
    runnerUpVeh      = nil,
    -- Top-K vehicles dos perseguidores ordenados (mais próximo do líder primeiro).
    -- Usado pela IA do líder para fugir considerando múltiplos chasers.
    topChasers       = {},
    myVehicle        = nil,
    participants     = {},
    eliminationOrder = {},
    eliminated       = false,
}


function RaceState.isActive()
    return RaceState.active == true
end

function RaceState.reset()
    RaceState.active           = false
    RaceState.isHost           = false
    RaceState.isMultiplayer    = false
    RaceState.roomId           = nil
    RaceState.leaderId         = nil
    RaceState.leaderVeh        = nil
    RaceState.runnerUpId       = nil
    RaceState.runnerUpVeh      = nil
    RaceState.topChasers       = {}
    RaceState.myVehicle        = nil
    RaceState.participants     = {}
    RaceState.eliminationOrder = {}
    RaceState.eliminated       = false
end

function RaceState.findParticipant(participantId)
    for index, p in ipairs(RaceState.participants) do
        if tostring(p.id) == tostring(participantId) then
            return p, index
        end
    end
end

function RaceState.markEliminated(participantId)
    local participant = RaceState.findParticipant(participantId)
    if not participant or participant.eliminated then
        return false, participant
    end
    participant.eliminated = true
    RaceState.eliminationOrder[#RaceState.eliminationOrder + 1] = participant.id
    return true, participant
end

function RaceState.buildRoundResults(activeStandings)
    local results = {}
    local seen = {}

    for _, entry in ipairs(activeStandings) do
        results[#results + 1] = entry.id
        seen[entry.id] = true
    end

    for index = #RaceState.eliminationOrder, 1, -1 do
        local participantId = RaceState.eliminationOrder[index]
        if not seen[participantId] then
            results[#results + 1] = participantId
            seen[participantId] = true
        end
    end

    local formatted = {}
    for position, participantId in ipairs(results) do
        formatted[#formatted + 1] = { id = participantId, position = position }
    end
    return formatted
end
