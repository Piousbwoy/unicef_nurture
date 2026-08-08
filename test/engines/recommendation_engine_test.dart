/// Recommendation synthesizer: the layer that turns engine outputs into one
/// safe, prioritized, explainable decision.
///
/// These tests pin the properties that make it trustworthy with real patients:
/// multi-condition merging, dangerous-interaction detection, the never-miss
/// and referral-guarantee guard-rails, honest uncertainty consolidation, and
/// urgency-first ordering.
library;

import 'dart:convert';

import 'package:carebridge_ai/domain/engines/recommendation_engine.dart';
import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

AssessmentResult _result({
  ClientType clientType = ClientType.childUnderFive,
  TriageLevel triage = TriageLevel.routine,
  String classification = 'NO IMCI CLASSIFICATION — WELL CHILD',
  List<ClinicalFinding> findings = const [],
  List<RecommendedAction> actions = const [],
  RecommendationConfidence confidence = RecommendationConfidence.high,
  NutritionStatus? nutritionStatus,
  List<String> dangerSigns = const [],
  List<String> missingData = const [],
  Set<String> capabilities = const {},
  int? followUpInDays,
  String? caregiverMessage,
}) => AssessmentResult(
  clientType: clientType,
  triage: triage,
  classification: classification,
  findings: findings,
  actions: actions,
  confidence: confidence,
  nutritionStatus: nutritionStatus,
  dangerSignsPresent: dangerSigns,
  missingData: missingData,
  referralCapabilitiesNeeded: capabilities,
  followUpInDays: followUpInDays,
  caregiverMessage: caregiverMessage,
);

ClinicalFinding _finding(
  String label,
  TriageLevel severity, {
  double weight = 1,
}) => ClinicalFinding(
  label: label,
  detail: '$label detail.',
  severity: severity,
  protocolSource: 'Test protocol',
  weight: weight,
);

RecommendedAction _action(
  String instruction,
  ReferralUrgency urgency, {
  bool referral = false,
  bool treatment = false,
  bool counselling = false,
}) => RecommendedAction(
  instruction: instruction,
  urgency: urgency,
  isReferral: referral,
  isTreatment: treatment,
  isCounselling: counselling,
);

