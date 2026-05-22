-- ============================================================
--  OUTRUN — Server: Bootstrap / handlers de eventos
--
--  Este arquivo só faz wiring entre os eventos da rede e os
--  módulos `Rooms` (estado) e `RoundManager` (use-cases).
-- ============================================================

local SE = Config.Events.Server
local CE = Config.Events.Client


-- ===== Lobby =====

RegisterNetEvent(SE.CREATE_LOBBY, function(pointTarget)
    local src = source

    if Rooms.getByHost(src) then
        TriggerClientEvent(CE.NOTIFY, src, "Você já possui uma sala aberta.")
        return
    end

    local roomId, room = Rooms.create(src, tonumber(pointTarget))
    TriggerClientEvent(CE.LOBBY_CREATED, src, roomId, room)
    Logger.info("SRV", ("Sala %d criada pelo jogador %d"):format(roomId, src))
end)

RegisterNetEvent(SE.REQUEST_LOBBY_STATE, function()
    local src = source
    local roomId, room = Rooms.getByParticipant(src)
    if room then
        TriggerClientEvent(CE.LOBBY_CREATED, src, roomId, room)
    else
        TriggerClientEvent(CE.NO_ACTIVE_LOBBY, src)
    end
end)

RegisterNetEvent(SE.ADD_NPC, function(model, personality)
    local src = source
    local _, room = Rooms.getByHost(src)
    if not room or room.state ~= Config.States.Room.LOBBY then return end

    Rooms.addNPC(room, model, personality)
    TriggerClientEvent(CE.LOBBY_UPDATED, src, room)
end)

RegisterNetEvent(SE.SET_CAR, function(model)
    local src = source
    local _, room = Rooms.getByParticipant(src)
    if not room or room.state ~= Config.States.Room.LOBBY then return end

    if Rooms.setParticipantCar(room, src, model) then
        TriggerClientEvent(CE.LOBBY_UPDATED, room.host, room)
    end
end)

RegisterNetEvent(SE.TOGGLE_READY, function()
    local src = source
    local _, room = Rooms.getByParticipant(src)
    if not room or room.state ~= Config.States.Room.LOBBY then return end

    Rooms.toggleReady(room, src)
    TriggerClientEvent(CE.LOBBY_UPDATED, room.host, room)
end)

RegisterNetEvent(SE.LEAVE_LOBBY, function()
    local src = source
    local roomId, room = Rooms.getByParticipant(src)
    if not room or room.state ~= Config.States.Room.LOBBY then return end

    if room.host == src then
        -- Host saindo: a sala é encerrada para todos os participantes humanos.
        Rooms.eachHuman(room, function(p)
            if p.source ~= src then
                TriggerClientEvent(CE.FORCE_LOBBY_CLOSE, p.source)
            end
        end)
        Rooms.delete(roomId)
        Logger.info("SRV", ("Sala %d encerrada (host %d saiu)"):format(roomId, src))
    else
        Rooms.removeParticipant(room, src)
        TriggerClientEvent(CE.LOBBY_UPDATED, room.host, room)
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

RegisterNetEvent(SE.RACE_STARTED, function()
    local src = source
    local _, room = Rooms.getByHost(src)
    if not room then return end
    RoundManager.markRacing(room)
end)

RegisterNetEvent(SE.UPDATE_LEADER, function(leaderId)
    local src = source
    local _, room = Rooms.getByHost(src)
    if not room then return end
    RoundManager.handleLeaderUpdate(room, leaderId)
end)

RegisterNetEvent(SE.ROUND_END, function(results)
    local src = source
    local roomId, room = Rooms.getByHost(src)
    if not room then return end
    RoundManager.endRound(roomId, room, results)
end)


-- ===== Eliminação =====

RegisterNetEvent(SE.PLAYER_ELIMINATED, function(eliminatedId)
    local src = source
    local _, room = Rooms.getByHost(src)
    if not room then return end
    RoundManager.handleEliminated(room, eliminatedId)
end)
