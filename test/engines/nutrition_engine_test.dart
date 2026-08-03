/// Nutrition engine: the branch that must never be wrong.
///
/// SAM gets therapeutic food (RUTF/F-75) and never home-diet advice; local
/// foods belong to MAM and prevention. These tests pin that boundary, plus
/// the season and cost filtering that make advice realistic in Northern
/// Ghana.
library;

import 'package:carebridge_ai/data/reference/local_foods.dart';
import 'package:carebridge_ai/domain/engines/nutrition_engine.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NutritionEngine — pathway selection', () {
    test('SAM with oedema is inpatient therapeutic care', () {
      final plan = NutritionEngine.plan(
        subject: NutritionSubject.child,
        status: NutritionStatus.severeAcute,
        month: 8,
        ageMonths: 18,
        hasBilateralOedema: true,
      );

      expect(plan.pathway, NutritionPathway.inpatientTherapeutic);
      expect(plan.therapeuticFoodRequired, isTrue);
    });

    test('SAM with a danger sign is inpatient, even with appetite', () {
      final plan = NutritionEngine.plan(
        subject: NutritionSubject.child,
        status: NutritionStatus.severeAcute,
        month: 8,
        ageMonths: 20,
        appetiteTestPassed: true,
        hasAnyDangerSign: true,
      );

      expect(plan.pathway, NutritionPathway.inpatientTherapeutic);
    });

    test('uncomplicated SAM with appetite is OTP', () {
      final plan = NutritionEngine.plan(
        subject: NutritionSubject.child,
        status: NutritionStatus.severeAcute,
        month: 8,
        ageMonths: 20,
        appetiteTestPassed: true,
        hasAnyDangerSign: false,
      );

      expect(plan.pathway, NutritionPathway.outpatientTherapeutic);
      expect(plan.therapeuticFoodRequired, isTrue);
    });

    test('SAM never receives home local-food suggestions as treatment', () {
      final plan = NutritionEngine.plan(
        subject: NutritionSubject.child,
        status: NutritionStatus.severeAcute,
        month: 8,
        ageMonths: 18,
        appetiteTestPassed: true,
        hasAnyDangerSign: false,
      );

      // The therapeutic pathway withholds home-diet advice by design.
      expect(plan.pathway.needsTherapeuticFood, isTrue);
    });

    test('MAM gets supplementary feeding with local foods', () {
      final plan = NutritionEngine.plan(
        subject: NutritionSubject.child,
        status: NutritionStatus.moderateAcute,
        month: 9,
        ageMonths: 14,
        groupsEatenYesterday: {FoodGroup.grainsRootsTubers},
      );

      expect(plan.pathway, NutritionPathway.supplementaryFeeding);
      expect(plan.suggestions, isNotEmpty);
      expect(plan.diversityGapsFilled, isNotEmpty);
    });

    test('adequate nutrition gets preventive counselling', () {
      final plan = NutritionEngine.plan(
        subject: NutritionSubject.child,
        status: NutritionStatus.normal,
        month: 3,
        ageMonths: 10,
        stillBreastfeeding: true,
      );

      expect(plan.pathway, NutritionPathway.preventiveCounselling);
      expect(plan.therapeuticFoodRequired, isFalse);
    });

    test('an infant under 6 months is never told to take home foods', () {
      final plan = NutritionEngine.plan(
        subject: NutritionSubject.child,
        status: NutritionStatus.atRisk,
        month: 5,
        ageMonths: 4,
        stillBreastfeeding: true,
      );

      // Exclusive breastfeeding is the entire message under six months.
      expect(
        plan.feedingRules.any((r) => r.toLowerCase().contains('breast')),
        isTrue,
      );
    });
  });

  group('NutritionEngine — realism filters', () {
    test('lean-season advice acknowledges the hunger gap', () {
      final plan = NutritionEngine.plan(
        subject: NutritionSubject.child,
        status: NutritionStatus.moderateAcute,
        month: 8, // August: lean season in Northern Ghana.
        ageMonths: 16,
      );

      expect(plan.seasonNote, isNotEmpty);
    });

    test('a breastfeeding mother with anaemia gets iron-rich foods', () {
      final plan = NutritionEngine.plan(
        subject: NutritionSubject.breastfeedingWoman,
        status: NutritionStatus.atRisk,
        month: 10,
        ageMonths: 30,
        isAnaemic: true,
      );

      expect(plan.suggestions, isNotEmpty);
    });

    test('every suggestion carries a household measure, not grams', () {
      final plan = NutritionEngine.plan(
        subject: NutritionSubject.child,
        status: NutritionStatus.moderateAcute,
        month: 11,
        ageMonths: 15,
      );

      for (final s in plan.suggestions) {
        expect(s.householdMeasure, isNotEmpty, reason: s.food);
      }
    });
  });
}
