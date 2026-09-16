/// Offline research models. Clinical decisions remain in the guideline engines.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'tflite_runner.dart';
import 'tflite_dart_interpreter.dart';

part 'offline_prediction.dart';
part 'research_runtime.dart';

/// Typed feature bag passed to every predictor. Fields are nullable because
/// real-world CHO intake is incomplete — each predictor reports which ones it
/// actually used / missed so the UI can nudge.
class OfflineFeatureBag {
  const OfflineFeatureBag({
    // ── Shared vitals / demographics ──────────────────────────────────────
    this.ageDays,
    this.ageMonths,
    this.isMaternal = false,
    this.gestationalWeeks,
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
  final int? ageMonths;
  final bool isMaternal;
  final int? gestationalWeeks;
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

  static const Object _unset = Object();

  /// Field-by-field copy used by [withoutFeature]. An argument left at
  /// [_unset] keeps the current value; an explicit null clears it.
  OfflineFeatureBag _copy({
    Object? ageDays = _unset,
    Object? gestationalWeeksAtBirth = _unset,
    Object? heartRatePerMin = _unset,
    Object? respiratoryRatePerMin = _unset,
    Object? temperatureCelsius = _unset,
    Object? oxygenSaturationPerCent = _unset,
    Object? systolicBloodPressureMmhg = _unset,
    Object? diastolicBloodPressureMmhg = _unset,
    Object? maternalMuacMm = _unset,
    Object? maternalBmi = _unset,
    Object? haemoglobinGDl = _unset,
    Object? urineProtein0To4 = _unset,
    Object? urineKetones0To3 = _unset,
    Object? urineBlood0To3 = _unset,
    Object? urineGlucose0To4 = _unset,
    Object? previousPregnancyLosses = _unset,
    Object? prevCaesareanSection = _unset,
    Object? maternalAgeYears = _unset,
    Object? gravida = _unset,
    Object? parity = _unset,
    Object? weightGainKgThisPregnancy = _unset,
    Object? oedemaHandsOrFace = _unset,
    Object? epigastricPain = _unset,
    Object? headacheSevere = _unset,
    Object? blurredVision = _unset,
    Object? briskReflexes = _unset,
    Object? oliguria = _unset,
    Object? weightGainOver1kgPerWeek = _unset,
    Object? birthWeightKg = _unset,
    Object? birthLengthCm = _unset,
    Object? apgar5Minute = _unset,
    Object? historyOfConvulsions = _unset,
    Object? severeChestIndrawing = _unset,
    Object? nasalFlaring = _unset,
    Object? grunting = _unset,
    Object? bulgingFontanelle = _unset,
    Object? jaundiceBefore24h = _unset,
    Object? feedingDifficulty = _unset,
    Object? abdominalDistension = _unset,
    Object? cordRednessBeyondBase = _unset,
    Object? cordPus = _unset,
    Object? skinPustules = _unset,
    Object? lethargicOrUnconscious = _unset,
    Object? bleedingFromAnySite = _unset,
    Object? coughPresent = _unset,
    Object? chestIndrawing = _unset,
    Object? stridorCalm = _unset,
    Object? generalDangerSign = _unset,
    Object? hivExposedOrInfected = _unset,
    Object? multipleBirth = _unset,
  }) => OfflineFeatureBag(
    ageMonths: ageMonths,
    isMaternal: isMaternal,
    gestationalWeeks: gestationalWeeks,
    ageDays: identical(ageDays, _unset) ? this.ageDays : ageDays as int?,
    gestationalWeeksAtBirth: identical(gestationalWeeksAtBirth, _unset)
        ? this.gestationalWeeksAtBirth
        : gestationalWeeksAtBirth as int?,
    heartRatePerMin: identical(heartRatePerMin, _unset)
        ? this.heartRatePerMin
        : heartRatePerMin as int?,
    respiratoryRatePerMin: identical(respiratoryRatePerMin, _unset)
        ? this.respiratoryRatePerMin
        : respiratoryRatePerMin as int?,
    temperatureCelsius: identical(temperatureCelsius, _unset)
        ? this.temperatureCelsius
        : temperatureCelsius as double?,
    oxygenSaturationPerCent: identical(oxygenSaturationPerCent, _unset)
        ? this.oxygenSaturationPerCent
        : oxygenSaturationPerCent as int?,
    systolicBloodPressureMmhg: identical(systolicBloodPressureMmhg, _unset)
        ? this.systolicBloodPressureMmhg
        : systolicBloodPressureMmhg as int?,
    diastolicBloodPressureMmhg: identical(diastolicBloodPressureMmhg, _unset)
        ? this.diastolicBloodPressureMmhg
        : diastolicBloodPressureMmhg as int?,
    maternalMuacMm: identical(maternalMuacMm, _unset)
        ? this.maternalMuacMm
        : maternalMuacMm as int?,
    maternalBmi: identical(maternalBmi, _unset)
        ? this.maternalBmi
        : maternalBmi as double?,
    haemoglobinGDl: identical(haemoglobinGDl, _unset)
        ? this.haemoglobinGDl
        : haemoglobinGDl as double?,
    urineProtein0To4: identical(urineProtein0To4, _unset)
        ? this.urineProtein0To4
        : urineProtein0To4 as int?,
    urineKetones0To3: identical(urineKetones0To3, _unset)
        ? this.urineKetones0To3
        : urineKetones0To3 as int?,
    urineBlood0To3: identical(urineBlood0To3, _unset)
        ? this.urineBlood0To3
        : urineBlood0To3 as int?,
    urineGlucose0To4: identical(urineGlucose0To4, _unset)
        ? this.urineGlucose0To4
        : urineGlucose0To4 as int?,
    previousPregnancyLosses: identical(previousPregnancyLosses, _unset)
        ? this.previousPregnancyLosses
        : previousPregnancyLosses as int?,
    prevCaesareanSection: identical(prevCaesareanSection, _unset)
        ? this.prevCaesareanSection
        : prevCaesareanSection as bool?,
    maternalAgeYears: identical(maternalAgeYears, _unset)
        ? this.maternalAgeYears
        : maternalAgeYears as int?,
    gravida: identical(gravida, _unset) ? this.gravida : gravida as int?,
    parity: identical(parity, _unset) ? this.parity : parity as int?,
    weightGainKgThisPregnancy: identical(weightGainKgThisPregnancy, _unset)
        ? this.weightGainKgThisPregnancy
        : weightGainKgThisPregnancy as double?,
    oedemaHandsOrFace: identical(oedemaHandsOrFace, _unset)
        ? this.oedemaHandsOrFace
        : oedemaHandsOrFace as bool?,
    epigastricPain: identical(epigastricPain, _unset)
        ? this.epigastricPain
        : epigastricPain as bool?,
    headacheSevere: identical(headacheSevere, _unset)
        ? this.headacheSevere
        : headacheSevere as bool?,
    blurredVision: identical(blurredVision, _unset)
        ? this.blurredVision
        : blurredVision as bool?,
    briskReflexes: identical(briskReflexes, _unset)
        ? this.briskReflexes
        : briskReflexes as bool?,
    oliguria: identical(oliguria, _unset) ? this.oliguria : oliguria as bool?,
    weightGainOver1kgPerWeek: identical(weightGainOver1kgPerWeek, _unset)
        ? this.weightGainOver1kgPerWeek
        : weightGainOver1kgPerWeek as bool?,
    birthWeightKg: identical(birthWeightKg, _unset)
        ? this.birthWeightKg
        : birthWeightKg as double?,
    birthLengthCm: identical(birthLengthCm, _unset)
        ? this.birthLengthCm
        : birthLengthCm as double?,
    apgar5Minute: identical(apgar5Minute, _unset)
        ? this.apgar5Minute
        : apgar5Minute as int?,
    historyOfConvulsions: identical(historyOfConvulsions, _unset)
        ? this.historyOfConvulsions
        : historyOfConvulsions as bool?,
    severeChestIndrawing: identical(severeChestIndrawing, _unset)
        ? this.severeChestIndrawing
        : severeChestIndrawing as bool?,
    nasalFlaring: identical(nasalFlaring, _unset)
        ? this.nasalFlaring
        : nasalFlaring as bool?,
    grunting: identical(grunting, _unset) ? this.grunting : grunting as bool?,
    bulgingFontanelle: identical(bulgingFontanelle, _unset)
        ? this.bulgingFontanelle
        : bulgingFontanelle as bool?,
    jaundiceBefore24h: identical(jaundiceBefore24h, _unset)
        ? this.jaundiceBefore24h
        : jaundiceBefore24h as bool?,
    feedingDifficulty: identical(feedingDifficulty, _unset)
        ? this.feedingDifficulty
        : feedingDifficulty as bool?,
    abdominalDistension: identical(abdominalDistension, _unset)
        ? this.abdominalDistension
        : abdominalDistension as bool?,
    cordRednessBeyondBase: identical(cordRednessBeyondBase, _unset)
        ? this.cordRednessBeyondBase
        : cordRednessBeyondBase as bool?,
    cordPus: identical(cordPus, _unset) ? this.cordPus : cordPus as bool?,
    skinPustules: identical(skinPustules, _unset)
        ? this.skinPustules
        : skinPustules as bool?,
    lethargicOrUnconscious: identical(lethargicOrUnconscious, _unset)
        ? this.lethargicOrUnconscious
        : lethargicOrUnconscious as bool?,
    bleedingFromAnySite: identical(bleedingFromAnySite, _unset)
        ? this.bleedingFromAnySite
        : bleedingFromAnySite as bool?,
    coughPresent: identical(coughPresent, _unset)
        ? this.coughPresent
        : coughPresent as bool?,
    chestIndrawing: identical(chestIndrawing, _unset)
        ? this.chestIndrawing
        : chestIndrawing as bool?,
    stridorCalm: identical(stridorCalm, _unset)
        ? this.stridorCalm
        : stridorCalm as bool?,
    generalDangerSign: identical(generalDangerSign, _unset)
        ? this.generalDangerSign
        : generalDangerSign as bool?,
    hivExposedOrInfected: identical(hivExposedOrInfected, _unset)
        ? this.hivExposedOrInfected
        : hivExposedOrInfected as bool?,
    multipleBirth: identical(multipleBirth, _unset)
        ? this.multipleBirth
        : multipleBirth as bool?,
  );

  /// A copy of this bag with the feature named by [featureKey] removed,
  /// exactly as if that measurement had never been taken. Keys match the
  /// model input schemas in [_inputSchemaFor] plus the deterministic
  /// fallback rule names; composite keys clear every underlying field.
  /// Unknown keys return the bag unchanged. This powers the honest
  /// leave-one-out counterfactual: the prediction is re-run, never faked.
  OfflineFeatureBag withoutFeature(String featureKey) => switch (featureKey) {
    'age_days' => _copy(ageDays: null),
    'temperature_celsius' ||
    'temperature_abnormality' => _copy(temperatureCelsius: null),
    'respiratory_rate_per_min' ||
    'respiratory_rate_per_min_age_cutoff' => _copy(respiratoryRatePerMin: null),
    'heart_rate_per_min' => _copy(heartRatePerMin: null),
    'oxygen_saturation_per_cent' ||
    'oxygen_saturation' => _copy(oxygenSaturationPerCent: null),
    'systolic_bp' || 'diastolic_bp' || 'blood_pressure' => _copy(
      systolicBloodPressureMmhg: null,
      diastolicBloodPressureMmhg: null,
    ),
    'maternal_muac_mm' || 'maternal_muac' => _copy(maternalMuacMm: null),
    'maternal_bmi' => _copy(maternalBmi: null),
    'haemoglobin' => _copy(haemoglobinGDl: null),
    'urine_protein' => _copy(urineProtein0To4: null),
    'previous_losses' => _copy(previousPregnancyLosses: null),
    'prev_caesarean' => _copy(prevCaesareanSection: null),
    'maternal_age' => _copy(maternalAgeYears: null),
    'gravida' => _copy(gravida: null),
    'parity' => _copy(parity: null),
    'weight_gain_kg_this_pregnancy' => _copy(weightGainKgThisPregnancy: null),
    'oedema_hands_or_face' => _copy(oedemaHandsOrFace: null),
    'epigastric_pain' => _copy(epigastricPain: null),
    'headache_severe' => _copy(headacheSevere: null),
    'blurred_vision' => _copy(blurredVision: null),
    'brisk_reflexes' => _copy(briskReflexes: null),
    'oliguria' => _copy(oliguria: null),
    'weight_gain_over_1kg_per_week' => _copy(weightGainOver1kgPerWeek: null),
    'birth_weight_kg' || 'low_birth_weight' => _copy(birthWeightKg: null),
    'preterm' => _copy(gestationalWeeksAtBirth: null),
    'apgar_5_minute' || 'apgar5_low' => _copy(apgar5Minute: null),
    'history_of_convulsions' => _copy(historyOfConvulsions: null),
    'severe_chest_indrawing' => _copy(severeChestIndrawing: null),
    'nasal_flaring_grunting' => _copy(nasalFlaring: null, grunting: null),
    'nasal_flaring' => _copy(nasalFlaring: null),
    'grunting' => _copy(grunting: null),
    'bulging_fontanelle' => _copy(bulgingFontanelle: null),
    'jaundice_before_24h' => _copy(jaundiceBefore24h: null),
    'feeding_difficulty' => _copy(feedingDifficulty: null),
    'abdominal_distension' => _copy(abdominalDistension: null),
    'cord_infection' => _copy(cordRednessBeyondBase: null, cordPus: null),
    'cord_redness_beyond_base' => _copy(cordRednessBeyondBase: null),
    'cord_pus' => _copy(cordPus: null),
    'skin_pustules' => _copy(skinPustules: null),
    'lethargic_unconscious' ||
    'lethargic_or_unconscious' => _copy(lethargicOrUnconscious: null),
    'bleeding' || 'bleeding_from_any_site' => _copy(bleedingFromAnySite: null),
    'cough_present' => _copy(coughPresent: null),
    'chest_indrawing' => _copy(chestIndrawing: null),
    'stridor_calm' => _copy(stridorCalm: null),
    'general_danger_sign' => _copy(generalDangerSign: null),
    'hiv_exposed' ||
    'hiv_exposed_or_infected' => _copy(hivExposedOrInfected: null),
    'multiple_birth' => _copy(multipleBirth: null),
    _ => this,
  };
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
    this.contract = const {},
    this.metadataValid = false,
  });

  final Map<String, Object?> contract;
  final bool metadataValid;

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
      contract['evidence'] == 'legacy_real_data' ||
      contract['evidence'] == 'retrospective_research';

  /// The validation block a reviewer should believe first.
  ///
  /// Real-data models: the internal cross-validation IS the evidence — the
  /// external block is an out-of-domain transfer check, expected to score
  /// near-chance. Simulator-seeded models: the internal numbers are circular
  /// (the model is predicting its own simulator), so the external check on
  /// real patients is the headline when one exists; otherwise the internal
  /// block is all there is and must be read as a sanity check only.
  Map<String, Object?> get headlineValidation =>
      contract['evaluation_kind'] == 'exported_int8_holdout'
      ? internalValidation
      : const {};

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
