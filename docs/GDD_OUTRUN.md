# GDD — Projeto OUTRUN (FiveM / QBCore)

> **Sobre este documento.** Este GDD é a *fonte da verdade* das regras de design do
> modo OUTRUN. Ele descreve o que o jogo deve fazer; o estado real da
> implementação fica em [`ARCHITECTURE.md`](ARCHITECTURE.md) e
> [`ROADMAP.md`](ROADMAP.md). Quando o GDD descrever algo ainda não
> implementado, há um aviso explícito `> Status: planejado`.

---

## 1. Visão geral

OUTRUN é um modo de corrida arcade estilo *Gato e Rato* (inspiração: NFS
Underground 2) em mundo aberto (Los Santos). Os corredores largam juntos. Quem
toma a frente vira o **Líder**. O objetivo do Líder é abrir **500 m** do segundo
colocado. Os demais perseguem para roubar a liderança. Quem ficar a 500 m do
Líder é **eliminado**. A rodada termina quando o Líder vence ou resta apenas um.
Um sistema de campeonato em rodadas define o grande vencedor.

A primeira release é **single-player no host** (humano + NPCs). A arquitetura é
preparada para multiplayer futuro (ver [`MULTIPLAYER_PLAN.md`](MULTIPLAYER_PLAN.md)).

---

## 2. Requisitos

### 2.1 Funcionais (RF)

| ID    | Descrição                                                                                              | Implementado |
|-------|--------------------------------------------------------------------------------------------------------|--------------|
| RF01  | Comando `/outrun` abre a NUI principal                                                                 | ✅           |
| RF02  | Criar salas com meta de pontos configurável (50/100/200)                                               | ✅           |
| RF03  | Host adiciona NPCs e escolhe veículo + personalidade                                                   | ✅           |
| RF03b | Host escolhe seu próprio veículo a partir de lista pré-definida                                        | ✅           |
| RF04  | Sistema de "Pronto" (Ready) bloqueia o "Iniciar" até todos confirmarem                                 | ✅           |
| RF05  | Teleporte e alinhamento em **grid F1** (duas colunas, stagger longitudinal)                            | ✅           |
| RF06  | Veículos congelados (`FreezeEntityPosition`) durante a contagem regressiva                             | ✅           |
| RF07  | Cálculo de liderança em tempo real (Dot Product, 2D)                                                   | ✅           |
| RF08  | Eliminação de quem ficar > 500 m do Líder → vira espectador                                            | ✅           |
| RF09  | Vitória do Líder ao abrir > 500 m do 2º colocado                                                       | ✅           |
| RF10  | Pontuação por posição: 10 / 8 / 6 / 4 / 2                                                              | ✅           |
| RF11  | Rodada Bônus (Polícia) com sorteio em cima do líder do campeonato                                      | ✅           |
| RF12  | Personalities de NPC (`balanced`/`aggressive`/`precise`) afetam comportamento                          | ✅ (via Strategy) |
| RF13  | Rubber-banding (catch-up via torque)                                                                   | ⏳ planejado |
| RF14  | Validação server-side da liderança (anti-desync)                                                       | ⏳ planejado |

### 2.2 Não-funcionais (RNF)

* **RNF01** — A lógica de IA roda no client do *Host* (latência zero).
* **RNF02** — Distâncias atualizadas a cada `Config.Race.DISTANCE_UPDATE_INTERVAL` (50 ms).
* **RNF03** — Estado da sala vive no server (persistência em memória durante a sessão).
* **RNF04** — Anti-stuck só ativa após `Config.AI.STUCK_WARMUP_MS` (5 s) depois da largada.
* **RNF05** — Distâncias em **2D** (ignorar Z) para evitar bugs em pontes/túneis.

---

## 3. Estados e fluxos

### 3.1 Máquina de estados da sala

```
LOBBY ─▶ SPAWN_GRID ─▶ COUNTDOWN ─▶ RACING ─▶ ROUND_RESULT
                                                  │
                                                  ▼
                                       CHECK_CHAMPIONSHIP
                                          │            │
                          (sem campeão) ◀─┘            └─▶ END_SCREEN
                                  │
                                  ▼
                              SPAWN_GRID  (loop)
```

### 3.2 Fluxo do jogador

1. Digita `/outrun`.
2. Acessa lobby ▸ define meta de pontos ▸ adiciona NPCs ▸ escolhe carro.
3. Clica **PRONTO** ▸ Host clica **INICIAR**.
4. Veículos spawnam em grid F1 ▸ countdown 5..GO.
5. Corre ▸ alguém abre 500 m ▸ rodada acaba.
6. HUD mostra placar por 10 s ▸ próxima rodada começa em um spawn node novo.
7. Loop até alguém somar a meta de pontos ▸ tela de vencedor.

---

## 4. Regras de negócio

### 4.1 Liderança

