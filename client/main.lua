-- ============================================================
--  OUTRUN — Client Main
-- ============================================================

RaceState = {
    active       = false,
    isHost       = false,
    roomId       = nil,
    leaderId     = nil,
    leaderVeh    = nil,
    runnerUpId   = nil,
    runnerUpVeh  = nil,
    myVehicle    = nil,
    participants = {},
    eliminationOrder = {},
    eliminated   = false,
}

local spawnedVehicles = {}
local hasActiveLobby  = false
local roundEnded      = false
local trafficEnabled  = true

-- Modelos de NPCs com aparência de "corredor" para variedade visual
local NPC_PED_MODELS = {
    "a_m_y_musclbeac_01",
    "a_m_m_business_01",
    "a_m_y_skater_01",
    "a_m_y_hipster_01",
    "a_m_y_genstreet_01",
    "a_m_y_eastsa_01",
}

-- Helper para carregar modelos com timeout. CreateVehicle/CreatePed
-- devolvem 0 silenciosamente se o modelo não estiver na memória.
local function loadModelHash(hash)
    if HasModelLoaded(hash) then return true end
    if not IsModelInCdimage(hash) then return false end
    RequestModel(hash)
    local elapsed = 0
    while not HasModelLoaded(hash) and elapsed < 5000 do
        Citizen.Wait(50)
        elapsed = elapsed + 50
    end
    return HasModelLoaded(hash)
end

local function notify(msg)
    TriggerEvent('QBCore:Notify', msg, 'primary')
end

local function sendNUI(action, data)
    SendNUIMessage({ action = action, data = data or {} })
end

local function getLeaderVeh()    return RaceState.leaderVeh    end
local function getRunnerUpVeh()  return RaceState.runnerUpVeh  end
local function getParticipants() return RaceState.participants end

local function findParticipantById(participantId)
    for index, participant in ipairs(RaceState.participants) do
        if tostring(participant.id) == tostring(participantId) then
            return participant, index
        end
    end

    return nil, nil
end

