/// Regression guard for the AI Triage tab crash ("Bad state: No element").
///
/// The SQLite register outlives app versions: rows written by older builds
/// (and the cloud-restore path) carried enum names — `mother`, `infant` —
/// that no longer exist. One such row used to take the whole day-plan /
/// AI Triage tab down with an unguarded `firstWhere`. These tests pin the
/// defensive reads: legacy and unknown names must degrade to a sensible
/// fallback, never throw.
library;

import 'dart:convert';

import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _personRow({
  String clientType = 'mother',
  String? dateOfBirth,
  int? ageYearsApprox,
}) => {
  'id': 'p-1',
  'household_id': 'h-1',
  'full_name': 'Aisha Ibrahim',
  'client_type': clientType,
  'sex': 'female',
  'date_of_birth': dateOfBirth,
  'age_years_approx': ageYearsApprox,
  'is_active': 1,
};

Map<String, Object?> _resultJson({
  String triage = 'priority',
  String severity = 'urgent',
  String urgency = 'immediate',
}) => {
  'client_type': 'mother',
  'triage': triage,
  'classification': 'PRIORITY — TREAT AND FOLLOW UP',
  'findings': [
    {
      'label': 'Severe acute malnutrition',
      'detail': 'MUAC 10.9 cm is below the 11.5 cm SAM cut-off.',
      'severity': severity,
    },
  ],
  'actions': [
    {
      'instruction': 'Refer to the nearest facility today.',
      'urgency': urgency,
    },
  ],
  'confidence': 'low',
};

Map<String, Object?> _assessmentRow(String clientType) => {
  'id': 'a-1',
  'visit_id': 'v-1',
  'person_id': 'p-1',
  'client_type': clientType,
  'performed_by': 'u-1',
  'performed_at': '2026-07-20T09:00:00.000',
  'inputs_json': '{"fever": true}',
  'result_json': jsonEncode(_resultJson()),
};

void main() {
  group('Person.fromMap with legacy client types', () {
    test("'mother' maps to pregnantWoman and never throws", () {
      final person = Person.fromMap(_personRow());
      expect(person.clientType, ClientType.pregnantWoman);
    });

    test("'infant' maps to childUnderFive", () {
      final person = Person.fromMap(_personRow(clientType: 'infant'));
      expect(person.clientType, ClientType.childUnderFive);
    });

    test("'child' maps to childUnderFive", () {
      final person = Person.fromMap(_personRow(clientType: 'child'));
      expect(person.clientType, ClientType.childUnderFive);
    });

    test('unknown name falls back by age when a date of birth exists', () {
      final person = Person.fromMap(
        _personRow(
          clientType: 'toddler',
          dateOfBirth: DateTime.now()
              .subtract(const Duration(days: 120))
              .toIso8601String(),
        ),
      );
      expect(person.clientType, ClientType.childUnderFive);
    });

    test('unknown name and no age data falls back to the least-assumption '
        'bucket instead of throwing', () {
      final person = Person.fromMap(_personRow(clientType: 'guardian'));
      expect(person.clientType, ClientType.womanOfReproductiveAge);
    });

    test('an out-of-range age also falls back instead of throwing', () {
      final person = Person.fromMap(
        _personRow(
          clientType: 'great-grandmother',
          dateOfBirth: DateTime.now()
              .subtract(const Duration(days: 365 * 70))
              .toIso8601String(),
        ),
      );
      expect(person.clientType, ClientType.womanOfReproductiveAge);
    });
  });

  group('Assessment.fromMap (the day-plan path that crashed)', () {
    test('a legacy mother row loads without throwing', () {
      final assessment = Assessment.fromMap(_assessmentRow('mother'));
      expect(assessment.clientType, ClientType.pregnantWoman);
      expect(assessment.result.triage, TriageLevel.priority);
    });

    test('a legacy infant row loads without throwing', () {
      final assessment = Assessment.fromMap(_assessmentRow('infant'));
      expect(assessment.clientType, ClientType.childUnderFive);
    });
  });

  group('AssessmentResult.fromJson defensive reads', () {
    test('an invalid triage degrades to routine, not an exception', () {
      final result = AssessmentResult.fromJson(
        _resultJson(triage: 'STAT'),
      );
      expect(result.triage, TriageLevel.routine);
    });

    test('an invalid finding severity degrades to routine', () {
      final result = AssessmentResult.fromJson(
        _resultJson(severity: 'catastrophic'),
      );
      expect(result.findings.single.severity, TriageLevel.routine);
    });

    test('an invalid action urgency degrades to scheduled', () {
      final result = AssessmentResult.fromJson(
        _resultJson(urgency: 'ASAP!!!'),
      );
      expect(result.actions.single.urgency, ReferralUrgency.scheduled);
    });
  });

  group('AppUser.fromMap defensive role read', () {
    test('an unknown role degrades to the least-privilege caregiver role', () {
      final user = AppUser.fromMap({
        'id': 'u-1',
        'full_name': 'Mariama Alhassan',
        'phone': '0244000000',
        'role': 'super-admin',
        'region': 'Northern Region',
        'district': 'Gushegu',
        'community': 'Gushegu',
      });
      expect(user.role, UserRole.caregiver);
    });
  });

  group('protocolConfidenceScore', () {
    test('is the share of decisive measurements actually taken', () {
      expect(protocolConfidenceScore(measuredKeyInputs: 3, keyInputCount: 4), 75);
      expect(protocolConfidenceScore(measuredKeyInputs: 0, keyInputCount: 4), 0);
      expect(protocolConfidenceScore(measuredKeyInputs: 4, keyInputCount: 4), 100);
    });

    test('an observed danger sign needs no instrument and pins at 95', () {
      expect(
        protocolConfidenceScore(
          measuredKeyInputs: 0,
          keyInputCount: 4,
          observedDangerSign: true,
        ),
        95,
      );
    });

    test('legacy bucket estimates stay monotonic with the bucket', () {
      expect(
        legacyConfidenceEstimate(RecommendationConfidence.protocolCertain),
        greaterThan(legacyConfidenceEstimate(RecommendationConfidence.high)),
      );
      expect(
        legacyConfidenceEstimate(RecommendationConfidence.high),
        greaterThan(legacyConfidenceEstimate(RecommendationConfidence.moderate)),
      );
      expect(
        legacyConfidenceEstimate(RecommendationConfidence.moderate),
        greaterThan(legacyConfidenceEstimate(RecommendationConfidence.low)),
      );
    });
  });
}
