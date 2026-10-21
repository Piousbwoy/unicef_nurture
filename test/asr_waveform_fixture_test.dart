import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:carebridge_ai/core/ml/asr_contract.dart';
import 'package:carebridge_ai/core/ml/asr_features.dart';
import 'package:flutter_test/flutter_test.dart';

/// The `waveform` half of the `asr-v1` contract, pinned against the real
/// `Wav2Vec2FeatureExtractor` (`tool/asr_export/make_waveform_fixture.py`).
///
/// This recipe is one subtraction and one division, which is precisely why it
/// needs a fixture: sample-versus-population variance, or the epsilon inside
/// instead of outside the root, changes the number the model was trained on and
/// still returns a fluent transcript.
const pack = 'test/fixtures/asr/waveform_pack';
const fbankPack = 'test/fixtures/asr/pack';

void main() {
  final fixtures = (jsonDecode(
        File('test/fixtures/asr/waveform_fixtures.json').readAsStringSync(),
      ) as List)
      .cast<Map<String, dynamic>>();
  final config = File('$pack/frontend.json').readAsStringSync();

  Map<String, Object?> audio(Map<String, Object?> override) {
    final decoded = jsonDecode(config) as Map<String, dynamic>;
    return {...decoded['audio'] as Map<String, Object?>, ...override};
  }

  String configWith({Map<String, Object?>? audioFields, Map<String, Object?>? modelFields}) {
    final decoded = jsonDecode(config) as Map<String, dynamic>;
    return jsonEncode({
      ...decoded,
      'audio': audio({...?audioFields}),
      'model': {...decoded['model'] as Map<String, Object?>, ...?modelFields},
    });
  }

  group('waveform contract', () {
    test('reads as a waveform pack, not a mel pack wearing a hat', () {
      final spec = AsrModelSpec.fromJson(config);
      expect(spec.isWaveform, isTrue);
      expect(spec.featureType, 'waveform');
      expect(spec.inputDim, 1);
      expect(spec.framesPerSecond, 16000);
      expect(spec.waveformEpsilon, 1e-7);
      // The fields a raw-waveform pack does not have stay absent rather than
      // being filled with a geometry someone could later feed to the mel path.
      expect(spec.fbank, isNull);
      expect(spec.inputNames, ['input_values', 'attention_mask']);
      expect(spec.labels.length, 36);
      expect(spec.labels[spec.blankIndex], '[PAD]');
    });

    test('its frames are samples, capped by the pack rather than by framing', () {
      final spec = AsrModelSpec.fromJson(config);
      expect(spec.framesFor(19200), 19200);
      // max_frames is 64000: the app's four-second ceiling, held as a ceiling on
      // memory, not a claim that a longer take is fine.
      expect(spec.framesFor(64001), 64000);
    });

    test('refuses a waveform pack that lies about its width or rate', () {
      expect(
        () => AsrModelSpec.fromJson(configWith(audioFields: {'input_dim': 80})),
        throwsFormatException,
      );
      expect(
        () => AsrModelSpec.fromJson(
          configWith(audioFields: {'frames_per_second': 50}),
        ),
        throwsFormatException,
      );
      expect(
        () => AsrModelSpec.fromJson(
          configWith(
            modelFields: {
              'inputs': ['input_features', 'attention_mask'],
            },
          ),
        ),
        throwsFormatException,
      );
    });

    test('an unknown recipe still fails loudly', () {
      expect(
        () => AsrModelSpec.fromJson(
          configWith(audioFields: {'features': 'mfcc'}),
        ),
        throwsFormatException,
      );
    });
  });

  group('waveform frontend', () {
    for (final clip in fixtures) {
      test('${clip['name']} matches the real extractor', () {
        final samples = Float32List.fromList(
          (clip['samples'] as List)
              .cast<num>()
              .map((value) => value.toDouble())
              .toList(),
        );
        final expected = (clip['input_values'] as List).cast<num>();
        final mask = (clip['attention_mask'] as List).cast<num>();
        final features = AsrFrontend.fromPack(
          spec: AsrModelSpec.fromJson(config),
        ).process(samples);
        expect(features.length, expected.length);
        expect(mask.length, expected.length);
        expect(mask.every((value) => value == 1), isTrue);
        var worst = 0.0;
        for (var i = 0; i < expected.length; i++) {
          final error = (features[i] - expected[i].toDouble()).abs();
          if (error > worst) worst = error;
        }
        expect(worst, lessThan(1e-5));
      });
    }

    test('a silent take stays finite instead of decoding into noise', () {
      final frontend = AsrFrontend.fromPack(
        spec: AsrModelSpec.fromJson(config),
      );
      expect(frontend.process(Float32List(0)), isEmpty);
      final features = frontend.process(Float32List(320));
      expect(features, hasLength(320));
      expect(features.every((value) => value.isFinite), isTrue);
    });

    test('the take comes back centred and unit-scaled', () {
      final shape = Float32List.fromList(
        [for (var i = 0; i < 16000; i++) (i % 97) / 97.0 - 0.5],
      );
      final features = WaveformFrontend(1e-7).process(shape);
      var mean = 0.0;
      for (final value in features) {
        mean += value;
      }
      mean /= features.length;
      expect(mean, closeTo(0, 1e-9));
      var variance = 0.0;
      for (final value in features) {
        variance += (value - mean) * (value - mean);
      }
      expect(variance / features.length, closeTo(1, 1e-3));
      // It is not scale-invariant at a whisper: the epsilon sits inside the
      // root, so a take quieter than about sqrt(1e-7) comes back under unit
      // variance. The Python extractor does the same arithmetic, which is why
      // this is pinned by fixture rather than by a symmetry nobody checked.
    });

    test('a waveform pack cannot be handed mel tables', () {
      final spec = AsrModelSpec.fromJson(config);
      final tables = File('$fbankPack/mel_filters.json').readAsStringSync();
      final window = File('$fbankPack/window.json').readAsStringSync();
      expect(
        () => AsrFrontend.fromPack(
          spec: spec,
          filters: tables,
          window: window,
        ),
        throwsFormatException,
      );
    });

    test('a mel pack missing its tables is refused, not guessed at', () {
      final spec = AsrModelSpec.fromJson(
        File('$fbankPack/frontend.json').readAsStringSync(),
      );
      expect(() => AsrFrontend.fromPack(spec: spec), throwsFormatException);
    });
  });
}
