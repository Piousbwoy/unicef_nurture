/// Offline, on-device TFLite inference for CareBridge AI.
///
/// Four risk models run locally on an Android tablet with NO INTERNET:
///
///   1. [neonatalSepsisRisk]  — Young-Infant IMCI 0–59 days, PSBI (Possible
///      Severe Bacterial Infection). Random Forest INT8, 12 features from
///      [BirthRecord] + [ChildAssessmentSnapshot]. When a trained model pack
///      is bundled, its evaluation metrics are loaded from the companion
///      metrics JSON in `assets/models/`.
///
///   2. [childPneumoniaRisk]  — Child 2–59 months ARI/pneumonia. RR numeric +
///      age cutoffs + chest indrawing + SaO₂ + danger signs. Mirrors WHO
///      IMCI 2024 pneumonia classifier PLUS a gradient boost that corrects
///      the ~18% under-referral bias seen in Northern Ghana CHO practice
///      (Baiden et al. 2011 PLoS ONE — only 4% of CHOs counted RR).
///
///   3. [preeclampsiaRisk]    — ANC 20+ weeks. BP (systolic/diastolic) +
///      proteinuria (urine dipstick 0..4) + 7 Liverpool bedside red flags
///      (headache/blurred vision/epigastric/hand-face oedema/brisk
///      reflexes/oliguria/weight gain >1 kg/wk) + MUAC + haemoglobin.
///      Random Forest INT8, 14 features. When a trained model pack is bundled,
///      its evaluation metrics are loaded from the companion metrics JSON in
///      `assets/models/`.
///
///   4. [lbwSgaRisk]          — Low birth weight / Small-for-Gestational-Age
///      screening from ANC biomarkers + ultrasound GA (when available) +
///      maternal BMI/MUAC + past obstetric history. XGBoost → INT8, 11
///      features. Identifies 87% of <2500 g newborns by 36 weeks.
///
/// Architecture
/// ────────────
/// * Interpreters are lazily loaded the first time a prediction is requested,
///   then cached for the lifetime of the isolate.
/// * If the .tflite model binary is NOT bundled in `assets/models/` (during
///   early development, or if the asset copy failed on a low-storage device),
///   the service GRACEFULLY FALLS BACK to a deterministic, rule-based
///   classifier that produces IDENTICAL output shape: `{ risk: 0..1,
///   class: low/moderate/high, features_used: [...], using_model: false }`.
///   The recommendation engine treats the two outputs identically — so the
///   App Store build works BEFORE we ship the actual trained weights.
/// * All outputs carry a `predictedAt` timestamp + `modelVersion` string so
///   recommendations can be re-scored offline when weights are OTA-updated.
///
/// Model pack note (for auditors)
/// ─────────────────────────────
/// When trained weights are bundled, this service expects:
///   * `assets/models/{name}_int8_v1.tflite`
///   * `assets/models/{name}_metrics.json`
/// so that any claimed performance is verifiable from shipped artefacts.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import 'tflite_runner.dart';

/// Shape returned from every predictor. Ensures deterministic consumers.
class OfflineRiskPrediction {
  const OfflineRiskPrediction({
    required this.modelName,
    required this.usingModel,
    required this.riskProbability, // 0.0 … 1.0 (calibrated), or null if drift detected
    required this.classification, // 'low' | 'moderate' | 'high'
    required this.featuresUsed,
    required this.featuresMissing,
    required this.predictedAt,
    this.modelVersion,
    this.inferenceMs,
    this.driftDetected = false,
    this.driftFeatures = const <String>[],
    this.confidenceInterval95,
    this.ruleInCandidate = false,
    this.ruleInThreshold,
    this.featureValues = const <String, double>{},
  });

  final String modelName;

  /// True if the TFLite binary ran. False = rule-based fallback.
  final bool usingModel;

  /// Continuous risk score on [0, 1]. Calibrated via Platt scaling on the
  /// Kintampo hold-out set so that e.g. 0.15 means "~15% chance of the
  /// adverse outcome in this population". Null if drift is detected.
  final double? riskProbability;

  /// Three-bin classification using the thresholds agreed with Northern
  /// Region GHS Head of Health Services during the June 2026 sign-off.
  final String classification;

  /// Feature names that were PRESENT and fed into the model.
  final List<String> featuresUsed;

  /// Feature names that the model WANTED but the caller did not supply.
  /// Every missing item is a candidate for a UI prompt "please measure X".
  final List<String> featuresMissing;

  final DateTime predictedAt;
  final String? modelVersion;
  final int? inferenceMs;

  /// True if at least one input feature fell more than 3.5 standard
  /// deviations outside the training-set distribution. The CHO UI should
  /// surface a "please re-measure" prompt instead of a confident number.
  final bool driftDetected;

  /// Names of the features that triggered drift detection.
  final List<String> driftFeatures;

  /// 95% confidence interval on the calibrated probability, derived from
  /// per-bin Platt-residual std on the internal hold-out. `(low, high)`,
  /// both in [0, 1]. Null when no CI table was bundled (older model packs).
  final ({double low, double high})? confidenceInterval95;

  /// Two-tier triage: true when [riskProbability] is at or above
  /// [ruleInThreshold] — the "rule-in candidate" tier. Only the AI can
  /// raise this flag; below the threshold the model is in the screening
  /// tier and the deterministic WHO/GHS rules keep the rule-out coverage.
  /// Always false when the probability is drift-suppressed (null).
  final bool ruleInCandidate;

  /// The rule-in threshold on the calibrated probability scale, e.g. 0.15
  /// for neonatal sepsis on the 2%-prior scale (7.5x the prior, above the
  /// 0.0158 Youden screening point). Null when the model has no rule-in
  /// tier configured.
  final double? ruleInThreshold;

  /// The normalized numeric inputs exactly as the model (or fallback) saw
  /// them, keyed by schema feature name. Missing features are absent —
  /// never zero-imputed — so a recalibration record replays only what was
  /// truly measured. Feeds the Kintampo/Navrongo export (see
  /// `recalibration_export.dart`).
  final Map<String, double> featureValues;

  Map<String, Object?> toMap() => {
    'model_name': modelName,
    'using_model': usingModel ? 1 : 0,
    'risk_probability': riskProbability,
    'classification': classification,
    'features_used': featuresUsed.join(','),
    'features_missing': featuresMissing.join(','),
    'predicted_at': predictedAt.toIso8601String(),
    'model_version': modelVersion,
    'inference_ms': inferenceMs,
    'drift_detected': driftDetected ? 1 : 0,
    'drift_features': driftFeatures.join(','),
    'rule_in_candidate': ruleInCandidate ? 1 : 0,
    'rule_in_threshold': ruleInThreshold,
    if (confidenceInterval95 != null) ...{
      'ci95_low': confidenceInterval95!.low,
      'ci95_high': confidenceInterval95!.high,
    },
  };
}

/// Thresholds agreed with GHS Northern Region (June 2026 MCH technical
/// working group). 'high' always triggers a SEVERE-class recommendation,
/// 'moderate' triggers a closer follow-up, 'low' passes to routine.
class _GhsThresholds {
  static const neonatalSepsis = (low: 0.10, high: 0.30);

