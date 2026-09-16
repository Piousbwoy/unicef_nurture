/// The delta-pull engine, against a fake district server.
///
/// Pins the read half of the hybrid contract:
///  - pages merge under LWW (households, persons) and insert-if-absent
///    (visits) with per-page transactions;
///  - pulled rows never look locally dirty, so the outbox cannot echo them
///    straight back to the server;
///  - the per-user watermark advances only after a pull completes end to end;
///  - the next pull sends that watermark minus one second of overlap, and the
///    merge rules make the re-delivery invisible;
///  - every terminal state (not configured, unauthorized, unreachable) is an
///    honest report, and the debounce collapses eager triggers into one fetch.
///
/// The transport is [PlatformHttpClient.override] — no sockets, no timing,
/// fully deterministic. Rows offered by the fake server are templated from
/// rows the real DAOs wrote, so the schemas can never drift apart silently.
library;

import 'dart:convert';
import 'dart:io';

import 'package:carebridge_ai/data/local/app_database.dart';
import 'package:carebridge_ai/data/local/household_dao.dart';
import 'package:carebridge_ai/data/local/preferences_store.dart';
import 'package:carebridge_ai/data/local/sync_state_dao.dart';
import 'package:carebridge_ai/data/local/user_dao.dart';
import 'package:carebridge_ai/data/local/visit_dao.dart';
import 'package:carebridge_ai/data/sync/http_client.dart';
import 'package:carebridge_ai/data/sync/pull_service.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One stable server clock reading for the whole suite.
const _serverTime = '2026-08-28T09:00:00.000Z';

/// Builds a well-formed pull page the way `server/src/pull.js` would. The
/// data map is untyped on purpose: tables arrive as row lists, but the
/// caller's own user row arrives as a single object.
Map<String, dynamic> _page({
  Map<String, dynamic> data = const {},
  bool hasMore = false,
  int? nextCursor,
}) =>
    {
      'ok': true,
      'server_time': _serverTime,
      'scoped_to': {'user_id': 'u-pull', 'role': 'fhw'},
      'data': data,
      'has_more': hasMore,
      'next_cursor': ?nextCursor,
    };

AppUser _self() => AppUser(
      id: 'u-self',
      fullName: 'Fatima Yakubu',
      phone: '0244000000',
      role: UserRole.frontlineHealthWorker,
      region: 'Northern Region',
      district: 'Savelugu Municipal',
      community: 'Diare',
    );

/// Writes a real household via the real DAO, then reads the row back — the
/// fake server offers exactly this shape, so a schema drift fails loudly here
/// instead of silently corrupting a merge rule.
Future<Map<String, dynamic>> _householdRow(String id) async {
  await HouseholdDao.upsert(
    Household(
      id: id,
      name: 'The Template family',
      region: 'Northern Region',
      district: 'Savelugu Municipal',
      community: 'Diare',
      createdBy: 'u-origin',
      headName: 'Head of the Template family',
    ),
  );
  final db = await AppDatabase.instance.database;
  final rows = await db
      .query(Tables.households, where: 'id = ?', whereArgs: [id], limit: 1);
  return Map<String, dynamic>.of(rows.single);
}

Future<Map<String, dynamic>> _personRow(String id, String householdId) async {
  await PersonDao.upsert(
    Person(
      id: id,
      householdId: householdId,
      fullName: 'Template Person',
      clientType: ClientType.newborn,
      dateOfBirth: DateTime(2026, 6, 1),
    ),
  );
  final db = await AppDatabase.instance.database;
  final rows = await db
      .query(Tables.persons, where: 'id = ?', whereArgs: [id], limit: 1);
  return Map<String, dynamic>.of(rows.single);
}

Future<Map<String, dynamic>> _visitRow(String id, String householdId) async {
  await VisitDao.upsert(
    Visit(
      id: id,
      householdId: householdId,
      conductedBy: 'u-origin',
      startedAt: DateTime(2026, 8, 20, 9, 30),
      reasons: const [VisitReason.newbornRegistration],
    ),
  );
  final db = await AppDatabase.instance.database;
  final rows =
      await db.query(Tables.visits, where: 'id = ?', whereArgs: [id], limit: 1);
  return Map<String, dynamic>.of(rows.single);
}

