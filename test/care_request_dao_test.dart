/// The request row and its sync intent commit together or not at all.
///
/// This is the rule the whole repository obeys (see outbox_dao.dart's header),
/// and it matters most here: a family that pressed "Ask for help" and lost the
/// row to a half-write would believe help was on the way. The critical-priority
/// test is the other half — on ninety seconds of signal an urgent request must
/// leave before eighty routine registrations. And the withdrawal tests are the
/// promise that a queued request is not yet a call-out: what has not left the
/// phone can still be called back.
library;

import 'dart:io';

import 'package:carebridge_ai/data/local/app_database.dart';
import 'package:carebridge_ai/data/local/care_request_dao.dart';
import 'package:carebridge_ai/domain/entities/care_request.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

CareRequest _request({String id = 'req-chk-1'}) => CareRequest(
  id: id,
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

  // The DAOs read AppDatabase.instance.database, so the test must hold that
  // same handle. A second openInMemory() would be a different database and
  // every read below would come back null.
  late Database db;
  setUp(() async {
    final dir = Directory.systemTemp.createTempSync('carebridge_care_request');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? dir.path
              : null,
        );
    AppDatabase.initialiseForDesktopAndTests();
    db = await AppDatabase.instance.database;
    // care_requests has live foreign keys and the database turns them on, so
    // the parent rows are not optional here.
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

  Future<List<Map<String, Object?>>> queued(String id) => db.query(
    Tables.outbox,
    where: 'entity_table = ? AND entity_id = ?',
    whereArgs: ['care_requests', id],
  );

  group('CareRequestDao', () {
    test('creates the row and queues it at critical priority', () async {
      await db.transaction((txn) => CareRequestDao.createIn(txn, _request()));

      final stored = await CareRequestDao.byId('req-chk-1');
      expect(stored?.level, CareRequestLevel.urgent);

      final entry = (await queued('req-chk-1')).single;
      expect(entry['operation'], 'insert');
      expect(entry['priority'], 0); // SyncPriority.critical
      final payload = entry['payload_json'] as String;
      expect(payload, isNot(contains('fits')));
      expect(payload, isNot(contains('answers')));
    });

    test('a rolled back write leaves no row and no outbox entry', () async {
      await expectLater(
        db.transaction((txn) async {
          await CareRequestDao.createIn(txn, _request());
          throw StateError('the phone died mid-write');
        }),
        throwsStateError,
      );
      expect(await CareRequestDao.byId('req-chk-1'), isNull);
      expect(await queued('req-chk-1'), isEmpty);
    });

    test(
      'an open request already raised for a check is found, not duplicated',
      () async {
        await CareRequestDao.createIn(db, _request());
        expect(await CareRequestDao.openForCheck('chk-1'), isNotNull);
      },
    );

    test('an answered request is no longer open', () async {
      await CareRequestDao.createIn(db, _request());
      await CareRequestDao.markAnsweredIn(
        db,
        'req-chk-1',
        DateTime(2026, 9, 28, 14),
      );
      final stored = await CareRequestDao.byId('req-chk-1');
      expect(stored?.status, CareRequestStatus.answered);
      expect(stored?.isOpen, isFalse);
      expect(stored!.updatedAt.isAfter(stored.createdAt), isTrue);
      expect(await CareRequestDao.openForCheck('chk-1'), isNull);
      // The read the family's screen uses still finds it: the reply is the
      // thing they should see, and a second tap must land on this row instead
      // of replacing it.
      expect(await CareRequestDao.forCheck('chk-1'), isNotNull);
    });

    test('sent means the queue entry was pushed, not that time passed',
        () async {
      await CareRequestDao.createIn(db, _request());
      // The row's own sync_state is 'pending' here and stays so until a pull
      // re-offers it — push only ever touches outbox.synced_at. The card reads
      // this method, never the column, so it cannot claim a delivery the phone
      // has not seen.
      expect(await CareRequestDao.isSent('req-chk-1'), isFalse);
      await db.update(
        Tables.outbox,
        {'synced_at': '2026-09-28T09:10:00.000'},
        where: 'entity_id = ?',
        whereArgs: ['req-chk-1'],
      );
      expect(await CareRequestDao.isSent('req-chk-1'), isTrue);
    });

    test('withdrawing a request that has not left deletes the row and the '
        'queue entry together', () async {
      await CareRequestDao.createIn(db, _request());
      expect(await CareRequestDao.withdrawIn(db, 'req-chk-1'), isTrue);
      expect(await CareRequestDao.byId('req-chk-1'), isNull);
      expect(await queued('req-chk-1'), isEmpty);
    });

    test('a withdrawn write that rolls back keeps both the row and the entry',
        () async {
      await CareRequestDao.createIn(db, _request());
      await expectLater(
        db.transaction((txn) async {
          await CareRequestDao.withdrawIn(txn, 'req-chk-1');
          throw StateError('interrupted');
        }),
        throwsStateError,
      );
      expect(await CareRequestDao.byId('req-chk-1'), isNotNull);
      expect(await queued('req-chk-1'), hasLength(1));
    });

    test('a request the server already has cannot be withdrawn locally',
        () async {
      await CareRequestDao.createIn(db, _request());
      await db.update(
        Tables.outbox,
        {'synced_at': '2026-09-28T09:10:00.000'},
        where: 'entity_id = ?',
        whereArgs: ['req-chk-1'],
      );
      expect(await CareRequestDao.withdrawIn(db, 'req-chk-1'), isFalse);
      expect(await CareRequestDao.byId('req-chk-1'), isNotNull);
    });

    test('an answered request cannot be withdrawn — the reply is the record',
        () async {
      await CareRequestDao.createIn(db, _request());
      await CareRequestDao.markAnsweredIn(
        db,
        'req-chk-1',
        DateTime(2026, 9, 28, 14),
      );
      expect(await CareRequestDao.withdrawIn(db, 'req-chk-1'), isFalse);
      final stored = await CareRequestDao.byId('req-chk-1');
      expect(stored?.status, CareRequestStatus.answered);
    });
  });

  test('a v8 database gains an empty care_requests table', () async {
    // createAll already built v9; take the new table away to stand in for a v8
    // device, then run the real upgrade path. Same trick as the v7 migration
    // test's _downgradeToV7.
    await db.execute('DROP TABLE ${Tables.careRequests}');
    await AppDatabase.upgradeForTesting(db, 8);
    expect(
      await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
        [Tables.careRequests],
      ),
      hasLength(1),
    );
    expect(await db.query(Tables.careRequests), isEmpty);
  });
}
