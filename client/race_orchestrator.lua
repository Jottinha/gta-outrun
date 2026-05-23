-- ============================================================
--  OUTRUN — Client: RaceOrchestrator
--
--  Coordena o ciclo de vida de uma rodada no client.
--
--  Solo (1 humano): comportamento idêntico ao original.
--    1. beginRound()   → Spawn.run → countdown local → launch
--    2. onTick()       → callback do RaceLogic.StartLoop
--    3. endRound()     → para loops, envia SE.ROUND_END
--
--  Multiplayer (2+ humanos):
--    1. beginRoundMP() → Spawn.runMyVehicle → SE.SPAWN_READY
--    2. onAllSpawned() → popula participants do netIdMap
--    3. onRaceStartMP()→ descongela, inicia snapshot loop
--    4. onStandingsUpdate() → HUD/state via CE.STANDINGS_UPDATE
-- ============================================================

RaceOrchestrator = {}

local SE = Config.Events.Server
local CE = Config.Events.Client

local spawnedVehicles = {}
local roundEnded      = false


-- ===== Helper: blips dos chasers para o líder =====

local function updateChaserBlipsFromStandings(standings)
    local myId   = GetPlayerServerId(PlayerId())
    if myId ~= RaceState.leaderId then
        ChaserBlips.clear()
        return
    end
    local chasers = {}
    for _, entry in ipairs(standings) do
        if not entry.isLeader and not entry.eliminated then
            local veh = entry.vehicle
            if (not veh or not DoesEntityExist(veh)) then
                local p = RaceState.findParticipant(entry.id)
                if p and p.netId then
                    veh = NetToVeh(p.netId)
                    if DoesEntityExist(veh) then p.vehicle = veh end
                end
            end
            if veh and DoesEntityExist(veh) then
                chasers[#chasers + 1] = veh
            end
        end
        if #chasers >= 3 then break end
    end
    ChaserBlips.update(chasers)
end


-- ===== Accessors usados pelos loops (solo) =====

local function getLeaderVeh()    return RaceState.leaderVeh    end
local function getTopChasers()   return RaceState.topChasers   end
local function getLeaderId()     return RaceState.leaderId     end
local function getParticipants() return RaceState.participants end

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
-- Solo: Countdown local
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
-- Solo: Largada
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
-- Solo: Tick — callback do RaceLogic.StartLoop
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
    local riskDist
    if isLeader then
        riskDist = (runnerUp and runnerUp.dist)
                or (standings[2] and standings[2].dist)
                or nil
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
    LeaderBlip.clear()
    ChaserBlips.clear()
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
    updateChaserBlipsFromStandings(standings)

    if not RaceState.isHost or roundEnded or result.skipped then return end

    if result.eliminations and #result.eliminations > 0 then
        applyEliminations(result.eliminations)
    end

    if result.winConfirmed then
        endRound(standings)
    end
end


-- ============================================================
-- Solo: Ponto de entrada (CE.SPAWN_VEHICLES)
-- ============================================================

function RaceOrchestrator.beginRound(payload)
    RaceOrchestrator.cleanupVehicles()
    LeaderBlip.clear()
    ChaserBlips.clear()

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


-- ============================================================
-- Multiplayer: Ponto de entrada (CE.SPAWN_MY_VEHICLE)
-- ============================================================

function RaceOrchestrator.beginRoundMP(payload)
    roundEnded = false
    RaceOrchestrator.cleanupVehicles()
    LeaderBlip.clear()
    ChaserBlips.clear()

    RaceState.participants     = {}
    RaceState.eliminationOrder = {}
    RaceState.eliminated       = false
    RaceState.runnerUpId       = nil
    RaceState.runnerUpVeh      = nil
    RaceState.topChasers       = {}
    Spectator.Stop()

    local veh, netId = Spawn.runMyVehicle(payload)
    spawnedVehicles = { veh }

    -- Countdown UI será ativada quando CE.ALL_SPAWNED chegar
    TriggerServerEvent(SE.SPAWN_READY, netId)
    Logger.debug("ORCH", ("MP: spawn pronto, netId=%d"):format(netId))
end


-- Chamado quando CE.ALL_SPAWNED chega com o mapa netId de todos.
function RaceOrchestrator.onAllSpawned(netIdMap)
    local myId = GetPlayerServerId(PlayerId())

    RaceState.participants = {}
    for srcStr, info in pairs(netIdMap) do
        local src = tonumber(srcStr)
        local veh
        if src == myId then
            veh = RaceState.myVehicle
        else
            veh = NetToVeh(info.netId)
            -- NetToVeh pode retornar 0 se o veículo ainda não chegou via rede;
            -- o campo netId fica salvo para tentativa lazy em LEADER_CHANGED.
            if not DoesEntityExist(veh) then veh = nil end
        end
        RaceState.participants[#RaceState.participants + 1] = {
            id          = src,
            vehicle     = veh,
            netId       = info.netId,
            displayName = info.displayName,
            isNPC       = false,
            eliminated  = false,
        }
    end

    -- Mostrar tela de countdown (server enviará os ticks a seguir)
    Nui.send('showCountdown', { isBonusRound = false })

    Logger.debug("ORCH", ("MP: %d participantes registrados"):format(#RaceState.participants))
end


-- Chamado quando CE.RACE_START chega do servidor (MP).
function RaceOrchestrator.onRaceStartMP()
    roundEnded = false
    RaceState.eliminated = false
    RaceState.active     = true

    if RaceState.myVehicle then
        FreezeEntityPosition(RaceState.myVehicle, false)
        SetVehicleEngineOn(RaceState.myVehicle, true, true, false)
    end

    Nui.send('countdownGo', {})
    Nui.send('showHUD', {})

    RaceLogic.StartSnapshotLoop()
end


-- Chamado quando CE.STANDINGS_UPDATE chega do servidor (MP).
function RaceOrchestrator.onStandingsUpdate(data)
    if roundEnded then return end

    local standings = data.standings
    if not standings or #standings == 0 then return end

    -- Atualizar líder
    if data.leaderId and data.leaderId ~= RaceState.leaderId then
        RaceState.leaderId = data.leaderId
        local lp = RaceState.findParticipant(data.leaderId)
        if lp then
            local v = lp.vehicle
            if (not v or not DoesEntityExist(v)) and lp.netId then
                v = NetToVeh(lp.netId)
                if DoesEntityExist(v) then lp.vehicle = v end
            end
            RaceState.leaderVeh = DoesEntityExist(v or 0) and v or nil
        end
        Nui.send('leaderChanged', { leaderId = data.leaderId })
    end

    -- Runner-up
    RaceState.runnerUpId = data.runnerUpId
    if data.runnerUpId then
        local rp = RaceState.findParticipant(data.runnerUpId)
        if rp then
            local v = rp.vehicle
            if (not v or not DoesEntityExist(v)) and rp.netId then
                v = NetToVeh(rp.netId)
                if DoesEntityExist(v) then rp.vehicle = v end
            end
            RaceState.runnerUpVeh = DoesEntityExist(v or 0) and v or nil
        end
    end

    updateChaserBlipsFromStandings(standings)

    -- Top chasers (sem IA em MP, mas mantém para LeaderBlip via spectator)
    RaceState.topChasers = {}
    for _, entry in ipairs(standings) do
        if not entry.isLeader and not entry.ahead and not entry.eliminated then
            local p = RaceState.findParticipant(entry.id)
            if p and p.vehicle and DoesEntityExist(p.vehicle) then
                RaceState.topChasers[#RaceState.topChasers + 1] = p.vehicle
            end
        end
    end

    -- HUD
    local myId = GetPlayerServerId(PlayerId())
    local myEntry, myPos
    for pos, entry in ipairs(standings) do
        if entry.id == myId then
            myEntry = entry
            myPos   = pos
            break
        end
    end

    if myEntry and not RaceState.eliminated then
        local isLeader = (myId == RaceState.leaderId)
        local riskDist
        if isLeader then
            riskDist = data.runnerUpDist
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

    -- Marcar participantes eliminados localmente (para HUD)
    if data.newEliminations then
        local myId2 = GetPlayerServerId(PlayerId())
        for _, eid in ipairs(data.newEliminations) do
            if eid ~= myId2 then
                RaceState.markEliminated(eid)
            end
            -- Se for o player local: BE_SPECTATOR vem do servidor separadamente
        end
    end

    -- Vitória detectada pelo servidor → parar snapshot loop e aguardar ROUND_RESULT
    if data.winConfirmed and not roundEnded then
        roundEnded = true
        RaceState.active = false
        RaceLogic.StopLoop()
        LeaderBlip.clear()
        ChaserBlips.clear()
    end
end


-- ============================================================
-- Cleanup e encerramento de sessão
-- ============================================================

function RaceOrchestrator.cleanupVehicles()
    for _, veh in ipairs(spawnedVehicles) do
        if DoesEntityExist(veh) then DeleteVehicle(veh) end
    end
    spawnedVehicles = {}
    RaceState.myVehicle = nil
end

function RaceOrchestrator.endSession()
    RaceState.active = false
    roundEnded = true
    RaceLogic.StopLoop()
    AIController.StopLoop()
    LeaderBlip.clear()
    ChaserBlips.clear()

    AIController.UnregisterAll()
    Spectator.Stop()

    Citizen.CreateThread(function()
        Citizen.Wait(300)
        RaceOrchestrator.cleanupVehicles()
    end)
end
