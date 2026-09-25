/// The FHW shell chrome — the deep-blue clinic header that sits above every
/// tab.
///
/// The header used to place a `Flexible` directly inside a `Wrap`. A `Wrap`
/// hands its children unbounded width, so the parent-data write fails during
/// build and Flutter drops the whole subtree: on the web release build the
/// header *and* both tab bodies collapsed into an empty grey panel, which no
/// tab-body-only test could see. These pump the real shell so the crash is a
/// test failure, and pin the truncation the `Flexible` was there to achieve.
library;

import 'package:carebridge_ai/app/providers.dart';
import 'package:carebridge_ai/data/local/outbox_dao.dart';
import 'package:carebridge_ai/data/repositories/insight_repository.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:carebridge_ai/presentation/fhw/fhw_home.dart';
import 'package:carebridge_ai/presentation/fhw/home_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// A CHPS zone long enough to need the ellipsis, so the width ceiling is
/// actually exercised rather than silently absent.
const _longZone = 'Nakpayili & Kpalbusi CHPS Zone, Gushegu District';

final _user = AppUser(
  id: 'u-fhw-header',
  fullName: 'Amina Fuseini',
  phone: '0244000000',
  role: UserRole.frontlineHealthWorker,
  region: 'Northern Region',
  district: 'Gushegu',
  community: 'Tamale Central',
  chpsZone: _longZone,
);

const _household = Household(
  id: 'h-header',
  name: 'Achana household',
  region: 'Northern Region',
  district: 'Gushegu',
  community: 'Tamale Central',
  createdBy: 'u-fhw-header',
  headName: 'Achana Yakubu',
  familySize: 6,
);

final _emptyPlan = DayPlan(
  priorities: const [],
  dueContacts: const [],
  overdueContacts: const [],
  chaseReferrals: const [],
  generatedAt: DateTime(2026, 9, 1, 6),
);

Future<void> _pumpShell(
  WidgetTester tester, {
  Size size = const Size(390, 1400),
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
        dayPlanProvider.overrideWith((ref) async => _emptyPlan),
        openReferralsProvider.overrideWith((ref) async => const []),
        activeClinicSessionProvider.overrideWith((ref) async => null),
        clinicQueueProvider.overrideWith((ref) async => const []),
        householdProvider.overrideWith((ref, id) async => _household),
        zoneHomeChecksProvider.overrideWith((ref) async => const []),
        dailyRegisterProvider.overrideWith(
          (ref) async => const DailyRegisterTally(),
        ),
        syncStatusProvider.overrideWith(
          (ref) => Stream.value(
            const SyncStatusSummary(pending: 0, failing: 0, criticalPending: 0),
          ),
        ),
        connectivityProvider.overrideWith((ref) => Stream.value(true)),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const FhwHome(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('the clinic header builds instead of collapsing the shell', (
    tester,
  ) async {
    await _pumpShell(tester);

    expect(tester.takeException(), isNull);
    expect(find.text(_longZone), findsOneWidget);
    expect(find.text('Amina'), findsOneWidget);
  });

  testWidgets('a header that builds leaves the tab body on screen', (
    tester,
  ) async {
    await _pumpShell(tester);

    // The grey-panel symptom was the *body* disappearing with the header, so
    // the header alone is not enough evidence.
    expect(find.text('Care starts here.'), findsOneWidget);
    expect(find.text('Receive a patient'), findsOneWidget);
  });

  testWidgets('a long zone stays on one line inside the header', (
    tester,
  ) async {
    await _pumpShell(tester);

    final text = tester.widget<Text>(find.text(_longZone));
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
    // The line has a ceiling of its own, which is what gives the ellipsis
    // something to work against; without it the `Wrap` hands it infinity.
    expect(tester.getSize(find.text(_longZone)).width, lessThanOrEqualTo(220));
  });
}
