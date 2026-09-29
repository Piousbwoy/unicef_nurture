/// Schema v8: the follow-up answer ledger.
///
/// This is the repository's first migration test, and it exists because v8 is
/// the first version that has to carry a real device's history. A field phone in
/// Karaga may be several app versions behind, and its register holds months of
/// referrals whose follow-up was written as prose in `outcome_notes`. Those rows
/// must still read after the upgrade — and the new tables must start genuinely
/// empty, because an answer the worker never gave cannot be reconstructed from
/// a sentence.
library;

import 'package:carebridge_ai/data/local/app_database.dart';
import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

Future<Set<String>> _columns(Database db, String table) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return rows.map((r) => r['name'] as String).toSet();
}

Future<bool> _hasTable(Database db, String table) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
    [table],
  );
  return rows.isNotEmpty;
}

/// Strips the v8 objects back out of a freshly created database, leaving behind
/// exactly what a v7 device would have: the old tables, the old columns, and
/// rows written by the old app.
Future<void> _downgradeToV7(Database db) async {
  await db.execute('DROP TABLE ${Tables.followUpContacts}');
  await db.execute(
    'ALTER TABLE ${Tables.referrals} DROP COLUMN link_from_referral_id',
  );
  await db.execute(
    'ALTER TABLE ${Tables.scheduledContacts} DROP COLUMN referral_id',
  );
  await db.transaction((txn) async {
    await txn.rawDelete('DELETE FROM ${Tables.barrierReports}');
    await txn.rawDelete('DELETE FROM ${Tables.scheduledContacts}');
    await txn.rawDelete('DELETE FROM ${Tables.referrals}');
    await txn.rawDelete('DELETE FROM ${Tables.assessments}');
    await txn.rawDelete('DELETE FROM ${Tables.visits}');
    await txn.rawDelete('DELETE FROM ${Tables.growthMeasurements}');
    await txn.rawDelete('DELETE FROM ${Tables.persons}');
    await txn.rawDelete('DELETE FROM ${Tables.households}');
    await txn.rawDelete('DELETE FROM ${Tables.outbox}');
  });
}

/// A referral as the v7 app wrote it: the follow-up answer is a sentence glued
/// onto `outcome_notes`, and nothing else records that anyone went looking.
Map<String, Object?> _legacyReferralRow() => {
  'id': 'ref-legacy',
  'reference_code': 'CB-7K2M',
  'person_id': 'p-1',
  'assessment_id': 'a-1',
  'facility_name': 'Bawku Municipal Hospital',
  'reason': 'Fast breathing and chest indrawing',
  'urgency': 'sameDay',
  'issued_by': 'u-1',
  'issued_at': DateTime(2026, 9, 18, 9, 5).toIso8601String(),
  'status': 'travelling',
  'status_updated_at': DateTime(2026, 9, 19).toIso8601String(),
  'clinical_summary': 'MUAC 11.2 cm. No danger signs.',
  'arrival_confirmed_by': null,
  'outcome_notes':
      'Self-reported, not facility-verified.\n'
      'Outcome: Yes — reached the facility\n'
      'Notes: Brother drove him in',
  'escalated_at': null,
  'sync_state': 'pending',
};

Map<String, Object?> _legacyContactRow() => {
  'id': 'sc-legacy',
  'person_id': 'p-1',
  'household_id': 'h-1',
  'due_date': DateTime(2026, 9, 21).toIso8601String(),
  'purpose': 'Re-check after referral',
  'created_by': 'u-1',
  'completed_at': null,
  'assessment_id': null,
  'priority': 'urgent',
  'sync_state': 'pending',
};

Map<String, Object?> _legacyHouseholdRow() => {
  'id': 'h-1',
  'name': 'The Abanga family',
  'region': 'Upper East Region',
  'district': 'Bawku Municipal',
  'community': 'Zenuoye',
  'created_by': 'u-1',
  'created_at': DateTime(2026, 8, 2).toIso8601String(),
  'updated_at': DateTime(2026, 8, 2).toIso8601String(),
};

Map<String, Object?> _legacyPersonRow() => {
  'id': 'p-1',
  'household_id': 'h-1',
  'full_name': 'Abanga Kambili',
  'client_type': 'childUnderFive',
  'sex': 'male',
  'age_years_approx': 2,
  'is_active': 1,
  'created_at': DateTime(2026, 8, 2).toIso8601String(),
  'updated_at': DateTime(2026, 8, 2).toIso8601String(),
};

