-- ============================================================
--  OUTRUN — Server: Amphibious (re-broadcast de netId no swap)
--
--  Feature ISOLADA. Quando um player troca o carro pelo jetski (ou vice-versa)
--  via client/amphibious.lua, ele manda o novo netId. O server atualiza o
--  registro da sala e rebroadcasta para todos os humanos da sala, para que
--  cada client re-resolva o veículo daquele participante (blips, spectator,
--  topChasers). A pontuação/standings é por `source` no server e NÃO depende
--  do netId, então este handler não interfere na lógica de corrida.
-- ============================================================

local Events = Config.Events

RegisterNetEvent(Events.Server.UPDATE_VEHICLE_NETID, function(netId)
    local src = source
    if type(netId) ~= "number" then return end

    local _, room = Rooms.getByParticipant(src)
    if not room or room.state ~= Config.States.Room.RACING then return end

    -- atualiza o registro da sala (mantém buildNetIdMap consistente)
    Rooms.setNetId(room, src, netId)

    -- rebroadcast para todos os humanos da sala (inclusive o próprio src,
    -- inofensivo: o client só atualiza participants[src])
    for _, p in ipairs(room.participants) do
        if not p.isNPC and p.source then
            TriggerClientEvent(Events.Client.VEHICLE_NETID_CHANGED, p.source, src, netId)
        end
    end

    Logger.debug("AMPHIB", ("player %d trocou de veiculo (netId=%d)"):format(src, netId))
end)
