import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:onnxruntime/onnxruntime.dart';

import 'model_artifact.dart';
import 'piper_contract.dart';
import 'piper_phonemizer.dart';

/// Owns all native pointers in one isolate. No pointer crosses a message port.
/// Disposal is queued behind inference, so cancellation cannot free live tensors.
class PiperNativeEngine {
  PiperNativeEngine._();
  final _responses = ReceivePort();
  final _ready = Completer<SendPort>();
  final _pending = <int, Completer<Object?>>{};
  late StreamSubscription<dynamic> _subscription;
  SendPort? _commands;
  int _nextId = 0;
  bool _closed = false;
  Future<void>? _disposing;

  static Future<PiperNativeEngine> load({
    required Uint8List model,
    required ModelArtifact artifact,
    required String config,
    required String language,
    required int speaker,
    String? rules,
  }) async {
    final engine = PiperNativeEngine._();
    engine._subscription = engine._responses.listen(engine._receive);
    try {
      await Isolate.spawn(
        _worker,
        engine._responses.sendPort,
        onError: engine._responses.sendPort,
        onExit: engine._responses.sendPort,
        debugName: 'CareBridge Piper',
      );
      engine._commands = await engine._ready.future;
      await engine._request('load', {
        'model': TransferableTypedData.fromList([model]),
        'artifact': artifact,
        'config': config,
        'language': language,
        'speaker': speaker,
        'rules': rules,
      });
      return engine;
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
          StateError('Piper ${message['stage']} failed (${message['kind']})'),
        );
      } else {
        completer?.complete(message['value']);
      }
    } else {
      _closed = true;
      if (!_ready.isCompleted) {
        _ready.completeError(StateError('Piper worker unavailable'));
      }
      for (final completer in _pending.values) {
        completer.completeError(StateError('Piper worker stopped'));
      }
      _pending.clear();
    }
  }

  Future<Object?> _request(String operation, [Map<String, Object?>? data]) {
    if (_closed || _commands == null) {
      return Future.error(StateError('Piper worker unavailable'));
    }
    final id = ++_nextId;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _commands!.send({'id': id, 'operation': operation, ...?data});
    return completer.future;
  }

  Future<void> validate(String text) async {
    await _request('validate', {'text': text});
  }

  Future<Uint8List> synthesize(String text) async {
    if (_disposing != null) throw StateError('Piper worker disposed');
    final result = await _request('synthesize', {'text': text});
    return (result as TransferableTypedData).materialize().asUint8List();
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
  PiperModelSpec? spec;
  PiperPhonemizer? frontend;
  var speaker = 0;
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
          final nextSpec = PiperModelSpec.fromJson(request['config'] as String);
          speaker = request['speaker'] as int;
          nextSpec.validateSpeaker(speaker);
          final nextFrontend = PiperPhonemizer.fromConfig(
            request['config'] as String,
            request['language'] as String,
            twiRules: request['rules'] as String?,
          );
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
              throw const FormatException('Unsupported Piper output contract');
            }
            session = candidate;
            candidate = null;
            spec = nextSpec;
            frontend = nextFrontend;
          } finally {
            candidate?.release();
            options.release();
          }
          break;
        case 'validate':
          if (frontend == null ||
              frontend!.encode(request['text'] as String).isEmpty) {
            throw const FormatException('Invalid speech');
          }
          break;
        case 'synthesize':
          stage = 'synthesis';
          if (session == null) throw StateError('Piper model unavailable');
          final ids = frontend!.encode(request['text'] as String);
          if (ids.isEmpty) throw const FormatException('Empty speech');
          final inputs = <String, OrtValue>{};
          OrtRunOptions? options;
          List<OrtValue?> outputs = [];
          try {
            inputs['input'] = OrtValueTensor.createTensorWithDataList(
              Int64List.fromList(ids),
              [1, ids.length],
            );
            inputs['input_lengths'] = OrtValueTensor.createTensorWithDataList(
              Int64List.fromList([ids.length]),
              [1],
            );
            inputs['scales'] = OrtValueTensor.createTensorWithDataList(
              spec!.scales,
              [3],
            );
            if (spec!.numSpeakers > 1) {
              inputs['sid'] = OrtValueTensor.createTensorWithDataList(
                Int64List.fromList([speaker]),
                [1],
              );
            }
            options = OrtRunOptions();
            outputs = session!.run(options, inputs, ['output']);
            final audio = PiperAudio.samples(outputs.single?.value);
            result = TransferableTypedData.fromList([
              PiperAudio.wav(audio, spec!.sampleRate),
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
          if (environmentReady) OrtEnv.instance.release();
          commands.close();
          break;
        default:
          throw StateError('Unsupported Piper operation');
      }
      responses.send({'id': request['id'], 'value': result});
    } catch (error) {
      // Native exceptions can include input data. Never forward them to logs/UI.
      responses.send({
        'id': request['id'],
        'error': true,
        'stage': stage,
        'kind': error.runtimeType.toString(),
      });
    }
  });
}
