/// FHW Today tab — the screen a health worker opens first, on a phone with
/// whatever signal there happens to be.
///
/// These pin the behaviours that make the tab trustworthy rather than
/// decorative: one obvious way in, an honest connection and sync line, resume
/// offered before a duplicate session is created, urgent referrals chased
/// without implying the family never attended, and priority ordering labelled
/// as a reading of saved records rather than a diagnosis. Layout is checked at
/// the accessibility floor (320px, 200% text) because the field devices small.
library;

import 'package:carebridge_ai/app/providers.dart';
import 'package:carebridge_ai/data/local/outbox_dao.dart';
import 'package:carebridge_ai/data/repositories/insight_repository.dart';
import 'package:carebridge_ai/domain/engines/vulnerability_engine.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:carebridge_ai/presentation/fhw/home_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

final _user = AppUser(
  id: 'u-fhw-1',
  fullName: 'Amina Fuseini',
  phone: '0244000000',
  role: UserRole.frontlineHealthWorker,
  region: 'Northern Region',
  district: 'Savelugu Municipal',
  community: 'Tamale Central',
);

const _household = Household(
  id: 'h-1',
  name: 'Achana household',
  region: 'Northern Region',
  district: 'Savelugu Municipal',
  community: 'Tamale Central',
  createdBy: 'u-fhw-1',
  headName: 'Achana Yakubu',
  familySize: 6,
);

final _when = DateTime(2026, 9, 1, 6);

final _emptyPlan = DayPlan(
  priorities: const [],
  dueContacts: const [],
  overdueContacts: const [],
  chaseReferrals: const [],
  generatedAt: _when,
);

const _priority = HouseholdPriority(
  household: _household,
  members: [],
  score: VulnerabilityScore(
    score: 62,
    band: VulnerabilityBand.high,
    factors: [
      RiskFactor(
        label: 'Missed scheduled contacts',
        detail: 'Two antenatal contacts have no completion recorded',
        points: 22,
        isModifiable: true,
      ),
    ],
    dataCompleteness: 0.4,
    confidence: RecommendationConfidence.low,
  ),
);

Visit _openVisit() => Visit(
  id: 'v-open',
  householdId: _household.id,
  conductedBy: _user.id,
  startedAt: _when,
  reasons: const [VisitReason.ancFollowUp],
);

Referral _urgent() => Referral(
  id: 'r-1',
  referenceCode: 'CB-2026-0417',
  personId: 'p-1',
  assessmentId: 'a-1',
  facilityName: 'Savelugu Health Centre',
  reason: 'Danger sign reported at the last assessment',
  urgency: ReferralUrgency.immediate,
  issuedBy: _user.id,
  issuedAt: _when,
);

Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(390, 1200),
  double textScale = 1,
  DayPlan? plan,
  List<Referral> referrals = const [],
  Visit? activeSession,
  List<ClinicQueueTicket> queue = const [],
  int pendingSync = 0,
  bool online = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(_user),
        visibleHouseholdsProvider.overrideWith((ref) async => [_household]),
        dayPlanProvider.overrideWith((ref) async => plan ?? _emptyPlan),
        openReferralsProvider.overrideWith((ref) async => referrals),
        activeClinicSessionProvider.overrideWith((ref) async => activeSession),
        clinicQueueProvider.overrideWith((ref) async => queue),
        householdProvider.overrideWith((ref, id) async => _household),
        zoneHomeChecksProvider.overrideWith((ref) async => const []),
        syncStatusProvider.overrideWith(
          (ref) => Stream.value(
            SyncStatusSummary(
              pending: pendingSync,
              failing: 0,
              criticalPending: 0,
            ),
          ),
        ),
        connectivityProvider.overrideWith((ref) => Stream.value(online)),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: FhwHomeTab(
            onOpenFamilies: () {},
            onOpenQueue: () {},
            onOpenReferrals: () {},
            onOpenProfile: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('one obvious action and an honest connection line', (
    tester,
  ) async {
    await _pump(tester, pendingSync: 3);

    expect(find.text('Care starts here.'), findsOneWidget);
    expect(find.text('Receive a patient'), findsOneWidget);
    expect(
      find.text('Network available · 3 changes waiting to send'),
      findsOneWidget,
    );
    expect(
      find.text('Clinical assessment works without internet.'),
      findsOneWidget,
    );

    for (final label in [
      'Overdue reviews',
      'Due today',
      'Open referrals',
      'Household records',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    // An empty schedule is stated as a local-record fact, never as reassurance.
    expect(
      find.textContaining('does not rule out urgent care needs'),
      findsOneWidget,
    );
  });

  testWidgets('working offline is named, not hidden', (tester) async {
    await _pump(tester, online: false);
    expect(
      find.text('Working offline · 0 changes waiting to send'),
      findsOneWidget,
    );
    expect(find.text('Receive a patient'), findsOneWidget);
  });

  testWidgets('an open session is offered as a live queue before a new one', (
    tester,
  ) async {
    await _pump(
      tester,
      queue: [
        ClinicQueueTicket(
          visit: _openVisit(),
          householdName: 'Achana household',
          presentCount: 2,
          assessedCount: 1,
        ),
      ],
    );

    expect(find.text('1 patient in the clinic queue'), findsOneWidget);
    expect(find.text('1 person still to be assessed.'), findsOneWidget);
    expect(find.text('1 to assess'), findsOneWidget);
    expect(find.text('Open clinic queue'), findsOneWidget);
    expect(find.text('Achana household'), findsWidgets);
  });

  testWidgets('urgent referrals are chased without blaming the family', (
    tester,
  ) async {
    await _pump(tester, referrals: [_urgent()]);

    expect(find.text('1 urgent referral awaiting arrival'), findsOneWidget);
    expect(
      find.text(
        'No arrival has been recorded on this phone. Check what happened next.',
      ),
      findsOneWidget,
    );
    expect(find.text('Review urgent referrals'), findsOneWidget);
  });

  testWidgets('priorities are labelled as records, not a diagnosis', (
    tester,
  ) async {
    await _pump(
      tester,
      plan: DayPlan(
        priorities: const [_priority],
        dueContacts: const [],
        overdueContacts: const [],
        chaseReferrals: const [],
        generatedAt: _when,
      ),
    );

    expect(find.text('Bring these records forward'), findsOneWidget);
    expect(
      find.text('Priorities from saved records—not a diagnosis of who is '
          'unwell now.'),
      findsOneWidget,
    );
    expect(find.text('Achana household'), findsWidgets);
  });

  testWidgets('fits 320px at 200% text without overflow', (tester) async {
    await _pump(
      tester,
      size: const Size(320, 900),
      textScale: 2,
      pendingSync: 12,
      referrals: [_urgent()],
      queue: [
        ClinicQueueTicket(
          visit: _openVisit(),
          householdName: 'Achana household',
          presentCount: 2,
          assessedCount: 0,
        ),
      ],
      plan: DayPlan(
        priorities: const [_priority],
        dueContacts: const [],
        overdueContacts: const [],
        chaseReferrals: const [],
        generatedAt: _when,
      ),
    );
    expect(tester.takeException(), isNull);

    for (var i = 0; i < 6; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -420));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'after scroll $i');
    }
  });
}
