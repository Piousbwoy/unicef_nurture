/// The follow-up read path: the queries the referral desk is built from.
///
/// The desk cannot be built on `ReferralStatus.isOpen`. An answer of "went and
/// is still waiting in the queue" moves the referral to `arrived`, which is not
/// open — so an open-only query would file the case away as handled while the
/// child is still untreated on a bench in Bawku. Everything the desk needs to
/// know about a case therefore comes from the answer ledger, and these are the
/// four questions it asks: who have I answered, who is still unanswered, what
/// is the trace behind this case, and is a visit chasing it.
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

const _worker = 'u-cho';

final _today = DateTime(2026, 9, 25, 11);

Referral _referral({
  required String id,
  required DateTime issuedAt,
  ReferralStatus status = ReferralStatus.issued,
  String? linkFromReferralId,
}) => Referral(
  id: id,
  referenceCode: 'CB-${id.substring(id.length - 4).toUpperCase()}',
  personId: 'p-1',
  assessmentId: 'a-1',
  facilityName: 'Bawku Municipal Hospital',
  reason: 'Fast breathing and chest indrawing',
  urgency: ReferralUrgency.sameDay,
  issuedBy: _worker,
  issuedAt: issuedAt,
  status: status,
  linkFromReferralId: linkFromReferralId,
);

