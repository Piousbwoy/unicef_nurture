/// Optional, immutable language packs in app-owned storage; no patient data.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'model_artifact.dart';

class NativePackStore {
  NativePackStore({this.root, this.origin});
  final Directory? root;
  final Uri? origin;
  HttpClient? _client;
  int _generation = 0;
  bool _installing = false;

  static const configuredOrigin = String.fromEnvironment('VOICE_PACK_BASE_URL');
  Uri? get downloadOrigin =>
      origin ??
      (configuredOrigin.isEmpty ? null : Uri.tryParse(configuredOrigin));

  static String base(String language, bool translation) {
    if (!['Twi', 'Hausa'].contains(language)) {
      throw ArgumentError('Unsupported language pack');
    }
    return translation
        ? 'assets/models/translation_${language.toLowerCase()}'
        : 'assets/tts/${language.toLowerCase()}_piper';
  }

  Future<Directory> _root() async =>
      root ??
      Directory(
        p.join(
          (await getApplicationSupportDirectory()).path,
          'offline_voice_packs_v1',
        ),
      );

  static void validateInventory(ModelArtifactManifest manifest, String base) {
    final names = base.contains('/translation_')
        ? [
            'encoder_model.onnx',
            'decoder_model.onnx',
            'source.spm',
            'target.spm',
            'vocab.json',
            'generation_config.json',
            'tokenizer_fixtures.json',
            'generation_fixtures.json',
          ]
        : [
            'model.onnx',
            'model.onnx.json',
            if (base.endsWith('twi_piper')) 'twi_rules.json',
          ];
    for (final name in names) {
      manifest.file(name);
    }
  }

  /// Snapshot one immutable revision so replacements cannot mix model files.
  Future<AssetBundle> bundle(String base) async {
    final folder = Directory(p.join((await _root()).path, p.basename(base)));
    if (await folder.exists()) {
      final revisions = await folder
          .list(followLinks: false)
          .where(
            (entry) =>
                entry is Directory &&
                p.basename(entry.path).startsWith('ready-'),
          )
          .cast<Directory>()
          .toList();
      revisions.sort((a, b) => b.path.compareTo(a.path));
      for (final revision in revisions) {
        final bundle = _PackBundle(base, revision);
        try {
          final manifest = await ModelArtifactManifest.load(
            base,
            _contract(base),
            bundle: bundle,
          );
          validateInventory(manifest, base);
          // Detect eviction/truncation without repeatedly hashing on the UI isolate.
          for (final file in manifest.files.values) {
            if (await File(p.join(revision.path, file.name)).length() !=
                file.bytes) {
              throw const FormatException('Pack file missing');
            }
          }
          return bundle;
        } catch (_) {
          /* Keep the last complete revision available. */
        }
      }
    }
    return rootBundle;
  }

  static String _contract(String base) =>
      base.contains('/translation_') ? 'marian-v1' : 'piper-v1';

  Future<bool> installed(String base) async {
    try {
      final source = await bundle(base);
      final manifest = await ModelArtifactManifest.load(
        base,
        _contract(base),
        bundle: source,
      );
      validateInventory(manifest, base);
      for (final file in manifest.files.values) {
        if (source is _PackBundle) {
          await _verifyOffUi(p.join(source.directory.path, file.name), file);
        } else {
          await manifest.read(base, file.name, bundle: source);
        }
      }
      return true; // Integrity only; inference is a separate gate.
    } catch (_) {
      return false;
    }
  }

  // A separate closure scope prevents capturing the live HTTP client.
  static Future<void> _verifyOffUi(String path, ModelArtifact artifact) =>
      Isolate.run(() => verifyFile(File(path), artifact));

  static Future<void> verifyFile(File file, ModelArtifact artifact) async {
    if (await file.length() != artifact.bytes) {
      throw const FormatException('Pack size mismatch');
    }
    final handle = await file.open();
    late List<int> prefix;
    try {
      prefix = await handle.read(64);
    } finally {
      await handle.close();
    }
    if (ascii
            .decode(prefix, allowInvalid: true)
            .startsWith('version https://git-lfs') ||
        (artifact.name.endsWith('.onnx') && artifact.bytes < 1024) ||
        (await sha256.bind(file.openRead()).first).toString() !=
            artifact.hash) {
      throw const FormatException('Pack integrity failed');
    }
  }

  void cancel() {
    ++_generation;
    _client?.close(force: true);
  }