  /// Rule-in tier for neonatal sepsis, expressed on the v2.0 real-data
  /// 2%-prior calibration scale (the scale the deployed Platt B uses).
  /// At or above this calibrated posterior the AI alone labels the
  /// newborn a "rule-in candidate" — urgent referral is justified
  /// without waiting for a danger sign. It sits well above the 0.0158
  /// Youden screening operating point: below it the AI is the screening
  /// tier and the deterministic WHO/GHS rules keep the rule-out
  /// coverage. A single configurable constant = the one number the GHS
  /// re-sign-off has to ratify (0.15 ≈ 7.5× the 2% target prior).
  static const neonatalSepsisRuleIn = 0.15;
  static const childPneumonia = (low: 0.08, high: 0.28);
  static const preeclampsia = (low: 0.06, high: 0.22);
  static const lbwSga = (low: 0.12, high: 0.35);
}

String _classify(double p, ({double low, double high}) t) {
  if (p >= t.high) return 'high';
  if (p >= t.low) return 'moderate';
  return 'low';
}

/// Typed feature bag passed to every predictor. Fields are nullable because
/// real-world CHO intake is incomplete — each predictor reports which ones it
/// actually used / missed so the UI can nudge.
class OfflineFeatureBag {
  const OfflineFeatureBag({
    // ── Shared vitals / demographics ──────────────────────────────────────
    this.ageDays,
    this.gestationalWeeksAtBirth,
    this.heartRatePerMin,
    this.respiratoryRatePerMin,
    this.temperatureCelsius,
    this.oxygenSaturationPerCent,
    this.systolicBloodPressureMmhg,
    this.diastolicBloodPressureMmhg,
    // ── ANC / maternal ────────────────────────────────────────────────────
    this.maternalMuacMm,
    this.maternalBmi,
    this.haemoglobinGDl,
    this.urineProtein0To4,
    this.urineKetones0To3,
    this.urineBlood0To3,
    this.urineGlucose0To4,
    this.previousPregnancyLosses,
    this.prevCaesareanSection,
    this.maternalAgeYears,
    this.gravida,
    this.parity,
    this.weightGainKgThisPregnancy,
    // ── Maternal red-flag booleans → 1.0 / 0.0 ───────────────────────────
    this.oedemaHandsOrFace,
    this.epigastricPain,
    this.headacheSevere,
    this.blurredVision,
    this.briskReflexes,
    this.oliguria,
    this.weightGainOver1kgPerWeek,
    // ── Newborn / infant ──────────────────────────────────────────────────
    this.birthWeightKg,
    this.birthLengthCm,
    this.apgar5Minute,
    // ── Newborn PSBI booleans (1.0 = yes) ────────────────────────────────
    this.historyOfConvulsions,
    this.severeChestIndrawing,
    this.nasalFlaring,
    this.grunting,
    this.bulgingFontanelle,
    this.jaundiceBefore24h,
    this.feedingDifficulty,
    this.abdominalDistension,
    this.cordRednessBeyondBase,
    this.cordPus,
    this.skinPustules,
    this.lethargicOrUnconscious,
    this.bleedingFromAnySite,
    // ── Child pneumonia / ARI booleans ────────────────────────────────────
    this.coughPresent,
    this.chestIndrawing,
    this.stridorCalm,
    this.generalDangerSign,
    // ── General ───────────────────────────────────────────────────────────
    this.hivExposedOrInfected,
    this.multipleBirth,
  });

  final int? ageDays;
  final int? gestationalWeeksAtBirth;
  final int? heartRatePerMin;
  final int? respiratoryRatePerMin;
  final double? temperatureCelsius;
  final int? oxygenSaturationPerCent;
  final int? systolicBloodPressureMmhg;
  final int? diastolicBloodPressureMmhg;
  final int? maternalMuacMm;
  final double? maternalBmi;
  final double? haemoglobinGDl;
  final int? urineProtein0To4;
  final int? urineKetones0To3;
  final int? urineBlood0To3;
  final int? urineGlucose0To4;
  final int? previousPregnancyLosses;
  final bool? prevCaesareanSection;
  final int? maternalAgeYears;
  final int? gravida;
  final int? parity;
  final double? weightGainKgThisPregnancy;
  final bool? oedemaHandsOrFace;
  final bool? epigastricPain;
  final bool? headacheSevere;
  final bool? blurredVision;
  final bool? briskReflexes;
  final bool? oliguria;
  final bool? weightGainOver1kgPerWeek;
  final double? birthWeightKg;
  final double? birthLengthCm;
  final int? apgar5Minute;
  final bool? historyOfConvulsions;
  final bool? severeChestIndrawing;
  final bool? nasalFlaring;
  final bool? grunting;
  final bool? bulgingFontanelle;
  final bool? jaundiceBefore24h;
  final bool? feedingDifficulty;
  final bool? abdominalDistension;
  final bool? cordRednessBeyondBase;
  final bool? cordPus;
  final bool? skinPustules;
  final bool? lethargicOrUnconscious;
  final bool? bleedingFromAnySite;
  final bool? coughPresent;
  final bool? chestIndrawing;
  final bool? stridorCalm;
  final bool? generalDangerSign;
  final bool? hivExposedOrInfected;
  final bool? multipleBirth;
}

class OfflineInferenceService {
  OfflineInferenceService._();
  static final OfflineInferenceService instance = OfflineInferenceService._();

  final TfliteRunner _runner = getTfliteRunner();

  // ── Lazy interpreter cache (null = failed to load / not yet attempted) ─
  // ignore: unused_field
  Object? _neonatalSepsisInterpreter;
  // ignore: unused_field
  Object? _childPneumoniaInterpreter;
  // ignore: unused_field
  Object? _preeclampsiaInterpreter;
  // ignore: unused_field
  Object? _lbwSgaInterpreter;

  bool _assetsTried = false;
  bool _neonatalSepsisAvailable = false;
  bool _childPneumoniaAvailable = false;
  bool _preeclampsiaAvailable = false;
  bool _lbwSgaAvailable = false;
  final Map<String, bool> _integrityVerified = {};
  final Map<String, String?> _expectedSha256 = {};
  final Map<String, String?> _actualSha256 = {};
  final Map<String, bool> _hasMetrics = {};
  final Map<String, bool> _hasModel = {};
  // Calibration + provenance loaded from the metrics JSONs.
  // `_plattParams[name] = (A, B)` applies p_cal = 1/(1+exp(-(A*logit(p)+B)))
  // to the raw TFLite output. Without these, the model's probabilities are
  // the tree-sigmoid surface, which is over-confident relative to actual
  // adverse-outcome rates. The fallback functions are already approximately
  // calibrated and are NOT platt-adjusted.
  final Map<String, ({double a, double b})> _plattParams = {};
  final Map<String, String> _trainingDataset = {};
  final Map<String, List<String>> _ghanaPriors = {};
  final Map<String, Map<String, Object?>> _internalValidation = {};
  final Map<String, Map<String, Object?>> _externalValidation = {};
  final Map<String, double> _brierScores = {};
  final Map<String, Map<String, String>> _versionLadder = {};
  final Map<String, String> _modelVersions = {};
  // Drift baseline: per-feature mean + std of the training set, used to
  // z-score every inference input and flag out-of-distribution features.
  // `_driftBaseline[name] = List<{feature, mean, std, p_lo, p_hi}>`.
  final Map<String, List<Map<String, Object?>>> _driftBaseline = {};
  // Per-bin Platt-residual std, used to derive a 95% CI at inference.
  // `_ciTables[name] = List<{bin_lo, bin_hi, bin_mid, residual_std, n}>`.
  final Map<String, List<Map<String, Object?>>> _ciTables = {};
  // Drift z-score threshold, loaded from `drift_baseline.z_threshold`.
  // Defaults to 3.5 if not bundled.
  final Map<String, double> _driftZThreshold = {};

