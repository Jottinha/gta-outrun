'use strict';

const State = { selectedPts: 100, isReady: false, trafficOn: true, isLeader: false };
const $    = (id) => document.getElementById(id);
const show = (id) => $(id).classList.remove('hidden');
const hide = (id) => $(id).classList.add('hidden');

function postNUI(action, data = {}) {
    fetch(`https://outrun/${action}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
    }).catch(() => {});
}

// ============================================================ Lobby

function setupLobby() {
    document.querySelectorAll('.btn-option').forEach(btn => {
        btn.addEventListener('click', () => {
            document.querySelectorAll('.btn-option').forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
            State.selectedPts = parseInt(btn.dataset.pts);
        });
    });

    $('btn-add-npc').addEventListener('click', () => {
        postNUI('addNPC', { model: $('npc-model').value, personality: $('npc-personality').value });
    });

    // Troca de carro do próprio jogador
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
    $('btn-close').addEventListener('click', () => postNUI('closeLobby'));
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

    // Sincroniza dropdown "Meu Carro" com o modelo atual do jogador
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
    const percent = Math.min(dist / maxDist, 1.0);

    fill.style.width = (percent * 100).toFixed(1) + '%';

    if (isLeader) {
        fill.classList.remove('chaser', 'danger');
        $('hud-position').textContent = 'LÍDER';
    } else {
        fill.classList.add('chaser');
        $('hud-position').textContent = position + 'º';
        const isDanger = percent >= 0.8;
        fill.classList.toggle('danger', isDanger);
        if (isDanger && !dangerPlaying) { dangerPlaying = true; playBeep(percent); }
        else if (!isDanger) { dangerPlaying = false; }
    }

    $('hud-dist').textContent = Math.floor(dist) + 'm / ' + maxDist + 'm';
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
    hide('lobby'); show('countdown');
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

function showRoundResult({ results, scores }) {
    hide('hud'); show('round-result');
    const labels = ['1º','2º','3º','4º','5º','6º'];
    $('result-list').innerHTML = (results||[]).map((r,i) => `
        <div class="result-row">
            <span class="result-pos">${labels[i]||i+1+'º'}</span>
            <span>${r.id}</span>
            <span>${(scores&&scores[r.id])||0} pts</span>
        </div>`).join('');

    setTimeout(() => {
        hide('round-result'); show('lobby');
        State.isReady = false;
        $('btn-ready').textContent = 'PRONTO';
        $('btn-ready').classList.remove('ready');
    }, 10000);
}

function showEndScreen({ champion, scores }) {
    hide('hud'); hide('round-result'); show('end-screen');
    $('champion-name').textContent = champion;
    const sorted = Object.entries(scores||{}).sort((a,b) => b[1]-a[1]);
    $('final-scores').innerHTML = sorted.map(([id,pts],i) => `
        <div class="result-row">
            <span class="result-pos">${i+1}º</span>
            <span>${id}</span>
            <span>${pts} pts</span>
        </div>`).join('');
    $('btn-close-end').addEventListener('click', () => { hide('end-screen'); postNUI('closeLobby'); }, { once: true });
}

// ============================================================ NUI Handler

window.addEventListener('message', ({ data: { action, data } }) => {
    switch (action) {
        case 'openLobby':
            show('lobby');
            if (!data.hasLobby) postNUI('createLobby', { pointTarget: State.selectedPts });
            break;
        case 'hideLobby':      hide('lobby'); break;
        case 'lobbyCreated':   show('lobby'); renderParticipants(data.room.participants||[]); break;
        case 'lobbyUpdated':   renderParticipants(data.room.participants||[]); break;
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

document.addEventListener('DOMContentLoaded', setupLobby);
