-- ============================================================
--  FERRAMENTA TEMPORÁRIA — captura de pontos de largada (vector4)
--
--  Remover este arquivo (e a entrada no fxmanifest) depois de
--  preencher Config.SpawnNodes.
--
--  Uso:
--    1) Dirija até uma rua LARGA, RETA e PLANA.
--    2) Pare no ponto da POLE, de FRENTE para a direção em que os
--       carros vão acelerar (o grid se monta para trás daqui).
--    3) /spawnpoint  -> imprime o vector4 no F8 + diagnóstico da rua.
--    4) Cole os vector4 aqui pra mim.
-- ============================================================

-- Mede a distância 2D até o nó de via mais próximo (só diagnóstico — o spawn
-- não usa mais o nó, mas ajuda a saber se você está sobre a pista).
local function nearestNode(x, y, z)
    local found, pos, head = GetClosestVehicleNodeWithHeading(x, y, z, 1, 3, 0)
    if found and type(pos) == "vector3" then
        local dist = #(vector3(x, y, 0.0) - vector3(pos.x, pos.y, 0.0))
        return dist, head
    end
    return nil, nil
end

RegisterCommand('spawnpoint', function()
    local ped = PlayerPedId()
    local c   = GetEntityCoords(ped)
    local h   = GetEntityHeading(ped)
    local v   = ('vector4(%.2f, %.2f, %.2f, %.1f)'):format(c.x, c.y, c.z, h)

    local dist, nodeHead = nearestNode(c.x, c.y, c.z)
    local diag
    if not dist then
        diag = "sem nó de via por perto (provavelmente FORA da pista)"
    elseif dist <= 4.0 then
        diag = ("OK — sobre a via (nó a %.1fm, heading da rua %.0f°)"):format(dist, nodeHead or 0)
    else
        diag = ("ATENÇÃO — nó a %.1fm; pode estar fora da rua"):format(dist)
    end

    print("[outrun][spawnpoint] " .. v .. "   [" .. diag .. "]")
    TriggerEvent('QBCore:Notify', v .. "  —  " .. diag, 'primary', 9000)
end, false)

RegisterKeyMapping('spawnpoint', 'Capturar ponto de largada (Outrun dev)', 'keyboard', 'j')
