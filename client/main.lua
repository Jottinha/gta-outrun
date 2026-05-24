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

-- Resolve o vehicle handle de um participante, com fallback para netId em MP.
local function resolveParticipantVeh(p)
    if p.vehicle and DoesEntityExist(p.vehicle) then return p.vehicle end
    if p.netId then
        local v = NetToVeh(p.netId)
        if DoesEntityExist(v) then
            p.vehicle = v
            return v
        end
    end
    return nil
end


-- ============================================================
-- Lobby: ações disparadas pela UI
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
    TriggerServerEvent(SE.SET_CAR, data.model or Config.Vehicles.DEFAULT, data.plate or nil)
end

function Lobby.toggleReady()
    TriggerServerEvent(SE.TOGGLE_READY)
end

function Lobby.startRace()
    VehiclePreview.destroy()
    TriggerServerEvent(SE.START_RACE)
end

function Lobby.leave()
    VehiclePreview.destroy()
    if hasActiveLobby then
        TriggerServerEvent(SE.LEAVE_LOBBY)
        hasActiveLobby = false
    end
end

function Lobby.closeMenu()
    VehiclePreview.destroy()
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

function Lobby.refreshRooms()
    TriggerServerEvent(SE.REQUEST_ROOMS_LIST)
end

-- Entrar em sala alheia (multiplayer real)
function Lobby.joinRoom(data)
    TriggerServerEvent(SE.JOIN_ROOM, tonumber(data.roomId))
end

local garageVehiclesCache = {}

-- Vehicle preview 3D
function Lobby.previewVehicle(data)
    local model = data.model or Config.Vehicles.DEFAULT
    local plate = data.plate
    local mods = nil
    if plate and garageVehiclesCache then
        for _, gv in ipairs(garageVehiclesCache) do
            if gv.plate == plate then mods = gv.mods; break end
        end
    end
    if VehiclePreview.isActive() then
        VehiclePreview.switchModel(model, mods)
    else
        VehiclePreview.show(model, mods)
    end
end

function Lobby.destroyPreview()
    VehiclePreview.destroy()
end


-- ============================================================
-- Comando
-- ============================================================

local function buildVehicleConfig()
    local vehicles = {}
    if #garageVehiclesCache > 0 then
        -- Jogador tem garagem: mostra só os carros salvos
        for _, gv in ipairs(garageVehiclesCache) do
            vehicles[#vehicles + 1] = {
                model = gv.model,
                label = gv.label or gv.model,
                plate = gv.plate,
            }
        end
    else
        -- Sem garagem: fallback para lista fixa
        for _, model in ipairs(Config.Vehicles.SELECTABLE) do
            local display = Config.VehicleDisplay[model]
            vehicles[#vehicles + 1] = {
                model = model,
                label = display and display.label or model,
            }
        end
    end
    return {
        vehicles     = vehicles,
        defaultModel = vehicles[1] and vehicles[1].model or Config.Vehicles.DEFAULT,
        botsEnabled  = Config.Features.BotsEnabled,
    }
end

RegisterNetEvent('outrun:client:garageVehicles', function(vehicles)
    garageVehiclesCache = vehicles or {}
    if hasActiveLobby then
        Nui.send('updateVehicleConfig', { vehicleConfig = buildVehicleConfig() })
    end
end)

RegisterCommand('outrun', function()
    TriggerServerEvent('outrun:server:getGarageVehicles')
    Nui.setFocus(true)
    if hasActiveLobby then
        TriggerServerEvent(SE.REQUEST_LOBBY_STATE)
    else
        Nui.send('openMenu', {})
    end
end, false)

RegisterKeyMapping('outrun', 'Ativar/Desativar Outrun', 'keyboard', 'o')


-- ============================================================
-- Thread de tráfego
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

RegisterNetEvent(CE.LOBBY_CREATED, function(roomId, room, isHostOverride)
    hasActiveLobby = true
    RaceState.roomId = roomId
    local myId   = GetPlayerServerId(PlayerId())
    local isHost = (isHostOverride ~= nil) and isHostOverride or (room.host == myId)
    Nui.setFocus(true)
    Nui.send('lobbyCreated', {
        roomId = roomId, room = room, isHost = isHost, mySrc = myId,
        vehicleConfig = buildVehicleConfig(),
        trafficOn     = trafficEnabled,
    })
end)

RegisterNetEvent(CE.NO_ACTIVE_LOBBY, function()
    hasActiveLobby = false
    Nui.setFocus(true)
    Nui.send('openMenu', {})
end)

