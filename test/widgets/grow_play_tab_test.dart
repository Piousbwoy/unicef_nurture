/// Growth & Play is the tab a caregiver lingers on, so the play card is
/// restaged as one "today's moment": the child's portrait, the age band, the
/// activity set as the largest words on the tab, and the band's caregiver
/// tip — content that always existed in NcAgeBand but was never shown.
/// These tests fail until each of those is on screen, and they keep failing
/// if the redesign ever drops the honesty lines the tab promises today.
library;

import 'package:carebridge_ai/app/providers.dart';
import 'package:carebridge_ai/core/audio/caregiver_playback.dart';
import 'package:carebridge_ai/core/theme/app_theme.dart';
import 'package:carebridge_ai/data/repositories/care_repository.dart';
import 'package:carebridge_ai/domain/engines/nurturing_care_engine.dart';
import 'package:carebridge_ai/domain/entities/caregiver.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:carebridge_ai/presentation/caregiver/caregiver_providers.dart';
import 'package:carebridge_ai/presentation/caregiver/growth/grow_play_tab.dart';
import 'package:carebridge_ai/presentation/caregiver/help/caregiver_voice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

const user = AppUser(
  id: 'user',
  fullName: 'Asatu Issah',
  phone: '0240000001',
  role: UserRole.caregiver,
  region: 'Northern Region',
  district: 'Karaga',
  community: 'Karaga',
);
const scope = CaregiverScope(userId: 'user', householdId: 'family');
final now = DateTime(2026, 8, 10, 9);

/// 213 days old — floor(213 / 30.4375) = 7 months, inside the 6-to-8 band.
/// Day 10 of the month picks activities[10 % 5] = activities[0].
final child = Person(
  id: 'kid',
  householdId: 'family',
  fullName: 'Fusea Issah',
  clientType: ClientType.childUnderFive,
  dateOfBirth: now.subtract(const Duration(days: 213)),
);

const todayActivity =
    'Sit baby on a firm mat with 3 safe household objects (cup, spoon, cloth)';
const anotherActivity = 'Hide a cloth over a toy; let them pull it off to find the toy';
const bandTip = 'Name what you see, name what you do, name what baby does.';

class _SilentVoice implements CaregiverVoiceBackend {
  @override
  Future<void> play(
    CaregiverSpeech speech,
    void Function(CaregiverPlayback) event,
  ) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

Future<void> _open(
  WidgetTester tester, {
  double scale = 1,
  Size size = const Size(390, 844),
  bool focusOnChild = false,
}) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        careRepositoryProvider.overrideWithValue(CareRepository()),
        currentUserProvider.overrideWithValue(user),
        linkedHouseholdProvider.overrideWithValue('family'),
        caregiverScopeProvider.overrideWithValue(scope),
        caregiverClockProvider.overrideWithValue(() => now),
        caregiverVoiceBackendProvider.overrideWithValue(_SilentVoice.new),
        caregiverClinicalProvider.overrideWith(
          (ref, scope) => CaregiverClinicalData(
            members: [child],
            checks: const [],
            milestones: const [],
            assessments: const [],
            contacts: const [],
            referrals: const [],
          ),
        ),
        caregiverSettingsProvider.overrideWith(
          (ref, scope) => CaregiverSettings(
            scope: scope,
            updatedAt: now,
            selectedPersonId: focusOnChild ? 'kid' : null,
          ),
        ),
        caregiverActivityProvider.overrideWith((ref, scope) => const []),
        growthSeriesProvider.overrideWith((ref, personId) => const []),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(
            textScaler: TextScaler.linear(scale),
            size: size,
          ),
          child: const CaregiverGrowPlayTab(householdId: 'family'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The tab is a lazy ListView: content deep in it is not even built until the
/// list scrolls. This drags until the target exists, then nudges it on-screen.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  final view = find.byType(Scrollable).first;
  for (var i = 0; i < 40 && finder.evaluate().isEmpty; i++) {
    await tester.drag(view, const Offset(0, -300));
    await tester.pumpAndSettle();
  }
  if (finder.evaluate().isNotEmpty) {
    await tester.ensureVisible(finder.first);
    await tester.pumpAndSettle();
  }
}

Future<void> _expect(WidgetTester tester, String text) async {
  await _reveal(tester, find.text(text));
  expect(find.text(text), findsWidgets, reason: text);
}

Future<void> _expectPart(WidgetTester tester, String part) async {
  await _reveal(tester, find.textContaining(part));
  expect(find.textContaining(part), findsWidgets, reason: part);
}

Finder _orbOf(String asset) => find.byWidgetPredicate(
  (w) =>
      w is Image &&
      w.image is AssetImage &&
      (w.image as AssetImage).assetName == asset,
);

void main() {
  testWidgets('the play card names the band and shows the band tip', (
    tester,
  ) async {
    await _open(tester);
    expect(tester.takeException(), isNull);
    await _expect(tester, 'Play together today');
    await _expect(tester, todayActivity);
    await _expect(tester, '6 to 8 months');
    await _expect(tester, bandTip);
  });

  testWidgets('more play ideas reveals the rest of the band', (tester) async {
    await _open(tester);
    await _reveal(tester, find.text('More play ideas'));
    await tester.tap(find.text('More play ideas').last);
    await tester.pumpAndSettle();
    // Today's activity is the poster line and its own listen preview —
    // the expanded list must not repeat it a third time.
    expect(find.text(todayActivity), findsNWidgets(2));
    await _expect(tester, anotherActivity);
  });

  testWidgets('the child appears as a portrait on the play card and selector',
      (tester) async {
        await _open(tester, focusOnChild: true);
        expect(tester.takeException(), isNull);
        await _reveal(tester, find.text('We tried this'));
        expect(
          _orbOf('assets/images/card_child.png'),
          findsAtLeastNWidgets(2),
          reason: 'one orb on the CARING FOR card, one on the play card',
        );
      });

  testWidgets('the restyle keeps every promise the tab made before', (
    tester,
  ) async {
    await _open(tester);
    expect(tester.takeException(), isNull);
    await _expectPart(
      tester,
      'No scores or competition \u2014 every family\u2019s day is different.',
    );
    await _expectPart(
      tester,
      'This records trying an activity, not a milestone or developmental '
      'result.',
    );
    await _expectPart(
      tester,
      'Use familiar household items only when safe for this child.',
    );
    await _expectPart(tester, 'Optional two-minute timer');
    await _expectPart(
      tester,
      'No clinic growth measurements saved on this phone',
    );
  });

  testWidgets('the tab fits 320px at 200% text', (tester) async {
    await _open(tester, scale: 2, size: const Size(320, 720));
    expect(tester.takeException(), isNull);
    await _expect(tester, 'Play together today');
    expect(tester.takeException(), isNull);
  });

  test('the deterministic day picks the activity the tests expect', () {
    final band = NurturingCareEngine.bands.firstWhere(
      (b) => b.minMonths == 6,
    );
    expect(NurturingCareEngine.activityToday(band, now), todayActivity);
    expect(band.tip, bandTip);
  });
}
