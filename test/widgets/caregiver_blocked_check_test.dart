/// A person outside the check's scope used to land on one grey paragraph and a
/// "Get help" button, which read as a broken app. The screen now names the
/// exact reason, shows what the record says, and offers a way forward — and it
/// has to survive a 320px handset at 200% text, because that is the device
/// most caregivers in the north actually hold.
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

/// The check list is longer than one screen at 200% text, so every assertion
/// scrolls its target into view first.
Future<void> _expectText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  expect(finder, findsWidgets, reason: text);
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
  expect(finder, findsWidgets, reason: text);
}

void main() {
  testWidgets(
    'a child past five is told why, shown the record and given a way on',
    (tester) async {
      await _open(tester, [_kid(ageInDays: 6 * 365)]);
      expect(tester.takeException(), isNull);
      await _expectText(tester, 'Past the under-five window');
      await _expectText(tester, 'What the record says');
      await _expectText(tester, 'Who this check is for');
      await _expectText(tester, 'Check someone else');
      // The honesty line stays, with the real name instead of the old
      // sentence-ending interpolation that read as a broken string.
      await _expectText(
        tester,
        'Nothing was saved. No danger-sign check was done and no health '
        'conclusion has been made for Fusea Issah.',
      );

      await tester.tap(find.text('Check someone else'));
      await tester.pumpAndSettle();
      expect(find.text('Who needs a check today?'), findsOneWidget);
    },
  );

  testWidgets('a missing birth date names the missing field, not the app', (
    tester,
  ) async {
    await _open(tester, [_woman()]);
    expect(tester.takeException(), isNull);
    await _expectText(tester, 'A different kind of record');
    await _expectText(tester, 'Woman (general care)');
    await _expectText(tester, 'Add a family member');
    await _expectText(tester, 'Emergency — do not wait for a check');
  });

  testWidgets('the blocked screen fits 320px at 200% text', (tester) async {
    await _open(
      tester,
      [_kid(ageInDays: 6 * 365)],
      scale: 2,
      size: const Size(320, 720),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Past the under-five window'), findsOneWidget);
  });
}
