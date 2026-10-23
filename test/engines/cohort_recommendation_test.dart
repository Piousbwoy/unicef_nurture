/// Cohort awareness and result-driven counselling: the two upgrades that
/// stop the recommendation system from speaking one voice to every patient.
///
/// A 3-day-old, a 3-year-old and a pregnant mother with identical-looking
/// findings are not managed alike — the synthesizer must name the cohort,
/// carry the note assembled from *this* patient's record through persistence,
/// and fold in the cohort's watchpoint counselling. "Tailored" is a claim, not a
/// fact: what makes it true is the child's age, weight and review interval
/// appearing in the sentence, and an honest gap when they were never captured.
/// And the nutrition basket must change shape with the results: wasting buys
/// energy, anaemia buys iron, never a fixed list.
library;

import 'package:carebridge_ai/domain/engines/care_slots.dart';
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
      // The sentence is assembled, so the cohort is named by the protocol it was
      // assessed under and the watchpoints come from the cited sign table.
      expect(plan.cohortNote, contains('sick-young-infant protocol'));
      expect(plan.cohortNote, contains('feeding poorly'));
      expect(plan.cohortNote, contains('cold to touch'));
      expect(
        plan.actions.any((a) => a.isCounselling && a.instruction.contains('repeat')),
        isTrue,
      );
    });

    test('a record that carries the child\'s details puts them in the sentence', () {
      // This is the whole point of the change: the sentence differs per patient,
      // because it is built from this patient's record.
      final plan = RecommendationEngine.synthesize(
        results: [result(ClientType.childUnderFive)],
        slots: const CareSlots(
          subjectName: 'Amina',
          ageInMonths: 14,
          weightKg: 9.4,
          followUpInDays: 3,
        ),
      );
      expect(plan.cohortNote, contains('Amina'));
      expect(plan.cohortNote, contains('14 months'));
      expect(plan.cohortNote, contains('9.4 kg'));
      expect(
        plan.actions.any((a) => a.instruction.contains('Amina')),
        isTrue,
        reason: 'the teach-back must be about this child, not a child in general',
      );
    });

    test('an empty record declares its gaps and still keeps the counselling step', () {
      // Safety invariant: missing slots make the sentence rougher, never shorter.
      final plan = RecommendationEngine.synthesize(
        results: [result(ClientType.newborn)],
      );
      expect(plan.cohortNote, contains('name not recorded'));
      expect(plan.cohortNote, contains('weight not recorded'));
      expect(plan.cohortNote, isNot(contains('null')));
      expect(
        plan.actions.where((a) => a.isCounselling),
        isNotEmpty,
        reason: 'a nameless newborn must not lose the return-immediately step',
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
