import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:onnxruntime/onnxruntime.dart';

import 'marian_contract.dart';
import 'marian_tokenizer.dart';
import 'model_artifact.dart';
import 'native_inference_worker.dart';

class MarianNativeEngine {
  MarianNativeEngine._(this._worker);
  final NativeInferenceWorker _worker;

  static Future<MarianNativeEngine> load(
    ModelArtifactManifest manifest,
    Map<String, Uint8List> artifacts,
  ) async {
    final worker = await NativeInferenceWorker.start(_marianWorker);
    try {
      await worker.request('load', {
        'manifest': manifest,
        'artifacts': artifacts.map(
          (name, bytes) =>
              MapEntry(name, TransferableTypedData.fromList([bytes])),
        ),
      });
      return MarianNativeEngine._(worker);
    } catch (_) {
      await worker.dispose();
      rethrow;
    }
  }

  Future<String> translate(String text) async =>
      (await _worker.request('translate', {'text': text})) as String;
  Future<void> dispose() => _worker.dispose();
}

void _marianWorker(SendPort responses) {
  final commands = ReceivePort();
  responses.send(commands.sendPort);
  _MarianSession? session;
  commands.listen((dynamic message) {
    final request = message as Map;
    var stage = 'request';
    try {
      Object? value;
      switch (request['operation']) {
        case 'load':
          final manifest = request['manifest'] as ModelArtifactManifest;
          stage = 'integrity';
          final artifacts = (request['artifacts'] as Map)
              .map<String, Uint8List>((name, value) {
                final bytes = (value as TransferableTypedData)
                    .materialize()
                    .asUint8List();
                manifest.file(name as String).verify(bytes);
                return MapEntry(name, bytes);
              });
          session = _MarianSession(artifacts, (value) => stage = value);
          break;
        case 'translate':
          stage = 'translate';
          if (session == null) {
            throw StateError('Translation model unavailable');
          }
          value = session!.translate(request['text'] as String);
          break;
        case 'dispose':
          session?.dispose();
          commands.close();
          break;
        default:
          throw StateError('Unsupported inference operation');
      }
      responses.send({'id': request['id'], 'value': value});
    } catch (error) {
      responses.send({
        'id': request['id'],
        'error': true,
        'stage': stage,
        'kind': error.runtimeType.toString(),
      });
    }
  });
}

class _MarianSession {
  _MarianSession(Map<String, Uint8List> files, void Function(String) stage) {
    stage('tokenizer');
    tokenizer = MarianTokenizer(
      sourceModel: files['source.spm']!,
      targetModel: files['target.spm']!,
      vocabulary: utf8.decode(files['vocab.json']!),
      fixtures: utf8.decode(files['tokenizer_fixtures.json']!),
    );
    generation = MarianGeneration(
      utf8.decode(files['generation_config.json']!),
      vocabularySize: tokenizer.vocabularySize,
    );
    if (generation.eos != tokenizer.eos || generation.pad != tokenizer.pad) {
      throw const FormatException(
        'Mismatched tokenizer and generation contract',
      );
    }
    stage('runtime');
    OrtEnv.instance.init();
    final options = OrtSessionOptions();
    try {
      options.setInterOpNumThreads(1);
      options.setIntraOpNumThreads(2);
      stage('encoder');
      encoder = OrtSession.fromBuffer(files['encoder_model.onnx']!, options);
      stage('decoder');
      decoder = OrtSession.fromBuffer(files['decoder_model.onnx']!, options);
      if (files.containsKey('proj_model.onnx')) {
        stage('projection');
        proj = OrtSession.fromBuffer(files['proj_model.onnx']!, options);
      }
      stage('tensor-contract');
      _names(encoder!.inputNames, ['input_ids', 'attention_mask']);
      _names(encoder!.outputNames, ['last_hidden_state']);
      _names(decoder!.inputNames, [
        'decoder_input_ids',
        'encoder_hidden_states',
        'encoder_attention_mask',
      ]);
      _names(decoder!.outputNames, [
        proj == null ? 'logits' : 'decoder_hidden_states',
      ]);
      if (proj != null) {
        _names(proj!.inputNames, ['hidden_states']);
        _names(proj!.outputNames, ['logits']);
      }
      // A valid manifest alone does not prove that the graph returns logits.
      final fixtures =
          jsonDecode(utf8.decode(files['generation_fixtures.json']!)) as List;
      if (fixtures.isEmpty) {
        throw const FormatException('Missing generation fixture');
      }
      final probe = fixtures.first as Map;
      stage('generation-parity');
      final result = _generate(List<int>.from(probe['source_ids']));
      final expected = List<int>.from(probe['generated_ids']);
      if (result.length != expected.length ||
          List.generate(
            result.length,
            (i) => result[i] == expected[i],
          ).contains(false)) {
        throw const FormatException('Native generation parity failed');
      }
    } catch (_) {
      dispose();
      rethrow;
    } finally {
      options.release();
    }
  }
  late final MarianTokenizer tokenizer;
  late final MarianGeneration generation;
  OrtSession? encoder;
  OrtSession? decoder;
  OrtSession? proj;

