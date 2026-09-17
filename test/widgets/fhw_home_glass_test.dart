/// FHW home tab — glass re-skin regression guard.
///
/// The Today tab was re-skinned with glass surfaces, staggered entrances and
/// count-up numbers. These tests pin the two things that must survive any
/// visual change: the quick-action and dashboard-count labels the flow tests
/// and health workers rely on, and layout at a narrow phone width with 200%
/// text (the accessibility floor), under reduced motion so the glass layer
/// falls back to its flat translucent look.
library;

import 'package:carebridge_ai/app/providers.dart';
import 'package:carebridge_ai/data/local/outbox_dao.dart';
import 'package:carebridge_ai/data/repositories/insight_repository.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
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

Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(390, 1200),
  double textScale = 1,
  bool disableAnimations = true,
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
        dayPlanProvider.overrideWith(
          (ref) async => DayPlan(
            priorities: const [],
            dueContacts: const [],
            overdueContacts: const [],
            chaseReferrals: const [],
            generatedAt: DateTime.now(),
          ),
        ),
        openReferralsProvider.overrideWith((ref) async => const []),
        syncStatusProvider.overrideWith(
          (ref) => Stream.value(
            const SyncStatusSummary(pending: 0, failing: 0, criticalPending: 0),
          ),
        ),
        connectivityProvider.overrideWith((ref) => Stream.value(true)),
        zoneHomeChecksProvider.overrideWith((ref) async => const []),
        householdsVisitedTodayProvider.overrideWith((ref) async => 0),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: disableAnimations,
          ),
          child: child!,
        ),
        home: Scaffold(
          body: FhwHomeTab(onOpenFamilies: () {}, onOpenQueue: () {}),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('quick-action and dashboard-count labels are present', (
    tester,
  ) async {
    await _pump(tester);

    for (final label in [
      'Register & assess',
      'Add Household',
      'Search',
      'Sync',
    ]) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    for (final label in [
      'Registered Families',
      'Check-ups Due',
      'See First',
      'Referrals Open',
    ]) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    // Hero live counts.
    expect(find.text('Families'), findsWidgets);
    expect(find.text('To sync'), findsWidgets);
  });

  testWidgets('no BackdropFilter under reduced motion', (tester) async {
    await _pump(tester);
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('home tab fits 320px at 200% text without overflow', (
    tester,
  ) async {
    await _pump(tester, size: const Size(320, 900), textScale: 2);
    expect(tester.takeException(), isNull);

    final list = find.byType(ListView).first;
    for (var i = 0; i < 6; i++) {
      await tester.drag(list, const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'after scroll $i');
    }
    // Scroll back to the counts grid; it must still lay out cleanly.
    await tester.scrollUntilVisible(
      find.text('Referrals Open'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Referrals Open'), findsWidgets);
  });
}
