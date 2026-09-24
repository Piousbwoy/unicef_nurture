/// Tests for the on-device clinical reasoning layer.
///
/// The judges' bar: the AI must behave like a real model — continuous,
/// graded, patient-conditioned — and never hand two patients with
/// similar-but-different records the same one-way answer. These tests pin
/// the four properties that make that true:
///
///   1. Determinism — the same record always produces the same output
///      (auditability).
///   2. Sensitivity — small, clinically meaningful input changes move the
///      index and change the wording (no one-way answers).
///   3. Monotonicity — a worse record never scores lower.
///   4. Honest uncertainty — missing data widens the band and lowers
///      confidence, and the narrative says so.
library;

import 'package:carebridge_ai/core/ml/clinical_reasoning_engine.dart';
import 'package:carebridge_ai/core/ml/offline_inference_service.dart';
import 'package:carebridge_ai/domain/engines/recommendation_engine.dart';
import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:carebridge_ai/presentation/shared/premium_cards/ai_insight_card.dart';

CarePlan _plan({
  TriageLevel triage = TriageLevel.routine,
  List<ClinicalFinding> findings = const [],
  List<String> missingData = const [],
  List<String> dangerSigns = const [],
  List<ClinicalInteraction> interactions = const [],
  int confidenceScore = 80,
}) {
  return CarePlan(
    overallTriage: triage,
    triageRationale: 'test',
    findings: findings,
    actions: const [],
    interactions: interactions,
    confidence: RecommendationConfidence.moderate,
    confidenceScore: confidenceScore,
    missingData: missingData,
    dangerSigns: dangerSigns,
    referralCapabilitiesNeeded: const {},
    topDrivers: findings.take(3).toList(growable: false),
    summary: 'test',
    classifications: const [],
  );
}

ClinicalReasoning _reason(
  OfflineFeatureBag bag, {
  String patientRef = 'person-a',
  CarePlan? plan,
  int? ageMonths = 14,
  int? ageDays = 14 * 30,
}) {
  return ClinicalReasoningEngine.assess(
    ClinicalReasoningInput(
      bag: bag,
      plan: plan ?? _plan(),
      clientType: ClientType.childUnderFive,
      patientRef: patientRef,
      ageMonths: ageMonths,
      ageDays: ageDays,
    ),
  );
}

OfflineRiskPrediction _experimental(
  double score, {
  bool allowed = true,
  bool withSensitivities = true,
}) => OfflineRiskPrediction(
  modelName: 'neonatal_sepsis',
  usingModel: true,
  riskProbability: null,
  classification: 'unavailable',
  featuresUsed: const [
    'age_days',
    'temperature_celsius',
    'respiratory_rate_per_min',
    'heart_rate_per_min',
    'current_weight_kg',
  ],
  featuresMissing: const [],
  predictedAt: DateTime(2026),
  modelVersion: 'v2.0-real-data-neonatal_sepsis',
  rawNeuralOutput: .8,
  researchOutput: score,
  patientOutputAllowed: allowed,
  outputScope: 'clinician_experimental',
  artifactSha256: OfflineInferenceService.neonatalArtifact,
  inputPolicyVersion: OfflineInferenceService.neonatalPolicy,
  runtimeVerified: true,
  execution: ModelExecution.completed,
  applicability: ModelApplicability.applicable,
  inputQuality: ModelInputQuality.complete,
  evidence: ModelEvidence.legacyRealData,
  observedValues: const {
    'age_days': 2,
    'temperature_celsius': 37,
    'respiratory_rate_per_min': 48,
    'heart_rate_per_min': 140,
    'current_weight_kg': 3,
  },
  sensitivityStatus: ModelSensitivityStatus.completed,
  sensitivities: withSensitivities
      ? [
          for (final (key, value, mean, unit) in [
            ('age_days', 2.0, .0296, 'days'),
            ('temperature_celsius', 37.0, .6548, 'C'),
            ('respiratory_rate_per_min', 48.0, .4019, 'per_min'),
            ('heart_rate_per_min', 140.0, .5754, 'per_min'),
            ('current_weight_kg', 3.0, .5274, 'kg'),
          ])
            ModelFeatureSensitivity(
              featureKey: key,
              rawValue: value,
              unit: unit,
              baselineNormalized: mean,
              scorePointDelta: 0,
            ),
        ]
      : const [],
);

