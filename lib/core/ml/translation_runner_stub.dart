/// Web stub: ONNX inference unavailable in browser (no dart:ffi).
/// TranslationService falls through to the phrase dictionary.
library;

import 'translation_runner.dart';

TranslationRunner buildTranslationRunner() => _WebTranslationRunner();

class _WebTranslationRunner implements TranslationRunner {
  @override
  bool get available => false;

  @override
  bool hasModel(String language) => false;

  @override
  Future<void> init({
    required String language,
    required String assetBasePath,
  }) async {
    // No-op on web.
  }

  @override
  Future<String?> translate(String english, {required String language, String? langToken}) async => null;

  @override
  Future<void> dispose(String language) async {
    // No-op on web.
  }
}
