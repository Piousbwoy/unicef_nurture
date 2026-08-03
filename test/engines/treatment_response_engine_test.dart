/// Treatment-response engine: weight-gain monitoring on therapeutic feeding.
///
/// Pins the CMAM thresholds that decide whether a child on OTP is responding:
/// ≥10 g/kg/day is a good response, 5–9.9 is slow, <5 is poor, and any weight
/// loss is treated as deterioration. Also pins the honesty rule that a rate
/// over fewer than three days is reported as "too early", not a number.
library;

import 'package:carebridge_ai/domain/engines/treatment_response_engine.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final day0 = DateTime(2026, 6, 1);

  GrowthResult assessAfter(double startKg, double currentKg, int days) =>
      TreatmentResponseEngine.assess(
        startWeightKg: startKg,
        startDate: day0,
        currentWeightKg: currentKg,
        currentDate: day0.add(Duration(days: days)),
      );

  group('TreatmentResponseEngine', () {
    test('a gain of at least 10 g/kg/day is a good response', () {
      // 8.0 → 8.84 kg over 7 days ≈ 14.3 g/kg/day.
      final result = assessAfter(8.0, 8.84, 7);

      expect(result.response, TreatmentResponse.good);
      expect(result.gainPerKgPerDay!, greaterThanOrEqualTo(10));
      expect(result.needsEscalation, isFalse);
      expect(result.findings, isNotEmpty);
      expect(result.actions, isNotEmpty);
    });

    test('a gain of 5–9.9 g/kg/day is a slow response', () {
      // 8.0 → 8.49 kg over 7 days ≈ 8.5 g/kg/day.
      final result = assessAfter(8.0, 8.49, 7);

      expect(result.response, TreatmentResponse.slow);
      expect(result.gainPerKgPerDay!, greaterThanOrEqualTo(5));
      expect(result.gainPerKgPerDay!, lessThan(10));
      expect(result.needsEscalation, isFalse);
    });

    test('a gain below 5 g/kg/day is a poor response needing escalation', () {
      // 8.0 → 8.21 kg over 7 days ≈ 3.7 g/kg/day.
      final result = assessAfter(8.0, 8.21, 7);

      expect(result.response, TreatmentResponse.poor);
      expect(result.gainPerKgPerDay!, lessThan(5));
      expect(result.needsEscalation, isTrue);
      expect(result.actions.any((a) => a.isReferral), isTrue);
    });

    test('weight loss on treatment is treated as deterioration', () {
      final result = assessAfter(8.0, 7.7, 7);

      expect(result.response, TreatmentResponse.weightLoss);
      expect(result.gainPerKgPerDay!, lessThan(0));
      expect(result.needsEscalation, isTrue);
      expect(result.actions.any((a) => a.isReferral), isTrue);
    });

    test('fewer than three days is reported as too early, not a rate', () {
      final result = assessAfter(8.0, 8.2, 2);

      expect(result.response, TreatmentResponse.insufficientData);
      expect(result.gainPerKgPerDay, isNull);
      expect(result.needsEscalation, isFalse);
    });

    test('the arithmetic is exposed for the CHO to check', () {
      final result = assessAfter(8.0, 8.84, 7);

      expect(result.totalGainKg, closeTo(0.84, 0.001));
      expect(result.daysObserved, 7);
      expect(result.explanation, contains('g/kg/day'));
    });
  });

  group('TreatmentResponseEngine.assessFromSeries', () {
    final start = DateTime(2026, 6, 1);
    final now = DateTime(2026, 6, 8); // seven days later

    GrowthMeasurement weight(double kg, DateTime at) => GrowthMeasurement(
      id: 'g-${at.millisecondsSinceEpoch}',
      personId: 'child-1',
      takenAt: at,
      weightKg: kg,
    );

    test('a child on a SAM programme gets a response verdict', () {
      final result = TreatmentResponseEngine.assessFromSeries(
        series: [weight(8.0, start)],
        current: weight(8.84, now), // ≈14.3 g/kg/day — a good response
        nutritionStatus: NutritionStatus.severeAcute,
      );

      expect(result, isNotNull);
      expect(result!.response, TreatmentResponse.good);
    });

    test('weight loss on a MAM programme is deterioration', () {
      final result = TreatmentResponseEngine.assessFromSeries(
        series: [weight(8.0, start)],
        current: weight(7.7, now),
        nutritionStatus: NutritionStatus.moderateAcute,
      );

      expect(result, isNotNull);
      expect(result!.response, TreatmentResponse.weightLoss);
      expect(result.needsEscalation, isTrue);
    });

    test('a well child is not labelled as responding to treatment', () {
      final result = TreatmentResponseEngine.assessFromSeries(
        series: [weight(8.0, start)],
        current: weight(8.84, now),
        nutritionStatus: NutritionStatus.normal,
      );

      expect(result, isNull);
    });

    test('no earlier weight means nothing to compare against', () {
      final result = TreatmentResponseEngine.assessFromSeries(
        series: const [],
        current: weight(8.84, now),
        nutritionStatus: NutritionStatus.severeAcute,
      );

      expect(result, isNull);
    });

    test('the most recent earlier weight is the comparison point', () {
      final result = TreatmentResponseEngine.assessFromSeries(
        series: [
          weight(6.0, DateTime(2026, 5, 1)), // older and lower — not the start
          weight(8.0, start), // most recent before now — this one wins
        ],
        current: weight(8.84, now),
        nutritionStatus: NutritionStatus.severeAcute,
      );

      expect(result, isNotNull);
      expect(result!.totalGainKg, closeTo(0.84, 0.001));
    });
  });
}

/// Local alias so the helper's return type reads clearly.
typedef GrowthResult = TreatmentResponseResult;
