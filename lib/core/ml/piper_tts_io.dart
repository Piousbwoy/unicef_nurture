/// Native Piper TTS runner using the existing `onnxruntime` Dart FFI binding.
///
/// Loads a Piper VITS ONNX model and runs inference directly — no additional
/// native dependencies beyond the `onnxruntime` package already used for
/// neural translation. The phonemizer is rule-based (Hausa/Twi are phonemic).
///
/// Pipeline: text → PiperPhonemizer.encode() → phoneme IDs → OrtSession.run()
///           → Float32List audio → WAV bytes → audioplayers playback.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:onnxruntime/onnxruntime.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'piper_phonemizer.dart';
import 'piper_tts_runner.dart';

PiperTtsRunner buildPiperTtsRunner() => _IoPiperTtsRunner();

/// Per-language loaded model state.
class _PiperModel {
  _PiperModel({
    required this.session,
    required this.phonemizer,
    required this.sampleRate,
    required this.inputNames,
    required this.outputName,
    required this.speakerId,
  });
  final OrtSession session;
  final PiperPhonemizer phonemizer;
  final int sampleRate;
  final List<String> inputNames;
  final String outputName;
  final int speakerId;
}

class _IoPiperTtsRunner implements PiperTtsRunner {
  final _models = <String, _PiperModel>{};
  final _loadErrors = <String, Object>{};
  String? _currentLanguage;
  AudioPlayer? _player;
  Completer<void>? _playbackDone;

  @override
  bool get available => true;

  @override
  bool get isSpeaking => _currentLanguage != null && _player != null;

  @override
  Future<void> init({
    required String language,
    required String modelAssetPath,
    required int speakerId,
  }) async {
    if (_models.containsKey(language) || _loadErrors.containsKey(language)) {
      return;
    }
    try {
      // Load model config JSON (phoneme_id_map, sample_rate, espeak variant).
      final configAsset = '$modelAssetPath/model.onnx.json';
      final configData = await rootBundle.loadString(configAsset);
      final cfg = jsonDecode(configData) as Map<String, dynamic>;

      final sampleRate =
          (cfg['audio'] as Map<String, dynamic>?)?['sample_rate'] as int? ??
              22050;

      // Build phonemizer from config.
      final phonemizer = PiperPhonemizer.fromConfig(configData, language);

      // Copy model.onnx to device storage (OrtSession requires a file path).
      final dir = await getApplicationSupportDirectory();
      final ttsDir = Directory(p.join(dir.path, 'piper_models', language));
      await ttsDir.create(recursive: true);
      final modelPath = p.join(ttsDir.path, 'model.onnx');
      final modelFile = File(modelPath);
      if (!await modelFile.exists() || await modelFile.length() == 0) {
        final data = await rootBundle.load('$modelAssetPath/model.onnx');
        await modelFile.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
      }

      // Initialize ONNX Runtime environment (idempotent).
      OrtEnv.instance.init();

      // Create session.
      final sessionOptions = OrtSessionOptions();
      sessionOptions.setInterOpNumThreads(1);
      sessionOptions.setIntraOpNumThreads(4);

      final session = OrtSession.fromFile(File(modelPath), sessionOptions);

      // Discover input/output names from the model.
      final inputNames = session.inputNames;
      final outputNames = session.outputNames;

      // Piper VITS typically has output named "output" or similar.
      final outputName = outputNames.isNotEmpty ? outputNames.first : 'output';

      _models[language] = _PiperModel(
        session: session,
        phonemizer: phonemizer,
        sampleRate: sampleRate,
        inputNames: inputNames,
        outputName: outputName,
        speakerId: speakerId,
      );

      debugPrint(
        'PiperTts[$language]: loaded (${inputNames.length} inputs, '
        'sr=$sampleRate, speaker=$speakerId)',
      );
    } catch (e) {
      _loadErrors[language] = e;
      debugPrint('PiperTts[$language]: load failed — $e');
    }
  }

  @override
  Future<void> speak(String text, {bool waitForCompletion = true, void Function()? onStarted}) async {
    final generation = ++_generation;
    final language = _currentLanguage;
    final model = _models[language];
    if (model == null) throw StateError('Piper model unavailable');
    try {
      final pcm = _runInference(model, text);
      if (pcm == null || pcm.isEmpty) throw StateError('Piper synthesis failed');
      if (generation != _generation) throw StateError('Piper stopped');
      final wav = _pcmToWav(pcm, model.sampleRate);
      await _playWav(wav, waitForCompletion, generation, onStarted);
    } finally {
      if (generation == _generation) _currentLanguage = null;
    }
  }

  @override
  Future<void> speakNonBlocking(String text) =>
      speak(text, waitForCompletion: false);

  @override
  Future<void> stop() async {
    _generation++;
    try {
      await _player?.stop();
      await _player?.dispose();
    } catch (_) {}
    _player = null;
    _currentLanguage = null;
    if (_playbackDone != null && !_playbackDone!.isCompleted) {
      _playbackDone!.complete();
    }
  }

  @override
  void setActiveLanguage(String language) {
    _currentLanguage = language;
  }

  @override
  bool hasModel(String language) => _models.containsKey(language);

  @override
  Future<void> dispose(String language) async {
    final model = _models.remove(language);
    if (_currentLanguage == language) _currentLanguage = null;
    try {
      model?.session.release();
    } catch (_) {}
  }

  // ─── Inference ──────────────────────────────────────────────────────────────

