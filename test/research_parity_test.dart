import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:carebridge_ai/core/ml/tflite_dart_interpreter.dart';
import 'package:carebridge_ai/core/ml/offline_inference_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:carebridge_ai/core/ml/tflite_runner.dart';
import 'package:crypto/crypto.dart';
import 'package:carebridge_ai/core/ml/tflite_runner_stub.dart' as web_runtime;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const run = String.fromEnvironment(
    'RESEARCH_RUN',
    defaultValue: 'tool/research_runs/evidence_v1',
  );
  final experimental =
      jsonDecode(
            File('$run/neonatal_experimental_parity.json').readAsStringSync(),
          )
          as Map;
  test(
    'experimental policy exact INT8 and official Python versus Dart outputs',
    () {
      final bytes = File(
        experimental['model_path'] as String,
      ).readAsBytesSync();
      expect(sha256.convert(bytes).toString(), experimental['artifact_sha256']);
      final graph = TfliteDartModel.fromBytes(bytes);
      for (final c in experimental['cases'] as List) {
        final input = Float32List.fromList(
          (c['normalized'] as List)
              .cast<num>()
              .map((v) => v.toDouble())
              .toList(),
        );
        final output = graph.run(input);
        expect(graph.quantizedInput, c['quantized'], reason: c['name']);
        expect(
          output,
          closeTo((c['raw_output'] as num).toDouble(), 1e-5),
          reason: c['name'],
        );
      }
    },
  );
  test(
    'native Flutter runner matches official Python experimental vectors',
    () async {
      final runner = getTfliteRunner();
      for (final c in experimental['cases'] as List) {
        final output = await runner.run(
          assetPath: experimental['model_path'] as String,
          input: Float32List.fromList(
            (c['normalized'] as List)
                .cast<num>()
                .map((v) => v.toDouble())
                .toList(),
          ),
        );
        expect(
          output,
          closeTo((c['raw_output'] as num).toDouble(), 1e-5),
          reason: c['name'],
        );
      }
    },
    skip: !const bool.fromEnvironment('NATIVE_TFLITE')
        ? 'Requires native app/test host with the TFLite library beside its executable; enable NATIVE_TFLITE there.'
        : false,
  );
  test(
    'service preprocessing and adjustment match official experimental vectors',
    () async {
      final service = OfflineInferenceService(
        runner: web_runtime.createTfliteRunner(),
      );
      for (final c in (experimental['cases'] as List).take(3)) {
        final raw = (c['raw'] as List).cast<num>();
        final p = await service.neonatalSepsisRisk(
          OfflineFeatureBag(
            ageDays: raw[0].toInt(),
            temperatureCelsius: raw[1].toDouble(),
            respiratoryRatePerMin: raw[2].toInt(),
            heartRatePerMin: raw[3].toInt(),
            currentWeightKg: raw[4].toDouble(),
          ),
        );
        expect(p.execution, ModelExecution.completed, reason: p.statusReason);
        expect(
          p.rawNeuralOutput,
          closeTo((c['raw_output'] as num).toDouble(), 1e-5),
        );
        expect(
          p.researchOutput,
          closeTo((c['adjusted_output'] as num).toDouble(), 1e-5),
        );
      }
    },
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