void main() {
  late Database db;

  setUp(() async {
    db = await AppDatabase.openInMemory();
    await _downgradeToV7(db);
    await db.insert(Tables.households, _legacyHouseholdRow());
    await db.insert(Tables.persons, _legacyPersonRow());
    await db.insert(Tables.referrals, _legacyReferralRow());
    await db.insert(Tables.scheduledContacts, _legacyContactRow());
  });

  tearDown(() async {
    if (db.isOpen) await db.close();
  });

  group('v7 to v8', () {
    test('adds the answer ledger without touching the old columns', () async {
      expect(await _hasTable(db, Tables.followUpContacts), isFalse);

      await AppDatabase.upgradeForTesting(db, 7);

      expect(await _hasTable(db, Tables.followUpContacts), isTrue);
      expect(
        await _columns(db, Tables.followUpContacts),
        containsAll([
          'id',
          'referral_id',
          'household_id',
          'at',
          'channel',
          'reached',
          'care',
          'condition',
          'barriers',
          'note',
          'linked_referral_id',
          'recorded_by',
        ]),
      );
    });

    test('links referrals and the contacts that chase them', () async {
      await AppDatabase.upgradeForTesting(db, 7);

      expect(
        await _columns(db, Tables.referrals),
        contains('link_from_referral_id'),
      );
      expect(
        await _columns(db, Tables.scheduledContacts),
        contains('referral_id'),
      );
    });

    test('leaves every legacy referral exactly as the family left it', () async {
      await AppDatabase.upgradeForTesting(db, 7);

      final rows = await db.query(
        Tables.referrals,
        where: 'id = ?',
        whereArgs: ['ref-legacy'],
      );
      final referral = Referral.fromMap(rows.single);

      // The old prose answer stays readable: it is the only record of what the
      // family said, and dropping it would delete history.
      expect(referral.status, ReferralStatus.travelling);
      expect(referral.outcomeNotes, contains('reached the facility'));
      expect(referral.clinicalSummary, contains('MUAC 11.2'));
      expect(referral.issuedAt, DateTime(2026, 9, 18, 9, 5));
      expect(referral.linkFromReferralId, isNull);
    });

    test('starts the ledger empty instead of inventing past answers', () async {
      await AppDatabase.upgradeForTesting(db, 7);

      final seeded = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM ${Tables.followUpContacts}',
      );
      expect((seeded.first['c'] as num).toInt(), 0);

      // A v7 scheduled contact has no referral to chase: the old app never knew
      // the link, so guessing one would put a fake obligation on a real family.
      final contact = ScheduledContact.fromMap(
        (await db.query(
          Tables.scheduledContacts,
          where: 'id = ?',
          whereArgs: ['sc-legacy'],
        )).single,
      );
      expect(contact.referralId, isNull);
      expect(contact.purpose, 'Re-check after referral');
    });

    test('accepts a real answer on the upgraded device', () async {
      await AppDatabase.upgradeForTesting(db, 7);

      final contact = FollowUpContact(
        id: 'fc-1',
        referralId: 'ref-legacy',
        personId: 'p-1',
        householdId: 'h-1',
        at: DateTime(2026, 9, 25, 8, 40),
        channel: FollowUpChannel.householdVisit,
        reached: FollowUpReach.went,
        care: FollowUpCare.seenTreated,
        condition: FollowUpCondition.better,
        recordedBy: 'u-1',
      );
      await db.insert(Tables.followUpContacts, contact.toMap());

      final stored = FollowUpContact.fromMap(
        (await db.query(
          Tables.followUpContacts,
          where: 'id = ?',
          whereArgs: ['fc-1'],
        )).single,
      );
      expect(stored.referralId, 'ref-legacy');
      expect(stored.care, FollowUpCare.seenTreated);
      expect(stored.isAnswered, isTrue);
    });

    test('an upgraded device still reports the same completion count', () async {
      final before = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM ${Tables.referrals}',
      );
      await AppDatabase.upgradeForTesting(db, 7);
      final after = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM ${Tables.referrals}',
      );
      expect((after.first['c'] as num).toInt(), (before.first['c'] as num).toInt());
    });
  });

  group('fresh install', () {
    test('ships the ledger and both chain columns without a migration', () async {
      // sqflite_common_ffi hands out one connection per `:memory:` path, so the
      // downgraded handle has to go before a genuinely new database appears.
      await db.close();
      final fresh = await AppDatabase.openInMemory();
      // openInMemory is onCreate-only at the current version, so nothing has
      // run through _upgrade: the columns must already exist.
      expect(await _hasTable(fresh, Tables.followUpContacts), isTrue);
      expect(
        await _columns(fresh, Tables.referrals),
        contains('link_from_referral_id'),
      );
      expect(
        await _columns(fresh, Tables.scheduledContacts),
        contains('referral_id'),
      );
      await fresh.close();
    });
  });
}