local function markParticipantEliminated(participantId)
    local participant = findParticipantById(participantId)
    if not participant or participant.eliminated then
        return false, participant
    end

    participant.eliminated = true
    RaceState.eliminationOrder[#RaceState.eliminationOrder + 1] = participant.id
    return true, participant
end

local function buildRoundResults(activeStandings)
    local results = {}
    local seen = {}

    for _, entry in ipairs(activeStandings) do
        results[#results + 1] = entry.id
        seen[entry.id] = true
    end

    for index = #RaceState.eliminationOrder, 1, -1 do
        local participantId = RaceState.eliminationOrder[index]
        if not seen[participantId] then
            results[#results + 1] = participantId
            seen[participantId] = true
        end
    end

    local formatted = {}
    for position, participantId in ipairs(results) do
        formatted[#formatted + 1] = {
            id = participantId,
            position = position,
        }
    end

    return formatted
end

local function getGridVectors(heading)
    local radians = math.rad(heading)
    local forwardX = math.sin(radians)
    local forwardY = math.cos(radians)
    local rightX = math.cos(radians)
    local rightY = -math.sin(radians)

    return forwardX, forwardY, rightX, rightY
end

local function getGridOffset(index, totalParticipants)
    local rowSpacing = Config.Race.GRID_ROW_SPACING
    local columnSpacing = Config.Race.GRID_COLUMN_SPACING
    local staggerSpacing = Config.Race.GRID_STAGGER_SPACING
    if totalParticipants <= 1 then
        return {
            longitudinal = 0.0,
            lateral = 0.0,
        }
    end

    local zeroBasedIndex = index - 1
    local columnIndex = zeroBasedIndex % 2
    local rowIndex = math.floor(zeroBasedIndex / 2)
    local laneSign = (columnIndex == 0) and -1.0 or 1.0
    local staggerOffset = (columnIndex == 0) and 0.0 or staggerSpacing

    return {
        longitudinal = -((rowIndex * rowSpacing) + staggerOffset),
        lateral = laneSign * (columnSpacing * 0.5),
    }
end

-- ============================================================
-- Thread de controle de tráfego
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
-- Comando /outrun
-- ============================================================

RegisterCommand('outrun', function()
    if hasActiveLobby then
        TriggerServerEvent(Config.Events.Server.REQUEST_LOBBY_STATE)
    else
        SetNuiFocus(true, true)
        sendNUI('openLobby', { hasLobby = false })
    end
end, false)

-- ============================================================
-- NUI Callbacks
-- ============================================================

RegisterNUICallback('createLobby', function(data, cb)
    TriggerServerEvent(Config.Events.Server.CREATE_LOBBY, tonumber(data.pointTarget) or 100)
    cb({ ok = true })
end)

RegisterNUICallback('addNPC', function(data, cb)
    TriggerServerEvent('outrun:server:AddNPC',
        data.model       or 'sultan',
        data.personality or 'balanced')
    cb({ ok = true })
end)

RegisterNUICallback('setMyCar', function(data, cb)
    TriggerServerEvent('outrun:server:SetCar', data.model or 'sultan')
    cb({ ok = true })
end)

RegisterNUICallback('toggleReady', function(_, cb)
    TriggerServerEvent(Config.Events.Server.TOGGLE_READY)
    cb({ ok = true })
end)

RegisterNUICallback('startRace', function(_, cb)
    TriggerServerEvent(Config.Events.Server.START_RACE)
    cb({ ok = true })
end)

RegisterNUICallback('closeLobby', function(_, cb)
    SetNuiFocus(false, false)
    sendNUI('hideLobby', {})
    cb({ ok = true })
end)

RegisterNUICallback('setTraffic', function(data, cb)
    trafficEnabled = data.on == true
    cb({ ok = true })
end)

-- ============================================================
-- Spawn e Grid
-- ============================================================

local function spawnParticipantVehicles(payload)
    local base  = payload.spawnBase
    local parts = payload.participants
    local bonus = payload.bonusRound or { active = false }

    RaceState.isHost       = true
    RaceState.roomId       = payload.roomId
    RaceState.participants = {}

    -- Native: BOOL success, Vector3 outPos, float outHeading
    local found, nodePos, nodeHead = GetClosestVehicleNodeWithHeading(
        base.x, base.y, base.z, 1, 3, 0)
    -- Defesas: alguns builds do FX devolvem tipos diferentes
    if not found or type(nodePos) ~= 'vector3' then nodePos = base end
    if type(nodeHead) ~= 'number' then nodeHead = 0.0 end
    print("[OUTRUN] spawn node @ " .. tostring(nodePos) .. " heading=" .. tostring(nodeHead))

    local forwardX, forwardY, rightX, rightY = getGridVectors(nodeHead)

    for i, p in ipairs(parts) do
        local offset = getGridOffset(i, #parts)
        local spawnX = nodePos.x
            + (forwardX * offset.longitudinal)
            + (rightX * offset.lateral)
        local spawnY = nodePos.y
            + (forwardY * offset.longitudinal)
            + (rightY * offset.lateral)
        local spawnZ = nodePos.z + 0.5

        -- Carrega o modelo do veículo
        local model     = p.model or "sultan"
        local modelHash = GetHashKey(model)
        if not loadModelHash(modelHash) then
            print("[OUTRUN] WARN: modelo de veículo nao carregou: " .. tostring(model) ..
                " — usando fallback 'sultan'")
            modelHash = GetHashKey("sultan")
            loadModelHash(modelHash)
        end

        local veh = CreateVehicle(modelHash, spawnX, spawnY, spawnZ, nodeHead, true, false)
        SetVehicleEngineOn(veh, false, true, false)
        FreezeEntityPosition(veh, true)
        SetEntityAsMissionEntity(veh, true, true)
        SetModelAsNoLongerNeeded(modelHash)

        if p.isNPC then
            -- BUG FIX: antes 'a_m_y_musclbeac_01' era usado sem RequestModel,
            -- então CreatePedInsideVehicle devolvia 0 (carro sem motorista).
            local pedModelName = NPC_PED_MODELS[((i - 1) % #NPC_PED_MODELS) + 1]
            local pedHash      = GetHashKey(pedModelName)
            if not loadModelHash(pedHash) then
                print("[OUTRUN] ERR: ped model nao carregou: " .. pedModelName)
            end

            local ped = CreatePedInsideVehicle(veh, 26, pedHash, -1, true, false)
            if not DoesEntityExist(ped) then
                print("[OUTRUN] ERR: CreatePedInsideVehicle devolveu 0 para id=" .. tostring(p.source))
            else
                SetEntityAsMissionEntity(ped, true, true)
                SetBlockingOfNonTemporaryEvents(ped, true)
                SetPedKeepTask(ped, true)
                SetPedCanBeDraggedOut(ped, false)
                SetDriverAbility(ped, 1.0)
                SetDriverAggressiveness(ped, 1.0)
                SetPedCanRagdollFromPlayerImpact(ped, false)
                print("[OUTRUN] NPC " .. tostring(p.source) ..
                    " spawned com ped=" .. tostring(ped) .. " veh=" .. tostring(veh))
            end
            SetModelAsNoLongerNeeded(pedHash)

            AIController.RegisterNPC(p.source, veh, ped, p.personality)
            RaceState.participants[#RaceState.participants + 1] =
                { id = p.source, vehicle = veh, isNPC = true, eliminated = false }
        else
            if p.source == GetPlayerServerId(PlayerId()) then
                TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)
                RaceState.myVehicle = veh
            end
            RaceState.participants[#RaceState.participants + 1] =
                { id = p.source, vehicle = veh, isNPC = false, eliminated = false }
        end

        spawnedVehicles[#spawnedVehicles + 1] = veh
    end

    RaceState.leaderVeh = spawnedVehicles[1]
    RaceState.leaderId  = parts[1] and parts[1].source

    startCountdown(bonus)
end

function startCountdown(bonus)
    sendNUI('showCountdown', { isBonusRound = bonus.active })

    Citizen.CreateThread(function()
        for i = Config.Race.COUNTDOWN_SECONDS, 1, -1 do
            sendNUI('countdownTick', { count = i })
            Citizen.Wait(1000)
        end
        sendNUI('countdownGo', {})
        launchRace(bonus)
    end)
end

function launchRace(bonus)
    roundEnded           = false
    RaceState.eliminated = false
    RaceState.eliminationOrder = {}

    for _, veh in ipairs(spawnedVehicles) do
        FreezeEntityPosition(veh, false)
        SetVehicleEngineOn(veh, true, true, false)
    end

    if bonus.active then
        local myId = GetPlayerServerId(PlayerId())
        if bonus.targetSrc == myId then
            SetPlayerWantedLevel(PlayerId(), Config.BonusRound.WANTED_LEVEL, false)
            SetPlayerWantedLevelNow(PlayerId(), false)
        elseif Config.BonusRound.POLICE_IGNORE_OTHERS then
            SetPoliceIgnorePlayer(PlayerId(), true)
        end
    end

    TriggerServerEvent(Config.Events.Server.RACE_STARTED)

    RaceState.active = true
    sendNUI('showHUD', {})

    AIController.ReleaseGrid()
    if RaceState.isHost then
        AIController.StartLoop(getLeaderVeh, getRunnerUpVeh)
    end
    RaceLogic.StartLoop(getParticipants, getLeaderVeh, onRaceTickResult)
end

-- ============================================================
-- Loop de corrida
-- ============================================================

function onRaceTickResult(snapshot)
    local standings = snapshot.standings
    if #standings == 0 then return end

    local topId = snapshot.leaderId or standings[1].id
    if topId ~= RaceState.leaderId or snapshot.leaderVeh ~= RaceState.leaderVeh then
        RaceState.leaderId  = topId
        RaceState.leaderVeh = snapshot.leaderVeh or standings[1].vehicle
        if RaceState.isHost then
            TriggerServerEvent(Config.Events.Server.UPDATE_LEADER, topId)
        end
        sendNUI('leaderChanged', { leaderId = topId })
    end

    RaceState.runnerUpId = snapshot.runnerUp and snapshot.runnerUp.id or nil
    RaceState.runnerUpVeh = snapshot.runnerUp and snapshot.runnerUp.vehicle or nil

    local myId   = GetPlayerServerId(PlayerId())
    local myDist = 0.0
    local myPos  = 1
    local foundMe = false

    for pos, entry in ipairs(standings) do
        if entry.id == myId then
            myDist = entry.dist
            myPos  = pos
            foundMe = true
            break
        end
    end

    local isLeader  = (myId == RaceState.leaderId)
    local distTo2nd = standings[2] and standings[2].dist or 0.0

    if foundMe and not RaceState.eliminated then
        sendNUI('updateHUD', {
            isLeader = isLeader,
            dist     = isLeader and distTo2nd or myDist,
            maxDist  = Config.Race.WIN_DISTANCE,
            position = myPos,
            total    = #standings,
        })
    end

    if RaceState.isHost and not roundEnded then
        for index = #standings, 1, -1 do
            local entry = standings[index]
            if entry.dist >= Config.Race.ELIMINATION_DISTANCE
            and entry.id ~= RaceState.leaderId then
                local marked, participant = markParticipantEliminated(entry.id)
                if marked and participant then
                    if entry.isNPC then
                        AIController.SetState(entry.id, Config.States.AI.ELIMINATED)
                    else
                        TriggerServerEvent(Config.Events.Client.PLAYER_ELIMINATED, entry.id)
                    end
                end
            end
        end

        local resolvedSnapshot = RaceLogic.GetRaceSnapshot(getParticipants(), RaceState.leaderVeh)
        local resolvedStandings = resolvedSnapshot.standings

        if #resolvedStandings >= 2 and resolvedStandings[2].dist >= Config.Race.WIN_DISTANCE then
            roundEnded = true
            endRound(resolvedStandings)
        elseif #resolvedStandings == 1 then
            roundEnded = true
            endRound(resolvedStandings)
        end
    end
end

function endRound(standings)
    RaceState.active = false
    local results = buildRoundResults(standings)
    -- O server envia RoundResult para todos os participantes com os pontos completos
    TriggerServerEvent(Config.Events.Server.ROUND_END, results)
end

-- ============================================================
-- Eventos do servidor
-- ============================================================

RegisterNetEvent('outrun:client:LobbyCreated', function(roomId, room)
    hasActiveLobby = true
    RaceState.roomId = roomId
    SetNuiFocus(true, true)
    sendNUI('lobbyCreated', { roomId = roomId, room = room })
end)

RegisterNetEvent(Config.Events.Client.NO_ACTIVE_LOBBY, function()
    hasActiveLobby = false
    SetNuiFocus(true, true)
    sendNUI('openLobby', { hasLobby = false })
end)

RegisterNetEvent('outrun:client:LobbyUpdated', function(room)
    sendNUI('lobbyUpdated', { room = room })
end)

RegisterNetEvent('outrun:client:LeaderChanged', function(leaderId)
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

RegisterNetEvent('outrun:client:ClearWanted', function()
    ClearPlayerWantedLevel(PlayerId())
    SetPoliceIgnorePlayer(PlayerId(), false)
end)

RegisterNetEvent('outrun:client:RoundResult', function(results, scores, names)
    sendNUI('roundResult', { results = results, scores = scores, names = names })
end)

RegisterNetEvent('outrun:client:ShowEndScreen', function(champion, scores, names)
    hasActiveLobby   = false
    RaceState.active = false
    trafficEnabled   = true
    roundEnded       = true

    -- Para os loops e limpa entidades da sessão encerrada
    AIController.UnregisterAll()
    Spectator.Stop()

    Citizen.CreateThread(function()
        Citizen.Wait(300) -- aguarda os loops pararem no próximo ciclo
        for _, veh in ipairs(spawnedVehicles) do
            if DoesEntityExist(veh) then DeleteVehicle(veh) end
        end
        spawnedVehicles = {}
    end)

    RaceState = {
        active = false, isHost = false, roomId = nil,
        leaderId = nil, leaderVeh = nil, runnerUpId = nil, runnerUpVeh = nil, myVehicle = nil,
        participants = {}, eliminationOrder = {}, eliminated = false,
    }

    SetNuiFocus(true, true)
    sendNUI('endScreen', { champion = champion, scores = scores, names = names })
end)

RegisterNetEvent('outrun:client:Notify', function(msg)
    notify(msg)
end)

RegisterNetEvent('outrun:client:ForceLobbyClose', function()
    hasActiveLobby = false
    RaceState = {
        active = false, isHost = false, roomId = nil,
        leaderId = nil, leaderVeh = nil, runnerUpId = nil, runnerUpVeh = nil, myVehicle = nil,
        participants = {}, eliminationOrder = {}, eliminated = false,
    }
    SetNuiFocus(false, false)
    sendNUI('hideLobby', {})
    notify("A sala foi encerrada.")
end)

RegisterNetEvent(Config.Events.Client.SPAWN_VEHICLES, function(payload)
    SetNuiFocus(false, false)
    sendNUI('hideLobby', {})

    for _, veh in ipairs(spawnedVehicles) do
        if DoesEntityExist(veh) then DeleteVehicle(veh) end
    end
    spawnedVehicles = {}

    AIController.UnregisterAll()
    RaceState.participants = {}
    RaceState.eliminationOrder = {}
    RaceState.eliminated   = false
    RaceState.runnerUpId   = nil
    RaceState.runnerUpVeh  = nil
    Spectator.Stop()

    spawnParticipantVehicles(payload)
end)
