/// The real clinic queue — several open sessions, one nurse.
///
/// Two contracts the "super-rich clinic flow" rests on are pinned here.
///
/// First, at the data layer: the queue is built from plain open [Visit] rows,
/// so a worker may hold several at once. [VisitDao.openVisitsFor] returns them
/// newest-first (arrival order), [VisitDao.openVisitForHousehold] lets intake
/// *join* the one open session a family already has instead of starting a
/// duplicate, and completing a visit drops its ticket. This is the whole
/// "no schema change" bet, tested against the real database.
///
/// Second, at the UI layer: [ClinicQueueScreen] lists those tickets in the
/// order it is given, and the destructive "Cancel open session" action is
/// offered *only* for a ticket with nothing saved yet — a session with a saved
/// assessment must stay resumable, never cancellable from the board.
library;

import 'dart:io';

import 'package:carebridge_ai/app/providers.dart';
import 'package:carebridge_ai/data/local/app_database.dart';
import 'package:carebridge_ai/data/local/household_dao.dart';
import 'package:carebridge_ai/data/local/visit_dao.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:carebridge_ai/presentation/fhw/clinic_queue_screen.dart';
import 'package:carebridge_ai/presentation/fhw/home_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

const _worker = 'u-nurse';

final _user = AppUser(
  id: _worker,
  fullName: 'Amina Fuseini',
  phone: '0244000000',
  role: UserRole.frontlineHealthWorker,
  region: 'Northern Region',
  district: 'Savelugu Municipal',
  community: 'Tamale Central',
);

Household _household(String id) => Household(
  id: id,
  name: '$id household',
  region: 'Northern Region',
  district: 'Savelugu Municipal',
  community: 'Tamale Central',
  createdBy: _worker,
);

Person _person(String id, String hh) => Person(
  id: id,
  householdId: hh,
  fullName: '$id patient',
  clientType: ClientType.childUnderFive,
  dateOfBirth: DateTime(2024, 1, 1),
);

Visit _visit(String id, String hh, DateTime started) => Visit(
  id: id,
  householdId: hh,
  conductedBy: _worker,
  startedAt: started,
  reasons: const [VisitReason.ancFollowUp],
);

Assessment _assessment(String id, String visitId, String personId, DateTime at) =>
    Assessment(
      id: id,
      visitId: visitId,
      personId: personId,
      clientType: ClientType.childUnderFive,
      performedBy: _worker,
      performedAt: at,
      inputs: const {},
      result: AssessmentResult(
        clientType: ClientType.childUnderFive,
        triage: TriageLevel.routine,
        classification: 'ROUTINE CARE',
        findings: const [],
        actions: const [],
        confidence: RecommendationConfidence.high,
      ),
    );

