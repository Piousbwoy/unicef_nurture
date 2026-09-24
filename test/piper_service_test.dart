import 'dart:async';

import 'package:carebridge_ai/core/ml/piper_contract.dart';
import 'package:carebridge_ai/core/ml/piper_tts_runner.dart';
import 'package:carebridge_ai/core/ml/piper_tts_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('service starts without eagerly loading every language', () async {
    final runner = _Runner();
    final service = PiperTtsService.debugCreate(runner: runner);
    await service.initialize();
    expect(runner.loads, 0);
    expect(service.supportsLanguage('Twi'), isFalse);
  });
  test(
    'concurrent initialization deduplicates and failure can retry',
    () async {
      final runner = _Runner()
        ..gate = Completer<void>()
        ..fail = true;
      final service = PiperTtsService.debugCreate(runner: runner);
      final first = service.initializeLanguage('Twi');
      final second = service.initializeLanguage('Twi');
      expect(identical(first, second), isTrue);
      runner.gate!.complete();
      await Future.wait([first, second]);
      expect(service.supportsLanguage('Twi'), isFalse);
      runner.fail = false;
      await service.initializeLanguage('Twi');
      expect(runner.loads, 2);
      expect(service.supportsLanguage('Twi'), isTrue);
      expect(service.voiceLabelFor('Twi'), contains('twi-6'));
    },
  );
  test(
    'readiness follows runner eviction rather than stale service state',
    () async {
      final runner = _Runner();
      final service = PiperTtsService.debugCreate(runner: runner);
      await service.initializeLanguage('Twi');
      await service.initializeLanguage('Hausa');
      expect(service.supportsLanguage('Twi'), isFalse);
      expect(service.supportsLanguage('Hausa'), isTrue);
    },
  );
  test('disposal waits for pending loads and leaves no loaded model', () async {
    final runner = _Runner()..gate = Completer<void>();
    final service = PiperTtsService.debugCreate(runner: runner);
    final loading = service.initializeLanguage('Twi');
    final disposing = service.dispose();
    await service.initializeLanguage('Hausa');
    expect(runner.loads, 1);
    runner.gate!.complete();
    await Future.wait([loading, disposing]);
    expect(runner.loaded, isNull);
    expect(service.supportsLanguage('Twi'), isFalse);
  });

  test(
    'service forwards prosody to the runner, defaults to standard',
    () async {
      final runner = _Runner()..loaded = 'Twi';
      final service = PiperTtsService.debugCreate(runner: runner);
      expect(await service.speak('Akwaaba', 'Twi'), isTrue);
      expect(runner.lastProsody, SpeechProsody.standard);
      expect(
        await service.speak('Kase', 'Twi', prosody: SpeechProsody.urgent),
        isTrue,
      );
      expect(runner.lastProsody, SpeechProsody.urgent);
    },
  );
}

class _Runner implements PiperTtsRunner {
  String? loaded;
  int loads = 0;
  bool fail = false;
  Completer<void>? gate;
  @override
  bool get available => true;
  @override
  bool get isSpeaking => false;
  @override
  bool hasModel(String language) => loaded == language;
  @override
  Future<void> init({
    required String language,
    required String modelAssetPath,
    required int speakerId,
  }) async {
    loads++;
    await gate?.future;
    if (fail) throw StateError('Transient load failure');
    loaded = language;
  }

  @override
  Future<void> dispose(String language) async {
    if (loaded == language) loaded = null;
  }

  @override
  void setActiveLanguage(String language) {}
  @override
  Future<void> speak(
    String text, {
    bool waitForCompletion = true,
    void Function()? onStarted,
    SpeechProsody prosody = SpeechProsody.standard,
  }) async {
    lastProsody = prosody;
  }

  @override
  Future<void> speakNonBlocking(
    String text, {
    SpeechProsody prosody = SpeechProsody.standard,
  }) async {
    lastProsody = prosody;
  }

  @override
  Future<void> stop() async {}
  SpeechProsody? lastProsody;
}
