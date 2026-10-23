/// The number a nurse sees must be arithmetic she can re-do, and a record that
/// never carried one must not be handed a figure by guesswork.
///
/// Judges asked for a confidence score. What the engine actually computed was
/// the share of decisive measurements taken — which is useful, and is not
/// confidence. A child with a respiratory rate of 51 against a cut-off of 50
/// has 100% of its inputs recorded and a verdict one beat from flipping. So
/// this file pins two things: the number is named for what it measures, and a
/// legacy row with no stored score reports *nothing* rather than an invented
/// bucket estimate.
library;

import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

AssessmentResult _result({int? evidenceSufficiency}) => AssessmentResult(
  clientType: ClientType.childUnderFive,
  triage: TriageLevel.routine,
  classification: 'WELL CHILD',
  findings: const [],
  actions: const [],
  confidence: RecommendationConfidence.moderate,
  evidenceSufficiency: evidenceSufficiency,
);

void main() {
  group('evidence sufficiency — the name matches the arithmetic', () {
    test('is the share of decisive measurements actually taken', () {
      expect(evidenceSufficiencyScore(measuredKeyInputs: 3, keyInputCount: 4), 75);
      expect(evidenceSufficiencyScore(measuredKeyInputs: 0, keyInputCount: 4), 0);
      expect(evidenceSufficiencyScore(measuredKeyInputs: 4, keyInputCount: 4), 100);
    });

    test('a danger sign seen with the eye is itself evidence, not a gap', () {
      // Chest indrawing needs no instrument. Punishing the worker for acting
      // on what they directly observed would teach them to distrust the score.
      expect(
        evidenceSufficiencyScore(
          measuredKeyInputs: 0,
          keyInputCount: 4,
          observedDirectSign: true,
        ),
        95,
      );
    });

    test('no decisive inputs required reads as unknown, not as zero', () {
      // A missing denominator is a reporting problem. Reading it as 0 would
      // claim the visit was unsupported when nothing was ever required.
      expect(evidenceSufficiencyScore(measuredKeyInputs: 0, keyInputCount: 0), isNull);
    });
  });

  group('a record that never carried a score reports no score', () {
    test('assessment read from a legacy row yields null, never an estimate', () {
      // The old code mapped the bucket word to 95/82/65/45. Those figures had
      // no computation behind them and appeared on a clinical verdict screen.
      final legacy = AssessmentResult.fromJson(
        _result().toJson()..remove('evidence_sufficiency'),
      );
      expect(legacy.evidenceSufficiency, isNull);
    });

    test('an old confidence_score key still parses into the new name', () {
      // Storage must not be rewritten out from under rows already on handsets.
      final row = _result().toJson()
        ..remove('evidence_sufficiency')
        ..['confidence_score'] = 75;
      expect(AssessmentResult.fromJson(row).evidenceSufficiency, 75);
    });

    test('the new key round-trips', () {
      expect(_result(evidenceSufficiency: 80).evidenceSufficiency, 80);
      expect(
        AssessmentResult.fromJson(
          _result(evidenceSufficiency: 80).toJson(),
        ).evidenceSufficiency,
        80,
      );
    });
  });
}