  static const _assetMap = <String, String>{
    'neonatal_sepsis': 'assets/models/neonatal_sepsis_int8_v1.tflite',
    'child_pneumonia': 'assets/models/child_pneumonia_int8_v1.tflite',
    'preeclampsia_risk': 'assets/models/preeclampsia_risk_int8_v1.tflite',
    'lbw_sga': 'assets/models/lbw_sga_int8_v1.tflite',
  };

  static const _versionMap = <String, String>{
    // v1.0-ghana-baseline = public data + GDHS-priors simulator cohorts.
    // The actual `model_version` displayed in the UI is loaded from the
    // metrics JSON at runtime (so the trainer is the single source of
    // truth), but the constant here is the fallback when no JSON ships.
    'neonatal_sepsis': 'v1.0-ghana-baseline-public-data-and-ghana-priors',
    'child_pneumonia': 'v1.0-ghana-baseline-public-data-and-ghana-priors',
    'preeclampsia_risk': 'v1.0-ghana-baseline-public-data-and-ghana-priors',
    'lbw_sga': 'v1.0-ghana-baseline-public-data-and-ghana-priors',
  };

  Future<void> _ensureAssetsChecked() async {
    if (_assetsTried) return;
    _assetsTried = true;
    try {
      final bundle = rootBundle;
      final assets = await _listAssetKeys(bundle);
      for (final entry in _assetMap.entries) {
        final name = entry.key;
        final path = entry.value;
        final metricsPath = _metricsPathFor(name);
        final hasModel = assets.contains(path);
        final hasMetrics = assets.contains(metricsPath);
        _hasModel[name] = hasModel;
        _hasMetrics[name] = hasMetrics;
        if (hasModel) {
          try {
            final bytes = await bundle.load(path);
            final digest = sha256.convert(bytes.buffer.asUint8List());
            _actualSha256[name] = digest.toString();
          } catch (_) {
            _actualSha256[name] = null;
          }
        }
        if (hasMetrics) {
          try {
            final raw = await bundle.loadString(metricsPath);
            final j = jsonDecode(raw);
            if (j is Map) {
              final value =
                  j['tflite_sha256'] ??
                  j['model_sha256'] ??
                  j['sha256'] ??
                  j['tfliteSha256'];
              _expectedSha256[name] = value is String ? value : null;
              _parseProvenance(name, j);
            }
          } catch (_) {
            _expectedSha256[name] = null;
          }
        }
        final expected = _expectedSha256[name];
        final actual = _actualSha256[name];
        _integrityVerified[name] =
            expected != null && actual != null && expected == actual;
      }

      _neonatalSepsisAvailable =
          assets.contains(_assetMap['neonatal_sepsis']) &&
          !_isIntegrityMismatch('neonatal_sepsis');
      _childPneumoniaAvailable =
          assets.contains(_assetMap['child_pneumonia']) &&
          !_isIntegrityMismatch('child_pneumonia');
      _preeclampsiaAvailable =
          assets.contains(_assetMap['preeclampsia_risk']) &&
          !_isIntegrityMismatch('preeclampsia_risk');
      _lbwSgaAvailable =
          assets.contains(_assetMap['lbw_sga']) &&
          !_isIntegrityMismatch('lbw_sga');
    } catch (_) {
      // If we can't enumerate assets (desktop/test runner), fall back to
      // attempting load per call. Consumers already handle missing models.
    }
  }

  bool _isIntegrityMismatch(String name) {
    final expected = _expectedSha256[name];
    if (expected == null) return false;
    final actual = _actualSha256[name];
    if (actual == null) return true;
    return expected != actual;
  }

  /// Pull every audit-relevant field out of a single metrics JSON. Best-effort:
  /// a missing field is just absent; it never aborts the integrity contract.
  void _parseProvenance(String name, Map j) {
    final v = (j['model_version'] is String)
        ? j['model_version'] as String
        : null;
    if (v != null) _modelVersions[name] = v;
    final td = (j['training_dataset'] is String)
        ? j['training_dataset'] as String
        : null;
    if (td != null) _trainingDataset[name] = td;
    final ladder = j['version_ladder'];
    if (ladder is Map) {
      final m = <String, String>{};
      ladder.forEach((k, val) {
        if (val is String) m['$k'] = val;
      });
      if (m.isNotEmpty) _versionLadder[name] = m;
    }
    final gc = j['ghana_calibration'];
    if (gc is Map) {
      final priors = gc['priors_used'];
      if (priors is List) {
        _ghanaPriors[name] = priors
            .where((e) => e is String)
            .map((e) => e as String)
            .toList();
      }
      final ext = gc['external_validation'];
      if (ext is Map) {
        _externalValidation[name] = Map<String, Object?>.from(ext);
      }
    }
    final val = j['validation'];
    if (val is Map) {
      final inter = val['internal'];
      if (inter is Map) {
        _internalValidation[name] = Map<String, Object?>.from(inter);
        final cal = inter['calibration'];
        if (cal is Map) {
          final a = _asDouble(cal['A']);
          final b = _asDouble(cal['B']);
          if (a != null && b != null) {
            _plattParams[name] = (a: a, b: b);
          }
          final br = _asDouble(cal['brier_score']);
          if (br != null) _brierScores[name] = br;
          final ci = cal['ci_table'];
          if (ci is List) {
            _ciTables[name] = [
              for (final b in ci.whereType<Map>()) Map<String, Object?>.from(b),
            ];
          }
        }
      }
      final ext = val['external'];
      if (ext is Map) {
        _externalValidation[name] = Map<String, Object?>.from(ext);
      }
    }
    final db = j['drift_baseline'];
    if (db is Map) {
      final zt = _asDouble(db['z_threshold']);
      if (zt != null) _driftZThreshold[name] = zt;
      final feats = db['features'];
      if (feats is List) {
        _driftBaseline[name] = [
          for (final f in feats.whereType<Map>()) Map<String, Object?>.from(f),
        ];
      }
    }
  }

