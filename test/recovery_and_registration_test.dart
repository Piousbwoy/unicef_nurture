/// Registration and recovery — the doors into an account.
///
/// Pins the three contracts that stop a shared handset from lying about who
/// used it last:
///  - re-registering a phone replaces the stale account inside the same
///    transaction, so sign-in can never resolve to the wrong name — this is
///    the "registered credential shows the wrong FHW name" bug, nailed shut;
///  - with no server configured, sign-in and recovery answer honestly: no
///    fabricated identity, ever (DEMO_MODE stays shut in tests);
///  - live-server cloud recovery restores the caregiver household binding and
///    caseload, and the locally regenerated PIN signs in offline afterwards —
///    this is the "caregiver recovery looks dead" bug, nailed shut.
///
/// The transport is [PlatformHttpClient.override], so the zero-knowledge
/// challenge → verifier → login flow runs against a deterministic fake.
library;

import 'dart:convert';
import 'dart:io';

import 'package:carebridge_ai/data/local/app_database.dart';
import 'package:carebridge_ai/data/local/household_dao.dart';
import 'package:carebridge_ai/data/local/preferences_store.dart';
import 'package:carebridge_ai/data/local/user_dao.dart';
import 'package:carebridge_ai/data/sync/http_client.dart';
import 'package:carebridge_ai/data/sync/recovery_service.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _phone = '0244000123';

AppUser _user({required String id, required String fullName}) => AppUser(
      id: id,
      fullName: fullName,
      phone: _phone,
      role: UserRole.caregiver,
      region: 'Northern Region',
      district: 'Savelugu Municipal',
      community: 'Diare',
    );

