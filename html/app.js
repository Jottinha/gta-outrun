'use strict';

// ============================================================ State + helpers

const State = {
    selectedPts: 50, isReady: false, trafficOn: true,
    isLeader: false, isHost: false, mySrc: null,
    vehicleIndex: 0, vehicles: [], botsEnabled: false,
    previewActive: false,
};

const $    = (id) => document.getElementById(id);
const show = (id) => { const el = $(id); if (el) el.classList.remove('hidden'); };
const hide = (id) => { const el = $(id); if (el) el.classList.add('hidden');    };

const MENU_SCREENS = ['main-menu', 'join-menu', 'lobby'];

function showScreen(id) {
    MENU_SCREENS.forEach(s => (s === id ? show(s) : hide(s)));
}

function hideAllMenus() {
    MENU_SCREENS.forEach(hide);
    destroyPreview();
}

// Limpeza total da UI (reset do mod): menus + HUD + overlays de corrida
function resetAllUI() {
    hideAllMenus();
    ['hud', 'round-result', 'countdown', 'end-screen', 'leader-takeover', 'leader-lose']
        .forEach(hide);
}

function postNUI(action, data = {}) {
    fetch(`https://outrun/${action}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
    }).catch(() => {});
}

function syncTrafficButton(on) {
    State.trafficOn = on;
    const btn = $('btn-traffic');
    if (!btn) return;
    btn.textContent = on ? 'ON' : 'OFF';
    btn.classList.toggle('off', !on);
}

function setHostUI(isHost) {
    State.isHost = isHost;
    const hostEls = ['btn-start'];
    hostEls.forEach(id => isHost ? show(id) : hide(id));
    show('btn-traffic');

    if (State.botsEnabled) {
        const npcEls = ['btn-add-npc', 'npc-model', 'npc-personality'];
        npcEls.forEach(id => isHost ? show(id) : hide(id));
        show('npc-section');
    } else {
        hide('npc-section');
    }

    const ptGroup = $('point-targets');
    if (ptGroup) {
        ptGroup.querySelectorAll('.btn-option').forEach(b => {
            b.disabled = !isHost;
            b.style.opacity = isHost ? '' : '0.4';
        });
    }
}


// ============================================================ Vehicle selector

function getCurrentVehicle() {
    return State.vehicles[State.vehicleIndex] || { model: 'sultan', label: 'Sultan' };
}

function updateVehicleDisplay() {
    const v = getCurrentVehicle();
    const nameEl = $('vehicle-name');
    const tagEl  = $('vehicle-model-tag');
    if (nameEl) nameEl.textContent = v.label;
    if (tagEl)  tagEl.textContent = v.model;

    const sel = $('my-car');
    if (sel) sel.value = v.model;
}

function requestPreview(vehicle) {
    State.previewActive = true;
    postNUI('previewVehicle', { model: vehicle.model, plate: vehicle.plate || null });
}

function destroyPreview() {
    if (State.previewActive) {
        State.previewActive = false;
        postNUI('destroyPreview');
    }
}

function navigateVehicle(direction) {
    if (State.vehicles.length === 0) return;
    State.vehicleIndex = (State.vehicleIndex + direction + State.vehicles.length) % State.vehicles.length;
    updateVehicleDisplay();
    const v = getCurrentVehicle();
    postNUI('setMyCar', { model: v.model, plate: v.plate || null });
    requestPreview(v);
}

function setVehicleByModel(model) {
    const idx = State.vehicles.findIndex(v => v.model === model);
    if (idx >= 0) {
        State.vehicleIndex = idx;
        updateVehicleDisplay();
    }
}

function applyVehicleConfig(cfg) {
    if (!cfg) return;
    if (cfg.vehicles && cfg.vehicles.length > 0) {
        State.vehicles = cfg.vehicles;
    }
    State.botsEnabled = cfg.botsEnabled === true;

    if (cfg.defaultModel && State.vehicles.length > 0) {
        const idx = State.vehicles.findIndex(v => v.model === cfg.defaultModel);
        if (idx >= 0) State.vehicleIndex = idx;
    }
    updateVehicleDisplay();
}

function setupVehicleSelector() {
    $('vehicle-prev').addEventListener('click', () => navigateVehicle(-1));
    $('vehicle-next').addEventListener('click', () => navigateVehicle(1));
}

function initPreviewOnLobbyOpen() {
    const v = getCurrentVehicle();
    requestPreview(v);
}


// ============================================================ Main menu

function setupMainMenu() {
    $('card-create').addEventListener('click', () => {
        postNUI('openCreate', { pointTarget: State.selectedPts });
    });

    $('card-join').addEventListener('click', () => {
        showScreen('join-menu');
        postNUI('refreshRooms');
    });

    $('btn-menu-close').addEventListener('click', () => {
        hideAllMenus();
        postNUI('closeMenu');
    });
}

// ============================================================ Join menu

function setupJoinMenu() {
    $('btn-join-back').addEventListener('click', () => {
        showScreen('main-menu');
    });

    $('btn-join-refresh').addEventListener('click', () => {
        postNUI('refreshRooms');
        renderRoomsList(null);
    });
}

function renderRoomsList(rooms) {
    const container = $('rooms-list');

    if (rooms === null) {
        container.innerHTML = `<div class="rooms-empty">Atualizando…</div>`;
        return;
    }

    if (!rooms || rooms.length === 0) {
        container.innerHTML = `<div class="rooms-empty">Nenhuma sala disponível no momento.</div>`;
        return;
    }

    container.innerHTML = rooms.map(r => `
        <div class="room-card" data-room-id="${r.id}">
            <div>
                <div class="room-card-host">${r.hostName || ('Sala #' + r.id)}</div>
                <div class="room-card-meta">${r.humans} jogador(es)</div>
            </div>
            <div class="room-card-target">${r.pointTarget} pts</div>
            <div class="room-card-cta">ENTRAR ›</div>
        </div>
    `).join('');

    container.querySelectorAll('.room-card').forEach(el => {
        el.addEventListener('click', () => {
            const id = parseInt(el.dataset.roomId, 10);
            postNUI('joinRoom', { roomId: id });
        });
    });
}

// ============================================================ Lobby

function setupLobby() {
    document.querySelectorAll('#point-targets .btn-option').forEach(btn => {
        btn.addEventListener('click', () => {
            if (!State.isHost) return;
            document.querySelectorAll('#point-targets .btn-option').forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
            State.selectedPts = parseInt(btn.dataset.pts, 10);
        });
    });

    $('btn-add-npc').addEventListener('click', () => {
        if (!State.isHost) return;
        postNUI('addNPC', { model: $('npc-model').value, personality: $('npc-personality').value });
    });

    $('btn-traffic').addEventListener('click', () => {
        State.trafficOn = !State.trafficOn;
        $('btn-traffic').textContent = State.trafficOn ? 'ON' : 'OFF';
        $('btn-traffic').classList.toggle('off', !State.trafficOn);
        postNUI('setTraffic', { on: State.trafficOn });
    });

    $('btn-ready').addEventListener('click', () => {
        State.isReady = !State.isReady;
        $('btn-ready').textContent = State.isReady ? 'CANCELAR' : 'PRONTO';
        $('btn-ready').classList.toggle('ready', State.isReady);
        postNUI('toggleReady');
    });

    $('btn-start').addEventListener('click', () => {
        if (!State.isHost) return;
        destroyPreview();
        postNUI('startRace');
    });

    $('btn-lobby-back').addEventListener('click', () => {
        destroyPreview();
        postNUI('leaveLobby');
        showScreen('main-menu');
    });

    $('btn-close').addEventListener('click', () => {
        hideAllMenus();
        postNUI('closeMenu');
    });

    // Resetar corrida: exige um segundo clique de confirmação dentro de 3s
    $('btn-reset').addEventListener('click', () => {
        const btn = $('btn-reset');
        if (btn.dataset.confirm === '1') {
            clearTimeout(resetConfirmTimer);
            resetResetButtonLabel();
            postNUI('resetRace');
        } else {
            btn.dataset.confirm = '1';
            btn.textContent = 'CONFIRMAR RESET?';
            btn.classList.add('confirm');
            resetConfirmTimer = setTimeout(resetResetButtonLabel, 3000);
        }
    });

    setupVehicleSelector();
}

let resetConfirmTimer = null;

function resetResetButtonLabel() {
    const btn = $('btn-reset');
    if (!btn) return;
    btn.dataset.confirm = '';
    btn.textContent = 'RESETAR CORRIDA';
    btn.classList.remove('confirm');
}

// Mostra o botão de reset apenas com a corrida em andamento (estado != LOBBY)
function updateResetButton(roomState) {
    const btn = $('btn-reset');
    if (!btn) return;
    const racing = !!roomState && roomState !== 'LOBBY';
    btn.classList.toggle('hidden', !racing);
    if (resetConfirmTimer) clearTimeout(resetConfirmTimer);
    resetResetButtonLabel();
}

function getVehicleLabel(model) {
    const v = State.vehicles.find(v => v.model === model);
    return v ? v.label : model;
}

function renderParticipants(participants, isHost) {
    const allHumansReady = participants.every(p => p.isNPC || p.ready);
    const pLabel = { balanced: 'Equilibrado', aggressive: 'Agressivo', precise: 'Preciso' };

    $('participant-list').innerHTML = participants.map(p => `
        <div class="participant-row">
            <div class="participant-name">${p.isNPC
                ? '[NPC]'
                : '[P] ' + (p.name || p.source)
            }</div>
            <div>
                <div class="participant-car">${p.model ? getVehicleLabel(p.model) : '—'}</div>
                ${p.isNPC ? `<div class="participant-tag">${pLabel[p.personality] || ''}</div>` : ''}
            </div>
            <div class="participant-ready ${p.ready ? 'ready' : ''}"></div>
        </div>`).join('');

    const btnStart = $('btn-start');
    if (btnStart) btnStart.disabled = !allHumansReady || !isHost;

    const myPlr = State.mySrc != null
        ? participants.find(p => p.source == State.mySrc)
        : participants.find(p => !p.isNPC);
    if (myPlr && myPlr.model) {
        setVehicleByModel(myPlr.model);
    }
}

// ============================================================ Leader takeover

let leaderTakeoverTimer = null;
let leaderLoseTimer    = null;
let _wasLeader = false;

function showLeaderTakeover() {
    const el = $('leader-takeover');
    if (!el) return;
    if (leaderTakeoverTimer) { clearTimeout(leaderTakeoverTimer); leaderTakeoverTimer = null; }
    el.classList.remove('hidden');
    const txt = el.querySelector('.takeover-text');
    if (txt) {
        txt.style.animation = 'none';
        void txt.offsetWidth;
        txt.style.animation = 'takeoverPop 1s ease-out forwards';
    }
    leaderTakeoverTimer = setTimeout(() => {
        el.classList.add('hidden');
        leaderTakeoverTimer = null;
    }, 1000);
}

function showLeaderLose() {
    const el = $('leader-lose');
    if (!el) return;
    if (leaderLoseTimer) { clearTimeout(leaderLoseTimer); leaderLoseTimer = null; }
    el.classList.remove('hidden');
    const txt = el.querySelector('.lose-text');
    if (txt) {
        txt.style.animation = 'none';
        void txt.offsetWidth;
        txt.style.animation = 'takeoverPop 1s ease-out forwards';
    }
    leaderLoseTimer = setTimeout(() => {
        el.classList.add('hidden');
        leaderLoseTimer = null;
    }, 1000);
}

// ============================================================ HUD

let dangerPlaying  = false;
let _lastLeaderDist = 0;

function updateHUD({ isLeader, dist, maxDist, position }) {
    if (isLeader && !_wasLeader)  showLeaderTakeover();
    if (!isLeader && _wasLeader)  showLeaderLose();
    _wasLeader = isLeader;
    State.isLeader = isLeader;
    const fill    = $('hud-bar-fill');

    let effectiveDist = dist;
    if (isLeader) {
        if (typeof dist === 'number') _lastLeaderDist = dist;
        else effectiveDist = _lastLeaderDist;
    }

    const hasEffective = typeof effectiveDist === 'number';
    const hasRealDist  = typeof dist === 'number';
    const percent = hasEffective ? Math.min(effectiveDist / maxDist, 1.0) : 0;

    fill.style.width = (percent * 100).toFixed(1) + '%';

    if (isLeader) {
        fill.classList.remove('chaser', 'danger');
        $('hud-position').textContent = 'LÍDER';
        dangerPlaying = false;
    } else {
        fill.classList.add('chaser');
        $('hud-position').textContent = position + 'º';
        const isDanger = hasEffective && percent >= 0.8;
        fill.classList.toggle('danger', isDanger);
        if (isDanger && !dangerPlaying) { dangerPlaying = true; playBeep(percent); }
        else if (!isDanger) { dangerPlaying = false; }
    }

    $('hud-dist').textContent = hasRealDist
        ? Math.floor(dist) + 'm / ' + maxDist + 'm'
        : '— / ' + maxDist + 'm';
}

function playBeep(intensity) {
    try {
        const ctx = new (window.AudioContext || window.webkitAudioContext)();
        const osc = ctx.createOscillator(), gain = ctx.createGain();
        osc.connect(gain); gain.connect(ctx.destination);
        osc.frequency.value = 440 + intensity * 200;
        gain.gain.setValueAtTime(0.12, ctx.currentTime);
        gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.18);
        osc.start(ctx.currentTime); osc.stop(ctx.currentTime + 0.18);
    } catch (_) {}
}

function playLeaderSwoosh() {
    try {
        const ctx = new (window.AudioContext || window.webkitAudioContext)();
        const buf = ctx.createBuffer(1, ctx.sampleRate * 0.12, ctx.sampleRate);
        const d   = buf.getChannelData(0);
        for (let i = 0; i < d.length; i++) d[i] = (Math.random()*2-1)*(1-i/d.length);
        const src = ctx.createBufferSource(), gain = ctx.createGain();
        src.buffer = buf; gain.gain.value = 0.25;
        src.connect(gain); gain.connect(ctx.destination); src.start();
    } catch (_) {}
}

// ============================================================ Countdown

function showCountdown({ isBonusRound }) {
    hideAllMenus();
    hide('round-result');
    show('countdown');
    $('countdown-bonus').classList.toggle('hidden', !isBonusRound);
}

function countdownTick({ count }) {
    if ($('countdown').classList.contains('hidden')) showCountdown({ isBonusRound: false });
    const el = $('countdown-number');
    el.textContent = count;
    el.style.animation = 'none'; void el.offsetWidth; el.style.animation = 'countPulse 0.8s ease-out';
    el.style.color = count <= 3 ? '#ff2244' : '#00ff88';
}

function countdownGo() {
    $('countdown-number').textContent = 'GO!';
    $('countdown-number').style.color = '#00ff88';
    setTimeout(() => hide('countdown'), 1200);
}

// ============================================================ Results

function showRoundResult({ results, scores, names }) {
    const getName  = (id) => (names  && (names[id]  || names[String(id)]))  || id;
    const getScore = (id) => (scores && (scores[id] !== undefined ? scores[id] : scores[String(id)])) || 0;
    hide('hud'); show('round-result');
    const labels = ['1º','2º','3º','4º','5º','6º','7º','8º'];
    $('result-list').innerHTML = (results||[]).map((r,i) => `
        <div class="result-row">
            <span class="result-pos">${labels[i]||i+1+'º'}</span>
            <span>${getName(r.id)}</span>
            <span>${getScore(r.id)} pts</span>
        </div>`).join('');

    setTimeout(() => hide('round-result'), 10000);
}

function showEndScreen({ champion, scores, names }) {
    const getName = (id) => (names && (names[id] || names[String(id)])) || id;
    hide('hud'); hide('round-result'); show('end-screen');

    $('champion-name').textContent = getName(champion);

    const sorted = Object.entries(scores||{}).sort((a,b) => b[1]-a[1]);
    $('final-scores').innerHTML = `<div class="end-scores-list">` +
        sorted.map(([id,pts],i) => `
        <div class="end-row ${i===0?'first-place':''}">
            <span class="end-pos">${i+1}º</span>
            <span class="end-name">${getName(id)}</span>
            <span class="end-pts">${pts} pts</span>
        </div>`).join('') +
    `</div>`;

    $('btn-close-end').addEventListener('click', () => {
        hide('end-screen');
        postNUI('closeMenu');
    }, { once: true });
}

// ============================================================ NUI message handler

window.addEventListener('message', ({ data: { action, data } }) => {
    switch (action) {
        case 'openMenu':  showScreen('main-menu'); break;
        case 'showLobby': showScreen('lobby');     break;
        case 'hideMenus': hideAllMenus();          break;
        case 'resetUI':   resetAllUI();            break;

        case 'openLobby': showScreen('lobby'); break;
        case 'hideLobby': hideAllMenus();      break;

        case 'lobbyCreated': {
            const isHost = data.isHost === true;
            if (data.mySrc != null) State.mySrc = data.mySrc;
            applyVehicleConfig(data.vehicleConfig);
            if (data.trafficOn != null) syncTrafficButton(data.trafficOn);
            showScreen('lobby');
            setHostUI(isHost);
            renderParticipants(data.room.participants || [], isHost);
            updateResetButton(data.room.state);
            initPreviewOnLobbyOpen();
            // Sincronizar seleção inicial com o server
            const cv = getCurrentVehicle();
            postNUI('setMyCar', { model: cv.model, plate: cv.plate || null });
            break;
        }
        case 'lobbyUpdated': {
            const isHost = data.isHost === true;
            if (data.mySrc != null) State.mySrc = data.mySrc;
            if (data.vehicleConfig) applyVehicleConfig(data.vehicleConfig);
            setHostUI(isHost);
            renderParticipants(data.room.participants || [], isHost);
            updateResetButton(data.room.state);
            break;
        }
        case 'updateVehicleConfig':
            if (data.vehicleConfig) {
                applyVehicleConfig(data.vehicleConfig);
                const uv = getCurrentVehicle();
                postNUI('setMyCar', { model: uv.model, plate: uv.plate || null });
                requestPreview(uv);
            }
            break;
        case 'roomsList': renderRoomsList(data.rooms || []); break;

        case 'showCountdown': showCountdown(data); break;
        case 'countdownTick': countdownTick(data); break;
        case 'countdownGo':   countdownGo();       break;
        case 'showHUD':       show('hud');          break;
        case 'updateHUD':     updateHUD(data);      break;
        case 'leaderChanged': playLeaderSwoosh(); break;
        case 'showRoundResult':
        case 'roundResult':   showRoundResult(data); break;
        case 'endScreen':     showEndScreen(data);   break;
    }
});

// ============================================================ Drag system

function setupDrag() {
    let dragging = null;
    let offsetX = 0, offsetY = 0;

    document.addEventListener('mousedown', (e) => {
        const handle = e.target.closest('.drag-handle');
        if (!handle) return;

        const targetId = handle.dataset.dragTarget;
        const panel = document.getElementById(targetId);
        if (!panel) return;

        e.preventDefault();

        if (!panel.dataset.dragInit) {
            const rect = panel.getBoundingClientRect();
            panel.style.position = 'fixed';
            panel.style.left = rect.left + 'px';
            panel.style.top = rect.top + 'px';
            panel.style.margin = '0';
            panel.dataset.dragInit = '1';
        }

        dragging = panel;
        offsetX = e.clientX - panel.getBoundingClientRect().left;
        offsetY = e.clientY - panel.getBoundingClientRect().top;
        panel.classList.add('dragging');
    });

    document.addEventListener('mousemove', (e) => {
        if (!dragging) return;
        e.preventDefault();

        let newX = e.clientX - offsetX;
        let newY = e.clientY - offsetY;

        const maxX = window.innerWidth - dragging.offsetWidth;
        const maxY = window.innerHeight - dragging.offsetHeight;
        newX = Math.max(0, Math.min(newX, maxX));
        newY = Math.max(0, Math.min(newY, maxY));

        dragging.style.left = newX + 'px';
        dragging.style.top = newY + 'px';
    });

    document.addEventListener('mouseup', () => {
        if (dragging) {
            dragging.classList.remove('dragging');
            dragging = null;
        }
    });
}

function resetAllPanelPositions() {
    document.querySelectorAll('.draggable-panel[data-drag-init]').forEach(panel => {
        panel.style.position = '';
        panel.style.left = '';
        panel.style.top = '';
        panel.style.margin = '';
        delete panel.dataset.dragInit;
    });
}

document.addEventListener('DOMContentLoaded', () => {
    setupMainMenu();
    setupJoinMenu();
    setupLobby();
    setupDrag();
});
