/// Platform-conditional abstraction for on-device neural translation models.
///
/// Follows the same dispatch pattern as [TfliteRunner]:
///   - Native (Android/iOS/desktop): real ONNX inference via onnx_translation.
///   - Web: stub that reports unavailable → phrase dictionary handles it.
///
/// The service never blocks the UI thread: inference runs in an isolate via
/// the async [translate] method. Results are cached by [TranslationService].
library;

import 'translation_runner_stub.dart'
    if (dart.library.io) 'translation_runner_io.dart';

/// Abstraction over an ONNX encoder-decoder model for a single language pair.
abstract class TranslationRunner {
  /// Whether a native ONNX engine is available on this platform.
  bool get available;

  /// Successfully loaded state, separate from configured language support.
  bool hasModel(String language);

  /// Load model + tokenizer from the asset bundle. Called once per language.
  Future<void> init({required String language, required String assetBasePath});

  /// Run inference. Returns null if the model isn't loaded or fails.
  /// [english] is the source text; [langToken] is the target-language token
  /// (e.g. '##HA') or null for monodirectional models.
  Future<String?> translate(String english, {required String language, String? langToken});

  /// Release native memory for a language model.
  Future<void> dispose(String language);
}

TranslationRunner createTranslationRunner() => buildTranslationRunner();
