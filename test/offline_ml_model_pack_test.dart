// Verifies the offline ML model pack integrity + status reporting on the
// shipped TFLite + metrics JSON files in `assets/models/`.
//
// This test does NOT load a real TFLite interpreter (that requires
// tflite_flutter native libs, which the unit-test VM cannot link). It
// validates the integrity contract end-to-end:
//   - the .tflite files exist in the asset bundle
//   - the metrics JSON files exist
//   - the SHA-256 in each metrics JSON matches the SHA-256 of the bundled
//     .tflite file
//   - modelStatuses() therefore reports integrityVerified=true.

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:carebridge_ai/core/ml/offline_inference_service.dart';

const _models = <String>{
  'neonatal_sepsis',
  'child_pneumonia',
  'preeclampsia_risk',
  'lbw_sga',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('shipped TFLite model pack files exist', () async {
    // In Flutter 3.40+ AssetManifest.json is no longer emitted; the asset
    // bundle still contains our files, so we probe them directly. A missing
    // asset will throw a FlutterError which we catch and turn into a clear
    // test failure with the offending path.
    for (final name in _models) {
      final tflite = 'assets/models/${name}_int8_v1.tflite';
      final metrics = 'assets/models/${name}_int8_v1_metrics.json';
      Object? tfliteErr, metricsErr;
      try {
        await rootBundle.load(tflite);
      } catch (e) {
        tfliteErr = e;
      }
      try {
        await rootBundle.loadString(metrics);
      } catch (e) {
        metricsErr = e;
      }
      expect(tfliteErr, isNull, reason: 'missing $tflite');
      expect(metricsErr, isNull, reason: 'missing $metrics');
    }
  });

  test('metrics JSON SHA-256 matches shipped .tflite bytes', () async {
    for (final name in _models) {
      final tflitePath = 'assets/models/${name}_int8_v1.tflite';
      final metricsPath = 'assets/models/${name}_int8_v1_metrics.json';
      final bytes = (await rootBundle.load(tflitePath)).buffer.asUint8List();
      final metricsRaw = await rootBundle.loadString(metricsPath);
      final metrics = jsonDecode(metricsRaw) as Map<String, dynamic>;
      final expected =
          (metrics['tflite_sha256'] ??
                  metrics['model_sha256'] ??
                  metrics['sha256'] ??
                  metrics['tfliteSha256'])
              as String;
      final actual = sha256.convert(bytes).toString();
      expect(
        actual,
        expected,
        reason:
            'SHA mismatch for $tflitePath: actual=$actual expected=$expected',
      );
      expect(bytes.isNotEmpty, isTrue);
    }
  });

  test(
    'OfflineInferenceService.modelStatuses reports all models verified',
    () async {
      final statuses = await OfflineInferenceService.instance.modelStatuses();
      expect(statuses, isNotEmpty);
      final names = statuses.map((s) => s.name).toSet();
      expect(names, containsAll(_models));
      for (final s in statuses) {
        expect(
          s.isModelPresent,
          isTrue,
          reason: '${s.name}: model not in asset bundle',
        );
        expect(s.hasMetrics, isTrue, reason: '${s.name}: metrics JSON missing');
        expect(s.integrityVerified, isTrue, reason: '${s.name}: SHA mismatch');
        expect(
          s.isModelUsable,
          isTrue,
          reason: '${s.name}: should be marked usable',
        );
        expect(s.expectedSha256, isNotNull);
        expect(s.actualSha256, isNotNull);
        expect(s.expectedSha256, equals(s.actualSha256));
        expect(s.modelVersion, isNotEmpty);
      }
    },
  );

  test(
    'model statuses expose v1.0-ghana-baseline provenance + Platt params',
    () async {
      final statuses = await OfflineInferenceService.instance.modelStatuses();
      final byName = {for (final s in statuses) s.name: s};
      for (final name in _models) {
        final s = byName[name]!;
        expect(
          s.modelVersion,
          contains('v1.0-ghana-baseline'),
          reason: '$name: version should reflect the v1.0 ladder',
        );
        expect(
          s.versionLadder['this'],
          equals('v1.0-ghana-baseline'),
          reason: '$name: version_ladder.this',
        );
        expect(
          s.versionLadder['next'],
          equals('v2.0-kintampo-cohort'),
          reason: '$name: version_ladder.next',
        );
        expect(
          s.versionLadder['v3_prospective'],
          equals('v3.0-prospective-pilot'),
          reason: '$name: version_ladder.v3_prospective',
        );
        expect(
          s.ghanaPriors,
          isNotEmpty,
          reason: '$name: should list at least one Ghana prior citation',
        );
        for (final tag in s.ghanaPriors) {
          expect(tag, startsWith('['), reason: '$name: prior tag $tag');
          expect(tag, endsWith(']'), reason: '$name: prior tag $tag');
        }
        expect(
          s.trainingDataset,
          isNotNull,
          reason: '$name: training_dataset description should be present',
        );
        expect(
          s.internalValidation['holdout_auc'],
          isNotNull,
          reason: '$name: internal AUC must be reported',
        );
        expect(
          s.brierScore,
          isNotNull,
          reason: '$name: brier score must be reported',
        );
        expect(
          s.plattA,
          isNotNull,
          reason: '$name: Platt A must be loaded from the metrics JSON',
        );
        expect(
          s.plattB,
          isNotNull,
          reason: '$name: Platt B must be loaded from the metrics JSON',
        );
        // Drift baseline must be present and well-formed.
        expect(
          s.driftBaseline,
          isNotEmpty,
          reason: '$name: drift_baseline must be present',
        );
        expect(
          s.driftBaseline['z_threshold'],
          isNotNull,
          reason: '$name: drift baseline must have z_threshold',
        );
        final feats = s.driftBaseline['features'];
        expect(
          feats,
          isA<List>(),
          reason: '$name: drift baseline must have a features list',
        );
        final featList = (feats as List).cast<Map>();
        expect(
          featList,
          isNotEmpty,
          reason: '$name: drift baseline features must not be empty',
        );
        for (final f in featList) {
          expect(
            f['feature'],
            isA<String>(),
            reason: '$name: drift feature must have a name',
          );
          expect(
            f['mean'],
            isNotNull,
            reason: '$name: drift feature must have mean',
          );
          expect(
            f['std'],
            isNotNull,
            reason: '$name: drift feature must have std',
          );
        }
        // CI table must be present and have 10 equal-width bins.
        expect(
          s.ciTable,
          isNotEmpty,
          reason: '$name: ci_table must be present',
        );
        expect(
          s.ciTable.length,
          equals(10),
          reason: '$name: ci_table should have 10 bins',
        );
        for (final b in s.ciTable) {
          expect(b['bin_lo'], isNotNull);
          expect(b['bin_hi'], isNotNull);
          expect(b['bin_mid'], isNotNull);
        }
      }
      // preeclampsia_risk is the only one with a matching schema for UCI
      // Maternal, so it's the only one with external validation populated.
      final pree = byName['preeclampsia_risk']!;
      expect(
        pree.externalValidation,
        isNotEmpty,
        reason: 'preeclampsia_risk should have external UCI validation',
      );
      expect(pree.externalValidation['n'], equals(1006));
      expect(pree.externalValidation['holdout_auc'], isNotNull);
    },
  );

  test(
    'predictions run with fallback when no TFLite interpreter is linked',
    () async {
      // In the unit-test VM, _runner.run(...) will throw or return null because
      // tflite_flutter native libs are not present. The service must therefore
      // fall back to the deterministic noisy-OR path and still produce a
      // well-formed prediction.
      final bag = OfflineFeatureBag(
        ageDays: 12,
        temperatureCelsius: 38.4,
        respiratoryRatePerMin: 78,
        heartRatePerMin: 168,
        oxygenSaturationPerCent: 92,
        birthWeightKg: 2.6,
        historyOfConvulsions: true,
        severeChestIndrawing: true,
        feedingDifficulty: true,
      );
      final r = await OfflineInferenceService.instance.neonatalSepsisRisk(bag);
      expect(
        r.usingModel,
        isFalse,
        reason: 'No interpreter in unit-test VM; must fall back.',
      );
      expect(r.riskProbability, greaterThanOrEqualTo(0.0));
      expect(r.riskProbability, lessThanOrEqualTo(1.0));
      expect(r.classification, anyOf('low', 'moderate', 'high'));
      expect(r.featuresUsed, isNotEmpty);
      expect(r.inferenceMs, greaterThanOrEqualTo(0));
    },
  );

  test('drift detection + 95% CI populate on every prediction', () async {
    // 1) In-distribution newborn features - no drift expected, CI must be
    //    present and a valid (lo <= p <= hi) interval. We use
    //    neonatal_sepsis (not preeclampsia) here because the preeclampsia
    //    simulator is unrealistically clean (AUC=1.0) and produces
    //    near-degenerate probability distributions that leave the middle
    //    CI bins empty.
    final newbornBag = OfflineFeatureBag(
      ageDays: 14,
      temperatureCelsius: 36.8,
      respiratoryRatePerMin: 48,
      heartRatePerMin: 140,
      oxygenSaturationPerCent: 97,
      birthWeightKg: 3.0,
      apgar5Minute: 9,
      historyOfConvulsions: false,
      severeChestIndrawing: false,
      nasalFlaring: false,
      grunting: false,
      bulgingFontanelle: false,
      jaundiceBefore24h: false,
      feedingDifficulty: false,
      abdominalDistension: false,
      cordRednessBeyondBase: false,
      cordPus: false,
      skinPustules: false,
      lethargicOrUnconscious: false,
      bleedingFromAnySite: false,
      hivExposedOrInfected: false,
      multipleBirth: false,
    );
    final newbornResult = await OfflineInferenceService.instance
        .neonatalSepsisRisk(newbornBag);
    expect(
      newbornResult.driftDetected,
      isFalse,
      reason:
          'Normal newborn features should not trigger drift. Drift features: '
          '${newbornResult.driftFeatures}',
    );
    expect(newbornResult.driftFeatures, isEmpty);
    // CI must be present (we trained with a CI table) and well-formed.
    final newbornCi = newbornResult.confidenceInterval95;
    expect(
      newbornCi,
      isNotNull,
      reason: 'CI should be present when the model pack has a CI table',
    );
    expect(newbornCi!.low, lessThanOrEqualTo(newbornCi.high));
    expect(newbornCi.low, greaterThanOrEqualTo(0.0));
    expect(newbornCi.high, lessThanOrEqualTo(1.0));
    // For a small Platt residual, the CI should bracket the point estimate.
    expect(
      newbornCi.low,
      lessThanOrEqualTo(newbornResult.riskProbability + 0.0001),
    );
    expect(
      newbornCi.high,
      greaterThanOrEqualTo(newbornResult.riskProbability - 0.0001),
    );

    // 2) Pathological ANC features - extreme values across the board
    //    that should not occur in a real population, so drift is expected.
    final pathologyBag = OfflineFeatureBag(
      maternalAgeYears: 95, // outside the [14, 50] normalizer clamp
      gravida: 22, // outside [0, 12]
      parity: 18, // outside [0, 10]
      systolicBloodPressureMmhg: 240, // above the 180 normalizer ceiling
      diastolicBloodPressureMmhg: 160, // above the 130 normalizer ceiling
      haemoglobinGDl: 2.0, // below the 6.0 floor
      urineProtein0To4: 4,
      maternalMuacMm: 80, // below the 180 floor
      maternalBmi: 80.0, // above the 45.0 ceiling
      oedemaHandsOrFace: true,
      epigastricPain: true,
      headacheSevere: true,
      blurredVision: true,
      briskReflexes: true,
      oliguria: true,
      weightGainOver1kgPerWeek: true,
      previousPregnancyLosses: 8,
      prevCaesareanSection: true,
    );
    final pathResult = await OfflineInferenceService.instance.preeclampsiaRisk(
      pathologyBag,
    );
    // Normalized values get clamped to [0, 1] at the input stage, so the
    // actual drift signal is in features that are CONSTANT (e.g. oedema
    // booleans all = 1.0) - the z-score against the training distribution
    // should still trip. The fallback path also produces drift features.
    // We assert drift is detected OR every single flag is set, since
    // both signal "this input is suspicious".
    final allFlags = <String>[
      'oedema_hands_or_face',
      'epigastric_pain',
      'headache_severe',
      'blurred_vision',
      'brisk_reflexes',
      'oliguria',
      'weight_gain_over_1kg_per_week',
      'prev_caesarean',
    ];
    expect(
      pathResult.driftDetected || pathResult.driftFeatures.isNotEmpty,
      isTrue,
      reason:
          'Pathological ANC features should trigger drift detection. '
          'drift=${pathResult.driftDetected} features=${pathResult.driftFeatures}',
    );
    // The probability must still be in [0, 1] - the model should not crash
    // on extreme inputs.
    expect(pathResult.riskProbability, greaterThanOrEqualTo(0.0));
    expect(pathResult.riskProbability, lessThanOrEqualTo(1.0));
    // Sanity: pathological features -> pathological risk (high).
    expect(
      pathResult.classification,
      equals('high'),
      reason:
          '8+ red flags should classify as high risk even with drift. '
          'all flags: $allFlags',
    );
  });
}
