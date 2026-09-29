/// The read and write path for a family's request for help.
///
/// Small on purpose. Only the family's device creates these rows, and in this
/// pass only the family's device reads them; the desk that answers them is
/// separate work (see the spec's out-of-scope list).
library;

import 'package:sqflite/sqflite.dart';

import '../../domain/entities/care_request.dart';
import '../../domain/enums.dart';
import 'app_database.dart';
import 'outbox_dao.dart';

abstract final class CareRequestDao {
  /// Raises a request on its own transaction.
  ///
  /// The repository has no database handle and must not acquire one: every
  /// atomic write in this app is opened here, so `*In` takes a caller's
  /// executor and this wraps it (same pairing as `markEscalated`).
  static Future<void> create(CareRequest request) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) => createIn(txn, request));
  }

  /// Writes the row and its sync intent in the caller's transaction.
  static Future<void> createIn(
    DatabaseExecutor db,
    CareRequest request,
  ) async {
    final map = request.toMap();
    await db.insert(
      Tables.careRequests,
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    // Critical, not clinical: SyncPriority.critical is documented as "someone
    // may die today", and a queued urgent request is exactly that.
    await OutboxDao.enqueue(
      db,
      table: Tables.careRequests,
      entityId: request.id,
      operation: SyncOperation.insert,
      payload: map,
      priority: SyncPriority.critical,
    );
  }

  static Future<CareRequest?> byId(String id) async {
    final db = await AppDatabase.instance.database;
    return _first(
      await db.query(
        Tables.careRequests,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      ),
    );
  }

  /// The open request this check already raised, if any. Keyed on the check id
  /// because `CareRequest.id` is derived from it, which is what makes a second
  /// tap a no-op rather than a second summons.
  static Future<CareRequest?> openForCheck(String homeCheckId) async {
    final db = await AppDatabase.instance.database;
    return _first(
      await db.query(
        Tables.careRequests,
        where: "home_check_id = ? AND status = 'open'",
        whereArgs: [homeCheckId],
        limit: 1,
      ),
    );
  }

  /// The request this check raised, answered or not.
  ///
  /// `openForCheck` is the guard for "may I raise another"; this is the read for
  /// "what did we already agree". They differ exactly where it matters: once a
  /// worker replies, the family's screen must show the reply, and a second tap
  /// must find the row and leave it alone rather than replacing it with a fresh
  /// open request of the same deterministic id.
  static Future<CareRequest?> forCheck(String homeCheckId) async {
    final db = await AppDatabase.instance.database;
    return _first(
      await db.query(
        Tables.careRequests,
        where: 'home_check_id = ?',
        whereArgs: [homeCheckId],
        orderBy: 'created_at DESC',
        limit: 1,
      ),
    );
  }

  /// Whether this request has reached the server.
  ///
  /// Reads the outbox, not the row: a successful push sets `outbox.synced_at`
  /// and never touches `care_requests.sync_state`, which only a pull re-offering
  /// the row would change. So the column would say "pending" forever to a family
  /// whose request landed hours ago, and the card would lie at them.
  static Future<bool> isSent(String id) async {
    final db = await AppDatabase.instance.database;
    return _hasLeft(db, id);
  }

  /// Records the worker's answer. Called from the pull merge, not from a button.
  static Future<void> markAnsweredIn(
    DatabaseExecutor db,
    String id,
    DateTime at,
  ) async {
    await db.update(
      Tables.careRequests,
      {
        'status': CareRequestStatus.answered.wireValue,
        'answered_at': at.toIso8601String(),
        'updated_at': at.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Calls back a request, on its own transaction. See `withdrawIn` for the
  /// rules; this only opens the transaction the two deletions need to share.
  static Future<bool> withdraw(String id) async {
    final db = await AppDatabase.instance.database;
    return db.transaction((txn) => withdrawIn(txn, id));
  }

  /// Calls back a request that has not left the phone.
  ///
  /// Returns false, changing nothing, once the server has the row: deleting it
  /// locally would leave the health worker holding a summons the family's screen
  /// says was never sent. Before acknowledgement the family is entitled to their
  /// change of mind, and the row and its queue entry go in one transaction so a
  /// withdrawn request cannot linger as a half-truth.
  ///
  /// An answered request is also refused. By then it is not a request any more,
  /// it is the record that someone replied — and deleting it would throw away
  /// the only answer the family ever got.
  static Future<bool> withdrawIn(DatabaseExecutor db, String id) async {
    final existing = await db.query(
      Tables.careRequests,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (existing.isEmpty) return false;
    final status = CareRequestStatus.fromWire(
      existing.single['status'] as String,
    );
    if (!status.isOpen) return false;
    if (await _hasLeft(db, id)) return false;
    await db.delete(
      Tables.outbox,
      where: 'entity_table = ? AND entity_id = ?',
      whereArgs: [Tables.careRequests, id],
    );
    await db.delete(Tables.careRequests, where: 'id = ?', whereArgs: [id]);
    return true;
  }

  /// The one test of "this has left the phone", shared by the card's wording and
  /// the withdrawal guard so they cannot drift apart.
  static Future<bool> _hasLeft(DatabaseExecutor db, String id) async {
    final sent = await db.query(
      Tables.outbox,
      where: 'entity_table = ? AND entity_id = ? AND synced_at IS NOT NULL',
      whereArgs: [Tables.careRequests, id],
      limit: 1,
    );
    return sent.isNotEmpty;
  }

  static CareRequest? _first(List<Map<String, Object?>> rows) =>
      rows.isEmpty ? null : CareRequest.fromMap(rows.first);
}
