/// The verdict page used to print every engine's classification joined with " + "
/// and call it a diagnosis line. A nurse does not read a list — she reads one
/// condition, ranked first because it is the one that kills the child, and she
/// wants to see the measurement that produced it.
///
/// This resolver does the ranking the IMCI chart already does: a general danger
/// sign outranks a symptom cluster, a severe classification absorbs a mild one,
/// and an absent test is reported as a missing test rather than as a disease.
/// Nothing here decides treatment; it names what the engines already found, in
/// the order the guideline puts them.
library;

import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/domain/engines/clinical_impression_resolver.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

ClinicalFinding _f(
  String label, {
  String? measuredValue,
  String? threshold,
  TriageLevel severity = TriageLevel.urgent,
  double weight = 5,
}) => ClinicalFinding(
  label: label,
  detail: '$label found on assessment.',
  severity: severity,
  measuredValue: measuredValue,
  threshold: threshold,
  weight: weight,
);

void main() {
  group('one condition, ranked first', () {
    test('a general danger sign outranks every symptom cluster', () {
      final im = ClinicalImpressionResolver.resolve(
        classifications: const ['PNEUMONIA', 'VERY SEVERE DISEASE'],
        findings: [
          _f('Fast breathing', measuredValue: '62/min', threshold: '≥ 50/min'),
          _f('Not able to drink'),
        ],
      );
      expect(im.tier, ImpressionTier.emergency);
      expect(im.recordCode, 'VERY SEVERE DISEASE');
      // The pneumonia is still on the record — absorbing it would lose
      // information the receiving facility needs.
      expect(im.alsoPresent, contains('PNEUMONIA'));
    });

    test('pneumonia alone is treated here, not referred', () {
      final im = ClinicalImpressionResolver.resolve(
        classifications: const ['PNEUMONIA'],
        findings: [
          _f(
            'Fast breathing',
            measuredValue: '62/min',
            threshold: '≥ 50/min',
            severity: TriageLevel.watch,
          ),
        ],
      );
      expect(im.tier, ImpressionTier.treat);
      expect(im.conditionName, contains('neumonia'));
      expect(im.needsReferral, isFalse);
    });

    test('a cough with no fast breathing is supportive care', () {
      final im = ClinicalImpressionResolver.resolve(
        classifications: const ['COUGH OR COLD'],
        findings: const [],
      );
      expect(im.tier, ImpressionTier.supportive);
    });

    test('no classification reads as well, never as an empty verdict', () {
      final im = ClinicalImpressionResolver.resolve(
        classifications: const ['WELL CHILD'],
        findings: const [],
      );
      expect(im.tier, ImpressionTier.well);
      expect(im.needsReferral, isFalse);
    });
  });

  group('an absent test is not a disease', () {
    test('a required malaria test surfaces as a gap, not a condition', () {
      final im = ClinicalImpressionResolver.resolve(
        classifications: const ['FEVER — MALARIA TEST NEEDED'],
        findings: [_f('Fever', measuredValue: '38.4°C', threshold: '≥ 37.5°C')],
      );
      expect(im.tier, ImpressionTier.needsTest);
      expect(im.unresolved, isNotEmpty);
      expect(im.needsReferral, isFalse);
    });

    test('a real condition still outranks a pending test', () {
      final im = ClinicalImpressionResolver.resolve(
        classifications: const [
          'FEVER — MALARIA TEST NEEDED',
          'SEVERE DEHYDRATION',
        ],
        findings: const [],
      );
      expect(im.tier, ImpressionTier.emergency);
      expect(im.unresolved, contains('FEVER — MALARIA TEST NEEDED'));
    });
  });

  group('the named condition carries its own evidence', () {
    test('the measurement and the cut-off travel with the condition', () {
      final im = ClinicalImpressionResolver.resolve(
        classifications: const ['PNEUMONIA'],
        findings: [
          _f(
            'Fast breathing',
            measuredValue: '62/min',
            threshold: '≥ 50/min',
            severity: TriageLevel.watch,
          ),
        ],
      );
      expect(im.evidence, isNotEmpty);
      expect(im.evidence.first.statement, contains('62/min'));
      expect(im.evidence.first.statement, contains('50/min'));
    });

    test('plain words are a sentence, not the engine code', () {
      // The raw uppercase classification string is kept in recordCode for the
      // register; the line a human reads must never be that string.
      final im = ClinicalImpressionResolver.resolve(
        classifications: const ['PNEUMONIA'],
        findings: const [],
      );
      expect(im.plainWords, isNot(contains('PNEUMONIA')));
      expect(im.plainWords.length, greaterThan(24));
    });
  });

  group('unknown classifications degrade, never crash', () {
    test('a code from an engine this file has not met still resolves', () {
      // Newborn and maternal streams contribute their own strings. Dropping one
      // silently would hide a condition; guessing its tier would invent one.
      final im = ClinicalImpressionResolver.resolve(
        classifications: const ['SOME NEW GHANA EPI FINDING'],
        findings: const [],
      );
      expect(im.tier, ImpressionTier.needsReview);
      expect(im.recordCode, 'SOME NEW GHANA EPI FINDING');
      expect(im.conditionName, 'SOME NEW GHANA EPI FINDING');
    });

    test('ordering is deterministic for identical input', () {
      final a = ClinicalImpressionResolver.resolve(
        classifications: const ['PNEUMONIA', 'COUGH OR COLD'],
        findings: const [],
      );
      final b = ClinicalImpressionResolver.resolve(
        classifications: const ['PNEUMONIA', 'COUGH OR COLD'],
        findings: const [],
      );
      expect(a.conditionName, b.conditionName);
      expect(a.plainWords, b.plainWords);
      expect(a.alsoPresent, b.alsoPresent);
    });
  });
}
