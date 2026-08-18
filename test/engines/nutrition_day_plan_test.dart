/// The nutrition masterclass: the basket is not a shopping list, it is a
/// day. These tests pin the three upgrades that make the plan cookable
/// and defendable — the composed day plan, the nutrient-coverage audit,
/// and the diarrhoea response.
library;

import 'package:carebridge_ai/domain/engines/nutrition_engine.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NutritionEngine — the day\u2019s plate', () {
    test('a wasted 8-month-old gets meals, mashed, with fortification', () {
      final plan = NutritionEngine.plan(
        subject: NutritionSubject.child,
        status: NutritionStatus.moderateAcute,
        month: 9,
        ageMonths: 8,
      );

      expect(plan.dayPlan, isNotEmpty);
      expect(plan.dayPlan.first.moment, 'Breakfast');
      expect(plan.dayPlan.map((m) => m.moment), contains('Lunch'));
      expect(plan.dayPlan.map((m) => m.moment), contains('Dinner'));
      expect(plan.dayPlanNote, contains('Mash'));
      // Wasting earns the energy-fortification note on breakfast.
      expect(
        plan.dayPlan.first.note ?? '',
        contains('groundnut paste'),
      );
      // Every slot is fed from the basket — no empty plates.
      for (final slot in plan.dayPlan) {
        expect(slot.foods, isNotEmpty, reason: slot.moment);
      }
    });

    test('under six months the plate stays empty — breast milk only', () {
      final plan = NutritionEngine.plan(
        subject: NutritionSubject.child,
        status: NutritionStatus.atRisk,
        month: 5,
        ageMonths: 4,
        stillBreastfeeding: true,
      );

      expect(plan.dayPlan, isEmpty);
      expect(plan.dayPlanNote, contains('Breast milk only'));
    });

    test('SAM withholds the day plan — therapeutic food first', () {
      final plan = NutritionEngine.plan(
        subject: NutritionSubject.child,
        status: NutritionStatus.severeAcute,
        month: 9,
        ageMonths: 18,
        appetiteTestPassed: true,
        hasAnyDangerSign: false,
      );

      expect(plan.therapeuticFoodRequired, isTrue);
      expect(plan.dayPlan, isEmpty);
    });

    test('a mother gets three meals and the one she is owed', () {
      final plan = NutritionEngine.plan(
        subject: NutritionSubject.pregnantWoman,
        status: NutritionStatus.normal,
        month: 10,
        isAnaemic: true,
      );

      expect(plan.dayPlan.map((m) => m.moment), contains('Her extra meal'));
      expect(plan.dayPlanNote, contains('extra meal'));
    });

    test('the day plan and note survive JSON persistence', () {
      final plan = NutritionEngine.plan(
        subject: NutritionSubject.child,
        status: NutritionStatus.moderateAcute,
        month: 9,
        ageMonths: 14,
      );
      final json = plan.toJson();
      expect(json['day_plan'], isNotEmpty);
      expect(json['day_plan_note'], isNotNull);
      expect(json['nutrient_coverage'], isNotEmpty);
    });
  });

  group('NutritionEngine — the coverage audit', () {
    test('anaemia raises an Iron need, and the basket answers it', () {
      final plan = NutritionEngine.plan(
        subject: NutritionSubject.child,
        status: NutritionStatus.normal,
        month: 9,
        ageMonths: 20,
        isAnaemic: true,
      );

      expect(plan.nutrientCoverage['Iron'], isNotEmpty);
      expect(plan.nutrientCoverage['Vitamin C'], isNotEmpty);
    });

    test('a well child\u2019s coverage stays small — vitamin A alone', () {
      final plan = NutritionEngine.plan(
        subject: NutritionSubject.child,
        status: NutritionStatus.normal,
        month: 9,
        ageMonths: 20,
      );

      expect(plan.nutrientCoverage.containsKey('Iron'), isFalse);
    });
  });

  group('NutritionEngine — the diarrhoea response', () {
    test('diarrhoea adds the zinc + fluids + keep-feeding rules', () {
      final plan = NutritionEngine.plan(
        subject: NutritionSubject.child,
        status: NutritionStatus.normal,
        month: 9,
        ageMonths: 14,
        hasDiarrhoea: true,
        stillBreastfeeding: true,
      );

      expect(
        plan.feedingRules.any((r) => r.toLowerCase().contains('zinc')),
        isTrue,
      );
      expect(
        plan.feedingRules.any(
          (r) => r.toLowerCase().contains('breastfeed more often'),
        ),
        isTrue,
      );
    });

    test('no diarrhoea, no zinc rule', () {
      final plan = NutritionEngine.plan(
        subject: NutritionSubject.child,
        status: NutritionStatus.normal,
        month: 9,
        ageMonths: 14,
      );

      expect(
        plan.feedingRules.any((r) => r.toLowerCase().contains('zinc')),
        isFalse,
      );
    });
  });
}
