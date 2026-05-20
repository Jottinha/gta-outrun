# AI_SYSTEM — Sistema de IA do OUTRUN

> Como a IA dos NPCs é organizada, como o **Strategy Pattern** desacopla as
> personalidades e como **adicionar uma nova versão de IA** sem mexer no
> controlador.

---

## 1. Visão de alto nível

A IA do OUTRUN é dividida em **duas camadas**:

| Camada           | Arquivo                       | O que decide                                        |
|------------------|-------------------------------|-----------------------------------------------------|
| **Controller**   | `client/ai/ai_controller.lua` | *Quando* mudar de modo (FSM): GRID → CHASE → CHASER_CLOSE → EVADE → RECOVERY → ELIMINATED |
| **Strategy**     | `client/ai/ai_strategy.lua`   | *Como* o NPC se comporta em cada modo: driving style, velocidade, thresholds |

A **personalidade** do NPC (escolhida pelo host no lobby) é apenas um nome
(`balanced` / `aggressive` / `precise`) que a *Factory* resolve para uma
instância de Strategy.

---

## 2. Por que Strategy Pattern aqui?

Antes da refatoração, mudar o comportamento de um perfil exigia editar
`ai_controller.lua` com `if personality == "aggressive" then ...` espalhado.
Problemas:

1. Lógica de personalidade misturada com lógica de FSM.
2. Adicionar uma 4ª personality multiplica os `if`s em vários pontos.
3. Difícil testar isoladamente.

Com Strategy:

* `AIController` só conhece a *interface* `AIStrategy`.
* Cada personalidade é um arquivo/tabela isolada.
* Adicionar nova personality = criar um novo objeto + registrar na Factory.
  **Zero edição no Controller.**

---

## 3. Interface `AIStrategy`

Toda Strategy implementa estes campos:

```lua
-- contract (todas devem expor estes campos)
{
    name                    = string,   -- nome legível para logs
    chaseDrivingStyle       = number,   -- flags para SetDriveTaskDrivingStyle no modo CHASE
    chaseCloseDrivingStyle  = number,   -- idem no modo CHASER_CLOSE (ultrapassagem)
    evadeDrivingStyle       = number,   -- idem no modo EVADE (líder fugindo)
    recoveryDrivingStyle    = number,   -- idem no modo RECOVERY (sem-pressa, navegação)
    evadeSpeed              = number,   -- m/s, velocidade-alvo do líder fugindo
    recoverySpeed           = number,   -- m/s, velocidade-alvo durante recuperação
    chaseCloseThreshold     = number,   -- m, dist 2D abaixo da qual CHASE vira CHASER_CLOSE
    chaseCloseAhead         = number,   -- m, "carrot" à frente do líder no CHASER_CLOSE
    evadeForwardDistance    = number,   -- m, raio do alvo de fuga
    rubberBand              = {         -- coeficientes de catch-up (placeholders, ver Rubber-Band)
        leaderSlowFactor    = number,   -- multiplicador de torque quando líder abre demais
        chaserBoostFactor   = number,   -- multiplicador de torque quando perseguidor cai demais
        leaderThreshold     = number,   -- m, dist em que aplica leaderSlowFactor
        chaserThreshold     = number,   -- m, dist em que aplica chaserBoostFactor
    },
}
```

Não há herança real em Lua — usamos *composition* via merge sobre um perfil
base. Veja `AIStrategy.Base` em `client/ai/ai_strategy.lua`.

---

## 4. Strategies padrão

### 4.1 `Balanced`

Comportamento "normal" do GTA V tunado para corrida.

* Chase: dirigir respeitando o trânsito, mas sem freadas exageradas.
* Evade: rota longa em alta velocidade, com viés de fuga moderado.
* Threshold padrão de ultrapassagem.

### 4.2 `Aggressive`

NPCs que furam sinal, ultrapassam pela contramão e empurram tráfego leve.

* Driving styles com flags de "ignore traffic lights" + "drive fast".
* Threshold de ultrapassagem maior (entra em CHASER_CLOSE de mais longe).
* Velocidade de fuga ligeiramente acima.
* Rubber-band do perseguidor mais intenso (chega mais rápido).

### 4.3 `Precise`

NPCs que prezam por não bater. Usam bem os nodes de estrada, freiam direito.

* Driving styles "follow road" + "avoid vehicles".
* Threshold de ultrapassagem menor (só passa quando seguro).
* Recuperação mais demorada (não corre risco de bater de novo).

---

## 5. Como adicionar uma nova personality

Suponha que queremos uma personality `"reckless"` (kamikaze, sem freios).

### Passo 1 — Definir a Strategy

Em `client/ai/ai_strategy.lua`, depois das strategies existentes:

```lua
AIStrategy.Reckless = AIStrategy.makeFrom(AIStrategy.Aggressive, {
    name                    = "Reckless",
    chaseDrivingStyle       = 786603,
    chaseCloseDrivingStyle  = 786603,
    evadeSpeed              = 95.0,
    chaseCloseThreshold     = 18.0,
    chaseCloseAhead         = 22.0,
    rubberBand              = {
        leaderSlowFactor    = 0.7,
        chaserBoostFactor   = 1.7,
        leaderThreshold     = 280.0,
        chaserThreshold     = 220.0,
    },
})
```

