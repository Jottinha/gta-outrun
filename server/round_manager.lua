-- ============================================================
--  OUTRUN — Server: RoundManager
--
--  Use-cases de ciclo de rodada: iniciar, encerrar, decidir
--  Rodada Bônus, distribuir pontos, checar campeão.
--
--  Solo (1 humano): comportamento idêntico ao anterior.
--  Multiplayer (2+ humanos): spawn distribuído + countdown
--  server-side + OvertakeCore rodando em RaceServer.
-- ============================================================

RoundManager = {}

local Events = Config.Events

math.randomseed(os.time())


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


-- ===== Broadcast lobby para todos os humanos =====

local function broadcastLobby(room)
    local payload = Rooms.toLobbyPayload(room)
    Rooms.eachHuman(room, function(p)
        TriggerClientEvent(Events.Client.LOBBY_UPDATED, p.source, payload)
    end)
end


-- ===== Countdown server-side (apenas MP) =====

local function runServerCountdown(roomId, room)
    local capturedId   = roomId
    local capturedRoom = room

    Citizen.CreateThread(function()
        Rooms.setState(capturedRoom, Config.States.Room.COUNTDOWN)

        for i = Config.Race.COUNTDOWN_SECONDS, 1, -1 do
            if not Rooms.get(capturedId) then return end
            Rooms.eachHuman(capturedRoom, function(p)
                TriggerClientEvent(Events.Client.COUNTDOWN_TICK, p.source, i)
            end)
            Citizen.Wait(1000)
        end

        if not Rooms.get(capturedId) then return end

        Rooms.eachHuman(capturedRoom, function(p)
            TriggerClientEvent(Events.Client.RACE_START, p.source, {})
        end)

        RoundManager.markRacing(capturedRoom)
        RaceServer.startSession(capturedId, capturedRoom)

        Logger.info("SRV", ("Sala %d corrida MP iniciada!"):format(capturedId))
    end)
end


-- ===== API pública =====

function RoundManager.start(roomId, room)
    if not room or not Rooms.get(roomId) then return end

    Rooms.setState(room, Config.States.Room.SPAWN_GRID)
    Rooms.clearNetIds(room)
    room.roundNum = room.roundNum + 1

    local spawnPoint = pickSpawnNode()
    local bonus      = rollBonusRound(room)

    local isMP = Rooms.isMultiplayer(room)
    Logger.info("SRV", ("Sala %d rodada %d — modo: %s, humans: %d"):format(
        roomId, room.roundNum, isMP and "MP" or "SOLO", Rooms.humanCount(room)))

    if isMP then
        -- MP: cada player spawna o seu veículo
        local humanIdx   = 0
        local humanCount = Rooms.humanCount(room)

        for _, p in ipairs(room.participants) do
            if not p.isNPC then
                humanIdx = humanIdx + 1
                TriggerClientEvent(Events.Client.SPAWN_MY_VEHICLE, p.source, {
                    roomId     = roomId,
                    spawnBase  = spawnPoint,
                    model      = p.model,
                    gridIndex  = humanIdx,
                    totalCount = humanCount,
                    bonusRound = bonus,
                    scores     = room.scores,
                    isHost     = (p.source == room.host),
                })
            end
        end

        Logger.info("SRV", ("Sala %d iniciando rodada %d (MP, %d players)"):format(
            roomId, room.roundNum, humanCount))
    else
        -- Solo: host spawna tudo localmente (comportamento original)
        TriggerClientEvent(Events.Client.SPAWN_VEHICLES, room.host, {
            roomId       = roomId,
            participants = room.participants,
            spawnBase    = spawnPoint,
            bonusRound   = bonus,
            scores       = room.scores,
        })

        Logger.info("SRV", ("Sala %d iniciando rodada %d (solo)"):format(roomId, room.roundNum))
    end
end

-- Chamado quando cada player envia SE.SPAWN_READY com seu netId.
-- Quando todos estão prontos inicia o countdown server-side.
function RoundManager.handleSpawnReady(roomId, room, src, netId)
    if room.state ~= Config.States.Room.SPAWN_GRID then return end

    Rooms.setNetId(room, src, netId)
    Logger.debug("SRV", ("Sala %d: jogador %d pronto (netId=%d)"):format(roomId, src, netId))

    if Rooms.allHumansSpawned(room) then
        local netIdMap = Rooms.buildNetIdMap(room)
        Rooms.eachHuman(room, function(p)
            TriggerClientEvent(Events.Client.ALL_SPAWNED, p.source, netIdMap)
        end)
        Logger.debug("SRV", ("Sala %d: todos spawnados — iniciando countdown"):format(roomId))
        runServerCountdown(roomId, room)
    end
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

    -- Encerrar sessão server-side se MP
    if RaceServer.hasSession(roomId) then
        RaceServer.endSession(roomId)
    end

    Rooms.setState(room, Config.States.Room.ROUND_RESULT)
    Rooms.applyScoring(room, results)

    Rooms.eachHuman(room, function(p)
        TriggerClientEvent(Events.Client.CLEAR_WANTED, p.source)
    end)

    Rooms.setState(room, Config.States.Room.CHECK_CHAMPIONSHIP)
    local champion = Rooms.findChampion(room)
    local names    = Rooms.buildNames(room)

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