FollowUpContact _contact({
  required String id,
  required String referralId,
  required DateTime at,
  FollowUpReach reached = FollowUpReach.went,
  FollowUpCare care = FollowUpCare.seenTreated,
  FollowUpCondition condition = FollowUpCondition.better,
  Set<CareBarrier> barriers = const {},
  String? note,
}) => FollowUpContact(
  id: id,
  referralId: referralId,
  personId: 'p-1',
  householdId: 'h-1',
  at: at,
  channel: FollowUpChannel.householdVisit,
  reached: reached,
  care: care,
  condition: condition,
  barriers: barriers,
  note: note,
  recordedBy: _worker,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A file-backed database per group: these queries lean on real TEXT date
  // ordering and on `PRAGMA foreign_keys`, neither of which a mock can show.
  void useTempDb(WidgetTester tester, String tag) {
    final dir = Directory.systemTemp.createTempSync('carebridge_fu_$tag');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async =>
          call.method == 'getApplicationDocumentsDirectory' ? dir.path : null,
    );
    AppDatabase.initialiseForDesktopAndTests();
    addTearDown(() async {
      await AppDatabase.instance.close();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
  }

  Future<void> seed() async {
    await HouseholdDao.upsert(
      Household(
        id: 'h-1',
        name: 'The Abanga family',
        region: 'Upper East Region',
        district: 'Bawku Municipal',
        community: 'Zenuoye',
        createdBy: _worker,
      ),
    );
    await PersonDao.upsert(
      Person(
        id: 'p-1',
        householdId: 'h-1',
        fullName: 'Abanga Kambili',
        clientType: ClientType.childUnderFive,
        dateOfBirth: DateTime(2024, 4, 2),
      ),
    );
  }

  group('answer ledger', () {
    testWidgets('an answer round-trips with every field the desk reads', (
      tester,
    ) async {
      useTempDb(tester, 'roundtrip');
      await tester.runAsync(() async {
        await seed();
        await ReferralDao.upsert(
          _referral(id: 'ref-1', issuedAt: _today.subtract(const Duration(days: 2))),
        );
        await FollowUpDao.insert(
          _contact(
            id: 'fc-1',
            referralId: 'ref-1',
            at: _today,
            reached: FollowUpReach.didNotGo,
            care: FollowUpCare.none,
            condition: FollowUpCondition.notSeen,
            barriers: const {
              CareBarrier.noTransportMoney,
              CareBarrier.noPermission,
            },
            note: 'Husband away at market; mother could not leave.',
          ),
        );

        final saved = await FollowUpDao.forReferral('ref-1');
        expect(saved, hasLength(1));
        final c = saved.single;
        expect(c.reached, FollowUpReach.didNotGo);
        expect(c.care, FollowUpCare.none);
        expect(c.condition, FollowUpCondition.notSeen);
        expect(c.channel, FollowUpChannel.householdVisit);
        expect(
          c.barriers,
          equals(const {
            CareBarrier.noTransportMoney,
            CareBarrier.noPermission,
          }),
        );
        expect(c.note, contains('Husband away at market'));
        expect(c.recordedBy, _worker);

        // The ledger must leave the device with everything else, or the
        // district register has no answers in it.
        final db = await AppDatabase.instance.database;
        final queued = await db.rawQuery(
          'SELECT entity_id FROM ${Tables.outbox} WHERE entity_table = ?',
          [Tables.followUpContacts],
        );
        expect(queued.map((r) => r['entity_id']), contains('fc-1'));
      });
    });

    testWidgets('the trace reads oldest answer first', (tester) async {
      useTempDb(tester, 'order');
      await tester.runAsync(() async {
        await seed();
        await ReferralDao.upsert(
          _referral(id: 'ref-1', issuedAt: _today.subtract(const Duration(days: 6))),
        );
        // Inserted newest-first on purpose: the desk draws a trace line
        // forwards in time, so the DAO must not echo insertion order.
        await FollowUpDao.insert(
          _contact(
            id: 'fc-3',
            referralId: 'ref-1',
            at: _today.subtract(const Duration(days: 1)),
          ),
        );
        await FollowUpDao.insert(
          _contact(
            id: 'fc-2',
            referralId: 'ref-1',
            at: _today.subtract(const Duration(days: 3)),
            reached: FollowUpReach.unknown,
            care: FollowUpCare.unknown,
            condition: FollowUpCondition.notSeen,
          ),
        );
        await FollowUpDao.insert(
          _contact(
            id: 'fc-1',
            referralId: 'ref-1',
            at: _today.subtract(const Duration(days: 5)),
            reached: FollowUpReach.unknown,
            care: FollowUpCare.unknown,
            condition: FollowUpCondition.notSeen,
          ),
        );

        final trace = await FollowUpDao.forReferral('ref-1');
        expect(trace.map((c) => c.id), ['fc-1', 'fc-2', 'fc-3']);
        final latest = await FollowUpDao.latestFor('ref-1');
        expect(latest?.id, 'fc-3');
      });
    });

    testWidgets('attempts and answers are counted apart', (tester) async {
      useTempDb(tester, 'attempts');
      await tester.runAsync(() async {
        await seed();
        await ReferralDao.upsert(
          _referral(id: 'ref-1', issuedAt: _today.subtract(const Duration(days: 4))),
        );
        await FollowUpDao.insert(
          _contact(
            id: 'fc-1',
            referralId: 'ref-1',
            at: _today.subtract(const Duration(days: 3)),
            reached: FollowUpReach.unknown,
            care: FollowUpCare.unknown,
            condition: FollowUpCondition.notSeen,
          ),
        );
        await FollowUpDao.insert(
          _contact(
            id: 'fc-2',
            referralId: 'ref-1',
            at: _today.subtract(const Duration(days: 2)),
            reached: FollowUpReach.unknown,
            care: FollowUpCare.unknown,
            condition: FollowUpCondition.notSeen,
          ),
        );
        await FollowUpDao.insert(
          _contact(
            id: 'fc-3',
            referralId: 'ref-1',
            at: _today.subtract(const Duration(days: 1)),
            reached: FollowUpReach.went,
            care: FollowUpCare.seenWaiting,
            condition: FollowUpCondition.same,
          ),
        );

        // "Went round, nobody was home" twice is the escalation trigger; the
        // third visit answered, so the count must stop at two.
        expect(await FollowUpDao.unansweredAttempts('ref-1'), 2);
      });
    });

    testWidgets('the desk loads every ledger in one query', (tester) async {
      useTempDb(tester, 'batch');
      await tester.runAsync(() async {
        await seed();
        await ReferralDao.upsert(
          _referral(id: 'ref-1', issuedAt: _today.subtract(const Duration(days: 2))),
        );
        await ReferralDao.upsert(
          _referral(id: 'ref-2', issuedAt: _today.subtract(const Duration(days: 1))),
        );
        await ReferralDao.upsert(
          _referral(id: 'ref-3', issuedAt: _today.subtract(const Duration(days: 3))),
        );
        await FollowUpDao.insert(_contact(id: 'fc-1', referralId: 'ref-1', at: _today));
        await FollowUpDao.insert(
          _contact(
            id: 'fc-2',
            referralId: 'ref-2',
            at: _today,
            reached: FollowUpReach.unknown,
            care: FollowUpCare.unknown,
            condition: FollowUpCondition.notSeen,
          ),
        );

        final ledger = await FollowUpDao.forReferrals(const [
          'ref-1',
          'ref-2',
          'ref-3',
        ]);
        expect(ledger.keys, containsAll(['ref-1', 'ref-2', 'ref-3']));
        expect(ledger['ref-3'], isEmpty);
        expect(ledger['ref-1']!.single.isAnswered, isTrue);
        expect(ledger['ref-2']!.single.isAnswered, isFalse);
      });
    });

    testWidgets('writing the same answer twice does not create a second one', (
      tester,
    ) async {
      useTempDb(tester, 'idempotent');
      await tester.runAsync(() async {
        await seed();
        await ReferralDao.upsert(
          _referral(id: 'ref-1', issuedAt: _today.subtract(const Duration(days: 2))),
        );
        final contact = _contact(id: 'fc-1', referralId: 'ref-1', at: _today);
        await FollowUpDao.insert(contact);
        // The screen keeps the ID it minted when it opened, so the worker's
        // second tap after a slow save rewrites the same row.
        await FollowUpDao.insert(contact);

        expect(await FollowUpDao.forReferral('ref-1'), hasLength(1));
      });
    });
  });

  group('referral reads for the desk', () {
    testWidgets('recent returns the whole window, answered cases included', (
      tester,
    ) async {
      useTempDb(tester, 'recent');
      await tester.runAsync(() async {
        await seed();
        await ReferralDao.upsert(
          _referral(
            id: 'ref-old',
            issuedAt: _today.subtract(const Duration(days: 20)),
          ),
        );
        await ReferralDao.upsert(
          _referral(
            id: 'ref-settled',
            issuedAt: _today.subtract(const Duration(days: 2)),
            status: ReferralStatus.treated,
          ),
        );
        await ReferralDao.upsert(
          _referral(
            id: 'ref-fresh',
            issuedAt: _today.subtract(const Duration(days: 1)),
          ),
        );

        final recent = await ReferralDao.recent(withinDays: 7, now: _today);
        // A settled case still belongs on the desk — the trace is the record
        // of the week's work, and an answer nobody can see is an answer
        // a district nurse will be told never happened.
        expect(recent.map((r) => r.id), ['ref-fresh', 'ref-settled']);
      });
    });

    testWidgets('a chained referral is found from its parent', (tester) async {
      useTempDb(tester, 'chain');
      await tester.runAsync(() async {
        await seed();
        await ReferralDao.upsert(
          _referral(id: 'ref-parent', issuedAt: _today.subtract(const Duration(days: 3))),
        );
        await ReferralDao.upsert(
          _referral(
            id: 'ref-child',
            issuedAt: _today.subtract(const Duration(days: 1)),
            linkFromReferralId: 'ref-parent',
          ),
        );
        await ReferralDao.upsert(
          _referral(id: 'ref-unrelated', issuedAt: _today),
        );

        final children = await ReferralDao.linkedChildren('ref-parent');
        expect(children.map((r) => r.id), ['ref-child']);
        expect(children.single.linkFromReferralId, 'ref-parent');
      });
    });

    testWidgets('escalation is stamped once and holds', (tester) async {
      useTempDb(tester, 'escalate');
      await tester.runAsync(() async {
        await seed();
        await ReferralDao.upsert(
          _referral(id: 'ref-1', issuedAt: _today.subtract(const Duration(days: 3))),
        );
        final db = await AppDatabase.instance.database;
        await db.transaction((txn) => ReferralDao.markEscalatedIn(txn, 'ref-1'));

        final after = await ReferralDao.byId('ref-1');
        expect(after?.escalatedAt, isNotNull);
        // The 48-hour banner is only honest if it cannot re-fire forever:
        // a second write must not move the original trace date.
        final first = after!.escalatedAt!;
        await db.transaction(
          (txn) => ReferralDao.markEscalatedIn(txn, 'ref-1', at: first),
        );
        expect((await ReferralDao.byId('ref-1'))?.escalatedAt, first);
      });
    });
  });

  group('visits that chase a referral', () {
    testWidgets('a scheduled contact knows which referral it serves', (
      tester,
    ) async {
      useTempDb(tester, 'schedule');
      await tester.runAsync(() async {
        await seed();
        await ReferralDao.upsert(
          _referral(id: 'ref-1', issuedAt: _today.subtract(const Duration(days: 2))),
        );
        await ScheduleDao.upsert(
          ScheduledContact(
            id: 'sc-1',
            personId: 'p-1',
            householdId: 'h-1',
            dueDate: _today.add(const Duration(days: 2)),
            purpose: 'Re-check Abanga Kambili after referral',
            createdBy: _worker,
            referralId: 'ref-1',
          ),
        );
        await ScheduleDao.upsert(
          ScheduledContact(
            id: 'sc-2',
            personId: 'p-1',
            householdId: 'h-1',
            dueDate: _today.add(const Duration(days: 9)),
            purpose: 'Routine growth monitoring',
            createdBy: _worker,
          ),
        );

        final chasing = await ScheduleDao.forReferral('ref-1');
        expect(chasing.map((c) => c.id), ['sc-1']);

        await ScheduleDao.markDone('sc-1');
        expect(await ScheduleDao.forReferral('ref-1'), isEmpty);
        // The route still counts the visit as kept.
        expect(await ScheduleDao.byId('sc-1'), isNotNull);
      });
    });
  });
}
