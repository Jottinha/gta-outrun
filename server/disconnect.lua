-- ============================================================
--  OUTRUN — Server: Disconnect handler
--
--  Detecta playerDropped. Lida com três cenários:
--   1. Host sai durante LOBBY  → destrói sala, notifica todos
--   2. Host sai durante RACING (MP) → promove próximo humano;
--      se não há mais humanos, encerra a sala
--   3. Participante (não-host) sai → remove da sala, atualiza lobby
-- ============================================================

local CE = Config.Events.Client

local function notifyAndCloseLobby(room, droppedSrc)
    for _, p in ipairs(room.participants) do
        if not p.isNPC and p.source ~= droppedSrc then
            TriggerClientEvent(CE.NOTIFY, p.source,
                "O host abandonou a partida. A sala foi encerrada.")
            TriggerClientEvent(CE.FORCE_LOBBY_CLOSE, p.source)
        end
    end
end

local function broadcastLobby(room)
    local payload = Rooms.toLobbyPayload(room)
    Rooms.eachHuman(room, function(p)
        TriggerClientEvent(CE.LOBBY_UPDATED, p.source, payload)
    end)
end

AddEventHandler('playerDropped', function()
    local src         = source
    local hostRoomId, hostRoom = Rooms.getByHost(src)

    if hostRoom then
        -- Host desconectou
        if hostRoom.state == Config.States.Room.RACING and Rooms.isMultiplayer(hostRoom) then
            -- Tentar promover outro humano como novo host
            local newHost = Rooms.promoteNextHost(hostRoom)
            if newHost then
                TriggerClientEvent(CE.HOST_PROMOTED, newHost, newHost)
                Rooms.eachHuman(hostRoom, function(p)
                    if p.source ~= newHost then
                        TriggerClientEvent(CE.NOTIFY, p.source,
                            "O host saiu. Um novo host foi selecionado.")
                    end
                end)
                Logger.info("SRV", ("Host %d saiu. Sala %d: novo host = %d"):format(
                    src, hostRoomId, newHost))
                return
            end
        end

        -- Sem promoção possível: encerrar sala
        if RaceServer.hasSession(hostRoomId) then
            RaceServer.endSession(hostRoomId)
        end
        notifyAndCloseLobby(hostRoom, src)
        Rooms.delete(hostRoomId)
        Logger.info("SRV",
            ("Host %d desconectou. Sala %d destruída."):format(src, hostRoomId))
        return
    end

    local participantRoomId, participantRoom = Rooms.getByParticipant(src)
    if participantRoom then
        Rooms.removeParticipant(participantRoom, src)
        if participantRoom.state == Config.States.Room.LOBBY then
            broadcastLobby(participantRoom)
        end
        Logger.debug("SRV",
            ("Player %d saiu da sala %d"):format(src, participantRoomId))
    end
end)
