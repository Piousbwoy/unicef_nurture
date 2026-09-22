import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:carebridge_ai/core/ml/marian_native_engine.dart';
import 'package:carebridge_ai/core/ml/marian_tokenizer.dart';
import 'package:carebridge_ai/core/ml/model_artifact.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const enabled = bool.fromEnvironment('RUN_NATIVE_TRANSLATION');
  const language = String.fromEnvironment('TRANSLATION_LANGUAGE', defaultValue: 'twi');
  setUpAll(() {
    final library = Platform.environment['ORT_TEST_LIBRARY'];
    if (enabled && library != null) DynamicLibrary.open(library);
  });
  test('real Marian generation matches Python and releases its worker', () async {
    const packRoot = String.fromEnvironment('TRANSLATION_PACK_ROOT',
        defaultValue: 'build/marian_reference');
    final base = '$packRoot/translation_$language';
    final manifest = ModelArtifactManifest.parse(
      await File('$base/model_manifest.json').readAsString(), 'marian-v1');
    final files = <String, Uint8List>{};
    for (final artifact in manifest.files.values) {
      files[artifact.name] = await File('$base/${artifact.name}').readAsBytes();
    }
    final tokenizer = MarianTokenizer(sourceModel: files['source.spm']!,
      targetModel: files['target.spm']!, vocabulary: utf8.decode(files['vocab.json']!),
      fixtures: utf8.decode(files['tokenizer_fixtures.json']!));
    final engine = await MarianNativeEngine.load(manifest, files);
    addTearDown(engine.dispose);
    final fixtures = jsonDecode(utf8.decode(files['generation_fixtures.json']!)) as List;
    for (var index = 0; index < fixtures.length; index++) {
      final fixture = fixtures[index];
      // Fixed public fixture index only; runtime text is never logged.
      // ignore: avoid_print
      print('$language generation fixture ${index + 1}/${fixtures.length}');
      final expected = tokenizer.decode(List<int>.from(fixture['generated_ids'])).trim();
      await expectLater(engine.translate(fixture['text'] as String), completion(expected));
    }
    await expectLater(engine.translate('🙂'), throwsStateError);
    await expectLater(engine.translate(fixtures.first['text'] as String), completes);
    await engine.dispose();
    await expectLater(engine.translate('Good morning.'), throwsStateError);
  }, skip: !enabled, timeout: const Timeout(Duration(minutes: 8)));
}