  Future<void> install(String base, void Function(int, int) progress) async {
    if (_installing) throw StateError('Installation already running');
    final origin = downloadOrigin;
    if (origin == null ||
        !origin.hasAuthority ||
        origin.userInfo.isNotEmpty ||
        origin.hasQuery ||
        origin.hasFragment ||
        (origin.scheme != 'https' &&
            !(origin.scheme == 'http' &&
                ['localhost', '127.0.0.1', '::1'].contains(origin.host)))) {
      throw StateError('Configure an HTTPS VOICE_PACK_BASE_URL');
    }
    _installing = true;
    final generation = ++_generation;
    final client = _client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    Directory? staging;
    void check() {
      if (generation != _generation) throw StateError('Installation cancelled');
    }

    try {
      final originBase = origin.toString().endsWith('/')
          ? origin
          : Uri.parse('$origin/');
      final url = originBase.resolve('$base/');
      Future<HttpClientResponse> fetch(String name) async {
        check();
        final request = await client.getUrl(url.resolve(name));
        request.followRedirects = false;
        final response = await request.close().timeout(
          const Duration(seconds: 30),
        );
        if (response.statusCode != HttpStatus.ok) {
          throw StateError('Pack download failed');
        }
        return response;
      }

      final manifestBytes = BytesBuilder(copy: false);
      await for (final chunk in (await fetch(
        'model_manifest.json',
      )).timeout(const Duration(seconds: 30))) {
        check();
        manifestBytes.add(chunk);
        if (manifestBytes.length > 1048576) {
          throw const FormatException('Oversized manifest');
        }
      }
      final text = utf8.decode(manifestBytes.takeBytes());
      final manifest = ModelArtifactManifest.parse(text, _contract(base));
      validateInventory(manifest, base);
      final total = manifest.files.values.fold<int>(
        0,
        (sum, file) => sum + file.bytes,
      );
      if (total > 2 * 1024 * 1024 * 1024) {
        throw const FormatException('Oversized pack');
      }
      final folder = Directory(p.join((await _root()).path, p.basename(base)));
      await folder.create(recursive: true);
      staging = await folder.createTemp('.install-');
      var received = 0;
      progress(0, total);
      for (final artifact in manifest.files.values) {
        check();
        final file = File(p.join(staging.path, artifact.name));
        final sink = file.openWrite();
        // Observe disk/quota failures while the HTTP stream is still active.
        Object? writeError;
        unawaited(
          sink.done.catchError((Object error) {
            writeError = error;
            return file;
          }),
        );
        var count = 0;
        try {
          await for (final chunk in (await fetch(
            artifact.name,
          )).timeout(const Duration(seconds: 30))) {
            check();
            if (writeError != null) {
              throw StateError('Insufficient storage or write failure');
            }
            count += chunk.length;
            if (count > artifact.bytes) {
              throw const FormatException('Pack size mismatch');
            }
            sink.add(chunk);
            // Bound buffered data and propagate disk errors promptly.
            await sink.flush();
            progress(received + count, total);
          }
        } finally {
          await sink.close();
        }
        check();
        await _verifyOffUi(file.path, artifact);
        received += count;
      }
      await File(
        p.join(staging.path, 'model_manifest.json'),
      ).writeAsString(text, flush: true);
      check();
      // Rename within the same filesystem is the only activation operation.
      // Existing ready revisions are never removed by installation or failure.
      final name =
          'ready-${DateTime.now().microsecondsSinceEpoch}-${const Uuid().v4()}';
      for (var attempt = 0; ; attempt++) {
        check();
        try {
          await staging.rename(p.join(folder.path, name));
          break;
        } on FileSystemException catch (error) {
          // Windows scanners may briefly retain a handle after verification.
          if (!Platform.isWindows ||
              attempt >= 5 ||
              ![5, 32].contains(error.osError?.errorCode)) {
            rethrow;
          }
          await Future<void>.delayed(
            Duration(milliseconds: 100 * (attempt + 1)),
          );
        }
      }
      staging = null;
      progress(total, total);
    } finally {
      client.close(force: true);
      if (identical(client, _client)) _client = null;
      _installing = false;
      if (staging != null && await staging.exists()) {
        await staging.delete(recursive: true);
      }
    }
  }
}

class _PackBundle extends CachingAssetBundle {
  _PackBundle(this.base, this.directory);
  final String base;
  final Directory directory;
  @override
  Future<ByteData> load(String key) async {
    if (!key.startsWith('$base/') ||
        key.substring(base.length + 1).contains('/') ||
        key.contains('..') ||
        key.contains('\\')) {
      throw const FormatException('Invalid pack path');
    }
    final bytes = await File(
      p.join(directory.path, key.substring(base.length + 1)),
    ).readAsBytes();
    return ByteData.sublistView(bytes);
  }
}
