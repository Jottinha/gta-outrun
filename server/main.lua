-- ============================================================
--  OUTRUN — Server Main
-- ============================================================

Rooms = {}
local nextRoomId = 1

local function log(msg)
    if Config.Debug.ENABLED then
        print(Config.Debug.LOG_PREFIX .. " [SRV] " .. msg)
    end
end

local function getRoomByHost(src)
    for id, room in pairs(Rooms) do
        if room.host == src then return id, room end
    end
end

local function getRoomByPlayer(src)
    for id, room in pairs(Rooms) do
        for _, p in ipairs(room.participants) do
            if p.source == src then return id, room end
        end
    end
end

local function buildNames(room)
    local names = {}
    for _, p in ipairs(room.participants) do
        if p.isNPC then
            names[p.source] = "Bot (" .. (p.model or "NPC") .. ")"
        else
            names[p.source] = GetPlayerName(p.source) or ("Jogador " .. tostring(p.source))
        end
    end
    return names
end

local function getChampionshipLeaderSrc(room)
    local topScore = -1
    local topSrc   = nil
    for _, p in ipairs(room.participants) do
        if not p.isNPC then
            local pts = room.scores[p.source] or 0
            if pts > topScore then
                topScore = pts
                topSrc   = p.source
            end
        end
    end
    return topSrc or room.host
end

-- ============================================================
-- Criar Sala
-- ============================================================

RegisterNetEvent(Config.Events.Server.CREATE_LOBBY, function(pointTarget)
    local src = source
    if getRoomByHost(src) then
        TriggerClientEvent('outrun:client:Notify', src, "Você já possui uma sala aberta.")
        return
    end

    local roomId = nextRoomId
    nextRoomId   = nextRoomId + 1

    Rooms[roomId] = {
        host          = src,
        state         = Config.States.Room.LOBBY,
        pointTarget   = pointTarget or 100,
        scores        = { [src] = 0 },
        -- Jogador host com carro padrão; pode trocar via SetCar
        participants  = { { source = src, isNPC = false, ready = false, model = "sultan" } },
        roundNum      = 0,
        currentLeader = nil,
    }

    TriggerClientEvent('outrun:client:LobbyCreated', src, roomId, Rooms[roomId])
    log("Sala " .. roomId .. " criada pelo jogador " .. src)
end)

-- ============================================================
-- Solicitar Estado do Lobby
-- ============================================================

RegisterNetEvent(Config.Events.Server.REQUEST_LOBBY_STATE, function()
    local src = source
    local roomId, room = getRoomByPlayer(src)
    if room then
        TriggerClientEvent('outrun:client:LobbyCreated', src, roomId, room)
    else
        TriggerClientEvent(Config.Events.Client.NO_ACTIVE_LOBBY, src)
    end
end)

-- ============================================================
-- Adicionar NPC
-- ============================================================

RegisterNetEvent('outrun:server:AddNPC', function(model, personality)
    local src = source
    local roomId, room = getRoomByHost(src)
    if not room or room.state ~= Config.States.Room.LOBBY then return end

    local npcId = "npc_" .. #room.participants + 1
    table.insert(room.participants, {
        source      = npcId,
        isNPC       = true,
        ready       = true,
        model       = model       or "sultan",
        personality = personality or "balanced",
    })
    room.scores[npcId] = 0

    TriggerClientEvent('outrun:client:LobbyUpdated', src, room)
end)

-- ============================================================
-- Trocar Carro do Jogador (humano)
-- ============================================================

RegisterNetEvent('outrun:server:SetCar', function(model)
    local src = source
    local _, room = getRoomByPlayer(src)
    if not room or room.state ~= Config.States.Room.LOBBY then return end

    for _, p in ipairs(room.participants) do
        if p.source == src then
            p.model = model or "sultan"
            break
        end
    end

    TriggerClientEvent('outrun:client:LobbyUpdated', room.host, room)
end)

-- ============================================================
-- Toggle Ready
-- ============================================================

RegisterNetEvent(Config.Events.Server.TOGGLE_READY, function()
    local src = source
    local roomId, room = getRoomByPlayer(src)
    if not room or room.state ~= Config.States.Room.LOBBY then return end

    for _, p in ipairs(room.participants) do
        if p.source == src then
            p.ready = not p.ready
            break
        end
    end

    TriggerClientEvent('outrun:client:LobbyUpdated', room.host, room)
end)

-- ============================================================
-- Iniciar Rodada (usado pelo START_RACE e pelo auto-restart)
-- ============================================================

