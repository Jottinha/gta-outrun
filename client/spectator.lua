-- ============================================================
--  OUTRUN — Spectator
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

            local rad  = math.rad(orbitAngle)
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

RegisterNetEvent('outrun:client:BeSpectator', function(leaderId)
    RaceState.eliminated = true

    local leaderVeh = RaceState.leaderVeh
    for _, p in ipairs(RaceState.participants) do
        if tostring(p.id) == tostring(leaderId) then
            if p.vehicle and DoesEntityExist(p.vehicle) then
                leaderVeh = p.vehicle
            end
            break
        end
    end

    if leaderVeh and DoesEntityExist(leaderVeh) then
        Spectator.Start(leaderVeh)
    end
end)