void _useTempDb(WidgetTester tester, String tag) {
  final dir = Directory.systemTemp.createTempSync('carebridge_$tag');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => call.method == 'getApplicationDocumentsDirectory'
        ? dir.path
        : null,
  );
  AppDatabase.initialiseForDesktopAndTests();
  addTearDown(() => AppDatabase.instance.close());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('the queue is many open visits, newest first, joined per '
      'household, and closes on completion', (tester) async {
    _useTempDb(tester, 'queue_data');

    await tester.runAsync(() async {
      await HouseholdDao.upsert(_household('h1'));
      await HouseholdDao.upsert(_household('h2'));
      await PersonDao.upsert(_person('p1', 'h1'));
      await PersonDao.upsert(_person('p2', 'h2'));

      final first = DateTime(2026, 9, 1, 6);
      await VisitDao.start(
        _visit('v1', 'h1', first),
        [
          const VisitParticipant(
            visitId: 'v1',
            personId: 'p1',
            wasPresent: true,
            queueOrder: 0,
          ),
        ],
      );
      await VisitDao.start(
        _visit('v2', 'h2', first.add(const Duration(hours: 1))),
        [
          const VisitParticipant(
            visitId: 'v2',
            personId: 'p2',
            wasPresent: true,
            queueOrder: 0,
          ),
        ],
      );

      // Both arrive as tickets, most recent arrival first.
      var open = await VisitDao.openVisitsFor(_worker);
      expect(
        open.map((v) => v.id).toList(),
        ['v2', 'v1'],
        reason: 'a second household must not evict the first open session',
      );

      // Intake joins the family's own open visit rather than duplicating it.
      expect((await VisitDao.openVisitForHousehold(_worker, 'h1'))?.id, 'v1');
      expect((await VisitDao.openVisitForHousehold(_worker, 'h2'))?.id, 'v2');
      // A family with nothing open is not falsely joined.
      expect(await VisitDao.openVisitForHousehold(_worker, 'h-none'), isNull);

      // Closing a session (the queue's Cancel / Complete) removes its ticket,
      // leaving the other household still open and resumable.
      await VisitDao.complete('v2');
      open = await VisitDao.openVisitsFor(_worker);
      expect(open.map((v) => v.id).toList(), ['v1']);
      expect(await VisitDao.openVisitForHousehold(_worker, 'h2'), isNull);
    });
  });

  testWidgets(
    'clinic day stats derive received, still-open and door-to-provider time',
    (tester) async {
      _useTempDb(tester, 'clinic_day_stats');

      await tester.runAsync(() async {
        await HouseholdDao.upsert(_household('h1'));
        await HouseholdDao.upsert(_household('h2'));
        await HouseholdDao.upsert(_household('h3'));
        await PersonDao.upsert(_person('p1', 'h1'));
        await PersonDao.upsert(_person('p2', 'h2'));
        await PersonDao.upsert(_person('p3', 'h3'));

        // Midday, not "now": a run in the small hours would otherwise file
        // these sessions on the previous local day, which is the very window
        // the day-stats query slices.
        final clock = DateTime.now();
        final now = DateTime(clock.year, clock.month, clock.day, 12);
        final startA = now.subtract(const Duration(hours: 3));
        final startB = now.subtract(const Duration(hours: 2));
        final startC = now.subtract(const Duration(hours: 1));
        await VisitDao.start(_visit('v1', 'h1', startA), [
          const VisitParticipant(
            visitId: 'v1',
            personId: 'p1',
            wasPresent: true,
            queueOrder: 0,
          ),
        ]);
        await VisitDao.start(_visit('v2', 'h2', startB), [
          const VisitParticipant(
            visitId: 'v2',
            personId: 'p2',
            wasPresent: true,
            queueOrder: 0,
          ),
        ]);
        await VisitDao.start(_visit('v3', 'h3', startC), [
          const VisitParticipant(
            visitId: 'v3',
            personId: 'p3',
            wasPresent: true,
            queueOrder: 0,
          ),
        ]);
        await AssessmentDao.save(
          _assessment('a1', 'v1', 'p1', startA.add(const Duration(minutes: 10))),
        );
        await AssessmentDao.save(
          _assessment('a2', 'v2', 'p2', startB.add(const Duration(minutes: 30))),
        );
        // v2 is closed; v1 and v3 stay open; v3 has no saved assessment.
        await VisitDao.complete('v2');

        final stats = await VisitDao.clinicDayStats(_worker, DateTime.now());
        expect(stats.received, 3);
        expect(stats.openNow, 2);
        expect(
          stats.avgMinutesToFirstAssessment,
          20.0,
          reason: 'mean of 10 and 30 minutes to first saved assessment; the '
              'unassessed session contributes nothing',
        );
      });
    },
  );

  testWidgets('the board lists tickets in arrival order and gates cancel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final when = DateTime(2026, 9, 1, 6);
    final tickets = [
      ClinicQueueTicket(
        visit: _visit('v1', 'h1', when),
        householdName: 'Achana household',
        presentCount: 2,
        assessedCount: 0,
      ),
      ClinicQueueTicket(
        visit: _visit('v2', 'h2', when.add(const Duration(minutes: 20))),
        householdName: 'Fuseini household',
        presentCount: 2,
        assessedCount: 2,
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(_user),
          clinicQueueProvider.overrideWith((ref) async => tickets),
          clinicDayStatsProvider.overrideWith(
            (ref) async => const ClinicDayStats(
              received: 2,
              openNow: 1,
              avgMinutesToFirstAssessment: 12,
            ),
          ),
        ],
        child: const MaterialApp(home: ClinicQueueScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 patients received and still open'), findsOneWidget);
    expect(find.text('Achana household'), findsOneWidget);
    expect(find.text('Fuseini household'), findsOneWidget);

    // Today's front-door pace rides above the board.
    expect(find.text('Clinic pace today'), findsOneWidget);
    expect(find.text('2 received · 1 still open'), findsOneWidget);
    expect(
      find.text('Average wait to first assessment: 12 min'),
      findsOneWidget,
    );

    // Arrival order is preserved: the first-received ticket sits higher.
    expect(
      tester.getTopLeft(find.text('Achana household')).dy,
      lessThan(tester.getTopLeft(find.text('Fuseini household')).dy),
    );

    // The un-assessed ticket offers Continue + a destructive Cancel; the fully
    // assessed one offers Review and must never be cancellable here.
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Review session'), findsOneWidget);
    expect(
      find.text('Cancel open session'),
      findsOneWidget,
      reason: 'only a session with no saved assessment may be cancelled',
    );
  });
}
