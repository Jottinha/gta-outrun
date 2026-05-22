-- ============================================================
--  OUTRUN — Client: Spawn (criação de veículos e peds da rodada)
--
--  Carrega modelos, posiciona cada carro no grid F1, cria peds
--  NPC e registra-os no AIController. Devolve a lista de veículos
--  criados para o orquestrador limpar depois.
-- ============================================================

Spawn = {}


-- Carrega um modelo com timeout. Necessário porque CreateVehicle
-- e CreatePed* retornam 0 silenciosamente quando o modelo não
-- está em memória.
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


local function resolveSpawnNode(base)
    local found, nodePos, nodeHead = GetClosestVehicleNodeWithHeading(
        base.x, base.y, base.z, 1, 3, 0)

    if not found or type(nodePos) ~= "vector3" then nodePos = base end
    if type(nodeHead) ~= "number" then nodeHead = 0.0 end

    Logger.debug("SPAWN", ("spawn node @ %s heading=%s"):format(
        tostring(nodePos), tostring(nodeHead)))
    return nodePos, nodeHead
end


local function pickPedModelName(index)
    local models = Config.PedModels
    return models[((index - 1) % #models) + 1]
end


local function createVehicleAt(model, x, y, z, heading)
    local hash = GetHashKey(model)
    if not loadModelHash(hash) then
        Logger.warn("SPAWN",
            ("modelo de veículo nao carregou: %s — fallback %s"):format(
                tostring(model), Config.Vehicles.DEFAULT))
        hash = GetHashKey(Config.Vehicles.DEFAULT)
        loadModelHash(hash)
    end

    local veh = CreateVehicle(hash, x, y, z, heading, true, false)
    SetVehicleEngineOn(veh, false, true, false)
    FreezeEntityPosition(veh, true)
    SetEntityAsMissionEntity(veh, true, true)
    SetModelAsNoLongerNeeded(hash)
    return veh
end


local function createNPC(vehicle, participantIndex, participantId)
    local pedModel = pickPedModelName(participantIndex)
    local pedHash  = GetHashKey(pedModel)
    if not loadModelHash(pedHash) then
        Logger.error("SPAWN", "ped model nao carregou: " .. pedModel)
        return 0
    end

    local ped = CreatePedInsideVehicle(vehicle, 26, pedHash, -1, true, false)
    if not DoesEntityExist(ped) then
        Logger.error("SPAWN",
            "CreatePedInsideVehicle devolveu 0 para id=" .. tostring(participantId))
    else
        SetEntityAsMissionEntity(ped, true, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        SetPedKeepTask(ped, true)
        SetPedCanBeDraggedOut(ped, false)
        SetDriverAbility(ped, 1.0)
        SetDriverAggressiveness(ped, 1.0)
        SetPedCanRagdollFromPlayerImpact(ped, false)
    end
    SetModelAsNoLongerNeeded(pedHash)
    return ped
end


-- ============================================================
-- Spawn.runMyVehicle(payload) — usado no modo multiplayer
--
-- Cada player spawna apenas o seu próprio veículo.
-- payload = {
--     roomId, spawnBase, model, gridIndex, totalCount,
--     bonusRound, scores, isHost
-- }
--
-- Retorna (vehicle, netId).
-- ============================================================

function Spawn.runMyVehicle(payload)
    -- Limpar veículo anterior se existir
    if RaceState.myVehicle and DoesEntityExist(RaceState.myVehicle) then
        DeleteVehicle(RaceState.myVehicle)
        RaceState.myVehicle = nil
    end

    RaceState.isHost        = payload.isHost == true
    RaceState.isMultiplayer = true
    RaceState.roomId        = payload.roomId

    local base              = payload.spawnBase
    local nodePos, nodeHead = resolveSpawnNode(base)
    local fwdX, fwdY, rgtX, rgtY = Grid.basisFromHeading(nodeHead)

    local offset = Grid.computeOffset(payload.gridIndex, payload.totalCount)
    local spawnX = nodePos.x + (fwdX * offset.longitudinal) + (rgtX * offset.lateral)
    local spawnY = nodePos.y + (fwdY * offset.longitudinal) + (rgtY * offset.lateral)
    local spawnZ = nodePos.z + 0.5

    local veh = createVehicleAt(payload.model or Config.Vehicles.DEFAULT,
        spawnX, spawnY, spawnZ, nodeHead)

    -- Registrar como entidade de rede para que outros players vejam o veículo
    SetEntityAsMissionEntity(veh, true, true)
    NetworkRegisterEntityAsNetworked(veh)
    SetNetworkIdCanMigrate(VehToNet(veh), false)

    TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)
    RaceState.myVehicle = veh

    local netId = VehToNet(veh)
    Logger.debug("SPAWN", ("MP: veículo próprio spawnado, netId=%d"):format(netId))
    return veh, netId
end


-- ============================================================
-- Spawn.run(payload) — usado no modo solo (comportamento original)
--
-- payload = {
--     roomId, participants, spawnBase, bonusRound, scores
-- }
--
-- Retorna lista de vehicles para o orquestrador limpar depois.
-- ============================================================

function Spawn.run(payload)
    local base  = payload.spawnBase
    local parts = payload.participants

    RaceState.isHost        = true
    RaceState.isMultiplayer = false
    RaceState.roomId        = payload.roomId
    RaceState.participants  = {}

    local nodePos, nodeHead = resolveSpawnNode(base)
    local forwardX, forwardY, rightX, rightY = Grid.basisFromHeading(nodeHead)

    local spawnedVehicles = {}

    for index, p in ipairs(parts) do
        local offset = Grid.computeOffset(index, #parts)
        local spawnX = nodePos.x + (forwardX * offset.longitudinal) + (rightX * offset.lateral)
        local spawnY = nodePos.y + (forwardY * offset.longitudinal) + (rightY * offset.lateral)
        local spawnZ = nodePos.z + 0.5

        local veh = createVehicleAt(p.model or Config.Vehicles.DEFAULT,
            spawnX, spawnY, spawnZ, nodeHead)

        if p.isNPC then
            local ped = createNPC(veh, index, p.source)
            AIController.RegisterNPC(p.source, veh, ped, p.personality)
            RaceState.participants[#RaceState.participants + 1] = {
                id = p.source, vehicle = veh, isNPC = true, eliminated = false,
            }
        else
            if p.source == GetPlayerServerId(PlayerId()) then
                TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)
                RaceState.myVehicle = veh
            end
            RaceState.participants[#RaceState.participants + 1] = {
                id = p.source, vehicle = veh, isNPC = false, eliminated = false,
            }
        end

        spawnedVehicles[#spawnedVehicles + 1] = veh
    end

    RaceState.leaderVeh = spawnedVehicles[1]
    RaceState.leaderId  = parts[1] and parts[1].source

    return spawnedVehicles
end