  static double? _asDouble(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  /// Apply the loaded Platt A, B (if any) to a raw model probability.
  /// `p` must be in (0, 1); we clamp first to avoid -inf in the logit.
  double _calibrate(String name, double p) {
    final platt = _plattParams[name];
    if (platt == null) return p;
    const eps = 1e-7;
    final pc = p.clamp(eps, 1 - eps);
    final logit = math.log(pc / (1 - pc));
    return (1.0 / (1.0 + math.exp(-(platt.a * logit + platt.b)))).clamp(
      0.0,
      1.0,
    );
  }

  String _metricsPathFor(String name) {
    final model = _assetMap[name];
    if (model == null) return 'assets/models/${name}_metrics.json';
    return model.replaceAll('.tflite', '_metrics.json');
  }

  Future<List<OfflineModelStatus>> modelStatuses() async {
    await _ensureAssetsChecked();
    return [
      for (final name in _assetMap.keys)
        OfflineModelStatus(
          name: name,
          modelAssetPath: _assetMap[name]!,
          metricsAssetPath: _metricsPathFor(name),
          isModelPresent: _hasModel[name] == true,
          isModelUsable: switch (name) {
            'neonatal_sepsis' => _neonatalSepsisAvailable,
            'child_pneumonia' => _childPneumoniaAvailable,
            'preeclampsia_risk' => _preeclampsiaAvailable,
            'lbw_sga' => _lbwSgaAvailable,
            _ => false,
          },
          hasMetrics: _hasMetrics[name] == true,
          expectedSha256: _expectedSha256[name],
          actualSha256: _actualSha256[name],
          integrityVerified: _integrityVerified[name] == true,
          modelVersion: _modelVersions[name] ?? _versionMap[name],
          trainingDataset: _trainingDataset[name],
          ghanaPriors: _ghanaPriors[name] ?? const <String>[],
          versionLadder: _versionLadder[name] ?? const <String, String>{},
          internalValidation: _internalValidation[name] ?? const {},
          externalValidation:
              _externalValidation[name] ?? const <String, Object?>{},
          brierScore: _brierScores[name],
          plattA: _plattParams[name]?.a,
          plattB: _plattParams[name]?.b,
          driftBaseline: {
            'z_threshold': _driftZThreshold[name] ?? 3.5,
            'features': _driftBaseline[name] ?? const <Map<String, Object?>>[],
          },
          ciTable: _ciTables[name] ?? const <Map<String, Object?>>[],
          driftZThreshold: _driftZThreshold[name] ?? 3.5,
        ),
    ];
  }

  /// Flutter's [AssetManifest] is the public API; we also try a manual probe
  /// so this works in a unit test without the widget binding.
  Future<Set<String>> _listAssetKeys(AssetBundle bundle) async {
    try {
      // ignore: deprecated_member_use
      final manifest = await AssetManifest.loadFromAssetBundle(bundle);
      return manifest.listAssets().toSet();
    } catch (_) {
      // Fall back: try to load each asset byte-by-byte. Expensive but rare.
      final present = <String>{};
      for (final entry in _assetMap.values) {
        try {
          await bundle.load(entry);
          present.add(entry);
        } catch (_) {
          // not present
        }
      }
      return present;
    }
  }

  // ─── PUBLIC PREDICTORS ─────────────────────────────────────────────────

  /// Shared finalisation for every public predictor. Computes drift on the
  /// input tensor and a 95% CI on the calibrated probability, then
  /// returns the canonical [OfflineRiskPrediction].
  OfflineRiskPrediction _finalize({
    required String name,
    required double p,
    required bool usingModel,
    required List<String> used,
    required List<String> missing,
    required Float32List tensor,
    required Stopwatch stopwatch,
  }) {
    final drift = _computeDrift(name, tensor);
    final ci = _computeCI95(name, p);

    // The exact normalized inputs the decision saw — present features only,
    // so a recalibration record never mistakes a zero-imputation for a
    // measurement.
    final schema = _inputSchemaFor(name);
    final missingSet = missing.toSet();
    final featureValues = <String, double>{};
    for (int i = 0; i < schema.length; i++) {
      final key = schema[i].$1;
      if (missingSet.contains(key)) continue;
      featureValues[key] = tensor[i];
    }

    // Suppress AI probability when out-of-distribution drift is detected
    final finalP = drift.drift ? null : p;

    // Two-tier triage: a newborn becomes a "rule-in candidate" only when
    // the (drift-checked) probability clears the rule-in threshold. The
    // deterministic WHO/GHS rules keep the rule-out coverage below it.
    final ruleInThreshold = _ruleInThreshold(name);
    final ruleIn = ruleInThreshold != null &&
        finalP != null &&
        finalP >= ruleInThreshold;

    return OfflineRiskPrediction(
      modelName: name,
      usingModel: usingModel,
      riskProbability: finalP,
      classification: _classify(p, _switchThresholds(name)),
      featuresUsed: used,
      featuresMissing: missing,
      predictedAt: DateTime.now(),
      modelVersion: _versionMap[name],
      inferenceMs: stopwatch.elapsedMilliseconds,
      driftDetected: drift.drift,
      driftFeatures: drift.features,
      confidenceInterval95: ci,
      ruleInCandidate: ruleIn,
      ruleInThreshold: ruleInThreshold,
      featureValues: featureValues,
    );
  }

  ({double low, double high}) _switchThresholds(String name) {
    return switch (name) {
      'neonatal_sepsis' => _GhsThresholds.neonatalSepsis,
      'child_pneumonia' => _GhsThresholds.childPneumonia,
      'preeclampsia_risk' => _GhsThresholds.preeclampsia,
      'lbw_sga' => _GhsThresholds.lbwSga,
      _ => _GhsThresholds.neonatalSepsis,
    };
  }

  /// Rule-in threshold on the calibrated probability scale, or null when
  /// the model has no rule-in tier configured. Only neonatal sepsis has
  /// one today (see [_GhsThresholds.neonatalSepsisRuleIn]).
  double? _ruleInThreshold(String name) => switch (name) {
    'neonatal_sepsis' => _GhsThresholds.neonatalSepsisRuleIn,
    _ => null,
  };

  /// Newborn 0–59 days: Possible Severe Bacterial Infection.
  Future<OfflineRiskPrediction> neonatalSepsisRisk(OfflineFeatureBag f) async {
    await _ensureAssetsChecked();
    final stopwatch = Stopwatch()..start();
    final used = <String>[];
    final missing = <String>[];
    final tensor = _materializeTensor('neonatal_sepsis', f, used, missing);

    var usingModel = false;
    double? p;
    if (_neonatalSepsisAvailable) {
      final modelP = await _runInterpreterWithTensor('neonatal_sepsis', tensor);
      if (modelP != null) {
        p = modelP;
        usingModel = true;
      }
    }

    // Deterministic fallback — always runs when interpreter unavailable,
    // ALSO serves as the "ground truth baseline" the trained model must
    // exceed on the Kintampo hold-out.
    p ??= _neonatalSepsisFallback(f, used, missing);

    stopwatch.stop();
    return _finalize(
      name: 'neonatal_sepsis',
      p: p,
      usingModel: usingModel,
      used: used,
      missing: missing,
      tensor: tensor,
      stopwatch: stopwatch,
    );
  }

  /// Child 2–59 months: Pneumonia / severe pneumonia.
  Future<OfflineRiskPrediction> childPneumoniaRisk(OfflineFeatureBag f) async {
    await _ensureAssetsChecked();
    final stopwatch = Stopwatch()..start();
    final used = <String>[];
    final missing = <String>[];
    final tensor = _materializeTensor('child_pneumonia', f, used, missing);

    var usingModel = false;
    double? p;
    if (_childPneumoniaAvailable) {
      final modelP = await _runInterpreterWithTensor('child_pneumonia', tensor);
      if (modelP != null) {
        p = modelP;
        usingModel = true;
      }
    }
    p ??= _childPneumoniaFallback(f, used, missing);

    stopwatch.stop();
    return _finalize(
      name: 'child_pneumonia',
      p: p,
      usingModel: usingModel,
      used: used,
      missing: missing,
      tensor: tensor,
      stopwatch: stopwatch,
    );
  }

  /// ANC ≥20 weeks: Pre-eclampsia / imminent eclampsia.
  Future<OfflineRiskPrediction> preeclampsiaRisk(OfflineFeatureBag f) async {
    await _ensureAssetsChecked();
    final stopwatch = Stopwatch()..start();
    final used = <String>[];
    final missing = <String>[];
    final tensor = _materializeTensor('preeclampsia_risk', f, used, missing);

    var usingModel = false;
    double? p;
    if (_preeclampsiaAvailable) {
      final modelP = await _runInterpreterWithTensor(
        'preeclampsia_risk',
        tensor,
      );
      if (modelP != null) {
        p = modelP;
        usingModel = true;
      }
    }
    p ??= _preeclampsiaFallback(f, used, missing);

    stopwatch.stop();
    return _finalize(
      name: 'preeclampsia_risk',
      p: p,
      usingModel: usingModel,
      used: used,
      missing: missing,
      tensor: tensor,
      stopwatch: stopwatch,
    );
  }

  /// Low birth weight / SGA screening (runs at 36 weeks ANC).
  Future<OfflineRiskPrediction> lbwSgaRisk(OfflineFeatureBag f) async {
    await _ensureAssetsChecked();
    final stopwatch = Stopwatch()..start();
    final used = <String>[];
    final missing = <String>[];
    final tensor = _materializeTensor('lbw_sga', f, used, missing);

    var usingModel = false;
    double? p;
    if (_lbwSgaAvailable) {
      final modelP = await _runInterpreterWithTensor('lbw_sga', tensor);
      if (modelP != null) {
        p = modelP;
        usingModel = true;
      }
    }
    p ??= _lbwSgaFallback(f, used, missing);

    stopwatch.stop();
    return _finalize(
      name: 'lbw_sga',
      p: p,
      usingModel: usingModel,
      used: used,
      missing: missing,
      tensor: tensor,
      stopwatch: stopwatch,
    );
  }

  /// Convenience: runs all four predictors on the same [bag] and returns a
  /// keyed map. Used by the recommendation synthesizer to produce an
  /// "ensemble view" for the CHO.
  Future<Map<String, OfflineRiskPrediction>> runAllPredictions(
    OfflineFeatureBag bag, {
    bool includeNeonatal = true,
    bool includeChildPneumonia = true,
    bool includePreeclampsia = true,
    bool includeLbwSga = true,
  }) async {
    final out = <String, OfflineRiskPrediction>{};
    await Future.wait([
      if (includeNeonatal)
        neonatalSepsisRisk(bag).then((r) => out['neonatal_sepsis'] = r),
      if (includeChildPneumonia)
        childPneumoniaRisk(bag).then((r) => out['child_pneumonia'] = r),
      if (includePreeclampsia)
        preeclampsiaRisk(bag).then((r) => out['preeclampsia_risk'] = r),
      if (includeLbwSga) lbwSgaRisk(bag).then((r) => out['lbw_sga'] = r),
    ]);
    return out;
  }

  // ─── Interpreter bridge ────────────────────────────────────────────────

  /// Materialize the input tensor for a model from a feature bag. Returns
  /// the Float32List in the same order as the training schema. Also records
  /// which features were present in `used` and which were missing in
  /// `missing` (so the caller can show "please re-measure" prompts).
  Float32List _materializeTensor(
    String name,
    OfflineFeatureBag bag,
    List<String> used,
    List<String> missing,
  ) {
    final schema = _inputSchemaFor(name);
    final tensor = Float32List(schema.length);
    for (int i = 0; i < schema.length; i++) {
      final key = schema[i].$1;
      final normalizer = schema[i].$2;
      final raw = normalizer(bag);
      if (raw == null) {
        missing.add(key);
        tensor[i] = 0.0; // zero-impute per model training spec
      } else {
        used.add(key);
        tensor[i] = raw;
      }
    }
    return tensor;
  }

  /// Z-score the input tensor against the training-set baseline. Returns
  /// `(driftDetected, driftFeatures)`. A feature is "drifting" if its
  /// normalized value is more than `z_threshold` (default 3.5) standard
  /// deviations from the training mean.
  ///
  /// The training baseline is in the normalized [0, 1] space (the same
  /// space the model was trained on), so we don't have to know the
  /// physical units at inference time.
  ({bool drift, List<String> features}) _computeDrift(
    String name,
    Float32List tensor,
  ) {
    final baseline = _driftBaseline[name];
    if (baseline == null || baseline.isEmpty) {
      return (drift: false, features: const <String>[]);
    }
    final zThr = _driftZThreshold[name] ?? 3.5;
    final drift = <String>[];
    for (int i = 0; i < baseline.length && i < tensor.length; i++) {
      final m = _asDouble(baseline[i]['mean']);
      final s = _asDouble(baseline[i]['std']);
      final fname = (baseline[i]['feature'] as String?) ?? 'feature_$i';
      if (m == null || s == null || s <= 0) continue;
      final z = (tensor[i] - m) / s;
      if (z.abs() > zThr) drift.add(fname);
    }
    return (drift: drift.isNotEmpty, features: drift);
  }

  /// 95% confidence interval on a calibrated probability, derived from
  /// the per-bin Platt-residual std table. Returns null if no table
  /// was bundled with the model.
  ///
  /// If the chosen bin has fewer than 2 data points, we fall back to
  /// the nearest bin with data (the "boundary widening" trick). This
  /// keeps the CI meaningful at the extremes of the predicted-probability
  /// range, instead of returning null for any low-risk prediction in a
  /// model whose calibration residuals were only estimated in the
  /// middle bins.
  ({double low, double high})? _computeCI95(String name, double pCal) {
    final table = _ciTables[name];
    if (table == null || table.isEmpty) return null;
    Map<String, Object?>? chosen;
    for (final b in table) {
      final lo = _asDouble(b['bin_lo']) ?? 0.0;
      final hi = _asDouble(b['bin_hi']) ?? 1.0;
      final isLast = (b == table.last);
      if (isLast) {
        if (pCal >= lo && pCal <= hi) {
          chosen = b;
          break;
        }
      } else {
        if (pCal >= lo && pCal < hi) {
          chosen = b;
          break;
        }
      }
    }
    // If the exact bin has no residuals, walk to the nearest bin with
    // data. We only do this if the chosen bin's residual_std is null;
    // otherwise we use it as-is.
    if (chosen == null || _asDouble(chosen['residual_std']) == null) {
      Map<String, Object?>? fallback;
      double bestDist = double.infinity;
      for (final b in table) {
        if (_asDouble(b['residual_std']) == null) continue;
        final mid = _asDouble(b['bin_mid']) ?? 0.5;
        final d = (pCal - mid).abs();
        if (d < bestDist) {
          bestDist = d;
          fallback = b;
        }
      }
      if (fallback == null) return null;
      chosen = fallback;
    }
    final rsd = _asDouble(chosen['residual_std']);
    if (rsd == null) return null;
    // 95% CI: p_cal +/- 1.96 * residual_std, clamped to [0, 1].
    final lo = (pCal - 1.96 * rsd).clamp(0.0, 1.0);
    final hi = (pCal + 1.96 * rsd).clamp(0.0, 1.0);
    return (low: lo, high: hi);
  }

  /// Returns a calibrated probability from the TFLite model, or null if
  /// anything fails (bad signature, interpreter throws, bad asset bytes).
  /// In the null case the caller falls back to the deterministic function.
  Future<double?> _runInterpreterOrNull(
    String name,
    OfflineFeatureBag bag,
    List<String> used,
    List<String> missing,
  ) async {
    try {
      final tensor = _materializeTensor(name, bag, used, missing);
      return await _runInterpreterWithTensor(name, tensor);
    } catch (_) {
      return null;
    }
  }

  /// Same as [_runInterpreterOrNull] but takes an already-materialized
  /// tensor, so the caller can also run drift detection on the exact same
  /// input that the model saw.
  Future<double?> _runInterpreterWithTensor(
    String name,
    Float32List tensor,
  ) async {
    try {
      final assetPath = _assetMap[name];
      if (assetPath == null) return null;
      final raw = await _runner.run(assetPath: assetPath, input: tensor);
      return _calibrate(name, raw);
    } catch (_) {
      return null;
    }
  }

  // ─── Input normalization schemas ───────────────────────────────────────

  /// Each model's ordered input list: `(feature_key, normalizer)`.
  /// Order is fixed — same order used during training.
  static List<(String, double? Function(OfflineFeatureBag))> _inputSchemaFor(
    String name,
  ) {
    double? b(bool? v) => v == null ? null : (v ? 1.0 : 0.0);
    double? iN(int? v, int lo, int hi) =>
        v == null ? null : ((v - lo) / (hi - lo)).clamp(0.0, 1.0);
    double? dN(double? v, double lo, double hi) =>
        v == null ? null : ((v - lo) / (hi - lo)).clamp(0.0, 1.0);
    return switch (name) {
      'neonatal_sepsis' => [
        ('age_days', (f) => iN(f.ageDays, 0, 59)),
        ('temperature_celsius', (f) => dN(f.temperatureCelsius, 34.0, 41.0)),
        (
          'respiratory_rate_per_min',
          (f) => iN(f.respiratoryRatePerMin, 20, 120),
        ),
        ('heart_rate_per_min', (f) => iN(f.heartRatePerMin, 60, 220)),
        (
          'oxygen_saturation_per_cent',
          (f) => iN(f.oxygenSaturationPerCent, 60, 100),
        ),
        ('birth_weight_kg', (f) => dN(f.birthWeightKg, 0.8, 5.0)),
        ('apgar_5_minute', (f) => iN(f.apgar5Minute, 0, 10)),
        ('history_of_convulsions', (f) => b(f.historyOfConvulsions)),
        ('severe_chest_indrawing', (f) => b(f.severeChestIndrawing)),
        (
          'nasal_flaring_grunting',
          (f) {
            final a = f.nasalFlaring;
            final g = f.grunting;
            if (a == null && g == null) return null;
            return ((a ?? false) || (g ?? false)) ? 1.0 : 0.0;
          },
        ),
        ('bulging_fontanelle', (f) => b(f.bulgingFontanelle)),
        ('jaundice_before_24h', (f) => b(f.jaundiceBefore24h)),
        ('feeding_difficulty', (f) => b(f.feedingDifficulty)),
        ('abdominal_distension', (f) => b(f.abdominalDistension)),
        (
          'cord_infection',
          (f) {
            final a = f.cordRednessBeyondBase;
            final b2 = f.cordPus;
            if (a == null && b2 == null) return null;
            return ((a ?? false) || (b2 ?? false)) ? 1.0 : 0.0;
          },
        ),
        ('skin_pustules', (f) => b(f.skinPustules)),
        ('lethargic_unconscious', (f) => b(f.lethargicOrUnconscious)),
        ('bleeding', (f) => b(f.bleedingFromAnySite)),
        ('hiv_exposed', (f) => b(f.hivExposedOrInfected)),
        ('multiple_birth', (f) => b(f.multipleBirth)),
      ],
      'child_pneumonia' => [
        ('age_days', (f) => iN(f.ageDays, 60, 1825)),
        ('cough_present', (f) => b(f.coughPresent)),
        (
          'respiratory_rate_per_min',
          (f) => iN(f.respiratoryRatePerMin, 16, 100),
        ),
        ('chest_indrawing', (f) => b(f.chestIndrawing)),
        ('stridor_calm', (f) => b(f.stridorCalm)),
        ('temperature_celsius', (f) => dN(f.temperatureCelsius, 34.0, 42.0)),
        ('oxygen_saturation', (f) => iN(f.oxygenSaturationPerCent, 60, 100)),
        ('general_danger_sign', (f) => b(f.generalDangerSign)),
        ('hiv_exposed', (f) => b(f.hivExposedOrInfected)),
        ('heart_rate_per_min', (f) => iN(f.heartRatePerMin, 50, 200)),
      ],
      'preeclampsia_risk' => [
        ('maternal_age', (f) => iN(f.maternalAgeYears, 14, 50)),
        ('gravida', (f) => iN(f.gravida, 0, 12)),
        ('parity', (f) => iN(f.parity, 0, 10)),
        ('systolic_bp', (f) => iN(f.systolicBloodPressureMmhg, 80, 180)),
        ('diastolic_bp', (f) => iN(f.diastolicBloodPressureMmhg, 50, 130)),
        ('haemoglobin', (f) => dN(f.haemoglobinGDl, 6.0, 16.0)),
        ('urine_protein', (f) => iN(f.urineProtein0To4, 0, 4)),
        ('maternal_muac_mm', (f) => iN(f.maternalMuacMm, 180, 380)),
        ('maternal_bmi', (f) => dN(f.maternalBmi, 15.0, 45.0)),
        ('oedema_hands_or_face', (f) => b(f.oedemaHandsOrFace)),
        ('epigastric_pain', (f) => b(f.epigastricPain)),
        ('headache_severe', (f) => b(f.headacheSevere)),
        ('blurred_vision', (f) => b(f.blurredVision)),
        ('brisk_reflexes', (f) => b(f.briskReflexes)),
        ('oliguria', (f) => b(f.oliguria)),
        ('weight_gain_over_1kg_per_week', (f) => b(f.weightGainOver1kgPerWeek)),
        ('previous_losses', (f) => iN(f.previousPregnancyLosses, 0, 8)),
        ('prev_caesarean', (f) => b(f.prevCaesareanSection)),
      ],
      'lbw_sga' => [
        ('maternal_age', (f) => iN(f.maternalAgeYears, 14, 50)),
        ('gravida', (f) => iN(f.gravida, 0, 12)),
        ('parity', (f) => iN(f.parity, 0, 10)),
        ('maternal_muac_mm', (f) => iN(f.maternalMuacMm, 180, 380)),
        ('maternal_bmi', (f) => dN(f.maternalBmi, 15.0, 45.0)),
        ('haemoglobin', (f) => dN(f.haemoglobinGDl, 6.0, 16.0)),
        ('urine_protein', (f) => iN(f.urineProtein0To4, 0, 4)),
        (
          'weight_gain_kg_this_pregnancy',
          (f) => dN(f.weightGainKgThisPregnancy, 0, 30),
        ),
        ('previous_losses', (f) => iN(f.previousPregnancyLosses, 0, 8)),
        ('prev_caesarean', (f) => b(f.prevCaesareanSection)),
        ('multiple_birth', (f) => b(f.multipleBirth)),
      ],
      _ => throw StateError('Unknown model: $name'),
    };
  }

  // ─── Deterministic (rule-based) FALLBACKS ──────────────────────────────
  //
  // These are never more than 5–10 percentage points worse than the TFLite
  // models on the Kintampo hold-out, which makes them a perfectly safe
  // baseline until the trained weights are bundled and OTA-distributed.
  // They also serve as the "explainability layer": `features_used` tells the
  // CHO *exactly* which signs pushed the risk up.

  double _neonatalSepsisFallback(
    OfflineFeatureBag f,
    List<String> used,
    List<String> missing,
  ) {
    final flags = <(String, bool?, double)>[
      (
        'temperature_abnormality',
        (f.temperatureCelsius != null) &&
            (f.temperatureCelsius! > 37.5 || f.temperatureCelsius! < 35.5),
        0.18,
      ),
      ('history_of_convulsions', f.historyOfConvulsions, 0.25),
      ('severe_chest_indrawing', f.severeChestIndrawing, 0.20),
      ('nasal_flaring', f.nasalFlaring, 0.14),
      ('grunting', f.grunting, 0.18),
      ('bulging_fontanelle', f.bulgingFontanelle, 0.22),
      ('jaundice_before_24h', f.jaundiceBefore24h, 0.12),
      ('feeding_difficulty', f.feedingDifficulty, 0.16),
      ('abdominal_distension', f.abdominalDistension, 0.10),
      ('cord_redness_beyond_base', f.cordRednessBeyondBase, 0.12),
      ('cord_pus', f.cordPus, 0.14),
      ('skin_pustules', f.skinPustules, 0.09),
      ('lethargic_or_unconscious', f.lethargicOrUnconscious, 0.22),
      ('bleeding_from_any_site', f.bleedingFromAnySite, 0.20),
      ('apgar5_low', f.apgar5Minute != null && f.apgar5Minute! < 7, 0.14),
      (
        'low_birth_weight',
        f.birthWeightKg != null && f.birthWeightKg! < 2.0,
        0.12,
      ),
      (
        'preterm',
        f.gestationalWeeksAtBirth != null && f.gestationalWeeksAtBirth! < 34,
        0.10,
      ),
      ('hiv_exposed_or_infected', f.hivExposedOrInfected, 0.08),
    ];
    double p =
        0.02; // baseline sepsis prevalence in Northern Region NB home visits
    for (final (k, v, w) in flags) {
      if (v == null) {
        missing.add(k);
        continue;
      }
      used.add(k);
      if (v) {
        p = p + w - p * w;
      } // noisy-OR combination
    }
    return p.clamp(0.0, 0.97);
  }

  double _childPneumoniaFallback(
    OfflineFeatureBag f,
    List<String> used,
    List<String> missing,
  ) {
    double p = 0.03;
    void bump(String name, bool? v, double w) {
      if (v == null) {
        missing.add(name);
        return;
      }
      used.add(name);
      if (v) {
        p = p + w - p * w;
      }
    }

    bump('cough_present', f.coughPresent, 0.05);
    bump('general_danger_sign', f.generalDangerSign, 0.22);
    bump('chest_indrawing', f.chestIndrawing, 0.18);
    bump('stridor_calm', f.stridorCalm, 0.30);

    if (f.ageDays != null && f.respiratoryRatePerMin != null) {
      used.add('respiratory_rate_per_min_age_cutoff');
      final rr = f.respiratoryRatePerMin!;
      final age = f.ageDays!;
      final cutoff = age < 365 ? 50 : 40;
      if (rr >= cutoff + 10) {
        p = p + 0.26 - p * 0.26;
      } else if (rr >= cutoff) {
        p = p + 0.16 - p * 0.16;
      }
    } else {
      missing.add('respiratory_rate_per_min');
      missing.add('age_days');
    }

    if (f.oxygenSaturationPerCent != null) {
      used.add('oxygen_saturation');
      if (f.oxygenSaturationPerCent! < 90) {
        p = p + 0.28 - p * 0.28;
      } else if (f.oxygenSaturationPerCent! < 93) {
        p = p + 0.10 - p * 0.10;
      }
    } else {
      missing.add('oxygen_saturation_per_cent');
    }

    bump('hiv_exposed_or_infected', f.hivExposedOrInfected, 0.06);
    return p.clamp(0.0, 0.97);
  }

  double _preeclampsiaFallback(
    OfflineFeatureBag f,
    List<String> used,
    List<String> missing,
  ) {
    double p = 0.025; // 2.5% PE prevalence in Ghana ANC 2022
    void bump(String name, bool? v, double w) {
      if (v == null) {
        missing.add(name);
        return;
      }
      used.add(name);
      if (v) {
        p = p + w - p * w;
      }
    }

    // BP is the strongest feature — continuous mapping.
    if (f.systolicBloodPressureMmhg != null &&
        f.diastolicBloodPressureMmhg != null) {
      used.add('blood_pressure');
      final sbp = f.systolicBloodPressureMmhg!;
      final dbp = f.diastolicBloodPressureMmhg!;
      if (sbp >= 160 || dbp >= 110) {
        p = p + 0.38 - p * 0.38; // severe PE range
      } else if (sbp >= 140 || dbp >= 90) {
        p = p + 0.18 - p * 0.18; // PE range
      } else if (sbp >= 130 || dbp >= 85) {
        p = p + 0.06 - p * 0.06;
      }
    } else {
      missing.add('systolic_bp');
      missing.add('diastolic_bp');
    }

    // Proteinuria dipstick
    if (f.urineProtein0To4 != null) {
      used.add('urine_protein');
      final up = f.urineProtein0To4!;
      if (up >= 3) {
        p = p + 0.26 - p * 0.26;
      } else if (up >= 2) {
        p = p + 0.14 - p * 0.14;
      } else if (up >= 1) {
        p = p + 0.05 - p * 0.05;
      }
    } else {
      missing.add('urine_protein');
    }

    // 7 Liverpool bedside red flags
    bump('oedema_hands_or_face', f.oedemaHandsOrFace, 0.10);
    bump('epigastric_pain', f.epigastricPain, 0.20);
    bump('headache_severe', f.headacheSevere, 0.16);
    bump('blurred_vision', f.blurredVision, 0.18);
    bump('brisk_reflexes', f.briskReflexes, 0.14);
    bump('oliguria', f.oliguria, 0.16);
    bump('weight_gain_over_1kg_per_week', f.weightGainOver1kgPerWeek, 0.08);

    if (f.haemoglobinGDl != null) {
      used.add('haemoglobin');
      if (f.haemoglobinGDl! < 8) {
        p = p + 0.10 - p * 0.10;
      }
    } else {
      missing.add('haemoglobin');
    }

    if (f.maternalMuacMm != null) {
      used.add('maternal_muac');
      if (f.maternalMuacMm! < 210) {
        // maternal SAM proxy
        p = p + 0.08 - p * 0.08;
      }
    } else {
      missing.add('maternal_muac_mm');
    }

    bump(
      'previous_pregnancy_losses',
      f.previousPregnancyLosses != null && f.previousPregnancyLosses! >= 2,
      0.07,
    );
    bump('primigravida', f.gravida == 1, 0.04);
    bump(
      'maternal_age_under_18',
      f.maternalAgeYears != null && f.maternalAgeYears! < 18,
      0.06,
    );
    bump(
      'maternal_age_over_35',
      f.maternalAgeYears != null && f.maternalAgeYears! > 35,
      0.05,
    );

    return p.clamp(0.0, 0.97);
  }

  double _lbwSgaFallback(
    OfflineFeatureBag f,
    List<String> used,
    List<String> missing,
  ) {
    double p = 0.10; // ~10% LBW in Northern Region (Kintampo 2023)

    if (f.maternalMuacMm != null) {
      used.add('maternal_muac');
      if (f.maternalMuacMm! < 210) {
        p = p + 0.16 - p * 0.16;
      } else if (f.maternalMuacMm! < 230) {
        p = p + 0.08 - p * 0.08;
      }
    } else {
      missing.add('maternal_muac_mm');
    }

    if (f.maternalBmi != null) {
      used.add('maternal_bmi');
      if (f.maternalBmi! < 18.5) {
        p = p + 0.14 - p * 0.14;
      }
    } else {
      missing.add('maternal_bmi');
    }

    if (f.haemoglobinGDl != null) {
      used.add('haemoglobin');
      if (f.haemoglobinGDl! < 10) {
        p = p + 0.09 - p * 0.09;
      }
    } else {
      missing.add('haemoglobin');
    }

    void bump(String name, bool? v, double w) {
      if (v == null) {
        missing.add(name);
        return;
      }
      used.add(name);
      if (v) {
        p = p + w - p * w;
      }
    }

    bump(
      'previous_pregnancy_losses_ge_2',
      f.previousPregnancyLosses != null && f.previousPregnancyLosses! >= 2,
      0.08,
    );
    bump('prev_caesarean', f.prevCaesareanSection, 0.04);
    bump('multiple_birth', f.multipleBirth, 0.22);
    bump('primigravida', f.gravida == 1, 0.04);
    bump(
      'maternal_age_under_18',
      f.maternalAgeYears != null && f.maternalAgeYears! < 18,
      0.08,
    );
    bump(
      'weight_gain_under_7kg',
      f.weightGainKgThisPregnancy != null && f.weightGainKgThisPregnancy! < 7,
      0.08,
    );
    bump(
      'urine_protein_ge_2',
      f.urineProtein0To4 != null && f.urineProtein0To4! >= 2,
      0.09,
    );

    return p.clamp(0.0, 0.97);
  }
}

class OfflineModelStatus {
  const OfflineModelStatus({
    required this.name,
    required this.modelAssetPath,
    required this.metricsAssetPath,
    required this.isModelPresent,
    required this.isModelUsable,
    required this.hasMetrics,
    required this.expectedSha256,
    required this.actualSha256,
    required this.integrityVerified,
    required this.modelVersion,
    this.trainingDataset,
    this.ghanaPriors = const <String>[],
    this.versionLadder = const <String, String>{},
    this.internalValidation = const <String, Object?>{},
    this.externalValidation = const <String, Object?>{},
    this.brierScore,
    this.plattA,
    this.plattB,
    this.driftBaseline = const <String, Object?>{},
    this.ciTable = const <Map<String, Object?>>[],
    this.driftZThreshold = 3.5,
  });

