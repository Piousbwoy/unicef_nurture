import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ffi';
import 'dart:typed_data';

import 'package:carebridge_ai/core/ml/model_artifact.dart';
import 'package:carebridge_ai/core/i18n/speech_bank.dart';
import 'package:crypto/crypto.dart';
import 'package:carebridge_ai/core/ml/piper_native_engine.dart';
import 'package:flutter_test/flutter_test.dart';

// Requires the platform ONNX shared library. Deliberately separate from mocks.
void main() {
  const enabled = bool.fromEnvironment('RUN_NATIVE_VOICE');
  setUpAll(() {
    final library = Platform.environment['ORT_TEST_LIBRARY'];
    if (enabled && library != null) DynamicLibrary.open(library);
  });
  for (final voice in [
    ('Twi', 'twi_piper', 29, 'Maakye, wo ho te sɛn?'),
    ('Hausa', 'hausa_piper', 0, 'Sannu. Yaya kake?'),
    // Character-orthography exports; skipped until the pack is on disk.
    if (File('assets/tts/twi_farmerline/model.onnx').existsSync())
      ('Twi', 'twi_farmerline', 0, 'Akwaaba. Wo ho te sɛn?'),
    if (File('assets/tts/dagbani_piper/model.onnx').existsSync())
      ('Dagbani', 'dagbani_piper', 0, SpeechBank.qNewbornFeed.dagbani),
  ]) {
    test(
      'real ${voice.$1} ${voice.$2} inference, recovery and cleanup',
      () async {
        final base = 'assets/tts/${voice.$2}';
        final manifest = ModelArtifactManifest.parse(
          await File('$base/model_manifest.json').readAsString(),
          'piper-v1',
        );
        final clock = Stopwatch()..start();
        final engine = await PiperNativeEngine.load(
          model: await File('$base/model.onnx').readAsBytes(),
          artifact: manifest.file('model.onnx'),
          config: await File('$base/model.onnx.json').readAsString(),
          rules: File('$base/twi_rules.json').existsSync()
              ? await File('$base/twi_rules.json').readAsString()
              : null,
          language: voice.$1,
          speaker: voice.$3,
        );
        addTearDown(engine.dispose);
        final loadMs = clock.elapsedMilliseconds;
        await expectLater(engine.synthesize('🙂'), throwsStateError);
        clock.reset();
        final wav = await engine.synthesize(voice.$4);
        final synthesisMs = clock.elapsedMilliseconds;
        final header = ByteData.sublistView(wav);
        final rate = header.getUint32(24, Endian.little);
        final duration = (wav.length - 44) / 2 / rate;
        expect(duration, inInclusiveRange(0.3, 30));
        expect(header.getUint32(40, Endian.little), wav.length - 44);
        final samples = [
          for (var i = 44; i < wav.length; i += 2)
            header.getInt16(i, Endian.little),
        ];
        final peak = samples
            .map((v) => v.abs())
            .reduce((a, b) => a > b ? a : b);
        expect(peak, greaterThan(20));
        final output = Directory('build/voice_samples');
        await output.create(recursive: true);
        await File(
          '${output.path}/${voice.$2}_${voice.$3}.wav',
        ).writeAsBytes(wav);
        // Public fixed test text only. No patient utterances enter diagnostics.
        // ignore: avoid_print
        print(
          '${voice.$1}: load=${loadMs}ms synth=${synthesisMs}ms audio=${duration.toStringAsFixed(2)}s peak=$peak',
        );
        if (voice.$2 == 'twi_piper') {
          final vectors =
              jsonDecode(
                    await File(
                      'test/fixtures/voice/twi_reference_vectors.json',
                    ).readAsString(),
                  )
                  as Map;
          final corpus = <Map<String, String>>[
            for (final row in vectors['cases'] as List)
              if (row['language'] == 'twi')
                {
                  'category': 'upstream-reference',
                  'text': row['text'] as String,
                },
            {
              'category': 'numbers-written-out',
              'text': 'Baako, mmienu, mmiɛnsa, ɛnan, enum.',
            },
            {'category': 'numeric-symbols', 'text': '12, 3.5, 2026.'},
            {
              'category': 'bank-question-not-clinically-approved',
              'text': SpeechBank.qNewbornFeed.twi,
            },
            {
              'category': 'paragraph',
              'text': [
                for (final row in vectors['cases'] as List)
                  if (row['language'] == 'twi') row['text'] as String,
              ].join(' '),
            },
          ];
          final rows = <Map<String, Object?>>[];
          for (var index = 0; index < corpus.length; index++) {
            final item = corpus[index];
            clock.reset();
            Uint8List sample;
            try {
              sample = await engine.synthesize(item['text']!);
            } on StateError {
              rows.add({
                ...item,
                'status': 'rejected',
                'reason': 'unsupported_or_invalid_synthesis',
              });
              continue;
            }
            final elapsed = clock.elapsedMilliseconds;
            final data = ByteData.sublistView(sample);
            final hz = data.getUint32(24, Endian.little);
            final count = (sample.length - 44) ~/ 2;
            var energy = 0.0;
            var maximum = 0;
            for (var offset = 44; offset < sample.length; offset += 2) {
              final value = data.getInt16(offset, Endian.little);
              maximum = math.max(maximum, value.abs());
              energy += value * value;
            }
            expect(count / hz, inInclusiveRange(0.2, 90));
            expect(maximum, greaterThan(20));
            final name = 'twi_baseline_${index.toString().padLeft(2, '0')}.wav';
            await File('${output.path}/$name').writeAsBytes(sample);
            rows.add({
              ...item,
              'status': 'generated',
              'file': name,
              'sha256': sha256.convert(sample).toString(),
              'synthesisMs': elapsed,
              'durationSeconds': count / hz,
              'realTimeFactor': elapsed / 1000 / (count / hz),
              'peakPcm16': maximum,
              'rmsPcm16': math.sqrt(energy / count),
            });
          }
          final references = corpus.where(
            (row) => row['category'] == 'upstream-reference',
          );
          expect(references, isNotEmpty);
          expect(
            rows.where(
              (row) =>
                  row['category'] == 'upstream-reference' &&
                  row['status'] == 'generated',
            ),
            hasLength(references.length),
          );
          await File('${output.path}/twi_baseline.json').writeAsString(
            const JsonEncoder.withIndent('  ').convert({
              'modelRevision': manifest.revision,
              'speaker': 29,
              'platform': Platform.operatingSystem,
              'loadMs': loadMs,
              'clinicalApproved': false,
              'humanListeningApproved': false,
              'samples': rows,
            }),
          );
        }
        await engine.dispose();
        await expectLater(engine.synthesize(voice.$4), throwsStateError);
      },
      skip: !enabled,
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }

  // Track B proof: a piper voice trained from the licensed Dagbani corpus by
  // tool/track_b must load and speak through the same engine as the shipped
  // voices. The pack is a local training artifact (data/ is not committed), so
  // this asserts nothing until a training run has been done on this machine.
  test(
    'a Dagbani voice we trained speaks through the app engine',
    () async {
      const base = 'data/dagbani';
      final modelFile = File('$base/model.onnx');
      if (!modelFile.existsSync()) return;
      final bytes = await modelFile.readAsBytes();
      final clock = Stopwatch()..start();
      final engine = await PiperNativeEngine.load(
        model: bytes,
        artifact: ModelArtifact(
          'model.onnx',
          bytes.length,
          sha256.convert(bytes).toString(),
        ),
        config: await File('$base/model.onnx.json').readAsString(),
        language: 'Dagbani',
        speaker: 0,
      );
      addTearDown(engine.dispose);
      final wav = await engine.synthesize(SpeechBank.qNewbornFeed.dagbani);
      final data = ByteData.sublistView(wav);
      final rate = data.getUint32(24, Endian.little);
      final seconds = (wav.length - 44) / 2 / rate;
      var peak = 0;
      for (var offset = 44; offset + 1 < wav.length; offset += 2) {
        final value = data.getInt16(offset, Endian.little).abs();
        if (value > peak) peak = value;
      }
      expect(seconds, greaterThan(0.1));
      expect(peak, greaterThan(20));
      await Directory('build').create(recursive: true);
      await File('build/dagbani_trained.wav').writeAsBytes(wav);
      // ignore: avoid_print
      print(
        'trained Dagbani pack: ${bytes.length / 1e6} MB on disk, '
        '${seconds.toStringAsFixed(2)}s audio in ${clock.elapsedMilliseconds}ms, '
        'peak=$peak',
      );
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
