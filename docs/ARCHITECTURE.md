# ARCHITECTURE — Projeto OUTRUN

> Este documento descreve **como o código está organizado hoje**, com foco em
> responsabilidades de cada módulo, ordem de carga e fluxos críticos.
> Para regras de jogo, ver [`GDD_OUTRUN.md`](GDD_OUTRUN.md). Para o que muda
> rumo a multiplayer, ver [`MULTIPLAYER_PLAN.md`](MULTIPLAYER_PLAN.md).

---

## 1. Princípios

1. **Server é fonte da verdade** para tudo que envolve estado de sala.
   Client é UI + simulação local + reporting.
2. **Client do Host** roda a IA dos NPCs e o cálculo de liderança para
   minimizar latência. O server confirma e replica.
3. **Módulos por domínio**, não por camada. Cada arquivo tem **uma**
   responsabilidade clara nomeada no topo.
4. **Sem strings cruas** de evento de rede: tudo passa por `Config.Events`.
5. **Logger central** (`shared/logger.lua`) — nunca `print` direto.
6. **Globais por módulo** seguindo convenção FiveM: `Module = {}` no topo,
   funções como `Module.X`. Estado privado fica em `local` dentro do arquivo.

---

## 2. Diagrama de módulos

```
                ┌─────────────────────────┐
                │       config.lua        │   (shared)
                └────────────┬────────────┘
                             │
                ┌────────────▼────────────┐
                │   shared/logger.lua     │   (shared)
                └────────────┬────────────┘
                             │
        ┌────────────────────┴────────────────────┐
        │                                         │
┌───────▼────────┐                       ┌────────▼─────────┐
│    SERVER      │                       │      CLIENT      │
└───────┬────────┘                       └────────┬─────────┘
        │                                         │
        │  rooms.lua          ◀───┐               │  race_state.lua
        │  round_manager.lua  ────┘               │  race_logic.lua
        │  disconnect.lua                         │  grid.lua
        │  main.lua  (bootstrap)                  │  spawn.lua
        │                                         │  nui_bridge.lua
        │                                         │  spectator.lua
        │                                         │  ai/ai_strategy.lua
        │                                         │  ai/ai_controller.lua
        │                                         │  race_orchestrator.lua
        │                                         │  main.lua  (bootstrap)
        │                                         │
        └────────────────── NET ─────────────────►│
                            ◀─                    │
```

---

## 3. Responsabilidades por arquivo

### 3.1 Compartilhado

| Arquivo               | Responsabilidade                                                   |
|-----------------------|--------------------------------------------------------------------|
| `config.lua`          | Toda configuração (timings, regras, eventos, modelos, personalidades) |
| `shared/logger.lua`   | `Logger.debug/info/warn/error` com prefixo `[OUTRUN]`              |

### 3.2 Server

| Arquivo                    | Responsabilidade                                                                 |
|----------------------------|----------------------------------------------------------------------------------|
| `server/rooms.lua`         | Repositório das salas: CRUD + lookups por host/player                            |
| `server/round_manager.lua` | `startRound`, `endRound`, scoring, championship check, sorteio da Rodada Bônus  |
| `server/disconnect.lua`    | `playerDropped`: destrói sala se host saiu, remove participante se não-host      |
| `server/main.lua`          | Registra handlers de `Config.Events.Server.*` e delega para `Rooms`/`RoundManager` |

### 3.3 Client — núcleo

| Arquivo                       | Responsabilidade                                                            |
|-------------------------------|-----------------------------------------------------------------------------|
| `client/race_state.lua`       | Container do estado local da corrida (`RaceState`) + reset/clear            |
| `shared/overtake_core.lua`    | **Lógica pura de ultrapassagem** — `newState`, `tick`, `buildView` (sem FiveM) |
| `client/race_logic.lua`       | Adapter de `OvertakeCore` — coleta snapshots de FiveM, expõe `tick`, `buildView`, `Dist2D`, `StartLoop`, `StopLoop` |
| `client/grid.lua`             | `Grid.computeOffset(index, total)` — posicionamento F1                      |
| `client/spawn.lua`            | `Spawn.spawnAll(payload)` — cria veículos + peds NPC + warp jogador        |
| `client/nui_bridge.lua`       | `Nui.send(action, data)`, `Nui.setFocus`, registro central de callbacks     |
| `client/spectator.lua`        | Câmera orbital + `BeSpectator` handler                                      |
| `client/race_orchestrator.lua`| Coordena spawn → countdown → launch → tick → endRound (chama `AIController`, `RaceLogic`, `Nui`) |
| `client/main.lua`             | Bootstrap: comando `/outrun`, NUI callbacks, handlers de eventos do server  |