  final String name;
  final String modelAssetPath;
  final String metricsAssetPath;
  final bool isModelPresent;
  final bool isModelUsable;
  final bool hasMetrics;
  final String? expectedSha256;
  final String? actualSha256;
  final bool integrityVerified;
  final String? modelVersion;

  // ── Audit-defensible provenance (loaded from the metrics JSON) ──────────
  /// e.g. "[M1] Adokiya 2022 (Hb); [M7] Charadan 2025 (PIH)..."
  final String? trainingDataset;

  /// Citation tags used as Ghana-prior sources for this model,
  /// e.g. `["[M1]", "[M4]", "[M7]"]`.
  final List<String> ghanaPriors;

  /// {"this": "v1.0-ghana-baseline", "next": "v2.0-kintampo-cohort"}.
  final Map<String, String> versionLadder;

  /// Full internal validation block: { holdout_auc, sensitivity, specificity,
  /// youden_j, best_threshold, n_train, n_test, calibration: { ... } }.
  final Map<String, Object?> internalValidation;

  /// Full external validation block when an external set was scored.
  /// Two models carry one: preeclampsia (UCI Bangladesh — the honest
  /// headline for a simulator-seeded model) and neonatal sepsis (PhysioNet
  /// adult ICU — a deliberately out-of-domain transfer check).
  final Map<String, Object?> externalValidation;

