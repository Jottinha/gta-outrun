-- ============================================================
--  OUTRUN — OvertakeCore (shared, puro)
--
--  Recebe SNAPSHOTS de participantes e devolve {leaderId, standings,
--  runnerUp, eliminations, winConfirmed}. Não chama nada de FiveM —
--  é alimentado pelo adapter (client/race_logic.lua hoje, server no
--  futuro via MULTIPLAYER_PLAN §3.1).
--
--  Snapshot esperado (uma entry por participante):
--    {
--      id            = number,           -- id estável do participante
--      isNPC         = boolean,
--      valid         = boolean,          -- veículo existe?
--      eliminated    = boolean,
--      x, y, z       = number,           -- posição (se valid)
--      fx, fy        = number,           -- forward 2D do veículo (se valid)
--      vx, vy        = number,           -- velocity 2D (se valid)
--      speed         = number,           -- |velocity 2D| (se valid)
--    }
--
--  Config esperado: ver `Config.Race` em `config.lua`. Resumo:
--    - PASS_DISTANCE_NEAR/PASS_DISTANCE + NEAR_LATERAL + MAX_LATERAL_FOR_PASS
--      definem a região onde um candidato é considerado "à frente".
--    - PASS_DISTANCE_HARD + LEADER_HARD_HOLD_TICKS controlam fast-path.
--    - OVERRIDE_DISTANCE permite trocar durante cooldown.
--    - LEADER_HOLD_TICKS + LEADER_MIN_CURRENT_TICKS controlam histerese SOFT
--      (grupo + candidato atual, separados).
--    - LEADER_CHANGE_COOLDOWN_TICKS bloqueia trocas em cadeia.
--    - MIN_SPEED_FOR_PASS + MIN_ALIGNMENT filtram candidato parado/contramão.
--    - MIN_SPEED_FOR_VELOCITY_FWD escolhe entre velocity e forward visual.
-- ============================================================

OvertakeCore = {}


-- ------------------------------------------------------------
-- Estado mutável persistido entre ticks
-- ------------------------------------------------------------

function OvertakeCore.newState()
    return {
        leaderId           = nil,
        -- Histerese SOFT separada em "grupo" (qualquer pending) e "atual"
        -- (mesmo id). Trigger SOFT exige AMBOS — evita que candidato novo
        -- herde toda a histerese acumulada por outros.
        softGroupTicks     = 0,
        softCurrentTicks   = 0,
        candidateId        = nil,
        -- HARD precisa do MESMO candidato por N ticks (anti spike de giro).
        hardCandidateId    = nil,
        hardCandidateTicks = 0,
        -- Tick em que a última troca de líder ocorreu (para cooldown).
        leaderChangedAt    = -math.huge,
        winTicks           = 0,
        forwardCache       = nil,
        tickCount          = 0,
    }
end

function OvertakeCore.resetCandidate(state)
    state.candidateId        = nil
    state.softGroupTicks     = 0
    state.softCurrentTicks   = 0
    state.hardCandidateId    = nil
    state.hardCandidateTicks = 0
end

function OvertakeCore.resetWin(state)
    state.winTicks = 0
end


-- ------------------------------------------------------------
-- Helpers internos (locais — sem custo de export)
-- ------------------------------------------------------------

