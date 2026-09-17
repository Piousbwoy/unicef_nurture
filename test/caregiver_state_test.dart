import 'dart:io';
import 'dart:convert';
import 'package:carebridge_ai/domain/engines/recommendation_engine.dart';

import 'package:carebridge_ai/data/local/app_database.dart';
import 'package:carebridge_ai/data/repositories/care_repository.dart';
import 'package:carebridge_ai/domain/entities/caregiver.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:carebridge_ai/domain/services/caregiver_check_policy.dart';
import 'package:carebridge_ai/domain/services/caregiver_milestone_policy.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 8, 10, 9);
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
  final person = Person(
    id: 'baby',
    householdId: 'family',
    fullName: 'Awah',
    clientType: ClientType.newborn,
    dateOfBirth: DateTime(2026, 8, 1),
  );
  final repo = CareRepository(clock: () => now);
  late Database db;
  CaregiverDraft draft({
    String id = 'session',
    String personId = 'baby',
    CaregiverScope owner = scope,
    Map<String, CaregiverAnswer> answers = const {'feed': CaregiverAnswer.yes},
  }) => CaregiverDraft(
    id: id,
    scope: owner,
    personId: personId,
    kind: CaregiverDraftKind.homeCheck,
    questionVersion: CaregiverCheckPolicy.questionVersion,
    cohortKey: CaregiverCheckPolicy(
      clock: () => now,
    ).questionsFor(person)!.cohortKey,
    answers: answers,
    startedAt: now,
    updatedAt: now,
    onsetNote: 'Since morning',
  );
  CaregiverActivity activity({
    String id = 'activity',
    String day = '2026-08-10',
    String source = 'everyday',
    String item = 'feeding',
    String personId = 'baby',
    CaregiverObservation? observation,
    CaregiverActivityKind kind = CaregiverActivityKind.dailyTask,
    bool done = true,
    String note = '',
  }) => CaregiverActivity(
    id: id,
    scope: scope,
    personId: personId,
    kind: kind,
    sourceId: source,
    itemKey: item,
    observation: observation,
    occurrenceKey: day,
    occurredAt: now,
    updatedAt: now,
    done: done,
    note: note,
  );
  const counseling = RecommendedAction(instruction: 'Discuss feeding support',
    urgency: ReferralUrgency.scheduled, isCounselling: true);
  const treatment = RecommendedAction(instruction: 'Clinic procedure',
    urgency: ReferralUrgency.immediate, isTreatment: true);
  Future<void> seedPlan(String id, {String personId = 'baby'}) async {
    await db.insert(Tables.visits, Visit(id: 'visit-$id', householdId: 'family',
      conductedBy: user.id, startedAt: now, reasons: const []).toMap());
    const result = AssessmentResult(clientType: ClientType.newborn, triage: TriageLevel.routine,
      classification: 'Saved advice', findings: [], actions: [counseling, treatment],
      confidence: RecommendationConfidence.high);
    await db.insert(Tables.assessments, Assessment(id: id, visitId: 'visit-$id',
      personId: personId, clientType: ClientType.newborn, performedBy: user.id, performedAt: now,
      inputs: const {}, result: result,
      carePlanJson: jsonEncode(RecommendationEngine.synthesize(results: [result]).toJson())).toMap());
  }

  setUp(() async {
    final dir = Directory.systemTemp.createTempSync('carebridge_caregiver');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? dir.path
              : null,
        );
    AppDatabase.initialiseForDesktopAndTests();
    db = await AppDatabase.instance.database;
    await db.insert(
      Tables.users,
      user.toMap()..['linked_household_id'] = 'family',
    );
    await db.insert(Tables.users, {
      ...user.toMap(),
      'id': 'other',
      'phone': '0240000002',
      'linked_household_id': 'family',
    });
    for (final id in ['family', 'another']) {
      await db.insert(
        Tables.households,
        Household(
          id: id,
          name: id,
          region: user.region,
          district: user.district,
          community: user.community,
          createdBy: user.id,
        ).toMap(),
      );
    }
    await db.insert(Tables.persons, person.toMap());
    await db.insert(Tables.persons, {
      ...person.toMap(),
      'id': 'foreign',
      'household_id': 'another',
    });
  });
  tearDown(() => AppDatabase.instance.close());

  test('v6 upgrade preserves records and matches fresh v7 schema', () async {
    Future<List<Map<String, Object?>>> schema(
      Database database,
    ) => database.rawQuery(
      "SELECT name, sql FROM sqlite_master WHERE tbl_name IN ('caregiver_drafts','caregiver_activity','caregiver_settings') ORDER BY name",
    );
    final fresh = await schema(db);
    final legacy = HomeCheck(
      id: 'legacy',
      householdId: 'family',
      personId: 'baby',
      clientType: ClientType.newborn,
      verdict: HomeCheckVerdict.caution,
      yesSigns: const [],
      unsureSigns: const ['Feeding'],
      checkedBy: user.id,
      checkedAt: now,
    );
    await db.insert(Tables.homeChecks, legacy.toMap());
    await db.insert(Tables.syncState, {
      'key': 'watermark',
      'value': 'unchanged',
      'updated_at': now.toIso8601String(),
    });
    for (final table in [
      Tables.caregiverDrafts,
      Tables.caregiverActivity,
      Tables.caregiverSettings,
    ]) {
      await db.execute('DROP TABLE $table');
    }
    await db.setVersion(6);
    await AppDatabase.instance.close();
    db = await AppDatabase
        .instance
        .database; // Actual production onUpgrade callback.
    expect(await db.getVersion(), 7);
    expect(await schema(db), fresh);
    expect((await repo.homeChecks(user, 'family')).single.id, 'legacy');
    expect((await db.query(Tables.syncState)).single['value'], 'unchanged');
    expect((await db.query(Tables.persons)).length, 2);
  });

  test('draft and settings survive database close and reopen', () async {
    await repo.saveCaregiverDraft(user, draft());
    await repo.saveCaregiverSettings(
      user,
      CaregiverSettings(
        scope: scope,
        updatedAt: now,
        selectedPersonId: 'baby',
        foodsHave: {'Millet'},
        foodsAvoid: {'Groundnut paste'},
        contacts: const [
          SupportContact(
            kind: SupportContactKind.transport,
            name: 'Neighbor',
            number: '0240000003',
            landmark: 'Market',
          ),
        ],
      ),
    );
    await AppDatabase.instance.close();
    expect(
      (await repo.caregiverDraft(
        user,
        scope,
        'baby',
        CaregiverDraftKind.homeCheck,
      ))!.onsetNote,
      'Since morning',
    );
    final settings = (await repo.caregiverSettings(user, scope))!;
    expect(settings.foodsHave, {'Millet'});
    expect(settings.foodsAvoid, {'Groundnut paste'});
    expect(settings.contacts.single.landmark, 'Market');
  });

  test('concurrent finalization is idempotent and local-only', () async {
    await repo.saveCaregiverDraft(user, draft());
    final saved = await Future.wait(
      List.generate(4, (_) => repo.finalizeCaregiverHomeCheck(user, draft())),
    );
    expect(saved.map((r) => r.id).toSet(), {'session'});
    expect(
      saved.every(
        (r) => r.checkedAt == now && r.verdict == HomeCheckVerdict.urgent,
      ),
      isTrue,
    );
    expect(
      await repo.caregiverDraft(
        user,
        scope,
        'baby',
        CaregiverDraftKind.homeCheck,
      ),
      isNull,
    );
    final context = (await repo.caregiverActivity(user, scope)).single;
    expect(context.detail['answers'], {
      'feed': 'yes',
    }); // Unasked signs stay absent.
    expect(await db.query(Tables.homeChecks), hasLength(1));
    expect(await db.query(Tables.outbox), isEmpty);
    await expectLater(
      repo.saveCaregiverDraft(user, draft()),
      throwsA(isA<CaregiverDataException>()),
    );
    await expectLater(
      repo.finalizeCaregiverHomeCheck(
        user,
        draft(answers: {'fits': CaregiverAnswer.yes}),
      ),
      throwsA(isA<CaregiverDataException>()),
    );
  });

  test(
    'failed finalization rolls back the report and preserves a retryable draft',
    () async {
      await repo.saveCaregiverDraft(user, draft());
      await db.execute(
        "CREATE TRIGGER fail_context BEFORE INSERT ON caregiver_activity BEGIN SELECT RAISE(ABORT, 'test storage failure'); END",
      );
      await expectLater(
        repo.finalizeCaregiverHomeCheck(user, draft()),
        throwsA(isA<DatabaseException>()),
      );
      expect(await db.query(Tables.homeChecks), isEmpty);
      expect(
        await repo.caregiverDraft(
          user,
          scope,
          'baby',
          CaregiverDraftKind.homeCheck,
        ),
        isNotNull,
      );
      await db.execute('DROP TRIGGER fail_context');
      expect(
        (await repo.finalizeCaregiverHomeCheck(user, draft())).id,
        'session',
      );
    },
  );

  test('owner, household, person and persisted role are enforced', () async {
    await expectLater(
      repo.saveCaregiverDraft(
        user,
        draft(
          owner: const CaregiverScope(userId: 'other', householdId: 'family'),
        ),
      ),
      throwsA(isA<AccessDenied>()),
    );
    await expectLater(
      repo.caregiverSettings(
        user,
        const CaregiverScope(userId: 'caregiver', householdId: 'another'),
      ),
      throwsA(isA<AccessDenied>()),
    );
    await expectLater(
      repo.saveCaregiverDraft(user, draft(personId: 'foreign')),
      throwsA(isA<AccessDenied>()),
    );
    await expectLater(
      repo.saveCaregiverSettings(
        user,
        CaregiverSettings(
          scope: scope,
          updatedAt: now,
          selectedPersonId: 'foreign',
        ),
      ),
      throwsA(isA<AccessDenied>()),
    );
    await db.update(
      Tables.users,
      {'role': 'frontlineHealthWorker'},
      where: 'id = ?',
      whereArgs: [user.id],
    );
    await expectLater(
      repo.saveCaregiverDraft(user, draft()),
      throwsA(isA<CaregiverDataException>()),
    );
  });

  test(
    'relink denies stale scope and account switching isolates records',
    () async {
      await repo.saveCaregiverDraft(user, draft());
      final other = AppUser.fromMap({...user.toMap(), 'id': 'other'});
      expect(
        await repo.caregiverDraft(
          other,
          const CaregiverScope(userId: 'other', householdId: 'family'),
          'baby',
          CaregiverDraftKind.homeCheck,
        ),
        isNull,
      );
      await db.update(
        Tables.users,
        {'linked_household_id': 'another'},
        where: 'id = ?',
        whereArgs: [user.id],
      );
      await expectLater(
        repo.caregiverDraft(user, scope, 'baby', CaregiverDraftKind.homeCheck),
        throwsA(isA<AccessDenied>()),
      );
    },
  );

  test('draft ID collisions cannot overwrite another caregiver', () async {
    await repo.saveCaregiverDraft(user, draft());
    final other = AppUser.fromMap({...user.toMap(), 'id': 'other'});
    await expectLater(
      repo.saveCaregiverDraft(
        other,
        draft(
          owner: const CaregiverScope(userId: 'other', householdId: 'family'),
        ),
      ),
      throwsA(isA<CaregiverDataException>()),
    );
  });

  test(
    'daily task undo is serialized; dates and plan identities are independent',
    () async {
      await Future.wait([
        repo.saveCaregiverActivity(user, activity()),
        repo.saveCaregiverActivity(user, activity(done: false)),
      ]);
      expect((await repo.caregiverActivity(user, scope)).single.done, isFalse);
      await repo.saveCaregiverActivity(
        user,
        activity(id: 'tomorrow', day: '2026-08-11'),
      );
      for (final id in ['assessment1', 'assessment2']) {
        await seedPlan(id);
        await repo.saveCaregiverActivity(user, activity(id: 'progress-$id',
          source: id, day: id, item: jsonEncode(counseling.toJson()), kind: CaregiverActivityKind.planAction));
      }
      expect(await repo.caregiverActivity(user, scope), hasLength(4));
      expect(await db.query(Tables.outbox), isEmpty);
    },
  );

  test(
    'caregiver observations are append-only and cannot finalize reports',
    () async {
      await repo.saveCaregiverActivity(
        user,
        activity(kind: CaregiverActivityKind.note, note: 'Tired today'),
      );
      await expectLater(
        repo.saveCaregiverActivity(
          user,
          activity(kind: CaregiverActivityKind.note, note: 'Changed history'),
        ),
        throwsA(isA<CaregiverDataException>()),
      );
      await expectLater(
        repo.saveCaregiverActivity(
          user,
          activity(kind: CaregiverActivityKind.homeCheckContext),
        ),
        throwsA(isA<CaregiverDataException>()),
      );
    },
  );

  test('malformed and unsupported JSON fail explicitly', () async {
    await repo.saveCaregiverSettings(
      user,
      CaregiverSettings(scope: scope, updatedAt: now),
    );
    for (final content in ['not json', '{"version":99}']) {
      await db.update(Tables.caregiverSettings, {'content_json': content});
      await expectLater(
        repo.caregiverSettings(user, scope),
        throwsA(isA<CaregiverDataException>()),
      );
    }
    await repo.saveCaregiverDraft(user, draft());
    await db.update(Tables.caregiverDrafts, {'content_json': '{}'});
    await expectLater(
      repo.caregiverDraft(user, scope, 'baby', CaregiverDraftKind.homeCheck),
      throwsA(isA<CaregiverDataException>()),
    );
    await repo.discardCaregiverDraft(
      user,
      scope,
      'baby',
      CaregiverDraftKind.homeCheck,
    );
    expect(
      await repo.caregiverDraft(
        user,
        scope,
        'baby',
        CaregiverDraftKind.homeCheck,
      ),
      isNull,
    );
  });

  test(
    'partial all-NO cannot finalize; one unsure cannot become routine',
    () async {
      await expectLater(
        repo.finalizeCaregiverHomeCheck(
          user,
          draft(answers: {'feed': CaregiverAnswer.no}),
        ),
        throwsA(isA<CaregiverDataException>()),
      );
      final result = await repo.finalizeCaregiverHomeCheck(
        user,
        draft(answers: {'feed': CaregiverAnswer.unsure}),
      );
      expect(result.verdict, HomeCheckVerdict.caution);
    },
  );

  test(
    'milestones finalize atomically with existing screening semantics',
    () async {
      final band = CaregiverMilestonePolicy.bandFor(person, now)!;
      final session = CaregiverDraft(
        id: 'milestone',
        scope: scope,
        personId: person.id,
        kind: CaregiverDraftKind.milestone,
        questionVersion: CaregiverMilestonePolicy.questionVersion,
        cohortKey: CaregiverMilestonePolicy.cohortKey(person, band),
        answers: {for (final m in band.milestones) m.id: CaregiverAnswer.no},
        startedAt: now,
        updatedAt: now,
      );
      await repo.saveCaregiverDraft(user, session);
      final check = await repo.finalizeCaregiverMilestone(user, session);
      expect(
        check.flags,
        band.milestones.where((m) => m.isFlag).map((m) => m.question),
      );
      expect(
        await repo.caregiverDraft(
          user,
          scope,
          person.id,
          CaregiverDraftKind.milestone,
        ),
        isNull,
      );
      expect(await repo.milestoneChecks(user, 'family'), hasLength(1));
      expect(await db.query(Tables.outbox), isEmpty);
    },
  );

  test('plan progress rejects treatments, fabricated actions and wrong sources', () async {
    await seedPlan('assessment');
    for (final item in [jsonEncode(treatment.toJson()), 'invented']) {
      await expectLater(repo.saveCaregiverActivity(user, activity(source: 'assessment', day: 'assessment',
        item: item, kind: CaregiverActivityKind.planAction)), throwsA(isA<CaregiverDataException>()));
    }
    for (final source in ['missing', 'foreign-plan']) {
      if (source == 'foreign-plan') await seedPlan(source, personId: 'foreign');
      await expectLater(repo.saveCaregiverActivity(user, activity(source: source, day: source,
        item: jsonEncode(counseling.toJson()), kind: CaregiverActivityKind.planAction)), throwsA(isA<CaregiverDataException>()));
    }
    expect(await repo.caregiverActivity(user, scope), isEmpty);
  });

  test('later observations and arrivals must match the original person', () async {
    await repo.finalizeCaregiverHomeCheck(user, draft());
    for (final kind in [CaregiverActivityKind.observation, CaregiverActivityKind.arrival]) {
      await expectLater(repo.saveCaregiverActivity(user, activity(kind: kind,
        source: 'missing', observation: CaregiverObservation.better)), throwsA(isA<CaregiverDataException>()));
      await repo.saveCaregiverActivity(user, activity(id: kind.name, kind: kind,
        source: 'session', observation: CaregiverObservation.better));
    }
    expect((await repo.homeChecks(user, 'family')).single.verdict, HomeCheckVerdict.urgent);
    expect(await db.query(Tables.outbox), isEmpty);
  });

  test('support contact validation rejects unsafe numbers and duplicate slots', () async {
    for (final number in ['*123#', 'tel:112', '+12+3456', '', '12']) {
      await expectLater(repo.saveCaregiverSettings(user, CaregiverSettings(scope: scope, updatedAt: now,
        contacts: [SupportContact(kind: SupportContactKind.transport, name: 'Neighbor', number: number)])),
        throwsA(isA<CaregiverDataException>()));
    }
    const contact = SupportContact(kind: SupportContactKind.transport, name: 'Neighbor', number: '+233 24 000 0003');
    await expectLater(repo.saveCaregiverSettings(user, CaregiverSettings(scope: scope, updatedAt: now,
      contacts: const [contact, contact])), throwsA(isA<CaregiverDataException>()));
    await repo.saveCaregiverSettings(user, CaregiverSettings(scope: scope, updatedAt: now, contacts: const [contact]));
    expect((await repo.caregiverSettings(user, scope))!.contacts.single.number, contact.number);
  });

  test('device reset clears all companion state', () async {
    await repo.saveCaregiverDraft(user, draft());
    await repo.saveCaregiverActivity(user, activity());
    await repo.saveCaregiverSettings(
      user,
      CaregiverSettings(scope: scope, updatedAt: now),
    );
    await AppDatabase.instance.clearAll();
    for (final table in [
      Tables.caregiverDrafts,
      Tables.caregiverActivity,
      Tables.caregiverSettings,
      Tables.users,
      Tables.persons,
    ]) {
      expect(await db.query(table), isEmpty);
    }
  });
}