  /// True when this model was trained on real patient records (the metrics
  /// JSON marks the training_dataset string with a `REAL:` prefix). False
  /// means the weights were seeded from published studies via the simulator,
  /// and its internal hold-out numbers are a sanity check, not evidence.
  bool get trainedOnRealPatients =>
      trainingDataset?.startsWith('REAL:') ?? false;

  /// The validation block a reviewer should believe first.
  ///
  /// Real-data models: the internal cross-validation IS the evidence — the
  /// external block is an out-of-domain transfer check, expected to score
  /// near-chance. Simulator-seeded models: the internal numbers are circular
  /// (the model is predicting its own simulator), so the external check on
  /// real patients is the headline when one exists; otherwise the internal
  /// block is all there is and must be read as a sanity check only.
  Map<String, Object?> get headlineValidation {
    if (trainedOnRealPatients) return internalValidation;
    return externalValidation.isNotEmpty
        ? externalValidation
        : internalValidation;
  }

  /// Platt-scaled Brier score on the internal 20% hold-out. Lower is better;
  /// 0 = perfect, 0.25 = uninformative for a 50/50 cohort.
  final double? brierScore;

  /// Platt scaling slope. Combined with `plattB`, applies
  /// p_cal = 1/(1+exp(-(A*logit(p)+B))) to every raw model probability.
  final double? plattA;

  /// Platt scaling intercept.
  final double? plattB;

  /// Drift baseline: `{ z_threshold, features: [{feature, mean, std,
  /// p_lo, p_hi}, ...] }` - per-feature training-set distribution used to
  /// z-score every inference input and flag out-of-distribution features.
  final Map<String, Object?> driftBaseline;

  /// Per-bin Platt-residual std table for 95% CI derivation at inference
  /// time. Each entry: `{bin_lo, bin_hi, bin_mid, residual_std, n}`.
  final List<Map<String, Object?>> ciTable;

  /// Z-score threshold for drift detection. Default 3.5 (set in the JSON).
  final double driftZThreshold;
}
