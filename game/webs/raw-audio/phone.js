const $ = id => document.getElementById(id);
const query = new URLSearchParams(location.search);
$('code').value = query.get('code') || '';
if (query.has('relay')) $('relay').value = query.get('relay');
let session = null;
const status = text => { $('status').textContent = text; };

async function stop() {
  const s = session;
  session = null;
  if (!s) return;
  clearInterval(s.heartbeat);
  clearInterval(s.statsTimer);
  clearTimeout(s.deadline);
  s.stream?.getTracks().forEach(track => track.stop());
  s.source?.disconnect();
  s.worklet?.disconnect();
  s.worklet?.port.close();
  try { s.oscillator?.stop(); } catch {}
  s.dc?.close();
  s.pc?.close();
  s.ws?.close();
  await s.audio?.close();
  $('mic').disabled = $('tone').disabled = false;
  $('stop').disabled = true;
  status('Stopped');
}

async function start(useTone) {
  await stop();
  const s = { pending: [], localCandidates: [], directSentAt: new Map(), offerSent: false, sent: 0, relayed: 0, lastAudioAck: 0, dropped: 0, attempt: 1 };
  session = s;
  $('mic').disabled = $('tone').disabled = true;
  $('stop').disabled = false;
  const fail = async error => {
    if (session !== s) return;
    await stop();
    status(error.message || String(error));
  };
  try {
    s.audio = new AudioContext({ sampleRate: 48000, latencyHint: 'interactive' });
    await s.audio.resume();
    if (s.audio.sampleRate !== 48000) throw Error('This prototype requires a 48 kHz audio context');
    await s.audio.audioWorklet.addModule('./pcm-worklet.js');
    if (session !== s) return;
    if (useTone) {
      s.oscillator = s.audio.createOscillator();
      s.toneHz = Number($('frequency').value);
      if (!Number.isFinite(s.toneHz) || s.toneHz < 30 || s.toneHz > 1200) throw Error('Choose a frequency between 30 and 1200 Hz');
      s.oscillator.frequency.value = s.toneHz;
      const gain = s.audio.createGain();
      gain.gain.value = 0.25;
      s.oscillator.connect(gain);
      s.source = gain;
      s.oscillator.start();
    } else {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: {
        channelCount: 1, sampleRate: 48000,
        echoCancellation: false, noiseSuppression: false, autoGainControl: false
      } });
      if (session !== s) { stream.getTracks().forEach(t => t.stop()); return; }
      s.stream = stream;
      s.source = s.audio.createMediaStreamSource(stream);
    }
    s.ws = new WebSocket($('relay').value);
    const send = message => {
      if (session === s && s.ws.readyState === WebSocket.OPEN) s.ws.send(JSON.stringify({ protocol: 1, ...message }));
    };
    s.ws.onopen = () => {
      send({ type: 'client.join', displayCode: $('code').value.toUpperCase(), name: 'PCM experiment', preferredSlot: 1 });
      s.heartbeat = setInterval(() => send({ type: 'client.heartbeat' }), 2000);
    };
    s.ws.onclose = () => { if (session === s) fail(Error('Relay disconnected. Rejoin to try again.')); };
    s.ws.onerror = () => fail(Error('Relay connection failed'));
    s.ws.onmessage = async event => {
      try {
        if (session !== s) return;
        const m = JSON.parse(event.data);
        if (m.type === 'error') throw Error(m.code || 'Connection error');
        if (m.type === 'p2p.error') { status('Direct audio unavailable; using server route'); return; }
        if (m.type === 'host.disconnected' || m.type === 'room.closed') throw Error('Game disconnected');
        if (m.type === 'client.joined') {
          if (m.slot !== 1) throw Error('Player 1 is already occupied. Stop its phone session first.');
          if (!m.p2p?.enabled) throw Error('This room does not support native PCM');
          s.worklet = new AudioWorkletNode(s.audio, 'usce-pcm');
          s.worklet.port.onmessage = event => {
            if (session !== s) return;
            const packet = event.data;
            const forceRelay = $('relayOnly').checked;
            let confirmed = !forceRelay && s.lastAudioAck > 0 && performance.now() - s.lastAudioAck < 250;
            if (!forceRelay && s.dc?.readyState === 'open' && s.dc.bufferedAmount < 9600) {
              try {
                s.dc.send(packet); ++s.sent;
                s.directSentAt.set(new DataView(packet).getUint32(4, true), performance.now());
                if (s.directSentAt.size > 100) s.directSentAt.delete(s.directSentAt.keys().next().value);
              } catch { s.lastAudioAck = 0; confirmed = false; }
            }
            if (!confirmed) {
              if (s.ws.readyState === WebSocket.OPEN && s.ws.bufferedAmount < 16000) {
                const pcm = btoa(String.fromCharCode(...new Uint8Array(packet)));
                send({ type: 'audio.pcm', pcm });
                ++s.relayed;
              } else ++s.dropped;
            }
          };
          const mute = s.audio.createGain();
          mute.gain.value = 0;
          s.source.connect(s.worklet).connect(mute).connect(s.audio.destination);
          const ice = $('ice').value;
          s.pc = new RTCPeerConnection({ iceServers: ice ? [{ urls: ice }] : [] });
          s.pc.onicecandidate = event => {
            if (!event.candidate) return;
            const signal = { type: 'p2p.ice', attempt: s.attempt, candidate: event.candidate.toJSON() };
            if (s.offerSent) send(signal);
            else s.localCandidates.push(signal);
          };
          s.pc.onconnectionstatechange = () => {
            if (session !== s) return;
            if (['failed', 'closed', 'disconnected'].includes(s.pc.connectionState)) {
              s.lastAudioAck = 0; status('Direct connection unavailable; using server route');
            }
          };
          s.dc = s.pc.createDataChannel('usce-pcm-v1', { ordered: false, maxRetransmits: 0 });
          s.dc.onopen = () => {
            if (session !== s) return;
            clearTimeout(s.deadline);
            status(useTone ? `Sending ${s.toneHz} Hz test tone to USCE` : 'Sending microphone audio to USCE');
          };
          s.dc.onclose = s.dc.onerror = () => {
            if (session !== s) return;
            s.lastAudioAck = 0; status('Using server audio route');
          };
          s.dc.onmessage = event => {
            try {
              const ping = JSON.parse(event.data);
              if (ping.type === 'audio.pcm.ack' && !$('relayOnly').checked) {
                const sentAt = s.directSentAt.get(ping.sequence);
                if (sentAt !== undefined && performance.now() - sentAt < 250) s.lastAudioAck = performance.now();
              }
              if (ping.type === 'latency.ping' && Number.isFinite(ping.sentMs)) {
                s.applicationRttMs = performance.now() - ping.sentMs;
                s.bestRttMs = Math.min(s.bestRttMs ?? Infinity, s.applicationRttMs);
              }
            } catch {}
          };
          const offer = await s.pc.createOffer();
          await s.pc.setLocalDescription(offer);
          send({ type: 'p2p.offer', attempt: s.attempt, description: s.pc.localDescription.toJSON() });
          s.offerSent = true;
          for (const signal of s.localCandidates.splice(0)) send(signal);
          s.deadline = setTimeout(() => status('Direct connection timed out; using server audio route'), 20000);
          status('Sending through server while negotiating direct audio');
          s.statsTimer = setInterval(async () => {
            try {
              const stats = await s.pc.getStats();
              if (session !== s) return;
              const pair = [...stats.values()].find(v => v.type === 'candidate-pair' && v.state === 'succeeded' && v.nominated);
              const local = pair && stats.get(pair.localCandidateId);
              const remote = pair && stats.get(pair.remoteCandidateId);
              if (s.dc.readyState === 'open') s.dc.send(JSON.stringify({ type: 'latency.ping', sentMs: performance.now() }));
              $('stats').textContent = JSON.stringify({ source: useTone ? `${s.toneHz} Hz tone` : 'microphone',
                sampleRate: s.audio.sampleRate, sentPackets: s.sent, relayedPackets: s.relayed, droppedBeforeSend: s.dropped,
                audioRoute: !$('relayOnly').checked && s.lastAudioAck > 0 && performance.now() - s.lastAudioAck < 250 ? 'P2P confirmed by receiver' : 'server fallback / P2P probing',
                bufferedBytes: s.dc.bufferedAmount, roundTripMs: s.applicationRttMs ?? null,
                bestRoundTripMs: s.bestRttMs ?? null, packetAssemblyMs: 10,
                note: 'RTT excludes microphone hardware and pitch analysis. It is not mouth-to-screen latency.',
                route: local && remote ? `${local.candidateType} → ${remote.candidateType}` : 'negotiating',
                microphoneSettings: s.stream?.getAudioTracks()[0]?.getSettings() }, null, 2);
            } catch {}
          }, 1000);
        } else if (m.type === 'p2p.answer' && m.attempt === s.attempt) {
          await s.pc.setRemoteDescription(m.description);
          for (const candidate of s.pending.splice(0)) await s.pc.addIceCandidate(candidate);
        } else if (m.type === 'p2p.ice' && m.attempt === s.attempt) {
          if (s.pc?.remoteDescription) await s.pc.addIceCandidate(m.candidate);
          else s.pending.push(m.candidate);
        }
      } catch (error) { await fail(error); }
    };
  } catch (error) { await fail(error); }
}
$('mic').onclick = () => start(false);
$('tone').onclick = () => start(true);
$('stop').onclick = stop;
$('relayOnly').onchange = () => { if (session) session.lastAudioAck = 0; };
window.addEventListener('pagehide', stop);
$('frequency').oninput = () => {
  const hz = Number($('frequency').value);
  if (session?.oscillator && Number.isFinite(hz) && hz >= 30 && hz <= 1200) {
    session.toneHz = hz;
    session.oscillator.frequency.value = hz;
    status(`Sending ${hz} Hz test tone to USCE`);
  }
};
