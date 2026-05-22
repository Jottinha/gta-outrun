-- ============================================================
--  OUTRUN — Server: Bootstrap / handlers de eventos
--
--  Wiring entre eventos de rede e os módulos Rooms / RoundManager.
--  Solo (1 humano): comportamento idêntico ao anterior.
--  Multiplayer (2+ humanos): novos eventos JOIN_ROOM, SPAWN_READY,
--  POSITION_SNAPSHOT; lobby broadcasts para todos os participantes.
-- ============================================================

local SE = Config.Events.Server
local CE = Config.Events.Client


-- ===== Helper: broadcast para todos os humanos da sala =====

local function broadcastLobby(room)
    local payload = Rooms.toLobbyPayload(room)
    Rooms.eachHuman(room, function(p)
        TriggerClientEvent(CE.LOBBY_UPDATED, p.source, payload)
    end)
end


-- ===== Lobby =====

RegisterNetEvent(SE.CREATE_LOBBY, function(pointTarget)
    local src = source

    if Rooms.getByParticipant(src) then
        TriggerClientEvent(CE.NOTIFY, src, "Você já está em uma sala.")
        return
    end

    local roomId, room = Rooms.create(src, tonumber(pointTarget))
    TriggerClientEvent(CE.LOBBY_CREATED, src, roomId, Rooms.toLobbyPayload(room))
    Logger.info("SRV", ("Sala %d criada pelo jogador %d"):format(roomId, src))
end)

RegisterNetEvent(SE.REQUEST_LOBBY_STATE, function()
    local src = source
    local roomId, room = Rooms.getByParticipant(src)
    if room then
        local myIsHost = (room.host == src)
        TriggerClientEvent(CE.LOBBY_CREATED, src, roomId, Rooms.toLobbyPayload(room), myIsHost)
    else
        TriggerClientEvent(CE.NO_ACTIVE_LOBBY, src)
    end
end)

-- Multiplayer: entrar em sala existente
RegisterNetEvent(SE.JOIN_ROOM, function(roomId)
    local src = source

    if Rooms.getByParticipant(src) then
        TriggerClientEvent(CE.NOTIFY, src, "Você já está em uma sala.")
        return
    end

    local room = Rooms.get(roomId)
    if not room then
        TriggerClientEvent(CE.NOTIFY, src, "Sala não encontrada.")
        return
    end
    if room.state ~= Config.States.Room.LOBBY then
        TriggerClientEvent(CE.NOTIFY, src, "Esta sala já está em corrida.")
        return
    end
    if Rooms.humanCount(room) >= Config.Race.MAX_PLAYERS then
        TriggerClientEvent(CE.NOTIFY, src, "Sala cheia.")
        return
    end

    -- Ao entrar o segundo humano: remover todos os NPCs (MP sem bots)
    if Rooms.humanCount(room) >= 1 then
        Rooms.removeAllNPCs(room)
    end

    Rooms.addHuman(room, src)

    -- Confirmar ao jogador que entrou
    TriggerClientEvent(CE.LOBBY_CREATED, src, roomId, Rooms.toLobbyPayload(room), false)

    -- Atualizar lobby para todos (incluindo o host)
    broadcastLobby(room)

    Logger.info("SRV", ("Jogador %d entrou na sala %d"):format(src, roomId))
end)

RegisterNetEvent(SE.ADD_NPC, function(model, personality)
    local src = source
    local _, room = Rooms.getByHost(src)
    if not room or room.state ~= Config.States.Room.LOBBY then return end

    if Rooms.isMultiplayer(room) then
        TriggerClientEvent(CE.NOTIFY, src, "Bots não são permitidos em partidas multiplayer.")
        return
    end

    Rooms.addNPC(room, model, personality)
    TriggerClientEvent(CE.LOBBY_UPDATED, src, Rooms.toLobbyPayload(room))
end)

