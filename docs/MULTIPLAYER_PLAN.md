# MULTIPLAYER_PLAN — Preparação para Multiplayer

> O modo OUTRUN nasce single-player (humano + NPCs no host), mas a arquitetura
> precisa permitir multiplayer real sem retrabalho profundo. Este documento
> lista **o que já está pronto, o que falta, e quais armadilhas evitar**.

---

## 1. Visão geral

O FiveM já provê *Network Ownership* de entidades via OneSync. O desafio de MP
no OUTRUN não é "como spawnar carro em outros clients", e sim:

1. **Autoridade de estado** — quem decide quem é o líder?
2. **Sincronização da IA** — quem roda a FSM dos NPCs e como os demais clients
   enxergam o carro?
3. **Replicação de eventos de gameplay** — eliminação, fim de rodada,
   transição de UI.

---

## 2. O que já está pronto

| Item                                              | Status                                                   |
|---------------------------------------------------|----------------------------------------------------------|
| Estado da sala centralizado no server             | ✅ `server/rooms.lua` é fonte da verdade                 |
| Eventos de rede nomeados em `Config.Events`       | ✅                                                       |
| Server escolhe spawn node e bonus round           | ✅ `server/round_manager.lua`                            |
| Server distribui pontuação                        | ✅                                                       |
| Server detecta desconexão do host e fecha sala    | ✅ `server/disconnect.lua`                               |
| Cliente avisa o server quando líder muda          | ✅ `outrun:server:UpdateLeader`                          |
| Server faz broadcast de novo líder                | ✅ `outrun:client:LeaderChanged`                         |
| HUD desacoplada de quem é o jogador (usa `myId`)  | ✅ — qualquer client renderiza a barra correta para si  |
| Spectator se anexa a `leaderVeh` (não a `myVeh`)  | ✅                                                       |

---

## 3. O que falta para MP completo

### 3.1 Validação server-side da liderança

**Hoje**: client (host) calcula e o server só aceita.
**Risco em MP**: client adulterado afirma ser líder.

**Plano**:

1. Cada client humano envia *snapshot* da própria posição ao server
   periodicamente (ex.: a cada 200 ms via `Config.Events.Server.UPDATE_LEADER`,
   carregando `myPos` além do `leaderId` candidato).
2. Server mantém últimos snapshots de todos.
3. Server roda `RaceLogic.ResolveLeader` (mesmo algoritmo) com base nos
   snapshots e *confirma* o líder.
4. Broadcast do líder validado.

Para isso, `race_logic.lua` precisa ser **shared** (carregável em ambos os
lados). A versão atual depende de nativas (`GetEntityCoords`,
`GetEntityForwardVector`), então será preciso uma camada que receba
`{pos, forward}` por parâmetro.

> Estimativa de esforço: M — exige refator de `race_logic.lua` para aceitar
> *snapshots* em vez de ler nativas direto.

### 3.2 IA com network ownership consciente

**Hoje**: só o host roda a FSM. Demais clients veem o carro andando via
OneSync, mas se o host fizer migração de ownership (ex.: distância de scope),
a IA "congela".

**Plano**:

1. Em `AIController.Tick`, verificar `NetworkHasControlOfEntity(npcVehicle)`
   antes de emitir `Task*`. Se perdeu controle, devolver para o sistema de
   *host migration* (a definir).
2. Definir um **AI Host**: o cliente atualmente responsável pela IA. Pode ser
   o host original. Se ele cair, o server promove outro player.
3. Server expõe `outrun:client:BecomeAiHost` para a promoção.

> Estimativa de esforço: M — exige protocolo de migração.

### 3.3 Replicação de spawn

**Hoje**: `SPAWN_VEHICLES` vai só para o host, que cria as entidades. Em MP, os
outros clients dependem do OneSync para enxergar.

**Plano**:

1. Manter o host como spawner único (evita duplicação).
2. Garantir que o veículo é marcado como `mission entity` (já é) e
   `NetworkRegisterEntityAsNetworked`.
