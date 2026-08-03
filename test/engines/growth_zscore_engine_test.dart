/// Growth z-score engine: WHO weight-for-height (wasting) classification.
///
/// Pins the properties that make this safe to trust: the LMS arithmetic is
/// exact against the bundled reference, the WHO cut-offs classify correctly,
/// oedema overrides the number, and — critically — the engine declines to
/// compute rather than guess when data is missing or out of range.
library;

import 'package:carebridge_ai/domain/engines/growth_zscore_engine.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GrowthZScoreEngine', () {
    // Anchors use the official WHO 2006 weight-for-length LMS table. At the
    // 80.5 cm sample the boys parameters are L=-0.9047, M=10.8896, S=0.07653.

    test('a child at the WHO median has a z-score of zero', () {
      final result = GrowthZScoreEngine.assess(
        sex: Sex.male,
        weightKg: 10.88962699,
        heightCm: 80.5,
      );

      expect(result.referenceDataSufficient, isTrue);
      expect(result.zScore, isNotNull);
      expect(result.zScore!.abs(), lessThan(0.01));
      expect(result.severity, WastingSeverity.normal);
      expect(result.nutritionStatus, NutritionStatus.normal);
    });

    test('a very low weight-for-height is severe wasting (SAM)', () {
      final result = GrowthZScoreEngine.assess(
        sex: Sex.male,
        weightKg: 7.0,
        heightCm: 80.5,
      );

      expect(result.referenceDataSufficient, isTrue);
      expect(result.zScore!, lessThan(-3.0));
      expect(result.severity, WastingSeverity.severe);
      expect(result.nutritionStatus, NutritionStatus.severeAcute);
      expect(result.isAcuteMalnutrition, isTrue);
      expect(result.findings, isNotEmpty);
    });

    test('a low weight-for-height is moderate wasting (MAM)', () {
      final result = GrowthZScoreEngine.assess(
        sex: Sex.male,
        weightKg: 9.0,
        heightCm: 80.5,
      );

      expect(result.zScore!, greaterThanOrEqualTo(-3.0));
      expect(result.zScore!, lessThan(-2.0));
      expect(result.severity, WastingSeverity.moderate);
      expect(result.nutritionStatus, NutritionStatus.moderateAcute);
      expect(result.isAcuteMalnutrition, isTrue);
    });

    test('a mildly low weight-for-height is at risk, not malnutrition', () {
      final result = GrowthZScoreEngine.assess(
        sex: Sex.male,
        weightKg: 9.7,
        heightCm: 80.5,
      );

      expect(result.zScore!, greaterThanOrEqualTo(-2.0));
      expect(result.zScore!, lessThan(-1.0));
      expect(result.severity, WastingSeverity.atRisk);
      expect(result.nutritionStatus, NutritionStatus.atRisk);
      expect(result.isAcuteMalnutrition, isFalse);
    });

    test('a high weight-for-height flags possible overweight', () {
      final result = GrowthZScoreEngine.assess(
        sex: Sex.male,
        weightKg: 13.5,
        heightCm: 80.5,
      );

      expect(result.zScore!, greaterThan(2.0));
      expect(result.severity, WastingSeverity.possibleOverweight);
      // Overweight is not on the acute-malnutrition axis.
      expect(result.nutritionStatus, isNull);
    });

    test('interpolates between reference samples', () {
      // 81.0 cm sits halfway between the 80.5 and 81.5 cm samples; the median
      // interpolates to about 11.0 kg, so that weight should read z ≈ 0.
      final result = GrowthZScoreEngine.assess(
        sex: Sex.male,
        weightKg: 11.0,
        heightCm: 81.0,
      );

      expect(result.referenceDataSufficient, isTrue);
      expect(result.zScore!.abs(), lessThan(0.05));
      expect(result.severity, WastingSeverity.normal);
    });

    test('bilateral oedema is SAM regardless of the numbers', () {
      final result = GrowthZScoreEngine.assess(
        sex: Sex.male,
        weightKg: 10.7, // a "normal" weight — must not hide the oedema
        heightCm: 80,
        hasBilateralOedema: true,
      );

      expect(result.severity, WastingSeverity.severe);
      expect(result.nutritionStatus, NutritionStatus.severeAcute);
      expect(result.isAcuteMalnutrition, isTrue);
    });

    test('oedema overrides even a missing measurement', () {
      final result = GrowthZScoreEngine.assess(
        sex: Sex.female,
        weightKg: null,
        heightCm: null,
        hasBilateralOedema: true,
      );

      expect(result.severity, WastingSeverity.severe);
      expect(result.nutritionStatus, NutritionStatus.severeAcute);
    });

    test('a height outside the reference table yields no z-score', () {
      final tooShort = GrowthZScoreEngine.assess(
        sex: Sex.male,
        weightKg: 2.0,
        heightCm: 40, // below the 45 cm floor
      );
      final tooTall = GrowthZScoreEngine.assess(
        sex: Sex.male,
        weightKg: 17.0,
        heightCm: 105, // above the 103.5 cm ceiling
      );

      expect(tooShort.referenceDataSufficient, isFalse);
      expect(tooShort.zScore, isNull);
      expect(tooTall.referenceDataSufficient, isFalse);
      expect(tooTall.zScore, isNull);
    });

    test('missing weight or height yields no z-score', () {
      final noWeight = GrowthZScoreEngine.assess(
        sex: Sex.female,
        weightKg: null,
        heightCm: 80,
      );
      final noHeight = GrowthZScoreEngine.assess(
        sex: Sex.female,
        weightKg: 10.0,
        heightCm: null,
      );

      expect(noWeight.referenceDataSufficient, isFalse);
      expect(noWeight.zScore, isNull);
      expect(noHeight.referenceDataSufficient, isFalse);
      expect(noHeight.zScore, isNull);
    });

    test('girls use the girls reference', () {
      // At the 80.5 cm sample the girls median is 10.6892 kg.
      final result = GrowthZScoreEngine.assess(
        sex: Sex.female,
        weightKg: 10.6891553,
        heightCm: 80.5,
      );

      expect(result.zScore!.abs(), lessThan(0.01));
      expect(result.medianWeightKg, closeTo(10.6891553, 0.001));
    });
  });
}
