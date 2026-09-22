/// Native ONNX translation runner for Android / iOS / desktop.
///
/// App-owned Marian inference runs in an isolate using ONNX Runtime.
/// Optional packs are integrity-checked and snapshotted before loading;
/// tokenizer and generation fixtures gate runtime availability.
library;

import 'dart:typed_data';
import 'native_pack_store.dart';
import 'marian_native_engine.dart';
import 'model_artifact.dart';

import 'translation_runner.dart';

TranslationRunner buildTranslationRunner() => _IoTranslationRunner();

class _IoTranslationRunner implements TranslationRunner {
  /// One active language engine, lazily loaded.
  final _models = <String, MarianNativeEngine>{};
  Future<void> _lifecycle = Future.value();
  Future<void> _serialize(Future<void> Function() action) {
    final next = _lifecycle.then((_) => action());
    _lifecycle = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  @override
  bool get available => true;

  @override
  bool hasModel(String language) => _models.containsKey(language);

  @override
  Future<void> init({
    required String language,
    required String assetBasePath,
  }) => _serialize(() async {
    if (_models.containsKey(language)) return;
    final bundle = await NativePackStore().bundle(assetBasePath);
    final manifest = await ModelArtifactManifest.load(
      assetBasePath,
      'marian-v1',
      bundle: bundle,
    );
    for (final engine in _models.values) {
      await engine.dispose();
    }
    _models.clear();
    final artifacts = <String, Uint8List>{};
    for (final file in manifest.files.values) {
      final data = await bundle.load('$assetBasePath/${file.name}');
      artifacts[file.name] = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
    }
    // Hashing, tokenizer fixture checks, model loading and inference run off-UI.
    _models[language] = await MarianNativeEngine.load(manifest, artifacts);
  });

  @override
  Future<String?> translate(
    String english, {
    required String language,
    String? langToken,
  }) async {
    final model = _models[language];
    if (model == null) return null;

    try {
      if (langToken != null && langToken.isNotEmpty) return null;
      return await model.translate(english);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> dispose(String language) => _serialize(() async {
    final model = _models.remove(language);
    await model?.dispose();
  });
}
