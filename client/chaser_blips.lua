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
    for _, b in ipairs(blips) do
        -- Adicionado o ".id" para pegar apenas o número do blip salvo na tabela
        if DoesBlipExist(b.id) then RemoveBlip(b.id) end
    end
    blips = {}
end

local function makeBlip(vehicle, slot)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return nil end
    local cfg  = SLOT_CONFIG[slot]
    local blip = AddBlipForEntity(vehicle)
    if blip == 0 or not DoesBlipExist(blip) then return nil end

    SetBlipSprite(blip, 6)
    SetBlipColour(blip, cfg.colour)
    SetBlipScale(blip, 0.85)
    SetBlipDisplay(blip, 2)
    SetBlipAsShortRange(blip, false)
    SetBlipCategory(blip, 2)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentSubstringPlayerName(cfg.name)
    EndTextCommandSetBlipName(blip)

    SetBlipRotation(blip, math.ceil(GetEntityHeading(vehicle)))
    return blip
end


-- ------------------------------------------------------------
-- API pública
-- ------------------------------------------------------------

function ChaserBlips.update(chasers)
    destroyAll()
    for i = 1, math.min(#chasers, MAX_CHASERS) do
        local veh = chasers[i]
        local blip = makeBlip(veh, i)
        if blip then 
            -- Salva tanto o ID do blip quanto a entidade do veículo
            blips[#blips + 1] = { id = blip, vehicle = veh } 
        end
    end
end

function ChaserBlips.clear()
    destroyAll()
end

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(50) -- Intervalo curto para a rotação ser suave no minimapa

        if #blips > 0 then
            for _, b in ipairs(blips) do
                -- Garante que o carro e o blip ainda existem antes de atualizar
                if DoesEntityExist(b.vehicle) and DoesBlipExist(b.id) then
                    local heading = GetEntityHeading(b.vehicle)
                    SetBlipRotation(b.id, math.ceil(heading))
                end
            end
        else
            -- Se a lista estiver vazia, estende o Wait para poupar processamento
            Citizen.Wait(500)
        end
    end
end)
