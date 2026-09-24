import 'package:carebridge_ai/app/providers.dart';
import 'package:carebridge_ai/core/theme/app_theme.dart';
import 'package:carebridge_ai/core/theme/fhw_luxe.dart';
import 'package:carebridge_ai/data/repositories/insight_repository.dart';
import 'package:carebridge_ai/domain/engines/vulnerability_engine.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:carebridge_ai/presentation/fhw/clinic_widgets.dart';
import 'package:carebridge_ai/presentation/fhw/day_plan_tab.dart';
import 'package:carebridge_ai/presentation/fhw/household_screen.dart';
import 'package:carebridge_ai/presentation/fhw/home_tab.dart'
    show activeClinicSessionProvider;
import 'package:carebridge_ai/presentation/registration/patient_intake_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

const _household = Household(
  id: 'h-1',
  name: 'Alhassan household',
  region: 'Northern Region',
  district: 'Gushegu',
  community: 'Gushegu',
  createdBy: 'worker',
);
const _person = Person(
  id: 'p-1',
  householdId: 'h-1',
  fullName: 'Mariama Alhassan',
  clientType: ClientType.pregnantWoman,
);
const _priority = HouseholdPriority(
  household: _household,
  members: [_person],
  score: VulnerabilityScore(
    score: 35,
    band: VulnerabilityBand.high,
    factors: [
      RiskFactor(
        label: 'Missed scheduled contacts',
        detail: 'Two contacts have no completion recorded',
        points: 12,
        isModifiable: true,
      ),
    ],
    dataCompleteness: 0.5,
    confidence: RecommendationConfidence.low,
  ),
);
final _today = DateTime(2026, 9, 1);

ScheduledContact _contact(String id, {bool overdue = false}) =>
    ScheduledContact(
      id: id,
      personId: _person.id,
      householdId: _household.id,
      dueDate: overdue ? DateTime(2026, 8, 31) : _today,
      purpose: 'Review $id: antenatal blood pressure and haemoglobin follow-up',
      createdBy: 'worker',
    );

DayPlan _plan({
  List<ScheduledContact> overdue = const [],
  List<ScheduledContact> due = const [],
  List<HouseholdPriority> priorities = const [_priority],
  List<Referral> referrals = const [],
}) => DayPlan(
  priorities: priorities,
  dueContacts: due,
  overdueContacts: overdue,
  chaseReferrals: referrals,
  generatedAt: _today,
);