3. Os outros clients precisam apenas saber qual `id` (server id) pertence a
   qual carro — server envia esse mapeamento via `LobbyUpdated` com
   `participants[].vehicleNetId` após spawn.

> Estimativa de esforço: S.

### 3.4 Eliminação confiável

**Hoje**: o host detecta "X está a 500m do líder" e dispara
`outrun:client:PlayerEliminated` → server → `BeSpectator` ao alvo.

**Risco em MP**: se o host alegar "Y está eliminado" falsamente, o server
aceita. Para evitar isso, o server precisa do snapshot do candidato a
eliminado para conferir.

**Plano**: junto com a validação de liderança (§3.1), o server tem snapshots e
faz a própria conta de eliminação.

> Estimativa de esforço: S (depende de §3.1).

### 3.5 Sincronização de countdown

**Hoje**: o host roda o countdown localmente e dispara `RACE_STARTED` ao final.

**Risco em MP**: jitter de rede pode fazer outros clients ainda estarem no
countdown enquanto o host já largou.

**Plano**:

1. Server envia `startsAt = GetGameTimer() + delay` como timestamp absoluto.
2. Cada client calcula seu próprio countdown a partir desse timestamp,
   sincronizando largada.

> Estimativa de esforço: S.

---

## 4. Decisões que **não** podem ser tomadas para single-player

Estas escolhas, se feitas pensando só no single-player, atrapalham MP depois.
A arquitetura atual já evita todas elas.

* ❌ **Salvar líder na variável local do client** sem confirmar com server.
* ❌ **Aplicar pontuação no client** e enviar "ganhei X pontos" — dá pra
  trapacear. Toda pontuação é decidida pelo server hoje.
* ❌ **Lock de input direto no veículo do jogador** (ex.: `DisableControlAction`
  global). Hoje só `FreezeEntityPosition` no veículo do jogador — funciona em
  MP por entity.
* ❌ **Tempo via `os.time()` no client**. Hoje usamos `GetGameTimer()`
  consistente entre clients para timers locais e o **server** decide
  ordens absolutas.
* ❌ **Identidade por nome de player.** Sempre `GetPlayerServerId(PlayerId())`.

---

## 5. Modelo de propriedade (Ownership)

| Estado / Entidade           | Quem possui (autoritativo)                                      |
|-----------------------------|------------------------------------------------------------------|
| Lista de salas              | Server                                                           |
| Pontuação                   | Server                                                           |
| Estado da sala              | Server                                                           |
| Spawn node escolhido        | Server                                                           |
| Líder atual                 | **Hoje**: client (host) → server confirma. **MP**: server valida |
| Posição do jogador X        | Client X (envia snapshot)                                        |
| Veículo do NPC              | Client Host (entity owner)                                       |
| FSM da IA                   | Client Host                                                      |
| Câmera / HUD                | Client local                                                     |

---

## 6. Glossário de termos MP

* **Host**: o client que criou a sala. Hoje é o player que digitou `/outrun`.
* **AI Host**: o client responsável por rodar a FSM dos NPCs. Atualmente
  igual ao Host.
* **Snapshot**: pacote `{pos, forward, speed, ts}` enviado pelo client ao
  server.
* **Tick autoritativo**: o tick do server que valida liderança e eliminação
  com base nos snapshots mais recentes.

---

## 7. Próximos passos sugeridos (ordem de impacto)

1. Tornar `race_logic.lua` puro (aceitar snapshots, não chamar nativas).
2. Implementar `RaceLogic` no server (mesmo arquivo, carregado em ambos os
   lados via `shared_scripts`).
3. Adicionar protocolo de snapshot (`UPDATE_PLAYER_SNAPSHOT`).
4. Mover decisão de eliminação para o server.
5. Implementar `AI Host migration`.
6. Adicionar `vehicleNetId` ao broadcast de participantes.
