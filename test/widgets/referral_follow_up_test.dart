import 'package:carebridge_ai/app/providers.dart';
import 'package:carebridge_ai/data/repositories/care_repository.dart';
import 'package:carebridge_ai/data/repositories/insight_repository.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:carebridge_ai/presentation/fhw/clinic_widgets.dart';
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
Referral _referral([ReferralStatus status = ReferralStatus.issued]) => Referral(
  id: 'referral-1',
  referenceCode: 'CB-7K2M',
  personId: _patient.id,
  assessmentId: 'assessment-1',
  facilityName: 'Savelugu Municipal District Hospital',
  reason: 'Moderate anaemia with risk factors — review and treatment needed',
  urgency: ReferralUrgency.sameDay,
  issuedBy: _user.id,
  issuedAt: DateTime(2026, 8, 20, 9, 30),
  status: status,
  outcomeNotes: 'Community supporter: existing contact',
);

/// In-memory persistence at the actual repository boundary. No DAO calls or
/// platform database setup: assertions inspect the written records, not just UI.
class _MemoryCareRepository extends CareRepository {
  _MemoryCareRepository(this.saved);
  Referral saved;
  final Map<String, BarrierReport> barriers = {};
  final List<BarrierReport> barrierAttempts = [];
  final List<AppUser> writers = [];
  int statusWrites = 0;
  int confirmations = 0;
  int openReads = 0;
  int planReads = 0;
  int completionReads = 0;
  bool failStatus = false;
  bool failBarrier = false;
  bool missingPerson = false;

  @override
  Future<Person?> person(AppUser user, String personId) async =>
      missingPerson ? null : _patient;

  @override
  Future<List<Assessment>> assessmentHistory(
    AppUser user,
    String personId,
  ) async => [];

  @override
  Future<List<GrowthMeasurement>> growthSeries(
    AppUser user,
    String personId,
  ) async => [];

  @override
  Future<List<Referral>> openReferrals(AppUser user) async {
    openReads++;
    return saved.status.isOpen ? [saved] : [];
  }

  @override
  Future<void> updateReferralStatus(
    AppUser user, {
    required String referralId,
    required ReferralStatus status,
    String? outcomeNotes,
  }) async {
    statusWrites++;
    if (failStatus) throw StateError('Local write failed');
    expect(referralId, saved.id);
    writers.add(user);
    saved = saved.copyWith(status: status, outcomeNotes: outcomeNotes);
  }

