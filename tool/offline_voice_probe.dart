/// Browser acceptance entrypoint only; never included by lib/main.dart.
/// Build with tool/build_offline_web.py --probe, then invoke CareBridgeProbe.
library;

import 'dart:convert';
import 'dart:js_interop';
import 'package:carebridge_ai/main.dart' as app;
import 'package:carebridge_ai/core/audio/caregiver_playback.dart';
import 'package:carebridge_ai/core/i18n/speech_bank.dart';
import 'package:carebridge_ai/core/ml/piper_tts_runner.dart';
import 'package:carebridge_ai/core/ml/translation_runner.dart';
import 'package:carebridge_ai/core/ml/voice_pack_install.dart';
import 'package:carebridge_ai/core/ml/voice_web_bridge.dart';

@JS('CareBridgeProbe')
external set _probe(JSFunction callback);

final _piper = createPiperTtsRunner();
final _translation = createTranslationRunner();

Future<String> _run(String operation, String language) async {
  if (!['Twi', 'Hausa', 'Dagbani', 'English'].contains(language)) {
    throw ArgumentError('Unsupported probe');
  }
  final clock = Stopwatch()..start();
  final base = 'assets/models/translation_${language.toLowerCase()}';
  final installer = VoicePackInstaller();
  switch (operation) {
    case 'installVoice':
    case 'installTranslation':
      await installer.install(
        language,
        translation: operation == 'installTranslation',
        progress: (_, _) {},
      );
      return jsonEncode({'installed': true, 'ms': clock.elapsedMilliseconds});
    case 'translation':
      await _translation.init(language: language, assetBasePath: base);
      final loadMs = clock.elapsedMilliseconds;
      final cache =
          (await VoiceWebBridge.metadata('assets/$base'))['cache'] as String;
      final fixtures =
          jsonDecode(
                await VoiceWebBridge.text(
                  'assets/$base',
                  'generation_fixtures.json',
                  cache,
                ),
              )
              as List;
      final rows = <Map<String, Object?>>[];
      for (final fixture in fixtures) {
        clock.reset();
        final result = await _translation.translate(
          fixture['text'] as String,
          language: language,
        );
        rows.add({
          'matches': result == fixture['translation'],
          'translation': result,
          'ms': clock.elapsedMilliseconds,
        });
      }
      await _translation.dispose(language);
      return jsonEncode({
        'loadMs': loadMs,
        'fixtures': rows,
        'allMatch': rows.every((row) => row['matches'] == true),
      });
    case 'voice':
      await _piper.init(
        language: language,
        modelAssetPath: 'assets/tts/${language.toLowerCase()}_piper',
        speakerId: language == 'Twi' ? 29 : 0,
      );
      final loadMs = clock.elapsedMilliseconds;
      clock.reset();
      var starts = 0;
      await _piper.speak(
        language == 'Twi' ? 'Maakye, wo ho te sɛn?' : 'Sannu. Yaya kake?',
        onStarted: () => starts++,
      );
      await _piper.dispose(language);
      return jsonEncode({
        'loadMs': loadMs,
        'playbackMs': clock.elapsedMilliseconds,
        'starts': starts,
        'completed': true,
      });
    case 'recording':
      final voice = DeviceCaregiverVoice();
      final phases = <String>[];
      try {
        await voice.play(
          CaregiverSpeech(
            id: 'offline-recording-probe',
            english: SpeechBank.qNewbornFeed.english,
            language: language,
            clipId: SpeechBank.qNewbornFeed.id,
          ),
          (event) => phases.add(event.phase.name),
        );
      } finally {
        await voice.dispose();
      }
      return jsonEncode({'phases': phases});
    case 'stop':
      await _piper.stop();
      return jsonEncode({'stopped': true});
    default:
      throw ArgumentError('Unknown probe');
  }
}

void main() {
  _probe = ((JSString operation, JSString language) => _run(
    operation.toDart,
    language.toDart,
  ).then((result) => result.toJS).toJS).toJS;
  app.main();
}
