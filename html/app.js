'use strict';

// ============================================================ State + helpers

const State = { selectedPts: 50, isReady: false, trafficOn: true, isLeader: false };

const $    = (id) => document.getElementById(id);
const show = (id) => $(id).classList.remove('hidden');
const hide = (id) => $(id).classList.add('hidden');

// Telas mutuamente exclusivas: showScreen garante que apenas uma fica visível.
// HUD/countdown/result/end-screen NÃO são "telas" no sentido de menu — eles
// se sobrepõem em momentos específicos da partida e são controlados em separado.
const MENU_SCREENS = ['main-menu', 'join-menu', 'lobby'];

function showScreen(id) {
    MENU_SCREENS.forEach(s => (s === id ? show(s) : hide(s)));
}

function hideAllMenus() {
    MENU_SCREENS.forEach(hide);
}

function postNUI(action, data = {}) {
    fetch(`https://outrun/${action}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
    }).catch(() => {});
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
        renderRoomsList(null); // estado "carregando"
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
                <div class="room-card-meta">${r.humans} jogador(es) · ${r.npcs} NPC(s)</div>
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
            document.querySelectorAll('#point-targets .btn-option').forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
            State.selectedPts = parseInt(btn.dataset.pts, 10);
        });
    });

    $('btn-add-npc').addEventListener('click', () => {
        postNUI('addNPC', { model: $('npc-model').value, personality: $('npc-personality').value });
    });

    $('my-car').addEventListener('change', () => {
        postNUI('setMyCar', { model: $('my-car').value });
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

    $('btn-start').addEventListener('click', () => postNUI('startRace'));

    // "Voltar" volta ao main-menu e avisa o server para encerrar/sair da sala.
    $('btn-lobby-back').addEventListener('click', () => {
        postNUI('leaveLobby');
        showScreen('main-menu');
    });

    // "X" fecha tudo (mantém comportamento anterior).
    $('btn-close').addEventListener('click', () => {
        hideAllMenus();
        postNUI('closeMenu');
    });
}

function renderParticipants(participants) {
    const allReady = participants.every(p => p.ready || p.isNPC);
    const pLabel   = { balanced: 'Equilibrado', aggressive: 'Agressivo', precise: 'Preciso' };

    $('participant-list').innerHTML = participants.map(p => `
        <div class="participant-row">
            <div class="participant-name">${p.isNPC ? '[NPC]' : '[P] ' + (p.name || p.source)}</div>
            <div>
                <div class="participant-car">${p.model || '—'}</div>
                ${p.isNPC ? `<div class="participant-tag">${pLabel[p.personality] || ''}</div>` : ''}
            </div>
            <div class="participant-ready ${p.ready ? 'ready' : ''}"></div>
        </div>`).join('');

    $('btn-start').disabled = !allReady;

    const me = participants.find(p => !p.isNPC);
    if (me && me.model) {
        const sel = $('my-car');
        if (sel && sel.value !== me.model) sel.value = me.model;
    }
}

// ============================================================ HUD

let dangerPlaying = false;

function updateHUD({ isLeader, dist, maxDist, position }) {
    State.isLeader = isLeader;
    const fill    = $('hud-bar-fill');
    const hasDist = typeof dist === 'number';
    const percent = hasDist ? Math.min(dist / maxDist, 1.0) : 0;

    fill.style.width = (percent * 100).toFixed(1) + '%';

    if (isLeader) {
        fill.classList.remove('chaser', 'danger');
        $('hud-position').textContent = 'LÍDER';
        dangerPlaying = false;
    } else {
        fill.classList.add('chaser');
        $('hud-position').textContent = position + 'º';
        const isDanger = hasDist && percent >= 0.8;
        fill.classList.toggle('danger', isDanger);
        if (isDanger && !dangerPlaying) { dangerPlaying = true; playBeep(percent); }
        else if (!isDanger) { dangerPlaying = false; }
    }

    $('hud-dist').textContent = hasDist
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
    const getName = (id) => (names && names[id]) || id;
    hide('hud'); show('round-result');
    const labels = ['1º','2º','3º','4º','5º','6º'];
    $('result-list').innerHTML = (results||[]).map((r,i) => `
        <div class="result-row">
            <span class="result-pos">${labels[i]||i+1+'º'}</span>
            <span>${getName(r.id)}</span>
            <span>${(scores&&scores[r.id])||0} pts</span>
        </div>`).join('');

    setTimeout(() => hide('round-result'), 10000);
}

function showEndScreen({ champion, scores, names }) {
    const getName = (id) => (names && names[id]) || id;
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
        // Navegação de menus
        case 'openMenu':       showScreen('main-menu'); break;
        case 'showLobby':      showScreen('lobby');     break;
        case 'hideMenus':      hideAllMenus();          break;

        // Compatibilidade legada (algumas chamadas antigas ainda enviam isso)
        case 'openLobby':      showScreen('lobby');     break;
        case 'hideLobby':      hideAllMenus();          break;

        // Dados de salas
        case 'lobbyCreated':   showScreen('lobby'); renderParticipants(data.room.participants||[]); break;
        case 'lobbyUpdated':   renderParticipants(data.room.participants||[]); break;
        case 'roomsList':      renderRoomsList(data.rooms||[]); break;

        // Corrida em andamento
        case 'showCountdown':  showCountdown(data); break;
        case 'countdownTick':  countdownTick(data); break;
        case 'countdownGo':    countdownGo(); break;
        case 'showHUD':        show('hud'); break;
        case 'updateHUD':      updateHUD(data); break;
        case 'leaderChanged':  playLeaderSwoosh(); break;
        case 'showRoundResult':
        case 'roundResult':    showRoundResult(data); break;
        case 'endScreen':      showEndScreen(data); break;
    }
});

document.addEventListener('DOMContentLoaded', () => {
    setupMainMenu();
    setupJoinMenu();
    setupLobby();
});
