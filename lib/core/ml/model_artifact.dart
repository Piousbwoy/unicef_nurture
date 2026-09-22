import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

/// A local, pinned manifest; it contains no patient-specific data.
class ModelArtifactManifest {
  ModelArtifactManifest._(this.revision, this.files);
  final String revision;
  final Map<String, ModelArtifact> files;

  static Future<ModelArtifactManifest> load(
    String base,
    String contract, {
    AssetBundle? bundle,
  }) async {
    final json = await (bundle ?? rootBundle).loadString(
      '$base/model_manifest.json',
    );
    return ModelArtifactManifest.parse(json, contract);
  }

  factory ModelArtifactManifest.parse(String source, String contract) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid model manifest');
    }
    final json = decoded;
    final revision = json['revision'];
    if (json['schema'] != 1 ||
        json['contract'] != contract ||
        revision is! String ||
        !RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(revision)) {
      throw const FormatException('Unsupported model manifest');
    }
    final entries = json['files'];
    if (entries is! List || entries.isEmpty) {
      throw const FormatException('Model manifest has no artifacts');
    }
    final files = <String, ModelArtifact>{};
    for (final entry in entries) {
      if (entry is! Map<String, dynamic>) {
        throw const FormatException('Invalid model artifact');
      }
      final file = ModelArtifact.fromJson(entry);
      if (files.containsKey(file.name))
        throw const FormatException('Duplicate model artifact');
      files[file.name] = file;
    }
    return ModelArtifactManifest._(revision, Map.unmodifiable(files));
  }

  ModelArtifact file(String name) =>
      files[name] ??
      (throw const FormatException('Model artifact absent from manifest'));

  Future<Uint8List> read(
    String base,
    String name, {
    AssetBundle? bundle,
  }) async {
    final artifact = file(name);
    final bytes = await (bundle ?? rootBundle).load('$base/${artifact.name}');
    final data = bytes.buffer.asUint8List(
      bytes.offsetInBytes,
      bytes.lengthInBytes,
    );
    artifact.verify(data);
    return data;
  }

  Future<String> text(String base, String name, {AssetBundle? bundle}) async =>
      utf8.decode(await read(base, name, bundle: bundle));
}

class ModelArtifact {
  const ModelArtifact(this.name, this.bytes, this.hash);
  final String name;
  final int bytes;
  final String hash;

  factory ModelArtifact.fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    final size = json['bytes'];
    final hash = json['sha256'];
    if (name is! String ||
        !RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(name) ||
        name == '.' ||
        name == '..' ||
        size is! int ||
        size <= 0 ||
        hash is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
      throw const FormatException('Invalid model artifact metadata');
    }
    return ModelArtifact(name, size, hash);
  }

  void verify(Uint8List data) {
    final prefix = ascii.decode(data.take(64).toList(), allowInvalid: true);
    if (data.length != bytes ||
        sha256.convert(data).toString() != hash ||
        prefix.startsWith('version https://git-lfs') ||
        (name.endsWith('.onnx') && data.length < 1024)) {
      throw const FormatException(
        'Model integrity check failed; reinstall the language pack',
      );
    }
  }
}
