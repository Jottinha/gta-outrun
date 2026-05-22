-- ============================================================
--  OUTRUN — Client: Bootstrap
--
--  Wiring entre comandos, NUI callbacks e eventos de rede.
--  Toda lógica de gameplay vive em outros módulos.
-- ============================================================

local SE = Config.Events.Server
local CE = Config.Events.Client

local hasActiveLobby = false
local trafficEnabled = true


local function notify(msg)
    TriggerEvent('QBCore:Notify', msg, 'primary')
end


-- ============================================================
-- Lobby: ações disparadas pela UI
-- (Lobby foi pré-declarado em nui_bridge.lua)
-- ============================================================

-- "Criar Corrida" no main-menu: cria a sala no server.
function Lobby.create(data)
    TriggerServerEvent(SE.CREATE_LOBBY, tonumber(data.pointTarget) or Config.DefaultPointTarget)
end

function Lobby.addNPC(data)
    TriggerServerEvent(SE.ADD_NPC,
        data.model       or Config.Vehicles.DEFAULT,
        data.personality or "balanced")
end

function Lobby.setMyCar(data)
    TriggerServerEvent(SE.SET_CAR, data.model or Config.Vehicles.DEFAULT)
end

function Lobby.toggleReady()
    TriggerServerEvent(SE.TOGGLE_READY)
end

function Lobby.startRace()
    TriggerServerEvent(SE.START_RACE)
end

-- "Voltar" no lobby: cancela a sala no server (se host) ou sai (se participante)
-- e volta para o main-menu. NÃO fecha a NUI.
function Lobby.leave()
    if hasActiveLobby then
        TriggerServerEvent(SE.LEAVE_LOBBY)
        hasActiveLobby = false
    end
end

-- "X" / FECHAR: encerra a NUI inteiramente.
function Lobby.closeMenu()
    if hasActiveLobby then
        TriggerServerEvent(SE.LEAVE_LOBBY)
        hasActiveLobby = false
    end
    Nui.setFocus(false)
    Nui.send('hideMenus', {})
end

function Lobby.setTraffic(data)
    trafficEnabled = data.on == true
end

-- "Entrar em Corrida": pede a lista de salas ao server. Resposta vem em
-- CE.ROOMS_LIST e é repassada à NUI como `roomsList`.
function Lobby.refreshRooms()
    TriggerServerEvent(SE.REQUEST_ROOMS_LIST)
end

-- Tentativa de entrar em sala alheia. Hoje o server ainda não tem a lógica
-- de "addParticipant", então registramos a intenção e avisamos o jogador.
-- Quando o multiplayer entrar, basta substituir esta função por um
-- TriggerServerEvent específico (ex.: SE.JOIN_ROOM).
function Lobby.joinRoom(data)
    notify(("Multiplayer ainda não implementado — sala #%s será habilitada quando o recurso entrar."):format(
        tostring(data.roomId or "?")))
end


-- ============================================================
-- Comando
-- ============================================================

RegisterCommand('outrun', function()
    Nui.setFocus(true)
    if hasActiveLobby then
        -- Já participa de uma sala: tenta restaurar o estado pelo server.
        -- Server responde com LOBBY_CREATED (mostra lobby) ou NO_ACTIVE_LOBBY (volta main).
        TriggerServerEvent(SE.REQUEST_LOBBY_STATE)
    else
        Nui.send('openMenu', {})
    end
end, false)


-- ============================================================
-- Thread de tráfego (suprime tráfego/peds quando desativado)
-- ============================================================

Citizen.CreateThread(function()
    while true do
        if not trafficEnabled then
            SetVehicleDensityMultiplierThisFrame(0.0)
            SetRandomVehicleDensityMultiplierThisFrame(0.0)
            SetParkedVehicleDensityMultiplierThisFrame(0.0)
            SetPedDensityMultiplierThisFrame(0.0)
            SetScenarioPedDensityMultiplierThisFrame(0.0, 0.0)
        end
        Citizen.Wait(0)
    end
end)


-- ============================================================
-- Handlers de eventos do server
-- ============================================================

RegisterNetEvent(CE.LOBBY_CREATED, function(roomId, room)
    hasActiveLobby = true
    RaceState.roomId = roomId
    Nui.setFocus(true)
    Nui.send('lobbyCreated', { roomId = roomId, room = room })
end)

RegisterNetEvent(CE.NO_ACTIVE_LOBBY, function()
    hasActiveLobby = false
    Nui.setFocus(true)
    Nui.send('openMenu', {})
end)

RegisterNetEvent(CE.LOBBY_UPDATED, function(room)
    Nui.send('lobbyUpdated', { room = room })
end)

RegisterNetEvent(CE.ROOMS_LIST, function(rooms)
    Nui.send('roomsList', { rooms = rooms or {} })
end)

RegisterNetEvent(CE.LEADER_CHANGED, function(leaderId)
    RaceState.leaderId = leaderId
    for _, p in ipairs(RaceState.participants) do
        if p.id == leaderId then
            RaceState.leaderVeh = p.vehicle
            break
        end
    end
    if RaceState.eliminated and RaceState.leaderVeh then
        Spectator.SetTarget(RaceState.leaderVeh)
    end

    -- Marca o líder no minimap dos OUTROS jogadores (com rota GPS).
    -- Se o player local É o líder, limpa o blip (não faz sentido marcar a si mesmo).
    local myId = GetPlayerServerId(PlayerId())
    if leaderId == myId then
        LeaderBlip.clear()
    else
        LeaderBlip.setTarget(RaceState.leaderVeh)
    end
end)

RegisterNetEvent(CE.CLEAR_WANTED, function()
    ClearPlayerWantedLevel(PlayerId())
    SetPoliceIgnorePlayer(PlayerId(), false)
end)

RegisterNetEvent(CE.ROUND_RESULT, function(results, scores, names)
    Nui.send('roundResult', { results = results, scores = scores, names = names })
end)

RegisterNetEvent(CE.SHOW_END_SCREEN, function(champion, scores, names)
    hasActiveLobby = false
    trafficEnabled = true

    RaceOrchestrator.endSession()
    RaceState.reset()
    LeaderBlip.clear()

    Nui.setFocus(true)
    Nui.send('endScreen', { champion = champion, scores = scores, names = names })
end)

RegisterNetEvent(CE.NOTIFY, function(msg)
    notify(msg)
end)

RegisterNetEvent(CE.FORCE_LOBBY_CLOSE, function()
    hasActiveLobby = false
    RaceState.reset()
    LeaderBlip.clear()
    Nui.setFocus(false)
    Nui.send('hideMenus', {})
    notify("A sala foi encerrada.")
end)

RegisterNetEvent(CE.SPAWN_VEHICLES, function(payload)
    Nui.setFocus(false)
    Nui.send('hideMenus', {})
    RaceOrchestrator.beginRound(payload)
end)


-- ============================================================
-- Inicialização
-- ============================================================

Nui.registerCallbacks()
