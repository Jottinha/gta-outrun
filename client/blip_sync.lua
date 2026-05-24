-- ============================================================
--  OUTRUN — Client: BlipSync
--
--  Recebe CE.BLIP_UPDATE do servidor e distribui para
--  LeaderBlip e ChaserBlips.
--
--  Payload esperado (o servidor OMITE o próprio destinatário):
--    {
--      leader  = { x, y, z, heading } | false,
--      chasers = {
--        { slot = 1..3, x, y, z, heading },  -- slot 1=2°, 2=3°, 3=4°
--        ...
--      }
--    }
-- ============================================================

local CE = Config.Events.Client

RegisterNetEvent(CE.BLIP_UPDATE, function(data)
    -- ── Líder ───────────────────────────────────────────────
    if data.leader then
        LeaderBlip.updatePosition(
            data.leader.x, data.leader.y,
            data.leader.z, data.leader.heading
        )
    else
        LeaderBlip.clear()
    end

    -- ── Chasers ─────────────────────────────────────────────
    local active = {}
    for _, c in ipairs(data.chasers) do
        active[c.slot] = true
        ChaserBlips.updatePosition(c.slot, c.x, c.y, c.z, c.heading)
    end
    -- Remove slots ausentes no payload (eliminado / desconectado)
    for i = 1, 3 do
        if not active[i] then
            ChaserBlips.removeSlot(i)
        end
    end
end)

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    LeaderBlip.clear()
    ChaserBlips.clear()
end)
