# GDD & ANÁLISE DE SISTEMAS: PROJETO OUTRUN FIVEM

## 1. VISÃO GERAL DO SISTEMA
O modo recria a dinâmica de "Gato e Rato" (Outrun) do *NFS Underground 2* em um ambiente de mundo aberto (Los Santos). Os corredores largam juntos. Quem toma a frente vira o **Líder**. O objetivo do Líder é navegar pelo tráfego e abrir **500 metros** do segundo colocado. O objetivo dos demais é alcançar e ultrapassar o Líder. Se um corredor ficar 500m atrás do Líder, é eliminado. A rodada termina quando o Líder vence ou resta apenas um carro. Um sistema de campeonato em rodadas define o grande vencedor.

---

## 2. REQUISITOS DO SISTEMA

### Requisitos Funcionais (RF)
*   **RF01:** O comando `/outrun` deve abrir a UI (NUI) principal.
*   **RF02:** O sistema deve permitir criar salas definindo a meta de pontos (ex: 50, 100, 200).
*   **RF03:** O host deve poder adicionar múltiplos NPCs à sala e escolher os veículos para cada um.
*   **RF03b:** O jogador host deve poder escolher seu próprio veículo a partir de uma lista de modelos pré-definidos. A seleção é refletida na "miniatura do carro escolhido" da Seção 5.1.
*   **RF04:** Jogadores devem ter um botão de "Pronto" (Ready), bloqueando o botão "Iniciar" até todos confirmarem.
*   **RF05:** O sistema deve teleportar os veículos para coordenadas dinâmicas e alinhá-los em grid.
*   **RF06:** O controle dos veículos deve ser bloqueado (`FreezeEntityPosition`) até o fim da contagem de 5 segundos.
*   **RF07:** O sistema deve calcular a liderança em tempo real (quem está fisicamente à frente).
*   **RF08:** O sistema deve eliminar jogadores/NPCs que fiquem > 500m do líder (virando espectadores).
*   **RF09:** O sistema deve declarar o líder como vencedor da rodada se ele abrir > 500m do segundo colocado.
*   **RF10:** O sistema deve distribuir pontos: 1º (10), 2º (8), 3º (6), 4º (4).
*   **RF11:** O sistema deve sortear e aplicar o evento "Rodada Bônus" (Polícia) apenas no líder do campeonato.

### Requisitos Não Funcionais (RNF)
*   **RNF01:** A lógica de IA dos NPCs deve rodar no *Client-side* do Host para garantir latência zero na física de direção.
*   **RNF02:** Cálculos de distância devem ser atualizados no máximo a cada 50ms para evitar falsos positivos de eliminação.
*   **RNF03:** A persistência da sala (pontuação, configuração) deve ocorrer no *Server-side* para garantir a base do futuro Multiplayer.
*   **RNF04:** A IA deve ter um período de "aquecimento" pós-largada (≥ 3s) onde a detecção de *stuck* é desativada, evitando recuperações prematuras enquanto os NPCs ainda não atingiram velocidade de cruzeiro. Sem esse buffer, NPCs próximos ao líder parado entram em loop de teletransporte para o mesmo *vehicle node* ao serem considerados travados na largada.

---

## 3. FLUXOS E ESTADOS

### 3.1. Máquina de Estados da Sala (Campeonato)
`LOBBY` ➔ `SPAWN_GRID` ➔ `COUNTDOWN` ➔ `RACING` ➔ `ROUND_RESULT` ➔ `CHECK_CHAMPIONSHIP` ➔ (Loop para `SPAWN_GRID` ou vai para `END_SCREEN`).

### 3.2. Fluxograma Textual do Jogador
1. Digita `/outrun`.
2. Acessa Lobby ➔ Configura pontos (Ex: 100) ➔ Adiciona 3 NPCs ➔ Escolhe carros.
3. Clica "Pronto" ➔ Clica "Iniciar".
4. Tela de loading curta ➔ Veículos spawnados no mundo.
5. Contagem: 5, 4, 3, 2, 1, GO!
6. Corrida ocorre ➔ Alguém abre 500m ➔ Fim da rodada.
7. HUD mostra pontuação por 10s.
8. Loop reinicia em novo local até alguém somar 100 pontos.
9. Tela de vitória exibe o campeão.

---

## 4. DINÂMICAS CORE E REGRAS DE NEGÓCIO

