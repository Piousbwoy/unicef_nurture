/// Native ONNX translation runner for Android / iOS / desktop.
///
/// Uses the `onnx_translation` package (wraps `onnxruntime` Dart FFI bindings)
/// to run MarianMT encoder-decoder models entirely on-device.
///
/// Model lifecycle:
///   1. [init] loads ONNX graphs + tokenizer vocab from the asset bundle.
///   2. [translate] encodes English → runs encoder → autoregressive decode →
///      returns target-language text. ~170 ms per sentence on a OnePlus 13
///      for the 17 MB Tiny model.
///   3. [dispose] releases native session memory.
library;

import 'package:flutter/services.dart' show rootBundle;
import 'package:onnx_translation/onnx_translation.dart';

import 'translation_runner.dart';

TranslationRunner buildTranslationRunner() => _IoTranslationRunner();

class _IoTranslationRunner implements TranslationRunner {
  /// One OnnxModel per language, lazily loaded.
  final _models = <String, OnnxModel>{};
  final _loadErrors = <String, Object>{};

  @override
  bool get available => true;

  @override
  bool hasModel(String language) => _models.containsKey(language);

  @override
  Future<void> init({
    required String language,
    required String assetBasePath,
  }) async {
    if (_models.containsKey(language) || _loadErrors.containsKey(language)) {
      return;
    }
    try {
      // Verify the required model files exist in the asset bundle before
      // attempting to load — gives a clean error instead of a cryptic crash.
      await _assertAssetExists('$assetBasePath/encoder_model.onnx');
      await _assertAssetExists('$assetBasePath/vocab.json');

      final model = OnnxModel();
      await model.init(modelBasePath: assetBasePath);
      _models[language] = model;
    } catch (e) {
      _loadErrors[language] = e;
    }
  }

  @override
  Future<String?> translate(String english, {required String language, String? langToken}) async {
    final model = _models[language];
    if (model == null) return null;

    try {
      final output = await model.runModel(
        english,
        initialLangToken: (langToken != null && langToken.isNotEmpty) ? langToken : null,
      );
      if (output.isEmpty) return null;
      return _cleanOutput(output);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> dispose(String language) async {
    final model = _models.remove(language);
    model?.release();
  }

  Future<void> _assertAssetExists(String path) async {
    try {
      await rootBundle.load(path);
    } catch (_) {
      throw StateError('Translation model asset missing: $path');
    }
  }

  static String _cleanOutput(String text) {
    var cleaned = text.trim();
    // Strip common special tokens from MarianMT output.
    cleaned = cleaned.replaceAll('</s>', '').replaceAll('<pad>', '').trim();
    // Remove leading language token if the model echoes it (e.g. '>>hau<< ...').
    if (cleaned.startsWith('>>') && cleaned.contains('<<')) {
      cleaned = cleaned.substring(cleaned.indexOf('<<') + 2).trim();
    }
    return cleaned;
  }
}
