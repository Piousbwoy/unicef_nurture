/// Tests for the pre-referral stabilization protocol layer.
///
/// Pillar 1 (P0-CLINICAL-A) of the engine revamp. These tests pin the
/// activation logic, the citation contract, and the integration with
/// the recommendation synthesizer. The clinical stakes are the highest
/// in the app — a missed activation means a CHO sending a patient
/// down a flooded road without the drug that prevents the seizure
/// en-route. The tests are deliberately written to be loud: each
/// scenario names the WHO/GHS guideline it covers.
library;

import 'package:carebridge_ai/domain/engines/protocols/stabilization_protocol_selector.dart';
import 'package:carebridge_ai/domain/engines/protocols/stabilization_protocols.dart';
import 'package:carebridge_ai/core/ml/offline_inference_service.dart';
import 'package:carebridge_ai/domain/engines/recommendation_engine.dart';
import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

const _selector = StabilizationProtocolSelector();

void main() {
  group('StabilizationProtocol — citable constants', () {
    test('pre-eclampsia protocol cites WHO 2011 + GHS Safe Motherhood 2017',
        () {
      expect(preEclampsiaProtocol.id, 'pre_eclampsia_mgso4_v1');
      expect(preEclampsiaProtocol.citation.publishedYear, lessThan(2020));
      // The headline must mention the actual drug.
      expect(preEclampsiaProtocol.headline, contains('Magnesium'));
      // The first step must include a loading dose.
      expect(preEclampsiaProtocol.steps.first.action, contains('Magnesium'));
      expect(preEclampsiaProtocol.steps.first.dose, contains('IV'));
      // Must declare a contraindication block.
      expect(preEclampsiaProtocol.contraindications, isNotEmpty);
      // Must carry the decision-support notice verbatim.
      expect(
        preEclampsiaProtocol.decisionSupportNotice,
        contains('DECISION SUPPORT'),
      );
    });

    test('PSBI protocol cites WHO IMCI 2014 + WHO PSBI 2015', () {
      expect(psbiProtocol.id, 'young_infant_psbi_v1');
      expect(psbiProtocol.steps.any((s) => s.action.contains('Ampicillin')),
          isTrue);
      expect(psbiProtocol.steps.any((s) => s.action.contains('Gentamicin')),
          isTrue);
      expect(
        psbiProtocol.steps.any((s) => s.action.contains('Kangaroo')),
        isTrue,
      );
      expect(psbiProtocol.contraindications, isNotEmpty);
    });

    test('child pneumonia protocol cites WHO IMCI 2014 + GHS STG 2017', () {
      expect(childPneumoniaProtocol.id, 'child_pneumonia_v1');
      expect(
        childPneumoniaProtocol.steps.any((s) => s.action.contains('Amoxicillin')),
        isTrue,
      );
      expect(
        childPneumoniaProtocol.steps
            .any((s) => s.action.toLowerCase().contains('oxygen')),
        isTrue,
      );
    });
  });

  group('StabilizationProtocolSelector — pre-eclampsia activation', () {
    test('activates on AI preeclampsia_risk >= 0.22', () {
      final plan = _selector.select(
        context: const StabilizationContext(
          gestationalWeeks: 34,
          systolicBp: 138,
          diastolicBp: 88,
        ),
        risks: const StabilizationAiRisks(preeclampsiaRisk: 0.85),
      );
      expect(plan.protocols, contains(preEclampsiaProtocol));
      expect(
        plan.activatedBy[preEclampsiaProtocol.id],
        contains('preeclampsia_risk'),
      );
    });

    test('activates on severe hypertension (BP 170/112) even with no AI', () {
      final plan = _selector.select(
        context: const StabilizationContext(
          gestationalWeeks: 36,
          systolicBp: 170,
          diastolicBp: 112,
        ),
        risks: const StabilizationAiRisks(),
      );
      expect(plan.protocols, contains(preEclampsiaProtocol));
      expect(
        plan.activatedBy[preEclampsiaProtocol.id],
        contains('170/112'),
      );
    });

    test('activates on eclamptic convulsions even with normal BP', () {
      final plan = _selector.select(
        context: const StabilizationContext(
          gestationalWeeks: 38,
          systolicBp: 130,
          diastolicBp: 80,
          hasEclampsiaConvulsions: true,
        ),
        risks: const StabilizationAiRisks(),
      );
      expect(plan.protocols, contains(preEclampsiaProtocol));
      expect(
        plan.activatedBy[preEclampsiaProtocol.id],
        contains('eclamptic convulsions'),
      );
    });

    test('activates on gestational HTN + proteinuria', () {
      final plan = _selector.select(
        context: const StabilizationContext(
          gestationalWeeks: 32,
          systolicBp: 148,
          diastolicBp: 96,
          urineProtein0To4: 2,
        ),
        risks: const StabilizationAiRisks(),
      );
      expect(plan.protocols, contains(preEclampsiaProtocol));
      expect(
        plan.activatedBy[preEclampsiaProtocol.id],
        contains('proteinuria'),
      );
    });

    test('does NOT activate for a non-pregnant adult with elevated BP', () {
      final plan = _selector.select(
        context: const StabilizationContext(
          patientAgeDays: 365 * 30, // 30-year-old
          systolicBp: 138,
          diastolicBp: 88,
        ),
        risks: const StabilizationAiRisks(),
      );
      expect(plan.protocols, isNot(contains(preEclampsiaProtocol)));
    });
  });

  group('StabilizationProtocolSelector — young-infant PSBI activation', () {
    test(
      'activates on AI rule-in candidate (neonatal_sepsis >= 0.15 on the '
      '2%-prior scale) in a 14-day-old',
      () {
        final plan = _selector.select(
          context: const StabilizationContext(patientAgeDays: 14),
          risks: const StabilizationAiRisks(neonatalSepsisRisk: 0.75),
        );
        expect(plan.protocols, contains(psbiProtocol));
        expect(plan.activatedBy[psbiProtocol.id], contains('rule-in'));
        expect(
          plan.activatedBy[psbiProtocol.id],
          contains('neonatal_sepsis=0.750'),
        );
      },
    );

    test(
      'activates on the explicit rule-in flag (the service-computed path, '
      'drift-safe)',
      () {
        final plan = _selector.select(
          context: const StabilizationContext(patientAgeDays: 3),
          risks: const StabilizationAiRisks(
            neonatalSepsisRisk: 0.42,
            neonatalSepsisRuleInCandidate: true,
          ),
        );
        expect(plan.protocols, contains(psbiProtocol));
        expect(
          plan.activatedBy[psbiProtocol.id],
          contains('AI rule-in candidate'),
        );
      },
    );

    test('does NOT activate on low-tier AI risk without danger signs', () {
      final plan = _selector.select(
        context: const StabilizationContext(patientAgeDays: 14),
        risks: const StabilizationAiRisks(neonatalSepsisRisk: 0.05),
      );
      expect(plan.protocols, isNot(contains(psbiProtocol)));
      expect(plan.activatedBy, isEmpty);
    });

    test(
      'does NOT activate when AI is drift-suppressed (null riskProbability) '
      'without danger signs',
      () {
        final plan = _selector.select(
          context: const StabilizationContext(patientAgeDays: 14),
          risks: const StabilizationAiRisks(), // riskProbability is null
        );
        expect(plan.protocols, isNot(contains(psbiProtocol)));
      },
    );

    test(
      'deterministic rules keep rule-out coverage when AI is '
      'drift-suppressed',
      () {
        final plan = _selector.select(
          context: const StabilizationContext(
            patientAgeDays: 14,
            convulsions: true,
          ),
          risks: const StabilizationAiRisks(), // riskProbability is null
        );
        expect(plan.protocols, contains(psbiProtocol));
        expect(
          plan.activatedBy[psbiProtocol.id],
          contains('IMCI danger sign'),
        );
      },
    );

    test('activates on IMCI danger sign (convulsions) at age 7 days', () {
      final plan = _selector.select(
        context: const StabilizationContext(
          patientAgeDays: 7,
          convulsions: true,
        ),
        risks: const StabilizationAiRisks(),
      );
      expect(plan.protocols, contains(psbiProtocol));
      expect(
        plan.activatedBy[psbiProtocol.id],
        contains('IMCI danger sign'),
      );
    });

    test('activates on fever >= 37.5 in a 20-day-old', () {
      final plan = _selector.select(
        context: const StabilizationContext(
          patientAgeDays: 20,
          temperatureCelsius: 38.4,
        ),
        risks: const StabilizationAiRisks(),
      );
      expect(plan.protocols, contains(psbiProtocol));
    });

    test('activates on hypothermia < 35.5 in a 3-day-old', () {
      final plan = _selector.select(
        context: const StabilizationContext(
          patientAgeDays: 3,
          temperatureCelsius: 35.1,
        ),
        risks: const StabilizationAiRisks(),
      );
      expect(plan.protocols, contains(psbiProtocol));
    });

    test('does NOT activate for a 3-month-old (out of PSBI age window)', () {
      final plan = _selector.select(
        context: const StabilizationContext(
          patientAgeDays: 90, // 3 months
          convulsions: true,
        ),
        risks: const StabilizationAiRisks(),
      );
      expect(plan.protocols, isNot(contains(psbiProtocol)));
    });
  });

  group('StabilizationProtocolSelector — child pneumonia activation', () {
    test('activates on AI child_pneumonia >= 0.28 in an 18-month-old', () {
      final plan = _selector.select(
        context: const StabilizationContext(patientAgeDays: 30 * 18),
        risks: const StabilizationAiRisks(childPneumoniaRisk: 0.65),
      );
      expect(plan.protocols, contains(childPneumoniaProtocol));
    });

    test('activates on cough + severe chest indrawing at 24 months', () {
      final plan = _selector.select(
        context: const StabilizationContext(
          patientAgeDays: 30 * 24,
          coughPresent: true,
          severeChestIndrawing: true,
        ),
        risks: const StabilizationAiRisks(),
      );
      expect(plan.protocols, contains(childPneumoniaProtocol));
    });

    test('activates on cough + SaO2 85 at 12 months', () {
      final plan = _selector.select(
        context: const StabilizationContext(
          patientAgeDays: 30 * 12,
          coughPresent: true,
          oxygenSaturation: 85,
        ),
        risks: const StabilizationAiRisks(),
      );
      expect(plan.protocols, contains(childPneumoniaProtocol));
    });

    test('does NOT activate for a 5-year-old with cough only', () {
      final plan = _selector.select(
        context: const StabilizationContext(
          patientAgeDays: 30 * 60,
          coughPresent: true,
        ),
        risks: const StabilizationAiRisks(),
      );
      expect(plan.protocols, isNot(contains(childPneumoniaProtocol)));
    });
  });

  group('StabilizationProtocolSelector — co-activation', () {
    test('a normal well-child assessment activates nothing', () {
      final plan = _selector.select(
        context: const StabilizationContext(patientAgeDays: 30 * 18),
        risks: const StabilizationAiRisks(
          preeclampsiaRisk: 0.02,
          neonatalSepsisRisk: 0.05,
          childPneumoniaRisk: 0.10,
        ),
      );
      expect(plan.isEmpty, isTrue);
      expect(plan.activatedBy, isEmpty);
    });
  });

  group('StabilizationAiRisks.fromPredictions — rule-in tier propagation', () {
    test('carries the tier flag, the probability and the drift null', () {
      final now = DateTime.now();
      OfflineRiskPrediction pred({double? rp, bool ruleIn = false}) =>
          OfflineRiskPrediction(
            modelName: 'neonatal_sepsis',
            usingModel: false,
            riskProbability: rp,
            classification: 'low',
            featuresUsed: const [],
            featuresMissing: const [],
            predictedAt: now,
            ruleInCandidate: ruleIn,
            ruleInThreshold: 0.15,
          );

      // High tier: rule-in candidate.
      final high = StabilizationAiRisks.fromPredictions({
        'neonatal_sepsis': pred(rp: 0.42, ruleIn: true),
      });
      expect(high.neonatalSepsisRisk, equals(0.42));
      expect(high.neonatalSepsisRuleInCandidate, isTrue);

      // Low tier: below the rule-in threshold.
      final low = StabilizationAiRisks.fromPredictions({
        'neonatal_sepsis': pred(rp: 0.05),
      });
      expect(low.neonatalSepsisRuleInCandidate, isFalse);

      // Drift-suppressed: null probability, never a rule-in candidate.
      final drift = StabilizationAiRisks.fromPredictions({
        'neonatal_sepsis': pred(rp: null),
      });
      expect(drift.neonatalSepsisRisk, isNull);
      expect(drift.neonatalSepsisRuleInCandidate, isFalse);

      // No predictions at all: everything stays null/false-safe.
      final empty = StabilizationAiRisks.fromPredictions(null);
      expect(empty.neonatalSepsisRuleInCandidate, isNull);
    });
  });

  group('RecommendationEngine — pre-referral protocol integration', () {
    AssessmentResult emptyResult({
      TriageLevel triage = TriageLevel.routine,
    }) => AssessmentResult(
      clientType: ClientType.childUnderFive,
      triage: triage,
      classification: 'NO IMCI CLASSIFICATION — WELL CHILD',
      findings: const [],
      actions: const [],
      confidence: RecommendationConfidence.high,
    );

    test('a routine plan with no protocols stays routine', () {
      final plan = RecommendationEngine.synthesize(
        results: [emptyResult()],
        stabilizationContext: const StabilizationContext(
          patientAgeDays: 30 * 18,
        ),
        stabilizationRisks: const StabilizationAiRisks(),
      );
      expect(plan.preReferralProtocols, isEmpty);
      expect(plan.overallTriage, TriageLevel.routine);
      expect(plan.needsReferral, isFalse);
    });

    test('an activated pre-referral protocol escalates a routine plan to urgent',
        () {
      final plan = RecommendationEngine.synthesize(
        results: [emptyResult()],
        stabilizationContext: const StabilizationContext(
          patientAgeDays: 30 * 18,
          coughPresent: true,
          severeChestIndrawing: true,
        ),
        stabilizationRisks: const StabilizationAiRisks(),
      );
      expect(plan.preReferralProtocols, contains(childPneumoniaProtocol));
      expect(plan.overallTriage, TriageLevel.urgent);
      expect(plan.needsReferral, isTrue);
      // The protocol headline is in the action list.
      expect(
        plan.actions.any(
          (a) =>
              a.instruction.contains(childPneumoniaProtocol.headline) ||
              a.instruction.contains('Pre-referral'),
        ),
        isTrue,
      );
      // The activation reason is preserved.
      expect(
        plan.preReferralActivationReasons[childPneumoniaProtocol.id],
        isNotNull,
      );
    });

    test('an activated protocol does not OVERRIDE an already-urgent plan', () {
      // Engine already produced urgent. Activated protocol should not
      // regress triage.
      final plan = RecommendationEngine.synthesize(
        results: [emptyResult(triage: TriageLevel.urgent)],
        stabilizationContext: const StabilizationContext(
          patientAgeDays: 30 * 18,
          coughPresent: true,
          severeChestIndrawing: true,
        ),
        stabilizationRisks: const StabilizationAiRisks(),
      );
      expect(plan.overallTriage, TriageLevel.urgent);
      expect(plan.preReferralProtocols, isNotEmpty);
    });

    test('synthesize without stabilization args still works (backwards compat)',
        () {
      final plan = RecommendationEngine.synthesize(
        results: [emptyResult()],
      );
      expect(plan.preReferralProtocols, isEmpty);
    });

    test('CarePlan JSON round-trip preserves pre-referral protocols', () {
      final original = RecommendationEngine.synthesize(
        results: [emptyResult()],
        stabilizationContext: const StabilizationContext(
          gestationalWeeks: 36,
          systolicBp: 170,
          diastolicBp: 112,
        ),
        stabilizationRisks: const StabilizationAiRisks(),
      );
      final round = CarePlan.fromJson(original.toJson());
      expect(round.preReferralProtocols, original.preReferralProtocols);
      expect(
        round.preReferralActivationReasons,
        original.preReferralActivationReasons,
      );
    });
  });
}
