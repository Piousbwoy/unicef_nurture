import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:carebridge_ai/core/ml/piper_phonemizer.dart';
import 'package:carebridge_ai/core/ml/piper_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final config = File(
    'assets/tts/twi_piper/model.onnx.json',
  ).readAsStringSync();
  final rules = File('assets/tts/twi_piper/twi_rules.json').readAsStringSync();
  final reference =
      jsonDecode(
            File(
              'test/fixtures/voice/twi_reference_vectors.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final frontend = PiperPhonemizer.fromConfig(config, 'Twi', twiRules: rules);

  group('pinned Twi frontend contract', () {
    for (final item in reference['cases'] as List) {
      final sample = item as Map<String, dynamic>;
      test('reference IDs: ${sample['language']} ${sample['text']}', () {
        // All vectors exercise wrapping. Only Twi vectors exercise text G2P;
        // English phonemization is not certified by precomputed phoneme IDs.
        expect(
          frontend.encodeUnits(
            List<String>.from(sample['units']),
            languageToken: sample['language'] == 'mixed'
                ? 'twi'
                : sample['language'],
          ),
          sample['ids'],
        );
        if (sample['language'] == 'twi') {
          expect(frontend.phonemes(sample['text']), sample['units']);
          expect(frontend.encode(sample['text']), sample['ids']);
        }
      });
    }
    test('unknown characters cannot disappear from speech', () {
      expect(() => frontend.encode('Akwaaba 😀'), throwsFormatException);
      expect(
        () => frontend.encodeUnits(['not-a-phoneme']),
        throwsFormatException,
      );
    });
    test('empty text produces no BOS/EOS-only utterance', () {
      expect(frontend.encode('  \n '), isEmpty);
    });
    test('Twi rules are mandatory; text config does not imply raw letters', () {
      expect(
        () => PiperPhonemizer.fromConfig(config, 'Twi'),
        throwsFormatException,
      );
    });
    test('Hausa uses its own inventory with inter-unit padding', () {
      final ha = PiperPhonemizer.fromConfig(
        File('assets/tts/hausa_piper/model.onnx.json').readAsStringSync(),
        'Hausa',
      );
      expect(ha.encode('a ɓ'), [1, 0, 12, 0, 3, 0, 34, 0, 2]);
      expect(() => ha.encode('😀'), throwsFormatException);
    });
  });

  group('Piper audio contract', () {
    test('extracts real rank-four output without losing samples', () {
      final samples = PiperAudio.samples([
        [
          [
            [0.0, 0.2, -0.2],
          ],
        ],
      ]);
      expect(
        samples,
        [0, 0.2, -0.2]
            .map((v) => v.toDouble())
            .toList()
            .map((v) => Float32List.fromList([v]).single)
            .toList(),
      );
    });
    test('rejects silence, non-finite, multi-channel and empty outputs', () {
      for (final raw in <Object>[
        <double>[],
        [0.0, 0.0],
        [double.nan],
        [double.infinity],
        [
          [0.2],
          [0.3],
        ],
      ]) {
        expect(() => PiperAudio.samples(raw), throwsFormatException);
      }
    });
    test('WAV uses exact model sample rate and signed PCM', () {
      final wav = PiperAudio.wav(Float32List.fromList([0.5, -0.5]), 22050);
      final bytes = ByteData.sublistView(wav);
      expect(ascii.decode(wav.sublist(0, 4)), 'RIFF');
      expect(bytes.getUint32(24, Endian.little), 22050);
      expect(bytes.getUint32(40, Endian.little), 4);
      expect(bytes.getInt16(44, Endian.little), 16384);
      expect(bytes.getInt16(46, Endian.little), -16384);
    });
    test('model scales are float32 noise/length/noise-width in order', () {
      final spec = PiperModelSpec.fromJson(config);
      expect(spec.scales, isA<Float32List>());
      expect(spec.scales[0], closeTo(0.667, 0.00001));
      expect(spec.scales[1], 1);
      expect(spec.scales[2], closeTo(0.8, 0.00001));
      expect(spec.sampleRate, 22050);
      spec.validateSpeaker(29);
      expect(() => spec.validateSpeaker(1555), throwsFormatException);
      spec.validateInputs(['input', 'input_lengths', 'scales', 'sid']);
      expect(
        () => spec.validateInputs(['input', 'scales']),
        throwsFormatException,
      );
    });
    test('sentence chunks preserve every word and punctuation', () {
      const text = 'Akwaaba. Me da wo ase paa. Wo ho te sɛn?';
      final chunks = PiperAudio.chunks(text, maxCharacters: 24);
      expect(chunks.join(' '), text);
      expect(chunks.every((s) => s.length <= 24), isTrue);
    });
  });

  group('prosody presets (delivery only, never content)', () {
    final spec = PiperModelSpec.fromJson(config); // [0.667, 1.0, 0.8]
    test('standard returns the checkpoint scales unchanged', () {
      expect(spec.scalesFor(SpeechProsody.standard), spec.scales);
    });
    test('urgent is faster/crisper, soothing is slower/warmer', () {
      final std = spec.scalesFor(SpeechProsody.standard);
      final urgent = spec.scalesFor(SpeechProsody.urgent);
      final soothing = spec.scalesFor(SpeechProsody.soothing);
      // [noise, length, noise_w]
      expect(urgent[1], lessThan(std[1])); // quicker speech rate
      expect(soothing[1], greaterThan(std[1])); // slower, more deliberate
      expect(urgent[0], lessThan(std[0])); // less stochastic breathiness
      expect(soothing[0], greaterThan(std[0])); // warmer
      expect(urgent[2], lessThan(std[2]));
      expect(soothing[2], greaterThan(std[2]));
    });
    test(
      'every preset stays in a safe finite band and never touches content',
      () {
        for (final p in SpeechProsody.values) {
          final s = spec.scalesFor(p);
          expect(s, hasLength(3));
          for (final v in s) {
            expect(v.isFinite, isTrue);
            expect(v, greaterThan(0));
          }
        }
      },
    );
    test('extreme configs are clamped, never emitted raw', () {
      final huge = PiperModelSpec.fromJson(
        jsonEncode({
          'audio': {'sample_rate': 22050},
          'num_speakers': 1,
          'inference': {
            'noise_scale': 4.0,
            'length_scale': 4.0,
            'noise_w': 4.0,
          },
        }),
      );
      for (final v in huge.scalesFor(SpeechProsody.soothing)) {
        expect(v, lessThanOrEqualTo(1.80));
      }
      final tiny = PiperModelSpec.fromJson(
        jsonEncode({
          'audio': {'sample_rate': 22050},
          'num_speakers': 1,
          'inference': {
            'noise_scale': 0.1,
            'length_scale': 0.1,
            'noise_w': 0.1,
          },
        }),
      );
      for (final v in tiny.scalesFor(SpeechProsody.urgent)) {
        expect(v, greaterThanOrEqualTo(0.25));
      }
    });
  });
}
