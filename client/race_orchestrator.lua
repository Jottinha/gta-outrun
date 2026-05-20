-- ============================================================
--  OUTRUN — Client: RaceOrchestrator
--
--  Coordena o ciclo de vida de uma rodada no client:
--    1. Spawn (delegado para Spawn.run)
--    2. Countdown
--    3. Largada (libera grid, inicia loops)
--    4. Tick (callback do RaceLogic.StartLoop)
--    5. Encerramento e cleanup
-- ============================================================

RaceOrchestrator = {}

local SE = Config.Events.Server
local CE = Config.Events.Client

local spawnedVehicles = {}
local roundEnded      = false


-- ===== Acessors usados pelos loops =====

local function getLeaderVeh()    return RaceState.leaderVeh    end
local function getRunnerUpVeh()  return RaceState.runnerUpVeh  end
local function getParticipants() return RaceState.participants end


-- ============================================================
-- Bonus Round: efeitos visíveis no client
-- ============================================================

local function applyBonusRound(bonus)
    if not bonus or not bonus.active then return end

    local myId = GetPlayerServerId(PlayerId())
    if bonus.targetSrc == myId then
        SetPlayerWantedLevel(PlayerId(), Config.BonusRound.WANTED_LEVEL, false)
        SetPlayerWantedLevelNow(PlayerId(), false)
    elseif Config.BonusRound.POLICE_IGNORE_OTHERS then
        SetPoliceIgnorePlayer(PlayerId(), true)
    end
end


-- ============================================================
-- Countdown
-- ============================================================

local function runCountdown(bonus, onFinish)
    Nui.send('showCountdown', { isBonusRound = bonus and bonus.active or false })

    Citizen.CreateThread(function()
        for i = Config.Race.COUNTDOWN_SECONDS, 1, -1 do
            Nui.send('countdownTick', { count = i })
            Citizen.Wait(1000)
        end
        Nui.send('countdownGo', {})
        onFinish()
    end)
end


-- ============================================================
-- Largada
-- ============================================================

local function launch(bonus)
    roundEnded = false
    RaceState.eliminated       = false
    RaceState.eliminationOrder = {}

    for _, veh in ipairs(spawnedVehicles) do
        FreezeEntityPosition(veh, false)
        SetVehicleEngineOn(veh, true, true, false)
    end

    applyBonusRound(bonus)
    TriggerServerEvent(SE.RACE_STARTED)

    RaceState.active = true
    Nui.send('showHUD', {})

    AIController.ReleaseGrid()
    if RaceState.isHost then
        AIController.StartLoop(getLeaderVeh, getRunnerUpVeh)
    end
    RaceLogic.StartLoop(getParticipants, getLeaderVeh, RaceOrchestrator.onTick)
end


-- ============================================================
-- Tick: chamado pelo RaceLogic.StartLoop
-- ============================================================

local function broadcastLeaderChange(topId, snapshot)
    RaceState.leaderId  = topId
    RaceState.leaderVeh = snapshot.leaderVeh or (snapshot.standings[1] and snapshot.standings[1].vehicle)
    if RaceState.isHost then
        TriggerServerEvent(SE.UPDATE_LEADER, topId)
    end
    Nui.send('leaderChanged', { leaderId = topId })
end

local function updateLocalHUD(standings)
    local myId   = GetPlayerServerId(PlayerId())
    local myDist = 0.0
    local myPos  = 1
    local foundMe = false

    for pos, entry in ipairs(standings) do
        if entry.id == myId then
            myDist  = entry.dist
            myPos   = pos
            foundMe = true
            break
        end
    end

    if not foundMe or RaceState.eliminated then return end

    local isLeader  = (myId == RaceState.leaderId)
    local distTo2nd = standings[2] and standings[2].dist or 0.0

    Nui.send('updateHUD', {
        isLeader = isLeader,
        dist     = isLeader and distTo2nd or myDist,
        maxDist  = Config.Race.WIN_DISTANCE,
        position = myPos,
        total    = #standings,
    })
end

local function processEliminations(standings)
    for index = #standings, 1, -1 do
        local entry = standings[index]
        if entry.dist >= Config.Race.ELIMINATION_DISTANCE
        and entry.id ~= RaceState.leaderId then
            local marked = RaceState.markEliminated(entry.id)
            if marked then
                if entry.isNPC then
                    AIController.SetState(entry.id, Config.States.AI.ELIMINATED)
                else
                    TriggerServerEvent(CE.PLAYER_ELIMINATED, entry.id)
                end
            end
        end
    end
end

local function endRound(standings)
    RaceState.active = false
    roundEnded = true
    local results = RaceState.buildRoundResults(standings)
    TriggerServerEvent(SE.ROUND_END, results)
end

function RaceOrchestrator.onTick(snapshot)
    local standings = snapshot.standings
    if #standings == 0 then return end

    local topId = snapshot.leaderId or standings[1].id
    if topId ~= RaceState.leaderId or snapshot.leaderVeh ~= RaceState.leaderVeh then
        broadcastLeaderChange(topId, snapshot)
    end

    RaceState.runnerUpId  = snapshot.runnerUp and snapshot.runnerUp.id      or nil
    RaceState.runnerUpVeh = snapshot.runnerUp and snapshot.runnerUp.vehicle or nil

    updateLocalHUD(standings)

    if not RaceState.isHost or roundEnded then return end

    processEliminations(standings)

    -- Recalcula standings depois das eliminações para decidir vitória
    local resolved = RaceLogic.GetRaceSnapshot(getParticipants(), RaceState.leaderVeh)
    local resolvedStandings = resolved.standings

    local winConditionMet =
        (#resolvedStandings >= 2 and resolvedStandings[2].dist >= Config.Race.WIN_DISTANCE)
        or (#resolvedStandings == 1)

    if winConditionMet then
        endRound(resolvedStandings)
    end
end


-- ============================================================
-- Pontos de entrada
-- ============================================================

function RaceOrchestrator.beginRound(payload)
    -- Cleanup de uma rodada anterior dentro do mesmo lobby
    RaceOrchestrator.cleanupVehicles()

    AIController.UnregisterAll()
    RaceState.participants     = {}
    RaceState.eliminationOrder = {}
    RaceState.eliminated       = false
    RaceState.runnerUpId       = nil
    RaceState.runnerUpVeh      = nil
    Spectator.Stop()

    spawnedVehicles = Spawn.run(payload)

    runCountdown(payload.bonusRound, function() launch(payload.bonusRound) end)
end

function RaceOrchestrator.cleanupVehicles()
    for _, veh in ipairs(spawnedVehicles) do
        if DoesEntityExist(veh) then DeleteVehicle(veh) end
    end
    spawnedVehicles = {}
end

function RaceOrchestrator.endSession()
    RaceState.active = false
    roundEnded = true

    AIController.UnregisterAll()
    Spectator.Stop()

    Citizen.CreateThread(function()
        Citizen.Wait(300)
        RaceOrchestrator.cleanupVehicles()
    end)
end
