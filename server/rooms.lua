-- ============================================================
--  OUTRUN — Server: Rooms (repositório de salas em memória)
--
--  Único módulo autorizado a modificar a tabela interna `rooms`.
--  Outros módulos do server só interagem por funções daqui.
-- ============================================================

Rooms = {}

local rooms = {}
local nextRoomId = 1


-- ===== Helpers internos =====

local function findRoomByHost(src)
    for id, room in pairs(rooms) do
        if room.host == src then
            return id, room
        end
    end
end

local function findRoomByParticipant(src)
    for id, room in pairs(rooms) do
        for _, p in ipairs(room.participants) do
            if p.source == src then
                return id, room
            end
        end
    end
end


-- ===== API pública =====

function Rooms.create(hostSrc, pointTarget)
    local roomId = nextRoomId
    nextRoomId = nextRoomId + 1

    local room = {
        id            = roomId,
        host          = hostSrc,
        state         = Config.States.Room.LOBBY,
        pointTarget   = pointTarget or Config.DefaultPointTarget,
        scores        = { [hostSrc] = 0 },
        participants  = {
            {
                source = hostSrc,
                isNPC  = false,
                ready  = false,
                model  = Config.Vehicles.DEFAULT,
            },
        },
        roundNum      = 0,
        currentLeader = nil,
    }

    rooms[roomId] = room
    return roomId, room
end

function Rooms.getByHost(src)
    return findRoomByHost(src)
end

function Rooms.getByParticipant(src)
    return findRoomByParticipant(src)
end

function Rooms.get(roomId)
    return rooms[roomId]
end

function Rooms.delete(roomId)
    rooms[roomId] = nil
end

function Rooms.setState(room, newState)
    room.state = newState
end

function Rooms.addNPC(room, model, personality)
    local npcId = "npc_" .. (#room.participants + 1)
    table.insert(room.participants, {
        source      = npcId,
        isNPC       = true,
        ready       = true,
        model       = model       or Config.Vehicles.DEFAULT,
        personality = personality or "balanced",
    })
    room.scores[npcId] = 0
    return npcId
end

function Rooms.setParticipantCar(room, src, model)
    for _, p in ipairs(room.participants) do
        if p.source == src then
            p.model = model or Config.Vehicles.DEFAULT
            return true
        end
    end
    return false
end

function Rooms.toggleReady(room, src)
    for _, p in ipairs(room.participants) do
        if p.source == src then
            p.ready = not p.ready
            return p.ready
        end
    end
end

function Rooms.allHumansReady(room)
    for _, p in ipairs(room.participants) do
        if not p.isNPC and not p.ready then
            return false
        end
    end
    return true
end

function Rooms.removeParticipant(room, src)
    for i, p in ipairs(room.participants) do
        if not p.isNPC and p.source == src then
            table.remove(room.participants, i)
            room.scores[src] = nil
            return true
        end
    end
    return false
end

function Rooms.buildNames(room)
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

function Rooms.getChampionshipLeader(room)
    local topScore = -1
    local topSrc = nil
    for _, p in ipairs(room.participants) do
        if not p.isNPC then
            local pts = room.scores[p.source] or 0
            if pts > topScore then
                topScore = pts
                topSrc = p.source
            end
        end
    end
    return topSrc or room.host, topScore
end

function Rooms.applyScoring(room, results)
    for _, r in ipairs(results) do
        local pts = Config.Scoring[r.position] or 0
        room.scores[r.id] = (room.scores[r.id] or 0) + pts
    end
end

function Rooms.findChampion(room)
    local champion = nil
    local championScore = -1
    for participantId, pts in pairs(room.scores) do
        if pts >= room.pointTarget and pts > championScore then
            champion = participantId
            championScore = pts
        end
    end
    return champion, championScore
end

function Rooms.eachHuman(room, fn)
    for _, p in ipairs(room.participants) do
        if not p.isNPC then
            fn(p)
        end
    end
end

-- ===== Multiplayer: gestão de humanos e netIds =====

function Rooms.addHuman(room, src)
    for _, p in ipairs(room.participants) do
        if p.source == src then return false end
    end
    table.insert(room.participants, {
        source = src,
        isNPC  = false,
        ready  = false,
        model  = Config.Vehicles.DEFAULT,
    })
    room.scores[src] = 0
    return true
end

function Rooms.humanCount(room)
    local n = 0
    for _, p in ipairs(room.participants) do
        if not p.isNPC then n = n + 1 end
    end
    return n
end

function Rooms.isMultiplayer(room)
    return Rooms.humanCount(room) > 1
end

function Rooms.removeAllNPCs(room)
    local i = 1
    while i <= #room.participants do
        if room.participants[i].isNPC then
            room.scores[room.participants[i].source] = nil
            table.remove(room.participants, i)
        else
            i = i + 1
        end
    end
end

function Rooms.setNetId(room, src, netId)
    for _, p in ipairs(room.participants) do
        if p.source == src then
            p.netId = netId
            return true
        end
    end
    return false
end

function Rooms.allHumansSpawned(room)
    for _, p in ipairs(room.participants) do
        if not p.isNPC and not p.netId then return false end
    end
    return true
end

function Rooms.clearNetIds(room)
    for _, p in ipairs(room.participants) do
        p.netId = nil
    end
end

function Rooms.buildNetIdMap(room)
    local map = {}
    for _, p in ipairs(room.participants) do
        if not p.isNPC and p.netId then
            map[tostring(p.source)] = {
                netId       = p.netId,
                model       = p.model,
                displayName = GetPlayerName(p.source) or ("Jogador " .. tostring(p.source)),
            }
        end
    end
    return map
end

function Rooms.promoteNextHost(room)
    for _, p in ipairs(room.participants) do
        if not p.isNPC and p.source ~= room.host then
            room.host = p.source
            return p.source
        end
    end
    return nil
end

-- Serializa a sala com nomes de display para enviar à NUI.
function Rooms.toLobbyPayload(room)
    local participants = {}
    for _, p in ipairs(room.participants) do
        participants[#participants + 1] = {
            source      = p.source,
            isNPC       = p.isNPC,
            ready       = p.ready,
            model       = p.model,
            personality = p.personality,
            name        = p.isNPC and nil or (GetPlayerName(p.source) or ("Jogador " .. tostring(p.source))),
        }
    end
    return {
        id           = room.id,
        host         = room.host,
        state        = room.state,
        pointTarget  = room.pointTarget,
        scores       = room.scores,
        participants = participants,
        roundNum     = room.roundNum,
    }
end


-- Lista salas em estado LOBBY (aguardando jogadores).
function Rooms.list()
    local out = {}
    for _, room in pairs(rooms) do
        if room.state == Config.States.Room.LOBBY then
            local humans, npcs = 0, 0
            for _, p in ipairs(room.participants) do
                if p.isNPC then npcs = npcs + 1 else humans = humans + 1 end
            end
            out[#out + 1] = {
                id          = room.id,
                hostName    = GetPlayerName(room.host) or ("Host " .. tostring(room.host)),
                pointTarget = room.pointTarget,
                humans      = humans,
                npcs        = npcs,
                state       = room.state,
            }
        end
    end
    return out
end