### Passo 2 — Registrar na Factory

Ainda em `client/ai/ai_strategy.lua`, na função `AIStrategy.create`:

```lua
local STRATEGY_BY_NAME = {
    balanced   = AIStrategy.Balanced,
    aggressive = AIStrategy.Aggressive,
    precise    = AIStrategy.Precise,
    reckless   = AIStrategy.Reckless,    -- ◀ adicionar
}
```

### Passo 3 — Expor na NUI (opcional)

Em `html/index.html`, dentro do `<select id="npc-personality">`:

```html
<option value="reckless">Kamikaze</option>
```

Em `html/app.js`, mapear o label se desejar:

```js
const pLabel = {
    balanced: 'Equilibrado',
    aggressive: 'Agressivo',
    precise: 'Preciso',
    reckless: 'Kamikaze',
};
```

Pronto. **Nada no `ai_controller.lua` precisa mudar.**

---

## 6. Como adicionar um novo *modo* de IA (FSM)

Adicionar um modo é mais invasivo que adicionar uma personality. Caso de uso:
um modo `"DEFEND"` em que o líder, ao invés de fugir, freia para causar
acidente no perseguidor.

### Passo 1 — Definir o modo

Em `config.lua` → `Config.States.AI`:

```lua
DEFEND = "DEFEND",
```

### Passo 2 — Implementar o `enter*Role`

Em `client/ai/ai_controller.lua`, criar `enterDefendRole(data, runnerUpVeh)`
seguindo o padrão dos outros `enter*Role`. O comportamento usa
`strategy.defendDrivingStyle` e `strategy.defendSpeed` — adicione esses campos
à interface `AIStrategy`.

### Passo 3 — Adicionar transição no `Tick`

No `AIController.Tick`, adicione a condição que dispara o novo modo. Ex.:

```lua
if isLeader and chaseDist < strategy.defendThreshold then
    enterDefendRole(data, runnerUpVeh)
    return
end
```

### Passo 4 — Documentar

Atualize a tabela §6.1 do `GDD_OUTRUN.md` e a §3 deste documento.

---

## 7. Rubber-banding (catch-up)

> Status: planejado. A Strategy já expõe `rubberBand.*`, mas o efeito ainda
> não é aplicado.

Para ativar, em `AIController.Tick`, depois de calcular `chaseDist`:

```lua
local rb = data.strategy.rubberBand
if isLeader and chaseDist >= rb.leaderThreshold then
    SetVehicleEngineTorqueMultiplier(vehicle, rb.leaderSlowFactor)
elseif (not isLeader) and chaseDist >= rb.chaserThreshold then
    SetVehicleEngineTorqueMultiplier(vehicle, rb.chaserBoostFactor)
else
    SetVehicleEngineTorqueMultiplier(vehicle, 1.0)
end
```

Cuidados:

* O multiplicador é *aplicado por frame* enquanto o NPC está nesse estado.
  Não chame uma única vez na transição — o GTA reseta.
* Em MP, a entity precisa estar sob `NetworkHasControlOfEntity` para a nativa
  surtir efeito.

---

## 8. FSM atual (referência)

```
              ┌───────┐
              │ GRID  │
              └───┬───┘  ReleaseGrid()
                  ▼
              ┌───────┐ isLeader ?  ┌────────┐
              │ CHASE │◀──── não ──▶│ EVADE  │
              └───┬───┘             └────┬───┘
                  │ dist < threshold     │
                  ▼                      │
           ┌──────────────┐              │
           │ CHASER_CLOSE │              │
           └──────┬───────┘              │
                  │                      │
                  └──────────┬───────────┘
                             │ speed < limite por N ms (após warm-up)
                             ▼
                         ┌──────────┐
                         │ RECOVERY │
                         └────┬─────┘  speed > limite
                              ▼
                         volta para CHASE/EVADE

   eliminação 500m  ─▶  ELIMINATED  (delete entity)
```

---

## 9. Boas práticas ao mexer na IA

1. **Não chame `TaskVehicle*` toda hora.** As `Task*` são caras e resetam
   navegação. Use *role keys* (`data.currentRole`) e só re-emita a task se a
   key mudar. Esse padrão já está em `enterChaseRole`/`enterEvadeRole`.
2. **Throttle de updates** quando o alvo se move muito (ex.: `CHASER_CLOSE`
   tem `chaseCloseLastIssued`, re-emite só após `CHASE_CLOSE_UPDATE_MS`).
3. **Vehicle nodes existem mesmo no oceano.** Sempre verifique o `found` do
   `GetClosestVehicleNode*` antes de usar a posição.
4. **Logs com `Logger.debug`**, nunca `print`. O prefixo `[AI:<npcId>]`
   facilita filtrar.
5. **Personality é dado, não comportamento.** Toda decisão "se aggressive,
   faça X" deve virar um campo na Strategy.
