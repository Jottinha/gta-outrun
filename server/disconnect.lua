-- ============================================================
--  OUTRUN — Server: Disconnect handler
--
--  Detecta playerDropped. Se o host saiu, destrói a sala e
--  notifica os participantes. Caso contrário, remove o
--  participante da sala onde ele estava.
-- ============================================================

local function notifyAndCloseLobby(room, droppedSrc)
    for _, p in ipairs(room.participants) do
        if not p.isNPC and p.source ~= droppedSrc then
            TriggerClientEvent(Config.Events.Client.NOTIFY, p.source,
                "O host abandonou a partida. A sala foi encerrada.")
            TriggerClientEvent(Config.Events.Client.FORCE_LOBBY_CLOSE, p.source)
        end
    end
end

AddEventHandler('playerDropped', function()
    local src = source
    local hostRoomId, hostRoom = Rooms.getByHost(src)

    if hostRoom then
        notifyAndCloseLobby(hostRoom, src)
        Rooms.delete(hostRoomId)
        Logger.info("SRV",
            ("Host %d desconectou. Sala %d destruída."):format(src, hostRoomId))
        return
    end

    local participantRoomId, participantRoom = Rooms.getByParticipant(src)
    if participantRoom then
        Rooms.removeParticipant(participantRoom, src)
        TriggerClientEvent(Config.Events.Client.LOBBY_UPDATED,
            participantRoom.host, participantRoom)
        Logger.debug("SRV",
            ("Player %d saiu da sala %d"):format(src, participantRoomId))
    end
end)
