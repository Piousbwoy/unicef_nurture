/// The single atomic write behind the follow-up desk.
///
/// `CareRepository.recordFollowUp` is the whole redesign in one method: the
/// answer, the status it implies, the barrier behind a failure, the visit that
/// produced it, the next visit, and the fresh referral a worsening child
/// needs — all in one commit or in none of them.
///
/// The tests below are written against what a field worker would call correct,
/// not against SQL. Two of them matter more than the rest:
///
/// • "attended but untreated" must never read as settled. Before the ledger,
///   confirming arrival moved a referral to `arrived`, which is not an open
///   state, so the case vanished from the chase list while the child was still
///   sick on a bench.
/// • a second tap must not invent a second answer. Everything is keyed off the
///   contact ID the screen froze when it opened.
library;

import 'dart:io';

import 'package:carebridge_ai/data/local/app_database.dart';
import 'package:carebridge_ai/data/local/household_dao.dart';
import 'package:carebridge_ai/data/local/visit_dao.dart';
import 'package:carebridge_ai/data/repositories/care_repository.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:carebridge_ai/domain/services/follow_up_policy.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 9, 25, 11);

const _cho = AppUser(
  id: 'u-cho',
  fullName: 'Akosua Mensah',
  phone: '0244000001',
  role: UserRole.frontlineHealthWorker,
  region: 'Upper East Region',
  district: 'Bawku Municipal',
  community: 'Zenuoye',
);

const _mother = AppUser(
  id: 'u-mother',
  fullName: 'Awinile Bilali',
  phone: '0244000002',
  role: UserRole.caregiver,
  region: 'Upper East Region',
  district: 'Bawku Municipal',
  community: 'Zenuoye',
);

Referral _referral({
  String id = 'ref-1',
  String code = 'CB-7K2M',
  ReferralStatus status = ReferralStatus.issued,
}) => Referral(
  id: id,
  referenceCode: code,
  personId: 'p-1',
  assessmentId: 'a-1',
  facilityName: 'Bawku Municipal Hospital',
  reason: 'Fast breathing and chest indrawing',
  urgency: ReferralUrgency.sameDay,
  issuedBy: _cho.id,
  issuedAt: _now.subtract(const Duration(days: 2)),
  status: status,
  clinicalSummary: 'MUAC 11.2 cm. Chest indrawing present.',
);

FollowUpAnswer _answer({
  FollowUpReach reached = FollowUpReach.went,
  FollowUpCare care = FollowUpCare.seenTreated,
  FollowUpCondition condition = FollowUpCondition.better,
  Set<CareBarrier> barriers = const {},
  String? note,
}) => FollowUpAnswer(
  channel: FollowUpChannel.householdVisit,
  reached: reached,
  care: care,
  condition: condition,
  barriers: barriers,
  note: note,
);

/// What the check-in screen would pass when the child is worse and needs a
/// fresh referral chained to this one.
FollowUpReReferral _reRefer({String id = 'ref-2', String code = 'CB-QQ4T'}) =>
    FollowUpReReferral(
      id: id,
      referenceCode: code,
      facilityName: 'Bawku Municipal Hospital',
      reason: 'Worse after first referral: unable to feed, vomiting everything',
      urgency: ReferralUrgency.immediate,
    );

