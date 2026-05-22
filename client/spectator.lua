-- ============================================================
--  OUTRUN — Client: Spectator
--
--  Câmera orbital ao redor do líder, ativada quando o jogador
--  é eliminado. Recebe BE_SPECTATOR do server.
-- ============================================================

Spectator = {}

local spectatorCam  = nil
local targetVehicle = nil
local orbitAngle    = 0.0
local orbitDist     = 6.0
local orbitHeight   = 2.5
local active        = false


function Spectator.Start(leaderVeh)
    if active then Spectator.Stop() end

    targetVehicle = leaderVeh
    active        = true

    FreezeEntityPosition(PlayerPedId(), true)
    SetEntityVisible(PlayerPedId(), false, false)

    spectatorCam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    SetCamActive(spectatorCam, true)
    RenderScriptCams(true, false, 0, true, true)

    Citizen.CreateThread(function()
        while active do
            if not DoesEntityExist(targetVehicle) then break end

            local center = GetEntityCoords(targetVehicle)
            local rightX = GetControlNormal(0, 220)
            orbitAngle = orbitAngle + rightX * 2.0

            local rad = math.rad(orbitAngle)
            SetCamCoord(spectatorCam,
                center.x + math.cos(rad) * orbitDist,
                center.y + math.sin(rad) * orbitDist,
                center.z + orbitHeight)
            PointCamAtEntity(spectatorCam, targetVehicle, 0.0, 0.0, 0.0, true)

            Citizen.Wait(0)
        end
        Spectator.Stop()
    end)
end

function Spectator.Stop()
    active = false
    if spectatorCam then
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(spectatorCam, false)
        spectatorCam = nil
    end
    FreezeEntityPosition(PlayerPedId(), false)
    SetEntityVisible(PlayerPedId(), true, false)
    targetVehicle = nil
end

function Spectator.SetTarget(veh)
    targetVehicle = veh
end


RegisterNetEvent(Config.Events.Client.BE_SPECTATOR, function(leaderId)
    RaceState.eliminated = true

    local leaderVeh = RaceState.leaderVeh
    for _, p in ipairs(RaceState.participants) do
        if tostring(p.id) == tostring(leaderId) then
            local v = p.vehicle
            -- Em MP o vehicle pode ainda não estar resolvido; tenta via netId
            if (not v or not DoesEntityExist(v)) and p.netId then
                v = NetToVeh(p.netId)
            end
            if v and DoesEntityExist(v) then
                leaderVeh = v
                p.vehicle = v
            end
            break
        end
    end

    if leaderVeh and DoesEntityExist(leaderVeh) then
        Spectator.Start(leaderVeh)
    end
end)
