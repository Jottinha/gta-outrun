-- ============================================================
--  OUTRUN — Server Events
--  'Rooms' é global (sem local) em server/main.lua
-- ============================================================

AddEventHandler('playerDropped', function(reason)
    local src = source

    for roomId, room in pairs(Rooms) do
        if room.host == src then
            for _, p in ipairs(room.participants) do
                if not p.isNPC and p.source ~= src then
                    TriggerClientEvent('outrun:client:Notify', p.source,
                        "O host abandonou a partida. A sala foi encerrada.")
                    TriggerClientEvent('outrun:client:ForceLobbyClose', p.source)
                end
            end
            Rooms[roomId] = nil
            if Config.Debug.ENABLED then
                print(Config.Debug.LOG_PREFIX .. " [SRV] Host " .. src ..
                    " desconectou. Sala " .. roomId .. " destruída.")
            end
            return
        end

        for i, p in ipairs(room.participants) do
            if not p.isNPC and p.source == src then
                table.remove(room.participants, i)
                room.scores[src] = nil
                TriggerClientEvent('outrun:client:LobbyUpdated', room.host, room)
                break
            end
        end
    end
end)