  @override
  Future<void> recordBarrier(AppUser user, BarrierReport report) async {
    barrierAttempts.add(report);
    if (failBarrier) throw StateError('Barrier write failed');
    writers.add(user);
    barriers[report.id] = report;
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
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  _MemoryCareRepository repository, {
  bool tab = false,
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
          dueContacts: [],
          overdueContacts: [],
          chaseReferrals: [],
          generatedAt: DateTime(2026),
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
  // Keep the three providers live so invalidation is observable.
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
        home: tab
            ? const Scaffold(body: ReferralsTab())
            : Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              FollowUpCheckInScreen(referral: repository.saved),
                        ),
                      ),
                      child: const Text('Open follow-up'),
                    ),
                  ),
                ),
              ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (!tab) {
    await tester.tap(find.text('Open follow-up'));
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

Future<void> _notes(WidgetTester tester, String value) async {
  final finder = find.byType(TextField);
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      250,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(finder);
  await tester.enterText(finder, value);
  tester.testTextInput.hide();
  await tester.pumpAndSettle();
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  for (final status in ReferralStatus.values) {
    testWidgets(
      'unknown preserves ${status.name} and records the exact outcome',
      (tester) async {
        final repository = _MemoryCareRepository(_referral(status));
        final container = await _pump(tester, repository);
        await _tap(tester, "Don't know yet");
        await _notes(tester, 'Spoke to grandmother; check again tomorrow.');
        await _tap(tester, 'Save follow-up');
        expect(repository.saved.status, status);
        expect(repository.saved.arrivalConfirmedBy, isNull);
        expect(
          repository.saved.outcomeNotes,
          contains("Outcome: Don't know yet"),
        );
        expect(
          repository.saved.outcomeNotes,
          contains('Self-reported, not facility-verified.'),
        );
        expect(
          repository.saved.outcomeNotes,
          contains('Notes: Spoke to grandmother; check again tomorrow.'),
        );
        expect(
          repository.saved.outcomeNotes,
          contains('Community supporter: existing contact'),
        );
        expect(repository.confirmations, 0);
        expect(repository.writers, [_user]);
        expect(repository.barriers, isEmpty);
        if (status.isOpen) {
          expect(
            (await container.read(openReferralsProvider.future)).single.status,
            status,
          );
        }
        expect(repository.openReads, greaterThan(1));
        expect(repository.planReads, greaterThan(1));
        expect(repository.completionReads, greaterThan(1));
        expect(find.text('Referral Complete'), findsNothing);
        await _tap(tester, 'Done');
        expect(find.byType(FollowUpCheckInScreen), findsNothing);
      },
    );
  }

  testWidgets(
    'reached untreated is arrival, with barriers saved through the repository',
    (tester) async {
      final repository = _MemoryCareRepository(_referral());
      await _pump(tester, repository);
      await _tap(tester, 'Reached the facility — not treated');
      await _tap(tester, CareBarrier.facilityClosed.label);
      await _notes(tester, 'No staff available; arrange another contact.');
      await _tap(tester, 'Save follow-up');
      expect(repository.saved.status, ReferralStatus.arrived);
      expect(repository.saved.status, isNot(ReferralStatus.didNotAttend));
      expect(repository.saved.arrivalConfirmedBy, isNull);
      expect(
        repository.saved.outcomeNotes,
        contains('Outcome: Reached the facility — not treated'),
      );
      final barrier = repository.barriers.values.single;
      expect(barrier.barriers, [CareBarrier.facilityClosed]);
      expect(barrier.householdId, _patient.householdId);
      expect(barrier.personId, _patient.id);
      expect(barrier.referralId, repository.saved.id);
      expect(barrier.recordedBy, _user.id);
      expect(barrier.notes, contains('Self-reported, not facility-verified.'));
      expect(
        barrier.notes,
        contains('No staff available; arrange another contact.'),
      );
      expect(repository.writers, [_user, _user]);
      expect(find.text('Arrival reported'), findsOneWidget);
      expect(find.textContaining('No treatment reported.'), findsOneWidget);
      expect(find.text('Referral Complete'), findsNothing);
    },
  );

  testWidgets('arrival alone never records treatment or a staff confirmer', (
    tester,
  ) async {
    final repository = _MemoryCareRepository(_referral());
    await _pump(tester, repository);
    await _tap(tester, 'Yes — reached the facility');
    await _tap(tester, 'Save follow-up');
    expect(repository.saved.status, ReferralStatus.arrived);
    expect(repository.saved.arrivalConfirmedBy, isNull);
    expect(
      repository.saved.outcomeNotes,
      contains('Outcome: Yes — reached the facility'),
    );
    expect(find.text('Arrival reported'), findsOneWidget);
    expect(
      find.textContaining('Treatment has not been established.'),
      findsOneWidget,
    );
    expect(find.text('Referral Complete'), findsNothing);
    expect(find.textContaining('loop is closed'), findsNothing);
    expect(repository.confirmations, 0);
  });

  testWidgets(
    'treatment requires the explicit family-reported treatment choice',
    (tester) async {
      final repository = _MemoryCareRepository(_referral());
      await _pump(tester, repository);
      await _tap(tester, 'Treatment received — reported by family');
      await _tap(tester, 'Save follow-up');
      expect(repository.saved.status, ReferralStatus.treated);
      expect(repository.saved.arrivalConfirmedBy, isNull);
      expect(
        repository.saved.outcomeNotes,
        contains('Outcome: Treatment received — reported by family'),
      );
      expect(find.text('Treatment reported'), findsOneWidget);
      expect(
        find.textContaining('not verified by facility staff'),
        findsOneWidget,
      );
    },
  );

  testWidgets('did not go records nonattendance and selected barriers', (
    tester,
  ) async {
    final repository = _MemoryCareRepository(_referral());
    await _pump(tester, repository);
    await _tap(tester, 'No — did not go');
    await _tap(tester, CareBarrier.noTransportMoney.label);
    await _tap(tester, 'Save follow-up');
    expect(repository.saved.status, ReferralStatus.didNotAttend);
    expect(repository.saved.outcomeNotes, contains('Outcome: No — did not go'));
    expect(repository.barriers.values.single.barriers, [
      CareBarrier.noTransportMoney,
    ]);
  });

  testWidgets('failed status save keeps answers and never reports success', (
    tester,
  ) async {
    final repository = _MemoryCareRepository(_referral())..failStatus = true;
    await _pump(tester, repository);
    await _tap(tester, 'Yes — reached the facility');
    await _notes(tester, 'Family called this morning.');
    await _tap(tester, 'Save follow-up');
    expect(repository.saved.status, ReferralStatus.issued);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('Could not save follow-up.'), findsOneWidget);
    expect(find.byType(FollowUpCheckInScreen), findsOneWidget);
    repository.failStatus = false;
    await _tap(tester, 'Retry save');
    expect(repository.saved.status, ReferralStatus.arrived);
    expect(
      repository.saved.outcomeNotes,
      contains('Family called this morning.'),
    );
    expect(repository.statusWrites, 2);
    expect(find.text('Arrival reported'), findsOneWidget);
  });

  testWidgets(
    'barrier failure is partial success and retry reuses the report ID',
    (tester) async {
      final repository = _MemoryCareRepository(_referral())..failBarrier = true;
      await _pump(tester, repository);
      await _tap(tester, 'Reached the facility — not treated');
      await _tap(tester, CareBarrier.facilityClosed.label);
      await _tap(tester, 'Save follow-up');
      expect(repository.saved.status, ReferralStatus.arrived);
      expect(repository.barriers, isEmpty);
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        find.textContaining('but barriers were not saved'),
        findsOneWidget,
      );
      repository.failBarrier = false;
      await _tap(tester, 'Retry save');
      expect(repository.statusWrites, 1);
      expect(repository.barriers, hasLength(1));
      expect(repository.barrierAttempts, hasLength(2));
      expect(
        repository.barrierAttempts.first.id,
        repository.barrierAttempts.last.id,
      );
      expect(find.text('Arrival reported'), findsOneWidget);
    },
  );

  testWidgets('missing household never silently drops selected barriers', (
    tester,
  ) async {
    final repository = _MemoryCareRepository(_referral())..missingPerson = true;
    await _pump(tester, repository);
    await _tap(tester, 'No — did not go');
    await _tap(tester, CareBarrier.noTransportMoney.label);
    await _tap(tester, 'Save follow-up');
    expect(repository.statusWrites, 0);
    expect(repository.barriers, isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Retry save'), findsOneWidget);
  });

  testWidgets('tab is readable at 320px and 200%, and launches follow-up', (
    tester,
  ) async {
    final repository = _MemoryCareRepository(_referral());
    await _pump(tester, repository, tab: true, width: 320, scale: 2);
    await tester.scrollUntilVisible(
      find.text(_patient.fullName),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byType(ClinicCard), findsWidgets);
    expect(find.text(_patient.fullName), findsOneWidget);
    await _tap(tester, 'Record follow-up');
    expect(find.byType(FollowUpCheckInScreen), findsOneWidget);
    await _tap(tester, 'Reached the facility — not treated');
    await _tap(tester, CareBarrier.noPermission.label);
    await _tap(tester, 'Save follow-up');
    expect(repository.saved.status, ReferralStatus.arrived);
    expect(repository.barriers.values.single.barriers, [
      CareBarrier.noPermission,
    ]);
    expect(tester.takeException(), isNull);
    await _tap(tester, 'Done');
    expect(find.byType(FollowUpCheckInScreen), findsNothing);
  });

  testWidgets(
    'call opens dialler without changing status or recording an outcome',
    (tester) async {
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
      final before = repository.saved;
      await _pump(tester, repository, tab: true);
      await _tap(tester, 'Call family');
      expect(calls, isNotEmpty);
      expect(calls.last.arguments.toString(), contains('tel:0244000001'));
      expect(repository.statusWrites, 0);
      expect(repository.confirmations, 0);
      expect(repository.saved, same(before));
      expect(
        find.textContaining('requires telephone service and cellular signal'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'staff code confirmation requires explicit verification and is not treatment',
    (tester) async {
      final repository = _MemoryCareRepository(_referral());
      await _pump(tester, repository, tab: true, width: 320, scale: 2);
      await _tap(tester, 'Confirm code · verified staff action');
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Confirm arrival'),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), 'CB-7K2M');
      await _tap(
        tester,
        'I have verified arrival with facility staff or in person.',
      );
      await _tap(tester, 'Confirm arrival');
      expect(repository.confirmations, 1);
      expect(repository.saved.status, ReferralStatus.arrived);
      expect(repository.saved.arrivalConfirmedBy, _user.id);
      expect(find.textContaining('does not confirm treatment'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('record details retain the community support route', (
    tester,
  ) async {
    final repository = _MemoryCareRepository(_referral());
    await _pump(tester, repository, tab: true);
    await _tap(tester, 'Record details and support');
    expect(find.text('Referral code: CB-7K2M'), findsOneWidget);
    expect(find.text('Open household record'), findsOneWidget);
    await _tap(tester, 'Loop in support');
    expect(find.byType(CommunitySupportScreen), findsOneWidget);
  });

  testWidgets(
    'tab shows the referral journey, flags stale urgent referrals and hands '
    'over SBAR',
    (tester) async {
      // Clock-independent staleness: issued three days ago, same-day urgency,
      // no confirmed arrival — the 48-hour escalation rule must fire whenever
      // this test runs.
      final stale = Referral(
        id: 'referral-1',
        referenceCode: 'CB-7K2M',
        personId: _patient.id,
        assessmentId: 'assessment-1',
        facilityName: 'Savelugu Municipal District Hospital',
        reason: 'Moderate anaemia with risk factors — review and treatment needed',
        urgency: ReferralUrgency.sameDay,
        issuedBy: _user.id,
        issuedAt: DateTime.now().subtract(const Duration(days: 3)),
        status: ReferralStatus.issued,
      );
      final repository = _MemoryCareRepository(stale);
      await _pump(tester, repository, tab: true);

      // The journey track renders every stage, reached or not.
      for (final node in ['Issued', 'Travelling', 'Arrived', 'Treated']) {
        expect(find.text(node), findsOneWidget);
      }
      // The stale urgent referral is flagged for tracing.
      expect(find.textContaining('trace now'), findsOneWidget);
      // The honest prose caption still stands beside the track.
      expect(
        find.text('Arrival pending — no arrival recorded. Follow-up needed.'),
        findsOneWidget,
      );

      // The SBAR handover composes from the referral itself.
      await _tap(tester, 'Record details and support');
      await _tap(tester, 'Handover note (SBAR)');
      expect(find.text('Handover note'), findsOneWidget);
      expect(
        find.text('Current status: Referral issued'),
        findsOneWidget,
      );
      // Scoped to the note itself: the stale banner behind the sheet carries
      // the same words, and the point here is that the handover repeats them.
      expect(
        find.descendant(
          of: find.byType(SbarCard),
          matching: find.textContaining('trace now'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
