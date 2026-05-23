-- ============================================================
--  OUTRUN — Client: LeaderBlip
--
--  Marca o veículo do LÍDER no minimap dos outros jogadores, com
--  uma ROTA GPS traçada (mesma linha do waypoint normal do GTA).
--  Acompanha automaticamente o líder porque o blip é vinculado à
--  entidade.
--
--  Acoplamento:
--    * Módulo isolado — só recebe um `vehicle handle` em setTarget.
--    * Não sabe se é singleplayer ou multiplayer. No MP, cada cliente
--      recebe LEADER_CHANGED do server, resolve o vehicle local e
--      chama `LeaderBlip.setTarget(vehicleHandle)`.
--    * Em singleplayer (atual), o orchestrator/main.lua chamam o setTarget
--      sempre que `RaceState.leaderVeh` muda.
-- ============================================================

LeaderBlip = {}

local config = {
    -- Aparência do blip
    sprite       = 225,    -- carro genérico (visível, distinto do default)
    colour       = 1,      -- vermelho (objetivo/perseguição)
    scale        = 1.0,
    name         = "Líder",
    -- Rota GPS (linha tracejada no minimap)
    routeColour  = 1,      -- mesma cor do blip
    showAsRoute  = true,
    -- Display: 2 = minimap + mapa grande; 3 = só mapa grande; 8 = só minimap
    displayMode  = 2,
}

local currentBlip    = nil
local currentVehicle = nil


-- ------------------------------------------------------------
-- Helpers internos
-- ------------------------------------------------------------

local function destroyBlip()
    if currentBlip and DoesBlipExist(currentBlip) then
        if config.showAsRoute then
            SetBlipRoute(currentBlip, false)
        end
        RemoveBlip(currentBlip)
    end
    currentBlip    = nil
    currentVehicle = nil
end

local function applyBlipStyle(blip)
    SetBlipSprite(blip, config.sprite)
    SetBlipColour(blip, config.colour)
    SetBlipScale(blip, config.scale)
    SetBlipDisplay(blip, config.displayMode)
    SetBlipAsShortRange(blip, false)
    SetBlipCategory(blip, 2)  -- categoria genérica
    -- Nome no minimap
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentSubstringPlayerName(config.name)
    EndTextCommandSetBlipName(blip)

    if config.showAsRoute then
        SetBlipRoute(blip, true)
        SetBlipRouteColour(blip, config.routeColour)
    end
end


-- ------------------------------------------------------------
-- API pública
-- ------------------------------------------------------------

-- Marca um veículo como líder. Se `vehicle` for nil/0/inválido, limpa o blip.
-- Se já estava marcando outro veículo, troca para o novo (remove o antigo).
function LeaderBlip.setTarget(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        destroyBlip()
        return
    end

    if currentVehicle == vehicle and currentBlip and DoesBlipExist(currentBlip) then
        return  -- idempotente: mesmo alvo, nada a fazer
    end

    destroyBlip()

    local blip = AddBlipForEntity(vehicle)
    if blip == 0 or not DoesBlipExist(blip) then
        Logger.warn("blip", "AddBlipForEntity falhou para o líder")
        return
    end

    applyBlipStyle(blip)
    currentBlip    = blip
    currentVehicle = vehicle
end

-- Remove o blip atual. Idempotente.
function LeaderBlip.clear()
    destroyBlip()
end

-- Util para outros módulos saberem se há blip ativo.
function LeaderBlip.hasTarget()
    return currentBlip ~= nil and DoesBlipExist(currentBlip)
end

