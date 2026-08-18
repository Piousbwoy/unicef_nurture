/// Cohort awareness and result-driven counselling: the two upgrades that
/// stop the recommendation system from speaking one voice to every patient.
///
/// A 3-day-old, a 3-year-old and a pregnant mother with identical-looking
/// findings are not managed alike — the synthesizer must name the cohort,
/// carry its tailored note through persistence, and fold in the cohort's
/// own watchpoint counselling. And the nutrition basket must change shape
/// with the results: wasting buys energy, anaemia buys iron, never a
/// fixed list.
library;

import 'package:carebridge_ai/domain/engines/nutrition_engine.dart';
import 'package:carebridge_ai/domain/engines/recommendation_engine.dart';
import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

AssessmentResult result(
  ClientType type, {
  TriageLevel triage = TriageLevel.routine,
}) => AssessmentResult(
  clientType: type,
  triage: triage,
  classification: 'TEST COHORT',
  findings: const [],
  actions: const [],
  confidence: RecommendationConfidence.high,
);

void main() {
  group('RecommendationEngine — cohort awareness', () {
    test('a newborn plan names its cohort and its watchpoints', () {
      final plan = RecommendationEngine.synthesize(
        results: [result(ClientType.newborn)],
      );
      expect(plan.patientCohort, ClientType.newborn);
      expect(plan.cohortNote, contains('young infant'));
      expect(
        plan.actions.any(
          (a) => a.instruction.contains('Watch the young infant'),
        ),
        isTrue,
      );
    });

    test('a pregnant plan carries the ANC danger-sign counselling', () {
      final plan = RecommendationEngine.synthesize(
        results: [result(ClientType.pregnantWoman)],
      );
      expect(plan.patientCohort, ClientType.pregnantWoman);
      expect(plan.cohortNote, contains('ANC'));
      expect(
        plan.actions.any(
          (a) => a.instruction.contains('reduced fetal movements'),
        ),
        isTrue,
      );
    });

    test('the most acute patient governs the cohort', () {
      final plan = RecommendationEngine.synthesize(
        results: [
          result(ClientType.pregnantWoman),
          result(ClientType.newborn, triage: TriageLevel.urgent),
        ],
      );
      expect(plan.patientCohort, ClientType.newborn);
    });

    test('JSON round-trip preserves cohort and note', () {
      final original = RecommendationEngine.synthesize(
        results: [result(ClientType.childUnderFive)],
      );
      final round = CarePlan.fromJson(original.toJson());
      expect(round.patientCohort, original.patientCohort);
      expect(round.cohortNote, original.cohortNote);
    });

    test('a legacy record without cohort fields loads with a null cohort', () {
      final plan = RecommendationEngine.synthesize(
        results: [result(ClientType.newborn)],
      );
      final json = Map<String, Object?>.from(plan.toJson())
        ..remove('patient_cohort')
        ..remove('cohort_note');
      expect(CarePlan.fromJson(json).patientCohort, isNull);
      expect(CarePlan.fromJson(json).cohortNote, isNull);
    });
  });

  group('NutritionEngine — result-driven basket', () {
    test('wasting steers the basket to energy, and the reason says so', () {
      final plan = NutritionEngine.plan(
        subject: NutritionSubject.child,
        status: NutritionStatus.moderateAcute,
        month: 9,
        ageMonths: 20,
      );
      expect(plan.suggestions, isNotEmpty);
      expect(
        plan.suggestions.any(
          (s) => s.reason.toLowerCase().contains('energy-dense'),
        ),
        isTrue,
      );
    });

    test('anaemia steers the basket to iron, and the reason says so', () {
      final plan = NutritionEngine.plan(
        subject: NutritionSubject.child,
        status: NutritionStatus.normal,
        month: 9,
        ageMonths: 20,
        isAnaemic: true,
      );
      expect(plan.suggestions, isNotEmpty);
      expect(
        plan.suggestions.any(
          (s) => s.reason.toLowerCase().contains('anaemia'),
        ),
        isTrue,
      );
    });

    test('different results give different baskets', () {
      final wasted = NutritionEngine.plan(
        subject: NutritionSubject.child,
        status: NutritionStatus.moderateAcute,
        month: 9,
        ageMonths: 20,
      );
      final anaemic = NutritionEngine.plan(
        subject: NutritionSubject.child,
        status: NutritionStatus.normal,
        month: 9,
        ageMonths: 20,
        isAnaemic: true,
      );
      final wastedFoods = wasted.suggestions.map((s) => s.food).join('|');
      final anaemicFoods = anaemic.suggestions.map((s) => s.food).join('|');
      expect(wastedFoods, isNot(equals(anaemicFoods)));
    });

    test("the regional iron anchors stay in an anaemic mother's basket", () {
      final plan = NutritionEngine.plan(
        subject: NutritionSubject.pregnantWoman,
        status: NutritionStatus.normal,
        month: 7, // lean season — the anchors must survive it
        isAnaemic: true,
      );
      final foods = plan.suggestions.map((s) => s.food).toSet();
      expect(foods, contains('Moringa leaves'));
      expect(foods, contains('Dawadawa (locust bean)'));
      expect(foods, contains('Bambara beans'));
      expect(foods, contains('Groundnut paste'));
    });
  });
}
