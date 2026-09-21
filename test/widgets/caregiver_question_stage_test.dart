/// The question screen used to be a plain white card with a shouty YES/NO row
/// and a greyed-out "Next" that did nothing until she guessed why. It is now a
/// navy stage that carries the words, the voice and the language choice, and an
/// answer deck whose step control is never dead. These are those guarantees.
library;

import 'dart:async';

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
import 'package:carebridge_ai/presentation/shared/speech_language_sheet.dart';
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
  preferredLanguage: 'Dagbani',
);
const scope = CaregiverScope(userId: 'user', householdId: 'family');
final now = DateTime(2026, 8, 10, 9);

final Person child = Person(
  id: 'kid',
  householdId: 'family',
  fullName: 'Fusea Issah',
  clientType: ClientType.childUnderFive,
  dateOfBirth: now.subtract(const Duration(days: 400)),
);

class _FamilyRepository extends CareRepository {
  @override
  Future<List<Person>> visitQueue(AppUser user, String householdId) async => [
    child,
  ];

  @override
  Future<Person?> person(AppUser user, String id) async =>
      id == child.id ? child : null;

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

/// Records what the screen asked to be spoken, and never finishes, so the play
/// control stays in its "playing" state for the assertions that need it.
class _RecordingVoice implements CaregiverVoiceBackend {
  static final requests = <CaregiverSpeech>[];
  static final pending = <Completer<void>>[];

  @override
  Future<void> play(
    CaregiverSpeech speech,
    void Function(CaregiverPlayback) event,
  ) {
    requests.add(speech);
    final done = Completer<void>();
    pending.add(done);
    return done.future;
  }

  @override
  Future<void> stop() async {
    for (final done in pending) {
      if (!done.isCompleted) done.complete();
    }
  }

  @override
  Future<void> dispose() => stop();
}

Future<void> _open(
  WidgetTester tester, {
  double scale = 1,
  Size size = const Size(390, 844),
}) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  _RecordingVoice.requests.clear();
  _RecordingVoice.pending.clear();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        careRepositoryProvider.overrideWithValue(_FamilyRepository()),
        currentUserProvider.overrideWithValue(user),
        linkedHouseholdProvider.overrideWithValue('family'),
        caregiverScopeProvider.overrideWithValue(scope),
        caregiverClockProvider.overrideWithValue(() => now),
        caregiverVoiceBackendProvider.overrideWithValue(_RecordingVoice.new),
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
  // The check opens on her own worry; choosing none still asks every sign.
  final worry = find.text('No specific worry — just check');
  await tester.ensureVisible(worry);
  await tester.pumpAndSettle();
  await tester.tap(worry);
  await tester.pumpAndSettle();
}

/// The stage is a lazy list, so a line can exist without being built yet.
/// Scroll until it appears, then assert it stayed in view.
Future<void> _expectText(WidgetTester tester, String text) async {  final finder = find.text(text);
  for (var i = 0; i < 8 && finder.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(ListView).first, const Offset(0, -320));
    await tester.pumpAndSettle();
  }
  expect(finder, findsWidgets, reason: text);
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
  expect(finder, findsWidgets, reason: text);
}

/// A control in the stage has to be in view before a finger can reach it.
Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}


void main() {
  testWidgets('the question is a stage, not a form card', (tester) async {
    await _open(tester);
    expect(tester.takeException(), isNull);

    await _expectText(tester, 'QUESTION 1 OF 8');
    await _expectText(tester, 'Fusea Issah');
    await _expectText(tester, 'Hear this question');
    await _expectText(tester, 'YOUR ANSWER');
    await _expectText(tester, 'Yes');
    await _expectText(tester, 'This is happening');
    await _expectText(tester, 'Not sure');
    // Shouty all-caps answers are gone; the words read as a conversation.
    expect(find.text('YES'), findsNothing);
    expect(find.text('NOT SURE'), findsNothing);
    // Eight questions, eight ticks.
    expect(find.text('Question 1 of 8'), findsNothing);
  });

  testWidgets('the play control plays at once in the family language', (
    tester,
  ) async {
    await _open(tester);
    // No sheet, no question back: a play button makes a sound.
    expect(find.byType(SpeechLanguageTile), findsNothing);
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pumpAndSettle();

    expect(_RecordingVoice.requests, hasLength(1));
    expect(_RecordingVoice.requests.single.language, 'Dagbani');
    expect(find.byType(SpeechLanguageTile), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the language rail shows words and one tap speaks them', (
    tester,
  ) async {
    await _open(tester);
    await tester.tap(find.byTooltip('Read this in another language'));
    await tester.pumpAndSettle();

    expect(find.byType(SpeechLanguageTile), findsNWidgets(4));
    // Availability sits on the card before the tap, never after it.
    expect(find.text('READY ON THIS PHONE'), findsWidgets);
    expect(find.text('NEEDS A PHONE VOICE'), findsOneWidget);
    expect(find.text('Say this in'), findsNothing);
    expect(find.text('Cancel'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('speech-language-Twi')));
    await tester.pumpAndSettle();

    expect(_RecordingVoice.requests.last.language, 'Twi');
    // The rail closes on itself: she is back at the question, not a dialog.
    expect(find.byType(SpeechLanguageTile), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unanswered question is a prompt, never a dead button', (
    tester,
  ) async {
    await _open(tester);
    expect(find.text('Continue'), findsNothing);
    await _expectText(tester, 'Choose one to continue');
    // Tapping it does the only useful thing: point at the answers.
    await tester.tap(find.text('Choose one to continue'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Continue'), findsNothing);

    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();
    await _expectText(tester, 'Continue');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await _expectText(tester, 'QUESTION 2 OF 8');
    // The step back lives on the stage, so an answer is never a one-way door.
    expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);
  });

  testWidgets('the stage holds together on a 320px handset at 200% text', (
    tester,
  ) async {
    await _open(tester, size: const Size(320, 720), scale: 2);
    expect(tester.takeException(), isNull);
    // The voice control is read first: at this size the stage below it is not
    // built until she scrolls, and the hero must survive being scrolled past.
    await _expectText(tester, 'QUESTION 1 OF 8');
    await _tap(tester, find.byTooltip('Read this in another language'));
    expect(find.byType(SpeechLanguageTile), findsNWidgets(4));
    expect(tester.takeException(), isNull);
    await _tap(tester, find.byTooltip('Close the language list'));

    await _expectText(tester, 'Choose one to continue');
    await _expectText(tester, 'I cannot tell');
    expect(tester.takeException(), isNull);
  });
}