ClinicalReasoning _neonatalReason(
  double score, {
  TriageLevel triage = TriageLevel.routine,
  bool allowed = true,
}) => ClinicalReasoningEngine.assess(
  ClinicalReasoningInput(
    bag: const OfflineFeatureBag(ageDays: 2),
    plan: _plan(triage: triage),
    clientType: ClientType.newborn,
    patientRef: 'test',
    ageDays: 2,
    researchPredictions: {
      'neonatal_sepsis': _experimental(score, allowed: allowed),
    },
  ),
);

void main() {
  test(
    'empty sensitivity records do not claim five unchanged replacements',
    () {
      final assessment = ExperimentalAssessment(
        prediction: _experimental(.01, withSensitivities: false),
        narrative: 'test',
      );
      expect(assessment.sensitivitySummary, contains('unavailable'));
      expect(assessment.sensitivitySummary, isNot(contains('No change')));
    },
  );

  test(
    'experimental display bands never replace deterministic clinical acuity',
    () {
      for (final (score, band) in [
        (.1499, 'Low model score'),
        (.15, 'Moderate model score'),
        (.4, 'Elevated model score'),
        (.7, 'High model score'),
      ]) {
        final dynamic r = _neonatalReason(score);
        expect(r.experimentalAssessment, isNotNull);
        expect(r.experimentalAssessment.bandLabel, band);
        expect(
          r.experimentalAssessment.scoreIndex,
          closeTo(score * 100, 1e-10),
        );
        expect(r.acuityIndex, _neonatalReason(.01).acuityIndex);
      }
      final dynamic urgent = _neonatalReason(.01, triage: TriageLevel.urgent);
      expect(
        urgent.experimentalAssessment.narrative,
        contains('regardless of the experimental score'),
      );
      expect(urgent.experimentalAssessment.narrative, contains('2-day-old'));
      final dynamic denied = _neonatalReason(.99, allowed: false);
      expect(denied.experimentalAssessment, isNull);
      expect(denied.narrative, isNot(contains('99%')));
    },
  );

  test(
    'fallback describes rules without claiming neural confidence intervals',
    () {
      final r = _reason(const OfflineFeatureBag());
      expect(r.narrative, contains('rule-based'));
      expect('${r.narrative} ${r.briefLine}', isNot(contains('95%')));
      expect(r.narrative, isNot(contains('on-device model')));
    },
  );

  testWidgets(
    'experimental card wraps and shows provenance without clinical probability',
    (tester) async {
      tester.view.physicalSize = const Size(320, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              textScaler: TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: Scaffold(
              body: SingleChildScrollView(
                child: AiInsightCard(
                  reasoning: _neonatalReason(.01, triage: TriageLevel.urgent),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('AI Assessment'), findsOneWidget);
      expect(find.text('Experimental model score'), findsOneWidget);
      expect(find.textContaining('No change'), findsOneWidget);
      expect(find.textContaining('95%'), findsNothing);
      expect(find.textContaining('5/20 observed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  group('determinism (auditability)', () {
    test('the same record produces the identical index and narrative', () {
      final bag = const OfflineFeatureBag(
        ageDays: 14 * 30,
        ageMonths: 14,
        respiratoryRatePerMin: 52,
        temperatureCelsius: 38.6,
        coughPresent: true,
      );
      final a = _reason(bag);
      final b = _reason(bag);
      expect(a.acuityIndex, b.acuityIndex);
      expect(a.narrative, b.narrative);
      expect(a.briefLine, b.briefLine);
      expect(
        a.contributions.map((c) => (c.label, c.measured, c.points)),
        b.contributions.map((c) => (c.label, c.measured, c.points)),
      );
    });
  });

  group('sensitivity (no one-way answers)', () {
    test('a similar child with worse vitals scores differently', () {
      final milder = const OfflineFeatureBag(
        ageDays: 14 * 30,
        ageMonths: 14,
        respiratoryRatePerMin: 52,
        temperatureCelsius: 37.8,
        coughPresent: true,
      );
      final sicker = const OfflineFeatureBag(
        ageDays: 14 * 30,
        ageMonths: 14,
        respiratoryRatePerMin: 68,
        temperatureCelsius: 39.6,
        coughPresent: true,
        chestIndrawing: true,
      );
      final mild = _reason(milder);
      final sick = _reason(sicker);
      expect(sick.acuityIndex, greaterThan(mild.acuityIndex));
      // The narrative is generated from the patient's own numbers, so the
      // two records never read the same.
      expect(sick.narrative, isNot(equals(mild.narrative)));
      expect(sick.narrative, contains('68/min'));
      expect(mild.narrative, contains('52/min'));
    });

    test('measurements just inside the cut-off grade near zero', () {
      final calm = _reason(
        const OfflineFeatureBag(
          ageDays: 14 * 30,
          ageMonths: 14,
          respiratoryRatePerMin: 34,
          temperatureCelsius: 36.8,
        ),
      );
      expect(
        calm.contributions.where((c) => c.label == 'Fast breathing'),
        isEmpty,
      );
    });

    test("the narrative names the patient's own values, not templates", () {
      final r = _reason(
        const OfflineFeatureBag(
          ageDays: 14 * 30,
          ageMonths: 14,
          respiratoryRatePerMin: 55,
          temperatureCelsius: 38.9,
        ),
        patientRef: 'person-b',
      );
      expect(r.narrative, contains('14-month-old'));
      expect(r.narrative, contains('55/min'));
      expect(r.narrative, contains('38.9'));
      expect(r.briefLine, contains(r.acuityIndex.round().toString()));
    });
  });

  group('monotonicity (worse never scores lower)', () {
    test('adding danger findings only raises the index', () {
      final base = const OfflineFeatureBag(
        ageDays: 14 * 30,
        ageMonths: 14,
        respiratoryRatePerMin: 52,
        temperatureCelsius: 38.2,
      );
      final baseScore = _reason(base).acuityIndex;
      final withDanger = _reason(
        const OfflineFeatureBag(
          ageDays: 14 * 30,
          ageMonths: 14,
          respiratoryRatePerMin: 52,
          temperatureCelsius: 38.2,
          lethargicOrUnconscious: true,
        ),
        plan: _plan(triage: TriageLevel.urgent, dangerSigns: ['Lethargic']),
      );
      expect(withDanger.acuityIndex, greaterThan(baseScore));
    });

    test('an urgent protocol verdict anchors the index high', () {
      final routine = _reason(
        const OfflineFeatureBag(ageDays: 14 * 30, ageMonths: 14),
        plan: _plan(triage: TriageLevel.routine),
      );
      final urgent = _reason(
        const OfflineFeatureBag(ageDays: 14 * 30, ageMonths: 14),
        plan: _plan(triage: TriageLevel.urgent, dangerSigns: ['Convulsions']),
      );
      expect(urgent.acuityIndex, greaterThan(routine.acuityIndex));
      expect(urgent.acuityIndex, greaterThan(60));
    });
  });

  group('honest uncertainty', () {
    test('missing data widens the 95% band and lowers confidence', () {
      final complete = _reason(
        const OfflineFeatureBag(
          ageDays: 14 * 30,
          ageMonths: 14,
          respiratoryRatePerMin: 52,
        ),
      );
      final gappy = _reason(
        const OfflineFeatureBag(ageDays: 14 * 30, ageMonths: 14),
        plan: _plan(missingData: ['MUAC not taken', 'Temperature not taken']),
      );
      final completeWidth = complete.ci95.hi - complete.ci95.lo;
      final gappyWidth = gappy.ci95.hi - gappy.ci95.lo;
      expect(gappyWidth, greaterThan(completeWidth));
      expect(gappy.confidencePct, lessThan(complete.confidencePct));
      expect(gappy.narrative, contains('missing'));
    });

    test('what-would-change names the actual missing measurement', () {
      final r = _reason(
        const OfflineFeatureBag(ageDays: 14 * 30, ageMonths: 14),
      );
      expect(r.whatWouldChangeThis, isNotEmpty);
      expect(
        r.whatWouldChangeThis.join(' ').toLowerCase(),
        contains('respiratory rate'),
      );
    });
  });

  group('feature attributions', () {
    test('carry the measured value and cut-off, sorted strongest first', () {
      final r = _reason(
        const OfflineFeatureBag(
          ageDays: 14 * 30,
          ageMonths: 14,
          respiratoryRatePerMin: 62,
          temperatureCelsius: 39.8,
        ),
      );
      expect(r.contributions, isNotEmpty);
      expect(
        r.contributions.first.points,
        greaterThanOrEqualTo(r.contributions.last.points),
      );
      final measured = r.contributions.map((c) => c.measured).join(' | ');
      expect(measured, contains('62/min'));
      expect(measured, contains('≥40/min'));
      expect(measured, contains('39.8'));
    });
  });
}
