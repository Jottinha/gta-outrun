-- ============================================================
--  OUTRUN — Server: RaceServer
--
--  Modo multiplayer (2+ humans): coleta snapshots de posição
--  enviados por cada player, roda OvertakeCore.tick() no servidor
--  e faz broadcast de CE.STANDINGS_UPDATE para todos.
--
--  Em solo (1 humano) este módulo não é ativado — a liderança
--  continua sendo calculada no client do host como hoje.
-- ============================================================

RaceServer = {}

local CE       = Config.Events.Client
local sessions = {}  -- roomId → session


-- ============================================================
-- Configuração (espelho de makeCfg() em client/race_logic.lua)
-- ============================================================

local function makeCfg()
    return {
        PASS_DISTANCE_NEAR           = Config.Race.LEADER_PASS_DISTANCE_NEAR,
        PASS_DISTANCE                = Config.Race.LEADER_PASS_DISTANCE,
        NEAR_LATERAL                 = Config.Race.LEADER_NEAR_LATERAL,
        MAX_LATERAL_FOR_PASS         = Config.Race.LEADER_MAX_LATERAL_FOR_PASS,
        PASS_DISTANCE_HARD           = Config.Race.LEADER_PASS_DISTANCE_HARD,
        OVERRIDE_DISTANCE            = Config.Race.LEADER_OVERRIDE_DISTANCE,
        MAX_Z_DIFF                   = Config.Race.LEADER_MAX_Z_DIFF,
        MIN_SPEED_FOR_PASS           = Config.Race.LEADER_MIN_SPEED_FOR_PASS,
        MIN_ALIGNMENT                = Config.Race.LEADER_MIN_ALIGNMENT,
        LEADER_HOLD_TICKS            = Config.Race.LEADER_HOLD_TICKS,
        LEADER_MIN_CURRENT_TICKS     = Config.Race.LEADER_MIN_CURRENT_TICKS,
        LEADER_HARD_HOLD_TICKS       = Config.Race.LEADER_HARD_HOLD_TICKS,
        LEADER_CHANGE_COOLDOWN_TICKS = Config.Race.LEADER_CHANGE_COOLDOWN_TICKS,
        WIN_DISTANCE                 = Config.Race.WIN_DISTANCE,
        ELIMINATION_DISTANCE         = Config.Race.ELIMINATION_DISTANCE,
        WIN_CONFIRM_TICKS            = Config.Race.WIN_CONFIRM_TICKS,
        MIN_SPEED_FOR_VELOCITY_FWD   = Config.Race.LEADER_MIN_SPEED_FOR_VELOCITY_FWD,
        FORWARD_MIN_MAGNITUDE        = Config.Race.FORWARD_MIN_MAGNITUDE,
        FORWARD_CACHE_MAX_AGE_TICKS  = Config.Race.FORWARD_CACHE_MAX_AGE_TICKS,
    }
end


-- ============================================================
-- API pública
-- ============================================================

function RaceServer.startSession(roomId, room)
    local session = {
        overtakeState  = OvertakeCore.newState(),
        cfg            = makeCfg(),
        snapshots      = {},
        eliminated     = {},
        eliminatedOrder = {},
        currentLeader  = nil,
        roundEnded     = false,
        generation     = 1,
    }
    sessions[roomId] = session

    local myGen = session.generation
    Citizen.CreateThread(function()
        while sessions[roomId] and sessions[roomId].generation == myGen do
            local s = sessions[roomId]
            if s and not s.roundEnded then
                -- Montar lista de snapshots recebidos
                local snapList = {}
                for _, snap in pairs(s.snapshots) do
                    snapList[#snapList + 1] = snap
                end

                if #snapList >= 2 then
                    local result = OvertakeCore.tick(s.overtakeState, snapList, s.cfg)

                    if result and result.leaderId then
                        local names = Rooms.buildNames(room)

                        -- Standings serializáveis (sem handles de entidade)
                        local standings = {}
                        for _, entry in ipairs(result.standings) do
                            standings[#standings + 1] = {
                                id          = entry.id,
                                displayName = names[entry.id] or tostring(entry.id),
                                dist        = entry.dist,
                                isLeader    = entry.isLeader,
                                ahead       = entry.ahead,
                                eliminated  = entry.eliminated,
                            }
                        end

                        -- Notificar troca de líder
                        if result.leaderId ~= s.currentLeader then
                            s.currentLeader = result.leaderId
                            RoundManager.handleLeaderUpdate(room, result.leaderId)
                        end

                        -- Processar eliminações novas
                        local newElims = {}
                        if result.eliminations then
                            for _, entry in ipairs(result.eliminations) do
                                if not s.eliminated[entry.id] then
                                    s.eliminated[entry.id] = true
                                    s.eliminatedOrder[#s.eliminatedOrder + 1] = entry.id
                                    newElims[#newElims + 1] = entry.id
                                    if not entry.isNPC then
                                        RoundManager.handleEliminated(room, entry.id)
                                    end
                                end
                            end
                        end

                        -- Broadcast para todos os humanos da sala
                        local runnerUpId = result.runnerUp and result.runnerUp.id or nil
                        -- Incluir dist do runner-up nas standings para HUD do líder
                        local runnerUpDist = nil
                        if runnerUpId then
                            for _, e in ipairs(standings) do
                                if e.id == runnerUpId then
                                    runnerUpDist = e.dist
                                    break
                                end
                            end
                        end

                        Rooms.eachHuman(room, function(p)
                            TriggerClientEvent(CE.STANDINGS_UPDATE, p.source, {
                                standings       = standings,
                                leaderId        = result.leaderId,
                                runnerUpId      = runnerUpId,
                                runnerUpDist    = runnerUpDist,
                                newEliminations = newElims,
                                winConfirmed    = result.winConfirmed or false,
                            })
                        end)

                        -- Vitória: construir resultados e encerrar rodada
                        if result.winConfirmed and not s.roundEnded then
                            s.roundEnded = true

                            local results = {}
                            local seen    = {}
                            for pos, entry in ipairs(result.standings) do
                                results[#results + 1] = { id = entry.id, position = pos }
                                seen[entry.id] = true
                            end
                            for i = #s.eliminatedOrder, 1, -1 do
                                local eid = s.eliminatedOrder[i]
                                if not seen[eid] then
                                    results[#results + 1] = { id = eid, position = #results + 1 }
                                    seen[eid] = true
                                end
                            end

                            RoundManager.endRound(roomId, room, results)
                        end
                    end
                end
            end

            Citizen.Wait(Config.Race.DISTANCE_UPDATE_INTERVAL)
        end

        Logger.debug("RACE_SRV", ("Sessão encerrada para sala %d"):format(roomId))
    end)

    Logger.info("RACE_SRV", ("Sessão MP iniciada para sala %d (%d players)"):format(
        roomId, Rooms.humanCount(room)))
end


function RaceServer.updateSnapshot(roomId, src, snap)
    local s = sessions[roomId]
    if not s or s.roundEnded then return end
    snap.id    = src
    snap.isNPC = false
    s.snapshots[src] = snap
end


function RaceServer.endSession(roomId)
    local s = sessions[roomId]
    if s then
        s.generation = s.generation + 1
        sessions[roomId] = nil
    end
end


function RaceServer.hasSession(roomId)
    return sessions[roomId] ~= nil
end
