import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:onnxruntime/onnxruntime.dart';

import 'asr_contract.dart';
import 'model_artifact.dart';

/// Runs one ASR pack on its own isolate. Mirrors [PiperNativeEngine]: all
/// native pointers stay inside one isolate and no pointer crosses a port, so a
/// cancelled listen can never free a tensor the encoder is still reading.
class AsrNativeEngine {
  AsrNativeEngine._();
  final _responses = ReceivePort();
  final _ready = Completer<SendPort>();
  final _pending = <int, Completer<Object?>>{};
  late StreamSubscription<dynamic> _subscription;
  SendPort? _commands;
  AsrModelSpec? _spec;
  int _nextId = 0;
  bool _closed = false;
  Future<void>? _disposing;

  static Future<({AsrNativeEngine engine, AsrModelSpec spec})> load({
    required Uint8List model,
    required ModelArtifact artifact,
    required String config,
  }) async {
    final engine = AsrNativeEngine._();
    engine._subscription = engine._responses.listen(engine._receive);
    try {
      await Isolate.spawn(
        _worker,
        engine._responses.sendPort,
        onError: engine._responses.sendPort,
        onExit: engine._responses.sendPort,
        debugName: 'CareBridge ASR',
      );
      engine._commands = await engine._ready.future;
      final value = await engine._request('load', {
        'model': TransferableTypedData.fromList([model]),
        'artifact': artifact,
        'config': config,
      });
      engine._spec = AsrModelSpec.fromJson(value as String);
      return (engine: engine, spec: engine._spec!);
    } catch (_) {
      await engine.dispose();
      rethrow;
    }
  }

  void _receive(dynamic message) {
    if (message is SendPort) {
      _ready.complete(message);
    } else if (message is Map) {
      final completer = _pending.remove(message['id']);
      if (message['error'] == true) {
        completer?.completeError(
          StateError(
            'Speech recogniser ${message['stage']} failed (${message['kind']})',
          ),
        );
      } else {
        completer?.complete(message['value']);
      }
    } else {
      _closed = true;
      if (!_ready.isCompleted) {
        _ready.completeError(StateError('Speech recogniser unavailable'));
      }
      for (final completer in _pending.values) {
        completer.completeError(StateError('Speech recogniser stopped'));
      }
      _pending.clear();
    }
  }

  Future<Object?> _request(String operation, [Map<String, Object?>? data]) {
    if (_closed || _commands == null) {
      return Future.error(StateError('Speech recogniser unavailable'));
    }
    final id = ++_nextId;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _commands!.send({'id': id, 'operation': operation, ...?data});
    return completer.future;
  }

  /// Feeds `frames x inputDim` features, plus the attention mask when the pack
  /// declares one, and returns the encoder's frame posteriors as `rows x labels`.
  /// The rows are the encoder's own: a wav2vec2-Bert stack halves them again
  /// through its adapter, so they cannot be assumed to equal `frames`.
  Future<List<Float32List>> encode(Float32List features, int frames) async {
    if (_disposing != null) throw StateError('Speech recogniser disposed');
    final flat =
        (await _request('encode', {
              'features': TransferableTypedData.fromList([features]),
              'frames': frames,
            }))
            as TransferableTypedData;
    final values = flat.materialize().asFloat32List();
    final labels = _spec!.labels.length;
    if (values.isEmpty || values.length % labels != 0) {
      throw const FormatException(
        'ASR output disagrees with the label inventory',
      );
    }
    final rows = values.length ~/ labels;
    return [
      for (var t = 0; t < rows; t++)
        Float32List.sublistView(values, t * labels, (t + 1) * labels),
    ];
  }

  Future<void> dispose() => _disposing ??= _dispose();

  Future<void> _dispose() async {
    try {
      if (!_closed && _commands != null) await _request('dispose');
    } finally {
      _closed = true;
      await _subscription.cancel();
      _responses.close();
    }
  }
}

