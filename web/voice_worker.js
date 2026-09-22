'use strict';
importScripts('./voice_storage.js', './voice_runtime/ort.wasm.min.js');
ort.env.wasm.wasmPaths = new URL('./voice_runtime/', self.location.href).href;
ort.env.wasm.numThreads = 1;
ort.env.wasm.proxy = false;
const store = self.CareBridgeVoiceStore;
const models = new Map();
const installations = new Map();
const cancelled = new Set();
const active = new Set();
const safeErrors = new Set(['unsupported_pack', 'invalid_manifest', 'incomplete_manifest',
  'size_mismatch', 'invalid_model', 'integrity_failed', 'pack_not_installed', 'pack_evicted',
  'pack_changed', 'artifact_not_listed', 'manifest_unavailable', 'insufficient_storage',
  'download_failed', 'cancelled', 'tensor_contract', 'generation_contract', 'generation_parity',
  'model_not_loaded', 'voice_configuration', 'invalid_audio', 'translation_length_limit']);
let tail = Promise.resolve();
const text = buffer => new TextDecoder().decode(buffer);
const int64 = (ids, dims) => new ort.Tensor('int64', BigInt64Array.from(ids, BigInt), dims);
const fail = code => { throw new Error(code); };
function names(actual, expected) {
  if (actual.length !== expected.length || expected.some(name => !actual.includes(name))) fail('tensor_contract');
}
async function release(kind) {
  const model = models.get(kind);
  models.delete(kind);
  if (model) for (const session of model.sessions) await session.release();
}
async function load(kind, base) {
  if (!['piper', 'marian'].includes(kind)) fail('unsupported_model');
  const info = await store.metadata(base);
  if ((kind === 'piper' ? 'piper-v1' : 'marian-v1') !== info.manifest.contract) fail('tensor_contract');
  if (models.get(kind)?.base === base && models.get(kind).cache === info.cache) return true;
  await release(kind);
  const model = {base, cache: info.cache, sessions: []};
  const read = name => store.read(base, name, info.cache);
  try {
    const options = {executionProviders: ['wasm'], graphOptimizationLevel: 'all'};
    if (kind === 'piper') {
      model.config = JSON.parse(text(await read('model.onnx.json')));
      const session = await ort.InferenceSession.create(await read('model.onnx'), options);
      model.sessions.push(session);
      names(session.inputNames, ['input', 'input_lengths', 'scales', ...(model.config.num_speakers > 1 ? ['sid'] : [])]);
      names(session.outputNames, ['output']);
    } else {
      model.config = JSON.parse(text(await read('generation_config.json')));
      const config = model.config;
      const vocabulary = JSON.parse(text(await read('vocab.json')));
      model.vocabularySize = Object.keys(vocabulary).length;
      const validToken = token => Number.isInteger(token) && token >= 0 && token < model.vocabularySize;
      if (![config.decoder_start_token_id, config.eos_token_id, config.pad_token_id].every(validToken) ||
          config.num_beams !== 1 || config.do_sample !== false || !Number.isInteger(config.max_length) ||
          config.max_length < 2 || config.max_length > 512 || (config.min_length || 0) !== 0 ||
          (config.repetition_penalty ?? 1) !== 1 || (config.no_repeat_ngram_size || 0) !== 0 ||
          config.forced_bos_token_id != null || config.suppress_tokens != null || config.begin_suppress_tokens != null ||
          (config.bad_words_ids || []).some(word => word.length !== 1 || !validToken(word[0]))) fail('generation_contract');
      model.sessions.push(await ort.InferenceSession.create(await read('encoder_model.onnx'), options));
      model.sessions.push(await ort.InferenceSession.create(await read('decoder_model.onnx'), options));
      names(model.sessions[0].inputNames, ['input_ids', 'attention_mask']);
      names(model.sessions[0].outputNames, ['last_hidden_state']);
      names(model.sessions[1].inputNames, ['decoder_input_ids', 'encoder_hidden_states', 'encoder_attention_mask']);
      names(model.sessions[1].outputNames, ['logits']);
      const fixture = JSON.parse(text(await read('generation_fixtures.json')))[0];
      if (!fixture) fail('missing_generation_fixture');
      const actual = await generate(model, fixture.source_ids, -1);
      if (actual.length !== fixture.generated_ids.length ||
          actual.some((id, index) => id !== fixture.generated_ids[index])) fail('generation_parity');
    }
    if ((await store.metadata(base)).cache !== info.cache) fail('pack_changed');
    models.set(kind, model);
    return true;
  } catch (error) {
    for (const session of model.sessions) await session.release();
    throw error;
  }
}
async function generate(model, ids, requestId) {
  if (!ids.length || ids.length > 512) fail('source_length');
  const [encoder, decoder] = model.sessions;
  const input = int64(ids, [1, ids.length]);
  const mask = int64(new Int32Array(ids.length).fill(1), [1, ids.length]);
  let encoded;
  try {
    encoded = await encoder.run({input_ids: input, attention_mask: mask});
    const config = model.config;
    const prefix = [config.decoder_start_token_id];
    const suppressed = new Set((config.bad_words_ids || []).map(word => word[0]));
    while (prefix.length < config.max_length - 1) {
      await new Promise(resolve => setTimeout(resolve, 0));
      if (cancelled.has(requestId)) fail('cancelled');
      const decoderIds = int64(prefix, [1, prefix.length]);
      let output;
      try {
        output = await decoder.run({decoder_input_ids: decoderIds,
          encoder_hidden_states: encoded.last_hidden_state, encoder_attention_mask: mask});
        const logits = output.logits;
        if (logits.dims.length !== 3 || logits.dims[0] !== 1 || logits.dims[1] !== prefix.length ||
            logits.dims[2] !== model.vocabularySize) fail('logits_contract');
        const count = logits.dims[2];
        const offset = (prefix.length - 1) * count;
        let best = -1;
        for (let i = 0; i < count; i++) {
          if (!Number.isFinite(logits.data[offset + i])) fail('invalid_logits');
          if (!suppressed.has(i) && (best < 0 || logits.data[offset + i] > logits.data[offset + best])) best = i;
        }
        if (best < 0) fail('no_generation_token');
        prefix.push(best);
        if (best === config.eos_token_id) return Int32Array.from(prefix);
      } finally {
        decoderIds.dispose();
        if (output) Object.values(output).forEach(tensor => tensor.dispose());
      }
    }
    fail('translation_length_limit');
  } finally {
    input.dispose(); mask.dispose();
    if (encoded) Object.values(encoded).forEach(tensor => tensor.dispose());
  }
}
async function execute(request) {
  const {operation, base, kind, id} = request;
  if (cancelled.has(id)) fail('cancelled');
  if (operation === 'metadata') return store.metadata(base);
  if (operation === 'read') return new Uint8Array(await store.read(base, request.name, request.cache));
  if (operation === 'status') return store.status(base);
  if (operation === 'load') return load(kind, base);
  if (operation === 'release') { await release(kind); return true; }
  const model = models.get(kind);
  if (!model || model.base !== base) fail('model_not_loaded');
  if ((await store.metadata(base)).cache !== model.cache) { await release(kind); fail('pack_changed'); }
  if (operation === 'translate') return generate(model, request.ids, id);
  if (operation !== 'synthesize') fail('unsupported_operation');
  if (!(request.ids instanceof Int32Array) || !request.ids.length || request.ids.length > 4096) fail('voice_configuration');
  if (!Number.isInteger(request.speaker) || request.speaker < 0 || request.speaker >= model.config.num_speakers ||
      request.scales.length !== 3 || request.scales.some(value => !Number.isFinite(value) || value <= 0)) fail('voice_configuration');
  const inputs = {input: int64(request.ids, [1, request.ids.length]),
    input_lengths: int64([request.ids.length], [1]), scales: new ort.Tensor('float32', request.scales, [3])};
  if (model.config.num_speakers > 1) inputs.sid = int64([request.speaker], [1]);
  let outputs;
  try {
    outputs = await model.sessions[0].run(inputs);
    const tensor = outputs.output;
    if (tensor.dims.slice(0, -1).some(d => d !== 1) || !tensor.data.length ||
        tensor.data.some(value => !Number.isFinite(value)) ||
        !tensor.data.some(value => Math.abs(value) > 1e-7)) fail('invalid_audio');
    return new Float32Array(tensor.data);
  } finally {
    Object.values(inputs).forEach(tensor => tensor.dispose());
    if (outputs) Object.values(outputs).forEach(tensor => tensor.dispose());
  }
}
self.onmessage = event => {
  const request = event.data;
  if (request.operation === 'cancel') {
    if (active.has(request.target)) cancelled.add(request.target);
    installations.get(request.target)?.abort();
    return;
  }
  active.add(request.id);
  const reply = async () => {
    try {
      let value;
      if (request.operation === 'install') {
        const controller = new AbortController();
        installations.set(request.id, controller);
        value = await store.install(request.base, controller.signal,
          progress => self.postMessage({id: request.id, progress}));
      } else { value = await execute(request); }
      if (cancelled.has(request.id)) fail('cancelled');
      const transfer = ArrayBuffer.isView(value) ? [value.buffer] : [];
      self.postMessage({id: request.id, value}, transfer);
    } catch (error) {
      // Only allowlisted reason codes may cross the worker boundary.
      const code = cancelled.has(request.id) ? 'cancelled' :
        error?.name === 'QuotaExceededError' ? 'insufficient_storage' :
        safeErrors.has(error?.message) ? error.message : 'offline_voice_operation_failed';
      self.postMessage({id: request.id, error: code});
    } finally {
      active.delete(request.id);
      cancelled.delete(request.id);
      installations.delete(request.id);
    }
  };
  if (request.operation === 'install') { void reply(); }
  else { tail = tail.then(reply, reply); }
};
