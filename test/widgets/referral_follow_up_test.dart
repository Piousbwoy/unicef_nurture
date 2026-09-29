import 'package:carebridge_ai/app/providers.dart';
import 'package:carebridge_ai/data/repositories/care_repository.dart';
import 'package:carebridge_ai/data/repositories/insight_repository.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:carebridge_ai/domain/services/follow_up_policy.dart';
import 'package:carebridge_ai/presentation/fhw/community_support_screen.dart';
import 'package:carebridge_ai/presentation/fhw/follow_up_check_in_screen.dart';
import 'package:carebridge_ai/presentation/fhw/referrals_tab.dart';
import 'package:carebridge_ai/presentation/visit/sbar_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

const _user = AppUser(
  id: 'worker-1',
  fullName: 'Amina Fuseini',
  phone: '0244000000',
  role: UserRole.frontlineHealthWorker,
  region: 'Northern Region',
  district: 'Savelugu',
  community: 'Tamale',
);
const _patient = Person(
  id: 'patient-1',
  householdId: 'household-1',
  fullName: 'Mariama Alhassan Abdul-Rahman',
  clientType: ClientType.pregnantWoman,
  phone: '0244000001',
);

/// Issued three days ago on a same-day clock: overdue whenever this runs, so
/// the desk's urgency signalling is not a function of the date of the run.
Referral _referral([ReferralStatus status = ReferralStatus.issued]) => Referral(
  id: 'referral-1',
  referenceCode: 'CB-7K2M',
  personId: _patient.id,
  assessmentId: 'assessment-1',
  facilityName: 'Savelugu Municipal District Hospital',
  reason: 'Moderate anaemia with risk factors — review and treatment needed',
  urgency: ReferralUrgency.sameDay,
  issuedBy: _user.id,
  issuedAt: DateTime.now().subtract(const Duration(days: 3)),
  status: status,
);

const _visit = 'At the household';
const _phone = 'On the phone';
const _went = 'Went to the facility';
const _didNotGo = 'Did not go';
const _dontKnow = "Don't know yet";
const _treated = 'Seen and treated';
const _waiting = 'Seen, still waiting';
const _noCare = 'Turned away, no care';
const _careUnknown = "Don't know what happened";
const _better = 'Better';
const _worse = 'Worse';

/// In-memory persistence at the repository boundary: the desk and the check-in
/// both talk to [CareRepository], so every assertion here is about the records
/// that were written, not the widgets that wrote them.
class _MemoryCareRepository extends CareRepository {
  _MemoryCareRepository(this.saved);

  Referral saved;
  final Map<String, FollowUpContact> contacts = {};
  final List<Referral> raised = [];
  final List<ScheduledContact> chases = [];
  final List<AppUser> writers = [];

  /// Households on today's route, so the desk can sort a case into the
  /// walk-past lane.
  Set<String> route = {};
  bool emptyDesk = false;
  bool failRecord = false;
  bool failPlan = false;
  AccessDenied? deny;

  int deskReads = 0;
  int records = 0;
  int confirmations = 0;
  int outcomes = 0;
  int openReads = 0;
  int planReads = 0;
  int completionReads = 0;

  /// The separate writes the atomic call replaced. Any hit here means a
  /// follow-up was saved in pieces again.
  int legacyStatusWrites = 0;
  int legacyBarrierWrites = 0;

  FollowUpContact? get onlyContact =>
      contacts.length == 1 ? contacts.values.single : null;

  /// Seeds an answer without a screen, so the desk can be shown mid-trace.
  void seedAnswer(FollowUpAnswer answer, {String id = 'seed'}) =>
      contacts[id] = FollowUpContact(
        id: id,
        referralId: saved.id,
        personId: _patient.id,
        householdId: _patient.householdId,
        at: DateTime.now().subtract(const Duration(days: 1)),
        channel: answer.channel,
        reached: answer.reached,
        care: answer.care,
        condition: answer.condition,
        barriers: answer.barriers,
        note: answer.note,
        recordedBy: _user.id,
      );

  @override
  Future<Person?> person(AppUser user, String personId) async => _patient;

  @override
  Future<List<Assessment>> assessmentHistory(
    AppUser user,
    String personId,
  ) async => const [];

