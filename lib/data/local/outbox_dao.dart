/// The sync outbox — how offline-first stops being a hope and becomes a
/// guarantee.
///
/// The rule the whole app obeys: **a record and its sync intent are written in
/// one transaction, or neither is written.** If a CHO saves an assessment and
/// the phone dies mid-write, SQLite rolls both back and the screen still holds
/// the form. What cannot happen is the case that ruins field deployments — a
/// record saved locally that the server never hears about, discovered six weeks
/// later when a child is missing from a report.
///
/// Two details that only matter once this is real:
///
/// **Priority, not FIFO.** On an EDGE connection in Gushegu you may get ninety
/// seconds of signal. In that window an urgent referral must leave the device
/// before eighty routine household registrations. Ordering is
/// `priority, queued_at`.
///
/// **Failures are surfaced, not swallowed.** A row that has failed repeatedly is
/// shown to a human with its last error, because silent retries for a fortnight
/// is how data is lost politely.
library;

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

/// What happened to the record. Deliberately coarse — the server applies
/// last-write-wins on `updated_at`, and a CHO has no business resolving merge
/// conflicts on a 5-inch screen.
enum SyncOperation { insert, update, delete }

/// Lower number leaves the device first.
abstract final class SyncPriority {
  /// Someone may die today. Referrals and urgent assessments.
  static const int critical = 0;

  /// Clinical content: assessments, growth, barrier reports.
  static const int clinical = 3;

  /// Registrations, visits, schedules.
  static const int routine = 5;

  /// Housekeeping that nobody is waiting for.
  static const int background = 8;
}

class OutboxEntry {
  const OutboxEntry({
    required this.id,
    required this.entityTable,
    required this.entityId,
    required this.operation,
    required this.payload,
    required this.priority,
    required this.queuedAt,
    this.attempts = 0,
    this.lastAttemptAt,
    this.lastError,
    this.syncedAt,
  });

  final int id;
  final String entityTable;
  final String entityId;
  final SyncOperation operation;
  final Map<String, Object?> payload;
  final int priority;
  final DateTime queuedAt;
  final int attempts;
  final DateTime? lastAttemptAt;
  final String? lastError;
  final DateTime? syncedAt;

  bool get isSynced => syncedAt != null;

  /// After this many failures the entry stops being a transient network problem
  /// and starts being something a person needs to look at.
  bool get needsAttention => attempts >= 5 && syncedAt == null;

  /// Exponential backoff, capped. Without the cap a row that failed overnight
  /// would wait days; without the backoff a device with no signal would drain
  /// its battery retrying.
  Duration get retryDelay {
    final minutes = (1 << attempts.clamp(0, 7)).clamp(1, 120);
    return Duration(minutes: minutes);
  }

  bool get isReadyToRetry {
    if (syncedAt != null) return false;
    final last = lastAttemptAt;
    if (last == null) return true;
    return DateTime.now().difference(last) >= retryDelay;
  }

  factory OutboxEntry.fromMap(Map<String, Object?> m) => OutboxEntry(
    id: (m['id'] as num).toInt(),
    entityTable: m['entity_table'] as String,
    entityId: m['entity_id'] as String,
    operation: SyncOperation.values.firstWhere(
      (o) => o.name == m['operation'],
      orElse: () => SyncOperation.update,
    ),
    payload: Map<String, Object?>.from(
      jsonDecode((m['payload_json'] as String?) ?? '{}') as Map,
    ),
    priority: (m['priority'] as num?)?.toInt() ?? SyncPriority.routine,
    queuedAt: DateTime.parse(m['queued_at'] as String),
    attempts: (m['attempts'] as num?)?.toInt() ?? 0,
    lastAttemptAt: DateTime.tryParse((m['last_attempt_at'] as String?) ?? ''),
    lastError: m['last_error'] as String?,
    syncedAt: DateTime.tryParse((m['synced_at'] as String?) ?? ''),
  );
}

/// Counts for the sync banner. A CHO should be able to glance at the top of the
/// screen and know whether their morning's work has left the phone.
class SyncStatusSummary {
  const SyncStatusSummary({
    required this.pending,
    required this.failing,
    required this.criticalPending,
    this.oldestPendingAt,
  });

  final int pending;
  final int failing;

  /// Urgent referrals still on the device. This is the number that matters.
  final int criticalPending;

  final DateTime? oldestPendingAt;

  bool get isClean => pending == 0;