local function filterActive(snapshots)
    local active = {}
    for _, s in ipairs(snapshots) do
        if s.valid and not s.eliminated then
            active[#active + 1] = s
        end
    end
    return active
end

local function findById(active, id)
    if id == nil then return nil end
    for _, s in ipairs(active) do
        if s.id == id then return s end
    end
    return nil
end

local function forwardMagnitudeSq(s)
    return (s.fx or 0) * (s.fx or 0) + (s.fy or 0) * (s.fy or 0)
end

-- Resolve (fx, fy) normalizados para um snapshot. Retorna nil se inválido.
local function normalizeForward(s, minMagnitude)
    local mag2 = forwardMagnitudeSq(s)
    if mag2 < (minMagnitude * minMagnitude) then
        return nil
    end
    local mag = math.sqrt(mag2)
    return s.fx / mag, s.fy / mag
end

-- Direção de corrida (race direction):
--   1) se o carro está acima de MIN_SPEED_FOR_VELOCITY_FWD E a velocidade
--      está alinhada com o forward visual (dot ≥ 0), usamos o vetor de
--      VELOCIDADE — robusto a capotamento e loop apertado.
--   2) se dot < 0 (carro em ré: velocity aponta para trás do corpo), usamos
--      o forward visual — a frente do carro é sempre a referência certa.
--   3) se nada estiver utilizável, retorna nil — caller cai em cache/fallback.
-- Exposta como OvertakeCore.resolveDirection para o módulo de debug visual
-- consumir a MESMA matemática que o tick usa (single source of truth).
function OvertakeCore.resolveDirection(s, cfg)
    local minVelFwd = cfg.MIN_SPEED_FOR_VELOCITY_FWD or 5.0
    if s.speed and s.speed >= minVelFwd and s.vx and s.vy then
        -- dot(velocity, forward): positivo = andando pra frente, negativo = ré
        local dot = s.vx * (s.fx or 0) + s.vy * (s.fy or 0)
        if dot >= 0 then
            return s.vx / s.speed, s.vy / s.speed
        end
        -- Em ré: cai para forward visual (aponta sempre à frente do carro)
    end
    return normalizeForward(s, cfg.FORWARD_MIN_MAGNITUDE)
end
local resolveRaceDirection = OvertakeCore.resolveDirection

-- Escolhe a âncora quando o líder anterior não existe mais.
-- Usa o forward cacheado (do último líder válido) para projetar a posição
-- de cada candidato na direção da pista — quem estiver mais avançado vira âncora.
-- Se não houver cache, cai no primeiro ativo.
local function pickAnchorFallback(active, cache)
    if cache and cache.fx and cache.fy then
        local bestProj, best = -math.huge, nil
        for _, s in ipairs(active) do
            local proj = (s.x - (cache.x or 0)) * cache.fx
                       + (s.y - (cache.y or 0)) * cache.fy
            if proj > bestProj then
                bestProj = proj
                best     = s
            end
        end
        return best or active[1]
    end
    return active[1]
end

-- Projeção longitudinal + lateral + dist 2D para um snapshot em relação a um pivô.
local function projectAgainst(s, pivot, fx, fy)
    local dx = s.x - pivot.x
    local dy = s.y - pivot.y
    local dz = math.abs(s.z - pivot.z)
    local longitudinal = dx * fx + dy * fy
    local lateral      = math.abs(dx * fy - dy * fx)
    local dist         = math.sqrt(dx * dx + dy * dy)
    return longitudinal, lateral, dist, dz
end

