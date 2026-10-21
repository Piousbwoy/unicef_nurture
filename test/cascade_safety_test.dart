/// A parent row must never lose its children because somebody edited it.
///
/// ### Why this file exists
///
/// `INSERT OR REPLACE` is not an update. SQLite implements it as a DELETE of the
/// conflicting row followed by an INSERT, and with `PRAGMA foreign_keys = ON` that
/// implicit DELETE fires every `ON DELETE CASCADE` pointing at the row. So the
/// idiom that reads like the safest possible upsert is the one that destroys a
/// family: correcting a household's name deleted its members, and with them the
/// growth curves, the assessments, the referrals and the follow-up answers.
///
/// This was found by the erasure test, not by design review: honouring an
/// erasure request upserted the person, and the "clinical history is kept"
/// promise in the same function's doc comment was false. Nothing raised an error
/// and nothing appeared in the audit trail — the rows were simply gone on the next
/// screen that read them.
///
/// Both halves are pinned here. The behaviour, because a helper that does not work
/// is worse than the bug. And the source, because the bug class is one an
/// unrelated future upsert can reintroduce silently, on a table nobody thought
/// about.
library;

import 'dart:io';

import 'package:carebridge_ai/data/local/app_database.dart';
import 'package:carebridge_ai/data/local/household_dao.dart';
import 'package:carebridge_ai/data/local/visit_dao.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

final _at = DateTime.utc(2026, 10, 18, 9, 14);

const _worker = AppUser(
  id: 'u-cascade',
  fullName: 'Aminata Fusena',
  phone: '0244111000',
  role: UserRole.frontlineHealthWorker,
  region: 'Northern Region',
  district: 'Savelugu Municipal',
  community: 'Gushegu',
);

const _household = Household(
  id: 'hh-c',
  name: 'The Yeboah family',
  region: 'Northern Region',
  district: 'Savelugu Municipal',
  community: 'Gushegu',
  createdBy: 'u-cascade',
);