  /// Run VITS inference on the loaded session. Returns PCM Float32List.
  Float32List? _runInference(_PiperModel model, String text) {
    final phonemeIds = model.phonemizer.encode(text);
    if (phonemeIds.isEmpty) return null;

    final seqLen = phonemeIds.length;

    // Build input tensors matching Piper's expected I/O names.
    // Typical Piper VITS inputs:
    //   input         int64[1, N]
    //   input_lengths int64[1]
    //   sid           int64[1]
    //   length_scale    float32[1]
    //   noise_scale     float32[1]
    //   noise_w_scale   float32[1]
    final inputs = <String, OrtValue>{};

    for (final name in model.inputNames) {
      if (name == 'input' || name == 'text') {
        inputs[name] = OrtValueTensor.createTensorWithDataList(
          phonemeIds, [1, seqLen],
        );
      } else if (name == 'input_lengths' || name == 'text_lengths') {
        inputs[name] = OrtValueTensor.createTensorWithDataList(
          <int>[seqLen], [1],
        );
      } else if (name == 'sid' || name == 'speaker_id') {
        inputs[name] = OrtValueTensor.createTensorWithDataList(
          <int>[model.speakerId], [1],
        );
      } else if (name == 'length_scale') {
        inputs[name] = OrtValueTensor.createTensorWithData(1.0);
      } else if (name == 'noise_scale') {
        inputs[name] = OrtValueTensor.createTensorWithData(0.667);
      } else if (name == 'noise_w' || name == 'noise_w_scale') {
        inputs[name] = OrtValueTensor.createTensorWithData(0.8);
      }
    }

    // Run.
    final runOptions = OrtRunOptions();
    final outputs = model.session.run(runOptions, inputs, [model.outputName]);

    // Extract audio.
    final outputTensor = outputs.first;
    if (outputTensor is! OrtValueTensor) return null;
    final rawValue = outputTensor.value;

    Float32List samples;
    if (rawValue is List<List<double>>) {
      // Shape [1, N]
      samples = Float32List.fromList(rawValue.first);
    } else if (rawValue is List<double>) {
      samples = Float32List.fromList(rawValue);
    } else if (rawValue is double) {
      return null;
    } else {
      return null;
    }

    // Release.
    for (final t in inputs.values) {
      t.release();
    }
    runOptions.release();
    for (final o in outputs) {
      o?.release();
    }

    return samples;
  }

  // ─── Playback ───────────────────────────────────────────────────────────────

  int _generation = 0;

  Future<void> _playWav(Uint8List wavBytes, bool waitForCompletion,
      int generation, void Function()? onStarted) async {
    void check() {
      if (generation != _generation) throw StateError('Piper stopped');
    }
    final dir = await getTemporaryDirectory();
    check();
    final tmpFile = File(
      p.join(dir.path, 'piper_${DateTime.now().microsecondsSinceEpoch}.wav'),
    );
    AudioPlayer? player;
    StreamSubscription<void>? completion;
    StreamSubscription<PlayerState>? states;
    final done = Completer<void>();
    try {
      await tmpFile.writeAsBytes(wavBytes, flush: true);
      check();
      final activePlayer = player = AudioPlayer();
      _player = activePlayer;
      _playbackDone = done;
      completion = activePlayer.onPlayerComplete.listen((_) {
        if (generation == _generation && !done.isCompleted) done.complete();
      });
      states = activePlayer.onPlayerStateChanged.listen((state) {
        if (generation == _generation && state == PlayerState.playing) {
          onStarted?.call();
        }
      });
      await activePlayer.setSource(DeviceFileSource(tmpFile.path));
      check();
      await activePlayer.resume();
      check();
      await done.future.timeout(const Duration(minutes: 3));
      check();
    } finally {
      await completion?.cancel();
      await states?.cancel();
      try { await player?.dispose(); } catch (_) {}
      if (identical(_player, player)) _player = null;
      if (identical(_playbackDone, done)) _playbackDone = null;
      await tmpFile.delete().catchError((_) => tmpFile);
    }
  }

  // ─── WAV encoding ───────────────────────────────────────────────────────────

  Uint8List _pcmToWav(Float32List samples, int sampleRate) {
    // Convert float [-1,1] → int16.
    final int16Data = Int16List(samples.length);
    for (var i = 0; i < samples.length; i++) {
      final clamped = samples[i].clamp(-1.0, 1.0);
      int16Data[i] = (clamped * 32767).toInt();
    }

    final dataSize = int16Data.lengthInBytes;
    final fileSize = 44 + dataSize;
    final wav = Uint8List(fileSize);
    final bd = wav.buffer.asByteData();

    // RIFF header.
    wav.setRange(0, 4, utf8.encode('RIFF'));
    bd.setUint32(4, fileSize - 8, Endian.little);
    wav.setRange(8, 12, utf8.encode('WAVE'));

    // fmt chunk.
    wav.setRange(12, 16, utf8.encode('fmt '));
    bd.setUint32(16, 16, Endian.little); // chunk size
    bd.setUint16(20, 1, Endian.little);  // PCM format
    bd.setUint16(22, 1, Endian.little);  // mono
    bd.setUint32(24, sampleRate, Endian.little);
    bd.setUint32(28, sampleRate * 2, Endian.little); // byte rate
    bd.setUint16(32, 2, Endian.little);  // block align
    bd.setUint16(34, 16, Endian.little); // bits per sample

    // data chunk.
    wav.setRange(36, 40, utf8.encode('data'));
    bd.setUint32(40, dataSize, Endian.little);
    wav.buffer.asUint8List().setRange(
      44, 44 + dataSize, int16Data.buffer.asUint8List(),
    );

    return wav;
  }
}