  void _names(List<String> actual, List<String> expected) {
    if (actual.length != expected.length ||
        !actual.toSet().containsAll(expected)) {
      throw const FormatException('Incompatible Marian tensor contract');
    }
  }

  String translate(String text) {
    if (text.trim().isEmpty || text.length > 4000) {
      throw const FormatException('Invalid translation length');
    }
    final ids = tokenizer.encode(text);
    if (ids.length > 512) {
      throw const FormatException('Translation requires sentence chunking');
    }
    if (ids.contains(tokenizer.unknown)) {
      throw const FormatException('Unsupported source symbols');
    }
    final output = _generate(ids);
    if (output.contains(tokenizer.unknown)) {
      throw const FormatException('Unknown translation token');
    }
    final translated = tokenizer.decode(output).trim();
    if (translated.isEmpty ||
        translated.toLowerCase() == text.trim().toLowerCase()) {
      throw const FormatException('Model did not translate this message');
    }
    return translated;
  }

  List<int> _generate(List<int> ids) {
    final inputs = <String, OrtValue>{};
    OrtRunOptions? options;
    List<OrtValue?> encoded = [];
    try {
      inputs['input_ids'] = OrtValueTensor.createTensorWithDataList(
        Int64List.fromList(ids),
        [1, ids.length],
      );
      inputs['attention_mask'] = OrtValueTensor.createTensorWithDataList(
        Int64List.fromList(List.filled(ids.length, 1)),
        [1, ids.length],
      );
      options = OrtRunOptions();
      encoded = encoder!.run(options, inputs, ['last_hidden_state']);
      final prefix = <int>[generation.start];
      // Never return a forced/truncated sentence as a successful translation.
      while (prefix.length < generation.maxLength - 1) {
        OrtValue? decoderIds;
        List<OrtValue?> outputs = [];
        List<OrtValue?> logits = [];
        try {
          decoderIds = OrtValueTensor.createTensorWithDataList(
            Int64List.fromList(prefix),
            [1, prefix.length],
          );
          outputs = decoder!.run(
            options,
            {
              'decoder_input_ids': decoderIds,
              'encoder_hidden_states': encoded.single!,
              'encoder_attention_mask': inputs['attention_mask']!,
            },
            [proj == null ? 'logits' : 'decoder_hidden_states'],
          );
          if (proj != null) {
            logits = proj!.run(
              options,
              {'hidden_states': outputs.single!},
              ['logits'],
            );
          }
          final raw = (proj == null ? outputs : logits).single?.value;
          if (raw is! List || raw.length != 1 || raw.single is! List) {
            throw const FormatException('Invalid decoder logits rank');
          }
          final sequence = raw.single as List;
          if (sequence.length != prefix.length || sequence.last is! List) {
            throw const FormatException('Invalid decoder logits sequence');
          }
          final token = generation.nextToken(
            List<num>.from(sequence.last as List),
          );
          prefix.add(token);
          if (token == generation.eos) return prefix;
        } finally {
          for (final output in logits) {
            output?.release();
          }
          for (final output in outputs) {
            output?.release();
          }
          decoderIds?.release();
        }
      }
      throw const FormatException('Translation length limit reached');
    } finally {
      for (final value in encoded) {
        value?.release();
      }
      for (final value in inputs.values) {
        value.release();
      }
      options?.release();
    }
  }

  void dispose() {
    proj?.release();
    decoder?.release();
    encoder?.release();
    proj = null;
    decoder = null;
    encoder = null;
    OrtEnv.instance.release();
  }
}
