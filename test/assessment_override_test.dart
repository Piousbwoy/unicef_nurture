/// Clinician override — the human overrules the machine.
///
/// These tests pin the contract that makes the override safe and honest:
/// the record always exposes the level that actually governs care
/// ([Assessment.effectiveTriage]), flags itself as overridden, and survives the
/// round-trip through SQLite (toMap/fromMap) with the overruler's identity and
/// reason intact. An override that silently drops its reason or its author is
/// worse than no override at all — it is accountability with the name erased.
library;

import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

AssessmentResult _result({TriageLevel triage = TriageLevel.priority}) =>
    AssessmentResult(
      clientType: ClientType.childUnderFive,
      triage: triage,
      classification: 'PNEUMONIA — FAST BREATHING',
      findings: const [],
      actions: const [],
      confidence: RecommendationConfidence.high,
      dangerSignsPresent: const [],
      missingData: const [],
      referralCapabilitiesNeeded: const {},
    );

Assessment _assessment({
  TriageLevel engineTriage = TriageLevel.priority,
  TriageLevel? override,
  String? reason,
  String? by,
}) => Assessment(
  id: 'a1',
  visitId: 'v1',
  personId: 'p1',
  clientType: ClientType.childUnderFive,
  performedBy: 'fhw-1',
  performedAt: DateTime(2026, 8, 1, 9),
  inputs: const {'cough': true},
  result: _result(triage: engineTriage),
  overriddenTriage: override,
  overrideReason: reason,
  overrideBy: by,
);

void main() {
  group('Assessment clinician override', () {
    test('without an override, the engine verdict governs care', () {
      final a = _assessment(engineTriage: TriageLevel.priority);
      expect(a.effectiveTriage, TriageLevel.priority);
      expect(a.wasOverridden, isFalse);
    });

    test('an override replaces the engine verdict as the governing level', () {
      final a = _assessment(
        engineTriage: TriageLevel.routine,
        override: TriageLevel.urgent,
        reason: 'Child looks more unwell than the score suggests.',
        by: 'fhw-2',
      );
      expect(a.effectiveTriage, TriageLevel.urgent);
      expect(a.wasOverridden, isTrue);
      // The raw engine result is preserved for the audit trail.
      expect(a.result.triage, TriageLevel.routine);
    });

    test('override fields survive the SQLite round-trip', () {
      final a = _assessment(
        engineTriage: TriageLevel.watch,
        override: TriageLevel.urgent,
        reason: 'Referring on clinical grounds despite watch verdict.',
        by: 'fhw-3',
      );
      final restored = Assessment.fromMap(a.toMap());
      expect(restored.overriddenTriage, TriageLevel.urgent);
      expect(
        restored.overrideReason,
        'Referring on clinical grounds despite watch verdict.',
      );
      expect(restored.overrideBy, 'fhw-3');
      expect(restored.effectiveTriage, TriageLevel.urgent);
      expect(restored.wasOverridden, isTrue);
    });

    test('a record with no override round-trips with null override fields', () {
      final a = _assessment(engineTriage: TriageLevel.routine);
      final restored = Assessment.fromMap(a.toMap());
      expect(restored.overriddenTriage, isNull);
      expect(restored.overrideReason, isNull);
      expect(restored.overrideBy, isNull);
      expect(restored.effectiveTriage, TriageLevel.routine);
      expect(restored.wasOverridden, isFalse);
    });
  });
}
