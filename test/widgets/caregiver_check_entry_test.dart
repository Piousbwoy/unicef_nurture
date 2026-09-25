/// Everyone the nurse can assess, the caregiver can check: a six-year-old and
/// a general-care woman used to land on a blocked screen, which read as a
/// broken app. The check now opens for every registered person, and the entry
/// screens have to survive a 320px handset at 200% text, because that is the
/// device most caregivers in the north actually hold.
library;

import 'package:carebridge_ai/app/providers.dart';
import 'package:carebridge_ai/core/audio/caregiver_playback.dart';
import 'package:carebridge_ai/core/theme/app_theme.dart';
import 'package:carebridge_ai/data/repositories/care_repository.dart';
import 'package:carebridge_ai/domain/entities/caregiver.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:carebridge_ai/presentation/caregiver/caregiver_providers.dart';
import 'package:carebridge_ai/presentation/caregiver/check/triage_screen.dart';
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
const household = Household(
  id: 'family',
  name: 'Issah household',
  region: 'Northern Region',
  district: 'Karaga',
  community: 'Karaga',
  createdBy: 'worker',
);
const scope = CaregiverScope(userId: 'user', householdId: 'family');
final now = DateTime(2026, 8, 10, 9);

Person _kid({required int ageInDays}) => Person(
  id: 'kid',
  householdId: 'family',
  fullName: 'Fusea Issah',
  clientType: ClientType.childUnderFive,
  dateOfBirth: now.subtract(Duration(days: ageInDays)),
);

Person _woman() => const Person(
  id: 'kid',
  householdId: 'family',
  fullName: 'Fusea Issah',
  clientType: ClientType.womanOfReproductiveAge,
);

class _FamilyRepository extends CareRepository {
  _FamilyRepository(this.members);
  final List<Person> members;

  @override
  Future<List<Person>> visitQueue(AppUser user, String householdId) async =>
      members;

  @override
  Future<Person?> person(AppUser user, String id) async =>
      members.where((p) => p.id == id).firstOrNull;

  @override
  Future<CaregiverDraft?> caregiverDraft(
    AppUser user,
    CaregiverScope scope,
    String id,
    CaregiverDraftKind kind,
  ) async => null;

  @override
  Future<CaregiverSettings?> caregiverSettings(
    AppUser user,
    CaregiverScope scope,
  ) async => null;
}

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
  WidgetTester tester,
  List<Person> members, {
  double scale = 1,
  Size size = const Size(390, 844),
}) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        careRepositoryProvider.overrideWithValue(_FamilyRepository(members)),
        currentUserProvider.overrideWithValue(user),
        linkedHouseholdProvider.overrideWithValue('family'),
        caregiverScopeProvider.overrideWithValue(scope),
        caregiverClockProvider.overrideWithValue(() => now),
        caregiverVoiceBackendProvider.overrideWithValue(_SilentVoice.new),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(
            textScaler: TextScaler.linear(scale),
            size: size,
          ),
          child: const CaregiverTriageScreen(
            householdId: 'family',
            personId: 'kid',
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The check screens are longer than one viewport at 200% text, so every
/// assertion scrolls its target into view first.
Future<void> _expectText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  expect(finder, findsWidgets, reason: text);
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
  expect(finder, findsWidgets, reason: text);
}

void main() {
  testWidgets('a child past five starts the child battery, not a block', (
    tester,
  ) async {
    await _open(tester, [_kid(ageInDays: 6 * 365)]);
    expect(tester.takeException(), isNull);
    await _expectText(tester, 'What is worrying you about Fusea today?');
    await _expectText(tester, 'Very thin or swollen feet');
    expect(find.text('Past the under-five window'), findsNothing);
    expect(find.text('Who this check is for'), findsNothing);

    await tester.tap(find.text('No specific worry — just check'));
    await tester.pumpAndSettle();
    await _expectText(tester, 'Is the child unable to drink or breastfeed?');
  });

  testWidgets('a general-care woman gets the maternal battery without the '
      'fetal-movement worry', (tester) async {
    await _open(tester, [_woman()]);
    expect(tester.takeException(), isNull);
    await _expectText(tester, 'What is worrying you about Fusea today?');
    await _expectText(tester, 'Bleeding');
    // Her battery has no fetal-movement question, so the picker must not
    // offer a worry that leads to a question she will never be asked.
    expect(find.text('Baby moving less'), findsNothing);
    expect(find.text('A different kind of record'), findsNothing);

    await tester.tap(find.text('No specific worry — just check'));
    await tester.pumpAndSettle();
    await _expectText(tester, 'Is there heavy bleeding?');
  });

  testWidgets('the check entry fits 320px at 200% text', (tester) async {
    await _open(
      tester,
      [_kid(ageInDays: 6 * 365)],
      scale: 2,
      size: const Size(320, 720),
    );
    expect(tester.takeException(), isNull);
    expect(
      find.text('What is worrying you about Fusea today?'),
      findsOneWidget,
    );
  });
}