void main() {
  group('what an answer implies for the referral status', () {
    test('an unanswered attempt changes nothing', () {
      expect(
        statusImpliedBy(
          _answer(
            reached: FollowUpReach.unknown,
            care: FollowUpCare.unknown,
            condition: FollowUpCondition.notSeen,
          ),
          from: ReferralStatus.issued,
        ),
        isNull,
      );
    });

    test('seen and treated settles the case', () {
      expect(
        statusImpliedBy(_answer(), from: ReferralStatus.issued),
        ReferralStatus.treated,
      );
    });

    test('attended but untreated confirms arrival, nothing more', () {
      // The case that used to disappear from the chase list.
      expect(
        statusImpliedBy(
          _answer(
            care: FollowUpCare.seenWaiting,
            condition: FollowUpCondition.same,
          ),
          from: ReferralStatus.issued,
        ),
        ReferralStatus.arrived,
      );
      expect(
        statusImpliedBy(
          _answer(care: FollowUpCare.none, condition: FollowUpCondition.worse),
          from: ReferralStatus.travelling,
        ),
        ReferralStatus.arrived,
      );
    });

    test('went to the facility but nobody knows the outcome', () {
      expect(
        statusImpliedBy(
          _answer(care: FollowUpCare.unknown, condition: FollowUpCondition.same),
          from: ReferralStatus.issued,
        ),
        ReferralStatus.arrived,
      );
    });

    test('did not go is recorded as a failure, not a cancellation', () {
      expect(
        statusImpliedBy(
          _answer(
            reached: FollowUpReach.didNotGo,
            care: FollowUpCare.none,
            condition: FollowUpCondition.notSeen,
          ),
          from: ReferralStatus.issued,
        ),
        ReferralStatus.didNotAttend,
      );
    });

    test('a confirmed treatment is never rewritten by a later visit', () {
      // Two referrals can concern the same child; a fresh answer on the trace
      // must not resurrect or undo a settled case.
      expect(
        statusImpliedBy(
          _answer(
            reached: FollowUpReach.didNotGo,
            care: FollowUpCare.none,
            condition: FollowUpCondition.notSeen,
          ),
          from: ReferralStatus.treated,
        ),
        isNull,
      );
    });

    test('a patient who died at home closes as a death', () {
      // The exact IMCI case the enum comment mourns: referred, never got to
      // the facility, and died. It must close honestly, not stay open forever.
      expect(
        statusImpliedBy(
          _answer(
            reached: FollowUpReach.didNotGo,
            care: FollowUpCare.none,
            condition: FollowUpCondition.died,
          ),
          from: ReferralStatus.issued,
        ),
        ReferralStatus.died,
      );
    });

    test('a death outranks a claimed treatment', () {
      expect(
        statusImpliedBy(
          _answer(
            reached: FollowUpReach.went,
            care: FollowUpCare.seenTreated,
            condition: FollowUpCondition.died,
          ),
          from: ReferralStatus.arrived,
        ),
        ReferralStatus.died,
      );
    });

    test('a family that declined closes as a refusal', () {
      expect(
        statusImpliedBy(
          _answer(
            reached: FollowUpReach.declined,
            care: FollowUpCare.unknown,
            condition: FollowUpCondition.notSeen,
          ),
          from: ReferralStatus.issued,
        ),
        ReferralStatus.refused,
      );
    });

    test('a death is not recorded from an unanswered knock', () {
      expect(
        statusImpliedBy(
          _answer(
            reached: FollowUpReach.unknown,
            care: FollowUpCare.unknown,
            condition: FollowUpCondition.died,
          ),
          from: ReferralStatus.issued,
        ),
        isNull,
      );
    });

    test('a closed death is never reopened by a later visit', () {
      expect(
        statusImpliedBy(
          _answer(
            reached: FollowUpReach.didNotGo,
            care: FollowUpCare.none,
            condition: FollowUpCondition.better,
          ),
          from: ReferralStatus.died,
        ),
        isNull,
      );
    });
  });

  group('what an answer implies for the desk outcome', () {
    test('a death reports as a death, not a settled case', () {
      expect(
        followUpOutcomeFor(
          answer: _answer(
            reached: FollowUpReach.didNotGo,
            care: FollowUpCare.none,
            condition: FollowUpCondition.died,
          ),
          referral: _referral(status: ReferralStatus.died),
          raised: null,
        ),
        FollowUpOutcome.deceased,
      );
    });

    test('a refusal reports as a closed case', () {
      expect(
        followUpOutcomeFor(
          answer: _answer(
            reached: FollowUpReach.declined,
            care: FollowUpCare.unknown,
            condition: FollowUpCondition.notSeen,
          ),
          referral: _referral(status: ReferralStatus.refused),
          raised: null,
        ),
        FollowUpOutcome.closed,
      );
    });
  });

  group('recordFollowUp', () {
    late Directory dbDir;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      dbDir = Directory.systemTemp.createTempSync('carebridge_record');
      await _mockPathProvider(dbDir.path);
      AppDatabase.initialiseForDesktopAndTests();
      await HouseholdDao.upsert(
        Household(
          id: 'h-1',
          name: 'The Abanga family',
          region: 'Upper East Region',
          district: 'Bawku Municipal',
          community: 'Zenuoye',
          createdBy: _cho.id,
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
      await ReferralDao.upsert(_referral());
    });

    tearDown(() async {
      await AppDatabase.instance.close();
      if (dbDir.existsSync()) dbDir.deleteSync(recursive: true);
    });

    test('a settled answer writes the answer, the status and the outbox rows', () async {
      final repo = CareRepository(clock: () => _now);
      final result = await repo.recordFollowUp(
        _cho,
        referral: _referral(),
        householdId: 'h-1',
        contactId: 'fc-1',
        answer: _answer(),
      );

      expect(result.outcome, FollowUpOutcome.settled);
      expect(result.contact.referralId, 'ref-1');
      expect(result.contact.householdId, 'h-1');
      expect(result.contact.personId, 'p-1');
      expect(result.contact.at, _now);
      expect(result.contact.recordedBy, _cho.id);
      expect(result.referral.status, ReferralStatus.treated);
      expect(result.raised, isNull);

      final trace = await FollowUpDao.forReferral('ref-1');
      expect(trace, hasLength(1));
      final saved = await ReferralDao.byId('ref-1');
      expect(saved?.status, ReferralStatus.treated);

      final db = await AppDatabase.instance.database;
      final queued = await db.rawQuery(
        'SELECT DISTINCT entity_table FROM ${Tables.outbox}',
      );
      final tables = queued.map((r) => r['entity_table'] as String).toSet();
      expect(
        tables,
        containsAll([Tables.followUpContacts, Tables.referrals]),
        reason: 'an answer that never syncs is a district record that lies',
      );
    });

    test('attended-but-untreated stays actionable', () async {
      final repo = CareRepository(clock: () => _now);
      final result = await repo.recordFollowUp(
        _cho,
        referral: _referral(),
        householdId: 'h-1',
        contactId: 'fc-1',
        answer: _answer(
          care: FollowUpCare.seenWaiting,
          condition: FollowUpCondition.same,
        ),
      );

      expect(result.referral.status, ReferralStatus.arrived);
      expect(result.outcome, FollowUpOutcome.stillWaiting);
      // The desk must still surface it: `arrived` alone would not.
      final latest = await FollowUpDao.latestFor('ref-1');
      expect(latest?.condition.needsAction, isTrue);
    });

    test('a barrier answer is recorded against the referral in the same write',
        () async {
      final repo = CareRepository(clock: () => _now);
      await repo.recordFollowUp(
        _cho,
        referral: _referral(),
        householdId: 'h-1',
        contactId: 'fc-1',
        answer: _answer(
          reached: FollowUpReach.didNotGo,
          care: FollowUpCare.none,
          condition: FollowUpCondition.notSeen,
          barriers: const {CareBarrier.noTransportMoney},
          note: 'No money for the tamale lorry.',
        ),
      );

      final reports = await BarrierDao.forHousehold('h-1');
      expect(reports, hasLength(1));
      expect(reports.single.referralId, 'ref-1');
      expect(reports.single.barriers, [CareBarrier.noTransportMoney]);
      expect(reports.single.notes, contains('tamale lorry'));
      // The barrier's own action is what makes capturing it worth the tap.
      expect(
        reports.single.suggestedActions.single,
        contains('transport'),
      );
    });

    test('one unanswered visit is an attempt, two start a trace', () async {
      final repo = CareRepository(clock: () => _now);
      final first = await repo.recordFollowUp(
        _cho,
        referral: _referral(),
        householdId: 'h-1',
        contactId: 'fc-1',
        answer: _answer(
          reached: FollowUpReach.unknown,
          care: FollowUpCare.unknown,
          condition: FollowUpCondition.notSeen,
        ),
      );
      expect(first.outcome, FollowUpOutcome.attemptLogged);
      expect(first.referral.status, ReferralStatus.issued);
      expect(first.referral.escalatedAt, isNull);

      final current = await ReferralDao.byId('ref-1');
      final second = await repo.recordFollowUp(
        _cho,
        referral: current!,
        householdId: 'h-1',
        contactId: 'fc-2',
        answer: _answer(
          reached: FollowUpReach.unknown,
          care: FollowUpCare.unknown,
          condition: FollowUpCondition.notSeen,
        ),
      );
      expect(second.referral.escalatedAt, isNotNull);
      expect(
        second.outcome,
        FollowUpOutcome.attemptLogged,
        reason: 'still no answer — escalation is a trace, not a verdict',
      );
    });

    test('escalation fires once and keeps its first date', () async {
      final repo = CareRepository(clock: () => _now);
      for (final id in ['fc-1', 'fc-2']) {
        final current = await ReferralDao.byId('ref-1');
        await repo.recordFollowUp(
          _cho,
          referral: current!,
          householdId: 'h-1',
          contactId: id,
          answer: _answer(
            reached: FollowUpReach.unknown,
            care: FollowUpCare.unknown,
            condition: FollowUpCondition.notSeen,
          ),
        );
      }
      final escalatedAt = (await ReferralDao.byId('ref-1'))!.escalatedAt;
      expect(escalatedAt, _now);

      final later = DateTime(_now.year, _now.month, _now.day + 1);
      final current = await ReferralDao.byId('ref-1');
      await CareRepository(clock: () => later).recordFollowUp(
        _cho,
        referral: current!,
        householdId: 'h-1',
        contactId: 'fc-3',
        answer: _answer(
          reached: FollowUpReach.unknown,
          care: FollowUpCare.unknown,
          condition: FollowUpCondition.notSeen,
        ),
      );
      expect(
        (await ReferralDao.byId('ref-1'))?.escalatedAt,
        escalatedAt,
        reason: 'the trace keeps the day the case became overdue',
      );
    });

    test('a worse child raises a referral chained to the one it answers',
        () async {
      final repo = CareRepository(clock: () => _now);
      final result = await repo.recordFollowUp(
        _cho,
        referral: _referral(),
        householdId: 'h-1',
        contactId: 'fc-1',
        answer: _answer(
          care: FollowUpCare.none,
          condition: FollowUpCondition.worse,
          note: 'Came back on the same day, worse.',
        ),
        alsoReRefer: _reRefer(),
      );

      expect(result.outcome, FollowUpOutcome.reReferred);
      final raised = result.raised;
      expect(raised, isNotNull);
      expect(raised!.id, 'ref-2');
      expect(raised.referenceCode, 'CB-QQ4T');
      expect(raised.linkFromReferralId, 'ref-1');
      expect(raised.isChained, isTrue);
      expect(raised.personId, 'p-1');
      expect(raised.assessmentId, 'a-1');
      expect(raised.issuedBy, _cho.id);
      expect(raised.issuedAt, _now);
      expect(raised.status, ReferralStatus.issued);
      expect(raised.urgency, ReferralUrgency.immediate);
      // The receiving facility needs the evidence from the first visit, not a
      // blank slip.
      expect(raised.clinicalSummary, contains('MUAC 11.2'));

      expect(result.contact.linkedReferralId, 'ref-2');
      final children = await ReferralDao.linkedChildren('ref-1');
      expect(children.map((r) => r.id), ['ref-2']);
    });

    test('the visit that produced the answer is closed, and a next one is set',
        () async {
      await ScheduleDao.upsert(
        ScheduledContact(
          id: 'sc-today',
          personId: 'p-1',
          householdId: 'h-1',
          dueDate: _now,
          purpose: 'Chase referral CB-7K2M',
          createdBy: _cho.id,
          referralId: 'ref-1',
        ),
      );

      final repo = CareRepository(clock: () => _now);
      await repo.recordFollowUp(
        _cho,
        referral: _referral(),
        householdId: 'h-1',
        contactId: 'fc-1',
        answer: _answer(
          care: FollowUpCare.seenWaiting,
          condition: FollowUpCondition.same,
        ),
        completedContactId: 'sc-today',
        nextVisitAt: _now.add(const Duration(days: 1)),
      );

      expect((await ScheduleDao.byId('sc-today'))?.completedAt, isNotNull);
      // The visit that produced the answer has left the open set; the next one
      // the worker asked for has taken its place. forReferral returns only
      // open contacts, so sc-today must be gone and sc-fc-1 present.
      final open = await ScheduleDao.forReferral('ref-1');
      expect(open.map((c) => c.id), ['sc-fc-1']);

      final upcoming = await ScheduleDao.forPerson('p-1');
      final next = upcoming.where((c) => c.id != 'sc-today').toList();
      expect(next, hasLength(1));
      expect(next.single.referralId, 'ref-1');
      expect(next.single.dueDate, _now.add(const Duration(days: 1)));
      expect(next.single.purpose, contains('CB-7K2M'));
      expect(next.single.createdBy, _cho.id);
    });

    test('a caregiver cannot answer for another family', () async {
      final repo = CareRepository(clock: () => _now);
      await expectLater(
        repo.recordFollowUp(
          _mother,
          referral: _referral(),
          householdId: 'h-1',
          contactId: 'fc-1',
          answer: _answer(),
        ),
        throwsA(isA<AccessDenied>()),
      );
      expect(await FollowUpDao.forReferral('ref-1'), isEmpty);
      expect((await ReferralDao.byId('ref-1'))?.status, ReferralStatus.issued);
    });

    test('repeating the save writes one answer, one chain, one barrier',
        () async {
      final repo = CareRepository(clock: () => _now);
      Future<FollowUpResult> save() => repo.recordFollowUp(
        _cho,
        referral: _referral(),
        householdId: 'h-1',
        contactId: 'fc-1',
        answer: _answer(
          care: FollowUpCare.none,
          condition: FollowUpCondition.worse,
          barriers: const {CareBarrier.distanceTooFar},
        ),
        alsoReRefer: _reRefer(),
        completedContactId: 'sc-x',
        nextVisitAt: _now.add(const Duration(days: 1)),
      );

      await save();
      final again = await save();

      expect(await FollowUpDao.forReferral('ref-1'), hasLength(1));
      expect(await ReferralDao.linkedChildren('ref-1'), hasLength(1));
      expect(await BarrierDao.forHousehold('h-1'), hasLength(1));
      final upcoming = await ScheduleDao.forPerson('p-1');
      expect(upcoming, hasLength(1));
      expect(again.outcome, FollowUpOutcome.reReferred);
      expect(again.raised?.referenceCode, 'CB-QQ4T');
    });
  });

  group('the desk read', () {
    late Directory dbDir;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      dbDir = Directory.systemTemp.createTempSync('carebridge_desk');
      await _mockPathProvider(dbDir.path);
      AppDatabase.initialiseForDesktopAndTests();
      await HouseholdDao.upsert(
        Household(
          id: 'h-1',
          name: 'The Abanga family',
          region: 'Upper East Region',
          district: 'Bawku Municipal',
          community: 'Zenuoye',
          createdBy: _cho.id,
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
    });

    tearDown(() async {
      await AppDatabase.instance.close();
      if (dbDir.existsSync()) dbDir.deleteSync(recursive: true);
    });

    test('hands back every case in the window with its answers and its person',
        () async {
      final repo = CareRepository(clock: () => _now);
      await ReferralDao.upsert(_referral());
      await ReferralDao.upsert(
        _referral(id: 'ref-9', code: 'CB-OLD9', status: ReferralStatus.treated),
      );
      await repo.recordFollowUp(
        _cho,
        referral: _referral(id: 'ref-9', code: 'CB-OLD9',
            status: ReferralStatus.arrived),
        householdId: 'h-1',
        contactId: 'fc-9',
        answer: _answer(),
      );

      final desk = await repo.followUpDesk(_cho);

      expect(desk.referrals.map((r) => r.id), containsAll(['ref-1', 'ref-9']));
      expect(desk.ledger['ref-9'], hasLength(1));
      expect(desk.ledger['ref-1'], isEmpty);
      expect(desk.people['p-1']?.householdId, 'h-1');
      expect(desk.people['p-1']?.fullName, 'Abanga Kambili');
    });

    test('a referral older than the window is off the desk', () async {
      await ReferralDao.upsert(_referral());
      await ReferralDao.upsert(
        Referral(
          id: 'ref-ancient',
          referenceCode: 'CB-OLD0',
          personId: 'p-1',
          assessmentId: 'a-1',
          facilityName: 'Bawku Municipal Hospital',
          reason: 'Settled long ago',
          urgency: ReferralUrgency.scheduled,
          issuedBy: _cho.id,
          issuedAt: _now.subtract(const Duration(days: 60)),
          status: ReferralStatus.treated,
        ),
      );

      final desk = await CareRepository(clock: () => _now).followUpDesk(_cho);

      expect(desk.referrals.map((r) => r.id), isNot(contains('ref-ancient')));
    });

    test('a caregiver does not get the zone desk', () async {
      await ReferralDao.upsert(_referral());
      expect(
        () => CareRepository(clock: () => _now).followUpDesk(_mother),
        throwsA(isA<AccessDenied>()),
      );
    });

    test('a chase the route will not reach can be put on tomorrow', () async {
      final contact = ScheduledContact(
        id: 'sc-chase',
        personId: 'p-1',
        householdId: 'h-1',
        dueDate: DateTime(2026, 9, 26, 9),
        purpose: 'Chase referral CB-7K2M',
        createdBy: _cho.id,
        referralId: 'ref-1',
      );
      await CareRepository(clock: () => _now).planChaseVisit(_cho, contact);

      final upcoming = await ScheduleDao.forPerson('p-1');
      expect(upcoming.map((c) => c.id), ['sc-chase']);
      expect(upcoming.single.referralId, 'ref-1');
    });

    test('a caregiver cannot put a family on a route', () async {
      final elsewhere = ScheduledContact(
        id: 'sc-far',
        personId: 'p-9',
        householdId: 'h-1',
        dueDate: DateTime(2026, 9, 26, 9),
        purpose: 'Chase',
        createdBy: _mother.id,
      );
      expect(
        () => CareRepository(
          clock: () => _now,
        ).planChaseVisit(_mother, elsewhere),
        throwsA(isA<AccessDenied>()),
      );
      expect(await ScheduleDao.byId('sc-far'), isNull);
    });

    // The desk must know a chase is already coming. Without this read the
    // "put this household on a route" action stayed on screen after it had
    // been used, and a second tap scheduled the family a second visit.
    test('the desk read reports a chase that is already scheduled', () async {
      final repo = CareRepository(clock: () => _now);
      await ReferralDao.upsert(_referral());
      await repo.planChaseVisit(
        _cho,
        ScheduledContact(
          id: 'sc-chase',
          personId: 'p-1',
          householdId: 'h-1',
          dueDate: DateTime(2026, 9, 26, 9),
          purpose: 'Chase referral CB-7K2M',
          createdBy: _cho.id,
          referralId: 'ref-1',
        ),
      );
      await ScheduleDao.upsert(
        ScheduledContact(
          id: 'sc-kept',
          personId: 'p-1',
          householdId: 'h-1',
          dueDate: DateTime(2026, 9, 24, 9),
          purpose: 'A visit already kept',
          createdBy: _cho.id,
          referralId: 'ref-1',
          completedAt: _now,
        ),
      );

      final desk = await repo.followUpDesk(_cho);

      expect(desk.chases.map((c) => c.id), ['sc-chase']);
    });
  });
}

Future<void> _mockPathProvider(String path) async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async =>
            call.method == 'getApplicationDocumentsDirectory' ? path : null,
      );
}