local function startRound(roomId, room)
    if not room or not Rooms[roomId] then return end

    room.state    = Config.States.Room.SPAWN_GRID
    room.roundNum = room.roundNum + 1

    local nodes      = Config.SpawnNodes
    local spawnPoint = nodes[math.random(#nodes)]

    local bonusActive    = false
    local bonusTargetSrc = nil

    if math.random() < Config.BonusRound.TRIGGER_PROBABILITY then
        local topScore = 0
        for _, p in ipairs(room.participants) do
            if not p.isNPC then
                topScore = math.max(topScore, room.scores[p.source] or 0)
            end
        end
        if topScore > 0 or room.roundNum > 1 then
            bonusActive    = true
            bonusTargetSrc = getChampionshipLeaderSrc(room)
        end
    end

    TriggerClientEvent(Config.Events.Client.SPAWN_VEHICLES, room.host, {
        roomId       = roomId,
        participants = room.participants,
        spawnBase    = spawnPoint,
        bonusRound   = { active = bonusActive, targetSrc = bonusTargetSrc },
        scores       = room.scores,
    })

    log("Sala " .. roomId .. " iniciando rodada " .. room.roundNum ..
        (bonusActive and " [BÔNUS]" or ""))
end

RegisterNetEvent(Config.Events.Server.START_RACE, function()
    local src = source
    local roomId, room = getRoomByHost(src)
    if not room or room.state ~= Config.States.Room.LOBBY then return end

    for _, p in ipairs(room.participants) do
        if not p.isNPC and not p.ready then
            TriggerClientEvent('outrun:client:Notify', src, "Nem todos os jogadores estão prontos.")
            return
        end
    end

    startRound(roomId, room)
end)

-- ============================================================
-- Corrida Iniciada (B3)
-- ============================================================

RegisterNetEvent(Config.Events.Server.RACE_STARTED, function()
    local src = source
    local _, room = getRoomByHost(src)
    if not room then return end
    room.state = Config.States.Room.RACING
    log("Sala -> RACING")
end)

-- ============================================================
-- Atualizar Líder
-- ============================================================

RegisterNetEvent(Config.Events.Server.UPDATE_LEADER, function(leaderId)
    local src = source
    local _, room = getRoomByHost(src)
    if not room or room.state ~= Config.States.Room.RACING then return end

    room.currentLeader = leaderId
    for _, p in ipairs(room.participants) do
        if not p.isNPC then
            TriggerClientEvent('outrun:client:LeaderChanged', p.source, leaderId)
        end
    end
end)

-- ============================================================
-- Fim de Rodada
-- ============================================================

RegisterNetEvent(Config.Events.Server.ROUND_END, function(results)
    local src = source
    local roomId, room = getRoomByHost(src)
    if not room then return end

    room.state = Config.States.Room.ROUND_RESULT

    for _, r in ipairs(results) do
        local pts = Config.Scoring[r.position] or 0
        room.scores[r.id] = (room.scores[r.id] or 0) + pts
    end

    for _, p in ipairs(room.participants) do
        if not p.isNPC then
            TriggerClientEvent('outrun:client:ClearWanted', p.source)
        end
    end

    room.state = Config.States.Room.CHECK_CHAMPIONSHIP
    local champion = nil
    local championScore = -1
    for participantId, pts in pairs(room.scores) do
        if pts >= room.pointTarget and pts > championScore then
            champion = participantId
            championScore = pts
        end
    end

    local names = buildNames(room)

    if champion then
        room.state = Config.States.Room.END_SCREEN
        for _, p in ipairs(room.participants) do
            if not p.isNPC then
                TriggerClientEvent('outrun:client:ShowEndScreen', p.source, champion, room.scores, names)
            end
        end
        Rooms[roomId] = nil
        log("Campeão: " .. tostring(champion) .. " (" .. (names[champion] or "?") .. ")")
    else
        room.state = Config.States.Room.ROUND_RESULT
        for _, p in ipairs(room.participants) do
            if not p.isNPC then
                TriggerClientEvent('outrun:client:RoundResult', p.source, results, room.scores, names)
            end
        end
        -- Reinicia automaticamente após o placar ser exibido
        local capturedId = roomId
        Citizen.SetTimeout(10000, function()
            startRound(capturedId, Rooms[capturedId])
        end)
        log("Sala " .. roomId .. " aguardando 10s para próxima rodada")
    end
end)

-- ============================================================
-- Jogador Eliminado
-- ============================================================

RegisterNetEvent(Config.Events.Client.PLAYER_ELIMINATED, function(eliminatedId)
    local src = source
    local _, room = getRoomByHost(src)
    if not room then return end

    for _, p in ipairs(room.participants) do
        if not p.isNPC and tostring(p.source) == tostring(eliminatedId) then
            TriggerClientEvent('outrun:client:BeSpectator', p.source, room.currentLeader)
            break
        end
    end
end)
