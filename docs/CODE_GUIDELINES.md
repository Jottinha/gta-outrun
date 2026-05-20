# CODE_GUIDELINES — Padrões de código do OUTRUN

> Padrões que **todo** novo código no recurso deve seguir. Mantemos o
> projeto navegável e fácil de evoluir.

---

## 1. Estrutura de arquivos

* Domínio dirige a estrutura, não camada. Ex: `client/ai/` reúne tudo de IA,
  não temos um `client/models/` ou `client/services/` genérico.
* Cada arquivo declara o módulo no topo: `Module = {}`.
* Estado privado do módulo: `local x = ...` dentro do arquivo.
* Funções públicas: `function Module.X() end`.
* Funções privadas (visíveis só no arquivo): `local function helper() end`.

### Nomes de arquivos

* `snake_case.lua` para arquivos Lua.
* Nome reflete o módulo principal: `race_logic.lua` define `RaceLogic`.
* Pastas em minúsculo: `client/ai/`, `server/`, `shared/`.

### Nomes de identificadores

* **Módulos**: `PascalCase` (`RaceLogic`, `AIController`, `RoundManager`).
* **Funções públicas**: `lowerCamelCase` ou `PascalCase` consistente dentro do
  módulo. (Por compatibilidade com o que já existe, mantemos `PascalCase` para
  pontos de entrada principais como `RaceLogic.StartLoop`.)
* **Funções privadas**: `lowerCamelCase` (`getActiveParticipants`).
* **Variáveis e parâmetros**: `lowerCamelCase` (`leaderVeh`, `runnerUpVeh`).
* **Constantes de Config**: `UPPER_SNAKE_CASE` (`Config.Race.WIN_DISTANCE`).
* **Eventos**: namespace `outrun:server:Verbo` ou `outrun:client:Verbo`,
  declarados em `Config.Events`.

---

## 2. Eventos de rede

* **Nunca** use string crua de evento em `Register*Event`, `Trigger*Event` ou
  `AddEventHandler`. Sempre via `Config.Events.<Server|Client>.<Nome>`.
* Adicionar um evento novo:
  1. Declarar em `config.lua` → `Config.Events`.
  2. Registrar handler usando essa referência.
  3. Documentar na tabela de eventos do
     [`GDD_OUTRUN.md`](GDD_OUTRUN.md#72-eventos-de-rede).

Exceção: eventos do framework externo (`playerDropped`, `QBCore:*`) ficam
fora do `Config.Events` porque o nome é dado pelo framework.

---

## 3. Logging

* Nunca `print(...)` direto em código de produção.
* Usar `Logger.debug(modulo, msg)` / `Logger.info(modulo, msg)` /
  `Logger.warn(modulo, msg)` / `Logger.error(modulo, msg)`.
* `modulo` é uma string curta: `"SRV"`, `"AI:7"`, `"NUI"`, etc.
* `Config.Debug.ENABLED` controla emissão de `debug`. `info/warn/error`
  sempre passam.

---

## 4. Estado e singletons

* Estado de runtime em um único arquivo por domínio. Ex: `RaceState` mora em
  `client/race_state.lua` e expõe `reset()`, `clear()`, etc.
* Outros módulos **leem** `RaceState`, mas só `race_state.lua` deve
  modificá-lo por funções nomeadas.
* Server: estado em `server/rooms.lua`. Acesso via `Rooms.get(...)`,
  `Rooms.create(...)`, etc. Nunca acessar a tabela interna diretamente.

---

## 5. Funções e tamanhos

* Função > 40 linhas? Tente extrair um helper local nomeado.
* Função com 4+ parâmetros? Considere passar uma tabela `opts`.
* Função que faz duas coisas? Quebrar em duas.
* Função que retorna sucesso + dado? `return ok, data` (estilo Lua).

---

## 6. Lua specifics

* Sempre `local` para variáveis locais. Globais sem `local` são poluição.
* `Citizen.CreateThread` é caro. Evite criar uma thread nova a cada tick.
  Quando precisar de loop, crie **uma** thread no boot do módulo.
* `Wait(0)` consome um frame. Para loops de gameplay que não precisam de
  60Hz, use `Citizen.Wait(50)` ou `100`.
* `DoesEntityExist` antes de qualquer leitura. Entities podem morrer entre
  ticks.

---

## 7. Nativas FiveM

* `Get*` / `Set*` em pediatria de tipo: validar `type(x) == "vector3"` antes
  de usar — alguns builds devolvem `0` ou `nil`.
* `RequestModel` + `HasModelLoaded` loop com timeout. Nunca esperar
  indefinidamente. Helper: `loadModelHash(hash)` (em `spawn.lua`).
* `CreateVehicle`/`CreatePed*` devolvem `0` em falha. Sempre testar.
* `SetVehicleEngineTorqueMultiplier` deve ser chamado **por frame** enquanto o
  efeito é desejado (o motor reseta).

---

## 8. Comentários

* Escreva o **porquê**, não o **o quê**. Bom nome de função/variável já diz o
  que faz.
* Cabeçalho ASCII por seção é OK (ajuda navegação visual em arquivos grandes).
* TODOs com contexto: `-- TODO: validar liderança server-side (MULTIPLAYER_PLAN §3.1)`.
* Não copiar/colar o GDD nos arquivos. Linkar com path relativo se preciso.

---

## 9. Tratamento de erros

* O Lua do FiveM tem `pcall`. Use em interações com nativas que podem falhar
  silenciosamente.
* Nunca silencie um erro com `pcall` sem ao menos `Logger.warn`.
* Validar **entradas externas** (NUI callbacks, eventos de rede): nunca
  confiar em tipos do que vem do client.

---

## 10. Anti-padrões a evitar

* ❌ `print(...)` direto.
* ❌ `RegisterNetEvent('outrun:server:Foo', ...)` com string crua.
* ❌ Funções globais sem `local` apenas porque "outro arquivo precisa".
  Se outro arquivo precisa, exporte via `Module.X`.
* ❌ Magic numbers no meio da lógica: extraia para `Config`.
* ❌ Spawnar entidade sem `SetEntityAsMissionEntity` (vira lixo de cleanup).
* ❌ `while true do ... end` sem `Wait` (trava o jogo).
* ❌ Acessar `Rooms` ou `RaceState` por leitura direta de tabela cruzada.
  Sempre via funções do módulo dono.

---

## 11. Checklist antes de abrir PR

1. [ ] Arquivo respeita responsabilidade única.
2. [ ] Nenhum `print` direto, tudo via `Logger`.
3. [ ] Eventos novos passam por `Config.Events`.
4. [ ] Constantes novas em `Config`, não inline.
5. [ ] Funções de mais de 40 linhas justificadas ou refatoradas.
6. [ ] Estado novo mora em um único módulo dono.
7. [ ] Sem TODOs sem contexto.
8. [ ] GDD atualizado se houve mudança de regra de jogo.
9. [ ] Testado in-game (single-player) sem regressão visível.
