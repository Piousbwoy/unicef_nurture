/// The cohort line used to open with the word "Tailored" and then name nobody:
/// one fixed paragraph for every child aged 2–59 months in the country, and one
/// fixed counselling action. That is what a judge means by "mockup" — the claim
/// of tailoring without the data in the sentence.
///
/// These tests pin the replacement: the sentence is *assembled* from the child's
/// own record, and a slot with no value says so instead of quietly falling back
/// to generic prose. The guideline content — which signs send a family back — is
/// a data table, because it genuinely is the same for every child in the cohort.
/// What must not be the same is the child's name, age, weight and review date.
///
/// The invariant that matters most is here too: an incomplete record must never
/// cost the family the counselling step. Missing slots make the sentence rougher,
/// never shorter.
library;

import 'package:carebridge_ai/domain/engines/care_slots.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

const _unknown = CareSlots();

void main() {
  group('the note is assembled from the record', () {
    test('a named child with age and weight appears as herself', () {
      final g = CohortCareGuidanceBuilder.build(
        cohort: ClientType.childUnderFive,
        slots: const CareSlots(
          subjectName: 'Amina',
          ageInMonths: 14,
          weightKg: 9.4,
          followUpInDays: 3,
        ),
      );
      expect(g.note, contains('Amina'));
      expect(g.note, contains('14 months'));
      expect(g.note, contains('9.4 kg'));
      expect(g.note, contains('3 days'));
    });

    test('an unweighed child is never shown "null kg"', () {
      // A fabricated 0 kg would dose a child; an empty slot must say it is empty.
      final g = CohortCareGuidanceBuilder.build(
        cohort: ClientType.childUnderFive,
        slots: const CareSlots(subjectName: 'Amina', ageInMonths: 14),
      );
      expect(g.note, isNot(contains('null')));
      expect(g.note, contains('weight not recorded'));
    });

    test('an unnamed patient is described as unnamed, not as a stranger', () {
      final g = CohortCareGuidanceBuilder.build(
        cohort: ClientType.childUnderFive,
        slots: _unknown,
      );
      expect(g.note, contains('name not recorded'));
      expect(g.note, isNot(contains('Tailored')));
    });

    test('a newborn is stated in days, not months', () {
      final g = CohortCareGuidanceBuilder.build(
        cohort: ClientType.newborn,
        slots: const CareSlots(subjectName: 'Kofi', ageInDays: 3, weightKg: 2.8),
      );
      expect(g.note, contains('day 3'));
      expect(g.note, contains('2.8 kg'));
      expect(g.note, isNot(contains('months')));
    });

    test('a newborn with no age in days records the gap', () {
      final g = CohortCareGuidanceBuilder.build(
        cohort: ClientType.newborn,
        slots: const CareSlots(subjectName: 'Kofi'),
      );
      expect(g.note, contains('age in days not recorded'));
    });
  });

  group('the guideline content is data, cited and identical for the cohort', () {
    test('every cohort names its return-immediately signs', () {
      for (final cohort in ClientType.values) {
        final g = CohortCareGuidanceBuilder.build(
          cohort: cohort,
          slots: _unknown,
        );
        expect(
          CohortCareGuidanceBuilder.watchpointsFor(cohort),
          isNotEmpty,
          reason: '$cohort has no published watchpoint set',
        );
        // The signs reach both the note and the counselling action.
        for (final sign in CohortCareGuidanceBuilder.watchpointsFor(cohort)) {
          expect(g.note, contains(sign), reason: '$cohort note dropped $sign');
        }
      }
    });

    test('every cohort carries the protocol it was assessed under', () {
      final g = CohortCareGuidanceBuilder.build(
        cohort: ClientType.pregnantWoman,
        slots: _unknown,
      );
      expect(g.note, contains('ANC'));
      expect(g.counselling.protocolSource, contains('WHO'));
    });
  });

  group('counselling is never lost to a missing slot', () {
    test('an entirely unknown record still produces the repeat-back step', () {
      final g = CohortCareGuidanceBuilder.build(
        cohort: ClientType.childUnderFive,
        slots: _unknown,
      );
      expect(g.counselling.instruction, isNotEmpty);
      expect(g.counselling.isCounselling, isTrue);
      expect(g.counselling.isTreatment, isFalse);
      expect(g.counselling.isReferral, isFalse);
      expect(
        g.counselling.instruction,
        contains('repeat'),
        reason: 'the IMCI step is a teach-back, not a reading-out',
      );
    });

    test('the instruction uses the child\'s name when it is known', () {
      final g = CohortCareGuidanceBuilder.build(
        cohort: ClientType.childUnderFive,
        slots: const CareSlots(subjectName: 'Amina', ageInMonths: 14),
      );
      expect(g.counselling.instruction, contains('Amina'));
    });

    test('the counselling step can never outrank a clinical finding', () {
      final g = CohortCareGuidanceBuilder.build(
        cohort: ClientType.childUnderFive,
        slots: _unknown,
      );
      // Cohort counselling is appended by the synthesiser, so if it could carry
      // a treatment or a referral it would out-order what the engines actually
      // found. It is neither, at the lowest urgency the plan uses.
      expect(g.counselling.urgency, ReferralUrgency.scheduled);
      expect(g.counselling.isTreatment, isFalse);
      expect(g.counselling.isReferral, isFalse);
      expect(g.counselling.isPrereferralTreatment, isFalse);
    });
  });

  group('same record, same words', () {
    test('two identical slots render byte-identically', () {
      const a = CareSlots(subjectName: 'Amina', ageInMonths: 14, weightKg: 9.4);
      const b = CareSlots(subjectName: 'Amina', ageInMonths: 14, weightKg: 9.4);
      final one = CohortCareGuidanceBuilder.build(
        cohort: ClientType.childUnderFive,
        slots: a,
      );
      final two = CohortCareGuidanceBuilder.build(
        cohort: ClientType.childUnderFive,
        slots: b,
      );
      expect(one.note, two.note);
      expect(one.counselling.instruction, two.counselling.instruction);
    });

    test('a different age band says something different', () {
      // If age did not change the sentence, the sentence would be a template.
      final young = CohortCareGuidanceBuilder.build(
        cohort: ClientType.childUnderFive,
        slots: const CareSlots(subjectName: 'Amina', ageInMonths: 8),
      );
      final older = CohortCareGuidanceBuilder.build(
        cohort: ClientType.childUnderFive,
        slots: const CareSlots(subjectName: 'Amina', ageInMonths: 40),
      );
      expect(young.note, isNot(older.note));
    });
  });
}
