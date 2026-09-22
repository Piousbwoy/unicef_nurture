import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:carebridge_ai/core/ml/model_artifact.dart';
import 'package:carebridge_ai/core/ml/native_pack_store.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const base = 'assets/tts/twi_piper';
  late Directory root;
  late HttpServer server;
  late NativePackStore store;
  late Map<String, List<int>> files;
  late Map<String, dynamic> manifest;
  var corrupt = false;
  var missing = false;
  setUp(() async {
    root = await Directory('build/native_pack_tests').create(recursive: true);
    root = await root.createTemp('case-');
    files = {
      'model.onnx': List.filled(2048, 7),
      'model.onnx.json': utf8.encode('{"test":true}'),
      'twi_rules.json': utf8.encode('{"test":true}'),
    };
    manifest = {
      'schema': 1,
      'contract': 'piper-v1',
      'revision': 'test-v1',
      'files': files.entries
          .map(
            (entry) => {
              'name': entry.key,
              'bytes': entry.value.length,
              'sha256': sha256.convert(entry.value).toString(),
            },
          )
          .toList(),
    };
    corrupt = missing = false;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final name = request.uri.pathSegments.last;
      if (missing && name == 'model.onnx') {
        request.response.statusCode = 404;
      } else if (name == 'model_manifest.json') {
        request.response.write(jsonEncode(manifest));
      } else {
        request.response.add(
          corrupt && name == 'model.onnx' ? List.filled(2048, 8) : files[name]!,
        );
      }
      await request.response.close();
    });
    store = NativePackStore(
      root: root,
      origin: Uri.parse('http://127.0.0.1:${server.port}/'),
    );
  });
  tearDown(() async {
    store.cancel();
    await server.close(force: true);
    await root.delete(recursive: true);
  });

  test(
    'verified optional pack survives a new store and is not a runtime claim',
    () async {
      final progress = <(int, int)>[];
      await store.install(
        base,
        (received, total) => progress.add((received, total)),
      );
      expect(progress.first.$1, 0);
      expect(progress.last.$1, progress.last.$2);
      final reopened = NativePackStore(root: root);
      expect(await reopened.installed(base), isTrue);
      final bundle = await reopened.bundle(base);
      final loaded = await ModelArtifactManifest.load(
        base,
        'piper-v1',
        bundle: bundle,
      );
      expect(loaded.revision, 'test-v1');
      expect(
        await loaded.read(base, 'model.onnx', bundle: bundle),
        Uint8List.fromList(files['model.onnx']!),
      );
    },
  );

  for (final failure in ['corruption', 'interruption', 'missing']) {
    test('$failure keeps the previous pack and cleans staging', () async {
      await store.install(base, (_, _) {});
      manifest['revision'] = 'test-v2';
      corrupt = failure == 'corruption';
      missing = failure == 'missing';
      await expectLater(
        store.install(base, (received, total) {
          if (failure == 'interruption' && received > 0) store.cancel();
        }),
        throwsA(anything),
      );
      expect(await store.installed(base), isTrue);
      final bundle = await store.bundle(base);
      expect(
        (await ModelArtifactManifest.load(
          base,
          'piper-v1',
          bundle: bundle,
        )).revision,
        'test-v1',
      );
      expect(
        await root
            .list(recursive: true)
            .where((entry) => entry.path.contains('.install-'))
            .length,
        0,
      );
      corrupt = missing = false;
      await store.install(base, (_, _) {});
      expect(
        (await ModelArtifactManifest.load(
          base,
          'piper-v1',
          bundle: await store.bundle(base),
        )).revision,
        'test-v2',
      );
    });
  }

  test(
    'incomplete inventory and unsafe paths are rejected before activation',
    () async {
      (manifest['files'] as List).removeLast();
      await expectLater(store.install(base, (_, _) {}), throwsFormatException);
      (manifest['files'] as List).first['name'] = '../model.onnx';
      await expectLater(store.install(base, (_, _) {}), throwsFormatException);
      expect(await root.list(recursive: true).length, 0);
    },
  );

  test('production downloads require HTTPS', () async {
    final unsafe = NativePackStore(
      root: root,
      origin: Uri.parse('http://example.org/'),
    );
    await expectLater(unsafe.install(base, (_, _) {}), throwsStateError);
  });
}