### 4.1. Sistema de Liderança
No mundo aberto não há "checkpoints". A liderança é calculada por **distância e direção (Forward Vector)**:
*   Se o Carro B encosta no Carro A, o sistema calcula o *Dot Product* entre a posição de B e o vetor frontal de A.
*   Se B passar à frente da "linha imaginária" do para-choque de A, **B é o novo Líder**.
*   A distância da vitória/eliminação (500m) é sempre medida em relação ao Líder atual. A distância é euclidiana bidimensional (ignorando o eixo Z) para evitar vitórias injustas ao passar por pontes/túneis.

### 4.2. Sistema de Pontuação e Eliminação
*   **Vitória:** `Distância(Líder, 2º Colocado) >= 500.0`.
*   **Eliminação:** `Distância(Líder, Participante[X]) >= 500.0`.
*   **Espectador:** Jogadores eliminados têm a câmera anexada (cam *orbit*) ao veículo do Líder, com controle de rotação.
*   **Pontuação Fixa:** 10, 8, 6, 4. (Se houver 5 corredores, o 5º ganha 2; o 6º ganha 0).

### 4.3. Evento Especial: Rodada Bônus (Polícia)
*   **Ativação:** Probabilidade configurável (ex: 15% de chance ao iniciar uma nova rodada, desde que já exista um líder isolado no campeonato).
*   **Alvo Único:** O líder absoluto da tabela de pontos recebe 4 estrelas.
*   **Isolamento de IA:** Para a polícia não interferir nos outros, todos os corredores (exceto o alvo) recebem o native `SetPoliceIgnorePlayer(true)`.
*   **Objetivo:** Adicionar caos. Se o líder bater fugindo da polícia, ele perde a liderança do Outrun.
*   **Reset:** No estado `ROUND_RESULT`, o wanted level é limpo (`ClearPlayerWantedLevel`).

---

## 5. DESIGN DE HUD / UI (NUI)

### 5.1. Lobby
*   **Painel Esquerdo:** Configurações (Pontos alvo, Chance de Rodada Bônus, Tráfego On/Off).
*   **Centro:** Lista de Jogadores/NPCs, miniatura do carro escolhido, botão circular de Status (Vermelho/Verde para Pronto).
*   **Rodapé:** Botão "INICIAR CORRIDA" (Bloqueado até todos estarem verdes).

### 5.2. HUD da Corrida (In-game)

O HUD principal da corrida deve ser minimalista, focando a atenção do jogador na **Barra de Progressão Outrun**, localizada no canto superior direito da tela.

**A Barra de Progressão (A Dinâmica Principal)**
A barra tem um limite máximo que representa a distância de eliminação (Ex: 500 metros). Ela se preenche dinamicamente baseada no papel atual do jogador:

*   **SE O JOGADOR FOR O LÍDER (Barra Verde):**
    *   **Cor:** Verde Neon (Estilo NFS).
    *   **Alvo do Cálculo:** A distância medida é entre o Líder e o **2º colocado** (o oponente mais próximo de alcançá-lo).
    *   **Comportamento:** Quanto mais o Líder se afasta do 2º colocado, mais a barra verde enche.
    *   **Condição Final:** Quando a barra verde encher completamente (bater 500m de vantagem), o Líder vence a rodada.

*   **SE O JOGADOR FOR UM PERSEGUIDOR (Barra Vermelha):**
    *   **Cor:** Vermelho Alerta.
    *   **Alvo do Cálculo:** A distância medida é sempre entre o Jogador e o **Líder atual** (ignorando os outros corredores).
    *   **Comportamento:** Quanto mais o Líder abre distância do jogador, mais a barra vermelha enche. Se o jogador acelerar e se aproximar do Líder, a barra vermelha esvazia.
    *   **Condição Final:** Quando a barra vermelha encher completamente (ficar 500m para trás), o jogador é eliminado da rodada.

**Transição de Liderança (Inversão da Barra)**
Quando ocorre uma ultrapassagem pela liderança:
1.  A interface toca um efeito sonoro rápido ("Swoosh").
2.  A cor da barra muda instantaneamente (de Vermelho para Verde, ou vice-versa).
3.  A barra **não zera**, ela apenas inverte a perspectiva. (Ex: Se você estava colado no líder com a barra vermelha quase vazia, ao ultrapassá-lo, a barra fica verde e começa a encher a seu favor).