RegisterNetEvent(CE.LOBBY_UPDATED, function(room)
    local myId   = GetPlayerServerId(PlayerId())
    local isHost = (room.host == myId)
    Nui.send('lobbyUpdated', {
        room = room, isHost = isHost, mySrc = myId,
        vehicleConfig = buildVehicleConfig(),
    })
end)

RegisterNetEvent(CE.ROOMS_LIST, function(rooms)
    Nui.send('roomsList', { rooms = rooms or {} })
end)

RegisterNetEvent(CE.LEADER_CHANGED, function(leaderId)
    RaceState.leaderId = leaderId

    -- Resolver vehicle handle (local ou via netId em MP)
    local leaderVeh = nil
    for _, p in ipairs(RaceState.participants) do
        if tostring(p.id) == tostring(leaderId) then
            leaderVeh = resolveParticipantVeh(p)
            break
        end
    end
    RaceState.leaderVeh = leaderVeh

    if RaceState.eliminated and leaderVeh then
        Spectator.SetTarget(leaderVeh)
    end
end)

RegisterNetEvent(CE.CLEAR_WANTED, function()
    ClearPlayerWantedLevel(PlayerId())
    SetPoliceIgnorePlayer(PlayerId(), false)
end)

-- Lua tabelas com chaves numéricas sequenciais ({[1]=..., [2]=...}) são
-- serializadas como JSON ARRAY pelo SendNUIMessage. Isso destrói o
-- mapeamento id→valor (player id 2 vira índice 1 = wrong). Forçar chaves
-- string preserva o mapa original quando vira JSON object no JS.
local function stringKeys(t)
    if type(t) ~= 'table' then return t end
    local out = {}
    for k, v in pairs(t) do
        out[tostring(k)] = v
    end
    return out
end

RegisterNetEvent(CE.ROUND_RESULT, function(results, scores, names)
    Nui.send('roundResult', {
        results = results,
        scores  = stringKeys(scores),
        names   = stringKeys(names),
    })
end)

RegisterNetEvent(CE.SHOW_END_SCREEN, function(champion, scores, names)
    hasActiveLobby = false
    trafficEnabled = true

    RaceOrchestrator.endSession()
    RaceState.reset()
    LeaderBlip.clear()
    ChaserBlips.clear()

    Nui.setFocus(true)
    Nui.send('endScreen', {
        champion = tostring(champion),
        scores   = stringKeys(scores),
        names    = stringKeys(names),
    })
end)

RegisterNetEvent(CE.NOTIFY, function(msg)
    notify(msg)
end)

RegisterNetEvent(CE.FORCE_LOBBY_CLOSE, function()
    VehiclePreview.destroy()
    hasActiveLobby = false
    RaceState.reset()
    LeaderBlip.clear()
    ChaserBlips.clear()
    Nui.setFocus(false)
    Nui.send('hideMenus', {})
    notify("A sala foi encerrada.")
end)

-- Solo: host recebe lista completa de participants para spawnar tudo
RegisterNetEvent(CE.SPAWN_VEHICLES, function(payload)
    VehiclePreview.destroy()
    Nui.setFocus(false)
    Nui.send('hideMenus', {})
    RaceOrchestrator.beginRound(payload)
end)

-- Multiplayer: cada player spawna só o seu veículo
RegisterNetEvent(CE.SPAWN_MY_VEHICLE, function(payload)
    VehiclePreview.destroy()
    hasActiveLobby = true
    Nui.setFocus(false)
    Nui.send('hideMenus', {})
    RaceOrchestrator.beginRoundMP(payload)
end)

-- Multiplayer: todos spawnaram — recebe mapa de netIds para montar participants
RegisterNetEvent(CE.ALL_SPAWNED, function(netIdMap)
    RaceOrchestrator.onAllSpawned(netIdMap)
end)

-- Multiplayer: tick do countdown server-side
RegisterNetEvent(CE.COUNTDOWN_TICK, function(count)
    Nui.send('countdownTick', { count = count })
end)

-- Multiplayer: servidor diz GO
RegisterNetEvent(CE.RACE_START, function()
    RaceOrchestrator.onRaceStartMP()
end)

-- Multiplayer: standings calculados server-side pelo RaceServer
RegisterNetEvent(CE.STANDINGS_UPDATE, function(data)
    if RaceState.isMultiplayer then
        RaceOrchestrator.onStandingsUpdate(data)
    end
end)

-- Multiplayer: novo host após desconexão do anterior
RegisterNetEvent(CE.HOST_PROMOTED, function(newHostId)
    local myId = GetPlayerServerId(PlayerId())
    if newHostId == myId then
        RaceState.isHost = true
        Logger.info("MAIN", "Você se tornou o novo host da sala.")
    end
end)


-- ============================================================
-- Inicialização
-- ============================================================

Nui.registerCallbacks()