Widget _wrap(
  DayPlan plan, {
  double scale = 1,
  List<Override> overrides = const [],
}) => ProviderScope(
  overrides: [
    dayPlanProvider.overrideWith((ref) async => plan),
    currentUserProvider.overrideWithValue(
      AppUser(
        id: 'worker',
        fullName: 'Health worker',
        phone: '0244000000',
        role: UserRole.frontlineHealthWorker,
        region: 'Northern Region',
        district: 'Gushegu',
        community: 'Gushegu',
      ),
    ),
    householdProvider.overrideWith((ref, id) async => null),
    personProvider.overrideWith((ref, id) async => null),
    ...overrides,
  ],
  child: MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: const Scaffold(body: DayPlanTab()),
  ),
);

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 100,
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('empty schedule describes local records without reassurance', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(_plan(priorities: [])));
    await tester.pumpAndSettle();
    expect(find.text('Overdue (0)'), findsOneWidget);
    expect(find.text('Due today (0)'), findsOneWidget);
    expect(
      find.text('No care reviews scheduled on this phone'),
      findsOneWidget,
    );
    expect(find.textContaining('Nothing urgent'), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
    final surface = tester.widget<ColoredBox>(
      find
          .descendant(
            of: find.byType(DayPlanTab),
            matching: find.byType(ColoredBox),
          )
          .first,
    );
    expect(surface.color, AppColors.surface);
    final card = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(ClinicCard).first,
            matching: find.byType(Material),
          )
          .first,
    );
    expect(card.color, FhwLuxePalette.cardSurface);
  });

  testWidgets(
    'all overdue and today contacts have identity, dates and actions at 320px / 200%',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final overdue = List.generate(
        8,
        (i) => _contact('late-$i', overdue: true),
      );
      final due = List.generate(8, (i) => _contact('today-$i'));
      await tester.pumpWidget(
        _wrap(_plan(overdue: overdue, due: due), scale: 2),
      );
      await tester.pumpAndSettle();
      await _reveal(tester, find.text('Overdue (8)'));
      for (final contact in [...overdue, ...due]) {
        if (contact == due.first) {
          await _reveal(tester, find.text('Due today (8)'));
        }
        final tile = find.byKey(ValueKey('contact-${contact.id}'));
        await _reveal(tester, tile);
        expect(
          find.descendant(of: tile, matching: find.text(_person.fullName)),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: tile,
            matching: find.textContaining(_household.name),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: tile, matching: find.text(contact.purpose)),
          findsOneWidget,
        );
        final date = MaterialLocalizations.of(
          tester.element(tile),
        ).formatMediumDate(contact.dueDate);
        expect(
          find.descendant(of: tile, matching: find.textContaining(date)),
          findsOneWidget,
        );
        for (final label in ['Open assessment', 'Open household']) {
          // ButtonStyleButton is abstract, so match by subtype and walk back
          // from the visible label rather than naming a concrete button.
          final button = find.descendant(
            of: tile,
            matching: find.ancestor(
              of: find.text(label),
              matching: find.bySubtype<ButtonStyleButton>(),
            ),
          );
          await tester.ensureVisible(button);
          await tester.pumpAndSettle();
          expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
          expect(tester.widget<ButtonStyleButton>(button).onPressed, isNotNull);
          expect(tester.takeException(), isNull);
        }
      }
      await _reveal(tester, find.text('Household priorities (1)'));
      expect(
        find.textContaining('not a current triage diagnosis'),
        findsOneWidget,
      );
      await _reveal(tester, find.text('Saved-record reason'));
      expect(find.text(_priority.reason), findsOneWidget);
      expect(find.text('No visit recorded on this phone'), findsOneWidget);
      expect(find.byType(BackdropFilter), findsNothing);
    },
  );

  testWidgets(
    'overdue-only work remains actionable with a household fallback',
    (tester) async {
      final contact = _contact('unresolved', overdue: true);
      await tester.pumpWidget(_wrap(_plan(overdue: [contact], priorities: [])));
      await tester.pumpAndSettle();
      expect(
        find.text('No care reviews scheduled on this phone'),
        findsNothing,
      );
      await _reveal(tester, find.text('Patient name unavailable'));
      expect(find.text('Household details unavailable'), findsOneWidget);
      expect(find.text('Open assessment'), findsNothing);
      await _reveal(tester, find.text('Open household'));
      await tester.tap(find.text('Open household'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<HouseholdScreen>(find.byType(HouseholdScreen))
            .householdId,
        _household.id,
      );
      expect(contact.completedAt, isNull);
    },
  );

  testWidgets(
    'a scheduled contact opens the intake for its household, not a new visit',
    (tester) async {
      final contact = _contact('assess');
      await tester.pumpWidget(
        _wrap(
          _plan(due: [contact]),
          overrides: [
            visibleHouseholdsProvider.overrideWith((ref) async => [_household]),
            householdMembersProvider.overrideWith((ref, id) async => const []),
            activeClinicSessionProvider.overrideWith((ref) async => null),
          ],
        ),
      );
      await tester.pumpAndSettle();
      final tile = find.byKey(const ValueKey('contact-assess'));
      await _reveal(tester, tile);
      final action = find.descendant(
        of: tile,
        matching: find.text('Open assessment'),
      );
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      final intake = tester.widget<PatientIntakeScreen>(
        find.byType(PatientIntakeScreen),
      );
      expect(intake.initialHousehold?.id, _household.id);
      // The intake is a two-step journey: back returns to the household
      // picker first, so a single gesture never loses the session context.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Find the household record'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(PatientIntakeScreen), findsNothing);
      expect(contact.completedAt, isNull);
      await _reveal(tester, tile);
      expect(find.text(contact.purpose), findsOneWidget);
    },
  );

  testWidgets('missing plan identity resolves through existing providers', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        _plan(due: [_contact('provider')], priorities: []),
        overrides: [
          householdProvider.overrideWith((ref, id) async => _household),
          personProvider.overrideWith((ref, id) async => _person),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await _reveal(tester, find.byKey(const ValueKey('contact-provider')));
    expect(find.text(_person.fullName), findsOneWidget);
    expect(find.text('Open assessment'), findsOneWidget);
  });

  testWidgets(
    'urgent chase explains saved status and preserves check-in action',
    (tester) async {
      final referral = Referral(
        id: 'r-1',
        referenceCode: 'CB-1234',
        personId: _person.id,
        assessmentId: 'a-1',
        facilityName: 'District hospital',
        reason: 'Urgent referral from assessment',
        urgency: ReferralUrgency.immediate,
        status: ReferralStatus.travelling,
        issuedBy: 'worker',
        issuedAt: DateTime(2026, 8, 28),
      );
      await tester.pumpWidget(_wrap(_plan(referrals: [referral])));
      await tester.pumpAndSettle();
      await _reveal(tester, find.text('Urgent referral checks (1)'));
      expect(
        find.textContaining('does not mean the family did not attend'),
        findsOneWidget,
      );
      await _reveal(tester, find.text('Check referral status'));
      expect(
        find.text('Family reported travelling · Arrival unconfirmed'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Check referral status'),
            )
            .onPressed,
        isNotNull,
      );
      expect(referral.status, ReferralStatus.travelling);
    },
  );
}