RegisterNetEvent(SE.SET_CAR, function(model)
    local src = source
    local _, room = Rooms.getByParticipant(src)
    if not room or room.state ~= Config.States.Room.LOBBY then return end

    if Rooms.setParticipantCar(room, src, model) then
        broadcastLobby(room)
    end
end)

RegisterNetEvent(SE.TOGGLE_READY, function()
    local src = source
    local _, room = Rooms.getByParticipant(src)
    if not room or room.state ~= Config.States.Room.LOBBY then return end

    Rooms.toggleReady(room, src)
    broadcastLobby(room)
end)

RegisterNetEvent(SE.LEAVE_LOBBY, function()
    local src = source
    local roomId, room = Rooms.getByParticipant(src)
    if not room or room.state ~= Config.States.Room.LOBBY then return end

    if room.host == src then
        Rooms.eachHuman(room, function(p)
            if p.source ~= src then
                TriggerClientEvent(CE.FORCE_LOBBY_CLOSE, p.source)
            end
        end)
        Rooms.delete(roomId)
        Logger.info("SRV", ("Sala %d encerrada (host %d saiu)"):format(roomId, src))
    else
        Rooms.removeParticipant(room, src)
        broadcastLobby(room)
        Logger.info("SRV", ("Jogador %d saiu da sala %d"):format(src, roomId))
    end
end)

RegisterNetEvent(SE.REQUEST_ROOMS_LIST, function()
    local src = source
    TriggerClientEvent(CE.ROOMS_LIST, src, Rooms.list())
end)


-- ===== Corrida =====

RegisterNetEvent(SE.START_RACE, function()
    local src = source
    local roomId, room = Rooms.getByHost(src)
    if not room or room.state ~= Config.States.Room.LOBBY then return end

    if not Rooms.allHumansReady(room) then
        TriggerClientEvent(CE.NOTIFY, src, "Nem todos os jogadores estão prontos.")
        return
    end

    RoundManager.start(roomId, room)
end)

-- Multiplayer: player reporta que seu veículo está pronto
RegisterNetEvent(SE.SPAWN_READY, function(netId)
    local src = source
    local roomId, room = Rooms.getByParticipant(src)
    if not room or room.state ~= Config.States.Room.SPAWN_GRID then return end

    RoundManager.handleSpawnReady(roomId, room, src, netId)
end)

-- Multiplayer: snapshot de posição do player para o OvertakeCore server-side
RegisterNetEvent(SE.POSITION_SNAPSHOT, function(snap)
    local src = source
    local roomId, room = Rooms.getByParticipant(src)
    if not room or room.state ~= Config.States.Room.RACING then return end

    RaceServer.updateSnapshot(roomId, src, snap)
end)

-- Solo: host avisa que a corrida começou (apenas solo; MP não usa este evento)
RegisterNetEvent(SE.RACE_STARTED, function()
    local src = source
    local _, room = Rooms.getByHost(src)
    if not room or Rooms.isMultiplayer(room) then return end
    RoundManager.markRacing(room)
end)

-- Solo: host reporta troca de líder (MP usa RaceServer internamente)
RegisterNetEvent(SE.UPDATE_LEADER, function(leaderId)
    local src = source
    local _, room = Rooms.getByHost(src)
    if not room or Rooms.isMultiplayer(room) then return end
    RoundManager.handleLeaderUpdate(room, leaderId)
end)

-- Solo: host reporta fim de rodada (MP encerra via RaceServer)
RegisterNetEvent(SE.ROUND_END, function(results)
    local src = source
    local roomId, room = Rooms.getByHost(src)
    if not room or Rooms.isMultiplayer(room) then return end
    RoundManager.endRound(roomId, room, results)
end)

-- Solo: host reporta eliminação (MP usa RaceServer internamente)
RegisterNetEvent(SE.PLAYER_ELIMINATED, function(eliminatedId)
    local src = source
    local _, room = Rooms.getByHost(src)
    if not room or Rooms.isMultiplayer(room) then return end
    RoundManager.handleEliminated(room, eliminatedId)
end)
