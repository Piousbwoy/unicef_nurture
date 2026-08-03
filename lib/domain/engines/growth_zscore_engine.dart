/// Weight-for-height z-score (WHZ) — the WHO's quantitative measure of
/// *wasting* (acute malnutrition).
///
/// The app already screens with MUAC bands, and that is right: a tape is cheap,
/// needs no scales, and a CHO can use it on a squirming two-year-old in a
/// doorway. But MUAC is a single number with a single cut-off, and it misses a
/// specific, dangerous child — the one whose **weight has collapsed but whose
/// arm is still just above 11.5 cm**. For that child the tape says "yellow"
/// while their weight-for-height is already below −3.
///
/// WHZ closes that gap. It compares a child's weight to the WHO median for a
/// child of the *same height and sex*, expressed in standard deviations
/// (z-scores). That is the measure the WHO and Ghana's CMAM protocol use to
/// define severe acute malnutrition (WHZ < −3) and moderate acute malnutrition
/// (−3 ≤ WHZ < −2).
///
/// ## Why this stays deterministic and inspectable
///
/// A z-score is not a prediction and not a model output. It is a child's
/// measured weight placed on the WHO's published growth distribution — pure
/// arithmetic against a published standard. Every result here states the
/// measured value, the median it was compared to, and the cut-off it crossed,
/// so a CHO can check it against the growth card and a supervisor can audit it.
/// That is the same "show the arithmetic" commitment as the rest of the app.
///
/// ## Safety guard-rails
///
///   * **Never extrapolate.** A height outside the bundled reference table
///     returns *insufficient reference data* — never a guessed z-score. An
///     incomplete table can only make the app conservative, never wrong.
///   * **Oedema overrides the number.** Bilateral pitting oedema is SAM by
///     definition, whatever the z-score. This engine respects that.
///   * **WHZ complements MUAC, it does not replace it.** The child is the
///     worse of the two indicators, and the finding says so.
library;

import 'dart:math' as math;

import '../../data/reference/growth_reference.dart';
import '../enums.dart';
import '../entities/visit.dart';

/// How far a child's weight-for-height sits below (or above) the WHO median.
enum WastingSeverity {
  severe(
    'Severe wasting',
    'Weight-for-height below −3 SD. Severe acute malnutrition.',
    TriageLevel.urgent,
  ),
  moderate(
    'Moderate wasting',
    'Weight-for-height between −3 and −2 SD. Moderate acute malnutrition.',
    TriageLevel.priority,
  ),
  atRisk(
    'At risk of wasting',
    'Weight-for-height between −2 and −1 SD. Watch closely and counsel.',
    TriageLevel.watch,
  ),
  normal(
    'Adequate weight-for-height',
    'Weight-for-height at or above −1 SD.',
    TriageLevel.routine,
  ),
  possibleOverweight(
    'High weight-for-height',
    'Weight-for-height above +2 SD. Possible overweight — review feeding and '
        'refer if persistent.',
    TriageLevel.watch,
  );

  const WastingSeverity(this.label, this.meaning, this.triage);
  final String label;
  final String meaning;
  final TriageLevel triage;
}

/// The result of a weight-for-height assessment.
class GrowthZScoreResult {
  const GrowthZScoreResult({
    required this.severity,
    required this.referenceDataSufficient,
    required this.explanation,
    this.zScore,
    this.medianWeightKg,
    this.nutritionStatus,
    this.findings = const [],
  });

  final WastingSeverity severity;

  /// The computed z-score, or `null` when it could not be computed (missing
  /// inputs or insufficient reference data).
  final double? zScore;

  /// The WHO median weight for this child's height and sex — shown so the CHO
  /// can see what the child was compared against.
  final double? medianWeightKg;

  /// Maps the wasting result onto the app's shared nutrition vocabulary.
  /// `null` when no z-score could be computed.
  final NutritionStatus? nutritionStatus;

  /// False when the height fell outside the bundled reference table and no
  /// z-score could be produced.
  final bool referenceDataSufficient;

  /// The arithmetic, in words, so it can be checked against the growth card.
  final String explanation;

  final List<ClinicalFinding> findings;

  /// True when this result alone warrants SAM/MAM management.
  bool get isAcuteMalnutrition =>
      severity == WastingSeverity.severe || severity == WastingSeverity.moderate;
}

abstract final class GrowthZScoreEngine {
  static const String _source = 'WHO Child Growth Standards (2006), '
      'weight-for-height';

  /// WHO cut-offs, in standard deviations below/above the median.
  static const double _severeCutOff = -3.0;
  static const double _moderateCutOff = -2.0;
  static const double _atRiskCutOff = -1.0;
  static const double _overweightCutOff = 2.0;