### 3.4 Client — IA

| Arquivo                       | Responsabilidade                                                            |
|-------------------------------|-----------------------------------------------------------------------------|
| `client/ai/ai_strategy.lua`   | Strategy Pattern: `Base`, `Balanced`, `Aggressive`, `Precise`, `Factory`    |
| `client/ai/ai_controller.lua` | Registro de NPCs, loop, FSM (GRID/CHASE/CHASER_CLOSE/EVADE/RECOVERY)        |

---

## 4. Ordem de carga (`fxmanifest.lua`)

```text
shared_scripts:
  1. config.lua
  2. shared/logger.lua
  3. shared/overtake_core.lua

server_scripts:
  1. server/rooms.lua
  2. server/round_manager.lua
  3. server/disconnect.lua
  4. server/main.lua

client_scripts:
  1. client/race_state.lua
  2. client/nui_bridge.lua
  3. client/grid.lua
  4. client/race_logic.lua
  5. client/spawn.lua
  6. client/ai/ai_strategy.lua
  7. client/ai/ai_controller.lua
  8. client/spectator.lua
  9. client/race_orchestrator.lua
  10. client/main.lua
```

Dependências respeitadas:

* `ai_controller` depende de `ai_strategy` (Factory) e `race_logic` (`Dist2D`).
* `spawn` depende de `grid` (offsets) e `ai_controller` (registro de NPC).
* `race_orchestrator` depende de tudo acima.

---

## 5. Fluxos críticos

### 5.1 Criar lobby

```
Client (/outrun) ─▶ Nui.send openLobby
                ─▶ NUI Callback createLobby ─▶ Server CREATE_LOBBY
Server (Rooms.create) ─▶ Client LobbyCreated ─▶ Nui.send lobbyCreated
```

### 5.2 Início da corrida

```
Host clica INICIAR
  Client ─▶ Server START_RACE
  Server (RoundManager.start)
    ▸ verifica readys
    ▸ escolhe SpawnNode
    ▸ sorteia bonus round
    ▸ Client SPAWN_VEHICLES (apenas Host)
  HostClient (RaceOrchestrator.spawn)
    ▸ Spawn.spawnAll
    ▸ Countdown 5..1
    ▸ ReleaseGrid + ServerEvent RACE_STARTED
    ▸ AIController.StartLoop  (host)
    ▸ RaceLogic.StartLoop     (todos)
```

### 5.3 Tick da corrida

```
RaceLogic.StartLoop (50 ms)
  ▸ collectSnapshots (FiveM → entries puras)
  ▸ host: OvertakeCore.tick   → {leaderId, standings, runnerUp, eliminations, winConfirmed}
    não-host: OvertakeCore.buildView (líder vem do server via UPDATE_LEADER)
  ▸ callback ─▶ RaceOrchestrator.onTick
       ▸ se líder mudou ─▶ ServerEvent UPDATE_LEADER + Nui leaderChanged
       ▸ atualiza HUD (Nui.send updateHUD; dist nullable)
       ▸ (host) aplica `result.eliminations` ─▶ ServerEvent PLAYER_ELIMINATED
       ▸ (host) se `result.winConfirmed`: endRound(standings) ─▶ ServerEvent ROUND_END
```

**Histerese aplicada no core (config em `Config.Race`):**
- `LEADER_HOLD_TICKS`: ENQUANTO houver algum candidato à frente por N ticks consecutivos, a troca acontece (a identidade do candidato pode mudar entre ticks — tolerante a pelotão).
- `LEADER_PASS_DISTANCE_HARD`: override imediato. Candidato com vantagem ≥ HARD vira líder sem esperar histerese.
- `WIN_CONFIRM_TICKS`: gap `>= WIN_DISTANCE` precisa persistir por N ticks antes de fechar o round.
- `FORWARD_MIN_MAGNITUDE`: se o forward 2D do líder estiver instável (capotamento/salto), reusa o forward cacheado do tick anterior.

