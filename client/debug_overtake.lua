-- ============================================================
--  OUTRUN — Client: DebugOvertake
--
--  Visualização em tempo real da CAIXA DE ULTRAPASSAGEM no mundo.
--  Toggle via /outrun_debug (mesmo comando liga e desliga).
--
--  Single source of truth: TODOS os limiares vêm de RaceLogic.getCfg()
--  (mesma cfg que OvertakeCore.tick consome). A direção da corrida é
--  resolvida via OvertakeCore.resolveDirection — mesma função que o tick
--  usa. Alterar um número em Config.Race.LEADER_* muda o desenho
--  automaticamente, sem reiniciar o recurso.
--
--  Escopo: qualquer player com corrida ativa pode ativar.
--  A visualização usa a entidade de rede do líder, visível para todos.
-- ============================================================

DebugOvertake = {}

local enabled    = false
local renderGen  = 0


-- ------------------------------------------------------------
-- Constantes puramente visuais (não afetam gameplay)
-- ------------------------------------------------------------

-- Linhas empilhadas em vários Z para serem visíveis dentro do carro.
local LINE_Z_LEVELS = { 0.2, 0.8, 1.5 }

-- Cores RGBA.
local COLOR_SOFT     = { 0,   220, 0,   220 }  -- verde: zona SOFT válida
local COLOR_HARD     = { 255, 200, 0,   220 }  -- amarelo: linha HARD (fast-path)
local COLOR_OVERRIDE = { 255, 30,  30,  220 }  -- vermelho: linha OVERRIDE (bypass cooldown)
local COLOR_OUTSIDE  = { 255, 120, 0,   200 }  -- laranja: limites laterais externos
local COLOR_RUNNER   = { 30,  120, 255, 200 }  -- azul: runner-up

-- Padding extra além de OVERRIDE_DISTANCE só para o desenho não terminar
-- exatamente em cima da última linha. Não é constante de jogo.
local VIZ_PADDING = 5.0


-- ------------------------------------------------------------
-- Snapshot mínimo do líder no formato que OvertakeCore espera
-- (mesmo schema que race_logic.lua:collectSnapshots produz)
-- ------------------------------------------------------------

local function snapshotOfVehicle(veh)
    local pos = GetEntityCoords(veh)
    local fwd = GetEntityForwardVector(veh)
    local vel = GetEntityVelocity(veh)
    local speed2d = math.sqrt(vel.x * vel.x + vel.y * vel.y)
    return {
        x = pos.x, y = pos.y, z = pos.z,
        fx = fwd.x, fy = fwd.y,
        vx = vel.x, vy = vel.y,
        speed = speed2d,
    }
end


-- ------------------------------------------------------------
-- Transformações local → mundo
--   localX = longitudinal (forward), localY = lateral (right)
--   right = forward rotacionado 90° clockwise = (fy, -fx)
-- ------------------------------------------------------------

local function localToWorld(snap, fx, fy, longitudinal, lateral)
    local rx, ry = fy, -fx
    return snap.x + longitudinal * fx + lateral * rx,
           snap.y + longitudinal * fy + lateral * ry
end

local function drawStackedLine(x1, y1, baseZ, x2, y2, color)
    for i = 1, #LINE_Z_LEVELS do
        local dz = LINE_Z_LEVELS[i]
        DrawLine(x1, y1, baseZ + dz, x2, y2, baseZ + dz,
                 color[1], color[2], color[3], color[4])
    end
end

local function drawLocalLine(snap, fx, fy, l1, lat1, l2, lat2, color)
    local x1, y1 = localToWorld(snap, fx, fy, l1, lat1)
    local x2, y2 = localToWorld(snap, fx, fy, l2, lat2)
    drawStackedLine(x1, y1, snap.z, x2, y2, color)
end


-- ------------------------------------------------------------
-- Caixa de ultrapassagem (polígono em "T")
--
-- A zona SOFT válida (ver overtake_core.lua findPendingCandidate):
--   * lateral ≤ NEAR_LATERAL          → longitudinal > PASS_DISTANCE_NEAR
--   * NEAR_LATERAL < lateral ≤ MAX    → longitudinal > PASS_DISTANCE
--   * lateral > MAX_LATERAL_FOR_PASS  → IGNORADO
--
-- Vértices (lon, lat) sentido horário (vista de cima, +X=forward, +Y=right):
--      A=(pn, +ln)   B=(pf, +ln)   C=(pf, +lm)   D=(fz, +lm)
--      H=(pn, -ln)   G=(pf, -ln)   F=(pf, -lm)   E=(fz, -lm)
-- ------------------------------------------------------------

