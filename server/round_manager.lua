-- ============================================================
--  OUTRUN — Server: RoundManager
--
--  Use-cases de ciclo de rodada: iniciar, encerrar, decidir
--  Rodada Bônus, distribuir pontos, checar campeão.
-- ============================================================

RoundManager = {}

local Events = Config.Events


-- ===== Internos =====

local function rollBonusRound(room)
    if math.random() >= Config.BonusRound.TRIGGER_PROBABILITY then
        return { active = false, targetSrc = nil }
    end

    local topScore = 0
    for _, p in ipairs(room.participants) do
        if not p.isNPC then
            topScore = math.max(topScore, room.scores[p.source] or 0)
        end
    end

    if topScore <= 0 and room.roundNum <= 1 then
        return { active = false, targetSrc = nil }
    end

    local targetSrc = Rooms.getChampionshipLeader(room)
    return { active = true, targetSrc = targetSrc }
end

local function pickSpawnNode()
    local nodes = Config.SpawnNodes
    return nodes[math.random(#nodes)]
end


-- ===== API pública =====

function RoundManager.start(roomId, room)
    if not room or not Rooms.get(roomId) then return end

    Rooms.setState(room, Config.States.Room.SPAWN_GRID)
    room.roundNum = room.roundNum + 1

    local spawnPoint = pickSpawnNode()
    local bonus = rollBonusRound(room)

    TriggerClientEvent(Events.Client.SPAWN_VEHICLES, room.host, {
        roomId       = roomId,
        participants = room.participants,
        spawnBase    = spawnPoint,
        bonusRound   = bonus,
        scores       = room.scores,
    })

    Logger.info("SRV", ("Sala %d iniciando rodada %d%s"):format(
        roomId, room.roundNum, bonus.active and " [BÔNUS]" or ""))
end

function RoundManager.markRacing(room)
    Rooms.setState(room, Config.States.Room.RACING)
    Logger.debug("SRV", ("Sala %d → RACING"):format(room.id))
end

function RoundManager.handleLeaderUpdate(room, leaderId)
    if room.state ~= Config.States.Room.RACING then return end
    room.currentLeader = leaderId
    Rooms.eachHuman(room, function(p)
        TriggerClientEvent(Events.Client.LEADER_CHANGED, p.source, leaderId)
    end)
end

function RoundManager.handleEliminated(room, eliminatedId)
    Rooms.eachHuman(room, function(p)
        if tostring(p.source) == tostring(eliminatedId) then
            TriggerClientEvent(Events.Client.BE_SPECTATOR, p.source, room.currentLeader)
        end
    end)
end

function RoundManager.endRound(roomId, room, results)
    if not room then return end

    Rooms.setState(room, Config.States.Room.ROUND_RESULT)
    Rooms.applyScoring(room, results)

    Rooms.eachHuman(room, function(p)
        TriggerClientEvent(Events.Client.CLEAR_WANTED, p.source)
    end)

    Rooms.setState(room, Config.States.Room.CHECK_CHAMPIONSHIP)
    local champion = Rooms.findChampion(room)
    local names = Rooms.buildNames(room)

    if champion then
        Rooms.setState(room, Config.States.Room.END_SCREEN)
        Rooms.eachHuman(room, function(p)
            TriggerClientEvent(Events.Client.SHOW_END_SCREEN, p.source,
                champion, room.scores, names)
        end)
        Rooms.delete(roomId)
        Logger.info("SRV", ("Campeão: %s (%s)"):format(
            tostring(champion), names[champion] or "?"))
        return
    end

    Rooms.setState(room, Config.States.Room.ROUND_RESULT)
    Rooms.eachHuman(room, function(p)
        TriggerClientEvent(Events.Client.ROUND_RESULT, p.source,
            results, room.scores, names)
    end)

    local capturedId = roomId
    Citizen.SetTimeout(10000, function()
        local current = Rooms.get(capturedId)
        if current then RoundManager.start(capturedId, current) end
    end)
    Logger.debug("SRV", ("Sala %d aguardando 10s para próxima rodada"):format(roomId))
end
