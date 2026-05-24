-- ============================================================
--  OUTRUN — Client: LeaderBlip
--
--  Blip de coordenada para o líder, visível a TODOS os jogadores.
--  Imune a culling de entidade (>400m) porque usa AddBlipForCoord.
--  Posição atualizada via SetBlipCoords a cada CE.BLIP_UPDATE do servidor.
--
--  API pública:
--    LeaderBlip.updatePosition(x, y, z, heading)
--    LeaderBlip.clear()
--    LeaderBlip.hasTarget()
-- ============================================================

LeaderBlip = {}

local CFG = {
    sprite      = 6,
    colour      = 1,      -- vermelho
    scale       = 1.0,
    name        = "Líder",
    routeColour = 1,
    showAsRoute = true,
    displayMode = 2,      -- minimap + mapa grande
}

local blip = nil

local function applyStyle(b)
    SetBlipSprite(b, CFG.sprite)
    SetBlipColour(b, CFG.colour)
    SetBlipScale(b, CFG.scale)
    SetBlipDisplay(b, CFG.displayMode)
    SetBlipAsShortRange(b, false)
    SetBlipCategory(b, 2)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentSubstringPlayerName(CFG.name)
    EndTextCommandSetBlipName(b)
    if CFG.showAsRoute then
        SetBlipRoute(b, true)
        SetBlipRouteColour(b, CFG.routeColour)
    end
end

local function createAt(x, y, z)
    local b = AddBlipForCoord(x, y, z)
    if b == 0 or not DoesBlipExist(b) then
        Logger.warn("blip", "AddBlipForCoord falhou para o líder")
        return false
    end
    applyStyle(b)
    blip = b
    return true
end

function LeaderBlip.updatePosition(x, y, z, heading)
    if not blip or not DoesBlipExist(blip) then
        if not createAt(x, y, z) then return end
    end
    SetBlipCoords(blip, x, y, z)
    SetBlipRotation(blip, math.ceil(heading))
end

function LeaderBlip.clear()
    if blip and DoesBlipExist(blip) then
        if CFG.showAsRoute then SetBlipRoute(blip, false) end
        RemoveBlip(blip)
    end
    blip = nil
end

function LeaderBlip.hasTarget()
    return blip ~= nil and DoesBlipExist(blip)
end
