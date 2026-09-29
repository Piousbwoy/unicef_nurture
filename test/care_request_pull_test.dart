/// A request is only real when a human can receive it.
///
/// barrier_reports and scheduled_contacts are push-only: they reach the server
/// and never a worker's device (see the spec). This file is the reason
/// care_requests is not built the same way. It pins the two halves of the
/// round trip — the family's ask arriving on a worker's pull stream, and the
/// worker's status change arriving back home — and the one property that makes
/// the second half safe: a pulled row must never look locally dirty, or the
/// family's phone would echo the server's own answer straight back at it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:carebridge_ai/data/local/app_database.dart';
import 'package:carebridge_ai/data/local/care_request_dao.dart';
import 'package:carebridge_ai/data/local/preferences_store.dart';
import 'package:carebridge_ai/data/sync/http_client.dart';
import 'package:carebridge_ai/data/sync/pull_service.dart';
import 'package:carebridge_ai/domain/entities/care_request.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

const _serverTime = '2026-09-28T12:00:00.000Z';

/// As server/src/pull.js would: the row is the entity's own serialization, so
/// a column the entity stops writing stops being offered here too, plus the
/// server's watermark marker that the client must intersect away before
/// writing.
Map<String, dynamic> _asServerRow(
  CareRequest request, {
  Map<String, dynamic> overrides = const {},
}) => {
  ...request.toMap(),
  ...overrides,
  'pull_updated_at': _serverTime,
};

Map<String, dynamic> _page(List<Map<String, dynamic>> careRequests) => {
  'ok': true,
  'server_time': _serverTime,
  'scoped_to': {'user_id': 'u-worker', 'role': 'fhw'},
  'data': {'care_requests': careRequests},
  'has_more': false,
  'next_cursor': null,
};

final _request = CareRequest(
  id: 'req-chk-1',
  householdId: 'family',
  personId: 'baby',
  level: CareRequestLevel.urgent,
  homeCheckId: 'chk-1',
  createdBy: 'caregiver',
  createdAt: DateTime(2026, 9, 28, 9, 5),
  updatedAt: DateTime(2026, 9, 28, 9, 5),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // PullService and the DAOs both read AppDatabase.instance, so this file gets
  // one database through the path_provider mock — the same harness
  // test/pull_service_test.dart uses. A second handle would mean merging into
  // a database nothing here reads back.
  late Database db;
  setUp(() async {
    final dir = Directory.systemTemp.createTempSync('carebridge_pull_request');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? dir.path
              : null,
        );
    AppDatabase.initialiseForDesktopAndTests();
    db = await AppDatabase.instance.database;
    // The pull writes into care_requests, whose foreign keys are live.
    await db.insert(Tables.households, const {
      'id': 'family',
      'name': 'Family',
      'region': 'Northern Region',
      'district': 'Karaga',
      'community': 'Karaga',
      'created_by': 'caregiver',
      'created_at': '2026-09-01T00:00:00.000',
      'updated_at': '2026-09-01T00:00:00.000',
    });
    await db.insert(Tables.persons, const {
      'id': 'baby',
      'household_id': 'family',
      'full_name': 'Awah',
      'client_type': 'newborn',
      'date_of_birth': '2026-08-01T00:00:00.000',
      'created_at': '2026-09-01T00:00:00.000',
      'updated_at': '2026-09-01T00:00:00.000',
    });
  });
  tearDown(() => AppDatabase.instance.close());

  /// Serves one page from the fake district server and runs a real pull.
  Future<PullReport> pull(List<Map<String, dynamic>> rows) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await PreferencesStore.setSyncApiUrl('http://district.test');
    await PreferencesStore.setSyncApiToken('pull-test-token');
    PlatformHttpClient.override =
        (method, uri, headers, body) async =>
            HttpReply(200, jsonEncode(_page(rows)));
    addTearDown(() => PlatformHttpClient.override = null);
    return PullService(minGap: Duration.zero).pull(userId: 'u-worker');
  }

  group('the pull stream', () {
    test('server/src/pull.js streams care_requests, scoped by household', () {
      final src = File('server/src/pull.js').readAsStringSync();
      expect(src, contains("'care_requests'"));
      // Scoped the way persons and visits are — by the household, never by the
      // author. A worker who covers the zone must see the ask; a worker two
      // districts over must not.
      expect(
        RegExp(
          r"case 'persons':\s*case 'visits':\s*case 'care_requests':",
        ).hasMatch(src.replaceAll(RegExp(r'\s+'), ' ')),
        isTrue,
        reason: 'care_requests must join the household-scoped case, not grow '
            'its own filter that a later edit can drift from',
      );
    });

    test('a worker’s empty device receives the ask, and does not send it '
        'back', () async {
      // Nothing was written to care_requests in setUp, which is exactly a
      // worker who has never seen this family.
      final report = await pull([_asServerRow(_request)]);
      expect(report.isSuccess, isTrue, reason: report.toString());

      final stored = await CareRequestDao.byId('req-chk-1');
      expect(stored?.level, CareRequestLevel.urgent);
      expect(stored?.syncState, SyncState.synced);
      expect(
        await db.query(
          Tables.outbox,
          where: 'entity_table = ?',
          whereArgs: [Tables.careRequests],
        ),
        isEmpty,
        reason: 'a pulled row that looks dirty is a row the phone sends back',
      );
      expect(
        (await db.query(Tables.careRequests)).single.containsKey(
          'pull_updated_at',
        ),
        isFalse,
        reason: 'server bookkeeping is intersected away, not written into a '
            'local schema with no such column',
      );
    });

    test('the family’s device receives a worker’s answer', () async {
      await db.transaction((txn) => CareRequestDao.createIn(txn, _request));
      // The outbox row is what makes the family's copy look dirty; clearing it
      // stands for the push having completed, so only the server's newer
      // version is left to arrive.
      await db.delete(Tables.outbox);

      final answered = _asServerRow(
        _request,
        overrides: {
          'status': CareRequestStatus.answered.wireValue,
          'answered_at': '2026-09-28T14:00:00.000',
          // The exact column _mergeLww compares, written in the same format
          // the local row uses: the comparison is a plain string compare, so a
          // trailing Z here would make the ordering a lie.
          'updated_at': '2026-09-28T14:00:00.000',
        },
      );

      final report = await pull([answered]);
      expect(report.isSuccess, isTrue, reason: report.toString());

      final stored = await CareRequestDao.byId('req-chk-1');
      expect(stored?.status, CareRequestStatus.answered);
      expect(stored?.isOpen, isFalse);
      expect(
        await db.query(
          Tables.outbox,
          where: 'entity_table = ?',
          whereArgs: [Tables.careRequests],
        ),
        isEmpty,
        reason: 'being handed an answer is not the family having one to send',
      );
    });

    test('a re-offered older page cannot undo the newer status', () async {
      await CareRequestDao.createIn(
        db,
        CareRequest(
          id: _request.id,
          householdId: _request.householdId,
          personId: _request.personId,
          level: _request.level,
          homeCheckId: _request.homeCheckId,
          createdBy: _request.createdBy,
          createdAt: _request.createdAt,
          updatedAt: DateTime(2026, 9, 28, 14),
          status: CareRequestStatus.answered,
          answeredAt: DateTime(2026, 9, 28, 14),
        ),
      );
      await db.delete(Tables.outbox);

      await pull([_asServerRow(_request)]); // the 09:05 version, re-offered

      expect(
        (await CareRequestDao.byId('req-chk-1'))?.status,
        CareRequestStatus.answered,
        reason: 'last-write-wins must not let a replayed page unanswer a '
            'request the family was already told about',
      );
    });
  });
}
