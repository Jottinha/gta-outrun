# ROADMAP — Próximos passos técnicos

> Lista priorizada de melhorias para o OUTRUN. Marcado por **impacto x risco**.
> Atualize quando algum item for entregue.

---

## Sprint 0 — Estabilização (atual)

* [x] Documentação completa (`GDD`, `ARCHITECTURE`, `AI_SYSTEM`, etc.).
* [x] Refatoração: client/main, server/main quebrados em módulos focados.
* [x] Strategy Pattern para IA com personalities funcionais.
* [x] Logger centralizado.
* [x] Eventos via `Config.Events`.
* [x] Smoke test in-game após o refator (manual, ver §Teste manual).

---

## Sprint 1 — Polimento de IA

### S1.1 — Rubber-banding ativo

* Aplicar `SetVehicleEngineTorqueMultiplier` no `AIController.Tick` conforme
  os campos `rubberBand.*` da Strategy.
* **Esforço**: P
* **Risco**: M — alterar torque pode causar comportamento errático em curva.
  Calibrar com vídeo gravado por 1 hora de teste.
* **Aceite**: NPC perseguidor a 250 m abaixo do líder ganha visivelmente
  velocidade; NPC líder a 300 m acima freia.

### S1.2 — Personalidades melhor diferenciadas

* `Aggressive` deve furar sinal e empurrar tráfego no `CHASER_CLOSE`.
* `Precise` deve frear corretamente em curvas (driving style com flag
  `avoid vehicles`).
* **Esforço**: P
* **Aceite**: vídeo de NPC `precise` vs `aggressive` no mesmo trecho mostra
  diferença visual clara.

### S1.3 — Recuperação inteligente

* Hoje `RECOVERY` direciona pro vehicle node mais próximo. Em becos sem saída,
  o NPC fica preso de novo.
* Solução: ao falhar a recuperação 2 vezes seguidas, fazer teleporte discreto
  para o vehicle node mais próximo **atrás da câmera do líder**.
* **Esforço**: M
* **Aceite**: NPC nunca passa mais de 20 s em `RECOVERY`.

---

## Sprint 2 — Validação server-side (precursor de MP)

### S2.1 — Tornar `race_logic.lua` "puro"

* Remover dependências de nativas (passar `pos`/`forward` por parâmetro).
* Mover para `shared_scripts` no `fxmanifest`.
* **Esforço**: M
* **Risco**: refator profundo, exige verificação cuidadosa.

### S2.2 — Snapshots de jogadores

* Adicionar `outrun:server:UpdatePlayerSnapshot` enviando
  `{pos, forward, speed}` a cada 200 ms.
* Server mantém último snapshot por jogador.
* **Esforço**: M.

### S2.3 — Liderança autoritativa no server

* Server executa `RaceLogic.ResolveLeader` com base nos snapshots.
* Cliente para de mandar `UPDATE_LEADER`; só recebe.
* **Esforço**: P (depende de S2.1 e S2.2).

### S2.4 — Eliminação autoritativa no server

* Server detecta e dispara `BeSpectator`.
* Remove a viagem de ida-e-volta `client → server → client`.
* **Esforço**: P.

---

## Sprint 3 — Multiplayer real

### S3.1 — Network ownership-aware AI

* `AIController.Tick` confere `NetworkHasControlOfEntity`.
* **Esforço**: M.

### S3.2 — Promoção de AI Host

* Server escolhe novo AI Host se o atual cair.
* **Esforço**: M.

### S3.3 — Sincronização do countdown

* Server envia `startsAt`. Cada client calcula localmente.
* **Esforço**: P.

### S3.4 — `vehicleNetId` no broadcast

* Server inclui `vehicleNetId` em `LobbyUpdated` após spawn.
* Permite que outros clients identifiquem qual carro é qual.
* **Esforço**: P.

---

## Sprint 4 — Persistência QBCore

### S4.1 — Salvar histórico de campeonato

* Após `END_SCREEN`, persistir em tabela MySQL via `oxmysql`:
  `outrun_championships(id, host_citizenid, ts, winner_citizenid, scores_json)`.
* **Esforço**: P.

### S4.2 — Ranking global

* Tela acessível via `/outrun rank` mostra top N por wins, win rate, KDR
  (kill-distance-ratio?).
* **Esforço**: M.

---

## Sprint 5 — Qualidade

### S5.1 — Testes unitários para `race_logic`

* Após S2.1, `race_logic.lua` é puro e testável fora do FiveM.
* Suite mínima: `Dist2D`, `ResolveLeader` (vários cenários: empate, troca,
  flapping), `BuildStandings`.
* **Esforço**: M.

### S5.2 — Linter (luacheck) no CI

* Configurar `.luacheckrc` com globals do FiveM e do projeto.
* Rodar no GitHub Actions a cada push.
* **Esforço**: P.

### S5.3 — Métricas runtime

* Exposição de tempo gasto em `AIController.Tick` e `RaceLogic.tick`.
* Aviso no log se `tick > 16ms` (mais que um frame).
* **Esforço**: P.

---

## Backlog (não priorizado)

* Modo "Time trial" (1 carro, melhor volta).
* Modo "Drag" (linha reta, sem eliminação).
* Power-ups (turbo, EMP).
* Replays de momento (último 30 s).
* Sistema de XP/dinheiro integrado ao QBCore.
* Suporte a `qb-garages`: jogador usa o próprio carro da garagem.
* Carros liberáveis por pontuação.
* Skins de NPC mais variadas.

---

## Pontos que **precisam** ser testados antes de cada release

Lista mínima de smoke test manual após qualquer refator estrutural:

1. `/outrun` abre o lobby.
2. Adicionar 3 NPCs `aggressive` + 1 carro do jogador `kuruma`.
3. Marcar pronto e iniciar.
4. Grid F1 alinhado, countdown roda, GO funciona.
5. Acelerar e tomar liderança — barra muda para verde + swoosh toca.
6. Ficar parado — barra vai para vermelho, pisca em 80%, ouve beep.
7. Ficar a 500 m → vira espectador, câmera orbital funciona.
8. NPC eliminado some.
9. Quando líder abrir 500 m → fim da rodada, placar aparece.
10. Após 10 s, próxima rodada inicia em novo spawn node.
11. Ao bater a meta de pontos → end screen com vencedor.
12. Fechar end screen volta ao freeroam normal.
13. Tráfego volta a aparecer (toggle deve ter resetado).
