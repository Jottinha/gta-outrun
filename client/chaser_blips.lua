-- ============================================================
--  OUTRUN — Client: ChaserBlips
--
--  Marca os perseguidores no minimap DO LÍDER.
--  O líder vê onde estão os chasers; eles já veem o líder via LeaderBlip.
--  Cada posição tem cor diferente para fácil leitura.
--
--  API:
--    ChaserBlips.update(chasers) — chasers = array de vehicle handles
--                                  ordenados por posição (2º primeiro)
--    ChaserBlips.clear()         — remove todos os blips
-- ============================================================

ChaserBlips = {}

-- Configuração por slot (índice = posição no ranking de chasers, a partir do 2º)
local SLOT_CONFIG = {
    { colour = 3,  name = "2\xC2\xBA" },  -- azul
    { colour = 5,  name = "3\xC2\xBA" },  -- amarelo
    { colour = 17, name = "4\xC2\xBA" },  -- laranja
}

local MAX_CHASERS = #SLOT_CONFIG
local blips = {}


-- ------------------------------------------------------------
-- Helpers internos
-- ------------------------------------------------------------

local function destroyAll()
    for _, blip in ipairs(blips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    blips = {}
end

local function makeBlip(vehicle, slot)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return nil end
    local cfg  = SLOT_CONFIG[slot]
    local blip = AddBlipForEntity(vehicle)
    if blip == 0 or not DoesBlipExist(blip) then return nil end

    SetBlipSprite(blip, 225)
    SetBlipColour(blip, cfg.colour)
    SetBlipScale(blip, 0.85)
    SetBlipDisplay(blip, 2)
    SetBlipAsShortRange(blip, false)
    SetBlipCategory(blip, 2)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentSubstringPlayerName(cfg.name)
    EndTextCommandSetBlipName(blip)

    return blip
end


-- ------------------------------------------------------------
-- API pública
-- ------------------------------------------------------------

function ChaserBlips.update(chasers)
    destroyAll()
    for i = 1, math.min(#chasers, MAX_CHASERS) do
        local blip = makeBlip(chasers[i], i)
        if blip then blips[#blips + 1] = blip end
    end
end

function ChaserBlips.clear()
    destroyAll()
end
