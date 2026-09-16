import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:carebridge_ai/core/ml/tflite_dart_interpreter.dart';
import 'package:carebridge_ai/core/ml/offline_inference_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const run = String.fromEnvironment(
    'RESEARCH_RUN',
    defaultValue: 'tool/research_runs/evidence_v1',
  );
  final fixtures =
      jsonDecode(File('$run/runtime_fixtures.json').readAsStringSync()) as Map;
  for (final fixture in fixtures['cases'] as List) {
    test(
      '${fixture['name']} boundary/missing preprocessing and exact INT8 input parity',
      () {
        final model = TfliteDartModel.fromBytes(
          File(fixture['model_path'] as String).readAsBytesSync(),
        );
        for (final c in fixture['cases'] as List) {
          final columns = fixture['features'] as List;
          final input = columns.isEmpty
              ? Float32List.fromList(
                  (c['normalized'] as List)
                      .cast<num>()
                      .map((n) => n.toDouble())
                      .toList(),
                )
              : Float32List.fromList(
                  List.generate(columns.length, (i) {
                    final f = columns[i] as Map;
                    final raw = c['raw'][i] as num?;
                    return raw == null
                        ? (f['imputation_normalized'] as num).toDouble()
                        : ResearchTransform.normalize(
                            raw.toDouble(),
                            (f['min'] as num).toDouble(),
                            (f['max'] as num).toDouble(),
                          );
                  }),
                );
          expect(input, c['normalized']);
          final actual = model.run(input);
          expect(model.quantizedInput, c['quantized']);
          expect(
            actual,
            closeTo(
              (c['expected'] as num).toDouble(),
              (fixture['tolerance'] as num).toDouble(),
            ),
          );
        }
      },
    );
  }
  test('invalid normalization does not clip into model support', () {
    expect(
      () => ResearchTransform.normalize(100, 34, 41),
      throwsFormatException,
    );
    expect(
      () => ResearchTransform.normalize(double.nan, 0, 1),
      throwsFormatException,
    );
  });
  for (final name in ['neonatal_sepsis', 'preeclampsia_risk', 'lbw_sga']) {
    test('$name official TFLite versus pure-Dart INT8 output', () {
      final fixture =
          jsonDecode(File('$run/${name}_parity.json').readAsStringSync())
              as Map;
      final model = TfliteDartModel.fromBytes(
        File(fixture['model_path'] as String).readAsBytesSync(),
      );
      final tolerance = (fixture['output_quantization'][0] as num).toDouble();
      for (final c in fixture['cases'] as List) {
        final input = Float32List.fromList(
          (c['input'] as List).cast<num>().map((n) => n.toDouble()).toList(),
        );
        final actual = model.run(input);
        expect(actual, closeTo((c['expected'] as num).toDouble(), tolerance));
      }
    });
  }
}