-- Para uma âncora + direção, encontra o melhor candidato à liderança.
-- Filtros (todos precisam passar):
--   1. longitudinal > PASS_DISTANCE_NEAR (se lateral ≤ NEAR_LATERAL)
--      ou longitudinal > PASS_DISTANCE     (se lateral ≤ MAX_LATERAL_FOR_PASS)
--      → carros muito laterais são descartados (não estão na "fila" do líder)
--   2. dz ≤ MAX_Z_DIFF                     (anti-viaduto)
--   3. speed ≥ MIN_SPEED_FOR_PASS          (anti-carro-parado)
--   4. dot(forward candidato, direção do líder) ≥ MIN_ALIGNMENT
--      (anti-contramão/atravessado; só verifica se forward do candidato
--       tem magnitude utilizável — capotado passa direto)
-- Best = maior longitudinal; desempate por menor lateral.
local function findPendingCandidate(active, anchor, fx, fy, cfg)
    local maxLat       = cfg.MAX_LATERAL_FOR_PASS or 8.0
    local nearLat      = cfg.NEAR_LATERAL         or 3.0
    local passNear     = cfg.PASS_DISTANCE_NEAR   or 2.0
    local passFar      = cfg.PASS_DISTANCE        or 4.0
    local passMax      = cfg.PASS_MAX_DISTANCE    or math.huge
    local maxZ         = cfg.MAX_Z_DIFF           or 8.0
    local minSpeed     = cfg.MIN_SPEED_FOR_PASS   or 2.0
    local minAlignment = cfg.MIN_ALIGNMENT        or 0.25
    local fwdMinMag2   = (cfg.FORWARD_MIN_MAGNITUDE or 0.2) ^ 2
    local best = nil
    for _, s in ipairs(active) do
        if s.id ~= anchor.id then
            local longitudinal, lateral, _, dz = projectAgainst(s, anchor, fx, fy)
            local needed = (lateral <= nearLat) and passNear or passFar

            local passes = lateral <= maxLat
                and longitudinal > needed
                and longitudinal <= passMax
                and dz <= maxZ
                and (not s.speed or s.speed >= minSpeed)

            if passes and s.fx and s.fy then
                local sMag2 = s.fx * s.fx + s.fy * s.fy
                if sMag2 >= fwdMinMag2 then
                    local sMag = math.sqrt(sMag2)
                    local align = (s.fx / sMag) * fx + (s.fy / sMag) * fy
                    if align < minAlignment then passes = false end
                end
                -- Forward inválido do candidato: não bloqueia (capotando mas
                -- ainda à frente é ultrapassagem legítima)
            end

            if passes then
                if not best
                or longitudinal > best.longitudinal
                or (math.abs(longitudinal - best.longitudinal) <= 0.5
                    and lateral < best.lateral) then
                    best = { id = s.id, longitudinal = longitudinal, lateral = lateral }
                end
            end
        end
    end
    return best
end

-- Constrói as standings completas, marcando isLeader e categoria (ahead/trailing).
local function buildStandingsTable(active, leader, fx, fy)
    local standings = {}
    for _, s in ipairs(active) do
        local longitudinal, lateral, dist = projectAgainst(s, leader, fx, fy)
        standings[#standings + 1] = {
            id           = s.id,
            isNPC        = s.isNPC,
            vehicle      = s.vehicle,
            x            = s.x,
            y            = s.y,
            z            = s.z,
            dist         = dist,
            longitudinal = longitudinal,
            lateral      = lateral,
            isLeader     = (s.id == leader.id),
            ahead        = longitudinal > 0 and s.id ~= leader.id,
        }
    end

    -- Ordenação:
    --   1) líder primeiro
    --   2) carros "ahead" (ultrapassando, ainda dentro de PASS_DISTANCE)
    --      ordenados por maior longitudinal
    --   3) restante por menor "atraso" (longitudinal menos negativo) primeiro;
    --      desempate por menor lateral
    table.sort(standings, function(a, b)
        if a.isLeader ~= b.isLeader then return a.isLeader end
        if a.ahead    ~= b.ahead    then return a.ahead    end
        if a.ahead then
            return a.longitudinal > b.longitudinal
        end
        if math.abs(a.longitudinal - b.longitudinal) > 0.5 then
            return a.longitudinal > b.longitudinal
        end
        return a.lateral < b.lateral
    end)

    return standings
end

-- Fallback usado quando NÃO há direção de corrida utilizável (líder capotado,
-- forward inválido, cache expirado). Rankeia por distância 2D ao líder —
-- impreciso, mas mantém topChasers/runner-up populados para a IA.
local function buildFallbackStandings(active, leader)
    local standings = {}
    for _, s in ipairs(active) do
        local dx = s.x - leader.x
        local dy = s.y - leader.y
        local dist = math.sqrt(dx * dx + dy * dy)
        standings[#standings + 1] = {
            id           = s.id,
            isNPC        = s.isNPC,
            vehicle      = s.vehicle,
            x = s.x, y = s.y, z = s.z,
            dist         = dist,
            longitudinal = -dist,  -- assume "atrás" — sem direção, é o seguro
            lateral      = 0,
            isLeader     = (s.id == leader.id),
            ahead        = false,
        }
    end
    table.sort(standings, function(a, b)
        if a.isLeader ~= b.isLeader then return a.isLeader end
        return a.dist < b.dist
    end)
    return standings