Não há checkpoints. A liderança é calculada por **distância longitudinal** ao
vetor frontal do líder atual:

* Para cada candidato a líder, projeta-se o vetor `candidato - líder` sobre o
  `forward` do líder. Se essa projeção for maior que
  `Config.Race.LEADER_PASS_DISTANCE` (4 m), o candidato passou de fato.
* `Config.Race.LEADER_MAX_Z_DIFF` (8 m) impede troca de líder quando os carros
  estão em altitudes muito diferentes (ponte vs túnel).
* O algoritmo é iterativo: depois de eleger um novo líder, recalcula a partir
  dele (resolve o caso de vários carros à frente no mesmo instante).
* Em empate longitudinal, ganha o de menor distância lateral.

### 4.2 Pontuação e eliminação

* **Eliminação**: `dist2D(participante, líder) >= Config.Race.ELIMINATION_DISTANCE`.
* **Vitória da rodada**: `dist2D(líder, 2º) >= Config.Race.WIN_DISTANCE`.
* **Espectador**: jogador eliminado entra em câmera orbital no líder.
* **Pontuação fixa** (`Config.Scoring`): 1º=10, 2º=8, 3º=6, 4º=4, 5º=2.
* **Ordem final da rodada**: participantes ainda ativos pela posição atual,
  seguidos por eliminados em **ordem inversa de eliminação**
  (último eliminado fica mais bem colocado).

### 4.3 Rodada Bônus (Polícia)

* Probabilidade `Config.BonusRound.TRIGGER_PROBABILITY` (default 15%) de
  ocorrer no início de cada nova rodada.
* Só dispara se já existir um líder claro no campeonato.
* O líder absoluto recebe `Config.BonusRound.WANTED_LEVEL` (4 estrelas).
* Demais participantes recebem `SetPoliceIgnorePlayer(true)` para a polícia não
  interferir.
* Ao final da rodada, `ClearPlayerWantedLevel` reseta tudo.

---

## 5. UI / NUI

### 5.1 Lobby

* **Painel esquerdo**: meta de pontos, "Meu carro", adicionar NPC (modelo +
  personality), toggle de tráfego.
* **Centro**: lista de participantes com nome, modelo do carro e bolinha de
  Pronto (vermelho/verde).
* **Rodapé**: botões **PRONTO** / **INICIAR CORRIDA** (bloqueado até todos
  prontos) / **✕** fechar.

### 5.2 HUD da corrida

Minimalista, canto superior direito.

* **Barra única**, cor depende do papel atual:
  * **Líder** ▸ verde, enche conforme abre distância do 2º. Cheia ⇒ vitória.
  * **Perseguidor** ▸ vermelho, enche conforme fica para trás do Líder.
    Cheia ⇒ eliminação.
* Em `>= Config.HUD.DANGER_THRESHOLD_PERCENT` (80%) a barra pisca e dispara um
  *beep* cardíaco com frequência crescente.
* Texto da posição (`LÍDER` / `2º` / `3º`) acima da barra.
* Texto de distância atual abaixo (`123m / 500m`).
* Mudança de liderança toca um *swoosh* curto.

### 5.3 Round result e End screen

* `round-result`: top da rodada e placar geral, fica visível por 10 s.
* `end-screen`: nome do campeão em destaque, classificação final completa,
  botão de fechar.

---

## 6. Sistema de IA

> Detalhes técnicos completos em [`AI_SYSTEM.md`](AI_SYSTEM.md).

### 6.1 Máquina de estados (FSM)

Os modos reais usados pela IA hoje:

| Modo            | Comportamento                                                                 |
|-----------------|-------------------------------------------------------------------------------|
| `GRID`          | Carro congelado, sem tarefa de direção                                        |
| `CHASE`         | Persegue líder com `TaskVehicleChase` quando dist > `CHASE_CLOSE_DISTANCE`    |
| `CHASER_CLOSE`  | Subfase de ultrapassagem: mira ponto à frente do líder via `TaskVehicleDriveToCoord` |
| `EVADE`         | Líder foge: alvo dinâmico à frente, com viés contra o 2º colocado             |
| `RECOVERY`      | Tasks limpas + drive lento até `vehicle node` próximo (sem teleporte)         |
| `ELIMINATED`    | Removido do conjunto ativo                                                    |

### 6.2 Strategy Pattern

A personalidade do NPC (`balanced` / `aggressive` / `precise`) é uma
*Strategy* que decide:

* Driving style (`SetDriveTaskDrivingStyle`) por modo;
* Velocidade-alvo de fuga/recuperação;
* Threshold de troca CHASE → CHASER_CLOSE;
* Multiplicadores de rubber-banding (quando implementado).

Adicionar uma nova IA = criar uma nova Strategy e registrá-la na Factory.
Não exige editar o `AIController`.