  @override
  Future<List<GrowthMeasurement>> growthSeries(
    AppUser user,
    String personId,
  ) async => const [];

  @override
  Future<List<Referral>> openReferrals(AppUser user) async {
    openReads++;
    return saved.status.isOpen ? [saved] : [];
  }

  @override
  Future<
      ({
        List<Referral> referrals,
        Map<String, List<FollowUpContact>> ledger,
        Map<String, Person> people,
        List<ScheduledContact> chases,
      })
    >
    followUpDesk(AppUser user, {int withinDays = 21}) async {
    deskReads++;
    if (deny != null) throw deny!;
    if (emptyDesk) {
      return (
        referrals: const <Referral>[],
        ledger: const <String, List<FollowUpContact>>{},
        people: const <String, Person>{},
        chases: const <ScheduledContact>[],
      );
    }
    final all = [saved, ...raised];
    return (
      referrals: all,
      ledger: {
        for (final referral in all)
          referral.id: [
            for (final contact in contacts.values)
              if (contact.referralId == referral.id) contact,
          ],
      },
      people: {_patient.id: _patient},
      chases: chases,
    );
  }

  @override
  Future<FollowUpResult> recordFollowUp(
    AppUser user, {
    required Referral referral,
    required String householdId,
    required String contactId,
    required FollowUpAnswer answer,
    FollowUpReReferral? alsoReRefer,
    DateTime? nextVisitAt,
    String? completedContactId,
  }) async {
    records++;
    if (failRecord) throw StateError('Local write failed');
    expect(referral.id, saved.id);
    expect(householdId, _patient.householdId);
    writers.add(user);

    Referral? next;
    if (alsoReRefer != null) {
      next = Referral(
        id: alsoReRefer.id,
        referenceCode: alsoReRefer.referenceCode,
        personId: referral.personId,
        assessmentId: referral.assessmentId,
        facilityName: alsoReRefer.facilityName,
        reason: alsoReRefer.reason,
        urgency: alsoReRefer.urgency,
        issuedBy: user.id,
        issuedAt: DateTime.now(),
        linkFromReferralId: referral.id,
      );
      raised.add(next);
    }
    final contact = FollowUpContact(
      id: contactId,
      referralId: referral.id,
      personId: referral.personId,
      householdId: householdId,
      at: DateTime.now(),
      channel: answer.channel,
      reached: answer.reached,
      care: answer.care,
      condition: answer.condition,
      barriers: answer.barriers,
      note: answer.note,
      linkedReferralId: next?.id,
      recordedBy: user.id,
    );
    // Keyed by the frozen contact id: a retry after a failed write overwrites
    // its own row rather than answering one referral twice.
    contacts[contactId] = contact;

    final target = statusImpliedBy(answer, from: saved.status);
    if (target != null) saved = saved.copyWith(status: target);

    return (
      outcome: followUpOutcomeFor(answer: answer, referral: saved, raised: next),
      contact: contact,
      referral: saved,
      raised: next,
    );
  }

  @override
  Future<void> planChaseVisit(AppUser user, ScheduledContact contact) async {
    if (deny != null) throw deny!;
    if (failPlan) throw StateError('Local write failed');
    expect(contact.referralId, saved.id);
    chases.add(contact);
  }

  @override
  Future<Referral?> confirmArrival(AppUser user, String referenceCode) async {
    confirmations++;
    if (referenceCode.toUpperCase() != saved.referenceCode) return null;
    saved = saved.copyWith(
      status: ReferralStatus.arrived,
      arrivalConfirmedBy: user.id,
    );
    return saved;
  }

  @override
  Future<Referral?> confirmReferralOutcome(
    AppUser user,
    String referenceCode, {
    required ReferralStatus outcome,
    String? outcomeNotes,
  }) async {
    outcomes++;
    if (referenceCode.toUpperCase() != saved.referenceCode) return null;
    saved = saved.copyWith(
      status: outcome,
      arrivalConfirmedBy: user.id,
      outcomeNotes: outcomeNotes,
    );
    return saved;
  }

  @override
  Future<void> updateReferralStatus(
    AppUser user, {
    required String referralId,
    required ReferralStatus status,
    String? outcomeNotes,
  }) async {
    legacyStatusWrites++;
    throw StateError('a follow-up is one write, not a status update');
  }

