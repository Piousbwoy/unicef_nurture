import 'package:carebridge_ai/app/providers.dart';
import 'package:carebridge_ai/core/audio/speech_content_policy.dart';
import 'package:carebridge_ai/core/theme/app_theme.dart';
import 'package:carebridge_ai/domain/entities/caregiver.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:carebridge_ai/domain/services/caregiver_today_planner.dart';
import 'package:carebridge_ai/presentation/caregiver/caregiver_home.dart';
import 'package:carebridge_ai/presentation/caregiver/caregiver_providers.dart';
import 'package:carebridge_ai/presentation/caregiver/family/family_tab.dart';
import 'package:carebridge_ai/presentation/caregiver/widgets/companion.dart';
import 'package:carebridge_ai/presentation/shared/audio_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _scope = CaregiverScope(userId: 'caregiver', householdId: 'household');
const _person = Person(
  id: 'child',
  householdId: 'household',
  fullName: 'Abdul-Rahman Suleimana Alhassan',
  clientType: ClientType.childUnderFive,
);

Widget _app(Widget child, {double scale = 1, bool reduced = false}) =>
    MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: reduced,
        ),
        child: child!,
      ),
      home: Scaffold(body: child),
    );

Future<void> _hub(
  WidgetTester tester, {
  List<Person> people = const [_person],
  bool failMembers = false,
  bool failSettings = false,
  bool fullShell = false,
  bool reduced = true,
  double scale = 2,
  CaregiverDay? day,
  String? selectedPersonId,
}) async {
  tester.view.physicalSize = const Size(320, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        caregiverScopeProvider.overrideWithValue(_scope),
        currentUserProvider.overrideWithValue(
          AppUser(
            id: 'caregiver',
            fullName: 'Mariama Alhassan',
            phone: '',
            role: UserRole.caregiver,
            region: 'Northern Region',
            district: 'Tamale',
            community: 'Tamale',
          ),
        ),
        householdProvider.overrideWith((ref, id) async => null),
        householdMembersProvider.overrideWith((ref, id) async {
          if (failMembers) throw StateError('Local read failed');
          return people;
        }),
        caregiverSettingsProvider.overrideWith((ref, scope) async {
          if (failSettings) throw StateError('Settings unavailable');
          return CaregiverSettings(
            scope: scope,
            selectedPersonId: selectedPersonId,
            updatedAt: DateTime(2026, 9, 24),
          );
        }),
        caregiverClockProvider.overrideWithValue(
          () => DateTime(2026, 9, 24, 15),
        ),
        caregiverTodayProvider.overrideWith(
          (ref, scope) async =>
              day ??
              CaregiverDay(
                dateKey: '2026-09-24',
                attention: const [],
                routine: const [],
              ),
        ),
      ],
      child: _app(
        fullShell
            ? const CaregiverHome()
            : CaregiverFamilyTab(householdId: 'household', onSwitch: (_) {}),
        scale: scale,
        reduced: reduced,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('dock switches destinations without motion when reduced', (
    tester,
  ) async {
    var index = 0;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) => CaregiverNavigation(
            index: index,
            onSelect: (value) => setState(() => index = value),
          ),
        ),
        reduced: true,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Help'));
    await tester.pump();
    expect(index, 4);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('dock keeps all labels and touch targets at 320px and 200%', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var selected = -1;
    await tester.pumpWidget(
      _app(
        CaregiverNavigation(index: 0, onSelect: (i) => selected = i),
        scale: 2,
        reduced: true,
      ),
    );
    for (final (i, label) in CaregiverNavigation.labels.indexed) {
      final target = find.ancestor(
        of: find.text(label),
        matching: find.byType(InkWell),
      );
      expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
      await tester.tap(find.text(label));
      await tester.pump();
      expect(selected, i);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'whole shell keeps emergency access and instant navigation in Lite mode',
    (tester) async {
      SharedPreferences.setMockInitialValues({'reduced_effects': true});
      await _hub(tester, fullShell: true, reduced: false);
      expect(find.byType(BackdropFilter), findsNothing);
      expect(
        find.byType(CaregiverEmergencyButton).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.text('Help'));
      await tester.pump();
      expect(find.byType(CaregiverFamilyTab), findsNothing);
      for (final element in find.byType(AnimatedSwitcher).evaluate()) {
        expect(TickerMode.valuesOf(element).enabled, isFalse);
      }
      expect(
        find.byType(CaregiverEmergencyButton).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('family member is directly selectable without a modal at 200%', (
    tester,
  ) async {
    await _hub(tester);
    final member = find.bySemanticsLabel('Select ${_person.fullName}');
    await tester.scrollUntilVisible(
      member,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(member, findsOneWidget);
    expect(find.text('Choose family member'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a general-care member gets a portrait, not a generic icon', (
    tester,
  ) async {
    const woman = Person(
      id: 'woman',
      householdId: 'household',
      fullName: 'Habiba Yakubu',
      clientType: ClientType.womanOfReproductiveAge,
    );
    await _hub(tester, people: const [woman]);
    final portrait = find.byWidgetPredicate(
      (w) =>
          w is Image &&
          w.image is AssetImage &&
          (w.image as AssetImage).assetName == 'assets/images/card_woman.png',
    );
    await tester.scrollUntilVisible(
      portrait,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(portrait, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty family keeps add-member and check actions readable', (
    tester,
  ) async {
    await _hub(tester, people: const []);
    for (final label in ['Add a family member', 'Check on someone now']) {
      await tester.scrollUntilVisible(
        find.text(label),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text(label).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('failed family read shows retry without hiding check access', (
    tester,
  ) async {
    await _hub(tester, failMembers: true);
    await tester.scrollUntilVisible(
      find.text('Retry'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Retry').hitTestable(), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Check on someone now'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Check on someone now').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings failure leaves add-member and records accessible', (
    tester,
  ) async {
    await _hub(tester, failSettings: true);
    for (final label in [
      'View record: ${_person.fullName}',
      'Add a family member',
    ]) {
      await tester.scrollUntilVisible(
        find.text(label),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text(label).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('family hub keeps local-record guidance without code sharing', (
    tester,
  ) async {
    await _hub(tester, scale: 1);
    expect(find.text('Your family code'), findsNothing);
    expect(find.byIcon(Icons.copy_outlined), findsNothing);
    expect(
      find.text(
        'Local-only notes and home checks are not automatically uploaded.',
      ),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Add a family member'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Add a family member').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('urgent guidance stays visible for an unselected member', (
    tester,
  ) async {
    final focus = CaregiverFocus(
      personId: _person.id,
      sourceId: 'check',
      itemKey: 'urgent',
      source: CaregiverFocusSource.homeCheck,
      title: 'Go to the health facility now',
      detail: 'Get help for the danger sign you reported.',
      route: CaregiverFocusRoute.check,
      priority: 0,
      sourceTime: DateTime(2026, 9, 24),
    );
    await _hub(
      tester,
      selectedPersonId: 'another-member',
      day: CaregiverDay(dateKey: '2026-09-24', attention: [focus], routine: []),
    );
    await tester.scrollUntilVisible(
      find.text(focus.title),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text(focus.title).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'priority audio matches the visible guidance without a duplicate transcript',
    (tester) async {
      final focus = CaregiverFocus(
        personId: _person.id,
        sourceId: 'contact',
        itemKey: 'visit',
        source: CaregiverFocusSource.clinic,
        title: 'Visit your health worker',
        detail: 'Bring your family record.',
        route: CaregiverFocusRoute.carePlan,
        priority: 2,
        sourceTime: DateTime(2026, 9, 20),
        dueDate: DateTime(2026, 9, 24),
      );
      var opened = false;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            caregiverClockProvider.overrideWithValue(
              () => DateTime(2026, 9, 24, 15),
            ),
            currentUserProvider.overrideWithValue(null),
          ],
          child: _app(
            SingleChildScrollView(
              child: CaregiverFocusCard(
                focus: focus,
                dateKey: '2026-09-24',
                person: _person,
                onOpen: () async => opened = true,
              ),
            ),
            scale: 2,
            reduced: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final audio = tester.widget<AudioButton>(find.byType(AudioButton));
      expect(
        audio.text,
        '${_person.fullName} • ${caregiverAge(_person)}. Visit your health worker. Bring your family record. Due 24 Sep.',
      );
      expect(audio.language, 'English');
      expect(audio.policy, SpeechContentPolicy.clinical);
      expect(find.text(focus.detail), findsOneWidget);
      expect(find.text('Due 24 Sep'), findsOneWidget);
      expect(find.textContaining('Overdue'), findsNothing);
      await tester.ensureVisible(find.text('Open guidance'));
      await tester.tap(find.text('Open guidance'));
      await tester.pumpAndSettle();
      expect(opened, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
