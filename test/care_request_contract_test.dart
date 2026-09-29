/// server/src/tables.js, schema.sql, migration 004 and CareRequest.toMap()
/// describe one thing four times. sync.js answers 400 for an unlisted table and
/// the client turns that into a permanent SendRejected, so a column present in
/// Dart and absent in SQL is not a warning — it is a request that never lands.
library;

import 'dart:io';

import 'package:carebridge_ai/domain/entities/care_request.dart';
import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

const _keys = [
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
];

void main() {
  final sample = CareRequest.fromCheck(
    check: HomeCheck(
      id: 'chk-1',
      householdId: 'hh-1',
      personId: 'p-1',
      clientType: ClientType.childUnderFive,
      verdict: HomeCheckVerdict.urgent,
      yesSigns: const [],
      unsureSigns: const [],
      checkedBy: 'u-mother',
      checkedAt: DateTime(2026, 9, 28),
    ),
    userId: 'u-mother',
    at: DateTime(2026, 9, 28),
  )!;

  test('the entity serializes exactly the agreed columns', () {
    expect(sample.toMap().keys.toSet(), _keys.toSet());
  });

  for (final path in [
    'server/schema.sql',
    'server/migrations/004_care_requests.sql',
  ]) {
    test('$path declares care_requests with every column', () {
      final sql = File(path).readAsStringSync();
      final block = RegExp(
        r'CREATE TABLE IF NOT EXISTS care_requests \(([\s\S]*?)\)\s*ENGINE',
      ).firstMatch(sql);
      expect(block, isNotNull, reason: 'no care_requests DDL in $path');
      for (final column in _keys) {
        expect(
          block!.group(1),
          contains(column),
          reason: '$column missing from $path',
        );
      }
    });
  }

  test('tables.js whitelists care_requests for push', () {
    final js = File('server/src/tables.js').readAsStringSync();
    final block = RegExp(r'care_requests: \{([\s\S]*?)\n  \}').firstMatch(js);
    expect(block, isNotNull, reason: 'care_requests absent from the whitelist');
    for (final column in _keys) {
      expect(block!.group(1), contains("'$column'"));
    }
  });
}