**Elementos Secundários na Tela:**
*   **Aviso de Posição:** Um texto discreto abaixo da barra indicando a posição atual (`LÍDER`, `2º`, `3º`).
*   **Alerta de Perigo:** Quando a barra vermelha atingir 80% (400m de distância), a barra começa a piscar em vermelho mais forte e um bipe cardíaco começa a tocar, acelerando conforme a barra se aproxima dos 100%.
---

## 6. SISTEMA AVANÇADO DE IA (NPCS)

A inteligência artificial padrão do GTA V para direção é inútil para corridas. Eles param em semáforos, fogem ou batem. Precisamos de um controlador de IA customizado através de *Natives*.

### 6.1. Máquina de Estados da IA
*   **`GRID`:** Motor desligado, posição travada.
*   **`CHASING` (Perseguindo):** O NPC não é o líder. Usa a função nativa `TaskVehicleDriveToCoord` atualizando o alvo para as coordenadas futuras do Líder (não onde o líder está, mas para onde ele está indo, usando o vetor de velocidade do líder).
*   **`FLEEING` (Líder):** O NPC é o líder. Ele precisa "fugir". Usa `GenerateDirectionsToCoord` para um ponto aleatório a 2km de distância, garantindo que a rota seja por estradas longas (evitando becos onde ele travaria).
*   **`OVERTAKING`:** Distância < 20m. A IA muda a flag de direção (Driving Style) para máxima agressividade (ex: `1074528293`), forçando ultrapassagem e empurrando tráfego leve.
*   **`RECOVERY` (Stuck):** Detectado se `Velocidade < 2.0` por mais de 3 segundos (sem estar no Grid).
*   **`ELIMINATED`:** O NPC é deletado do mundo físico.

### 6.2. Comportamento e Personalidade
Cada NPC gerado terá um *Driving Style* que afeta sua agressividade, configurado na *Native* `SetDriveTaskDrivingStyle`:
*   **Agressivo:** Fura sinal, ultrapassa na contramão, ignora pequenos obstáculos (Style `786603` ou similar).
*   **Equilibrado:** Tenta se manter na via, desvia com segurança, mas corre em alta velocidade.
*   **Preciso:** Usa perfeitamente os *nodes* da estrada, freia corretamente, prioriza não bater (ideal para liderar sem causar acidentes).

### 6.3. Sistema de Borracha (Catch-up / Rubber-banding)
*Crucial para o modo offline não ficar entediante.*
*   **NPC Líder fugindo rápido demais:** Se o NPC líder abrir > 300m, o script reduz o multiplicador de torque dele (`SetVehicleEngineTorqueMultiplier`) para 0.8.
*   **NPC Perseguidor ficando para trás:** Se o NPC ficar > 250m atrás do jogador líder, seu torque sobe para 1.5 e aderência aumenta, garantindo que ele chegue perto para "pressionar" o jogador e manter a tensão.

### 6.4. Recuperação de Rota (Anti-Stuck)
NPCs no GTA batem. Para evitar que a corrida acabe porque a IA ficou presa num muro:
*   **Detecção:** Thread verifica `GetEntitySpeed(npcVehicle)` a cada 2 segundos.
*   **Ação:** Se preso, o sistema recalcula a rota. Se continuar preso no próximo check, o sistema faz um *teleport* discreto e imperceptível do NPC para o *node* de estrada válido mais próximo, atrás do jogador (se invisível na câmera do jogador) ou ao lado dele.
*   **Warm-up (RNF04):** A detecção de stuck só começa após **5 segundos** da largada (`ReleaseGrid` no client do host marca o timestamp inicial). Antes disso, qualquer NPC parado é tratado como "ainda acelerando", não como travado. Isso impede o loop onde múltiplos NPCs próximos ao líder parado teleportam todos para o mesmo *vehicle node* ao mesmo tempo.
*   **Mira fallback:** Quando o líder está praticamente parado (`velMag < 2.0 m/s`), o NPC perseguidor mira 150m à frente da direção que o líder aponta (`GetEntityForwardVector`) em vez da posição exata do líder. Isso evita que o NPC "alcance" o líder estacionado e fique parado ao lado, sendo classificado como travado.

---

## 7. ARQUITETURA DE REDE (FiveM Client/Server)

Para já nascer pronto para o Multiplayer, a estrutura deve separar claramente as responsabilidades.

