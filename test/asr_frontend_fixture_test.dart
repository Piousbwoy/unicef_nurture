import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:carebridge_ai/core/ml/asr_contract.dart';
import 'package:carebridge_ai/core/ml/asr_features.dart';
import 'package:flutter_test/flutter_test.dart';

/// The proof that `AsrFrontend` *is* HuggingFace's feature extractor.
///
/// `test/fixtures/asr/frontend_fixtures.json` holds clips pushed through the
/// real `SeamlessM4TFeatureExtractor`, and `test/fixtures/asr/pack` holds the mel
/// matrix and window that run produced them; this replays the same samples
/// through Dart and fails on disagreement. A frontend that is subtly wrong does
/// not crash — it transcribes the wrong words fluently, which in a triage flow is
/// the worst failure this app can have.
void main() {
  const pack = 'test/fixtures/asr/pack';
  final fixtures =
      jsonDecode(
            File('test/fixtures/asr/frontend_fixtures.json').readAsStringSync(),
          )
          as List;

  AsrFrontend frontend() => AsrFrontend.fromPack(
    spec: AsrModelSpec.fromJson(File('$pack/frontend.json').readAsStringSync()),
    filters: File('$pack/mel_filters.json').readAsStringSync(),
    window: File('$pack/window.json').readAsStringSync(),
  );

  for (final clip in fixtures) {
    test('${clip['name']} features match the real extractor', () {
      final spec = AsrModelSpec.fromJson(
        File('$pack/frontend.json').readAsStringSync(),
      );
      final samples = Float32List.fromList(
        (clip['samples'] as List).cast<num>().map((v) => v.toDouble()).toList(),
      );
      final expected = (clip['input_features'] as List).cast<List<dynamic>>();
      // The pack's own geometry, not a re-derivation: 1.2 s of 16 kHz audio is
      // 118 analysis frames of 400 at a 160 hop, and 59 stacked frames of 160.
      expect(spec.fbank!.melFrames(samples.length), 118);
      expect(spec.framesFor(samples.length), 59);
      final features = frontend().process(samples);
      expect(features.length, expected.length * spec.inputDim);
      expect(
        (clip['attention_mask'] as List).length,
        spec.framesFor(samples.length),
      );
      var worst = 0.0;
      var where = '';
      for (var t = 0; t < expected.length; t++) {
        for (var d = 0; d < spec.inputDim; d++) {
          final error =
              (features[t * spec.inputDim + d] -
                      (expected[t][d] as num).toDouble())
                  .abs();
          if (error > worst) {
            worst = error;
            where = 'frame $t dim $d';
          }
        }
      }
      // Measured: 1.7e-6 on both clips, which is the float32 the features are
      // stored in. A recipe difference is three orders of magnitude bigger —
      // reading the variance with numpy's ddof instead of torch's is 1.5e-2.
      // ignore: avoid_print
      print('${clip['name']}: max abs feature error $worst at $where');
      expect(worst, lessThan(1e-5));
    });
  }

  test('refuses a mel bank whose recorded axes are the other way round', () {
    final spec = AsrModelSpec.fromJson(
      File('$pack/frontend.json').readAsStringSync(),
    );
    final bank =
        jsonDecode(File('$pack/mel_filters.json').readAsStringSync())
            as Map<String, dynamic>;
    // A transposed bank still yields a plausible spectrogram, so the shape and
    // the axis names are both checked rather than assumed.
    final transposed = jsonEncode({
      'axes': ['mel_filter', 'frequency_bin'],
      'shape': [bank['shape'][1], bank['shape'][0]],
      'values': [
        for (var m = 0; m < (bank['shape'][1] as int); m++)
          [
            for (var b = 0; b < (bank['shape'][0] as int); b++)
              (bank['values'] as List)[b][m],
          ],
      ],
    });
    expect(
      () => AsrFrontend.fromPack(
        spec: spec,
        filters: transposed,
        window: File('$pack/window.json').readAsStringSync(),
      ),
      throwsFormatException,
    );
  });

  test('a take too short for one window yields no features', () {
    final spec = AsrModelSpec.fromJson(
      File('$pack/frontend.json').readAsStringSync(),
    );
    expect(spec.fbank!.melFrames(spec.fbank!.frameLength - 1), 0);
    expect(
      frontend().process(Float32List(spec.fbank!.frameLength - 1)),
      isEmpty,
    );
    expect(frontend().process(Float32List(0)), isEmpty);
  });
}