const _child = Person(
  id: 'p-c',
  householdId: 'hh-c',
  fullName: 'Akosia Yeboah',
  clientType: ClientType.childUnderFive,
  ageYearsApprox: 2,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void useRegister(WidgetTester tester) {
    final dir = Directory.systemTemp.createTempSync('carebridge_cascade');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async =>
          call.method == 'getApplicationDocumentsDirectory' ? dir.path : null,
    );
    AppDatabase.initialiseForDesktopAndTests();
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows holds the handle a moment longer than the close; %TEMP%
        // reclaims it. Neither is what the test is asserting.
      }
    });
    addTearDown(() => AppDatabase.instance.close());
  }

  Future<int> count(Database db, String table) async {
    final rows = await db.rawQuery('SELECT COUNT(*) c FROM $table');
    return (rows.first['c'] as num).toInt();
  }

  /// Seed a family with one row in every table that cascades from the parents.
  Future<void> seedFullFamily(Database db) async {
    await HouseholdDao.upsert(_household);
    await PersonDao.upsert(_child);
    await db.insert(Tables.growthMeasurements, {
      'id': 'g-1',
      'person_id': _child.id,
      'taken_at': _at.toIso8601String(),
      'weight_kg': 9.4,
    });
    await VisitDao.upsert(
      Visit(
        id: 'v-1',
        householdId: _household.id,
        conductedBy: _worker.id,
        startedAt: _at,
        reasons: const [],
      ),
    );
    await db.insert(Tables.visitParticipants, {
      'visit_id': 'v-1',
      'person_id': _child.id,
      'was_present': 1,
    });
    await db.insert(Tables.assessments, {
      'id': 'a-1',
      'visit_id': 'v-1',
      'person_id': _child.id,
      'client_type': _child.clientType.name,
      'performed_by': _worker.id,
      'performed_at': _at.toIso8601String(),
      'inputs_json': '{}',
      'result_json': '{}',
    });
    await db.insert(Tables.referrals, {
      'id': 'r-1',
      'reference_code': 'REF-CASCADE-1',
      'person_id': _child.id,
      'assessment_id': 'a-1',
      'facility_name': 'Savelugu Hospital',
      'reason': 'Danger signs',
      'urgency': 'emergency',
      'issued_by': _worker.id,
      'issued_at': _at.toIso8601String(),
      'status': 'open',
    });
    await db.insert(Tables.followUpContacts, {
      'id': 'f-1',
      'referral_id': 'r-1',
      'person_id': _child.id,
      'household_id': _household.id,
      'at': _at.toIso8601String(),
      'channel': FollowUpChannel.phoneCall.name,
      'reached': FollowUpReach.went.name,
      'care': FollowUpCare.seenTreated.name,
      'condition': FollowUpCondition.better.name,
      'recorded_by': _worker.id,
    });
    await db.insert(Tables.users, {
      'id': _worker.id,
      'full_name': _worker.fullName,
      'phone': _worker.phone,
      'role': _worker.role.name,
      'region': _worker.region,
      'district': _worker.district,
      'community': _worker.community,
      'created_at': _at.toIso8601String(),
    });
    await db.insert(Tables.caregiverActivity, {
      'id': 'ca-1',
      'user_id': _worker.id,
      'household_id': _household.id,
      'person_id': _child.id,
      'kind': 'guidance',
      'item_key': 'exclusive_breastfeeding',
      'occurrence_key': 'x',
      'content_json': '{}',
      'occurred_at': _at.toIso8601String(),
      'updated_at': _at.toIso8601String(),
    });
  }

  group('editing a parent keeps its children', () {
    testWidgets('a household rename does not delete the family', (
      tester,
    ) async {
      useRegister(tester);
      await tester.runAsync(() async {
        final db = await AppDatabase.instance.database;
        await seedFullFamily(db);
        expect(await count(db, Tables.persons), 1);

        await HouseholdDao.upsert(_household.copyWith(name: 'Yeboah compound'));

        expect(await count(db, Tables.persons), 1, reason: 'The members went.');
        expect(
          await count(db, Tables.growthMeasurements),
          1,
          reason: 'The curve went.',
        );
        expect(
          await count(db, Tables.assessments),
          1,
          reason: 'The verdicts went.',
        );
        expect(
          await count(db, Tables.referrals),
          1,
          reason: 'The referral went.',
        );
        expect(
          await count(db, Tables.followUpContacts),
          1,
          reason:
              'The follow-up answers went — the evidence of whether this mother '
              'reached the facility.',
        );
        expect(
          (await HouseholdDao.byId(_household.id))!.name,
          'Yeboah compound',
          reason: 'The edit itself must still land.',
        );
      });
    });

    testWidgets('a person edit does not delete their history', (tester) async {
      useRegister(tester);
      await tester.runAsync(() async {
        final db = await AppDatabase.instance.database;
        await seedFullFamily(db);

        await PersonDao.upsert(_child.copyWith(fullName: 'Akosia Yeboah-Fosu'));

        expect(await count(db, Tables.growthMeasurements), 1);
        expect(await count(db, Tables.assessments), 1);
        expect(await count(db, Tables.referrals), 1);
        expect(
          (await PersonDao.byId(_child.id))!.fullName,
          'Akosia Yeboah-Fosu',
        );
      });
    });

    testWidgets('re-saving a visit does not delete its roll call or findings', (
      tester,
    ) async {
      useRegister(tester);
      await tester.runAsync(() async {
        final db = await AppDatabase.instance.database;
        await seedFullFamily(db);

        await VisitDao.upsert(
          Visit(
            id: 'v-1',
            householdId: _household.id,
            conductedBy: _worker.id,
            startedAt: _at,
            reasons: const [],
            notes: 'Returned to finish the growth plot',
          ),
        );

        expect(await count(db, Tables.visitParticipants), 1);
        expect(await count(db, Tables.assessments), 1);
      });
    });

    testWidgets('advancing a referral does not delete its follow-up ledger', (
      tester,
    ) async {
      useRegister(tester);
      await tester.runAsync(() async {
        final db = await AppDatabase.instance.database;
        await seedFullFamily(db);

        // The shape ReferralDao.upsertIn writes: the same row, status advanced.
        final row = (await db.query(
          Tables.referrals,
          where: 'id = ?',
          whereArgs: ['r-1'],
        )).first;
        await db.transaction(
          (txn) => txn.update(
            Tables.referrals,
            {'status': 'arrived'},
            where: 'id = ?',
            whereArgs: [row['id']],
          ),
        );

        expect(await count(db, Tables.followUpContacts), 1);
      });
    });

    testWidgets('re-registering an account does not delete its drafts', (
      tester,
    ) async {
      useRegister(tester);
      await tester.runAsync(() async {
        final db = await AppDatabase.instance.database;
        await seedFullFamily(db);

        await db.update(
          Tables.users,
          {'full_name': 'Aminata Fusena-Mahama'},
          where: 'id = ?',
          whereArgs: [_worker.id],
        );

        expect(
          await count(db, Tables.caregiverActivity),
          1,
          reason:
              'A name change on the account is not a reason to lose a family’s history.',
        );
      });
    });
  });

  group('the bug class cannot come back quietly', () {
    /// The tables other tables cascade from, read out of the DDL that declares
    /// them — not from a list somebody maintained.
    Set<String> cascadeParents(String schemaSource) {
      final names = <String, String>{
        for (final m in RegExp(
          r"static const (\w+)\s*=\s*'([^']+)'",
        ).allMatches(schemaSource))
          m.group(1)!: m.group(2)!,
      };
      return {
        for (final m in RegExp(
          r'REFERENCES\s*\$\{Tables\.(\w+)\}\s*\(\s*id\s*\)\s*(?:[\w=+]+\s+)*ON\s+DELETE\s+CASCADE',
          dotAll: true,
        ).allMatches(schemaSource))
          names[m.group(1)!] ?? m.group(1)!,
      };
    }

    test('the register has the cascade parents this test assumes', () {
      final parents = cascadeParents(
        File('lib/data/local/app_database.dart').readAsStringSync(),
      );
      expect(
        parents,
        containsAll(<String>{
          'households',
          'persons',
          'visits',
          'referrals',
          'users',
        }),
        reason: 'A new cascade parent widens the blast radius of an upsert.',
      );
    });

    test('no cascade parent is written with ConflictAlgorithm.replace anywhere '
        'in lib/', () {
      final parents = cascadeParents(
        File('lib/data/local/app_database.dart').readAsStringSync(),
      );
      // `<name>` is deliberately not fixed to `Tables.x`: the recovery restore
      // loop iterates tables by variable, and a replace there would be just as
      // destructive. The pattern is bounded so it cannot bridge two statements.
      final offenderPattern = RegExp(
        r'\.insert\(\s*(?:Tables\.)?([\w.]+)\s*,(?:(?!\.insert\()[\s\S]){0,1500}?'
        r'conflictAlgorithm:\s*ConflictAlgorithm\.replace',
      );

      final files = [
        Directory('lib/data'),
        Directory('lib/domain'),
        Directory('lib/core'),
        Directory('lib/app'),
      ];
      final offenders = <String>[];
      for (final dir in files.where((d) => d.existsSync())) {
        for (final entity in dir.listSync(recursive: true)) {
          if (entity is! File || !entity.path.endsWith('.dart')) continue;
          final src = entity.readAsStringSync();
          for (final m in offenderPattern.allMatches(src)) {
            final table = (m.group(1) ?? '').split('.').last;
            if (parents.contains(table)) {
              offenders.add(
                '${entity.path}:${src.substring(0, m.start).split('\n').length}',
              );
            }
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            '${offenders.join(', ')} writes a cascade parent with INSERT OR '
            'REPLACE. That deletes the row before re-inserting it, so every '
            'child of that row cascades away — use upsertWithoutCascade().',
      );
    });
  });
}