/// Re-dresses a local row as a server row: new identity, plus the
/// server-owned watermark marker a `SELECT *` delivers with every row. The
/// pull path strips it; the client must intersect anything else away —
/// writing unknown columns verbatim is how cloud recovery died on
/// "no column named pull_updated_at".
Map<String, dynamic> _asServerRow(
  Map<String, dynamic> row, {
  Map<String, dynamic> overrides = const {},
}) {
  final out = Map<String, dynamic>.of(row)
    ..addAll(overrides)
    ..['pull_updated_at'] = _serverTime;
  return out;
}

/// Shifts a timestamp while preserving its exact string format: the LWW rule
/// compares ISO strings lexicographically, so the shifted value must stay in
/// the same format family as the stored one or the comparison lies.
String _shift(String iso, Duration delta) =>
    DateTime.parse(iso).add(delta).toIso8601String();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Each test gets a fresh database file; the singleton is closed in teardown
  // so the next test reopens against its own temp directory.
  void setUpDb(WidgetTester tester) {
    final dbDir = Directory.systemTemp.createTempSync('carebridge_pull');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async =>
          call.method == 'getApplicationDocumentsDirectory' ? dbDir.path : null,
    );
    AppDatabase.initialiseForDesktopAndTests();
    addTearDown(() => PlatformHttpClient.override = null);
    addTearDown(() => AppDatabase.instance.close());
  }

  Future<void> configureServer() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await PreferencesStore.setSyncApiUrl('http://district.test');
    await PreferencesStore.setSyncApiToken('pull-test-token');
  }

  testWidgets(
      'a first pull merges a household and its member, and nothing looks '
      'locally dirty', (tester) async {
    setUpDb(tester);
    await tester.runAsync(() async {
      await configureServer();

      final hh = await _householdRow('hh-t1');
      final person = await _personRow('p-t1', 'hh-t1');
      final pullUris = <Uri>[];
      final authHeaders = <String?>[];
      PlatformHttpClient.override = (method, uri, headers, body) async {
        pullUris.add(uri);
        authHeaders.add(headers['Authorization']);
        return HttpReply(
          200,
          jsonEncode(_page(data: {
            'households': [
              _asServerRow(hh, overrides: {
                'id': 'hh-server-1',
                'name': 'The Pulled family',
                'created_by': 'u-nurse-b',
              }),
            ],
            'persons': [
              _asServerRow(person, overrides: {
                'id': 'p-server-1',
                'household_id': 'hh-server-1',
              }),
            ],
          })),
        );
      };

      final report =
          await PullService(minGap: Duration.zero).pull(userId: 'u-pull');

      expect(report.isSuccess, isTrue, reason: report.toString());
      expect(report.rowsApplied, 2);
      expect(report.pages, 1);
      expect(pullUris, hasLength(1));
      expect(pullUris.single.path, '/api/pull');
      expect(
        authHeaders.single,
        'Bearer pull-test-token',
        reason: 'a pull without credentials is refused server-side',
      );

      final db = await AppDatabase.instance.database;
      final pulledHh = (await db.query(
        Tables.households,
        where: 'id = ?',
        whereArgs: ['hh-server-1'],
      ))
          .single;
      expect(pulledHh['name'], 'The Pulled family');
      expect(
        pulledHh.containsKey('pull_updated_at'),
        isFalse,
        reason: 'server-owned bookkeeping columns are intersected away, not '
            'written into a local schema that has no such column',
      );
      final pulledPerson = (await db.query(
        Tables.persons,
        where: 'id = ?',
        whereArgs: ['p-server-1'],
      ))
          .single;
      expect(pulledPerson['household_id'], 'hh-server-1');
      expect(
        await db.query(
          Tables.outbox,
          where: 'entity_id = ?',
          whereArgs: ['hh-server-1'],
        ),
        isEmpty,
        reason: 'pulled rows never enter the outbox, or the app would echo '
            'them straight back to the server',
      );

      // The watermark and its bookkeeping are scoped to the pulling user.
      expect(
        await SyncStateDao.read(
            SyncStateKeys.scoped(SyncStateKeys.pullWatermark, 'u-pull')),
        _serverTime,
      );
      expect(
        await SyncStateDao.read(
            SyncStateKeys.scoped(SyncStateKeys.pullWatermark, 'u-other')),
        isNull,
        reason: 'nurse A\u2019s watermark says nothing about nurse B\u2019s scope',
      );
      expect(
        await SyncStateDao.read(
            SyncStateKeys.scoped(SyncStateKeys.lastPullRows, 'u-pull')),
        '2',
      );
    });
  });

  testWidgets(
      're-pulls send the watermark minus one second and merge idempotently',
      (tester) async {
    setUpDb(tester);
    await tester.runAsync(() async {
      await configureServer();

      final hh = await _householdRow('hh-t2');
      final person = await _personRow('p-t2', 'hh-t2');
      final visit = await _visitRow('v-t2', 'hh-t2');
      final hhNewer = _shift(hh['updated_at'] as String,
          const Duration(seconds: 5));
      final personOlder = _shift(person['updated_at'] as String,
          const Duration(seconds: -5));

      final sinceSeen = <String?>[];
      final service = PullService(minGap: Duration.zero);

      // Pull 1: the household and person arrive for the first time.
      PlatformHttpClient.override = (method, uri, headers, body) async {
        if (uri.path == '/api/pull') sinceSeen.add(uri.queryParameters['since']);
        return HttpReply(
          200,
          jsonEncode(_page(data: {
            'households': [_asServerRow(hh, overrides: {'id': 'hh-2'})],
            'persons': [
              _asServerRow(person, overrides: {
                'id': 'p-2',
                'household_id': 'hh-2',
              }),
            ],
          })),
        );
      };
      final r1 = await service.pull(userId: 'u-pull');
      expect(r1.isSuccess, isTrue, reason: r1.toString());
      expect(
        sinceSeen.single,
        isNull,
        reason: 'a first pull has no watermark to send',
      );

      // Pull 2: a newer household applies, an older person must not, and a
      // visit the device has never seen arrives.
      PlatformHttpClient.override = (method, uri, headers, body) async {
        if (uri.path == '/api/pull') sinceSeen.add(uri.queryParameters['since']);
        return HttpReply(
          200,
          jsonEncode(_page(data: {
            'households': [
              _asServerRow(hh, overrides: {
                'id': 'hh-2',
                'name': 'The Updated family',
                'updated_at': hhNewer,
              }),
            ],
            'persons': [
              _asServerRow(person, overrides: {
                'id': 'p-2',
                'household_id': 'hh-2',
                'updated_at': personOlder,
              }),
            ],
            'visits': [
              _asServerRow(
                visit,
                overrides: {'id': 'v-2', 'household_id': 'hh-2'},
              ),
            ],
          })),
        );
      };
      final r2 = await service.pull(userId: 'u-pull');
      expect(r2.isSuccess, isTrue, reason: r2.toString());
      expect(r2.rowsApplied, 2, reason: r2.toString());
      expect(r2.rowsSkipped, 1, reason: r2.toString());

      final expectedSince =
          _shift(_serverTime, const Duration(seconds: -1));
      expect(
        sinceSeen.last,
        expectedSince,
        reason: 'the overlap re-reads the watermark second on purpose',
      );

      final db = await AppDatabase.instance.database;
      expect(
        (await db.query(
          Tables.households,
          where: 'id = ?',
          whereArgs: ['hh-2'],
        ))
            .single['name'],
        'The Updated family',
      );
      final untouched = (await db.query(
        Tables.persons,
        where: 'id = ?',
        whereArgs: ['p-2'],
      ))
          .single;
      expect(
        untouched['updated_at'],
        person['updated_at'],
        reason: 'an older row must never overwrite the local future',
      );
      expect(
        await db.query(Tables.visits, where: 'id = ?', whereArgs: ['v-2']),
        hasLength(1),
        reason: 'a visit carrying server-only bookkeeping columns still merges',
      );

      // Pull 3: the server re-offers exactly what we already have — the
      // overlap window in miniature. Nothing may change.
      PlatformHttpClient.override = (method, uri, headers, body) async {
        if (uri.path == '/api/pull') sinceSeen.add(uri.queryParameters['since']);
        return HttpReply(
          200,
          jsonEncode(_page(data: {
            'households': [
              _asServerRow(hh, overrides: {
                'id': 'hh-2',
                'name': 'The Updated family',
                'updated_at': hhNewer,
              }),
            ],
            'persons': [
              _asServerRow(person, overrides: {
                'id': 'p-2',
                'household_id': 'hh-2',
                'updated_at': personOlder,
              }),
            ],
            'visits': [
              _asServerRow(
                visit,
                overrides: {'id': 'v-2', 'household_id': 'hh-2'},
              ),
            ],
          })),
        );
      };
      final r3 = await service.pull(userId: 'u-pull');
      expect(r3.isSuccess, isTrue, reason: r3.toString());
      expect(r3.rowsApplied, 0, reason: r3.toString());
      expect(r3.rowsSkipped, 3, reason: r3.toString());
      expect(
        await db.query(Tables.visits, where: 'id = ?', whereArgs: ['v-2']),
        hasLength(1),
        reason: 're-delivered clinical history is absorbed, never duplicated',
      );
    });
  });

  testWidgets(
      'a pull that dies mid-pages leaves the watermark standing and heals '
      'on retry', (tester) async {
    setUpDb(tester);
    await tester.runAsync(() async {
      await configureServer();

      final hh = await _householdRow('hh-t3');
      final hhNewer =
          _shift(hh['updated_at'] as String, const Duration(seconds: 5));
      final sinceSeen = <String?>[];
      final replies = <HttpReply>[
        // Page 1 of the doomed session: merges fine.
        HttpReply(
          200,
          jsonEncode(_page(
            hasMore: true,
            nextCursor: 1,
            data: {
              'households': [_asServerRow(hh, overrides: {'id': 'hh-3'})],
            },
          )),
        ),
        // Page 2: the district server falls over.
        HttpReply(
          500,
          jsonEncode({'error': 'the district server fell over'}),
        ),
        // The retry: the same window, now with a fresher household.
        HttpReply(
          200,
          jsonEncode(_page(data: {
            'households': [
              _asServerRow(hh, overrides: {
                'id': 'hh-3',
                'name': 'The Healed family',
                'updated_at': hhNewer,
              }),
            ],
          })),
        ),
      ];
      PlatformHttpClient.override = (method, uri, headers, body) async {
        if (uri.path == '/api/pull') sinceSeen.add(uri.queryParameters['since']);
        return replies.removeAt(0);
      };

      final service = PullService(minGap: Duration.zero);
      final failed = await service.pull(userId: 'u-pull');
      expect(failed.status, PullStatus.unavailable);
      expect(failed.pages, 1, reason: 'page one merged, page two never did');
      expect(
        await SyncStateDao.read(
            SyncStateKeys.scoped(SyncStateKeys.pullWatermark, 'u-pull')),
        isNull,
        reason: 'no watermark until the whole session completes',
      );
      expect(
        await SyncStateDao.read(
            SyncStateKeys.scoped(SyncStateKeys.lastPullAt, 'u-pull')),
        isNull,
      );

      final retried = await service.pull(userId: 'u-pull', force: true);
      expect(retried.isSuccess, isTrue, reason: retried.toString());
      expect(
        sinceSeen,
        everyElement(isNull),
        reason: 'both attempts re-read the same window from the beginning',
      );

      final db = await AppDatabase.instance.database;
      final healed = (await db.query(
        Tables.households,
        where: 'id = ?',
        whereArgs: ['hh-3'],
      ))
          .single;
      expect(healed['name'], 'The Healed family');
      expect(
        await SyncStateDao.read(
            SyncStateKeys.scoped(SyncStateKeys.pullWatermark, 'u-pull')),
        _serverTime,
        reason: 'the watermark moves only after a completed session',
      );
    });
  });

  testWidgets('a rejected credential is reported honestly and touches nothing',
      (tester) async {
    setUpDb(tester);
    await tester.runAsync(() async {
      await configureServer();

      final pullUris = <Uri>[];
      PlatformHttpClient.override = (method, uri, headers, body) async {
        pullUris.add(uri);
        return HttpReply(
          401,
          jsonEncode({'error': 'expired token'}),
        );
      };

      final report =
          await PullService(minGap: Duration.zero).pull(userId: 'u-pull');

      expect(report.status, PullStatus.unauthorized);
      expect(
        pullUris,
        hasLength(1),
        reason: 'no refresh token exists on a test device, so no second try',
      );
      expect(
        await SyncStateDao.read(
            SyncStateKeys.scoped(SyncStateKeys.pullWatermark, 'u-pull')),
        isNull,
      );
    });
  });

  testWidgets('with no server configured the pull is a honest no-op',
      (tester) async {
    setUpDb(tester);
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final pullUris = <Uri>[];
      PlatformHttpClient.override = (method, uri, headers, body) async {
        pullUris.add(uri);
        return HttpReply(200, jsonEncode(_page()));
      };

      final report =
          await PullService(minGap: Duration.zero).pull(userId: 'u-pull');

      expect(report.status, PullStatus.notConfigured);
      expect(pullUris, isEmpty, reason: 'standalone devices never dial out');
    });
  });

  testWidgets('the debounce collapses eager triggers into one fetch',
      (tester) async {
    setUpDb(tester);
    await tester.runAsync(() async {
      await configureServer();

      final hh = await _householdRow('hh-t6');
      var fetches = 0;
      PlatformHttpClient.override = (method, uri, headers, body) async {
        fetches++;
        return HttpReply(
          200,
          jsonEncode(_page(data: {
            'households': [_asServerRow(hh, overrides: {'id': 'hh-6'})],
          })),
        );
      };

      // Default gap (30s): a push drain, a connectivity flap and a manual
      // tap landing together produce one network conversation.
      final service = PullService();
      final r1 = await service.pull(userId: 'u-pull');
      final r2 = await service.pull(userId: 'u-pull');
      expect(identical(r1, r2), isTrue,
          reason: 'the debounce returns the very same report');
      expect(fetches, 1);

      final r3 = await service.pull(userId: 'u-pull', force: true);
      expect(r3.isSuccess, isTrue);
      expect(fetches, 2, reason: 'force bypasses the debounce');
    });
  });

  testWidgets(
      'the self-user row refreshes the profile but never device credentials '
      'or a fresh household binding', (tester) async {
    setUpDb(tester);
    await tester.runAsync(() async {
      await configureServer();
      await UserDao.register(
        user: _self(),
        pin: '2468',
        linkedHouseholdId: 'hh-mine',
      );

      final db = await AppDatabase.instance.database;
      final before = (await db.query(
        Tables.users,
        where: 'id = ?',
        whereArgs: ['u-self'],
        limit: 1,
      ))
          .single;

      PlatformHttpClient.override = (method, uri, headers, body) async {
        return HttpReply(
          200,
          jsonEncode(_page(data: {
            // The server's scrub contract: no pin_hash, no pin_salt, and no
            // linked_household_id — that column never leaves the device.
            'users': {
              'id': 'u-self',
              'full_name': 'Fatima Yakubu (server)',
              'phone': '0244000000',
              'role': 'fhw',
              'region': 'Northern Region',
              'district': 'Savelugu Municipal',
              'community': 'Diare',
              'chps_zone': 'Zone A',
              'facility_name': 'Diare CHPS',
              'staff_id': 'STF-1',
              'preferred_language': 'English',
              'created_at': before['created_at'],
            },
          })),
        );
      };

      final report =
          await PullService(minGap: Duration.zero).pull(userId: 'u-self');
      expect(report.isSuccess, isTrue, reason: report.toString());
      expect(report.rowsApplied, 1);

      final after = (await db.query(
        Tables.users,
        where: 'id = ?',
        whereArgs: ['u-self'],
        limit: 1,
      ))
          .single;
      expect(after['full_name'], 'Fatima Yakubu (server)');
      expect(
        after['pin_hash'],
        before['pin_hash'],
        reason: 'server rows never touch device credentials',
      );
      expect(after['pin_salt'], before['pin_salt']);
      expect(
        after['linked_household_id'],
        'hh-mine',
        reason: 'a locally fresh binding must survive a profile refresh',
      );
    });
  });
}