  /// Computes a weight-for-height z-score and classifies wasting.
  ///
  /// [hasBilateralOedema] overrides the z-score: oedematous malnutrition is
  /// SAM by definition. Pass it through from the measurement — never drop it.
  static GrowthZScoreResult assess({
    required Sex sex,
    required double? weightKg,
    required double? heightCm,
    bool hasBilateralOedema = false,
  }) {
    // Oedema is SAM regardless of any number. Decide that first so a missing
    // or out-of-range measurement can never hide it.
    if (hasBilateralOedema) {
      return GrowthZScoreResult(
        severity: WastingSeverity.severe,
        referenceDataSufficient: true,
        nutritionStatus: NutritionStatus.severeAcute,
        explanation: 'Bilateral pitting oedema is present. Oedematous '
            'malnutrition is severe acute malnutrition by definition, '
            'whatever the weight-for-height reads.',
        findings: const [
          ClinicalFinding(
            label: 'Bilateral pitting oedema',
            detail: 'Oedema in both feet is severe acute malnutrition until '
                'proven otherwise. This overrides every anthropometric number.',
            severity: TriageLevel.urgent,
            protocolSource: 'WHO IMCI / CMAM protocol',
            weight: 1,
            isDangerSign: true,
          ),
        ],
      );
    }

    if (weightKg == null || heightCm == null) {
      return GrowthZScoreResult(
        severity: WastingSeverity.normal,
        referenceDataSufficient: false,
        explanation: weightKg == null && heightCm == null
            ? 'Neither weight nor height was recorded, so weight-for-height '
                  'cannot be computed. Measure both at the next contact — and '
                  'use the MUAC tape today, which needs neither scales nor a '
                  'board.'
            : weightKg == null
                  ? 'Weight was not recorded, so weight-for-height cannot be '
                        'computed. Weigh the child at the next contact.'
                  : 'Height/length was not recorded, so weight-for-height '
                        'cannot be computed. Measure length (under 2 years) or '
                        'height at the next contact.',
      );
    }

    final lms = GrowthReference.interpolate(sex, heightCm);
    if (lms == null) {
      return GrowthZScoreResult(
        severity: WastingSeverity.normal,
        referenceDataSufficient: false,
        explanation: 'Height ${_fmt(heightCm)} cm is outside the bundled '
            'WHO reference range '
            '(${_fmt(GrowthReference.minHeight(sex))}–'
            '${_fmt(GrowthReference.maxHeight(sex))} cm). No z-score is '
            'produced rather than guess — use the MUAC tape and clinical '
            'judgement, and refer if there is any doubt.',
      );
    }

    final z = _zScore(weightKg, lms);
    final severity = _classify(z);

    final explanation = 'Weight ${_fmt(weightKg)} kg for height '
        '${_fmt(heightCm)} cm (${sex.label.toLowerCase()}) is '
        '${_fmt(z, decimals: 2)} SD from the WHO median of '
        '${_fmt(lms.m)} kg. '
        '${severity.meaning}';

    final findings = <ClinicalFinding>[];
    if (severity == WastingSeverity.severe ||
        severity == WastingSeverity.moderate ||
        severity == WastingSeverity.atRisk) {
      findings.add(
        ClinicalFinding(
          label: severity.label,
          detail: 'Weight-for-height z-score ${_fmt(z, decimals: 2)} is '
              '${z < _moderateCutOff ? 'below the −3 SD cut-off' : z < _atRiskCutOff ? 'below the −2 SD cut-off' : 'below the −1 SD line'}. '
              'Compared against the WHO median of ${_fmt(lms.m)} kg for a '
              '${sex.label.toLowerCase()} child of ${_fmt(heightCm)} cm. '
              'Confirm with the MUAC tape — the child is managed by whichever '
              'indicator is worse.',
          severity: severity.triage,
          protocolSource: _source,
          measuredValue: '${_fmt(weightKg)} kg, ${_fmt(heightCm)} cm',
          threshold: 'median ${_fmt(lms.m)} kg (z ${_fmt(z, decimals: 2)})',
          weight: severity == WastingSeverity.severe ? 1 : 0.5,
        ),
      );
    } else if (severity == WastingSeverity.possibleOverweight) {
      findings.add(
        ClinicalFinding(
          label: severity.label,
          detail: 'Weight-for-height z-score ${_fmt(z, decimals: 2)} is above '
              '+2 SD. Review feeding practices and growth over time; refer if '
              'persistent.',
          severity: severity.triage,
          protocolSource: _source,
          measuredValue: '${_fmt(weightKg)} kg, ${_fmt(heightCm)} cm',
          threshold: 'median ${_fmt(lms.m)} kg',
        ),
      );
    }

    return GrowthZScoreResult(
      severity: severity,
      zScore: z,
      medianWeightKg: lms.m,
      nutritionStatus: _toNutritionStatus(severity),
      referenceDataSufficient: true,
      explanation: explanation,
      findings: findings,
    );
  }

  /// The WHO LMS z-score. Exact published formula.
  static double _zScore(double x, LmsPoint lms) {
    final ratio = x / lms.m;
    if (lms.l == 0) {
      return math.log(ratio) / lms.s;
    }
    return (math.pow(ratio, lms.l) - 1) / (lms.l * lms.s);
  }

  static WastingSeverity _classify(double z) {
    if (z < _severeCutOff) return WastingSeverity.severe;
    if (z < _moderateCutOff) return WastingSeverity.moderate;
    if (z < _atRiskCutOff) return WastingSeverity.atRisk;
    if (z > _overweightCutOff) return WastingSeverity.possibleOverweight;
    return WastingSeverity.normal;
  }

  static NutritionStatus? _toNutritionStatus(WastingSeverity severity) =>
      switch (severity) {
        WastingSeverity.severe => NutritionStatus.severeAcute,
        WastingSeverity.moderate => NutritionStatus.moderateAcute,
        WastingSeverity.atRisk => NutritionStatus.atRisk,
        WastingSeverity.normal => NutritionStatus.normal,
        // Overweight is not on the acute-malnutrition axis; leave the shared
        // nutrition status unset rather than mislabel it.
        WastingSeverity.possibleOverweight => null,
      };

  static String _fmt(double v, {int decimals = 1}) => v.toStringAsFixed(decimals);
}