  @override
  Future<void> recordBarrier(AppUser user, BarrierReport report) async {
    legacyBarrierWrites++;
    throw StateError('a follow-up is one write, not a separate barrier');
  }
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  _MemoryCareRepository repository, {
  bool checkIn = false,
  double width = 390,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      currentUserProvider.overrideWithValue(_user),
      careRepositoryProvider.overrideWithValue(repository),
      bootstrapProvider.overrideWith((ref) async {}),
      dayPlanProvider.overrideWith((ref) async {
        repository.planReads++;
        return DayPlan(
          priorities: [],
          dueContacts: [
            for (final householdId in repository.route)
              ScheduledContact(
                id: 'sc-$householdId',
                personId: _patient.id,
                householdId: householdId,
                dueDate: DateTime.now(),
                purpose: 'Antenatal visit',
                createdBy: _user.id,
              ),
          ],
          overdueContacts: [],
          chaseReferrals: [],
          generatedAt: DateTime.now(),
        );
      }),
      referralCompletionProvider.overrideWith((ref) async {
        repository.completionReads++;
        final arrived =
            repository.saved.status == ReferralStatus.arrived ||
            repository.saved.status == ReferralStatus.treated;
        return (issued: 1, arrived: arrived ? 1 : 0, rate: arrived ? 1.0 : 0.0);
      }),
    ],
  );
  addTearDown(container.dispose);
  container.listen(openReferralsProvider, (_, _) {}, fireImmediately: true);
  container.listen(dayPlanProvider, (_, _) {}, fireImmediately: true);
  container.listen(
    referralCompletionProvider,
    (_, _) {},
    fireImmediately: true,
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: checkIn
            ? const Scaffold(body: SizedBox.expand())
            : const Scaffold(body: ReferralsTab()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (checkIn) {
    // Pushed the way the desk and the day plan push it. As `home:` the screen
    // has no route to pop, so it would carry no Back button to test.
    Navigator.of(tester.element(find.byType(Scaffold))).push(
      MaterialPageRoute(
        builder: (_) => FollowUpCheckInScreen(
          referral: repository.saved,
          householdId: _patient.householdId,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
  return container;
}

Future<void> _tap(WidgetTester tester, String label) async {
  final finder = find.text(label);
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      250,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _note(WidgetTester tester, String value) async {
  // The note sits at the foot of a long form, so it is not built until the
  // list has been scrolled to it.
  await tester.scrollUntilVisible(
    find.byType(TextField),
    250,
    scrollable: find.byType(Scrollable).last,
    maxScrolls: 12,
  );
  final finder = find.byType(TextField).last;
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.enterText(finder, value);
  tester.testTextInput.hide();
  await tester.pumpAndSettle();
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  group('the desk', () {
    testWidgets('sorts an unanswered referral into the bucket it earned', (
      tester,
    ) async {
      final repository = _MemoryCareRepository(_referral());
      await _pump(tester, repository);

      expect(find.textContaining('Awaiting answer · 1'), findsOneWidget);
      expect(find.text(_patient.fullName), findsOneWidget);
      expect(find.text('Answered — not cared for'), findsNothing);
      expect(find.textContaining('NO VISIT PLANNED SOON'), findsOneWidget);
      // The seven-state lifecycle is never offered as a picker.
      expect(find.text(ReferralStatus.travelling.label), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('puts a household on today\u2019s route in the walk-past lane', (
      tester,
    ) async {
      final repository = _MemoryCareRepository(_referral())
        ..route = {_patient.householdId};
      await _pump(tester, repository);

      expect(find.textContaining('ON YOUR ROUTE TODAY'), findsOneWidget);
      expect(find.textContaining('NO VISIT PLANNED SOON'), findsNothing);
      expect(find.text('Answer it at this visit'), findsOneWidget);
    });

    testWidgets('one tap books the chase, and the card stops offering it twice', (
      tester,
    ) async {
      final repository = _MemoryCareRepository(_referral());
      await _pump(tester, repository);
      await _tap(tester, 'Put this household on a route');

      expect(repository.chases, hasLength(1));
      expect(repository.chases.single.referralId, 'referral-1');
      expect(repository.chases.single.householdId, _patient.householdId);
      expect(repository.chases.single.purpose, 'Chase referral CB-7K2M');
      expect(repository.records, 0);

      await tester.pumpAndSettle();
      expect(find.text('Put this household on a route'), findsNothing);
      expect(find.text('Answer it now — visit already booked'), findsOneWidget);
      expect(find.textContaining('Visit booked'), findsOneWidget);
    });

    testWidgets('a booked chase turns the route action into the visit itself', (
      tester,
    ) async {
      final repository = _MemoryCareRepository(_referral())
        ..chases.add(
          ScheduledContact(
            id: 'sc-1',
            personId: _patient.id,
            householdId: _patient.householdId,
            dueDate: DateTime.now().add(const Duration(days: 1)),
            purpose: 'Chase referral CB-7K2M',
            createdBy: _user.id,
            referralId: 'referral-1',
          ),
        );
      await _pump(tester, repository);
      expect(find.text('Put this household on a route'), findsNothing);
      expect(find.text('Answer it now — visit already booked'), findsOneWidget);
    });

    testWidgets('an answered case leaves the awaiting column and asks to be revisited', (
      tester,
    ) async {
      final repository = _MemoryCareRepository(_referral())
        ..seedAnswer(
          const FollowUpAnswer(
            channel: FollowUpChannel.householdVisit,
            reached: FollowUpReach.went,
            care: FollowUpCare.seenWaiting,
            condition: FollowUpCondition.better,
          ),
        );
      await _pump(tester, repository);

      expect(find.textContaining('Awaiting answer'), findsNothing);
      expect(
        find.textContaining('Answered — not cared for · 1'),
        findsOneWidget,
      );
      expect(find.text('Record what changed'), findsOneWidget);
      // The trace is attributed to the visit that produced it, and worded as
      // what someone was told — never as facility fact.
      await _tap(tester, 'Case detail');
      expect(find.textContaining('What was found'), findsOneWidget);
      expect(find.textContaining('went, still waiting'), findsOneWidget);
      expect(find.textContaining('facility-verified'), findsNothing);
    });

    testWidgets('two unanswered visits make it a trace, not a bad afternoon', (
      tester,
    ) async {
      final repository = _MemoryCareRepository(_referral());
      FollowUpContact knock(String id, int daysAgo) => FollowUpContact(
        id: id,
        referralId: repository.saved.id,
        personId: _patient.id,
        householdId: _patient.householdId,
        at: DateTime.now().subtract(Duration(days: daysAgo)),
        channel: FollowUpChannel.householdVisit,
        reached: FollowUpReach.unknown,
        care: FollowUpCare.unknown,
        condition: FollowUpCondition.notSeen,
        recordedBy: _user.id,
      );
      repository.contacts['a'] = knock('a', 3);
      repository.contacts['b'] = knock('b', 2);
      await _pump(tester, repository);

      expect(find.textContaining('2 unanswered visits'), findsOneWidget);
    });

    testWidgets('reads at 320px and 200% text and opens the check-in', (
      tester,
    ) async {
      final repository = _MemoryCareRepository(_referral())
        ..route = {_patient.householdId};
      await _pump(tester, repository, width: 320, scale: 2);

      await tester.scrollUntilVisible(
        find.text(_patient.fullName),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(_patient.fullName), findsOneWidget);
      await _tap(tester, 'Answer it at this visit');
      expect(find.byType(FollowUpCheckInScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('hands over SBAR, support and the household record', (
      tester,
    ) async {
      final repository = _MemoryCareRepository(_referral());
      await _pump(tester, repository);
      await _tap(tester, 'Case detail');
      expect(find.text('Referral code: CB-7K2M'), findsOneWidget);
      expect(find.text('Open household record'), findsOneWidget);

      await _tap(tester, 'SBAR');
      expect(find.byType(SbarCard), findsOneWidget);
      // The handover sheet has no close button by design — you read it, then
      // push it aside.
      await tester.drag(find.byType(SbarCard), const Offset(0, 500));
      await tester.pumpAndSettle();
      expect(find.byType(SbarCard), findsNothing);

      await _tap(tester, 'Support');
      expect(find.byType(CommunitySupportScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('calling opens the dialler and writes nothing', (tester) async {
      final calls = <MethodCall>[];
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return true;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final repository = _MemoryCareRepository(_referral());
      await _pump(tester, repository);
      await _tap(tester, 'Call');

      expect(calls, isNotEmpty);
      expect(calls.last.arguments.toString(), contains('tel:0244000001'));
      expect(repository.records, 0);
      expect(repository.saved.status, ReferralStatus.issued);
      // A call is not a follow-up: nothing was written, so the card still asks
      // for the answer.
      expect(find.text('Put this household on a route'), findsOneWidget);
    });

    testWidgets('the staff code is the only thing that names a verifier', (
      tester,
    ) async {
      final repository = _MemoryCareRepository(_referral());
      await _pump(tester, repository);
      await _tap(tester, 'Confirm a code · verified staff action');
      await tester.enterText(find.byType(TextField).first, 'CB-7K2M');
      await _tap(
        tester,
        'I have verified arrival with facility staff or in person.',
      );
      await _tap(tester, 'Confirm arrival');

      expect(repository.confirmations, 1);
      expect(repository.saved.status, ReferralStatus.arrived);
      expect(repository.saved.arrivalConfirmedBy, _user.id);
      expect(repository.records, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a verifier records the facility outcome as treated', (
      tester,
    ) async {
      final repository = _MemoryCareRepository(_referral());
      await _pump(tester, repository);
      await _tap(tester, 'Confirm a code · verified staff action');
      await tester.enterText(find.byType(TextField).first, 'CB-7K2M');
      await _tap(tester, 'Seen and treated');
      await _tap(
        tester,
        'I have verified arrival with facility staff or in person.',
      );
      await _tap(tester, 'Save facility outcome');

      // Treatment now carries a verifier's name without a follow-up answer
      // being written: this is the facility attesting, not the family reporting.
      expect(repository.outcomes, 1);
      expect(repository.confirmations, 0);
      expect(repository.saved.status, ReferralStatus.treated);
      expect(repository.saved.arrivalConfirmedBy, _user.id);
      expect(repository.records, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a verifier records a death witnessed at the facility', (
      tester,
    ) async {
      final repository = _MemoryCareRepository(_referral());
      await _pump(tester, repository);
      await _tap(tester, 'Confirm a code · verified staff action');
      await tester.enterText(find.byType(TextField).first, 'CB-7K2M');
      await _tap(tester, 'Patient died');
      await _tap(
        tester,
        'I have verified arrival with facility staff or in person.',
      );
      await _tap(tester, 'Save facility outcome');

      expect(repository.saved.status, ReferralStatus.died);
      expect(repository.saved.arrivalConfirmedBy, _user.id);
      expect(tester.takeException(), isNull);
    });

    test('a verifier may confirm arrival, treatment or death', () {
      expect(
        facilityOutcomeAllowed(ReferralStatus.issued, ReferralStatus.arrived),
        isTrue,
      );
      expect(
        facilityOutcomeAllowed(ReferralStatus.arrived, ReferralStatus.treated),
        isTrue,
      );
      expect(
        facilityOutcomeAllowed(ReferralStatus.issued, ReferralStatus.died),
        isTrue,
      );
    });

    test('a facility cannot record a family-side refusal', () {
      expect(
        facilityOutcomeAllowed(ReferralStatus.issued, ReferralStatus.refused),
        isFalse,
      );
      expect(
        facilityOutcomeAllowed(
          ReferralStatus.issued,
          ReferralStatus.didNotAttend,
        ),
        isFalse,
      );
    });

    test('a settled case is never reopened by a facility outcome', () {
      expect(
        facilityOutcomeAllowed(ReferralStatus.treated, ReferralStatus.died),
        isFalse,
      );
      expect(
        facilityOutcomeAllowed(ReferralStatus.died, ReferralStatus.treated),
        isFalse,
      );
    });

    testWidgets('an empty desk says what it does not know', (tester) async {
      final repository = _MemoryCareRepository(_referral())..emptyDesk = true;
      await _pump(tester, repository);

      expect(find.textContaining('Nothing waits on you'), findsOneWidget);
      expect(
        find.textContaining('not the same as every patient being cared for'),
        findsOneWidget,
      );
    });

    testWidgets('a denied desk explains itself instead of spinning', (
      tester,
    ) async {
      final repository = _MemoryCareRepository(_referral())
        ..deny = const AccessDenied('view the follow-up desk', null);
      await _pump(tester, repository);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('view the follow-up desk'), findsOneWidget);
    });

    testWidgets('is the whole surface, with no second list to fall back to', (
      tester,
    ) async {
      final repository = _MemoryCareRepository(_referral());
      await _pump(tester, repository);

      // The desk builds lazily, so an unfound widget proves nothing until the
      // foot of the list has actually been rendered.
      final scrollable = find.byType(Scrollable).first;
      for (var i = 0; i < 8; i++) {
        await tester.drag(scrollable, const Offset(0, -400));
        await tester.pumpAndSettle();
      }

      // The desk already holds every open referral in a column that names what
      // is missing. A second flat list of the same rows is one more place for
      // "not yet arrived" to be mistaken for "not yet cared for".
      expect(find.text('Open the trace list'), findsNothing);
    });
  });

  group('the check-in', () {
    testWidgets('is one write carrying the answer, the status and the note', (
      tester,
    ) async {
      final repository = _MemoryCareRepository(_referral());
      await _pump(tester, repository, checkIn: true);
      await _tap(tester, _visit);
      await _tap(tester, _went);
      await _tap(tester, _noCare);
      await _tap(tester, _worse);
      await _tap(tester, CareBarrier.noTransportMoney.label);
      await _note(tester, 'Grandmother says no money since market day.');
      await _tap(tester, 'Save follow-up');

      expect(repository.records, 1);
      expect(repository.legacyStatusWrites, 0);
      expect(repository.legacyBarrierWrites, 0);
      final contact = repository.onlyContact!;
      expect(contact.channel, FollowUpChannel.householdVisit);
      expect(contact.reached, FollowUpReach.went);
      expect(contact.care, FollowUpCare.none);
      expect(contact.condition, FollowUpCondition.worse);
      expect(contact.barriers, {CareBarrier.noTransportMoney});
      expect(contact.note, 'Grandmother says no money since market day.');
      expect(contact.recordedBy, _user.id);
      expect(repository.saved.status, ReferralStatus.arrived);
      expect(repository.writers, [_user]);
    });

    for (final status in ReferralStatus.values) {
      testWidgets("an unanswered knock leaves a ${status.name} referral alone", (
        tester,
      ) async {
        final repository = _MemoryCareRepository(_referral(status));
        await _pump(tester, repository, checkIn: true);
        await _tap(tester, _phone);
        await _tap(tester, _dontKnow);
        await _note(tester, 'Nobody picked up.');
        await _tap(tester, 'Save follow-up');

        expect(repository.saved.status, status);
        expect(repository.saved.arrivalConfirmedBy, isNull);
        expect(repository.onlyContact?.isAnswered, isFalse);
        expect(repository.onlyContact?.note, 'Nobody picked up.');
        // An attempt is not an outcome, and the screen must not imply one.
        expect(find.text('Referral Complete'), findsNothing);
        expect(find.textContaining('Nobody reached'), findsOneWidget);
        await _tap(tester, 'Done');
        expect(find.byType(FollowUpCheckInScreen), findsNothing);
      });
    }

    testWidgets('arrival never reads as treatment, in word or in the record', (
      tester,
    ) async {
      final repository = _MemoryCareRepository(_referral());
      await _pump(tester, repository, checkIn: true);
      await _tap(tester, _visit);
      await _tap(tester, _went);
      // Stopping at "they went" must not invent what happened at the facility.
      await _tap(tester, _careUnknown);
      await _tap(tester, 'Save follow-up');

      expect(repository.saved.status, ReferralStatus.arrived);
      expect(repository.saved.arrivalConfirmedBy, isNull);
      expect(repository.onlyContact?.care, FollowUpCare.unknown);
      expect(find.text('Referral Complete'), findsNothing);
      expect(find.textContaining('loop is closed'), findsNothing);
      expect(
        find.textContaining('Treatment has not been established'),
        findsOneWidget,
      );
    });

    testWidgets('treatment needs the words "seen and treated"', (tester) async {
      final repository = _MemoryCareRepository(_referral());
      await _pump(tester, repository, checkIn: true);
      await _tap(tester, _visit);
      await _tap(tester, _went);
      await _tap(tester, _treated);
      await _tap(tester, _better);
      await _tap(tester, 'Save follow-up');

      expect(repository.saved.status, ReferralStatus.treated);
      // Family-reported treatment is still not a facility signature.
      expect(repository.saved.arrivalConfirmedBy, isNull);
      expect(repository.onlyContact?.linkedReferralId, isNull);
      expect(find.text('Referral Complete'), findsNothing);
      expect(
        find.textContaining('not verified by facility staff'),
        findsOneWidget,
      );
    });

    testWidgets('not going has to be explained before it can be saved', (
      tester,
    ) async {
      final repository = _MemoryCareRepository(_referral());
      await _pump(tester, repository, checkIn: true);
      await _tap(tester, _visit);
      await _tap(tester, _didNotGo);
      await _tap(tester, _worse);
      await _tap(tester, 'Say what stopped them');

      // The primary control names what is missing instead of greying out, and
      // nothing reaches the record until the reason is in.
      expect(repository.records, 0);
      expect(find.textContaining('barrier is the finding'), findsOneWidget);

      await _tap(tester, CareBarrier.distanceTooFar.label);
      await _tap(tester, 'Save follow-up');
      expect(repository.records, 1);
      expect(repository.saved.status, ReferralStatus.didNotAttend);
      expect(repository.onlyContact?.barriers, {CareBarrier.distanceTooFar});
    });

    testWidgets('worse or the same can raise a chained referral on the spot', (
      tester,
    ) async {
      final repository = _MemoryCareRepository(_referral());
      await _pump(tester, repository, checkIn: true);
      await _tap(tester, _visit);
      await _tap(tester, _went);
      await _tap(tester, _waiting);
      await _tap(tester, _worse);

      await _tap(tester, 'Raise a new referral');
      // The family is shown the code before the write, so the slip in their
      // hand and the row on the device are the same referral.
      expect(find.textContaining('CB-'), findsWidgets);
      await _tap(tester, 'Save follow-up');

      expect(repository.raised, hasLength(1));
      final chain = repository.raised.single;
      expect(chain.linkFromReferralId, 'referral-1');
      expect(chain.personId, _patient.id);
      expect(chain.issuedBy, _user.id);
      expect(repository.saved.status, isNot(ReferralStatus.treated));
      expect(repository.onlyContact?.linkedReferralId, chain.id);
      expect(find.textContaining('is now on your desk'), findsOneWidget);
    });

    testWidgets('getting better offers no second referral', (tester) async {
      final repository = _MemoryCareRepository(_referral());
      await _pump(tester, repository, checkIn: true);
      await _tap(tester, _visit);
      await _tap(tester, _went);
      await _tap(tester, _treated);
      await _tap(tester, _better);
      expect(find.text('Raise a new referral'), findsNothing);
      await _tap(tester, 'Save follow-up');

      expect(repository.raised, isEmpty);
      expect(repository.records, 1);
    });

    testWidgets('a failed save keeps every answer and retries once', (
      tester,
    ) async {
      final repository = _MemoryCareRepository(_referral())..failRecord = true;
      await _pump(tester, repository, checkIn: true);
      await _tap(tester, _visit);
      await _tap(tester, _went);
      await _tap(tester, _waiting);
      await _tap(tester, _better);
      await _note(tester, 'Waiting since 6am.');
      await _tap(tester, 'Save follow-up');

      expect(repository.saved.status, ReferralStatus.issued);
      expect(repository.contacts, isEmpty);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('Could not save'), findsOneWidget);
      expect(find.byType(FollowUpCheckInScreen), findsOneWidget);
      expect(find.text('Waiting since 6am.'), findsOneWidget);

      repository.failRecord = false;
      await _tap(tester, 'Retry save');
      expect(repository.records, 2);
      expect(repository.contacts, hasLength(1));
      expect(repository.saved.status, ReferralStatus.arrived);
    });

    testWidgets('leaving without saving writes nothing', (tester) async {
      final repository = _MemoryCareRepository(_referral());
      await _pump(tester, repository, checkIn: true);
      await _tap(tester, _visit);
      await _tap(tester, _went);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(repository.records, 0);
      expect(repository.contacts, isEmpty);
    });
  });
}
