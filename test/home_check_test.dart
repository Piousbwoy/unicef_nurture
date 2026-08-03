/// Home checks — the family's own danger-sign reports.
///
/// These tests pin the contract of the entity that carries a caregiver's
/// check to the FHW: the verdict and the exact sign wording survive the
/// SQLite round-trip, because a report that loses its words is a report the
/// health worker cannot act on.
library;

import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

HomeCheck _check({
  HomeCheckVerdict verdict = HomeCheckVerdict.urgent,
  List<String> yes = const ['Fits or convulsions', 'Vomiting everything'],
  List<String> unsure = const ['Very hot or very cold to touch'],
}) => HomeCheck(
  id: 'hc1',
  householdId: 'hh1',
  personId: 'p1',
  clientType: ClientType.newborn,
  verdict: verdict,
  yesSigns: yes,
  unsureSigns: unsure,
  checkedBy: 'cg1',
  checkedAt: DateTime(2026, 8, 1, 7, 30),
);

void main() {
  group('HomeCheck', () {
    test('survives the SQLite round-trip with its words intact', () {
      final restored = HomeCheck.fromMap(_check().toMap());

      expect(restored.id, 'hc1');
      expect(restored.personId, 'p1');
      expect(restored.clientType, ClientType.newborn);
      expect(restored.verdict, HomeCheckVerdict.urgent);
      expect(restored.yesSigns, [
        'Fits or convulsions',
        'Vomiting everything',
      ]);
      expect(restored.unsureSigns, ['Very hot or very cold to touch']);
      expect(restored.checkedAt, DateTime(2026, 8, 1, 7, 30));
    });

    test('a clean check round-trips with empty sign lists', () {
      final restored = HomeCheck.fromMap(
        _check(verdict: HomeCheckVerdict.fine, yes: const [], unsure: const [])
            .toMap(),
      );

      expect(restored.verdict, HomeCheckVerdict.fine);
      expect(restored.yesSigns, isEmpty);
      expect(restored.unsureSigns, isEmpty);
    });

    test('sign wording containing commas stays one sign, not several', () {
      final restored = HomeCheck.fromMap(
        _check(yes: const ['Breathing fast or grunting']).toMap(),
      );

      expect(restored.yesSigns, hasLength(1));
      expect(restored.yesSigns.single, 'Breathing fast or grunting');
    });

    test('every verdict the triage can produce carries a human label', () {
      for (final v in HomeCheckVerdict.values) {
        expect(v.label, isNotEmpty);
      }
    });
  });
}
