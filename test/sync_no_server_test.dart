/// Regression guard for the "no district server configured" sync path.
///
/// A field phone that has never been pointed at a sync server must NOT have its
/// outbox drained through LoopbackTransport — that transport accepts everything,
/// so every record would be marked synced and dropped from the pending queue,
/// never to re-send, while the UI claimed the district already had it. The real
/// build resolves to [NotConfiguredTransport], which leaves records honestly
/// pending. This mirrors the DEMO_MODE gate in recovery_service: the loopback
/// simulation is an explicit opt-in, never a silent production default.
library;

import 'dart:io';

import 'package:carebridge_ai/data/local/app_database.dart';
import 'package:carebridge_ai/data/local/outbox_dao.dart';
import 'package:carebridge_ai/data/sync/sync_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // File-backed database per test, so OutboxDao and SyncService — which both
  // reach the AppDatabase singleton — see the same rows this test writes.
  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('carebridge_sync');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? dir.path
              : null,
        );
    AppDatabase.initialiseForDesktopAndTests();
  });
  tearDown(() async {
    await AppDatabase.instance.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<void> enqueueOne() async {
    final db = await AppDatabase.instance.database;
    await db.transaction(
      (txn) => OutboxDao.enqueue(
        txn,
        table: Tables.households,
        entityId: 'hh-1',
        operation: SyncOperation.insert,
        payload: const {'id': 'hh-1', 'updated_at': '2026-01-01T00:00:00.000'},
      ),
    );
  }

  test('no server configured: runOnce leaves the record pending, never synced',
      () async {
    await enqueueOne();
    final service = SyncService(transport: const NotConfiguredTransport());
    expect(service.serverConfigured, isFalse);

    final report = await service.runOnce();
    expect(report.accepted, 0);
    expect(report.attempted, 0);

    final pending = await OutboxDao.pending();
    expect(pending, hasLength(1));
    expect(pending.single.entityId, 'hh-1');
    expect(pending.single.isSynced, isFalse);
    // Not counted as a failure either — an unconfigured device is a normal
    // state, not an error a supervisor must triage.
    expect(pending.single.attempts, 0);
  });

  test('no server configured: drain does not prune the outbox', () async {
    await enqueueOne();
    final service = SyncService(transport: const NotConfiguredTransport());
    await service.drain();
    final db = await AppDatabase.instance.database;
    final rows = await db.query(Tables.outbox);
    expect(rows, hasLength(1));
    expect(rows.single['synced_at'], isNull);
  });

  test('the loopback simulation still counts as configured (DEMO_MODE path)',
      () {
    // Guards the intent of the fix: loopback remains a deliberate simulation
    // for demos and tests, distinguished from a real field build only by which
    // transport the composition root resolves.
    expect(
      SyncService(transport: const LoopbackTransport()).serverConfigured,
      isTrue,
    );
  });
}