**Eliminação por longitudinal, não por dist absoluta:** carros 500m **atrás** (longitudinal ≤ −ELIMINATION_DISTANCE) são eliminados; carros à frente em outro nível (viaduto) não são mais punidos.

**Multi-bot (4–5 NPCs):**
- `EVADE` do líder considera os top-K chasers (`Config.Race.EVADE_CHASERS_CONSIDERED`), não só o runner-up. Vetor de fuga ponderado por 1/dist.
- Cada NPC recebe `chaseSlot` estável no register → offset lateral em `CHASER_CLOSE` (`Config.AI.CHASER_LATERAL_SPACING`) evita que todos converjam no mesmo carrot.
- `RECOVERY` é stagger por slot (`STUCK_TIME_STAGGER_MS`) e cada NPC mira no k-ésimo nó mais próximo (`RECOVERY_NODE_VARIANTS`) — anti-cascata em pelotão preso.
- `CHASE ↔ CHASER_CLOSE` tem histerese assimétrica (`CHASE_CLOSE_DISTANCE` entrada, `CHASE_CLOSE_EXIT_DISTANCE` saída) — anti-flapping na borda.
- Eliminação de NPC: `AIController.SetState(id, ELIMINATED)` deleta ped/vehicle e remove do registry no mesmo tick (sem esperar o loop de IA).

### 5.4 Fim de rodada

```
Host ─▶ Server ROUND_END(results)
Server (RoundManager.endRound)
  ▸ aplica scoring
  ▸ ClearWanted para todos
  ▸ checa champion (score >= pointTarget)
    ↳ sim ─▶ Client ShowEndScreen + Rooms.delete
    ↳ não ─▶ Client RoundResult
            ▸ SetTimeout 10s ─▶ startRound()
```

---

## 6. Decisões arquiteturais importantes

### 6.1 Por que o cálculo de liderança roda no client?

* Latência de física é determinante em arcade racing.
* O server **confirma** a liderança via `UPDATE_LEADER`, mas não recalcula a
  cada frame. Para MP real, o server deve passar a validar
  (ver `MULTIPLAYER_PLAN.md` §3).

### 6.2 Por que a IA roda só no client do Host?

* `RNF01` — latência zero.
* Outros clients enxergam o NPC via OneSync (entity ownership do host).
* Trade-off: se o host migrar, a IA "pisca". Aceitável para a fase atual.

### 6.3 Por que `RaceState` é um objeto global no client?

* É consumido por múltiplos arquivos (`race_orchestrator`, `spectator`,
  `ai_controller` indireto). Em vez de injetar via parâmetro em N pontos,
  vive como singleton no módulo `race_state.lua` com funções `reset()`.
* É só **state**, não tem lógica. Toda lógica fica nos demais módulos.

### 6.4 Por que existe um `nui_bridge.lua`?

* Centraliza `SendNUIMessage` e `RegisterNUICallback`. Facilita logging,
  futura migração de NUI (ex: para `chat:addMessage`) e testes.
* Evita `SendNUIMessage` espalhado em vários arquivos.

### 6.5 Por que separar `grid.lua` de `spawn.lua`?

* `grid.lua` é matemática pura (testável sem o jogo rodando).
* `spawn.lua` interage com nativas (`CreateVehicle`, `CreatePedInsideVehicle`).
* Separar facilita troca futura do layout de grid (ex: drag race em linha
  única, time trial individual).

---

## 7. O que **não** está nesta arquitetura (intencionalmente)

* **Persistência SQL** — pontuação é volátil por sessão. Histórico/win rate
  fica como roadmap quando o campeonato terminar.
* **Sistema de partículas/SFX customizado** — som é browser audio na NUI.
* **Replicação de IA em MP** — depende de OneSync; veja
  [`MULTIPLAYER_PLAN.md`](MULTIPLAYER_PLAN.md).
* **Sistema de itens/power-ups** — fora do escopo do MVP.