void _worker(SendPort responses) {
  final commands = ReceivePort();
  responses.send(commands.sendPort);
  OrtSession? session;
  AsrModelSpec? spec;
  var environmentReady = false;
  commands.listen((dynamic message) {
    final request = message as Map;
    var stage = 'contract';
    try {
      Object? result;
      switch (request['operation']) {
        case 'load':
          final bytes = (request['model'] as TransferableTypedData)
              .materialize()
              .asUint8List();
          stage = 'integrity';
          (request['artifact'] as ModelArtifact).verify(bytes);
          stage = 'frontend';
          final nextSpec = AsrModelSpec.fromJson(request['config'] as String);
          stage = 'runtime';
          OrtEnv.instance.init();
          environmentReady = true;
          final options = OrtSessionOptions();
          OrtSession? candidate;
          try {
            options.setInterOpNumThreads(1);
            options.setIntraOpNumThreads(2);
            stage = 'session';
            candidate = OrtSession.fromBuffer(bytes, options);
            stage = 'tensor-contract';
            nextSpec.validateInputs(candidate.inputNames);
            if (candidate.outputNames.length != 1 ||
                candidate.outputNames.single != 'output') {
              throw const FormatException('Unsupported ASR output contract');
            }
            session = candidate;
            candidate = null;
            spec = nextSpec;
            // Round-tripped back so the caller builds its own view of the same
            // validated contract instead of re-parsing a string it trusts.
            result = request['config'] as String;
          } finally {
            candidate?.release();
            options.release();
          }
          break;
        case 'encode':
          stage = 'encode';
          if (session == null || spec == null) {
            throw StateError('Speech model unavailable');
          }
          final features = (request['features'] as TransferableTypedData)
              .materialize()
              .asFloat32List();
          final frames = request['frames'] as int;
          final inputs = <String, OrtValue>{};
          OrtRunOptions? options;
          List<OrtValue?> outputs = [];
          try {
            for (final name in spec!.inputNames) {
              inputs[name] = name == 'attention_mask'
                  ? OrtValueTensor.createTensorWithDataList(
                      // An un padded take attends every frame it produced.
                      Int64List.fromList(List.filled(frames, 1)),
                      [1, frames],
                    )
                  : spec!.isWaveform
                  // A waveform pack is fed one value per sample: its frame axis
                  // *is* the time axis, so there is no third dimension to claim.
                  ? OrtValueTensor.createTensorWithDataList(features, [
                      1,
                      frames,
                    ])
                  : OrtValueTensor.createTensorWithDataList(features, [
                      1,
                      frames,
                      spec!.inputDim,
                    ]);
            }
            options = OrtRunOptions();
            outputs = session!.run(options, inputs, ['output']);
            final value = outputs.single?.value;
            if (value is! List ||
                value.length != 1 ||
                value.single is! List ||
                (value.single as List).isEmpty ||
                (value.single as List).first is! List) {
              throw const FormatException('Invalid ASR output');
            }
            result = TransferableTypedData.fromList([
              // The graph ends in a linear layer, so its rows are logits: the
              // decoder takes the log of each value, and the log of a logit is
              // not a log-probability. Without this softmax the closed set ranks
              // by an accident of scale, `perFrame` comes out positive, and the
              // absolute floor that is supposed to refuse silence refuses
              // nothing at all.
              _softmax(
                Float32List.fromList(
                  _flatten(value.single).map((v) => v.toDouble()).toList(),
                ),
                spec!.labels.length,
              ),
            ]);
          } finally {
            for (final output in outputs) {
              output?.release();
            }
            for (final input in inputs.values) {
              input.release();
            }
            options?.release();
          }
          break;
        case 'dispose':
          session?.release();
          session = null;
          spec = null;
          if (environmentReady) OrtEnv.instance.release();
          commands.close();
          break;
        default:
          throw StateError('Unsupported ASR operation');
      }
      responses.send({'id': request['id'], 'value': result});
    } catch (error) {
      // Native errors can echo input tensors. Never forward them to logs or UI.
      responses.send({
        'id': request['id'],
        'error': true,
        'stage': stage,
        'kind': error.runtimeType.toString(),
      });
    }
  });
}

/// Each row of `frames x labels` becomes a probability distribution.
Float32List _softmax(Float32List logits, int labels) {
  final out = Float32List(logits.length);
  for (var row = 0; row * labels < logits.length; row++) {
    final start = row * labels;
    final end = (start + labels).clamp(0, logits.length);
    var top = logits[start];
    for (var i = start + 1; i < end; i++) {
      if (logits[i] > top) top = logits[i];
    }
    var sum = 0.0;
    for (var i = start; i < end; i++) {
      sum += math.exp(logits[i] - top);
    }
    for (var i = start; i < end; i++) {
      out[i] = math.exp(logits[i] - top) / sum;
    }
  }
  return out;
}

List<num> _flatten(Object? value) {
  if (value is List) return value.expand(_flatten).toList();
  return [value as num];
}
