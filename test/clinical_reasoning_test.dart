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

void main() {
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
      expect(gappy.narrative, contains('confidence'));
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
      expect(r.contributions.first.points,
          greaterThanOrEqualTo(r.contributions.last.points));
      final measured = r.contributions.map((c) => c.measured).join(' | ');
      expect(measured, contains('62/min'));
      expect(measured, contains('≥40/min'));
      expect(measured, contains('39.8'));
    });
  });
}
