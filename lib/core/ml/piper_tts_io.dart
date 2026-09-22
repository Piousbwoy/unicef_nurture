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
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'model_artifact.dart';
import 'piper_contract.dart';
import 'piper_native_engine.dart';
import 'piper_tts_runner.dart';

PiperTtsRunner buildPiperTtsRunner() => _IoPiperTtsRunner();

class _IoPiperTtsRunner implements PiperTtsRunner {
  final _models = <String, PiperNativeEngine>{};
  Future<void> _lifecycle = Future.value();

  Future<void> _serialize(Future<void> Function() action) {
    final next = _lifecycle.then((_) => action());
    _lifecycle = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

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
  }) => _serialize(() async {
    if (_models.containsKey(language)) return;
    final manifest = await ModelArtifactManifest.load(
      modelAssetPath,
      'piper-v1',
    );
    final config = await manifest.text(modelAssetPath, 'model.onnx.json');
    final rules = language == 'Twi'
        ? await manifest.text(modelAssetPath, 'twi_rules.json')
        : null;
    // Release the previous pipeline before allocating another model.
    await stop();
    for (final engine in _models.values) {
      await engine.dispose();
    }
    _models.clear();
    final data = await rootBundle.load('$modelAssetPath/model.onnx');
    final engine = await PiperNativeEngine.load(
      model: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      artifact: manifest.file('model.onnx'),
      config: config,
      language: language,
      speaker: speakerId,
      rules: rules,
    );
    _models[language] = engine;
  });

  @override
  Future<void> speak(
    String text, {
    bool waitForCompletion = true,
    void Function()? onStarted,
  }) async {
    final language = _currentLanguage;
    final engine = _models[language];
    if (engine == null) throw StateError('Piper model unavailable');
    final chunks = PiperAudio.chunks(text);
    if (chunks.isEmpty) throw const FormatException('Empty speech');
    // Validate the whole request before playing any of its chunks in the worker.
    final stopped = stop();
    final generation = _generation;
    await stopped;
    if (generation != _generation) throw StateError('Piper stopped');
    await engine.validate(text);
    if (generation != _generation) throw StateError('Piper stopped');
    _currentLanguage = language;
    final started = Completer<void>();
    void began() {
      if (!started.isCompleted) {
        started.complete();
        onStarted?.call();
      }
    }

    Future<void> play() async {
      try {
        for (final chunk in chunks) {
          if (generation != _generation) throw StateError('Piper stopped');
          final wav = await engine.synthesize(chunk);
          if (generation != _generation) throw StateError('Piper stopped');
          await _playWav(wav, generation, began);
        }
      } finally {
        if (generation == _generation) _currentLanguage = null;
      }
    }

    final playback = play();
    if (waitForCompletion) {
      await playback;
    } else {
      unawaited(
        playback.then<void>(
          (_) {
            if (!started.isCompleted)
              started.completeError(StateError('Piper did not start'));
          },
          onError: (Object _, StackTrace __) {
            if (!started.isCompleted)
              started.completeError(StateError('Piper playback failed'));
          },
        ),
      );
      await started.future;
    }
  }

  @override
  Future<void> speakNonBlocking(String text) =>
      speak(text, waitForCompletion: false);

  @override
  Future<void> stop() async {
    _generation++;
    final player = _player;
    final done = _playbackDone;
    _player = null;
    _playbackDone = null;
    _currentLanguage = null;
    if (done != null && !done.isCompleted) done.complete();
    try {
      await player?.stop();
    } catch (_) {}
    // The request's finally block owns player disposal and its temporary file.
  }

  @override
  void setActiveLanguage(String language) {
    _currentLanguage = language;
  }

  @override
  bool hasModel(String language) => _models.containsKey(language);

  @override
  Future<void> dispose(String language) => _serialize(() async {
    final engine = _models.remove(language);
    if (_currentLanguage == language) await stop();
    await engine?.dispose();
  });

  // ─── Playback ───────────────────────────────────────────────────────────────

  int _generation = 0;

  Future<void> _playWav(
    Uint8List wavBytes,
    int generation,
    void Function()? onStarted,
  ) async {
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
      void failed(Object _) {
        if (!done.isCompleted)
          done.completeError(StateError('Audio playback failed'));
      }

      // Observe errors immediately, even while setSource/resume is awaiting.
      unawaited(
        done.future.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
      );
      completion = activePlayer.onPlayerComplete.listen((_) {
        if (generation == _generation && !done.isCompleted) done.complete();
      }, onError: failed);
      states = activePlayer.onPlayerStateChanged.listen((state) {
        if (generation == _generation && state == PlayerState.playing) {
          onStarted?.call();
        }
      }, onError: failed);
      await activePlayer.setSource(DeviceFileSource(tmpFile.path));
      check();
      await activePlayer.resume();
      check();
      await done.future.timeout(const Duration(minutes: 3));
      check();
    } finally {
      await completion?.cancel();
      await states?.cancel();
      try {
        await player?.dispose();
      } catch (_) {}
      if (identical(_player, player)) _player = null;
      if (identical(_playbackDone, done)) _playbackDone = null;
      await tmpFile.delete().catchError((_) => tmpFile);
    }
  }
}