### 6.3 Rubber-banding (catch-up)

> Status: **planejado** — interface no `AIStrategy` já reserva o ponto de
> extensão, mas o efeito ainda não é aplicado no veículo.

Especificação:

* NPC líder abrindo > 300 m do 2º → `SetVehicleEngineTorqueMultiplier(veh, 0.8)`.
* NPC perseguidor > 250 m atrás → `SetVehicleEngineTorqueMultiplier(veh, 1.5)`.
* Valores resetam quando a distância volta à normalidade.

### 6.4 Anti-stuck

* Warm-up de `Config.AI.STUCK_WARMUP_MS` (5 s) após `ReleaseGrid()`.
  Antes disso, qualquer NPC parado é considerado "ainda acelerando".
* Gatilho: `GetEntitySpeed(veh) < Config.AI.STUCK_SPEED_THRESHOLD` por
  `Config.AI.STUCK_TIME_THRESHOLD_MS` acumulados.
* Recuperação **sem teleporte**: `ClearPedTasks` + `TaskVehicleDriveToCoord`
  até um vehicle node próximo, em baixa velocidade.
* Saída: ao superar `STUCK_SPEED_THRESHOLD` novamente, volta a CHASE/EVADE.

### 6.5 Mira de fuga adaptativa

Quando o líder está praticamente parado (`< 2.0 m/s`), o perseguidor mira
**150 m à frente da direção apontada pelo líder** em vez da posição exata, para
não "alcançar e estacionar" ao lado dele (o que dispararia anti-stuck).
> Status: documentado no GDD, **a implementação atual já mira em coord à frente
> do líder na sua direção**, então o efeito prático equivalente está coberto.

---

## 7. Arquitetura de rede

> Visão completa em [`ARCHITECTURE.md`](ARCHITECTURE.md) e
> [`MULTIPLAYER_PLAN.md`](MULTIPLAYER_PLAN.md).

### 7.1 Separação de responsabilidades

* **Server** — fonte da verdade: salas, pontuação, escolha do spawn node,
  decisão da Rodada Bônus, eventos de transição de estado.
* **Client do Host** — orquestração da corrida: spawna entidades, roda IA, faz
  cálculo de liderança *local* e reporta ao server.
* **Demais clients** — recebem broadcasts (líder, fim de rodada, end screen).
  Atualmente o single-player coloca o jogador como Host.

### 7.2 Eventos de rede

Todos os nomes vivem em `Config.Events.Server` / `Config.Events.Client`.

| Evento                                           | Direção        | Quando                                              |
|--------------------------------------------------|----------------|-----------------------------------------------------|
| `outrun:server:CreateLobby`                      | C → S          | `/outrun` cria sala                                 |
| `outrun:server:RequestLobbyState`                | C → S          | Reabrir UI com sala já criada                       |
| `outrun:server:AddNPC`                           | C → S          | Host adiciona NPC ao lobby                          |
| `outrun:server:SetCar`                           | C → S          | Host troca o próprio veículo                        |
| `outrun:server:ToggleReady`                      | C → S          | Jogador marca/desmarca pronto                       |
| `outrun:server:StartRace`                        | C → S          | Host inicia a corrida                               |
| `outrun:server:RaceStarted`                      | C → S          | Host avisa que largada ocorreu                      |
| `outrun:server:UpdateLeader`                     | C → S          | Host informa novo líder                             |
| `outrun:server:RoundEnd`                         | C → S          | Host envia classificação da rodada                  |
| `outrun:client:SpawnVehicles`                    | S → C(host)    | Server pede ao host para spawnar                    |
| `outrun:client:LobbyCreated` / `LobbyUpdated`    | S → C          | Sincronização do lobby                              |
| `outrun:client:LeaderChanged`                    | S → C          | Broadcast de novo líder                             |
| `outrun:client:PlayerEliminated`                 | C → S          | Host avisa que um jogador foi eliminado            |
| `outrun:client:BeSpectator`                      | S → C          | Server manda o jogador eliminado virar espectador  |
| `outrun:client:RoundResult` / `ShowEndScreen`    | S → C          | Server envia resultados                             |
| `outrun:client:ClearWanted`                      | S → C          | Reset de polícia ao fim da rodada                   |
| `outrun:client:NoActiveLobby`                    | S → C          | Sem sala ao tentar reabrir UI                       |
| `outrun:client:ForceLobbyClose`                  | S → C          | Host caiu, sala destruída                           |
| `outrun:client:Notify`                           | S → C          | Mensagem curta via QBCore Notify                    |

---

## 8. Prevenção de bugs

### 8.1 Bug do eixo Z

* **Problema**: distância 3D contabiliza diferença vertical (ponte vs túnel).
* **Solução implementada**: `RaceLogic.Dist2D` ignora Z; a troca de liderança
  exige `dz <= Config.Race.LEADER_MAX_Z_DIFF`.

