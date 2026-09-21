/// Platform-conditional abstraction for on-device Piper neural TTS.
///
/// Follows the same dispatch pattern as [TranslationRunner]:
///   - Native (Android/iOS/desktop): Piper VITS inference via flutter_piper_tts.
///   - Web: stub that reports unavailable → system TTS handles it.
///
/// Piper models (Murya Hausa, Stable-Twi) produce native-quality speech at
/// 22-24 kHz from ONNX VITS graphs, running entirely on-device via Rust ort
/// bindings — no conflict with the Dart onnxruntime used for translation.
library;

import 'piper_tts_stub.dart' if (dart.library.io) 'piper_tts_io.dart';

/// Abstraction over a loaded Piper TTS engine for a single language.
abstract class PiperTtsRunner {
  /// Whether native Piper TTS is available on this platform.
  bool get available;

  /// Copy model assets to device storage and initialize the Piper engine.
  /// [language] is the canonical name ('Hausa', 'Twi').
  /// [modelAssetPath] is the asset folder containing model.onnx + model.onnx.json.
  /// [speakerId] selects the voice from the multi-speaker model.
  Future<void> init({
    required String language,
    required String modelAssetPath,
    required int speakerId,
  });

  /// Speak [text] in the initialized language. Returns a future that completes
  /// when playback finishes (or use [speakNonBlocking] for fire-and-forget).
  Future<void> speak(String text, {bool waitForCompletion = true, void Function()? onStarted});

  /// Start speaking without waiting for completion.
  Future<void> speakNonBlocking(String text);

  /// Stop current playback immediately.
  Future<void> stop();

  /// Whether audio is currently playing.
  bool get isSpeaking;

  /// Set the active language for subsequent speak() calls.
  void setActiveLanguage(String language);

  /// Whether a model is loaded and ready for [language].
  bool hasModel(String language);

  /// Release native model resources for a language.
  Future<void> dispose(String language);
}

PiperTtsRunner createPiperTtsRunner() => buildPiperTtsRunner();
