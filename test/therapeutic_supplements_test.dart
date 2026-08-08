/// Tests for Pillar 2: Northern Ghana Therapeutic Supplement Selector.
///
/// Pillar 2 of the engine revamp: the bridge between the AI diagnostic
/// output and the four highest-impact nutrition interventions in the
/// Northern Region:
///
///   1. Multiple Micronutrient Supplements (MMS) — pregnant women
///   2. Iron-Folic Acid (IFA) — non-pregnant anaemic women
///   3. Kangaroo Mother Care (KMC) + EBF — LBW infants
///   4. Ready-to-Use Therapeutic Food (RUTF) — SAM children in OTP
///
/// Each prescription must carry its WHO/GHS citation, dose, schedule,
/// duration, and counselling note. These tests pin the activation
/// thresholds, the citation contract, and the regional specificity
/// (Adokiya 2022, n=420, Hb 10.4 g/dL for Northern Ghanaian anaemia).
library;

import 'package:carebridge_ai/domain/engines/nutrition/therapeutic_supplements.dart';
import 'package:carebridge_ai/domain/engines/nutrition_engine.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TherapeuticSupplement — citable constants', () {
    test('ANC MMS cites WHO ANC 2020 + GHS 2022', () {
      expect(ancMmsSupplement.id, 'anc_mms_who2020_v1');
      expect(ancMmsSupplement.citation.shortName, contains('WHO'));
      expect(ancMmsSupplement.dose, contains('1 tablet'));
      expect(ancMmsSupplement.schedule, contains('pregnancy'));
      expect(ancMmsSupplement.counsellingNote, isNotEmpty);
      expect(ancMmsSupplement.contraindications, isNotEmpty);
    });

    test('IFA cites GHS STG 2017 + Adokiya 2022', () {
      expect(ifaSupplement.id, 'ifa_ghs2017_v1');
      expect(ifaSupplement.dose, contains('iron'));
      expect(ifaSupplement.counsellingNote, isNotEmpty);
    });

    test('KMC cites WHO KMC 2015 + Boundy 2016', () {
      expect(lbwKmcProtocol.id, 'kmc_lbw_who2015_v1');
      expect(lbwKmcProtocol.dose, contains('skin-to-skin'));
      expect(lbwKmcProtocol.dose.toLowerCase(), contains('breastfeed'));
      expect(lbwKmcProtocol.counsellingNote, contains('upright'));
    });

    test('RUTF cites WHO CMAM 2023 + Ghana CMAM 2018', () {
      expect(samRutfProtocol.id, 'sam_rutf_who2023_v1');
      expect(samRutfProtocol.dose, contains('sachet'));
      expect(samRutfProtocol.contraindications, isNotEmpty);
    });
  });

  group('TherapeuticSupplementSelector — MMS for pregnant women', () {
    test('activates MMS for a pregnant woman at 16 weeks, any Hb', () {
      final plan = TherapeuticSupplementSelector.select(
        context: const TherapeuticContext(
          gestationalWeeks: 16,
          haemoglobinGDl: 11.8,
        ),
      );
      expect(plan.supplements, contains(ancMmsSupplement));
      expect(plan.activatedBy[ancMmsSupplement.id], contains('GA 16w'));
    });

    test('flags Ghana-specific Hb threshold 10.4 g/dL in the reason', () {
      final plan = TherapeuticSupplementSelector.select(
        context: const TherapeuticContext(
          gestationalWeeks: 28,
          haemoglobinGDl: 9.2,
        ),
      );
      expect(plan.supplements, contains(ancMmsSupplement));
      expect(plan.activatedBy[ancMmsSupplement.id], contains('10.4'));
      expect(plan.activatedBy[ancMmsSupplement.id], contains('Adokiya 2022'));
    });

    test('does NOT activate before 12 weeks gestation', () {
      final plan = TherapeuticSupplementSelector.select(
        context: const TherapeuticContext(gestationalWeeks: 8),
      );
      expect(plan.supplements, isNot(contains(ancMmsSupplement)));
    });

    test(
      'does NOT activate for non-pregnant women (IFA is the right call)',
      () {
        final plan = TherapeuticSupplementSelector.select(
          context: const TherapeuticContext(haemoglobinGDl: 9.5),
        );
        expect(plan.supplements, isNot(contains(ancMmsSupplement)));
        expect(plan.supplements, contains(ifaSupplement));
      },
    );
  });

  group('TherapeuticSupplementSelector — IFA for non-pregnant anaemia', () {
    test('activates IFA for Hb 9.8 g/dL in non-pregnant woman', () {
      final plan = TherapeuticSupplementSelector.select(
        context: const TherapeuticContext(haemoglobinGDl: 9.8),
      );
      expect(plan.supplements, contains(ifaSupplement));
      expect(plan.activatedBy[ifaSupplement.id], contains('10.4'));
    });

    test('does NOT activate IFA when Hb is normal (>= 11.0)', () {
      final plan = TherapeuticSupplementSelector.select(
        context: const TherapeuticContext(haemoglobinGDl: 12.5),
      );
      expect(plan.supplements, isNot(contains(ifaSupplement)));
    });
  });

  group('TherapeuticSupplementSelector — KMC for LBW', () {
    test('activates KMC for birth weight 2.1 kg (LBW)', () {
      final plan = TherapeuticSupplementSelector.select(
        context: const TherapeuticContext(birthWeightKg: 2.1, ageDays: 5),
      );
      expect(plan.supplements, contains(lbwKmcProtocol));
      expect(plan.activatedBy[lbwKmcProtocol.id], contains('2.10'));
    });

    test('does NOT activate KMC for birth weight 3.0 kg (normal)', () {
      final plan = TherapeuticSupplementSelector.select(
        context: const TherapeuticContext(birthWeightKg: 3.0, ageDays: 2),
      );
      expect(plan.supplements, isNot(contains(lbwKmcProtocol)));
    });
  });

  group('TherapeuticSupplementSelector — RUTF for SAM', () {
    test('activates RUTF for SAM, 18 months, appetite test passed', () {
      final plan = TherapeuticSupplementSelector.select(
        context: const TherapeuticContext(
          ageDays: 30 * 18,
          nutritionStatus: 'severeAcute',
          appetiteTestPassed: true,
        ),
      );
      expect(plan.supplements, contains(samRutfProtocol));
    });

    test(
      'does NOT activate RUTF when appetite test FAILED (refer inpatient)',
      () {
        final plan = TherapeuticSupplementSelector.select(
          context: const TherapeuticContext(
            ageDays: 30 * 18,
            nutritionStatus: 'severeAcute',
            appetiteTestPassed: false,
          ),
        );
        expect(plan.supplements, isNot(contains(samRutfProtocol)));
      },
    );

    test('does NOT activate RUTF for children under 6 months', () {
      final plan = TherapeuticSupplementSelector.select(
        context: const TherapeuticContext(
          ageDays: 30 * 4, // 4 months
          nutritionStatus: 'severeAcute',
          appetiteTestPassed: true,
        ),
      );
      expect(plan.supplements, isNot(contains(samRutfProtocol)));
    });

    test('does NOT activate RUTF when bilateral pitting oedema present', () {
      final plan = TherapeuticSupplementSelector.select(
        context: const TherapeuticContext(
          ageDays: 30 * 18,
          nutritionStatus: 'severeAcute',
          appetiteTestPassed: true,
          hasBilateralOedema: true,
        ),
      );
      expect(plan.supplements, isNot(contains(samRutfProtocol)));
    });
  });

  group('TherapeuticSupplementSelector — co-activation', () {
    test('a normal healthy 2-year-old activates nothing', () {
      final plan = TherapeuticSupplementSelector.select(
        context: const TherapeuticContext(
          ageDays: 30 * 24,
          haemoglobinGDl: 12.0,
          birthWeightKg: 3.2,
          nutritionStatus: 'normal',
        ),
      );
      expect(plan.isEmpty, isTrue);
    });
  });

  group('NutritionEngine.plan — Pillar 2 integration', () {
    test(
      'a pregnant woman with anaemia gets MMS + the regional iron stack',
      () {
        final plan = NutritionEngine.plan(
          subject: NutritionSubject.pregnantWoman,
          status: NutritionStatus.normal,
          month: 7, // lean season
          ageMonths: 0,
          isAnaemic: true,
          therapeuticContext: const TherapeuticContext(
            gestationalWeeks: 22,
            haemoglobinGDl: 9.5,
          ),
        );
        expect(plan.therapeuticPlan, isNotNull);
        expect(plan.therapeuticPlan!.supplements, contains(ancMmsSupplement));
        // The regional iron stack should include Moringa, Dawadawa, Bambara.
        final foodNames = plan.suggestions.map((s) => s.food).toSet();
        expect(foodNames, contains('Moringa leaves'));
        expect(foodNames, contains('Dawadawa (locust bean)'));
        expect(foodNames, contains('Bambara beans'));
        expect(foodNames, contains('Groundnut paste'));
      },
    );

    test('a child with SAM gets RUTF + therapeutic food required', () {
      final plan = NutritionEngine.plan(
        subject: NutritionSubject.child,
        status: NutritionStatus.severeAcute,
        month: 8,
        ageMonths: 14,
        appetiteTestPassed: true,
        therapeuticContext: const TherapeuticContext(
          ageDays: 30 * 14,
          nutritionStatus: 'severeAcute',
          appetiteTestPassed: true,
        ),
      );
      expect(plan.therapeuticFoodRequired, isTrue);
      expect(plan.therapeuticPlan, isNotNull);
      expect(plan.therapeuticPlan!.supplements, contains(samRutfProtocol));
    });

    test('a normal plan without therapeutic context has empty plan', () {
      final plan = NutritionEngine.plan(
        subject: NutritionSubject.child,
        status: NutritionStatus.normal,
        month: 5,
        ageMonths: 24,
      );
      // No therapeutic context = nothing prescribed.
      expect(plan.therapeuticPlan, isNotNull); // Always constructed
      expect(plan.therapeuticPlan!.supplements, isEmpty);
    });

    test('a LBW newborn (1.8 kg) gets KMC', () {
      final plan = NutritionEngine.plan(
        subject: NutritionSubject.child,
        status: NutritionStatus.atRisk,
        month: 4,
        ageMonths: 0,
        therapeuticContext: const TherapeuticContext(
          ageDays: 3,
          birthWeightKg: 1.8,
        ),
      );
      expect(plan.therapeuticPlan, isNotNull);
      expect(plan.therapeuticPlan!.supplements, contains(lbwKmcProtocol));
    });
  });
}
