/// The family's request for help.
///
/// The payload test in this file is the privacy guarantee. `home_checks` has no
/// server counterpart on purpose (see the spec), and `care_requests` is the one
/// table allowed to carry a hint that a check happened. If a future change adds
/// a sign name, an answer or a MUAC reading to the serialized row, this file
/// fails before the code can ship a family's symptom list to a database they
/// never agreed to write to.
library;

import 'package:carebridge_ai/domain/entities/care_request.dart';
import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

HomeCheck _check({HomeCheckVerdict verdict = HomeCheckVerdict.urgent}) =>
    HomeCheck(
      id: 'chk-1',
      householdId: 'hh-1',
      personId: 'p-1',
      clientType: ClientType.childUnderFive,
      verdict: verdict,
      yesSigns: const ['Fits (convulsions)'],
      unsureSigns: const [],
      checkedBy: 'u-mother',
      checkedAt: DateTime(2026, 9, 28, 8, 42),
    );

void main() {
  group('CareRequest', () {
    test('survives a map round trip', () {
      final request = CareRequest.fromCheck(
        check: _check(),
        userId: 'u-mother',
        at: DateTime(2026, 9, 28, 9, 5),
      );
      final back = CareRequest.fromMap(request!.toMap());
      expect(back.id, request.id);
      expect(back.householdId, 'hh-1');
      expect(back.personId, 'p-1');
      expect(back.level, CareRequestLevel.urgent);
      expect(back.homeCheckId, 'chk-1');
      expect(back.status, CareRequestStatus.open);
      expect(back.answeredAt, isNull);
    });

    test('the payload carries no clinical content', () {
      final map = CareRequest.fromCheck(
        check: _check(),
        userId: 'u-mother',
        at: DateTime(2026, 9, 28, 9, 5),
      )!
          .toMap();

      expect(
        map.keys.toSet(),
        {
          'id',
          'household_id',
          'person_id',
          'level',
          'home_check_id',
          'created_by',
          'created_at',
          'updated_at',
          'status',
          'answered_at',
          'sync_state',
        },
      );
      // Nothing in the row can be a sign name or a measurement.
      final joined = map.values.whereType<String>().join(' ');
      expect(joined, isNot(contains('Fits')));
      expect(joined, isNot(contains('convulsion')));
    });

    test('a caution verdict asks for a visit today, not an emergency', () {
      final request = CareRequest.fromCheck(
        check: _check(verdict: HomeCheckVerdict.caution),
        userId: 'u-mother',
        at: DateTime(2026, 9, 28, 9, 5),
      );
      expect(request?.level, CareRequestLevel.today);
    });

    test('a fine verdict raises nothing', () {
      expect(CareRequest.levelFor(HomeCheckVerdict.fine), isNull);
      expect(
        CareRequest.fromCheck(
          check: _check(verdict: HomeCheckVerdict.fine),
          userId: 'u-mother',
          at: DateTime(2026, 9, 28, 9, 5),
        ),
        isNull,
      );
    });

    test('the id is derived from the check, so a second tap cannot duplicate',
        () {
      final first = CareRequest.fromCheck(
        check: _check(),
        userId: 'u-mother',
        at: DateTime(2026, 9, 28, 9, 5),
      );
      final second = CareRequest.fromCheck(
        check: _check(),
        userId: 'u-mother',
        at: DateTime(2026, 9, 28, 9, 5, 30),
      );
      expect(first!.id, 'req-chk-1');
      expect(second!.id, first.id);
    });
  });

  group('wire values', () {
    test('levels and statuses round trip through their stored strings', () {
      for (final level in CareRequestLevel.values) {
        expect(CareRequestLevel.fromWire(level.wireValue), level);
      }
      for (final status in CareRequestStatus.values) {
        expect(CareRequestStatus.fromWire(status.wireValue), status);
      }
    });

    test('an unreadable level is refused, an unreadable status stays open',
        () {
      // The level parser refuses to invent an urgency; a request whose status
      // cannot be read stays visible, because dropping it would tell the family
      // nobody was asked.
      expect(CareRequestLevel.fromWire('nope'), isNull);
      expect(CareRequestStatus.fromWire('nope'), CareRequestStatus.open);
    });

    test('only an open request is still asking', () {
      expect(CareRequestStatus.open.isOpen, isTrue);
      expect(CareRequestStatus.answered.isOpen, isFalse);
    });
  });
}
