'use strict';
// Shared by the voice worker and installer. These caches never contain patient data.
self.CareBridgeVoiceStore = (() => {
  const indexName = 'carebridge-voice-index-v1';
  const root = new URL('./', self.location.href);
  const bases = new Map([
    ['assets/assets/tts/twi_piper', 'piper-v1'],
    ['assets/assets/tts/hausa_piper', 'piper-v1'],
    ['assets/assets/models/translation_twi', 'marian-v1'],
    ['assets/assets/models/translation_hausa', 'marian-v1'],
  ]);
  const fail = code => { throw new Error(code); };
  function baseUrl(base) {
    if (!bases.has(base)) fail('unsupported_pack');
    return new URL(`${base}/`, root).href;
  }
  function validate(manifest, base) {
    if (!manifest || typeof manifest !== 'object' || manifest.schema !== 1 ||
        manifest.contract !== bases.get(base) || typeof manifest.revision !== 'string' ||
        !/^[a-zA-Z0-9._-]+$/.test(manifest.revision) ||
        !Array.isArray(manifest.files) || !manifest.files.length) fail('invalid_manifest');
    const names = new Set();
    for (const file of manifest.files) {
      if (!file || typeof file.name !== 'string' ||
          !/^[a-zA-Z0-9_.-]+$/.test(file.name) || ['.', '..'].includes(file.name) ||
          !Number.isSafeInteger(file.bytes) || file.bytes <= 0 || typeof file.sha256 !== 'string' ||
          !/^[a-f0-9]{64}$/.test(file.sha256) || names.has(file.name)) fail('invalid_manifest');
      names.add(file.name);
    }
    const required = bases.get(base) === 'piper-v1'
      ? ['model.onnx', 'model.onnx.json', ...(base.includes('twi') ? ['twi_rules.json'] : [])]
      : ['encoder_model.onnx', 'decoder_model.onnx', 'source.spm', 'target.spm',
        'vocab.json', 'generation_config.json', 'tokenizer_fixtures.json', 'generation_fixtures.json'];
    if (required.some(name => !names.has(name))) fail('incomplete_manifest');
    return manifest;
  }
  async function verify(buffer, file) {
    if (buffer.byteLength !== file.bytes) fail('size_mismatch');
    const prefix = new TextDecoder().decode(buffer.slice(0, 64));
    if (prefix.startsWith('version https://git-lfs') ||
        (file.name.endsWith('.onnx') && buffer.byteLength < 1024)) fail('invalid_model');
    const hash = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', buffer)),
      byte => byte.toString(16).padStart(2, '0')).join('');
    if (hash !== file.sha256) fail('integrity_failed');
  }
  async function metadata(base) {
    const response = await (await caches.open(indexName)).match(baseUrl(base));
    if (!response) fail('pack_not_installed');
    const info = await response.json();
    validate(info.manifest, base);
    if (typeof info.cache !== 'string' || !/^carebridge-voice-pack-[a-zA-Z0-9-]+$/.test(info.cache)) fail('invalid_manifest');
    return info;
  }
  async function read(base, name, expectedCache) {
    const info = await metadata(base);
    if (expectedCache && info.cache !== expectedCache) fail('pack_changed');
    const file = info.manifest.files.find(file => file.name === name);
    if (!file) fail('artifact_not_listed');
    const response = await (await caches.open(info.cache)).match(new URL(name, baseUrl(base)));
    if (!response) fail('pack_evicted');
    const data = await response.arrayBuffer();
    await verify(data, file);
    return data;
  }
  async function status(base) {
    try {
      const info = await metadata(base);
      const cache = await caches.open(info.cache);
      for (const file of info.manifest.files) {
        const response = await cache.match(new URL(file.name, baseUrl(base)));
        if (!response) fail('pack_evicted');
        await verify(await response.arrayBuffer(), file);
      }
      return {installed: true, integrityReady: true, runtimeReady: false, revision: info.manifest.revision};
    } catch (_) { return {installed: false, integrityReady: false, runtimeReady: false}; }
  }
  async function install(base, signal, progress) {
    const url = baseUrl(base);
    const response = await fetch(new URL('model_manifest.json', url), {signal, cache: 'no-store'});
    if (!response.ok) fail('manifest_unavailable');
    const manifest = validate(await response.json(), base);
    const total = manifest.files.reduce((sum, file) => sum + file.bytes, 0);
    const estimate = await navigator.storage?.estimate?.();
    if (estimate?.quota && estimate.quota - (estimate.usage || 0) < total * 1.1) fail('insufficient_storage');
    const name = `carebridge-voice-pack-${crypto.randomUUID()}`;
    const cache = await caches.open(name);
    let completed = 0;
    try {
      for (const file of manifest.files) {
        const fileUrl = new URL(file.name, url);
        const download = await fetch(fileUrl, {signal, cache: 'no-store'});
        if (!download.ok || !download.body) fail('download_failed');
        const reader = download.body.getReader();
        const chunks = [];
        let received = 0;
        while (true) {
          const {value, done} = await reader.read();
          if (done) break;
          received += value.byteLength;
          if (received > file.bytes) { await reader.cancel(); fail('size_mismatch'); }
          chunks.push(value);
          progress({received: completed + received, total});
        }
        const data = new Uint8Array(received);
        let offset = 0;
        for (const chunk of chunks) { data.set(chunk, offset); offset += chunk.length; }
        await verify(data.buffer, file);
        if (signal.aborted) fail('cancelled');
        await cache.put(fileUrl, new Response(data, {headers: {'Content-Type': 'application/octet-stream'}}));
        completed += received;
      }
      if (signal.aborted) fail('cancelled');
      // The only activation write happens after every artifact passes integrity.
      await (await caches.open(indexName)).put(url, new Response(JSON.stringify({cache: name, manifest})));
      progress({received: total, total});
      return {installed: true, integrityReady: true, runtimeReady: false, bytes: total, revision: manifest.revision};
    } catch (error) {
      await caches.delete(name);
      throw error;
    }
  }
  return {read, status, install, metadata, verify};
})();