### 7.1. Separação de Responsabilidades
**Server-side (`server/main.lua`, `server/lobby.lua`)**
*   Fonte da verdade. Guarda quem está na sala, as pontuações e o estado global (`LOBBY`, `RACING`, etc.).
*   Gera os locais dinâmicos de spawn.
*   Aplica pontuação após receber evento de finalização.
*   Decide (RNG) quando ocorre a Rodada Bônus.

**Client-side (`client/main.lua`, `client/ai_controller.lua`, `client/hud.lua`)**
*   Lê *inputs*, renderiza HUD.
*   **Host do Lobby:** O client que criou a sala é dono das entidades (*Network Ownership*). A IA dos NPCs roda exclusivamente no client do Host, enviando as coordenadas pela rede nativa do OneSync.
*   Calcula colisões, calcula distância e quem é o líder (baseado nas posições locais e rede).

### 7.2. Eventos do Sistema (Fluxo Multiplayer Futuro)
1.  `outrun:server:CreateLobby`
2.  `outrun:server:JoinLobby`
3.  `outrun:server:ToggleReady`
4.  `outrun:server:StartRace` -> Dispara `outrun:client:SpawnVehicles` para todos.
5.  `outrun:server:UpdateLeader` (Broadcast de quem assumiu a liderança).
6.  `outrun:client:PlayerEliminated` -> Envia ao server, que atualiza a tabela e define o alvo para *Spectator*.
7.  `outrun:server:RoundEnd` -> Processa pontos e dispara NUI de resultados para clients.

### 7.3. Persistência e Banco de Dados (Cache)
*   **Temporário (KV/Memória):** O estado da sala, pontos atuais e lista de jogadores são guardados em tabelas Lua na memória do Servidor. Não há necessidade de SQL durante a corrida.
*   **Persistente (SQL Futuro):** Salvar estatísticas de vitórias e Win Rate no banco de dados do framework (QBCore/ESX) quando o Campeonato terminar.

---

## 8. PREVENÇÃO DE BUGS E EXPLOITS

### 8.1. O Bug do Eixo Z (Túneis e Pontes)
*   **Problema:** Se o cálculo for 3D puro (`#(vector3(x,y,z) - vector3(x,y,z))`), um jogador numa ponte e outro no túnel embaixo podem dar distância de 100m vertical, acionando eliminações injustas.
*   **Solução:** Todas as distâncias devem ser calculadas no vetor bidimensional plano: `#(vector2(pos1.x, pos1.y) - vector2(pos2.x, pos2.y))`.

### 8.2. O Bug da Liderança Interminável (Ping/Desync)
*   **Problema:** No multiplayer, com latência alta, o Jogador 1 vê o Jogador 2 atrás. O Jogador 2 vê o Jogador 1 atrás. Ambos acham que são líderes.
*   **Solução:** O Servidor possui autoridade de Liderança. O client avisa: "Eu ultrapassei!". O servidor verifica as coordenadas globais. Se for válido, o Servidor faz broadcast: "O Jogador 2 é o novo Líder". A UI e as distâncias obedecem estritamente à entidade Líder validada pelo Servidor.

### 8.3. Spawns Dinâmicos Quebrados
*   **Problema:** Teleportar os carros no início da rodada para dentro do oceano ou em montanhas.
*   **Solução:** Usar `GetRandomVehicleNode` passando um raio vasto, mas validar a propriedade do nó (evitar terra batida caso configurado apenas asfalto) e validar se há espaço livre na bounding box para os X veículos da sessão.

### 8.4. Abandono de Partida
*   **Problema:** O Host desloga durante o modo contra NPC.
*   **Solução:** O servidor detecta o evento `playerDropped`. Se for o Host, o loop é encerrado, as entidades NPCs são deletadas (`DeleteEntity`) e a sala é destruída para não gerar lixo na memória (*Memory Leak*).

---

## 9. ESTRUTURA DE ARQUIVOS (MÓDULOS) RECOMENDADA

