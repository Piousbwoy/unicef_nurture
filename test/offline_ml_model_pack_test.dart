// Offline contract, fail-closed execution, and research/clinical separation.
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:carebridge_ai/core/ml/offline_inference_service.dart';
import 'package:carebridge_ai/core/ml/tflite_runner.dart';

const _contractPath = 'assets/models/research_contracts.json';
const _modelPath = 'assets/models/neonatal_sepsis_int8_v1.tflite';
const _complete = OfflineFeatureBag(
  ageDays: 2,
  temperatureCelsius: 37,
  respiratoryRatePerMin: 48,
  heartRatePerMin: 140,
  oxygenSaturationPerCent: 97,
  birthWeightKg: 3,
  apgar5Minute: 9,
  historyOfConvulsions: false,
  severeChestIndrawing: false,
  nasalFlaring: false,
  grunting: false,
  bulgingFontanelle: false,
  jaundiceBefore24h: false,
  feedingDifficulty: false,
  abdominalDistension: false,
  cordPus: false,
  cordRednessBeyondBase: false,
  skinPustules: false,
  lethargicOrUnconscious: false,
  bleedingFromAnySite: false,
  hivExposedOrInfected: false,
  multipleBirth: false,
);

class _Bundle extends CachingAssetBundle {
  final overrides = <String, ByteData?>{};
  final loads = <String, int>{};
  @override
  Future<ByteData> load(String key) async {
    loads.update(key, (n) => n + 1, ifAbsent: () => 1);
    if (overrides.containsKey(key)) {
      final data = overrides[key];
      if (data == null) throw StateError('Missing test asset');
      return data;
    }
    return rootBundle.load(key);
  }

  void json(String key, Object value) => overrides[key] = ByteData.sublistView(
    Uint8List.fromList(utf8.encode(jsonEncode(value))),
  );
}

class _Runner implements TfliteRunner {
  _Runner({this.output = 0.8, this.fail = false});
  final double output;
  final bool fail;
  int calls = 0;
  Float32List? input;
  @override
  Future<double> run({
    required String assetPath,
    required Float32List input,
  }) async {
    calls++;
    this.input = input;
    if (fail) throw StateError('Interpreter unavailable');
    return output;
  }
}

Future<_Bundle> _bundle({
  void Function(Map)? mutate,
  bool research = false,
}) async {
  final bundle = _Bundle();
  final root = jsonDecode(await rootBundle.loadString(_contractPath)) as Map;
  final c = root['models']['neonatal_sepsis'] as Map;
  if (research) {
    // A test-only eligibility contract; never written to shipped assets.
    c['evidence'] = 'retrospective_research';
    c['patient_output_allowed'] = true;
    c['calibration'] = {'A': 1.0, 'B': 0.0};
    for (final f in c['features'] as List) {
      f['supported'] = true;
    }
  }
  mutate?.call(c);
  bundle.json(_contractPath, root);
  return bundle;
}

