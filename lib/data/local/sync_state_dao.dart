/// The pull engine's memory.
///
/// Delta pull needs three small facts to survive an app restart: the server
/// clock reading this device last pulled up to (the watermark), when that pull
/// finished, and how many rows it brought. They live in a tiny key-value table
/// inside SQLite itself — next to the rows they describe — rather than in
/// SharedPreferences, so that "reset this device" clears pull memory and
/// pulled data together, and a rebuilt database never inherits a watermark it
/// cannot justify.
///
/// Keys are namespaced per user id ([SyncStateKeys.scoped]) because pull scope
/// is per-user: Nurse A's watermark says nothing about what Nurse B's narrower
/// or wider scope has already received.
library;

import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import 'app_database.dart';

/// Keys used in [Tables.syncState], namespaced per user via [scoped].
abstract final class SyncStateKeys {
  /// The `server_time` of the first page of the last completed pull. The next
  /// pull sends it back (minus a one-second overlap) as `since`.
  static const pullWatermark = 'pull_watermark_server_time';

  /// When the last pull finished (device clock — display only; the pull
  /// engine never reasons with it, the server owns the change markers).
  static const lastPullAt = 'pull_last_completed_at';

  /// How many rows the last pull merged, stored as text. Display only.
  static const lastPullRows = 'pull_last_rows';

  /// Namespaces a base key for one account. A null user keeps the bare key,
  /// which is only ever written by pulls that could not identify their actor.
  static String scoped(String base, String? userId) =>
      userId == null || userId.isEmpty ? base : '$base:$userId';
}

abstract final class SyncStateDao {
  /// Reads one key, or null when absent — and null on any failure, because a
  /// lost watermark only costs one redundant (idempotent) pull.
  static Future<String?> read(String key) async {
    try {
      final db = await AppDatabase.instance.database;
      final rows = await db.query(
        Tables.syncState,
        columns: const ['value'],
        where: 'key = ?',
        whereArgs: [key],
        limit: 1,
      );
      return rows.isEmpty ? null : rows.first['value'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Never throws — same reasoning as AuditDao.record. Audit logging must not
  /// break care delivery, and watermark writes must not break pulls: a lost
  /// watermark is retried into existence by the next pull.
  static Future<void> write(String key, String value) async {
    try {
      final db = await AppDatabase.instance.database;
      await db.insert(
        Tables.syncState,
        {
          'key': key,
          'value': value,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {
      /* The next successful pull rewrites it. */
    }
  }
}