```text
[outrun_mode]/
├── fxmanifest.lua
├── config.lua               # Variáveis globais (Metas, Distância 500m, Locais RNG, Modelos de NPC)
├── server/
│   ├── main.lua             # Escuta de eventos, gerenciamento da sala, pontuação
│   └── events.lua           # Sorteio de rodada policial, controle de desconexões
├── client/
│   ├── main.lua             # Threads principais da corrida, inputs, NUI trigger
│   ├── ai_controller.lua    # Máquina de estado da IA, catch-up, anti-stuck, rotas
│   ├── race_logic.lua       # Matemática vetorial para Liderança, distância bidimensional
│   └── spectator.lua        # Lógica de controle de câmera ao ser eliminado
└── html/
    ├── index.html           # Lobby e HUD estruturado
    ├── style.css            # Estilização Neon/NFS
    └── app.js               # Lógica React/Vanilla para atualizar UI sem gargalos

---
## 10. ARQUITETURA DO SERVIDOR E FRAMEWORK (QBCORE FREEROAM)

Para suportar o ecossistema do modo Outrun e permitir progressão (dinheiro e garagens personalizadas) sem a burocracia de um servidor de Roleplay, o projeto utilizará a base **QBCore** adaptada para o modelo **Freeroam / Racing Server**.

### 10.1. Estratégia de Adaptação (Clean-up)
O QBCore será mantido como motor principal de dados, mas todos os módulos voltados para simulação de vida e economia civil (Roleplay) serão estritamente desativados via `server.cfg` para poupar processamento (tick rate) e evitar conflitos com a lógica de corrida.

### 10.2. Módulos Core a serem MANTIDOS
Estes recursos nativos do QBCore são obrigatórios para a fundação do servidor e deverão permanecer ativos:
*   **Banco de Dados:** `oxmysql`
*   **Núcleo da Base:** `qb-core`
*   **Gerenciamento de Jogador:** `qb-multicharacter` (Tela de seleção), `qb-clothing` ou `illenium-appearance` (Criação de avatar), `qb-spawn`.
*   **Economia e Itens:** `qb-inventory` (Essencial para itens mecânicos e chaves de veículos), `qb-banking`.
*   **Ecossistema Veicular:** `qb-garages` (Persistência de veículos), `qb-customs` (Oficina de modificação visual e performance), `qb-carmenu`.

### 10.3. Módulos a serem DESATIVADOS
As seguintes categorias de scripts devem ter sua inicialização comentada (`# ensure script`) no `server.cfg` e, posteriormente, deletadas do repositório:
*   **Empregos Oficiais:** `qb-policejob`, `qb-ambulancejob`, `qb-mechanicjob`, `qb-taxi`, `qb-tow`, etc.
*   **Atividades e Gangues:** `qb-bankrobbery`, `qb-storerobbery`, `qb-drugs`, `qb-weed`, `qb-prison`.
*   **Imóveis e Burocracia:** `qb-cityhall`, `qb-houses`, `qb-apartments`.

### 10.4. Modificações de Regra de Negócio (Sobrevivência)
Como este é um servidor focado em corrida e não em sobrevivência, as mecânicas de saúde passiva devem ser anuladas:
1.  **Remoção de Fome e Sede:** A *thread* responsável por drenar a saúde do jogador baseada em fome/sede, localizada em `[qb] > qb-smallresources > client > survival.lua`, deverá ser completamente desativada ou deletada.
2.  **Ajuste de HUD:** No script responsável pela interface (`qb-hud` ou equivalente), as métricas de fome, sede e estresse devem ser ocultadas da NUI, mantendo a tela limpa apenas com: Minimapa, Velocímetro e a Barra de Progressão do modo Outrun.
3.  **Sistema de Chaves Automático:** A lógica do `qb-vehiclekeys` precisará ser ajustada para garantir que o jogador sempre possua a chave do próprio carro ao retirá-lo da garagem (`qb-garages`), eliminando a necessidade de "trancar/destrancar" manualmente durante a montagem das corridas.
---

## 11. ADENDO DE IMPLEMENTACAO - IA E LIDERANCA

Este adendo complementa e, quando houver conflito, substitui as descricoes mais antigas da Secao 6.

### 11.1. Resolucao de Lideranca
*   A troca de lideranca nao ocorre apenas com `dot > 0`. O desafiante precisa abrir um buffer longitudinal minimo a frente do lider atual para evitar flapping em emparelhamentos laterais.
*   Quando mais de um carro aparece a frente do lider atual no mesmo instante, o sistema promove iterativamente o carro mais avancado ate resolver quem realmente esta na ponta do pelotao.
*   Depois de resolver o lider, a ordem dos demais participantes e recalculada a partir dele. O 2o colocado passa a ser o perseguidor ativo mais relevante para a IA de fuga.