end

-- Devolve o primeiro entry com longitudinal < 0 (verdadeiro 2º colocado).
-- Fallback: se TODOS os não-líderes estão marcados `ahead` (acontece em
-- curvas fechadas quando o forward do líder gira e projeta perseguidores
-- com longitudinal > 0), devolve o primeiro não-líder mesmo assim. Sem
-- fallback, HUD e win-check perdem o runner-up intermitentemente em curvas.
local function findTrailingRunnerUp(standings)
    local fallback = nil
    for _, e in ipairs(standings) do
        if not e.isLeader then
            if not e.ahead then return e end
            if not fallback then fallback = e end
        end
    end
    return fallback
end

local function collectEliminations(standings, cfg)
    local out = {}
    for _, e in ipairs(standings) do
        if not e.isLeader and e.longitudinal <= -cfg.ELIMINATION_DISTANCE then
            out[#out + 1] = e
        end
    end
    return out
end


-- ------------------------------------------------------------
-- Resultado vazio — factory (nunca compartilhar instância: callers podem
-- mutar `standings` etc. e contaminar ticks futuros).
-- ------------------------------------------------------------

local function emptyResult()
    return {
        leaderId     = nil,
        standings    = {},
        runnerUp     = nil,
        eliminations = {},
        winConfirmed = false,
        skipped      = false,
    }
end


-- ------------------------------------------------------------
-- Tick principal (host-side: avalia tudo + persiste histerese)
-- ------------------------------------------------------------

function OvertakeCore.tick(state, snapshots, cfg)
    state.tickCount = (state.tickCount or 0) + 1

    local active = filterActive(snapshots)
    if #active == 0 then
        OvertakeCore.resetCandidate(state)
        OvertakeCore.resetWin(state)
        return emptyResult()
    end

    -- 1) Âncora: líder anterior se ainda ativo, senão fallback orientado.
    local anchor = findById(active, state.leaderId)
    if not anchor then
        anchor = pickAnchorFallback(active, state.forwardCache)
        OvertakeCore.resetCandidate(state)
        OvertakeCore.resetWin(state)
        if state.leaderId and Logger then
            Logger.warn("overtake", "Líder anterior sumiu — âncora redefinida para id=" .. tostring(anchor.id))
        end
    end

    -- 2) Direção de corrida: velocidade preferida; forward visual como fallback.
    --    Se nada utilizável, recorre ao cache (se fresco). Em último caso,
    --    devolve standings por distância 2D (sem decidir troca de líder).
    local fx, fy = resolveRaceDirection(anchor, cfg)
    local fwdFresh = (fx ~= nil)
    if not fx then
        local cache = state.forwardCache
        if cache and cache.id == anchor.id then
            local maxAge = cfg.FORWARD_CACHE_MAX_AGE_TICKS or 20
            local age    = state.tickCount - (cache.refreshedAt or 0)
            if age <= maxAge then
                fx, fy = cache.fx, cache.fy
            end
        end
    end

    if not fx then
        -- Sem direção utilizável. Não trocamos de líder, mas ainda devolvemos
        -- standings ordenados por distância 2D — mantém o orchestrator e a IA
        -- com contexto (topChasers, runner-up por proximidade) em vez de
        -- "degenerar" para só o líder.
        state.leaderId = anchor.id
        local standings = buildFallbackStandings(active, anchor)
        return {
            leaderId     = anchor.id,
            standings    = standings,
            runnerUp     = findTrailingRunnerUp(standings),
            eliminations = {},
            winConfirmed = false,
            skipped      = true,
        }
    end

    -- 3) Candidato à ultrapassagem + histerese.
    -- Regras:
    --   a) HARD: vantagem >= PASS_DISTANCE_HARD do MESMO candidato por
    --      LEADER_HARD_HOLD_TICKS ticks consecutivos. Filtra spikes
    --      instantâneos por giro rápido do forward (loop / curva fechada).
    --   b) Histerese tolerante: enquanto HOUVER algum candidato à frente por
    --      LEADER_HOLD_TICKS ticks consecutivos, troca usando o candidato
    --      ATUAL (a identidade pode mudar entre ticks — típico de pelotão).
    --   c) Cooldown pós-troca: durante LEADER_CHANGE_COOLDOWN_TICKS após
    --      uma troca, nenhuma nova troca dispara. Acumuladores continuam
    --      contando — quando liberar, troca legítima sai no próximo tick.
    local pending = findPendingCandidate(active, anchor, fx, fy, cfg)
    local effectiveLeader = anchor

    local cooldownTicks  = cfg.LEADER_CHANGE_COOLDOWN_TICKS or 0
    local ticksSince     = state.tickCount - (state.leaderChangedAt or -math.huge)
    local cooldownActive = ticksSince < cooldownTicks

    local function commitLeaderChange(newLeader)
        effectiveLeader        = newLeader
        state.leaderChangedAt  = state.tickCount
        OvertakeCore.resetCandidate(state)
        OvertakeCore.resetWin(state)
    end

    if pending then
        local hardThreshold     = cfg.PASS_DISTANCE_HARD or (cfg.PASS_DISTANCE * 2.5)
        local overrideThreshold = cfg.OVERRIDE_DISTANCE   or (hardThreshold * 1.5)
        local hardHold          = cfg.LEADER_HARD_HOLD_TICKS    or 2
        local softGroupNeeded   = cfg.LEADER_HOLD_TICKS         or 3
        local softCurrentNeeded = cfg.LEADER_MIN_CURRENT_TICKS  or 2
        local isHardCandidate   = pending.longitudinal >= hardThreshold

        -- HARD: histerese curta, mas exige MESMO candidato persistente.
        if isHardCandidate and state.hardCandidateId == pending.id then
            state.hardCandidateTicks = state.hardCandidateTicks + 1
        elseif isHardCandidate then
            state.hardCandidateId    = pending.id
            state.hardCandidateTicks = 1
        else
            state.hardCandidateId    = nil
            state.hardCandidateTicks = 0
        end

        -- SOFT separado em "grupo" (qualquer pending) e "atual" (mesmo id).
        -- Grupo evita trava em pelotão; atual evita candidato novo herdando
        -- ticks acumulados pelos outros.
        state.softGroupTicks = state.softGroupTicks + 1
        if state.candidateId == pending.id then
            state.softCurrentTicks = state.softCurrentTicks + 1
        else
            state.candidateId      = pending.id
            state.softCurrentTicks = 1
        end

        local hardReady = isHardCandidate
            and state.hardCandidateId == pending.id
            and state.hardCandidateTicks >= hardHold

        local softReady = state.softGroupTicks   >= softGroupNeeded
            and state.softCurrentTicks >= softCurrentNeeded

        -- Override durante cooldown: vantagem ENORME (>=OVERRIDE_DISTANCE)
        -- com mesma identidade por hardHold ticks bypassa o bloqueio. Garante
        -- que ultrapassagem clara que ocorra logo após uma troca não fique
        -- represada por até 1s (problema F6).
        local overrideReady = pending.longitudinal >= overrideThreshold
            and state.hardCandidateId == pending.id
            and state.hardCandidateTicks >= hardHold

        local canChange = (not cooldownActive and (hardReady or softReady))
                       or overrideReady

        if canChange then
            local newLeader = findById(active, pending.id)
            if newLeader then commitLeaderChange(newLeader) end
        end
    else
        OvertakeCore.resetCandidate(state)
    end

    -- 4) Recalcula direção em torno do líder efetivo, se mudou.
    if effectiveLeader.id ~= anchor.id then
        local nfx, nfy = resolveRaceDirection(effectiveLeader, cfg)
        if nfx then
            fx, fy   = nfx, nfy
            fwdFresh = true
        else
            -- Novo líder também instável: reusamos fx,fy do anterior; próximo
            -- tick corrige. fwdFresh fica como estava (provavelmente false).
        end
    end

    -- 5) Cache de forward para o líder efetivo. Só atualiza `refreshedAt`
    -- quando o forward é fresco; caso contrário, preserva o timestamp antigo
    -- para que a regra de expiração funcione (cache não rejuvenesce sozinho).
    local prevCache = state.forwardCache
    local refreshedAt
    if fwdFresh then
        refreshedAt = state.tickCount
    elseif prevCache and prevCache.id == effectiveLeader.id then
        refreshedAt = prevCache.refreshedAt
    else
        refreshedAt = state.tickCount  -- novo líder via cache antigo — começa cronômetro
    end
    state.forwardCache = {
        id = effectiveLeader.id,
        fx = fx, fy = fy,
        x  = effectiveLeader.x,
        y  = effectiveLeader.y,
        refreshedAt = refreshedAt,
    }
    state.leaderId = effectiveLeader.id

    -- 6) Standings, runner-up, eliminações.
    local standings   = buildStandingsTable(active, effectiveLeader, fx, fy)
    local runnerUp    = findTrailingRunnerUp(standings)
    local eliminations = collectEliminations(standings, cfg)

    -- 7) Histerese de vitória (gap precisa persistir WIN_CONFIRM_TICKS).
    -- Usa max(-longitudinal, dist) como gap: -longitudinal é o "atraso
    -- pela pista" quando runner-up está trailing, mas em curvas pode ser
    -- negativo (projeção inverte). dist 2D pura é robusta a isso. Pegar
    -- o maior dos dois evita que curvas atrasem a confirmação de vitória
    -- legítima, sem perder a semântica de "distância ao longo da pista".
    local winConfirmed = false
    if #standings == 1 then
        state.winTicks = state.winTicks + 1
        if state.winTicks >= cfg.WIN_CONFIRM_TICKS then
            winConfirmed = true
        end
    elseif runnerUp then
        local gap = math.max(-(runnerUp.longitudinal or 0), runnerUp.dist or 0)
        if gap >= cfg.WIN_DISTANCE then
            state.winTicks = state.winTicks + 1
            if state.winTicks >= cfg.WIN_CONFIRM_TICKS then
                winConfirmed = true
            end
        else
            state.winTicks = 0
        end
    else
        state.winTicks = 0
    end

    return {
        leaderId     = effectiveLeader.id,
        standings    = standings,
        runnerUp     = runnerUp,
        eliminations = eliminations,
        winConfirmed = winConfirmed,
        skipped      = false,
    }
end


-- ------------------------------------------------------------
-- Versão "view-only" (não-host): standings em torno de um líder
-- já decidido externamente. Não toca state.
-- ------------------------------------------------------------

function OvertakeCore.buildView(snapshots, leaderId, cfg)
    local active = filterActive(snapshots)
    if #active == 0 then return emptyResult() end

    local leader = findById(active, leaderId) or active[1]
    local fx, fy = resolveRaceDirection(leader, cfg)
    if not fx then
        local standings = buildFallbackStandings(active, leader)
        return {
            leaderId     = leader.id,
            standings    = standings,
            runnerUp     = findTrailingRunnerUp(standings),
            eliminations = {},
            winConfirmed = false,
            skipped      = true,
        }
    end

    local standings = buildStandingsTable(active, leader, fx, fy)
    return {
        leaderId     = leader.id,
        standings    = standings,
        runnerUp     = findTrailingRunnerUp(standings),
        eliminations = {},
        winConfirmed = false,
        skipped      = false,
    }
end
