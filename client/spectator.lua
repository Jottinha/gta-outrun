Spectator = {}

local spectatorCam  = nil
local targetVehicle = nil
local orbitAngle    = 0.0
local orbitDist     = 6.0
local orbitHeight   = 2.5
local active        = false

function Spectator.Start(leaderVeh, leaderPed)
    if active then Spectator.Stop() end

    targetVehicle = leaderVeh
    active        = true

    FreezeEntityPosition(PlayerPedId(), true)
    SetEntityVisible(PlayerPedId(), false, false)

    -- Força o carregamento do mapa/texturas em volta do alvo
    SetFocusEntity(targetVehicle) 

    spectatorCam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    SetCamActive(spectatorCam, true)
    RenderScriptCams(true, false, 0, true, true)

    Citizen.CreateThread(function()
        while active do
            -- Se a entidade sumir temporariamente (culling), não quebramos o loop imediatamente.
            -- Apenas paramos de atualizar a câmera até ela voltar.
            if DoesEntityExist(targetVehicle) then
                local center = GetEntityCoords(targetVehicle)
                
                -- Controle 1 = INPUT_LOOK_LR (Funciona no Mouse e no Controle nativamente)
                local rightX = GetControlNormal(0, 1) 
                
                -- Multiplicador aumentado levemente para não ficar muito lento no mouse
                orbitAngle = orbitAngle + (rightX * 4.0) 

                local rad = math.rad(orbitAngle)
                SetCamCoord(spectatorCam,
                    center.x + math.cos(rad) * orbitDist,
                    center.y + math.sin(rad) * orbitDist,
                    center.z + orbitHeight)
                
                PointCamAtEntity(spectatorCam, targetVehicle, 0.0, 0.0, 0.0, true)
            end

            Citizen.Wait(0)
        end
    end)
end

function Spectator.Stop()
    active = false
    if spectatorCam then
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(spectatorCam, false)
        spectatorCam = nil
    end
    
    ClearFocus() -- Limpa o foco do mapa para voltar ao seu personagem
    NetworkSetInSpectatorMode(false, PlayerPedId()) -- Desliga o espectador nativo da rede
    
    FreezeEntityPosition(PlayerPedId(), false)
    SetEntityVisible(PlayerPedId(), true, false)
    targetVehicle = nil
end

RegisterNetEvent(Config.Events.Client.BE_SPECTATOR, function(leaderId)
    RaceState.eliminated = true

    local leaderVeh = nil
    local leaderPed = nil
    
    -- Pega o ID do jogador (client local) com base no ID do servidor
    local targetPlayer = GetPlayerFromServerId(leaderId)
    
    if targetPlayer ~= -1 then
        leaderPed = GetPlayerPed(targetPlayer)
        
        -- Isso é o que realmente faz a "mágica" de carregar o veículo
        -- se o jogador estiver muito longe de você.
        NetworkSetInSpectatorMode(true, leaderPed)
        
        -- Damos um pequeno delay para a engine puxar o veículo pela rede
        Citizen.Wait(500) 
        
        leaderVeh = GetVehiclePedIsIn(leaderPed, false)
    end

    -- Fallback se o nativo não encontrou, tenta buscar pela RaceState
    if not leaderVeh or not DoesEntityExist(leaderVeh) then
        for _, p in ipairs(RaceState.participants) do
            if tostring(p.id) == tostring(leaderId) then
                if p.netId then
                    leaderVeh = NetToVeh(p.netId)
                end
                break
            end
        end
    end

    if leaderVeh and DoesEntityExist(leaderVeh) then
        Spectator.Start(leaderVeh, leaderPed)
    else
        print("Erro: Veículo do líder não está streamado/não foi encontrado.")
    end
end)