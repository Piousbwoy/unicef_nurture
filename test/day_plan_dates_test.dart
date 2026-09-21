import 'dart:io';

import 'package:carebridge_ai/data/local/app_database.dart';
import 'package:carebridge_ai/data/local/household_dao.dart';
import 'package:carebridge_ai/data/local/visit_dao.dart';
import 'package:carebridge_ai/data/repositories/insight_repository.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

ScheduledContact _contact(
  String id,
  DateTime due, {
  String householdId = 'local',
  String personId = 'person-local',
  DateTime? completedAt,
}) => ScheduledContact(
  id: id,
  personId: personId,
  householdId: householdId,
  dueDate: due,
  purpose: 'Care review $id',
  createdBy: 'colleague',
  completedAt: completedAt,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('overdue-only plans are not empty', () {
    final plan = DayPlan(
      priorities: const [],
      dueContacts: const [],
      overdueContacts: [_contact('overdue', DateTime(2026, 8, 31))],
      chaseReferrals: const [],
      generatedAt: DateTime(2026, 9, 1),
    );
    expect(plan.isEmpty, isFalse);
    expect(plan.headline, '1 contact overdue');
  });

  testWidgets('calendar partition and caseload scope use local source records', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('carebridge_day_plan');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async =>
          call.method == 'getApplicationDocumentsDirectory' ? dir.path : null,
    );
    AppDatabase.initialiseForDesktopAndTests();
    try {
      await tester.runAsync(() async {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final yesterday = DateTime(
          today.year,
          today.month,
          today.day - 1,
          23,
          59,
        );
        final tomorrow = DateTime(today.year, today.month, today.day + 1);
        for (final id in ['local', 'own-outside', 'outside']) {
          await HouseholdDao.upsert(
            Household(
              id: id,
              name: '$id household',
              region: id == 'local' ? 'Northern Region' : 'Upper East Region',
              district: id == 'local' ? 'Gushegu' : 'Bawku West',
              community: 'Test community',
              createdBy: id == 'own-outside' ? 'worker' : 'colleague',
            ),
          );
          await PersonDao.upsert(
            Person(
              id: 'person-$id',
              householdId: id,
              fullName: '$id patient',
              clientType: ClientType.womanOfReproductiveAge,
            ),
          );
          await ReferralDao.upsert(
            Referral(
              id: 'referral-$id',
              referenceCode: 'CB-$id',
              personId: 'person-$id',
              assessmentId: 'assessment-$id',
              facilityName: 'District hospital',
              reason: 'Urgent referral from saved assessment',
              urgency: ReferralUrgency.immediate,
              issuedBy: 'colleague',
              issuedAt: today.subtract(const Duration(days: 3)),
            ),
          );
        }
        await PersonDao.upsert(
          const Person(
            id: 'inactive',
            householdId: 'local',
            fullName: 'Inactive patient',
            clientType: ClientType.womanOfReproductiveAge,
            isActive: false,
          ),
        );
        await ScheduleDao.upsertAll([
          _contact('overdue', yesterday),
          _contact('today-midnight', today),
          _contact(
            'today-late',
            DateTime(today.year, today.month, today.day, 23, 59),
          ),
          _contact(
            'today-utc',
            DateTime(today.year, today.month, today.day, 12).toUtc(),
          ),
          _contact('tomorrow', tomorrow),
          _contact('done-today', today, completedAt: now),
          _contact('done-overdue', yesterday, completedAt: now),
          _contact(
            'own-today',
            today,
            householdId: 'own-outside',
            personId: 'person-own-outside',
          ),
          _contact(
            'own-overdue',
            yesterday,
            householdId: 'own-outside',
            personId: 'person-own-outside',
          ),
          _contact(
            'outside-today',
            today,
            householdId: 'outside',
            personId: 'person-outside',
          ),
          _contact(
            'outside-overdue',
            yesterday,
            householdId: 'outside',
            personId: 'person-outside',
          ),
          _contact('wrong-person', today, personId: 'person-outside'),
          _contact('wrong-household', today, householdId: 'outside'),
          _contact(
            'mismatched-within-scope',
            today,
            householdId: 'own-outside',
          ),
          _contact('inactive', today, personId: 'inactive'),
        ]);
        final db = await AppDatabase.instance.database;
        final beforeContacts = await db.query(Tables.scheduledContacts);
        final beforeReferrals = await db.query(Tables.referrals);
        final beforeOutbox = await db.query(Tables.outbox);
        // Pin the DAO's rolling-horizon behaviour that caused the duplication.
        final raw = await ScheduleDao.due(horizonDays: 0);
        expect(raw.map((c) => c.id), containsAll(['overdue', 'tomorrow']));

        final plan = await InsightRepository().planDay(
          workerId: 'worker',
          region: 'Northern Region',
          district: 'Gushegu',
        );
        final dueIds = plan.dueContacts.map((c) => c.id).toSet();
        final overdueIds = plan.overdueContacts.map((c) => c.id).toSet();
        expect(dueIds, {
          'today-midnight',
          'today-late',
          'today-utc',
          'own-today',
        });
        expect(overdueIds, {'overdue', 'own-overdue'});
        expect(dueIds.intersection(overdueIds), isEmpty);
        expect(plan.priorities.map((p) => p.household.id).toSet(), {
          'local',
          'own-outside',
        });
        expect(plan.chaseReferrals.map((r) => r.id).toSet(), {
          'referral-local',
          'referral-own-outside',
        });
        expect(
          plan.priorities.map((p) => p.nextContactDue!.id).toSet(),
          overdueIds,
        );
        // Planning is read-only: no completed contacts, changed referral statuses
        // or new outbound work merely from opening a plan.
        expect(await db.query(Tables.scheduledContacts), beforeContacts);
        expect(await db.query(Tables.referrals), beforeReferrals);
        expect(await db.query(Tables.outbox), beforeOutbox);
      });
    } finally {
      await tester.runAsync(() async {
        await AppDatabase.instance.close();
        await dir.delete(recursive: true);
      });
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    }
  });
}
