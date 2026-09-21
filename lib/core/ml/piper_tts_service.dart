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
/// On web, [PiperTtsRunner.available] is false — falls through to system TTS.
library;

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
/// Dagbani excluded — no Piper model exists.
const piperModelConfigs = <PiperModelConfig>[
  PiperModelConfig(
    language: 'Hausa',
    assetPath: 'assets/tts/hausa_piper',
    speakerId: 0, // Malam Garba (male, Standard Kano)
    voiceLabel: 'Malam Garba',
  ),
  PiperModelConfig(
    language: 'Twi',
    assetPath: 'assets/tts/twi_piper',
    speakerId: 29, // twi-6 (best pure Twi voice: 0.2677 UER, from voices.json)
    voiceLabel: 'Auntie Akosua',
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
  final _loadedLanguages = <String>{};
  final _loading = <String, Future<void>>{};

  bool isConfigured(String language) =>
      piperModelConfigs.any((config) => config.language == language);

  Future<void> initializeLanguage(String language) {
    if (!runner.available || !isConfigured(language)) return Future.value();
    return _loading.putIfAbsent(language, () async {
      final config = piperModelConfigs.firstWhere((c) => c.language == language);
      try {
        await runner.init(language: language, modelAssetPath: config.assetPath,
            speakerId: config.speakerId);
        if (runner.hasModel(language)) _loadedLanguages.add(language);
      } catch (_) { /* Readable guidance remains available. */ }
    });
  }

  /// Load Piper models for all configured languages.
  /// Called once during app initialization. Silently skips missing models.
  Future<void> initialize() async {
    if (_initialized || !runner.available) return;
    for (final config in piperModelConfigs) {
      await initializeLanguage(config.language);
      if (_isModelLoaded(config.language)) {
        _loadedLanguages.add(config.language);
      }
    }
    _initialized = true;
    debugPrint(
      'PiperTtsService: ready — $_loadedLanguages available',
    );
  }

  /// Whether Piper TTS can speak in [language].
  bool supportsLanguage(String language) {
    return _loadedLanguages.contains(language);
  }

  /// Speak [text] in [language] using the native Piper voice.
  /// Returns true if Piper handled it, false if caller should fall back
  /// to system TTS or readable text.
  Future<bool> speak(String text, String language, {VoidCallback? onStarted}) async {
    if (!supportsLanguage(language)) return false;
    try {
      _setActiveLanguage(language);
      await runner.speak(text, waitForCompletion: true, onStarted: onStarted);
      return true;
    } catch (e) {
      debugPrint('PiperTtsService: speak failed for $language: $e');
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
    } catch (e) {
      debugPrint('PiperTtsService: speakNonBlocking failed: $e');
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

  /// The voice label for display (e.g. "Malam Garba").
  String? voiceLabelFor(String language) {
    for (final config in piperModelConfigs) {
      if (config.language == language && _loadedLanguages.contains(language)) {
        return config.voiceLabel;
      }
    }
    return null;
  }

  /// Release all native model resources.
  Future<void> dispose() async {
    for (final language in _loadedLanguages.toList()) {
      await runner.dispose(language);
    }
    _loadedLanguages.clear();
    _loading.clear();
    _initialized = false;
  }

  // --- Private helpers ---

  bool _isModelLoaded(String language) => runner.hasModel(language);

  void _setActiveLanguage(String language) => runner.setActiveLanguage(language);
}
