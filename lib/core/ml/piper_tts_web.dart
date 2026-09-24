import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'piper_contract.dart';
import 'piper_phonemizer.dart';
import 'piper_tts_runner.dart';
import 'voice_web_bridge.dart';

PiperTtsRunner buildPiperTtsRunner() => _WebPiperTtsRunner();

class _WebPiperTtsRunner implements PiperTtsRunner {
  String? _language;
  String? _base;
  PiperModelSpec? _spec;
  PiperPhonemizer? _frontend;
  int _speaker = 0;
  int _generation = 0;
  bool _speaking = false;
  VoiceWebTask? _task;
  Future<void> _tail = Future.value();
  Future<void> _serial(Future<void> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  @override
  bool get available => VoiceWebBridge.available;
  @override
  bool get isSpeaking => _speaking;
  @override
  bool hasModel(String language) => _language == language && _frontend != null;
  @override
  void setActiveLanguage(String language) {
    if (!hasModel(language)) throw StateError('Voice pack not loaded');
  }

  @override
  Future<void> init({
    required String language,
    required String modelAssetPath,
    required int speakerId,
  }) => _serial(() async {
    await stop();
    _language = null;
    _frontend = null;
    final base = 'assets/$modelAssetPath';
    final info = await VoiceWebBridge.metadata(base);
    final cache = info['cache'] as String;
    final config = await VoiceWebBridge.text(base, 'model.onnx.json', cache);
    final spec = PiperModelSpec.fromJson(config)..validateSpeaker(speakerId);
    final frontend = PiperPhonemizer.fromConfig(
      config,
      language,
      twiRules: language == 'Twi'
          ? await VoiceWebBridge.text(base, 'twi_rules.json', cache)
          : null,
    );
    await VoiceWebBridge.call('load', {'kind': 'piper', 'base': base});
    if ((await VoiceWebBridge.metadata(base))['cache'] != cache) {
      throw StateError('Voice pack changed');
    }
    _base = base;
    _spec = spec;
    _speaker = speakerId;
    _frontend = frontend;
    _language = language;
  });
  @override
  Future<void> speak(
    String text, {
    bool waitForCompletion = true,
    void Function()? onStarted,
    SpeechProsody prosody = SpeechProsody.standard,
  }) async {
    final stopping = stop();
    final generation = _generation;
    await stopping;
    if (generation != _generation) throw StateError('Speech cancelled');
    final frontend = _frontend;
    final spec = _spec;
    final base = _base;
    if (frontend == null || spec == null || base == null) {
      throw StateError('Voice pack not loaded');
    }
    frontend.encode(text); // Validate the entire utterance before any audio.
    final chunks = PiperAudio.chunks(text);
    if (chunks.isEmpty) throw const FormatException('Empty speech');
    final started = Completer<void>();
    Future<void> run() async {
      try {
        for (final chunk in chunks) {
          if (generation != _generation) throw StateError('Speech cancelled');
          final task = VoiceWebBridge.start('synthesize', {
            'kind': 'piper',
            'base': base,
            'ids': Int32List.fromList(frontend.encode(chunk)).toJS,
            'scales': Float32List.fromList(spec.scalesFor(prosody)).toJS,
            'speaker': _speaker,
          });
          _task = task;
          final samples = ((await task.result) as JSFloat32Array).toDart;
          if (generation != _generation) throw StateError('Speech cancelled');
          final completed = await VoiceWebBridge.play(
            PiperAudio.samples(samples),
            spec.sampleRate,
            () {
              if (generation != _generation) return;
              _speaking = true;
              if (!started.isCompleted) {
                started.complete();
                onStarted?.call();
              }
            },
          );
          if (!completed || generation != _generation) {
            throw StateError('Speech cancelled');
          }
        }
      } finally {
        if (generation == _generation) {
          _speaking = false;
          _task = null;
        }
      }
    }

    final playback = run();
    if (waitForCompletion) {
      await playback;
    } else {
      unawaited(
        playback.then<void>(
          (_) {},
          onError: (Object error, StackTrace stack) {
            if (!started.isCompleted) started.completeError(error, stack);
          },
        ),
      );
      await started.future;
    }
  }

  @override
  Future<void> speakNonBlocking(
    String text, {
    SpeechProsody prosody = SpeechProsody.standard,
  }) => speak(text, waitForCompletion: false, prosody: prosody);
  @override
  Future<void> stop() async {
    ++_generation;
    _speaking = false;
    _task?.cancel();
    _task = null;
    if (available) VoiceWebBridge.stop();
  }

  @override
  Future<void> dispose(String language) => _serial(() async {
    if (_language != language) return;
    await stop();
    _frontend = null;
    _spec = null;
    _language = null;
    _base = null;
    await VoiceWebBridge.call('release', {'kind': 'piper'});
  });
}
