/// Tests for Pillar 3: UNICEF Nurturing Care Framework engine.
///
/// Pillar 3 of the engine revamp: integrates the five canonical
/// strategic actions of the WHO/UNICEF/World Bank 2018 Nurturing Care
/// Framework into the CareBridge AI result screen.
///
/// The framework's five pillars are the audited definition of what a
/// community-health visit *can* deliver for a child under five:
///
///   1. Good Health
///   2. Adequate Nutrition
///   3. Responsive Caregiving
///   4. Opportunities for Early Learning
///   5. Security and Safety
///
/// These tests pin:
///   - the exact set of pillars (no 6th pillar is invented)
///   - that every action carries a citation
///   - that pregnancy / postpartum / young infant / child visits all
///     produce appropriate actions per the framework
///   - that the pillar summaries report coverage
library;

import 'package:carebridge_ai/domain/engines/immunisation_engine.dart';
import 'package:carebridge_ai/domain/engines/nurturing_care_engine.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NurturingCarePillar — canonical five', () {
    test('exactly five pillars, in canonical order', () {
      expect(NurturingCarePillar.values.length, 5);
      expect(NurturingCarePillar.values.map((p) => p.name).toList(), [
        'goodHealth',
        'adequateNutrition',
        'responsiveCaregiving',
        'earlyLearning',
        'securityAndSafety',
      ]);
    });

    test('every pillar has a non-empty display name and short description', () {
      for (final p in NurturingCarePillar.values) {
        expect(p.displayName, isNotEmpty);
        expect(p.shortDescription, isNotEmpty);
      }
    });
  });

  group('NurturingCareEngine — a routine 2-year-old visit', () {
    final assessment = NurturingCareEngine.assess(
      context: const NurturingCareContext(
        clientType: ClientType.childUnderFive,
        ageMonths: 24,
      ),
    );

    test('produces non-empty action list', () {
      expect(assessment.actions, isNotEmpty);
    });

    test('covers all five pillars', () {
      final pillars = assessment.actions.map((a) => a.pillar).toSet();
      expect(pillars, containsAll(NurturingCarePillar.values));
    });

    test('every action carries a citation', () {
      for (final a in assessment.actions) {
        expect(a.citation.shortName, isNotEmpty);
        expect(a.citation.fullCitation, isNotEmpty);
        expect(a.citation.publishedYear, lessThanOrEqualTo(2026));
      }
    });

    test('every action has a non-empty counselling note', () {
      for (final a in assessment.actions) {
        expect(a.title, isNotEmpty);
        expect(a.counsellingNote, isNotEmpty);
      }
    });

    test('pillar summaries cover all 5 pillars', () {
      expect(
        assessment.pillarSummaries.keys,
        containsAll(NurturingCarePillar.values),
      );
    });
  });

  group('NurturingCareEngine — pregnancy triggers ANC birth preparedness', () {
    final assessment = NurturingCareEngine.assess(
      context: const NurturingCareContext(
        clientType: ClientType.pregnantWoman,
        ageMonths: 0,
      ),
    );

    test('includes ANC + birth preparedness action', () {
      expect(
        assessment.actions.any(
          (a) =>
              a.pillar == NurturingCarePillar.goodHealth &&
              a.title.toLowerCase().contains('birth preparedness'),
        ),
        isTrue,
      );
    });

    test('includes maternal MMS / IFA action', () {
      expect(
        assessment.actions.any(
          (a) =>
              a.pillar == NurturingCarePillar.adequateNutrition &&
              a.title.contains('MMS'),
        ),
        isTrue,
      );
    });
  });

  group('NurturingCareEngine — postpartum triggers EPDS mental health', () {
    final assessment = NurturingCareEngine.assess(
      context: const NurturingCareContext(
        clientType: ClientType.postpartumWoman,
        ageMonths: 0,
      ),
    );

    test('includes 2-item EPDS mental health action', () {
      expect(
        assessment.actions.any(
          (a) =>
              a.title.contains('mental-health') ||
              a.title.contains('mental health'),
        ),
        isTrue,
      );
    });
  });

  group('NurturingCareEngine — young infant < 2 months', () {
    test('exclusively breastfed action delivered', () {
      final assessment = NurturingCareEngine.assess(
        context: const NurturingCareContext(
          clientType: ClientType.newborn,
          ageMonths: 1,
          stillBreastfeeding: true,
        ),
      );
      final ebf = assessment.actions.firstWhere(
        (a) => a.title.toLowerCase().contains('exclusive breastfeeding'),
        orElse: () => const NurturingCareAction(
          pillar: NurturingCarePillar.adequateNutrition,
          title: '',
          counsellingNote: '',
          citation: PillarCitation(
            shortName: '',
            fullCitation: '',
            publishedYear: 0,
          ),
        ),
      );
      expect(ebf.deliveredAtVisit, isTrue);
    });

    test('safe sleep action present', () {
      final assessment = NurturingCareEngine.assess(
        context: const NurturingCareContext(
          clientType: ClientType.newborn,
          ageMonths: 1,
        ),
      );
      expect(
        assessment.actions.any(
          (a) =>
              a.pillar == NurturingCarePillar.securityAndSafety &&
              a.title.toLowerCase().contains('safe sleep'),
        ),
        isTrue,
      );
    });
  });

  group('NurturingCareEngine — overdue immunisation', () {
    test('catch-up immunisation action generated when due', () {
      // 14 months, no doses given → many items will be due/overdue.
      final imm = ImmunisationEngine.plan(
        ageInDays: 30 * 14,
        givenLabels: const {},
      );
      final itemsDueOrOverdue = [
        ...imm.giveToday.map(
          (dose) => ImmunisationItem(
            dose: dose,
            status: ImmunisationStatus.dueToday,
            detail: 'due',
          ),
        ),
        ...imm.overdue,
      ];
      final assessment = NurturingCareEngine.assess(
        context: NurturingCareContext(
          clientType: ClientType.childUnderFive,
          ageMonths: 14,
          immunisationItems: itemsDueOrOverdue,
        ),
      );
      final hasCatchUp = assessment.actions.any(
        (a) =>
            a.pillar == NurturingCarePillar.goodHealth &&
            a.title.toLowerCase().contains('catch-up'),
      );
      expect(hasCatchUp, isTrue);
    });
  });

  group('NurturingCareEngine — deduplication and stability', () {
    test('the same input produces the same actions', () {
      final a1 = NurturingCareEngine.assess(
        context: const NurturingCareContext(
          clientType: ClientType.childUnderFive,
          ageMonths: 24,
        ),
      );
      final a2 = NurturingCareEngine.assess(
        context: const NurturingCareContext(
          clientType: ClientType.childUnderFive,
          ageMonths: 24,
        ),
      );
      expect(a1.actions.length, a2.actions.length);
      for (var i = 0; i < a1.actions.length; i++) {
        expect(a1.actions[i].title, a2.actions[i].title);
        expect(a1.actions[i].pillar, a2.actions[i].pillar);
      }
    });
  });
}
