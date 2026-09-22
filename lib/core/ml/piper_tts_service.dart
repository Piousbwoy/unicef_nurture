/// High-level Piper TTS service for CareBridge native voice synthesis.
///
/// Manages the lifecycle of multi-speaker VITS models (Murya Hausa,
/// Stable-Twi) and exposes a clean API for the caregiver playback chain.
///
/// Architecture position:
///   SpeechBank clip (exact) → play bundled WAV (highest quality pre-gen)
///   Piper TTS available?    → synthesize native voice from translated text
///   System TTS fallback?    → speak English via device voice
///   Readable text            → always available
///
/// Browser playback uses the installed language pack and same-origin WASM.
library;

import 'dart:async';
import 'package:flutter/foundation.dart';

import 'piper_tts_runner.dart';

/// Configuration for a Piper TTS model (per language).
class PiperModelConfig {
  const PiperModelConfig({
    required this.language,
    required this.assetPath,
    required this.speakerId,
    required this.voiceLabel,
  });
  final String language;
  final String assetPath;
  final int speakerId;
  final String voiceLabel;
}

/// All TTS models the app can use.
/// No compact dynamic Dagbani voice has been validated for this application.
const piperModelConfigs = <PiperModelConfig>[
  PiperModelConfig(
    language: 'Hausa',
    assetPath: 'assets/tts/hausa_piper',
    speakerId: 0,
    voiceLabel: 'Murya F2',
  ),
  PiperModelConfig(
    language: 'Twi',
    assetPath: 'assets/tts/twi_piper',
    speakerId: 29, // twi-6 baseline; listening approval remains required.
    voiceLabel: 'Stable Twi · twi-6',
  ),
];

/// Orchestrates Piper TTS model loading and speech synthesis.
///
/// Singleton; lifecycle managed by [piperTtsInitProvider] in the Riverpod graph.
class PiperTtsService {
  PiperTtsService._();
  static final instance = PiperTtsService._();

  /// Test-only factory.
  static PiperTtsService debugCreate({PiperTtsRunner? runner}) {
    final s = PiperTtsService._();
    s._runner = runner;
    return s;
  }

  PiperTtsRunner? _runner;
  PiperTtsRunner get runner => _runner ??= createPiperTtsRunner();

  bool _initialized = false;
  bool get initialized => _initialized;
  bool get isAvailable => runner.available;

  /// Languages that have a loaded TTS model.
  final _loading = <String, Future<void>>{};
  bool _disposing = false;

  bool isConfigured(String language) =>
      piperModelConfigs.any((config) => config.language == language);

  Future<void> initializeLanguage(String language) {
    if (_disposing || !runner.available || !isConfigured(language)) {
      return Future.value();
    }
    if (runner.hasModel(language)) return Future.value();
    final pending = _loading[language];
    if (pending != null) return pending;
    final completion = Completer<void>();
    _loading[language] = completion.future;
    final config = piperModelConfigs.firstWhere((c) => c.language == language);
    Future<void> load() async {
      try {
        await runner.init(
          language: language,
          modelAssetPath: config.assetPath,
          speakerId: config.speakerId,
        );
      } catch (_) {
        /* Readable guidance remains available. */
      } finally {
        _loading.remove(language);
        completion.complete();
      }
    }

    unawaited(load());
    return completion.future;
  }

  /// Enable lazy initialization without allocating every language pipeline.
  Future<void> initialize() async {
    if (_disposing || !runner.available) return;
    // Initialization does not allocate every language model. Playback loads one.
    _initialized = true;
  }

  /// Whether Piper TTS can speak in [language].
  bool supportsLanguage(String language) {
    return !_disposing && runner.hasModel(language);
  }

  /// Speak [text] in [language] using the native Piper voice.
  /// Returns true if Piper handled it, false if caller should fall back
  /// to system TTS or readable text.
  Future<bool> speak(
    String text,
    String language, {
    VoidCallback? onStarted,
  }) async {
    if (!supportsLanguage(language)) return false;
    try {
      _setActiveLanguage(language);
      await runner.speak(text, waitForCompletion: true, onStarted: onStarted);
      return true;
    } catch (_) {
      debugPrint('PiperTtsService: synthesis or playback unavailable');
      return false;
    }
  }

  /// Start speaking without waiting. Use [stop] to interrupt.
  Future<bool> speakNonBlocking(String text, String language) async {
    if (!supportsLanguage(language)) return false;
    try {
      _setActiveLanguage(language);
      await runner.speakNonBlocking(text);
      return true;
    } catch (_) {
      debugPrint('PiperTtsService: playback unavailable');
      return false;
    }
  }

  /// Stop current playback.
  Future<void> stop() async {
    try {
      await runner.stop();
    } catch (_) {}
  }

  /// Whether audio is currently playing.
  bool get isSpeaking => runner.isSpeaking;

  /// Checkpoint voice label; not an inferred speaker identity.
  String? voiceLabelFor(String language) {
    for (final config in piperModelConfigs) {
      if (config.language == language && supportsLanguage(language)) {
        return config.voiceLabel;
      }
    }
    return null;
  }

  /// Release all native model resources.
  Future<void> dispose() async {
    _disposing = true;
    try {
      await stop();
      await Future.wait(_loading.values.toList());
      for (final config in piperModelConfigs) {
        await runner.dispose(config.language);
      }
    } finally {
      _loading.clear();
      _initialized = false;
      _disposing = false;
    }
  }

  // --- Private helpers ---

  void _setActiveLanguage(String language) =>
      runner.setActiveLanguage(language);
}
