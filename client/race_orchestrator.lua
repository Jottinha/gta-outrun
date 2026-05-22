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
local function getTopChasers()   return RaceState.topChasers   end
local function getLeaderId()     return RaceState.leaderId     end
local function getParticipants() return RaceState.participants end

-- Extrai dos standings os top-K perseguidores reais (não-líder e não-"ahead"),
-- já ordenados (mais próximo do líder primeiro). Usado pela IA do líder.
local function pickTopChasers(standings, maxChasers)
    local chasers = {}
    for _, entry in ipairs(standings) do
        if not entry.isLeader and not entry.ahead and entry.vehicle then
            chasers[#chasers + 1] = entry.vehicle
            if #chasers >= maxChasers then break end
        end
    end
    return chasers
end


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
        AIController.StartLoop(getLeaderVeh, getTopChasers)
    end
    RaceLogic.StartLoop(getParticipants, getLeaderId, RaceOrchestrator.onTick)
end


-- ============================================================
-- Tick: chamado pelo RaceLogic.StartLoop
-- ============================================================

local function broadcastLeaderChange(topId, standings)
    RaceState.leaderId  = topId
    RaceState.leaderVeh = standings[1] and standings[1].vehicle or nil
    if RaceState.isHost then
        TriggerServerEvent(SE.UPDATE_LEADER, topId)
    end
    Nui.send('leaderChanged', { leaderId = topId })
end

local function updateLocalHUD(standings, runnerUp)
    local myId   = GetPlayerServerId(PlayerId())
    local myEntry, myPos = nil, 1

    for pos, entry in ipairs(standings) do
        if entry.id == myId then
            myEntry = entry
            myPos   = pos
            break
        end
    end

    if not myEntry or RaceState.eliminated then return end

    local isLeader = (myId == RaceState.leaderId)
    -- Distância exibida no HUD/barra: 2D euclidiana, NÃO projeção longitudinal.
    -- A projeção oscila em curvas (mesma posição relativa, ângulo muda) e
    -- faz a barra encher/esvaziar visualmente sem motivo. A regra de jogo
    -- (eliminação, win) continua usando `longitudinal` no core; aqui no HUD
    -- queremos só a distância "no chão" que bate com o que o jogador vê.
    local riskDist
    if isLeader then
        riskDist = runnerUp and runnerUp.dist or nil
    else
        riskDist = myEntry.dist or 0
    end

    Nui.send('updateHUD', {
        isLeader = isLeader,
        dist     = riskDist,
        maxDist  = Config.Race.WIN_DISTANCE,
        position = myPos,
        total    = #standings,
    })
end

local function applyEliminations(eliminations)
    for _, entry in ipairs(eliminations) do
        local marked = RaceState.markEliminated(entry.id)
        if marked then
            if entry.isNPC then
                AIController.SetState(entry.id, Config.States.AI.ELIMINATED)
            else
                TriggerServerEvent(SE.PLAYER_ELIMINATED, entry.id)
            end
        end
    end
end

local function endRound(standings)
    RaceState.active = false
    roundEnded = true
    RaceLogic.StopLoop()
    AIController.StopLoop()
    local results = RaceState.buildRoundResults(standings)
    TriggerServerEvent(SE.ROUND_END, results)
end

function RaceOrchestrator.onTick(result)
    local standings = result.standings
    if #standings == 0 then return end

    local topId = result.leaderId
    if topId and (topId ~= RaceState.leaderId or
                  (standings[1] and standings[1].vehicle ~= RaceState.leaderVeh)) then
        broadcastLeaderChange(topId, standings)
    end

    RaceState.runnerUpId  = result.runnerUp and result.runnerUp.id      or nil
    RaceState.runnerUpVeh = result.runnerUp and result.runnerUp.vehicle or nil
    RaceState.topChasers  = pickTopChasers(standings, Config.Race.EVADE_CHASERS_CONSIDERED)

    updateLocalHUD(standings, result.runnerUp)

    if not RaceState.isHost or roundEnded or result.skipped then return end

    if result.eliminations and #result.eliminations > 0 then
        applyEliminations(result.eliminations)
    end

    if result.winConfirmed then
        endRound(standings)
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
    RaceState.topChasers       = {}
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
    RaceLogic.StopLoop()
    AIController.StopLoop()

    AIController.UnregisterAll()
    Spectator.Stop()

    Citizen.CreateThread(function()
        Citizen.Wait(300)
        RaceOrchestrator.cleanupVehicles()
    end)
end
