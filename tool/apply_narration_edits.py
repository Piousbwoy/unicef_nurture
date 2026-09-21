"""Apply verified, exact narration edits without stale editor snapshots."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
pending = {}

def edit(name, old, new):
    path = root / name
    text = pending.get(path, path.read_text(encoding='utf-8'))
    if text.count(old) != 1:
        raise RuntimeError(f'{name}: expected one anchor, found {text.count(old)}: {old[:80]}')
    pending[path] = text.replace(old, new, 1)

f = 'lib/core/audio/caregiver_playback.dart'
# Recover the verified pre-edit coordinator after the editor flushed its stale
# buffer during a failed replacement. HEAD plus the previously observed Piper
# additions reproduces that version; no other file is restored from Git.
import subprocess
base = subprocess.check_output(['git', 'show', 'HEAD:' + f], cwd=root).decode('utf-8')
base = base.replace("import '../ml/translation_service.dart';", "import '../ml/piper_tts_service.dart';\nimport '../ml/translation_service.dart';")
base = base.replace('      if (await _synthesize(run)) {', '''
      // Piper neural TTS: native-quality speech for dynamic translated text.
      if (await _piperSpeak(run)) {
        if (_current(run)) run.emit(CaregiverPlaybackPhase.completed);
        return;
      }
      if (!_current(run)) return;

      // System device TTS fallback (flat MMS-accented or English voice).
      if (await _synthesize(run)) {''')
base = base.replace('  Future<bool> _synthesize(_PlaybackRun run) async {', '''  /// Synthesize speech via on-device Piper VITS (native-quality Hausa/Twi).
  /// Returns true if Piper handled playback, false if caller should fall through.
  Future<bool> _piperSpeak(_PlaybackRun run) async {
    final service = PiperTtsService.instance;
    if (!service.supportsLanguage(run.language)) return false;
    // Only use Piper for non-English text (dynamic translations).
    if (run.language == 'English') return false;
    final text = run.transcript;
    if (text.trim().isEmpty) return false;
    try {
      run.source = 'Native Piper voice (${service.voiceLabelFor(run.language) ?? run.language})';
      run.emit(CaregiverPlaybackPhase.playing);
      final handled = await service.speak(text, run.language);
      return handled;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _synthesize(_PlaybackRun run) async {''')
pending[root / f] = base
edit(f, "import '../ml/translation_service.dart';", "import '../ml/translation_service.dart';\nimport 'speech_content_policy.dart';")
edit(f, '    this.clipIds,\n  });\n  final String id;', '    this.clipIds,\n    this.policy = SpeechContentPolicy.guidance,\n  });\n  final SpeechContentPolicy policy;\n  final String id;')
edit(f, '    if (selected == \'English\') return english;\n    final clips', '    if (selected == \'English\') return english;\n    if (SpeechSafety.requiresEnglish(english, policy)) return null;\n    final clips')
edit(f, '    return result?.text;', '    return result != null && result.coverage == 1 &&\n        SpeechSafety.preservesTokens(english, result.text) ? result.text : null;')
edit(f, '    clipIds: clipIds,\n  );', '    clipIds: clipIds,\n    policy: policy,\n  );')
edit(f, '  final String transcript;\n  final String language;\n  String source', '  String transcript;\n  String language;\n  String provenance = \'\';\n  String source')
edit(f, '    AssetBundle? assets,\n    this.operationTimeout', '    AssetBundle? assets,\n    TranslationService? translation,\n    PiperTtsService? piper,\n    this.operationTimeout')
edit(f, '       _assets = assets ?? rootBundle;', '       _assets = assets ?? rootBundle,\n       _translation = translation ?? TranslationService.instance,\n       _piper = piper ?? PiperTtsService.instance;')
edit(f, '  final AssetBundle _assets;', '  final AssetBundle _assets;\n  final TranslationService _translation;\n  final PiperTtsService _piper;\n\n  static Future<void> stopAll() =>\n      _PlaybackCoordinator.current?.stop() ?? Future<void>.value();')
edit(f, '    var quiet = true;\n    try {', '    var quiet = true;\n    try {\n      await _piper.stop().timeout(operationTimeout);\n    } catch (_) {\n      quiet = false;\n    }\n    try {')
edit(f, '    final localized = speech.localizedText;', '    var localized = speech.matchingClips != null || selected == \'English\'\n        ? speech.localizedText : null;')
edit(f, '      if (localized == null) {\n        run.source', '''      if (selected != 'English' &&
          SpeechSafety.requiresEnglish(speech.english, speech.policy)) {
        run.transcript = speech.english;
        run.language = 'English';
        run.source = 'English for safety: treatment, measurements and identifiers '
            'are not machine-translated. Choose English playback.';
        run.emit(CaregiverPlaybackPhase.fallback);
        return;
      }
      if (localized == null && speech.clipId == null && speech.clipIds == null) {
        final result = await _wait(
          _translation.translateAsync(speech.english, selected),
          run, operationTimeout,
        );
        if (!_current(run)) return;
        if (result != null && result.language == selected &&
            result.coverage == 1 && result.text.trim().isNotEmpty &&
            SpeechSafety.preservesTokens(speech.english, result.text)) {
          localized = result.text;
          run.transcript = result.text;
          run.language = selected;
          run.provenance = result.isNeural
              ? 'neural model draft' : 'phrase dictionary draft';
        }
      }
      if (localized == null) {
        run.source''')
edit(f, "    final service = PiperTtsService.instance;\n    if (!service.supportsLanguage(run.language)) return false;", "    final service = _piper;\n    if (!service.isConfigured(run.language)) return false;")
edit(f, '''      run.source = 'Native Piper voice (${service.voiceLabelFor(run.language) ?? run.language})';
      run.emit(CaregiverPlaybackPhase.playing);
      final handled = await service.speak(text, run.language);
      return handled;''', '''      await _wait(service.initializeLanguage(run.language), run, operationTimeout);
      if (!_current(run) || !service.supportsLanguage(run.language)) return false;
      run.source = 'Piper offline voice - ${run.provenance.isEmpty ? 'bank draft translation' : run.provenance}';
      final handled = await _wait(service.speak(text, run.language,
        onStarted: () {
          if (_current(run)) run.emit(CaregiverPlaybackPhase.playing);
        },
      ), run, playbackTimeout);
      return handled && _current(run);''')
edit(f, '''    } catch (_) {
      return false;
    }
  }

  Future<bool> _synthesize''', '''    } catch (_) {
      if (_current(run)) {
        await _PlaybackCoordinator.serialize(() async {
          if (_current(run)) _PlaybackCoordinator.quiet = await _stopDevices();
        });
      }
      return false;
    }
  }

  Future<bool> _synthesize''')
edit(f, "      // System device TTS fallback (flat MMS-accented or English voice).\n      if (await _synthesize(run))", "      if (!_PlaybackCoordinator.quiet) { _fallback(run); return; }\n      // Device fallback requires a proven offline voice in the same language.\n      if (await _synthesize(run))")
edit(f, "    } catch (_) {\n      if (_current(run)) _fallback(run);\n    } finally", "    } catch (_) {\n      if (_current(run)) {\n        await _PlaybackCoordinator.serialize(() async {\n          if (_current(run)) _PlaybackCoordinator.quiet = await _stopDevices();\n        });\n        if (_current(run)) _fallback(run);\n      }\n    } finally")
edit(f, "        tts.setStartHandler(() {", "        if (run.provenance.isNotEmpty) run.source += ' - ${run.provenance}';\n        tts.setStartHandler(() {")

f = 'lib/core/audio/voice_service.dart'
edit(f, "import '../ml/neural_translation_service.dart';\n", '')
edit(f, '''    // Warm neural translation for dynamic text before playback reads it.
    final lang = OfflineSpeechLanguage.canonical(speech.language);
    if (speech.clipId == null &&
        (speech.clipIds == null || speech.clipIds!.isEmpty) &&
        lang != 'English' &&
        NeuralTranslationService.instance.supportsLanguage(lang)) {
      await NeuralTranslationService.instance.warmTranslation(
        speech.english,
        lang,
      );
    }
''', '')
edit(f, ": playback!.source.startsWith('Bundled synthetic voice')", ": playback!.source.startsWith('Bundled synthetic voice') ||\n            playback.source.startsWith('Piper offline voice')")

f = 'lib/presentation/caregiver/help/caregiver_voice.dart'
edit(f, "import '../../../core/ml/neural_translation_service.dart';\n", '')
edit(f, '''    // Warm neural translation for dynamic text (no clip) before the sync read.
    // Adds ~200 ms on first call; subsequent calls hit the cache instantly.
    if (item.clipId == null &&
        (item.clipIds == null || item.clipIds!.isEmpty) &&
        language != 'English' &&
        NeuralTranslationService.instance.supportsLanguage(language)) {
      await NeuralTranslationService.instance.warmTranslation(
        item.english,
        language,
      );
    }
''', '')
edit(f, '    language: speech.language,\n    clipId:', '    language: speech.language,\n    policy: speech.policy,\n    clipId:')
edit(f, '      a.english == b.english &&', '      a.english == b.english &&\n      a.policy == b.policy &&')

for path, text in pending.items():
    path.write_text(text, encoding='utf-8', newline='\n')
    print(path.relative_to(root))