void main() {
  group('RecommendationEngine — merging & triage', () {
    test('a well child with no findings is routine with no escalation', () {
      final plan = RecommendationEngine.synthesize(results: [_result()]);

      expect(plan.overallTriage, TriageLevel.routine);
      expect(plan.needsReferral, isFalse);
      expect(plan.guardrailEscalated, isFalse);
      expect(plan.referralGuaranteed, isFalse);
    });

    test('overall triage is the worst across every engine and finding', () {
      final plan = RecommendationEngine.synthesize(results: [
        _result(triage: TriageLevel.watch),
        _result(triage: TriageLevel.priority),
        _result(
          triage: TriageLevel.routine,
          findings: [_finding('Severe pneumonia', TriageLevel.urgent)],
        ),
      ]);

      expect(plan.overallTriage, TriageLevel.urgent);
      expect(plan.needsReferral, isTrue);
    });

    test('duplicate findings are merged, keeping the more severe', () {
      final plan = RecommendationEngine.synthesize(results: [
        _result(findings: [_finding('Pneumonia', TriageLevel.priority)]),
        _result(findings: [_finding('Pneumonia', TriageLevel.urgent)]),
      ]);

      final pneumonia =
          plan.findings.where((f) => f.label == 'Pneumonia').toList();
      expect(pneumonia, hasLength(1));
      expect(pneumonia.single.severity, TriageLevel.urgent);
    });

    test('duplicate actions are not repeated', () {
      final plan = RecommendationEngine.synthesize(results: [
        _result(actions: [_action('Give ORS', ReferralUrgency.sameDay)]),
        _result(actions: [_action('Give ORS', ReferralUrgency.sameDay)]),
      ]);

      expect(
        plan.actions.where((a) => a.instruction == 'Give ORS'),
        hasLength(1),
      );
    });

    test('findings are ordered most-severe first', () {
      final plan = RecommendationEngine.synthesize(results: [
        _result(findings: [
          _finding('Runny nose', TriageLevel.routine),
          _finding('Severe pneumonia', TriageLevel.urgent),
          _finding('Fever', TriageLevel.watch),
        ]),
      ]);

      expect(plan.findings.first.label, 'Severe pneumonia');
      expect(plan.findings.last.label, 'Runny nose');
    });

    test('actions are ordered by urgency, prereferral treatments FIRST within a band', () {
      // ActionPhase clinical ordering ensures life-saving prereferral
      // stabilisations (MgSO4, rectal artesunate, antibiotics) execute
      // BEFORE the CHO sits down to write a referral note or arrange transport.
      final plan = RecommendationEngine.synthesize(results: [
        _result(actions: [
          _action('Counsel on feeding', ReferralUrgency.scheduled, counselling: true),
          _action('Give pre-referral antibiotic', ReferralUrgency.immediate, treatment: true),
          _action('Refer now', ReferralUrgency.immediate, referral: true),
          _action('Review in 2 days', ReferralUrgency.withinTwoDays, counselling: true),
        ]),
      ]);

      // Within the immediate-urgency band: prereferralTreatment (phase 0)
      // sorts BEFORE immediateReferral (phase 1).
      expect(plan.actions[0].instruction, 'Give pre-referral antibiotic');
      expect(plan.actions[1].instruction, 'Refer now');
      // Less urgent bands follow; counselling is last.
      expect(plan.actions.last.instruction, 'Counsel on feeding');
    });
  });

  group('RecommendationEngine — interaction detection', () {
    test('SAM with dehydration demands ReSoMal, not ORS', () {
      final plan = RecommendationEngine.synthesize(
        results: [
          _result(
            triage: TriageLevel.urgent,
            nutritionStatus: NutritionStatus.severeAcute,
          ),
        ],
        extraFindings: [_finding('Some dehydration', TriageLevel.priority)],
      );

      expect(
        plan.interactions.any((i) => i.label.contains('ReSoMal')),
        isTrue,
      );
      expect(
        plan.actions.any((a) => a.instruction.contains('ReSoMal')),
        isTrue,
      );
    });

    test('SAM with a danger sign is routed to inpatient, not OTP', () {
      final plan = RecommendationEngine.synthesize(
        results: [
          _result(
            triage: TriageLevel.priority,
            nutritionStatus: NutritionStatus.severeAcute,
            findings: [_finding('Pneumonia', TriageLevel.priority)],
          ),
        ],
      );

      expect(
        plan.interactions.any((i) => i.label.contains('inpatient')),
        isTrue,
      );
      expect(
        plan.actions.any((a) => a.instruction.contains('inpatient')),
        isTrue,
      );
    });

    test('severe anaemia with respiratory distress flags transfusion', () {
      final plan = RecommendationEngine.synthesize(
        results: [_result(triage: TriageLevel.urgent)],
        extraFindings: [
          _finding('Severe anaemia', TriageLevel.urgent),
          _finding('Respiratory distress', TriageLevel.urgent),
        ],
      );

      expect(
        plan.interactions.any((i) => i.label.contains('transfusion')),
        isTrue,
      );
      expect(
        plan.actions.any((a) => a.instruction.contains('transfusion')),
        isTrue,
      );
    });

    test('a well-fed child with dehydration gets no SAM interaction', () {
      final plan = RecommendationEngine.synthesize(
        results: [_result(triage: TriageLevel.priority)],
        extraFindings: [_finding('Some dehydration', TriageLevel.priority)],
      );

      expect(
        plan.interactions.any((i) => i.label.contains('ReSoMal')),
        isFalse,
      );
    });
  });

  group('RecommendationEngine — safety guard-rails', () {
    test('a danger-sign finding mislabelled priority still forces urgent', () {
      // The engine called convulsions "priority" — a bug. The synthesizer
      // must catch it anyway.
      final plan = RecommendationEngine.synthesize(results: [
        _result(
          triage: TriageLevel.priority,
          findings: [_finding('Convulsions', TriageLevel.priority)],
        ),
      ]);

      expect(plan.overallTriage, TriageLevel.urgent);
      expect(plan.guardrailEscalated, isTrue);
      expect(plan.dangerSigns, contains('Convulsions'));
    });

    test('an urgent verdict always carries a referral action', () {
      // Urgent triage but the engine forgot to add any referral step.
      // The guard-rail injects one, and — per ActionPhase ordering — the
      // prereferral oxygen treatment still executes BEFORE the referral
      // note is written (clinical correctness: stabilise first, document second).
      final plan = RecommendationEngine.synthesize(results: [
        _result(
          triage: TriageLevel.urgent,
          findings: [_finding('Severe pneumonia', TriageLevel.urgent)],
          actions: [_action('Give oxygen', ReferralUrgency.immediate, treatment: true)],
        ),
      ]);

      expect(plan.referralGuaranteed, isTrue);
      expect(plan.actions.any((a) => a.isReferral), isTrue);
      // Prereferral treatment (O2) sorts FIRST — before the injected referral.
      expect(plan.actions[0].instruction, 'Give oxygen');
      expect(plan.actions[0].isTreatment, isTrue);
      // The injected referral is immediate urgency and present.
      final injected = plan.actions.firstWhere((a) => a.isReferral);
      expect(injected.urgency, ReferralUrgency.immediate);
      expect(injected.instruction, contains('Refer now'));
      // And verify ordering: prereferral treatment index < referral index.
      final treatmentIdx = plan.actions.indexWhere((a) => a.instruction == 'Give oxygen');
      final referralIdx = plan.actions.indexWhere((a) => a.isReferral);
      expect(treatmentIdx, lessThan(referralIdx));
    });

    test('no referral is injected when one already exists', () {
      final plan = RecommendationEngine.synthesize(results: [
        _result(
          triage: TriageLevel.urgent,
          findings: [_finding('Severe pneumonia', TriageLevel.urgent)],
          actions: [_action('Refer now', ReferralUrgency.immediate, referral: true)],
        ),
      ]);

      expect(plan.referralGuaranteed, isFalse);
      expect(
        plan.actions.where((a) => a.isReferral),
        hasLength(1),
      );
    });
  });

  group('RecommendationEngine — uncertainty & explainability', () {
    test('confidence is the least confident of any input', () {
      final plan = RecommendationEngine.synthesize(results: [
        _result(confidence: RecommendationConfidence.high),
        _result(confidence: RecommendationConfidence.low),
      ]);

      expect(plan.confidence, RecommendationConfidence.low);
    });

    test('missing data and danger signs are unioned across engines', () {
      final plan = RecommendationEngine.synthesize(results: [
        _result(missingData: ['temperature'], dangerSigns: ['Convulsions']),
        _result(missingData: ['haemoglobin', 'temperature'], dangerSigns: []),
      ]);

      expect(plan.missingData, ['temperature', 'haemoglobin']);
      expect(plan.dangerSigns, ['Convulsions']);
    });

    test('referral capabilities are unioned and follow-up is earliest', () {
      final plan = RecommendationEngine.synthesize(results: [
        _result(capabilities: {'bloodBank'}, followUpInDays: 14),
        _result(capabilities: {'theatre'}, followUpInDays: 7),
      ]);

      expect(plan.referralCapabilitiesNeeded, {'bloodBank', 'theatre'});
      expect(plan.followUpInDays, 7);
    });

    test('top drivers name the findings behind the verdict', () {
      final plan = RecommendationEngine.synthesize(results: [
        _result(
          triage: TriageLevel.urgent,
          findings: [
            _finding('Severe pneumonia', TriageLevel.urgent, weight: 3),
            _finding('Fever', TriageLevel.watch),
            _finding('Runny nose', TriageLevel.routine),
          ],
        ),
      ]);

      expect(plan.topDrivers.first.label, 'Severe pneumonia');
      expect(plan.triageRationale, contains('Severe pneumonia'));
      expect(plan.summary, isNotEmpty);
    });

    test('the caregiver message comes from the most urgent result', () {
      final plan = RecommendationEngine.synthesize(results: [
        _result(caregiverMessage: 'Feed well and keep warm.'),
        _result(
          triage: TriageLevel.urgent,
          caregiverMessage: 'Go to the hospital now.',
        ),
      ]);

      expect(plan.caregiverMessage, 'Go to the hospital now.');
    });
  });

  group('RecommendationEngine — care plan persistence', () {
    test('a care plan survives the JSON round-trip it is stored as', () {
      final plan = RecommendationEngine.synthesize(
        results: [
          _result(
            triage: TriageLevel.urgent,
            classification: 'SEVERE PNEUMONIA OR VERY SEVERE DISEASE',
            nutritionStatus: NutritionStatus.severeAcute,
            dangerSigns: ['Convulsing now'],
            missingData: ['Temperature'],
            findings: [
              _finding('Convulsing now', TriageLevel.urgent),
              _finding('Some dehydration', TriageLevel.priority),
            ],
            followUpInDays: 1,
            caregiverMessage: 'Go to the hospital now.',
          ),
        ],
      );

      // SAM with dehydration must have produced interactions, so the
      // round-trip below genuinely exercises interaction serialization.
      expect(plan.interactions, isNotEmpty);

      // The exact path the result screen persists: encode, store, restore.
      final restored = CarePlan.fromJson(
        Map<String, Object?>.from(jsonDecode(jsonEncode(plan.toJson())) as Map),
      );

      expect(restored.overallTriage, plan.overallTriage);
      expect(restored.triageRationale, plan.triageRationale);
      expect(restored.summary, plan.summary);
      expect(restored.confidence, plan.confidence);
      expect(restored.dangerSigns, plan.dangerSigns);
      expect(restored.missingData, plan.missingData);
      expect(restored.classifications, plan.classifications);
      expect(restored.followUpInDays, plan.followUpInDays);
      expect(restored.caregiverMessage, plan.caregiverMessage);
      expect(restored.referralGuaranteed, plan.referralGuaranteed);
      expect(restored.guardrailEscalated, plan.guardrailEscalated);
      expect(restored.referralCapabilitiesNeeded, plan.referralCapabilitiesNeeded);
      expect(
        restored.findings.map((f) => f.label),
        plan.findings.map((f) => f.label),
      );
      expect(
        restored.actions.map((a) => a.instruction),
        plan.actions.map((a) => a.instruction),
      );
      expect(
        restored.interactions.map((i) => i.label),
        plan.interactions.map((i) => i.label),
      );
      expect(
        restored.interactions.map((i) => i.action?.instruction),
        plan.interactions.map((i) => i.action?.instruction),
      );
    });
  });
}
