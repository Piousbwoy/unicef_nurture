/// A write that keeps a row's children alive.
///
/// ### The trap this exists because of
///
/// `INSERT OR REPLACE` — what sqflite's `ConflictAlgorithm.replace` emits — is
/// implemented by SQLite as a **DELETE of the conflicting row followed by an
/// INSERT**. With `PRAGMA foreign_keys = ON`, which this register turns on
/// deliberately so an orphaned child cannot quietly skew a zone count, that
/// implicit DELETE fires every `ON DELETE CASCADE` pointing at the row. So the
/// idiom that looks like the safest way to write "insert or update" is the one
/// that destroys data:
///
///  * upserting a **household** deletes its members — and through them the growth
///    curve, the assessments, the referrals and the follow-up calls;
///  * upserting a **person** deletes that child's measurements and verdicts;
///  * upserting a **visit** deletes its roll call and its assessments;
///  * upserting a **referral** deletes every follow-up contact made against it;
///  * upserting a **user** deletes that account's drafts and activity.
///
/// None of it raises an error, and none of it appears in the audit trail. The rows
/// are simply gone on the next screen that reads them.
///
/// ### What this does instead
///
/// Look for the row; update it if it is there; insert it if it is not. Two
/// statements instead of one, and no delete anywhere in the path — which is the
/// only version of "upsert" that is safe under cascading foreign keys.
///
/// The two statements are only atomic as a pair when the caller runs them inside a
/// transaction on the single connection this app uses, which every call site here
/// does. A lost race between them surfaces as a constraint error rather than as
/// silent deletion, so the failure mode is one an operator can see.
library;

import 'package:sqflite/sqflite.dart';

/// Writes [row] into [table], keyed on [primaryKey], without deleting the row.
///
/// Every table named in [primaryKey] must be a column of [row]; the check is a
/// throw rather than a silent no-op, because a typo here would mean a parent row
/// that never updates.
Future<void> upsertWithoutCascade(
  DatabaseExecutor db, {
  required String table,
  required List<String> primaryKey,
  required Map<String, Object?> row,
}) async {
  final args = <Object?>[];
  for (final column in primaryKey) {
    if (!row.containsKey(column)) {
      throw ArgumentError.value(
        column,
        'primaryKey',
        '$table upsert is keyed on a column the row does not carry',
      );
    }
    args.add(row[column]);
  }
  final where = primaryKey.map((c) => '$c = ?').join(' AND ');
  // `update` never deletes, so no cascade can fire. Rows that legitimately have
  // to go are deleted by an explicit call that says so.
  final changed = await db.update(table, row, where: where, whereArgs: args);
  if (changed == 0) await db.insert(table, row);
}
