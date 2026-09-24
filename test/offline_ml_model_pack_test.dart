// Offline contract, fail-closed execution, and research/clinical separation.
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:carebridge_ai/core/ml/offline_inference_service.dart';
import 'package:carebridge_ai/core/ml/tflite_runner.dart';
import 'package:carebridge_ai/core/ml/tflite_runner_stub.dart' as web_runtime;

const _contractPath = 'assets/models/research_contracts.json';
const _modelPath = 'assets/models/neonatal_sepsis_int8_v1.tflite';
const _complete = OfflineFeatureBag(
  ageDays: 2,
  temperatureCelsius: 37,
  respiratoryRatePerMin: 48,
  heartRatePerMin: 140,
  oxygenSaturationPerCent: 97,
  birthWeightKg: 2,
  currentWeightKg: 3,
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
  _Runner({this.output = 0.8, this.fail = false, this.outputs, this.failAt});
  final double output;
  final bool fail;
  final List<double>? outputs;
  final int? failAt;
  bool busy = false;
  int calls = 0;
  Float32List? input;
  final inputs = <Float32List>[];
  @override
  Future<double> run({
    required String assetPath,
    required Float32List input,
  }) async {
    if (busy && outputs != null) {
      throw StateError('Concurrent interpreter access');
    }
    busy = true;
    calls++;
    this.input ??= Float32List.fromList(input);
    inputs.add(Float32List.fromList(input));
    await Future<void>.delayed(Duration.zero);
    busy = false;
    if (fail || calls == failAt) throw StateError('Interpreter unavailable');
    return outputs == null ? output : outputs![calls - 1];
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
    c.remove('input_policy_version');
    c.remove('output_scope');
    c.remove('sensitivity_baseline');
    c['evidence'] = 'retrospective_research';
    c['patient_output_allowed'] = true;
    c['calibration'] = {'A': 1.0, 'B': 0.0};
    for (final f in c['features'] as List) {
      f.remove('input_policy');
      f.remove('constant_normalized');
      f.remove('fixed_reason');
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
        expect(
          s.contract['patient_output_allowed'],
          s.name == 'neonatal_sepsis',
        );
        expect(s.contract['clinical_use_allowed'], isFalse);
        expect(s.headlineValidation, isEmpty);
        expect(s.externalValidation, isEmpty);
      }
    },
  );

  test(
    'neonatal execution requires current weight, never stored birth weight',
    () async {
      final runner = _Runner();
      final p = await OfflineInferenceService(
        runner: runner,
      ).neonatalSepsisRisk(_complete.withoutFeature('current_weight_kg'));
      expect(p.inputQuality, ModelInputQuality.missingObservations);
      expect(p.featuresMissing, contains('current_weight_kg'));
      expect(p.execution, ModelExecution.notRun);
      expect(runner.calls, 0);
      _noClinicalOutput(p);
    },
  );

  test(
    'display permission fails closed for every unverified or invalid state',
    () {
      OfflineRiskPrediction prediction(Map<String, dynamic> change) =>
          OfflineRiskPrediction(
            modelName: change['model'] ?? 'neonatal_sepsis',
            usingModel: change['using'] ?? true,
            riskProbability: null,
            classification: 'unavailable',
            featuresUsed: const [],
            featuresMissing: change['missing'] ?? const [],
            invalidFeatures: change['invalid'] ?? const [],
            predictedAt: DateTime(2026),
            rawNeuralOutput: change['raw'] ?? .8,
            researchOutput: change['adjusted'] ?? .04,
            patientOutputAllowed: change['allowed'] ?? true,
            runtimeVerified: change['verified'] ?? true,
            outputScope: change['scope'] ?? 'clinician_experimental',
            artifactSha256:
                change['hash'] ?? OfflineInferenceService.neonatalArtifact,
            inputPolicyVersion:
                change['policy'] ?? OfflineInferenceService.neonatalPolicy,
            execution: change['execution'] ?? ModelExecution.completed,
            evidence: change['evidence'] ?? ModelEvidence.legacyRealData,
            applicability: change['cohort'] ?? ModelApplicability.applicable,
            inputQuality: change['quality'] ?? ModelInputQuality.complete,
            driftDetected: change['drift'] ?? false,
          );
      expect(prediction({}).mayDisplayExperimentalOutput, isTrue);
      for (final change in <Map<String, dynamic>>[
        {'model': 'child_pneumonia'},
        {'using': false},
        {'allowed': false},
        {'verified': false},
        {'scope': 'clinical'},
        {'hash': 'wrong'},
        {'policy': 'unknown'},
        {'drift': true},
        {
          'missing': ['current_weight_kg'],
        },
        {
          'invalid': ['temperature_celsius'],
        },
        for (final execution in ModelExecution.values.where(
          (e) => e != ModelExecution.completed,
        ))
          {'execution': execution},
        for (final evidence in ModelEvidence.values.where(
          (e) => e != ModelEvidence.legacyRealData,
        ))
          {'evidence': evidence},
        for (final quality in ModelInputQuality.values.where(
          (e) => e != ModelInputQuality.complete,
        ))
          {'quality': quality},
        {'cohort': ModelApplicability.unknownCohort},
        {'cohort': ModelApplicability.unsupportedCohort},
        for (final value in [double.nan, double.infinity, -.1, 1.1]) ...[
          {'raw': value},
          {'adjusted': value},
        ],
      ]) {
        expect(
          prediction(change).mayDisplayExperimentalOutput,
          isFalse,
          reason: '$change',
        );
        expect(prediction(change).clinicallyActionable, isFalse);
      }
    },
  );

  test(
    'local sensitivities are sequential, signed and stably ranked',
    () async {
      final runner = _Runner(outputs: [.8, .6, .9, .6, .8, .7]);
      final p = await OfflineInferenceService(
        runner: runner,
      ).neonatalSepsisRisk(_complete);
      expect(p.sensitivityStatus, ModelSensitivityStatus.completed);
      expect(p.sensitivities.map((s) => s.featureKey), [
        'temperature_celsius',
        'age_days',
        'respiratory_rate_per_min',
        'current_weight_kg',
        'heart_rate_per_min',
      ]);
      expect(
        p.sensitivities.first.scorePointDelta,
        closeTo(-15.167173637413752, 1e-7),
      );
      expect(
        p.sensitivities[1].scorePointDelta,
        closeTo(3.925625077461277, 1e-7),
      );
      expect(p.sensitivities.last.scorePointDelta, 0);
      expect(p.sensitivities[1].rawValue, 2);
      expect(runner.calls, 6);
      _noClinicalOutput(p);
    },
  );

  test(
    'failed sensitivity retains primary output without invented drivers',
    () async {
      final p = await OfflineInferenceService(
        runner: _Runner(failAt: 3),
      ).neonatalSepsisRisk(_complete);
      expect(p.execution, ModelExecution.completed);
      expect(p.mayDisplayExperimentalOutput, isTrue);
      expect(p.rawNeuralOutput, .8);
      expect(p.researchOutput, closeTo(.04588406103741966, 1e-10));
      expect(p.sensitivityStatus, ModelSensitivityStatus.unavailable);
      expect(p.sensitivities, isEmpty);
      _noClinicalOutput(p);
    },
  );

  test(
    'real web graph executes the five-observed policy and sensitivity reruns',
    () async {
      final service = OfflineInferenceService(
        runner: web_runtime.createTfliteRunner(),
      );
      final p = await service.neonatalSepsisRisk(_complete);
      expect(p.execution, ModelExecution.completed, reason: p.statusReason);
      expect(p.mayDisplayExperimentalOutput, isTrue);
      expect(p.sensitivityStatus, ModelSensitivityStatus.completed);
      expect(p.sensitivities, hasLength(5));
      expect(p.fixedFeatures, hasLength(15));
      expect(p.observedValues, hasLength(5));
      final roundTrip = jsonDecode(jsonEncode(p.toMap())) as Map;
      expect(roundTrip['observed_values']['current_weight_kg'], 3);
      expect(
        roundTrip['fixed_features']['feeding_difficulty'],
        'legacy_encoding_defect',
      );
      expect(roundTrip['experimental_raw_output'], p.rawNeuralOutput);
      expect(roundTrip['experimental_adjusted_output'], p.researchOutput);
      _noClinicalOutput(p);
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
    expect(runner.calls, 12);
  });

  test(
    'legacy and synthetic artifacts never yield patient probabilities',
    () async {
      final runner = _Runner();
      final service = OfflineInferenceService(runner: runner);
      for (final p in (await service.runAllPredictions(_complete)).values) {
        _noClinicalOutput(p);
        if (p.modelName != 'neonatal_sepsis') expect(p.researchOutput, isNull);
      }
      final neonatal = await service.neonatalSepsisRisk(_complete);
      expect(neonatal.execution, ModelExecution.completed);
      expect(neonatal.evidence, ModelEvidence.legacyRealData);
      expect(neonatal.unsupportedFeatures, isEmpty);
      expect(runner.calls, 12);
    },
  );

  test(
    'training policy uses five observations and fifteen exact fixed zeros',
    () async {
      final runner = _Runner();
      final service = OfflineInferenceService(runner: runner);
      final p = await service.neonatalSepsisRisk(_complete);
      expect(p.execution, ModelExecution.completed);
      final input = runner.inputs.first;
      expect(
        input.take(4),
        orderedEquals([
          closeTo(2 / 59, 1e-7),
          closeTo(3 / 7, 1e-7),
          closeTo(.28, 1e-7),
          .5,
        ]),
      );
      expect(input[5], closeTo(2.2 / 4.2, 1e-7));
      for (final i in [4, ...List.generate(14, (i) => i + 6)]) {
        expect(input[i], 0, reason: 'Fixed slot $i');
      }
      expect(p.featuresUsed, [
        'age_days',
        'temperature_celsius',
        'respiratory_rate_per_min',
        'heart_rate_per_min',
        'current_weight_kg',
      ]);
      expect(p.featuresMissing, isEmpty);
      final saved = p.toMap();
      expect(saved['experimental_raw_output'], .8);
      expect(
        saved['experimental_adjusted_output'],
        closeTo(.04588406103741966, 1e-10),
      );
      expect(saved['fixed_features'], hasLength(15));
      expect(saved['observed_values'], containsPair('current_weight_kg', 3.0));
      expect(saved['sensitivities'], hasLength(5));
      expect(runner.inputs, hasLength(6));
      for (var i = 0; i < 5; i++) {
        final slot = [0, 1, 2, 3, 5][i];
        expect(
          runner.inputs[i + 1][slot],
          closeTo([.0296, .6548, .4019, .5754, .5274][i], 1e-7),
        );
        for (var j = 0; j < 20; j++) {
          if (j != slot) expect(runner.inputs[i + 1][j], input[j]);
        }
      }
      final changed = _Runner();
      await OfflineInferenceService(runner: changed).neonatalSepsisRisk(
        const OfflineFeatureBag(
          ageDays: 2,
          temperatureCelsius: 37,
          respiratoryRatePerMin: 48,
          heartRatePerMin: 140,
          currentWeightKg: 3,
          oxygenSaturationPerCent: 75,
          historyOfConvulsions: true,
          feedingDifficulty: true,
          lethargicOrUnconscious: true,
        ),
      );
      expect(changed.inputs.first, input);
      _noClinicalOutput(p);
    },
  );

  for (final mutation in <void Function(Map)>[
    (c) => c['output_scope'] = 'clinical',
    (c) => c['clinical_use_allowed'] = true,
    (c) => c['input_policy_version'] = 'unknown',
    (c) => c['features'][4]['constant_normalized'] = .5,
    (c) => c['features'][5]['input_source'] = 'birth_weight_kg',
    (c) => c['features'][1]['required'] = false,
    (c) => c['sensitivity_baseline'] = {},
  ]) {
    test(
      'malformed experimental policy blocks execution ${mutation.hashCode}',
      () async {
        final p = await OfflineInferenceService(
          bundle: await _bundle(mutate: mutation),
          runner: _Runner(),
        ).neonatalSepsisRisk(_complete);
        expect(p.execution, ModelExecution.invalidMetadata);
        _noClinicalOutput(p);
      },
    );
  }

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
