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

function Lobby.close()
    Nui.setFocus(false)
    Nui.send('hideLobby', {})
end

function Lobby.setTraffic(data)
    trafficEnabled = data.on == true
end


-- ============================================================
-- Comando
-- ============================================================

RegisterCommand('outrun', function()
    if hasActiveLobby then
        TriggerServerEvent(SE.REQUEST_LOBBY_STATE)
    else
        Nui.setFocus(true)
        Nui.send('openLobby', { hasLobby = false })
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
    Nui.send('openLobby', { hasLobby = false })
end)

RegisterNetEvent(CE.LOBBY_UPDATED, function(room)
    Nui.send('lobbyUpdated', { room = room })
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

    Nui.setFocus(true)
    Nui.send('endScreen', { champion = champion, scores = scores, names = names })
end)

RegisterNetEvent(CE.NOTIFY, function(msg)
    notify(msg)
end)

RegisterNetEvent(CE.FORCE_LOBBY_CLOSE, function()
    hasActiveLobby = false
    RaceState.reset()
    Nui.setFocus(false)
    Nui.send('hideLobby', {})
    notify("A sala foi encerrada.")
end)

RegisterNetEvent(CE.SPAWN_VEHICLES, function(payload)
    Nui.setFocus(false)
    Nui.send('hideLobby', {})
    RaceOrchestrator.beginRound(payload)
end)


-- ============================================================
-- Inicialização
-- ============================================================

Nui.registerCallbacks()