  String get label {
    if (pending == 0) return 'All records synced';
    if (criticalPending > 0) {
      return '$criticalPending urgent record${criticalPending == 1 ? '' : 's'} '
          'waiting to send';
    }
    return '$pending record${pending == 1 ? '' : 's'} saved on this phone';
  }

  /// Reassurance first — the commonest fear in the field is that unsent means
  /// lost.
  String get detail {
    if (pending == 0) return 'Nothing is waiting. Everything is safely uploaded.';
    final age = oldestPendingAt == null
        ? ''
        : ' The oldest has been waiting '
              '${DateTime.now().difference(oldestPendingAt!).inHours} hours.';
    return 'Your work is saved on this phone and will upload by itself when '
        'there is network. Nothing is lost.$age'
        '${failing > 0 ? ' $failing item${failing == 1 ? '' : 's'} could not be sent and need checking.' : ''}';
  }
}

abstract final class OutboxDao {
  /// Queues one change. **Always call this inside the same [txn] that wrote the
  /// record**, which is why it takes a [DatabaseExecutor] rather than fetching
  /// its own handle.
  static Future<void> enqueue(
    DatabaseExecutor txn, {
    required String table,
    required String entityId,
    required SyncOperation operation,
    required Map<String, Object?> payload,
    int priority = SyncPriority.routine,
  }) async {
    await txn.insert(Tables.outbox, {
      'entity_table': table,
      'entity_id': entityId,
      'operation': operation.name,
      'payload_json': jsonEncode(payload),
      'priority': priority,
      'queued_at': DateTime.now().toIso8601String(),
      'attempts': 0,
    });
  }

  /// The next batch to send, highest priority and oldest first.
  ///
  /// [limit] is small on purpose: a short window of signal should produce
  /// several small committed successes rather than one large rollback.
  static Future<List<OutboxEntry>> pending({int limit = 25}) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.outbox,
      where: 'synced_at IS NULL',
      orderBy: 'priority ASC, queued_at ASC',
      limit: limit,
    );
    return rows
        .map(OutboxEntry.fromMap)
        .where((e) => e.isReadyToRetry)
        .toList(growable: false);
  }

  static Future<void> markSynced(int id) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      Tables.outbox,
      {'synced_at': DateTime.now().toIso8601String(), 'last_error': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> markFailed(int id, String error) async {
    final db = await AppDatabase.instance.database;
    await db.rawUpdate(
      'UPDATE ${Tables.outbox} SET attempts = attempts + 1, '
      'last_attempt_at = ?, last_error = ? WHERE id = ?',
      [DateTime.now().toIso8601String(), error, id],
    );
  }

  static Future<SyncStatusSummary> summary() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT
        COUNT(*)                                            AS pending,
        SUM(CASE WHEN attempts >= 5 THEN 1 ELSE 0 END)      AS failing,
        SUM(CASE WHEN priority <= ${SyncPriority.critical} THEN 1 ELSE 0 END) AS critical,
        MIN(queued_at)                                      AS oldest
      FROM ${Tables.outbox}
      WHERE synced_at IS NULL
    ''');
    final r = rows.first;
    return SyncStatusSummary(
      pending: (r['pending'] as num?)?.toInt() ?? 0,
      failing: (r['failing'] as num?)?.toInt() ?? 0,
      criticalPending: (r['critical'] as num?)?.toInt() ?? 0,
      oldestPendingAt: DateTime.tryParse((r['oldest'] as String?) ?? ''),
    );
  }

  /// Entries a human must resolve, newest failure first.
  static Future<List<OutboxEntry>> failing() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.outbox,
      where: 'synced_at IS NULL AND attempts >= 5',
      orderBy: 'last_attempt_at DESC',
    );
    return rows.map(OutboxEntry.fromMap).toList(growable: false);
  }

  /// Resets the attempt counter so a stuck row tries again — used by the "retry
  /// now" button, after a CHO has fixed whatever was wrong.
  static Future<void> resetAttempts(int id) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      Tables.outbox,
      {'attempts': 0, 'last_error': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Drops successfully-synced rows older than [keepDays]. A shared CHPS phone
  /// has 8 GB of storage and years of work ahead of it.
  static Future<int> pruneSynced({int keepDays = 14}) async {
    final db = await AppDatabase.instance.database;
    final cutoff = DateTime.now()
        .subtract(Duration(days: keepDays))
        .toIso8601String();
    return db.delete(
      Tables.outbox,
      where: 'synced_at IS NOT NULL AND synced_at < ?',
      whereArgs: [cutoff],
    );
  }
}
