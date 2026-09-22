import 'dart:convert';
import 'dart:typed_data';

import 'package:carebridge_ai/core/ml/model_artifact.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final data = Uint8List.fromList(utf8.encode('{"config":1}'));
  final record = {'name': 'config.json', 'bytes': data.length,
    'sha256': sha256.convert(data).toString()};
  final manifest = {'schema': 1, 'contract': 'test-v1', 'revision': 'sha-123',
    'files': [record]};
  ModelArtifactManifest parse(Object? value) =>
      ModelArtifactManifest.parse(jsonEncode(value), 'test-v1');

  test('manifest validates exact bytes and immutable metadata', () {
    final pack = parse(manifest);
    pack.file('config.json').verify(data);
    expect(pack.revision, 'sha-123');
    expect(() => pack.files.clear(), throwsUnsupportedError);
    expect(() => pack.file('missing'), throwsFormatException);
  });
  test('corrupt and truncated artifacts are rejected', () {
    final file = parse(manifest).file('config.json');
    expect(() => file.verify(Uint8List(data.length)), throwsFormatException);
    expect(() => file.verify(Uint8List(0)), throwsFormatException);
  });
  test('malformed, empty, duplicate and incompatible manifests fail closed', () {
    for (final invalid in [null, [], 1, {},
      {...manifest, 'schema': 2}, {...manifest, 'contract': 'other'},
      {...manifest, 'revision': '../escape'}, {...manifest, 'files': null},
      {...manifest, 'files': []}, {...manifest, 'files': [null]},
      {...manifest, 'files': [record, record]},
    ]) { expect(() => parse(invalid), throwsFormatException); }
  });
  test('artifact path traversal and invalid digests/sizes fail closed', () {
    for (final invalid in [
      for (final name in ['../file', '/file', 'C:\\file', '.', '..', ''])
        {...record, 'name': name},
      {...record, 'bytes': 0}, {...record, 'bytes': 1.5},
      {...record, 'sha256': 'not-a-hash'},
    ]) { expect(() => ModelArtifact.fromJson(invalid), throwsFormatException); }
  });
  test('even correctly hashed LFS pointers are not model weights', () {
    final pointer = Uint8List.fromList(utf8.encode(
        'version https://git-lfs.github.com/spec/v1\n${' ' * 1200}'));
    final file = ModelArtifact('model.onnx', pointer.length, sha256.convert(pointer).toString());
    expect(() => file.verify(pointer), throwsFormatException);
  });
}
