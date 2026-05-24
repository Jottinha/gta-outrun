-- ============================================================
--  OUTRUN — Client: ChaserBlips
--
--  Blips de coordenada para os perseguidores, visíveis a TODOS
--  os jogadores. Imune a culling (AddBlipForCoord, sem entidade).
--  Posições atualizadas via SetBlipCoords a cada CE.BLIP_UPDATE.
--
--  API pública:
--    ChaserBlips.updatePosition(slot, x, y, z, heading)
--    ChaserBlips.removeSlot(slot)
--    ChaserBlips.clear()
-- ============================================================

ChaserBlips = {}

local SLOT_CONFIG = {
    { colour = 3,  name = "2\xC2\xBA" },  -- azul
    { colour = 5,  name = "3\xC2\xBA" },  -- amarelo
    { colour = 17, name = "4\xC2\xBA" },  -- laranja
}

local MAX_CHASERS = #SLOT_CONFIG
local slots = {}  -- slots[i] = blip handle ou nil

local function createAt(slot, x, y, z)
    local cfg = SLOT_CONFIG[slot]
    local b = AddBlipForCoord(x, y, z)
    if b == 0 or not DoesBlipExist(b) then return nil end
    SetBlipSprite(b, 6)
    SetBlipColour(b, cfg.colour)
    SetBlipScale(b, 0.85)
    SetBlipDisplay(b, 2)
    SetBlipAsShortRange(b, false)
    SetBlipCategory(b, 2)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentSubstringPlayerName(cfg.name)
    EndTextCommandSetBlipName(b)
    return b
end

function ChaserBlips.updatePosition(slot, x, y, z, heading)
    if slot < 1 or slot > MAX_CHASERS then return end
    if not slots[slot] or not DoesBlipExist(slots[slot]) then
        slots[slot] = createAt(slot, x, y, z)
        if not slots[slot] then return end
    end
    SetBlipCoords(slots[slot], x, y, z)
    SetBlipRotation(slots[slot], math.ceil(heading))
end

function ChaserBlips.removeSlot(slot)
    if slots[slot] and DoesBlipExist(slots[slot]) then
        RemoveBlip(slots[slot])
    end
    slots[slot] = nil
end

function ChaserBlips.clear()
    for i = 1, MAX_CHASERS do
        ChaserBlips.removeSlot(i)
    end
end