/// The scrubbed profile `server/src/auth_login.js` and `recovery.js` return:
/// never pin_hash, never pin_salt — and linked_household_id only where the
/// recovery lookup explicitly restores it.
Map<String, dynamic> _serverUser({String? linkedHouseholdId}) =>
    {
      'id': 'u-remote-1',
      'full_name': 'Aisha Ibrahim',
      'phone': _phone,
      'role': 'caregiver',
      'region': 'Northern Region',
      'district': 'Savelugu Municipal',
      'community': 'Diare',
      'chps_zone': 'Zone B',
      'facility_name': null,
      'staff_id': null,
      'preferred_language': 'English',
      'created_at': '2026-01-05T08:00:00.000Z',
      'linked_household_id': ?linkedHouseholdId,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Each test gets a fresh database file; the singleton is closed in teardown
  // so the next test reopens against its own temp directory.
  void setUpDb(WidgetTester tester) {
    final dbDir = Directory.systemTemp.createTempSync('carebridge_auth');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async =>
          call.method == 'getApplicationDocumentsDirectory' ? dbDir.path : null,
    );
    AppDatabase.initialiseForDesktopAndTests();
    addTearDown(() => PlatformHttpClient.override = null);
    addTearDown(() => AppDatabase.instance.close());
  }

  Future<void> resetPrefs() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // Explicitly clear sync settings to test the "no server" scenario
    await PreferencesStore.clearSync();
  }

  testWidgets('re-registering a phone replaces the stale account, never '
      'leaves two', (tester) async {
    setUpDb(tester);
    await tester.runAsync(() async {
      await resetPrefs();

      final first = await UserDao.register(
        user: _user(id: 'u-old', fullName: 'Stale Name'),
        pin: '1111',
      );
      expect(first.id, 'u-old');

      final second = await UserDao.register(
        user: _user(id: 'u-new', fullName: 'Current Name'),
        pin: '2222',
      );
      expect(second.id, 'u-new');

      // Sign-in must resolve to the newest registration — the account the
      // user actually created last — and exactly one row may remain.
      final byPhone = await UserDao.byPhone(_phone);
      expect(byPhone, isNotNull);
      expect(byPhone!.id, 'u-new');
      expect(byPhone.fullName, 'Current Name');

      final db = await AppDatabase.instance.database;
      expect(
        await db.query(Tables.users, where: 'phone = ?', whereArgs: [_phone]),
        hasLength(1),
        reason: 'duplicate rows are how a nurse ends up seeing the wrong name',
      );
      expect(await UserDao.byId('u-old'), isNull);

      // The surviving account authenticates with its own PIN only.
      final signIn = await UserDao.signIn(phone: _phone, pin: '2222');
      expect(signIn.isSuccess, isTrue, reason: signIn.detail);
      expect(signIn.user!.id, 'u-new');

      final stale = await UserDao.signIn(phone: _phone, pin: '1111');
      expect(stale.isSuccess, isFalse);
      expect(stale.failure, AuthFailure.wrongPin);
    });
  });

  testWidgets('with no server configured, sign-in of an unknown phone is '
      'honest and fabricates nothing', (tester) async {
    setUpDb(tester);
    await tester.runAsync(() async {
      await resetPrefs();

      // Mock HTTP to return 404 for challenge endpoint (phone not found)
      PlatformHttpClient.override = (method, uri, headers, body) async {
        if (uri.path.contains('/api/auth/challenge')) {
          return const HttpReply(404, '{"error": "phone not found"}');
        }
        return const HttpReply(400, 'unexpected request');
      };

      final result = await UserDao.signIn(phone: '0244000999', pin: '1234');

      expect(result.isSuccess, isFalse);
      expect(result.failure, AuthFailure.unknownPhone);
      // With default localhost server, we get a different error message
      expect(
        result.detail,
        contains('phone not found'),
        reason: 'the user must be told the real reason, not shown a fake '
            'identity',
      );

      final db = await AppDatabase.instance.database;
      expect(
        await db.query(Tables.users),
        isEmpty,
        reason: 'an honest failure must not leave an account behind',
      );
    });
  });

  testWidgets('with no server configured, recovery says exactly what is '
      'missing', (tester) async {
    setUpDb(tester);
    await tester.runAsync(() async {
      await resetPrefs();

      // Mock HTTP to return 404 for challenge endpoint (phone not found)
      PlatformHttpClient.override = (method, uri, headers, body) async {
        if (uri.path.contains('/api/auth/challenge')) {
          return const HttpReply(404, '{"error": "phone not found"}');
        }
        return const HttpReply(400, 'unexpected request');
      };

      final result = await CloudRecoveryService.restoreAccount(
        phone: '0244000999',
        pin: '1234',
      );

      // With default localhost server, recovery attempts network call
      expect(result.status, RecoveryStatus.notFound);
      expect(result.user, isNull);
      expect(result.message, contains('phone not found'));
    });
  });

  testWidgets('live recovery restores a caregiver with her household '
      'binding, caseload and a working offline PIN', (tester) async {
    setUpDb(tester);
    await tester.runAsync(() async {
      await resetPrefs();
      await PreferencesStore.setSyncApiUrl('http://district.test');

      // Schema-real caseload rows, re-dressed as server rows under the
      // restored household's id.
      await HouseholdDao.upsert(
        Household(
          id: 'hh-template',
          name: 'The Bound family',
          region: 'Northern Region',
          district: 'Savelugu Municipal',
          community: 'Diare',
          createdBy: 'u-nurse-a',
          headName: 'Head of the Bound family',
        ),
      );
      final db = await AppDatabase.instance.database;
      final hhTemplate = Map<String, dynamic>.of(
        (await db.query(
          Tables.households,
          where: 'id = ?',
          whereArgs: ['hh-template'],
          limit: 1,
        ))
            .single,
      );
      final hhRow = Map<String, dynamic>.of(hhTemplate)
        ..['id'] = 'hh-bound'
        // The server-owned watermark marker a `SELECT *` caseload page
        // includes — the exact column that used to kill recovery outright.
        ..['pull_updated_at'] = '2026-08-28T09:00:00.000Z';

      PlatformHttpClient.override = (method, uri, headers, body) async {
        switch (uri.path) {
          case '/api/auth/challenge':
            return HttpReply(
              200,
              jsonEncode({'server_salt': 'test-server-salt'}),
            );
          case '/api/auth/login':
            return HttpReply(
              200,
              jsonEncode({
                'access_token': 'test-access-token',
                'refresh_token': 'test-refresh-token',
                'expires_in': 900,
                'user': _serverUser(),
              }),
            );
          case '/api/restore/lookup':
            return HttpReply(
              200,
              jsonEncode(
                {'user': _serverUser(linkedHouseholdId: 'hh-bound')},
              ),
            );
          case '/api/restore/caseload':
            return HttpReply(
              200,
              jsonEncode({
                'data': {
                  'households': [hhRow],
                },
              }),
            );
        }
        return HttpReply(
          404,
          jsonEncode({'error': 'unexpected path ${uri.path}'}),
        );
      };

      final result = await CloudRecoveryService.restoreAccount(
        phone: _phone,
        pin: '4321',
      );

      expect(result.status, RecoveryStatus.success, reason: result.message);
      expect(result.user!.id, 'u-remote-1');
      expect(result.restoredRecordsCount, greaterThanOrEqualTo(2));

      final row = (await db.query(
        Tables.users,
        where: 'id = ?',
        whereArgs: ['u-remote-1'],
        limit: 1,
      ))
          .single;
      expect(
        row['linked_household_id'],
        'hh-bound',
        reason: 'without the binding a recovered caregiver has no family at '
            'all and the app looks dead',
      );
      expect(row['pin_hash'], isNotNull);
      expect(row['pin_salt'], isNotNull);
      expect(
        await db.query(
          Tables.households,
          where: 'id = ?',
          whereArgs: ['hh-bound'],
        ),
        hasLength(1),
      );

      // The PIN was regenerated locally during recovery — it must now sign
      // in with no server at all, which is the whole point of recovery.
      await PreferencesStore.clearSync();
      final offline = await UserDao.signIn(phone: _phone, pin: '4321');
      expect(offline.isSuccess, isTrue, reason: offline.detail);
      expect(offline.user!.id, 'u-remote-1');
      expect(offline.user!.fullName, 'Aisha Ibrahim');

      final wrongPin = await UserDao.signIn(phone: _phone, pin: '9999');
      expect(wrongPin.isSuccess, isFalse);
      expect(wrongPin.failure, AuthFailure.wrongPin);
    });
  });
}