local function drawOvertakeBox(snap, fx, fy, cfg)
    local pn = cfg.PASS_DISTANCE_NEAR
    local pf = cfg.PASS_DISTANCE
    local ph = cfg.PASS_DISTANCE_HARD
    local po = cfg.OVERRIDE_DISTANCE
    local ln = cfg.NEAR_LATERAL
    local lm = cfg.MAX_LATERAL_FOR_PASS
    local fz = po + VIZ_PADDING

    -- Perímetro SOFT (verde nas bordas internas, laranja nas externas):
    drawLocalLine(snap, fx, fy,  pn,  ln,  pn, -ln, COLOR_SOFT)    -- H-A: entrada do corredor (PASS_NEAR)
    drawLocalLine(snap, fx, fy,  pn, -ln,  pf, -ln, COLOR_SOFT)    -- G-H: degrau esq. (longitudinal)
    drawLocalLine(snap, fx, fy,  pf, -ln,  pf, -lm, COLOR_SOFT)    -- F-G: degrau esq. (lateral, PASS_FAR)
    drawLocalLine(snap, fx, fy,  pf, -lm,  fz, -lm, COLOR_OUTSIDE) -- E-F: limite lateral esq. (MAX_LATERAL)
    drawLocalLine(snap, fx, fy,  fz, -lm,  fz,  lm, COLOR_OUTSIDE) -- D-E: fundo da viz (OVERRIDE_DISTANCE + pad)
    drawLocalLine(snap, fx, fy,  fz,  lm,  pf,  lm, COLOR_OUTSIDE) -- C-D: limite lateral dir.
    drawLocalLine(snap, fx, fy,  pf,  lm,  pf,  ln, COLOR_SOFT)    -- B-C: degrau dir. (lateral)
    drawLocalLine(snap, fx, fy,  pf,  ln,  pn,  ln, COLOR_SOFT)    -- A-B: degrau dir. (longitudinal)

    -- Linha HARD: vertical em PASS_DISTANCE_HARD atravessando a banda inteira.
    drawLocalLine(snap, fx, fy,  ph,  lm,  ph, -lm, COLOR_HARD)

    -- Linha OVERRIDE: vertical em OVERRIDE_DISTANCE atravessando a banda inteira.
    drawLocalLine(snap, fx, fy,  po,  lm,  po, -lm, COLOR_OVERRIDE)
end


-- ------------------------------------------------------------
-- Marker do runner-up (esfera azul flutuando acima do veículo)
-- ------------------------------------------------------------

local function drawRunnerMarker(veh)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end
    local pos = GetEntityCoords(veh)
    DrawMarker(28,
        pos.x, pos.y, pos.z + 3.0,
        0.0, 0.0, 0.0,
        0.0, 0.0, 0.0,
        1.5, 1.5, 1.5,
        COLOR_RUNNER[1], COLOR_RUNNER[2], COLOR_RUNNER[3], COLOR_RUNNER[4],
        false, false, 2, false, nil, nil, false)
end


-- ------------------------------------------------------------
-- Thread de render — Wait(0) (todo frame). Geração token cancela
-- a thread anterior quando o debug é desligado/religado.
-- ------------------------------------------------------------

local function startRenderThread()
    renderGen = renderGen + 1
    local myGen = renderGen
    Citizen.CreateThread(function()
        while enabled and renderGen == myGen do
            local leaderVeh = RaceState.leaderVeh
            if RaceState.isActive()
               and leaderVeh and DoesEntityExist(leaderVeh) then
                local cfg  = RaceLogic.getCfg()
                local snap = snapshotOfVehicle(leaderVeh)
                local fx, fy = OvertakeCore.resolveDirection(snap, cfg)
                if fx then
                    drawOvertakeBox(snap, fx, fy, cfg)
                end
                drawRunnerMarker(RaceState.runnerUpVeh)
            end
            Citizen.Wait(0)
        end
    end)
end


-- ------------------------------------------------------------
-- API pública
-- ------------------------------------------------------------

function DebugOvertake.setEnabled(on)
    if on == enabled then return end
    enabled = on
    if enabled then
        startRenderThread()
    else
        renderGen = renderGen + 1  -- invalida thread em andamento
    end
end

function DebugOvertake.toggle()
    DebugOvertake.setEnabled(not enabled)
    return enabled
end

function DebugOvertake.isEnabled()
    return enabled
end


-- ------------------------------------------------------------
-- Comando: /outrun_debug (toggle)
-- ------------------------------------------------------------

RegisterCommand("outrun_debug", function()
    local now = DebugOvertake.toggle()
    local msg = now and "[OUTRUN] Debug visual ON" or "[OUTRUN] Debug visual OFF"
    TriggerEvent('QBCore:Notify', msg, now and 'success' or 'primary')
end, false)
RegisterKeyMapping('outrun_debug', 'Ativar/Desativar Debug Outrun', 'keyboard', 'k')