### 8.2 Liderança fantasma (desync futuro de MP)

> Status: parcialmente coberto. Hoje só o host calcula, então não há conflito.
> Para MP real, ver [`MULTIPLAYER_PLAN.md`](MULTIPLAYER_PLAN.md) §3.

### 8.3 Spawn quebrado

* O server escolhe um ponto de `Config.SpawnNodes` (lista curada manualmente).
* O client corrige para o `GetClosestVehicleNodeWithHeading` mais próximo, com
  heading válido de pista.
* Carros ficam em grid F1 com stagger, evitando empilhamento.

### 8.4 Host desconecta

* `server/disconnect.lua` detecta `playerDropped`. Se for o host, todos os
  clients restantes recebem `ForceLobbyClose`, e o registro da sala é apagado
  (sem memory leak).

---

## 9. Estrutura de arquivos

```text
[outrun]/outrun/
├── fxmanifest.lua
├── config.lua                      # Config global (compartilhado client/server)
├── shared/
│   └── logger.lua                  # Logger com níveis e prefixo
├── server/
│   ├── main.lua                    # Bootstrap: registra handlers de eventos
│   ├── rooms.lua                   # Repositório de salas (Rooms)
│   ├── round_manager.lua           # Início/fim de rodada, championship, bonus
│   └── disconnect.lua              # playerDropped handler
├── client/
│   ├── main.lua                    # Bootstrap: comando + wiring de handlers
│   ├── race_state.lua              # Estado local da corrida (RaceState)
│   ├── race_logic.lua              # Dot product, dist2D, standings
│   ├── race_orchestrator.lua       # Orquestra spawn → countdown → tick → fim
│   ├── grid.lua                    # Cálculo do grid F1
│   ├── spawn.lua                   # Criação de veículos + peds NPC
│   ├── nui_bridge.lua              # Wrapper de SendNUIMessage + callbacks
│   ├── spectator.lua               # Câmera orbital para eliminados
│   └── ai/
│       ├── ai_controller.lua       # Loop + state machine framework
│       └── ai_strategy.lua         # Base, Balanced/Aggressive/Precise, Factory
├── html/
│   ├── index.html
│   ├── style.css
│   └── app.js
└── docs/
    ├── GDD_OUTRUN.md               # Este arquivo
    ├── ARCHITECTURE.md
    ├── AI_SYSTEM.md
    ├── MULTIPLAYER_PLAN.md
    ├── CODE_GUIDELINES.md
    └── ROADMAP.md
```

---

## 10. Infraestrutura QBCore (Freeroam / Racing)

O servidor adota o **QBCore** como base, mas opera no modo Freeroam (sem
mecânicas de roleplay).

### 10.1 Módulos mantidos

* **Banco de dados**: `oxmysql`
* **Núcleo**: `qb-core`
* **Players**: `qb-multicharacter`, `qb-clothing` ou `illenium-appearance`, `qb-spawn`
* **Economia**: `qb-inventory`, `qb-banking`
* **Veículos**: `qb-garages`, `qb-customs`, `qb-carmenu`

### 10.2 Módulos desativados

* Empregos: `qb-policejob`, `qb-ambulancejob`, `qb-mechanicjob`, `qb-taxi`, `qb-tow`
* Crime/gangues: `qb-bankrobbery`, `qb-storerobbery`, `qb-drugs`, `qb-weed`, `qb-prison`
* Imóveis: `qb-cityhall`, `qb-houses`, `qb-apartments`

### 10.3 Ajustes de regra

1. Desativar fome/sede em `[qb] > qb-smallresources > client > survival.lua`.
2. Ocultar métricas de fome/sede/estresse no `qb-hud`.
3. `qb-vehiclekeys` ajustado para dar chave automática ao retirar carro da
   garagem.

---

## 11. Convenções e adendos

### 11.1 Resolução de liderança

* Troca de líder exige *buffer longitudinal* mínimo
  (`Config.Race.LEADER_PASS_DISTANCE`) para evitar flapping lateral.
* Iteração até o pelotão estabilizar: quem está mais à frente após a iteração
  fica como líder.
* Após resolvida a liderança, a ordem dos demais é recalculada por distância 2D
  do líder. O 2º colocado é o perseguidor relevante para a IA.

### 11.2 Spawn nodes configuráveis

* `Config.SpawnNodes` é curada manualmente.
* Server escolhe um ponto da lista a cada rodada.
* Client corrige para o `vehicle node` mais próximo com heading válido.

### 11.3 Grid F1

* Duas colunas com stagger longitudinal.
* `Config.Race.GRID_ROW_SPACING`, `GRID_COLUMN_SPACING`, `GRID_STAGGER_SPACING`
  parametrizam o desenho.
* Funciona para 1 jogador, jogador + N NPCs e cenários multiplayer futuros.
