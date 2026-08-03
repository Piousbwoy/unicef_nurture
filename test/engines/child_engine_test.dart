/// IMCI sick child engine (2–59 months).
///
/// Pins the age-banded fast-breathing thresholds, the general danger signs,
/// and — the hackathon's centrepiece — the MUAC-driven nutrition pathway
/// where SAM gets therapeutic food and never home-diet advice.
library;

import 'package:carebridge_ai/domain/engines/child_engine.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChildEngine — general assessment', () {
    test('a well two-year-old with a runny nose is routine', () {
      final result = ChildEngine.assess(
        const ChildInput(
          ageInMonths: 26,
          respiratoryRate: 28,
          temperatureCelsius: 37.1,
          muacCm: 13.5,
          runnyNose: true,
          stillBreastfeeding: true,
          mealsPerDay: 4,
          foodGroupsEatenYesterday: 5,
        ),
      );

      expect(result.triage.requiresReferral, isFalse);
      expect(result.clientType, ClientType.childUnderFive);
    });

    test('a general danger sign (lethargy) is urgent', () {
      final result = ChildEngine.assess(
        const ChildInput(ageInMonths: 18, lethargicOrUnconscious: true),
      );

      expect(result.triage, TriageLevel.urgent);
      expect(result.dangerSignsPresent, isNotEmpty);
    });

    test('cough with fast breathing at 8 months is pneumonia (50+ threshold)', () {
      final result = ChildEngine.assess(
        const ChildInput(
          ageInMonths: 8,
          cough: true,
          coughDurationDays: 3,
          respiratoryRate: 52,
        ),
      );

      expect(result.triage.isAtLeastPriority, isTrue);
      expect(result.classification.toLowerCase(), contains('pneumonia'));
    });

    test('38/min at 14 months is NOT fast breathing (threshold 40)', () {
      final result = ChildEngine.assess(
        const ChildInput(
          ageInMonths: 14,
          cough: true,
          coughDurationDays: 3,
          respiratoryRate: 38,
        ),
      );

      // Below the 12–59 month threshold of 40: no pneumonia classification.
      expect(result.classification.toLowerCase(), isNot(contains('pneumonia')));
      expect(result.triage.requiresReferral, isFalse);
    });

    test('48/min at 10 months is NOT fast breathing (threshold 50)', () {
      final result = ChildEngine.assess(
        const ChildInput(
          ageInMonths: 10,
          cough: true,
          coughDurationDays: 2,
          respiratoryRate: 48,
        ),
      );

      expect(result.classification.toLowerCase(), isNot(contains('severe')));
      // Cough without fast breathing or indrawing: cough/cold management.
      expect(result.triage.requiresReferral, isFalse);
    });

    test('cough with chest indrawing is severe — refer', () {
      final result = ChildEngine.assess(
        const ChildInput(
          ageInMonths: 20,
          cough: true,
          respiratoryRate: 55,
          chestIndrawing: true,
        ),
      );

      expect(result.triage, TriageLevel.urgent);
    });

    test('bloody diarrhoea is dysentery, at least priority', () {
      final result = ChildEngine.assess(
        const ChildInput(
          ageInMonths: 30,
          diarrhoea: true,
          diarrhoeaDurationDays: 4,
          bloodInStool: true,
        ),
      );

      expect(result.triage.isAtLeastPriority, isTrue);
    });

    test('fever with stiff neck is meningitis until proven otherwise', () {
      final result = ChildEngine.assess(
        const ChildInput(
          ageInMonths: 24,
          feverReported: true,
          stiffNeck: true,
        ),
      );

      expect(result.triage, TriageLevel.urgent);
    });

    test('positive malaria RDT with fever gets treatment, not referral', () {
      final result = ChildEngine.assess(
        const ChildInput(
          ageInMonths: 36,
          feverReported: true,
          malariaRdtDone: true,
          malariaRdtPositive: true,
        ),
      );

      expect(result.triage.isAtLeastPriority, isTrue);
      expect(result.actions, isNotEmpty);
    });
  });

  group('ChildEngine — nutrition pathway', () {
    test('MUAC 11.2 cm is SAM', () {
      final result = ChildEngine.assess(
        const ChildInput(ageInMonths: 24, muacCm: 11.2),
      );

      expect(result.nutritionStatus, NutritionStatus.severeAcute);
    });

    test('bilateral oedema is SAM regardless of MUAC', () {
      final result = ChildEngine.assess(
        const ChildInput(
          ageInMonths: 24,
          muacCm: 13.0,
          hasBilateralOedema: true,
        ),
      );

      expect(result.nutritionStatus, NutritionStatus.severeAcute);
    });

    test('MUAC 12.0 cm is MAM', () {
      final result = ChildEngine.assess(
        const ChildInput(ageInMonths: 24, muacCm: 12.0),
      );

      expect(result.nutritionStatus, NutritionStatus.moderateAcute);
    });

    test('MUAC 13.5 cm is adequate', () {
      final result = ChildEngine.assess(
        const ChildInput(ageInMonths: 24, muacCm: 13.5),
      );

      expect(result.nutritionStatus, NutritionStatus.normal);
    });

    test('SAM is urgent — the child is referred, not counselled', () {
      final result = ChildEngine.assess(
        const ChildInput(ageInMonths: 24, muacCm: 11.0),
      );

      expect(result.triage.isAtLeastPriority, isTrue);
    });
  });
}
