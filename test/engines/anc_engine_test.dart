/// ANC engine: the protocol a CHO was trained on, made executable.
///
/// These tests pin the safety-critical behaviour: danger signs must always
/// produce an urgent referral-level verdict, severe hypertension and severe
/// anaemia must never come back green, and a straightforward pregnancy must
/// not be medicalised into a referral.
library;

import 'package:carebridge_ai/domain/engines/anc_engine.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AncEngine', () {
    test('straightforward second-trimester pregnancy is not urgent', () {
      final result = AncEngine.assess(
        const PregnancyInput(
          gestationalWeeks: 24,
          maternalAgeYears: 26,
          gravida: 2,
          parity: 1,
          systolic: 110,
          diastolic: 70,
          haemoglobin: 11.5,
          ancContactsCompleted: 3,
          iptpDoses: 1,
          tdDoses: 2,
        ),
      );

      expect(result.triage.requiresReferral, isFalse);
      expect(result.dangerSignsPresent, isEmpty);
      expect(result.clientType, ClientType.pregnantWoman);
    });

    test('convulsions are an obstetric emergency — refer now', () {
      final result = AncEngine.assess(
        const PregnancyInput(gestationalWeeks: 34, convulsions: true),
      );

      expect(result.triage, TriageLevel.urgent);
      expect(result.needsReferral, isTrue);
      expect(result.dangerSignsPresent, isNotEmpty);
    });

    test('severe hypertension with headache is pre-eclampsia until proven otherwise', () {
      final result = AncEngine.assess(
        const PregnancyInput(
          gestationalWeeks: 32,
          systolic: 170,
          diastolic: 115,
          severeHeadache: true,
          blurredVision: true,
        ),
      );

      expect(result.triage, TriageLevel.urgent);
      expect(result.needsReferral, isTrue);
    });

    test('vaginal bleeding in the third trimester is urgent', () {
      final result = AncEngine.assess(
        const PregnancyInput(gestationalWeeks: 36, vaginalBleeding: true),
      );

      expect(result.triage, TriageLevel.urgent);
    });

    test('severe anaemia is at least priority, never routine', () {
      final result = AncEngine.assess(
        const PregnancyInput(gestationalWeeks: 28, haemoglobin: 6.8),
      );

      expect(result.triage.isAtLeastPriority, isTrue);
    });

    test('reduced foetal movement escalates above routine', () {
      final result = AncEngine.assess(
        const PregnancyInput(
          gestationalWeeks: 38,
          reducedFoetalMovement: true,
        ),
      );

      expect(result.triage.isAtLeastPriority, isTrue);
    });

    test('unmeasured inputs are declared, not hidden', () {
      final result = AncEngine.assess(
        const PregnancyInput(gestationalWeeks: 20),
      );

      expect(result.missingData, isNotEmpty);
      expect(result.confidence, isNot(RecommendationConfidence.protocolCertain));
    });

    test('every finding carries its protocol source', () {
      final result = AncEngine.assess(
        const PregnancyInput(
          gestationalWeeks: 30,
          systolic: 150,
          diastolic: 100,
          haemoglobin: 9.2,
        ),
      );

      expect(result.findings, isNotEmpty);
      for (final f in result.findings) {
        expect(f.protocolSource, isNotNull, reason: f.label);
      }
    });

    test('post-term pregnancy is flagged, not ignored', () {
      final result = AncEngine.assess(
        const PregnancyInput(gestationalWeeks: 42),
      );

      expect(result.triage.isAtLeastPriority, isTrue);
    });
  });
}