### 11.2. Estados Reais da IA
*   **`GRID`:** carro travado e sem tarefa de direcao.
*   **`CHASE`:** o NPC persegue o lider com `TaskVehicleChase`, so assumindo a lideranca quando a regra de ultrapassagem do sistema confirmar a manobra.
*   **`EVADE`:** o NPC lider foge especificamente do 2o colocado, usando um alvo dinamico projetado para frente com vies de escape em relacao ao perseguidor mais proximo.
*   **`RECOVERY`:** o NPC limpou as tasks e recebeu uma tarefa curta e cautelosa para destravar usando a propria navegacao da engine.
*   **`ELIMINATED`:** fora do conjunto ativo da rodada.

### 11.3. Controle de Estado e Performance
*   Cada NPC precisa manter uma tabela local com, no minimo: `currentRole`, `currentMode`, `stuckTimer`.
*   Uma nova `Task` de direcao so deve ser emitida quando a assinatura do papel mudar. Exemplos:
    *   mudou o lider perseguido;
    *   mudou o 2o colocado que pressiona o lider;
    *   o alvo de fuga mudou de setor viario;
    *   o NPC entrou ou saiu de recovery.

### 11.4. Anti-Stuck
*   Warm-up fixo de 5 segundos apos a largada.
*   Gatilho: `GetEntitySpeed(npcVehicle) < 2.0 m/s` por `3000ms` acumulados.
*   Recovery sem teleporte: `ClearPedTasks(npcPed)` + `TaskVehicleDriveToCoord` para um *vehicle node* muito proximo, em baixa velocidade, para a engine manobrar sozinha.
*   Ao voltar a superar `2.0 m/s`, o estado `RECOVERY` e limpo e o NPC reavalia `CHASE` ou `EVADE` no tick seguinte.

### 11.5. Eliminacao e Resultado da Rodada
*   Um participante eliminado sai imediatamente do conjunto de competidores ativos e nao pode mais influenciar lideranca, distancia de vitoria, escolha do 2o colocado ou comportamento da IA.
*   O placar final da rodada deve ser montado com:
    1. participantes ainda ativos na ordem final;
    2. eliminados em ordem inversa da eliminacao.

### 11.6. Spawn Nodes Configuraveis
*   Os locais de teleporte da corrida devem vir de uma lista configuravel de pontos candidatos (`Config.SpawnNodes`), permitindo curadoria manual de varios lugares diferentes no mapa sem alterar a logica da corrida.
*   O servidor escolhe um ponto dessa lista no inicio de cada rodada e envia esse ponto base para o host.
*   O ponto escolhido e apenas a base da largada; a posicao final sempre deve ser corrigida para o `vehicle node` mais proximo com heading valido de pista.
*   Isso substitui a premissa de uso de pontos aleatorios nao curados no mapa. A escolha pratica dos locais passa a ser manual e orientada por configuracao.

### 11.7. Grid de Largada F1 Classico
*   A largada nao deve alinhar todos os carros em uma unica linha lateral. O posicionamento oficial passa a ser **grid F1 classico**, com duas colunas e stagger longitudinal.
*   Regras do grid:
    1. um lado fica na pole position;
    2. o lado oposto fica alguns metros atras;
    3. novas filas sao criadas dinamicamente conforme a quantidade total de participantes;
    4. o sistema deve funcionar igualmente para humano sozinho, humano + 1 NPC, humano + varios NPCs e futuras combinacoes multiplayer.
*   O grid precisa definir a ordem inicial da corrida antes do `GO`, para que ja exista um primeiro colocado valido no instante da largada.
*   O espacamento do grid deve ficar centralizado no `config.lua`, com pelo menos tres parametros:
    *   espacamento entre filas;
    *   espacamento lateral entre colunas;
    *   stagger longitudinal entre pole e segundo colocado.

### 11.8. Estrutura Real do Recurso
*   A documentacao do projeto deve ficar dentro do recurso ativo, em `outrun/docs/GDD_OUTRUN.md`.
*   A raiz da categoria `[outrun]` nao deve conter pastas auxiliares sem `fxmanifest.lua`, para evitar warnings do scanner de recursos.
*   A estrutura operacional esperada passa a ser:
    *   `[outrun]/outrun/fxmanifest.lua`
    *   `[outrun]/outrun/config.lua`
    *   `[outrun]/outrun/client/*`
    *   `[outrun]/outrun/server/*`
    *   `[outrun]/outrun/html/*`
    *   `[outrun]/outrun/docs/GDD_OUTRUN.md`
