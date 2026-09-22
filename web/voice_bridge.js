'use strict';
// Only static model artifacts cross the network; inference stays in the worker.
self.CareBridgeOfflineVoice = (() => {
  let worker;
  let context;
  let playing;
  const pending = new Map();
  const failure = code => new Error(code);
  const available = () => self.isSecureContext && !!self.Worker && !!self.caches && !!self.crypto?.subtle;
  function connect() {
    if (worker) return worker;
    if (!available()) throw failure('offline_runtime_unavailable');
    worker = new Worker(new URL('voice_worker.js', document.baseURI));
    worker.onmessage = event => {
      const reply = event.data;
      const task = pending.get(reply.id);
      if (!task) return;
      if (reply.progress) { task.progress?.(reply.progress); return; }
      pending.delete(reply.id);
      if (reply.error) task.reject(failure(reply.error)); else task.resolve(reply.value);
    };
    worker.onerror = () => {
      for (const task of pending.values()) task.reject(failure('offline_worker_failed'));
      pending.clear();
      worker.terminate();
      worker = null;
    };
    return worker;
  }
  function request(id, operation, args, progress) {
    return new Promise((resolve, reject) => {
      try {
        const target = connect();
        if (pending.has(id)) throw failure('duplicate_request');
        pending.set(id, {resolve, reject, progress});
        const transfer = [];
        for (const value of Object.values(args)) {
          if (ArrayBuffer.isView(value) && !transfer.includes(value.buffer)) transfer.push(value.buffer);
        }
        target.postMessage({...args, id, operation}, transfer);
      } catch (_) { pending.delete(id); reject(failure('offline_worker_failed')); }
    });
  }
  function cancel(id) {
    if (pending.has(id)) worker?.postMessage({operation: 'cancel', target: id});
  }
  async function unlock() {
    const Audio = self.AudioContext || self.webkitAudioContext;
    if (!Audio) throw failure('audio_unavailable');
    context ??= new Audio();
    if (context.state !== 'running') await context.resume();
    if (context.state !== 'running') throw failure('audio_activation_required');
    return true;
  }
  function stopAudio() {
    const current = playing;
    playing = null;
    if (current) {
      current.source.onended = null;
      try { current.source.stop(); } catch (_) { /* Already ended. */ }
      current.source.disconnect();
      current.resolve(false);
    }
  }
  async function playAudio(samples, sampleRate, onStarted) {
    if (!context || context.state !== 'running') throw failure('audio_activation_required');
    if (!(samples instanceof Float32Array) || !samples.length ||
        !Number.isInteger(sampleRate) || sampleRate < 8000 || sampleRate > 96000 ||
        samples.some(value => !Number.isFinite(value))) throw failure('invalid_audio');
    stopAudio();
    const buffer = context.createBuffer(1, samples.length, sampleRate);
    buffer.copyToChannel(samples, 0);
    const source = context.createBufferSource();
    source.buffer = buffer;
    source.connect(context.destination);
    return new Promise((resolve, reject) => {
      const current = {source, resolve};
      playing = current;
      source.onended = () => {
        source.disconnect();
        if (playing === current) playing = null;
        resolve(true);
      };
      try { source.start(); onStarted?.(); }
      catch (_) { playing = null; source.disconnect(); reject(failure('audio_start_failed')); }
    });
  }
  async function shellStatus() {
    const url = new URL('offline_shell.json', document.baseURI).href;
    const response = await (await caches.open('carebridge-shell-index-v1')).match(url);
    if (!response) return false;
    const info = await response.json();
    const cache = await caches.open(info.name);
    for (const file of info.manifest.files) {
      const artifact = await cache.match(new URL(file.name, document.baseURI));
      if (!artifact) return false;
      const data = await artifact.arrayBuffer();
      if (data.byteLength !== file.bytes) return false;
      const hash = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', data)),
        value => value.toString(16).padStart(2, '0')).join('');
      if (hash !== file.sha256) return false;
    }
    return navigator.serviceWorker.controller?.scriptURL === new URL('app_sw.js', document.baseURI).href;
  }
  async function installShell() {
    if (!navigator.serviceWorker) throw failure('offline_runtime_unavailable');
    const registration = await navigator.serviceWorker.register(new URL('app_sw.js', document.baseURI), {updateViaCache: 'none'});
    await registration.update();
    const candidate = registration.installing || registration.waiting;
    if (candidate && candidate.state !== 'activated') await new Promise((resolve, reject) => {
      const timer = setTimeout(() => { candidate.removeEventListener('statechange', changed); reject(failure('shell_install_timeout')); }, 180000);
      function changed() {
        if (candidate.state === 'activated' || candidate.state === 'installed' || candidate.state === 'redundant') {
          clearTimeout(timer); candidate.removeEventListener('statechange', changed);
          if (candidate.state === 'redundant') reject(failure('shell_install_failed')); else resolve();
        }
      }
      candidate.addEventListener('statechange', changed); changed();
    });
    return shellStatus();
  }
  async function voices() {
    const synth = self.speechSynthesis;
    if (!synth) return [];
    if (!synth.getVoices().length) await new Promise(resolve => {
      const finish = () => { clearTimeout(timer); synth.removeEventListener('voiceschanged', finish); resolve(); };
      const timer = setTimeout(finish, 1500);
      synth.addEventListener('voiceschanged', finish);
    });
    return synth.getVoices().map(voice => ({name: voice.name, locale: voice.lang, localService: voice.localService}));
  }
  const activate = () => { void unlock().catch(() => {}); };
  document.addEventListener('pointerdown', activate, {capture: true, passive: true});
  document.addEventListener('keydown', activate, {capture: true});
  return {available, request, cancel, unlock, playAudio, stopAudio, voices, installShell, shellStatus};
})();
