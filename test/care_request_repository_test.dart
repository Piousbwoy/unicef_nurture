/// Asking for help is not the same permission as running a check.
///
/// A caregiver holds `runCaregiverTriage` because the family's own screen must
/// work. That does not make them entitled to summon a health worker — a request
/// costs a person a walk, and a family in one compound cannot be able to call
/// out the worker assigned to another. The gate is therefore separate, and the
/// household scope is the wall.
library;

import 'dart:io';

import 'package:carebridge_ai/data/local/app_database.dart';
import 'package:carebridge_ai/data/local/care_request_dao.dart';
import 'package:carebridge_ai/data/repositories/care_repository.dart';
import 'package:carebridge_ai/domain/entities/care_request.dart';
import 'package:carebridge_ai/domain/entities/caregiver.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:carebridge_ai/domain/services/caregiver_check_policy.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 9, 28, 9);
  const scope = CaregiverScope(userId: 'caregiver', householdId: 'family');
  const user = AppUser(
    id: 'caregiver',
    fullName: 'Amina',
    phone: '0240000001',
    role: UserRole.caregiver,
    region: 'Northern Region',
    district: 'Karaga',
    community: 'Karaga',
  );
  const worker = AppUser(
    id: 'fhw',
    fullName: 'Abena',
    phone: '0240000009',
    role: UserRole.frontlineHealthWorker,
    region: 'Northern Region',
    district: 'Karaga',
    community: 'Karaga',
  );
  final baby = Person(
    id: 'baby',
    householdId: 'family',
    fullName: 'Awah',
    clientType: ClientType.newborn,
    dateOfBirth: DateTime(2026, 9, 1),
  );
  final repo = CareRepository(clock: () => now);
  late Database db;

  /// A newborn check with one YES, which the policy decides as urgent — the
  /// same answer set caregiver_state_test finalizes to an urgent HomeCheck.
  CaregiverDraft draft({
    String id = 'session',
    String personId = 'baby',
    Map<String, CaregiverAnswer> answers = const {
      'feed': CaregiverAnswer.yes,
    },
  }) => CaregiverDraft(
    id: id,
    scope: scope,
    personId: personId,
    kind: CaregiverDraftKind.homeCheck,
    questionVersion: CaregiverCheckPolicy.questionVersion,
    cohortKey: CaregiverCheckPolicy(
      clock: () => now,
    ).questionsFor(baby)!.cohortKey,
    answers: answers,
    startedAt: now,
    updatedAt: now,
  );

  HomeCheck check({
    String id = 'session',
    String householdId = 'family',
    String personId = 'baby',
    HomeCheckVerdict verdict = HomeCheckVerdict.urgent,
  }) => HomeCheck(
    id: id,
    householdId: householdId,
    personId: personId,
    clientType: ClientType.newborn,
    verdict: verdict,
    yesSigns: const ['Not feeding well'],
    unsureSigns: const [],
    checkedBy: user.id,
    checkedAt: now,
  );

  /// The check saved through the repository, so the draft row exists and the
  /// verdict is the policy's own reading rather than a hand-written one.
  Future<HomeCheck> savedCheck() async {
    await repo.saveCaregiverDraft(user, draft());
    return repo.finalizeCaregiverHomeCheck(user, draft());
  }

  Future<List<Map<String, Object?>>> queued() => db.query(
    Tables.outbox,
    where: 'entity_table = ?',
    whereArgs: [Tables.careRequests],
  );

  setUp(() async {
    final dir = Directory.systemTemp.createTempSync('carebridge_care_request');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? dir.path
              : null,
        );
    AppDatabase.initialiseForDesktopAndTests();
    db = await AppDatabase.instance.database;
    for (final account in [user, worker]) {
      await db.insert(
        Tables.users,
        account.toMap()
          ..['linked_household_id'] = account == user ? 'family' : null,
      );
    }
    for (final id in ['family', 'another']) {
      await db.insert(Tables.households, {
        'id': id,
        'name': id,
        'region': user.region,
        'district': user.district,
        'community': user.community,
        'created_by': user.id,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
    }
    for (final p in [
      baby,
      Person(
        id: 'neighbour',
        householdId: 'another',
        fullName: 'Kofi',
        clientType: ClientType.newborn,
        dateOfBirth: DateTime(2026, 9, 1),
      ),
    ]) {
      await db.insert(Tables.persons, p.toMap());
    }
  });
  tearDown(() => AppDatabase.instance.close());

  group('raiseCareRequest', () {
    test('a caregiver raises one for their own finalized urgent check',
        () async {
      final saved = await savedCheck();

      final raised = await repo.raiseCareRequest(user, scope, saved);

      expect(raised?.level, CareRequestLevel.urgent);
      expect(raised?.homeCheckId, saved.id);
      expect(raised?.householdId, 'family');
      expect(raised?.status, CareRequestStatus.open);
      // The whole point of the record: something left the phone.
      final entries = await queued();
      expect(entries, hasLength(1));
      expect(entries.single['priority'], 0);
      expect(entries.single['entity_id'], 'req-${saved.id}');
    });

    test('a second tap on the same check returns the first request', () async {
      final saved = await savedCheck();
      final first = await repo.raiseCareRequest(user, scope, saved);
      final second = await repo.raiseCareRequest(user, scope, saved);

      expect(second?.id, first?.id);
      expect(await db.query(Tables.careRequests), hasLength(1));
      expect(
        await queued(),
        hasLength(1),
        reason: 'two queue entries would mean two summons for one tap',
      );
    });

    test('a check that came back fine raises nothing', () async {
      expect(
        await repo.raiseCareRequest(
          user,
          scope,
          check(verdict: HomeCheckVerdict.fine),
        ),
        isNull,
      );
      expect(await queued(), isEmpty);
      expect(await db.query(Tables.careRequests), isEmpty);
    });

    test('a caution verdict asks for a visit today, not an emergency',
        () async {
      final raised = await repo.raiseCareRequest(
        user,
        scope,
        check(verdict: HomeCheckVerdict.caution),
      );
      expect(raised?.level, CareRequestLevel.today);
    });

    test('one family cannot ask for another family’s worker', () async {
      await expectLater(
        repo.raiseCareRequest(user, scope, check(householdId: 'another')),
        throwsA(isA<AccessDenied>()),
      );
      expect(await db.query(Tables.careRequests), isEmpty);
      expect(await queued(), isEmpty);
    });

    test('a role without requestCare is refused', () async {
      await expectLater(
        repo.raiseCareRequest(
          worker,
          const CaregiverScope(userId: 'fhw', householdId: 'family'),
          check(),
        ),
        throwsA(isA<AccessDenied>()),
      );
    });
  });

  group('withdrawCareRequest', () {
    test('a request that has not been sent can be called back', () async {
      final saved = await savedCheck();
      await repo.raiseCareRequest(user, scope, saved);

      expect(await repo.withdrawCareRequest(user, scope, saved.id), isTrue);
      expect(await db.query(Tables.careRequests), isEmpty);
      expect(await queued(), isEmpty);
    });

    test('withdrawing another household’s request is refused', () async {
      // Written straight to the table, because the repository would never let
      // this family create it. What is being tested is the read side: a caller
      // who guesses a request id must not be able to cancel someone else's.
      await db.insert(
        Tables.careRequests,
        CareRequest(
          id: 'req-chk-other',
          householdId: 'another',
          personId: 'neighbour',
          level: CareRequestLevel.urgent,
          homeCheckId: 'chk-other',
          createdBy: 'someone-else',
          createdAt: now,
          updatedAt: now,
        ).toMap(),
      );
      await expectLater(
        repo.withdrawCareRequest(user, scope, 'chk-other'),
        throwsA(isA<AccessDenied>()),
      );
      expect(await CareRequestDao.byId('req-chk-other'), isNotNull);
    });

    test('withdrawing a request that was never raised is simply no', () async {
      expect(await repo.withdrawCareRequest(user, scope, 'session'), isFalse);
    });
  });

  group('careRequestState', () {
    test('nothing has been asked, so there is nothing to show', () async {
      final saved = await savedCheck();
      expect(await repo.careRequestState(user, scope, saved.id), isNull);
    });

    test('a queued request reads as asked and not yet sent', () async {
      final saved = await savedCheck();
      await repo.raiseCareRequest(user, scope, saved);

      final state = await repo.careRequestState(user, scope, saved.id);
      expect(state?.request.id, 'req-${saved.id}');
      expect(state?.sent, isFalse);
    });

    test('sent becomes true only when the queue entry has actually gone',
        () async {
      final saved = await savedCheck();
      await repo.raiseCareRequest(user, scope, saved);
      await db.update(
        Tables.outbox,
        {'synced_at': now.add(const Duration(minutes: 2)).toIso8601String()},
        where: 'entity_id = ?',
        whereArgs: ['req-${saved.id}'],
      );

      expect((await repo.careRequestState(user, scope, saved.id))?.sent, isTrue);
    });

    test('an answer stays visible, and cannot be re-raised over', () async {
      final saved = await savedCheck();
      await repo.raiseCareRequest(user, scope, saved);
      await CareRequestDao.markAnsweredIn(db, 'req-${saved.id}', now);

      final state = await repo.careRequestState(user, scope, saved.id);
      expect(state?.request.status, CareRequestStatus.answered);
      // A second tap finds the answered row instead of replacing it: the reply
      // is the family's record, and re-inserting would queue a second summons
      // for a household a worker has already answered.
      final again = await repo.raiseCareRequest(user, scope, saved);
      expect(again?.status, CareRequestStatus.answered);
      expect(await db.query(Tables.careRequests), hasLength(1));
      expect(await queued(), hasLength(1));
    });
  });
}
