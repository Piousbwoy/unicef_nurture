/// The inactivity lock: the policy, the watchdog, and what a lock actually does
/// to a stored session.
///
/// The last group is the one that matters most. `SessionController.restore()`
/// falls back to a shared-preferences pointer when secure storage is unavailable
/// — which is the normal state of a test host and the real state of some Android
/// devices with a broken keystore. Clearing only the secure pointer therefore
/// left a locked handset able to hand the session straight back on the next
/// launch, on precisely the weakest devices. That is pinned here rather than
/// noticed in review.
library;

import 'dart:io';

import 'package:carebridge_ai/core/auth/idle_lock.dart';
import 'package:carebridge_ai/core/auth/session.dart';
import 'package:carebridge_ai/data/local/app_database.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _nurse = AppUser(
  id: 'u-nurse',
  fullName: 'Amina Fusea',
  phone: '0244000101',
  role: UserRole.frontlineHealthWorker,
  region: 'Northern Region',
  district: 'Tamale Metropolitan',
  community: 'Vittin',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the inactivity policy', () {
    const policy = IdleLockPolicy.fieldWorker;

    test('a foreground pause locks at the window, not before', () {
      expect(
        policy.reasonFor(idleFor: const Duration(minutes: 4)),
        isNull,
        reason: 'writing in the paper register beside the phone is not a risk',
      );
      expect(
        policy.reasonFor(idleFor: const Duration(minutes: 5)),
        LockReason.idle,
      );
    });

    test('being away from the app locks sooner than an untouched screen', () {
      expect(
        policy.reasonFor(
          idleFor: const Duration(seconds: 30),
          backgroundedFor: const Duration(minutes: 2),
        ),
        LockReason.backgrounded,
      );
      expect(
        policy.reasonFor(
          idleFor: const Duration(seconds: 30),
          backgroundedFor: const Duration(seconds: 90),
        ),
        isNull,
      );
    });

    test('the stronger signal wins when both are true', () {
      expect(
        policy.reasonFor(
          idleFor: const Duration(minutes: 9),
          backgroundedFor: const Duration(minutes: 4),
        ),
        LockReason.backgrounded,
        reason: 'she left, which is what the message should say',
      );
    });

    test('a family’s own handset is never locked out of its own record', () {
      expect(IdleLockPolicy.forRole(UserRole.caregiver).isLive, isFalse);
      expect(
        IdleLockPolicy.forRole(UserRole.caregiver).reasonFor(
          idleFor: const Duration(hours: 6),
          backgroundedFor: const Duration(hours: 6),
        ),
        isNull,
      );
      expect(IdleLockPolicy.forRole(_nurse.role).isLive, isTrue);
    });

    test('the message quotes the window actually enforced', () {
      // Pinned because a screen that says "5 minutes" while the code says 3 is
      // how a security control quietly becomes a rumour.
      expect(policy.messageFor(LockReason.idle), contains('5 minutes'));
      expect(policy.messageFor(LockReason.backgrounded), contains('2 minutes'));
      expect(
        policy.messageFor(LockReason.idle),
        isNot(contains('signed out')),
        reason: 'she did not sign out, and the screen must not imply it',
      );
    });
  });

  group('the watchdog', () {
    late DateTime now;
    IdleWatchdog watch() =>
        IdleWatchdog(policy: IdleLockPolicy.fieldWorker, now: () => now);

    setUp(() => now = DateTime(2026, 10, 19, 9));

    test('a tap restarts the window', () {
      final w = watch()..rearm();
      now = now.add(const Duration(minutes: 4));
      w.touched();
      now = now.add(const Duration(minutes: 4));
      expect(
        w.onTick(),
        isNull,
        reason: 'four minutes since the last tap, not eight since the start',
      );
      now = now.add(const Duration(minutes: 1));
      expect(w.onTick(), LockReason.idle);
    });

    test('a lock is offered once, not on every tick afterwards', () {
      final w = watch()..rearm();
      now = now.add(const Duration(minutes: 6));
      expect(w.onTick(), LockReason.idle);
      expect(w.onTick(), isNull, reason: 'the keypad is already up');
    });

    test('the away window is measured on resume, not by a timer', () {
      final w = watch()..rearm();
      now = now.add(const Duration(minutes: 1));
      w.backgrounded();
      now = now.add(const Duration(minutes: 30));
      expect(w.onResumed(), LockReason.backgrounded);
    });

    test('a brief switch away does not lock', () {
      final w = watch()..rearm();
      w.backgrounded();
      now = now.add(const Duration(seconds: 45));
      expect(
        w.onResumed(),
        isNull,
        reason: 'checking a message is not leaving the compound',
      );
    });
  });

  group('locking a session', () {
    late Database db;

    /// A real SQLite file in a temp directory. `path_provider` has no
    /// implementation under `flutter test`, so it is mocked exactly the way the
    /// accountability suite mocks it.
    void setUpDb(WidgetTester tester) {
      final dbDir = Directory.systemTemp.createTempSync('carebridge_idle_lock');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => call.method == 'getApplicationDocumentsDirectory'
            ? dbDir.path
            : null,
      );
      AppDatabase.initialiseForDesktopAndTests();
      addTearDown(() => AppDatabase.instance.close());
    }

    Future<void> seedNurse() async {
      db = await AppDatabase.instance.database;
      await db.insert(Tables.users, {
        'id': _nurse.id,
        'full_name': _nurse.fullName,
        'phone': _nurse.phone,
        'role': _nurse.role.name,
        'region': _nurse.region,
        'district': _nurse.district,
        'community': _nurse.community,
        'preferred_language': 'English',
        'created_at': DateTime(2026, 10, 1).toIso8601String(),
      });
    }

    testWidgets('a locked session cannot resume from the fallback pointer', (
      tester,
    ) async {
      setUpDb(tester);
      // The FFI isolate behind sqflite never runs under FakeAsync, so every
      // database call here goes through runAsync like the accountability suite
      // does.
      await tester.runAsync(() async {
        await seedNurse();
        // The pointer secure storage could not write, on a device where it throws.
        SharedPreferences.setMockInitialValues({
          'carebridge.session.user_id_fallback': _nurse.id,
        });

        final controller = SessionController();
        final resumed = await controller.restore();
        expect(
          resumed,
          isA<SessionActive>(),
          reason: 'the fallback is what keeps an interrupted CHO signed in',
        );

        final locked = await controller.lockForInactivity(
          _nurse,
          message: 'Locked after 5 minutes without any taps.',
        );
        expect(locked, isA<SessionSignedOut>());
        expect(
          (locked as SessionSignedOut).message,
          contains('Locked after 5 minutes'),
        );

        // The whole point. Before this control existed, the fallback pointer was
        // never removed, so this line would return the session to her without a
        // PIN — a lock that unlocks itself on relaunch is not a lock.
        final after = await controller.restore();
        expect(after, isA<SessionSignedOut>());
      });
    });

    testWidgets('a lock writes its own audit action, not a sign-out', (
      tester,
    ) async {
      setUpDb(tester);
      await tester.runAsync(() async {
        await seedNurse();
        final controller = SessionController();
        await controller.lockForInactivity(_nurse, message: 'locked');

        final rows = await db.query(Tables.auditLog, orderBy: 'id DESC');
        final actions = rows.map((r) => r['action']).toList();
        expect(
          actions,
          contains('session locked after inactivity'),
          reason: 'a worker who was interrupted is not a worker who left',
        );
        expect(actions, isNot(contains('sign out')));
      });
    });
  });
}