void _noClinicalOutput(OfflineRiskPrediction p) {
  expect(p.riskProbability, isNull);
  expect(p.classification, 'unavailable');
  expect(p.clinicallyActionable, isFalse);
  expect(p.ruleInCandidate, isFalse);
  expect(p.ruleInThreshold, isNull);
  expect(p.confidenceInterval95, isNull);
  expect(p.toMap()['risk_probability'], isNull);
  expect(p.toMap()['rule_in_candidate'], 0);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'all four shipped binaries match hashes, signatures and real versions',
    () async {
      final statuses = await OfflineInferenceService().modelStatuses();
      expect(statuses, hasLength(4));
      for (final s in statuses) {
        final data = await rootBundle.load(s.modelAssetPath);
        expect(
          sha256
              .convert(
                data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
              )
              .toString(),
          s.expectedSha256,
        );
        expect(s.isModelPresent, isTrue);
        expect(s.hasMetrics, isTrue);
        expect(s.integrityVerified, isTrue);
        expect(s.metadataValid, isTrue, reason: s.name);
        expect(s.isModelUsable, isTrue);
        expect(s.modelVersion, s.contract['model_version']);
        expect(s.contract['patient_output_allowed'], isFalse);
        expect(s.headlineValidation, isEmpty);
        expect(s.externalValidation, isEmpty);
      }
    },
  );

  test('concurrent initialization loads each asset once', () async {
    final bundle = await _bundle();
    final runner = _Runner();
    final service = OfflineInferenceService(bundle: bundle, runner: runner);
    await Future.wait([
      service.modelStatuses(),
      service.runAllPredictions(_complete),
      service.neonatalSepsisRisk(_complete),
    ]);
    expect(bundle.loads[_contractPath], 1);
    expect(bundle.loads[_modelPath], 1);
    expect(runner.calls, 0);
  });

  test(
    'legacy and synthetic artifacts never yield patient probabilities',
    () async {
      final runner = _Runner();
      final service = OfflineInferenceService(runner: runner);
      for (final p in (await service.runAllPredictions(_complete)).values) {
        _noClinicalOutput(p);
        expect(p.researchOutput, isNull);
      }
      final neonatal = await service.neonatalSepsisRisk(_complete);
      expect(neonatal.execution, ModelExecution.notRun);
      expect(neonatal.evidence, ModelEvidence.legacyRealData);
      expect(neonatal.unsupportedFeatures, contains('feeding_difficulty'));
      expect(runner.calls, 0);
    },
  );

  for (final key in [
    'input_dtype',
    'input_shape',
    'output_type',
    'output_shape',
    'input_quantization',
    'input_quantization_arithmetic',
    'features',
    'evaluation',
    'model_version',
  ]) {
    test('invalid $key metadata fails explicitly', () async {
      final bundle = await _bundle(mutate: (c) => c[key] = 'invalid');
      final p = await OfflineInferenceService(
        bundle: bundle,
      ).neonatalSepsisRisk(_complete);
      expect(p.execution, ModelExecution.invalidMetadata);
      _noClinicalOutput(p);
    });
  }
  for (final missing in [true, false]) {
    test(
      '${missing ? 'missing' : 'malformed'} contract fails closed',
      () async {
        final bundle = _Bundle();
        bundle.overrides[_contractPath] = missing ? null : ByteData(2);
        final p = await OfflineInferenceService(
          bundle: bundle,
        ).neonatalSepsisRisk(_complete);
        expect(p.execution, ModelExecution.invalidMetadata);
        _noClinicalOutput(p);
      },
    );
  }
  test('missing model and corrupt bytes have distinct states', () async {
    final missing = _Bundle()..overrides[_modelPath] = null;
    expect(
      (await OfflineInferenceService(
        bundle: missing,
      ).neonatalSepsisRisk(_complete)).execution,
      ModelExecution.unavailable,
    );
    final corrupt = _Bundle()..overrides[_modelPath] = ByteData(8);
    expect(
      (await OfflineInferenceService(
        bundle: corrupt,
      ).neonatalSepsisRisk(_complete)).execution,
      ModelExecution.integrityFailure,
    );
  });

  test(
    'required observations are not zero-filled; invalid and unsupported differ',
    () async {
      final service = OfflineInferenceService();
      final missing = await service.neonatalSepsisRisk(
        const OfflineFeatureBag(ageDays: 2),
      );
      expect(missing.inputQuality, ModelInputQuality.missingObservations);
      expect(missing.featuresMissing, contains('heart_rate_per_min'));
      for (final temperature in [double.nan, -1.0, 70.0]) {
        final p = await service.neonatalSepsisRisk(
          OfflineFeatureBag(ageDays: 2, temperatureCelsius: temperature),
        );
        expect(p.inputQuality, ModelInputQuality.invalidValues);
        _noClinicalOutput(p);
      }
      final outside = await service.neonatalSepsisRisk(
        const OfflineFeatureBag(ageDays: 14, temperatureCelsius: 42),
      );
      expect(outside.inputQuality, ModelInputQuality.outsideSupport);
      expect(outside.driftFeatures, contains('age_days'));
      _noClinicalOutput(outside);
    },
  );

  test(
    'cohort boundaries never infer newborn eligibility from unknown age',
    () async {
      final service = OfflineInferenceService();
      for (final age in <int?>[null, -1, 60]) {
        final p = await service.neonatalSepsisRisk(
          OfflineFeatureBag(ageDays: age),
        );
        expect(
          p.applicability,
          age == null
              ? ModelApplicability.unknownCohort
              : ModelApplicability.unsupportedCohort,
        );
      }
      for (final months in [1, 2, 59, 60]) {
        final p = await service.childPneumoniaRisk(
          OfflineFeatureBag(ageMonths: months),
        );
        expect(
          p.applicability,
          months == 2 || months == 59
              ? ModelApplicability.applicable
              : ModelApplicability.unsupportedCohort,
        );
      }
      expect(
        (await service.preeclampsiaRisk(
          const OfflineFeatureBag(gestationalWeeks: 32),
        )).applicability,
        ModelApplicability.unsupportedCohort,
      );
      expect(
        (await service.preeclampsiaRisk(
          const OfflineFeatureBag(isMaternal: true, gestationalWeeks: 19),
        )).applicability,
        ModelApplicability.unsupportedCohort,
      );
    },
  );

  test(
    'permitted research execution uses ordered normalization and logit calibration',
    () async {
      final bundle = await _bundle(
        research: true,
        mutate: (c) => c['calibration'] = {'A': 2, 'B': 0},
      );
      final runner = _Runner();
      final p = await OfflineInferenceService(
        bundle: bundle,
        runner: runner,
      ).neonatalSepsisRisk(_complete);
      expect(p.execution, ModelExecution.completed);
      expect(p.researchOutput, closeTo(16 / 17, 1e-7));
      expect(runner.input![0], closeTo(2 / 59, 1e-7));
      expect(runner.input![1], closeTo(3 / 7, 1e-7));
      _noClinicalOutput(p);
    },
  );

  for (final output in [double.nan, double.infinity, -0.1, 1.1]) {
    test('invalid interpreter output $output never becomes 0.5', () async {
      final p = await OfflineInferenceService(
        bundle: await _bundle(research: true),
        runner: _Runner(output: output),
      ).neonatalSepsisRisk(_complete);
      expect(p.execution, ModelExecution.failed);
      expect(p.researchOutput, isNull);
      _noClinicalOutput(p);
    });
  }
  test('interpreter exception has explicit unavailable output', () async {
    final p = await OfflineInferenceService(
      bundle: await _bundle(research: true),
      runner: _Runner(fail: true),
    ).neonatalSepsisRisk(_complete);
    expect(p.execution, ModelExecution.failed);
    _noClinicalOutput(p);
  });

  test(
    'optional missing observation uses only declared training imputation',
    () async {
      final bundle = await _bundle(
        research: true,
        mutate: (c) {
          final feature = (c['features'] as List).firstWhere(
            (f) => f['name'] == 'temperature_celsius',
          );
          feature['required'] = false;
          feature['imputation'] = 37.5;
        },
      );
      final runner = _Runner();
      final p = await OfflineInferenceService(
        bundle: bundle,
        runner: runner,
      ).neonatalSepsisRisk(_complete.withoutFeature('temperature_celsius'));
      expect(p.imputedFeatures, contains('temperature_celsius'));
      expect(p.featuresMissing, contains('temperature_celsius'));
      expect(p.featuresUsed, isNot(contains('temperature_celsius')));
      expect(p.execution, ModelExecution.completed);
      expect(runner.input![1], closeTo(0.5, 1e-7));
    },
  );
}
