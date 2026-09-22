/// The language choice is made from the words themselves: every card shows
/// what that language can actually say for this message, and one press both
/// picks and plays it. These tests hold that contract — no confirm step, no
/// Cancel-only escape, no disabled control — plus the stale-result guards
/// around the audio buttons that open it.
library;

import 'dart:async';

import 'package:carebridge_ai/app/providers.dart';
import 'package:carebridge_ai/core/audio/caregiver_playback.dart';
import 'package:carebridge_ai/core/i18n/speech_bank.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:carebridge_ai/presentation/caregiver/help/caregiver_voice.dart';
import 'package:carebridge_ai/presentation/shared/audio_button.dart';
import 'package:carebridge_ai/presentation/settings/voice_test_screen.dart';
import 'package:carebridge_ai/presentation/shared/offline_voice_check.dart';
import 'package:carebridge_ai/presentation/shared/speech_language_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _user = AppUser(
  id: 'caregiver',
  fullName: 'Test caregiver',
  phone: '0240000001',
  role: UserRole.caregiver,
  region: 'Northern Region',
  district: 'Karaga',
  community: 'Karaga',
  preferredLanguage: 'Dagbani',
);
final _accountProvider = StateProvider<AppUser?>((ref) => _user);

CaregiverSpeech _bankSpeech({String language = 'Dagbani'}) => CaregiverSpeech(
  id: 'message',
  english: SpeechBank.qNewbornFeed.english,
  language: language,
  clipId: SpeechBank.qNewbornFeed.id,
);

Widget _app(Widget child, {double textScale = 1, bool reducedMotion = false}) =>
    ProviderScope(
      child: MaterialApp(
        builder: (context, page) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reducedMotion,
          ),
          child: page!,
        ),
        home: Scaffold(body: child),
      ),
    );

Widget _pickerApp(
  CaregiverSpeech speech,
  ValueChanged<String?> onResult, {
  double textScale = 1,
}) => _app(
  Builder(
    builder: (context) => Center(
      child: TextButton(
        onPressed: () async =>
            onResult(await chooseSpeechLanguage(context, speech)),
        child: const Text('Open picker'),
      ),
    ),
  ),
  textScale: textScale,
);

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder _choice(String language) =>
    find.byKey(ValueKey('speech-language-$language'));

SpeechLanguageTile _tile(WidgetTester tester, String language) =>
    tester.widget<SpeechLanguageTile>(_choice(language));

bool _selected(WidgetTester tester, String language) =>
    _tile(tester, language).selected;

/// The caregiver play button. Its label names the hold gesture because the
/// picker is a long press — a tap only ever means "speak this".
Finder _playButton(String language) =>
    find.byTooltip('Listen in $language. Hold to choose another language.');

Future<void> _holdToPick(
  WidgetTester tester, {
  String language = 'Dagbani',
}) async {
  await tester.longPress(_playButton(language));
  await tester.pumpAndSettle();
}

/// Makes every audio plugin resolve immediately: a real playback attempt with
/// no voice installed, which is exactly what a test device is.
void _stubSilentAudio(WidgetTester tester) {
  const tts = MethodChannel('flutter_tts');
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(tts, (call) async {
    if (call.method == 'getVoices' || call.method == 'getLanguages') {
      throw PlatformException(code: 'unavailable');
    }
    return 1;
  });
  messenger.setMockMessageHandler('flutter/assets', (message) async => null);
  addTearDown(() {
    messenger.setMockMethodCallHandler(tts, null);
    messenger.setMockMessageHandler('flutter/assets', null);
  });
}

class _RecordingVoice implements CaregiverVoiceBackend {
  final requests = <CaregiverSpeech>[];
  final events = <void Function(CaregiverPlayback)>[];
  final pending = <Completer<void>>[];
  int stops = 0;
  bool fail = false;

  @override
  Future<void> play(
    CaregiverSpeech speech,
    void Function(CaregiverPlayback) event,
  ) {
    requests.add(speech);
    events.add(event);
    if (fail) return Future<void>.error(StateError('No offline voice'));
    final done = Completer<void>();
    pending.add(done);
    return done.future;
  }

  void emit(int request, CaregiverPlaybackPhase phase) {
    final speech = requests[request];
    events[request](
      CaregiverPlayback(
        phase: phase,
        transcript: speech.localizedText ?? speech.english,
        language: speech.localizedText == null ? 'English' : speech.language,
        source: 'Bundled synthetic voice • draft translation',
      ),
    );
    if (phase == CaregiverPlaybackPhase.completed ||
        phase == CaregiverPlaybackPhase.fallback) {
      if (!pending[request].isCompleted) pending[request].complete();
    }
  }

  @override
  Future<void> stop() async {
    stops++;
    for (final done in pending) {
      if (!done.isCompleted) done.complete();
    }
  }

  @override
  Future<void> dispose() => stop();
}

ProviderContainer _container(CaregiverVoiceBackend Function() backend) =>
    ProviderContainer(
      overrides: [
        currentUserProvider.overrideWith((ref) => ref.watch(_accountProvider)),
        linkedHouseholdProvider.overrideWithValue('family'),
        caregiverVoiceBackendProvider.overrideWithValue(backend),
      ],
    );

Widget _listenApp(
  ProviderContainer container,
  Widget child, {
  bool reducedMotion = true,
}) => UncontrolledProviderScope(
  container: container,
  child: _app(
    SingleChildScrollView(child: child),
    reducedMotion: reducedMotion,
  ),
);

void main() {
  testWidgets(
    'settings samples preserve source language and exact bank content',
    (tester) async {
      const tts = MethodChannel('flutter_tts');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        tts,
        (call) async =>
            call.method == 'getLanguages' || call.method == 'getVoices'
            ? <String>[]
            : 1,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          tts,
          null,
        ),
      );
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_app(const VoiceTestScreen(), textScale: 2));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Try a language'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      final buttons = tester
          .widgetList<AudioButton>(find.byType(AudioButton))
          .toList();
      expect(buttons, hasLength(4));
      for (final button in buttons) {
        expect(button.sourceLanguage, button.language);
        expect(button.id, SpeechBank.qNewbornFeed.id);
        expect(
          button.text,
          button.language == 'English'
              ? SpeechBank.qNewbornFeed.english
              : SpeechBank.qNewbornFeed.textFor(button.language),
        );
      }
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Dagbani').last,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('Bridge to Hausa'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('every language card shows the words it can actually give', (
    tester,
  ) async {
    final results = <String?>[];
    await tester.pumpWidget(
      _pickerApp(
        const CaregiverSpeech(
          id: 'plain',
          english: 'Original message.',
          language: 'en_GH',
        ),
        results.add,
      ),
    );
    await _tapVisible(tester, find.text('Open picker'));

    expect(find.byType(SpeechLanguageTile), findsNWidgets(4));
    // The saved locale is canonicalised, so 'en_GH' opens on English.
    expect(_selected(tester, 'English'), isTrue);
    expect(_selected(tester, 'Twi'), isFalse);
    // Availability is on the card before the tap, not discovered after it.
    expect(find.text('NEEDS A PHONE VOICE'), findsOneWidget);
    expect(find.text('ENGLISH WORDS ONLY'), findsWidgets);
    expect(
      find.textContaining("native speaker's ear and clinical review"),
      findsOneWidget,
    );
    // A real tap target for a worried thumb, and nothing chosen yet.
    expect(tester.getRect(_choice('Hausa')).height, greaterThanOrEqualTo(44));
    expect(results, isEmpty);

    await _tapVisible(tester, find.byTooltip('Close'));
    expect(results, [null]);
  });

  testWidgets('one press on a card is the whole choice', (tester) async {
    final speech = _bankSpeech(language: 'tw');
    final results = <String?>[];
    await tester.pumpWidget(_pickerApp(speech, results.add));
    await _tapVisible(tester, find.text('Open picker'));

    expect(_selected(tester, 'Twi'), isTrue);
    expect(find.text(SpeechBank.qNewbornFeed.twi), findsOneWidget);
    expect(find.text('VOICE AVAILABLE TO TRY'), findsWidgets);
    expect(find.text('READY ON THIS PHONE'), findsNothing);

    // No confirm button exists: the card IS the request to hear it.
    await _tapVisible(tester, _choice('Hausa'));
    expect(results, ['Hausa']);
    // Choosing for one message never rewrites the account default.
    expect(speech.language, 'tw');
    expect(_user.preferredLanguage, 'Dagbani');
  });

  testWidgets('a language with no words says so on its own card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final original = List.generate(
      70,
      (i) => 'Original message line $i.',
    ).join('\n');
    final results = <String?>[];
    await tester.pumpWidget(
      _pickerApp(
        CaregiverSpeech(
          id: 'long',
          english: original,
          language: 'Hausa',
          clipId: SpeechBank.qNewbornFeed.id,
        ),
        results.add,
        textScale: 2.2,
      ),
    );
    await _tapVisible(tester, find.text('Open picker'));
    expect(tester.takeException(), isNull);

    // The Hausa card admits it has no Hausa words, and shows what it will do.
    expect(find.text('ENGLISH WORDS ONLY'), findsWidgets);
    expect(find.text(original), findsWidgets);
    // English is always offered, so there is no dead end and no disabled card.
    expect(
      tester.widget<SpeechLanguageTile>(_choice('English')).onSelected,
      isNotNull,
    );
    expect(find.byKey(const ValueKey('speech-language-listen')), findsNothing);

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await _tapVisible(tester, _choice('English'));
    expect(results, ['English']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AudioButton hold picks a language and tap plays', (
    tester,
  ) async {
    _stubSilentAudio(tester);
    const original = 'A different message, not the registered bank wording.';
    await tester.pumpWidget(
      _app(
        const Center(
          child: AudioButton(
            id: 'q_newborn.feed',
            text: original,
            language: 'Dagbani',
            compact: true,
          ),
        ),
      ),
    );
    expect(
      find.byTooltip('Play audio. Hold to choose another language.'),
      findsOneWidget,
    );

    await tester.longPress(find.byType(AudioButton));
    await tester.pumpAndSettle();
    expect(find.byType(SpeechLanguageTile), findsNWidgets(4));
    expect(find.text(original), findsWidgets);
    expect(find.text(SpeechBank.qNewbornFeed.english), findsNothing);
    expect(find.text('ENGLISH WORDS ONLY'), findsWidgets);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(SpeechLanguageTile), findsNothing);
    expect(find.textContaining('Audio unavailable'), findsNothing);

    // Tapping the same button goes straight to the words the caller chose.
    await tester.tap(find.byType(AudioButton));
    await tester.pumpAndSettle();
    expect(find.byType(SpeechLanguageTile), findsNothing);
    // A real attempt, honestly reported: no Dagbani words for this text and
    // no voice on a test device, so the button says so instead of guessing.
    final details = find.byTooltip(
      'English • Audio unavailable. Transcript and voice setup',
    );
    expect(details, findsOneWidget);
    await tester.tap(details);
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(OfflineVoiceCheck), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'unsupported setup language is visible without a dropdown crash',
    (tester) async {
      await tester.pumpWidget(
        _app(const OfflineVoiceCheck(language: 'French')),
      );
      expect(find.text('French (unsupported)'), findsOneWidget);
      await tester.tap(find.text('Check voice'));
      await tester.pumpAndSettle();
      expect(find.textContaining('French is not supported'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('localized source is never labeled as English translation', (
    tester,
  ) async {
    await tester.pumpWidget(
      _pickerApp(
        const CaregiverSpeech(
          id: 'localized',
          english: 'Maakye.',
          sourceLanguage: 'Twi',
          language: 'Hausa',
        ),
        (_) {},
      ),
    );
    await _tapVisible(tester, find.text('Open picker'));
    expect(find.text('TWI WORDS ONLY'), findsWidgets);
    expect(find.text('ENGLISH WORDS ONLY'), findsNothing);
    expect(
      speechOffering(_tile(tester, 'English').speech, 'English').audioReady,
      isFalse,
    );
  });

  testWidgets('compact feedback fits an app bar at large text scale', (
    tester,
  ) async {
    _stubSilentAudio(tester);
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _app(
        Scaffold(
          appBar: AppBar(
            title: const Text('Help'),
            actions: const [
              AudioButton(
                text: 'A new message.',
                language: 'Dagbani',
                compact: true,
              ),
            ],
          ),
        ),
        textScale: 2.2,
      ),
    );
    await tester.tap(
      find.byTooltip('Play audio. Hold to choose another language.'),
    );
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Tooltip &&
            (widget.message?.contains('Transcript and voice setup') ?? false),
      ),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byType(AudioButton)).height,
      lessThanOrEqualTo(kToolbarHeight),
    );
    if (find.byTooltip('Stop audio').evaluate().isNotEmpty) {
      await tester.tap(find.byTooltip('Stop audio'));
      await tester.pumpAndSettle();
      expect(
        find.byTooltip('English • Stopped. Transcript and voice setup'),
        findsOneWidget,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a play button with no picker never opens a sheet', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const Center(
          child: AudioButton(
            id: 'setup_preview_English',
            text: 'Breastfeed on demand, day and night.',
            language: 'English',
            compact: true,
            showLanguagePicker: false,
          ),
        ),
      ),
    );
    expect(find.byTooltip('Play audio'), findsOneWidget);
    await tester.longPress(find.byType(AudioButton));
    await tester.pumpAndSettle();
    expect(find.byType(SpeechLanguageTile), findsNothing);
    // A held button that does nothing must not pretend to have played.
    expect(find.textContaining('Audio unavailable'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('caregiver tap speaks the family language without a sheet', (
    tester,
  ) async {
    final backend = _RecordingVoice();
    final container = _container(() => backend);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      _listenApp(container, CaregiverListen(speech: _bankSpeech())),
    );
    await _tapVisible(tester, _playButton('Dagbani'));
    expect(find.byType(SpeechLanguageTile), findsNothing);
    expect(backend.requests.single.language, 'Dagbani');
    expect(find.text('Loading'), findsOneWidget);
    expect(find.text('Selected: Dagbani'), findsOneWidget);
  });

  testWidgets('caregiver dismissal never plays audio', (tester) async {
    final backend = _RecordingVoice();
    final container = _container(() => backend);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      _listenApp(container, CaregiverListen(speech: _bankSpeech())),
    );
    await _holdToPick(tester);
    await _tapVisible(tester, find.byTooltip('Close'));
    expect(backend.requests, isEmpty);
    expect(container.read(currentUserProvider)!.preferredLanguage, 'Dagbani');
    await _holdToPick(tester);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(backend.requests, isEmpty);
    expect(find.text('Selected: Dagbani'), findsOneWidget);
  });

  testWidgets('caregiver card press plays that language and real phases', (
    tester,
  ) async {
    final backend = _RecordingVoice();
    final container = _container(() => backend);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      _listenApp(container, CaregiverListen(speech: _bankSpeech())),
    );
    expect(backend.requests, isEmpty);
    await _holdToPick(tester);
    await _tapVisible(tester, _choice('Hausa'));

    // One press chose Hausa and started it; the sheet is gone.
    expect(find.byType(SpeechLanguageTile), findsNothing);
    expect(backend.requests.single.language, 'Hausa');
    expect(container.read(currentUserProvider)!.preferredLanguage, 'Dagbani');
    expect(find.text('Selected: Hausa'), findsOneWidget);
    expect(find.text('Loading'), findsOneWidget);
    expect(find.text('Playing'), findsNothing);
    expect(find.text('Hausa transcript'), findsOneWidget);
    expect(find.text(SpeechBank.qNewbornFeed.hausa), findsOneWidget);

    backend.emit(0, CaregiverPlaybackPhase.playing);
    await tester.pumpAndSettle();
    expect(find.text('Playing'), findsOneWidget);
    expect(
      find.textContaining('Hausa • Bundled synthetic voice'),
      findsOneWidget,
    );
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
    backend.emit(0, CaregiverPlaybackPhase.completed);
    await tester.pumpAndSettle();
    expect(find.text('Playback complete'), findsOneWidget);
    expect(find.byTooltip('Stop audio'), findsNothing);
  });

  testWidgets('loading can be stopped and stale playback events stay stopped', (
    tester,
  ) async {
    final backend = _RecordingVoice();
    final container = _container(() => backend);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      _listenApp(container, CaregiverListen(speech: _bankSpeech())),
    );
    await _tapVisible(tester, _playButton('Dagbani'));
    expect(find.text('Loading'), findsOneWidget);
    await _tapVisible(tester, find.byTooltip('Stop audio'));
    expect(backend.stops, 1);
    expect(find.text('Stopped'), findsOneWidget);
    backend.emit(0, CaregiverPlaybackPhase.playing);
    await tester.pumpAndSettle();
    expect(find.text('Stopped'), findsOneWidget);
    expect(find.text('Playing'), findsNothing);
  });

  testWidgets(
    'failed playback keeps translated text and an honest fallback label',
    (tester) async {
      final backend = _RecordingVoice()..fail = true;
      final container = _container(() => backend);
      addTearDown(container.dispose);
      await tester.pumpWidget(
        _listenApp(container, CaregiverListen(speech: _bankSpeech())),
      );
      await _tapVisible(tester, _playButton('Dagbani'));
      expect(find.text('Audio unavailable'), findsOneWidget);
      expect(find.text('Dagbani transcript'), findsOneWidget);
      expect(
        find.textContaining('Dagbani offline audio unavailable'),
        findsOneWidget,
      );
      expect(find.text(SpeechBank.qNewbornFeed.dagbani), findsOneWidget);
      expect(find.text('Playing'), findsNothing);
    },
  );

  for (final change in ['text', 'language', 'clips']) {
    testWidgets('same-id $change change invalidates an open picker', (
      tester,
    ) async {
      final backend = _RecordingVoice();
      final container = _container(() => backend);
      addTearDown(container.dispose);
      final speech = ValueNotifier(_bankSpeech());
      addTearDown(speech.dispose);
      await tester.pumpWidget(
        _listenApp(
          container,
          ValueListenableBuilder<CaregiverSpeech>(
            valueListenable: speech,
            builder: (context, value, _) => CaregiverListen(speech: value),
          ),
        ),
      );
      await _holdToPick(tester);
      speech.value = CaregiverSpeech(
        id: 'message',
        english: change == 'text'
            ? 'Updated original message.'
            : speech.value.english,
        language: change == 'language' ? 'Twi' : 'Dagbani',
        clipId: speech.value.clipId,
        clipIds: change == 'clips' ? [SpeechBank.qNewbornFast.id] : null,
      );
      await tester.pump();
      // The card press returns the stale sheet's language.
      await _tapVisible(tester, _choice('Dagbani'));
      expect(backend.requests, isEmpty);
      expect(find.text('Loading'), findsNothing);
    });
  }

  testWidgets(
    'same-id message replacement stops old playback and hides stale transcript',
    (tester) async {
      final backend = _RecordingVoice();
      final container = _container(() => backend);
      addTearDown(container.dispose);
      final speech = ValueNotifier(_bankSpeech());
      addTearDown(speech.dispose);
      await tester.pumpWidget(
        _listenApp(
          container,
          ValueListenableBuilder<CaregiverSpeech>(
            valueListenable: speech,
            builder: (context, value, _) => CaregiverListen(speech: value),
          ),
        ),
      );
      await _tapVisible(tester, _playButton('Dagbani'));
      speech.value = const CaregiverSpeech(
        id: 'message',
        english: 'Updated original message.',
        language: 'Dagbani',
      );
      await tester.pumpAndSettle();
      expect(backend.stops, 1);
      backend.emit(0, CaregiverPlaybackPhase.playing);
      await tester.pumpAndSettle();
      expect(find.text(SpeechBank.qNewbornFeed.dagbani), findsNothing);
      expect(find.text('Updated original message.'), findsOneWidget);
      expect(find.text('Playing'), findsNothing);
    },
  );

  testWidgets('account switch away and back rejects an old dialog result', (
    tester,
  ) async {
    final backends = <_RecordingVoice>[];
    final container = _container(() {
      final backend = _RecordingVoice();
      backends.add(backend);
      return backend;
    });
    addTearDown(container.dispose);
    await tester.pumpWidget(
      _listenApp(container, CaregiverListen(speech: _bankSpeech())),
    );
    await _holdToPick(tester);
    container.read(_accountProvider.notifier).state = null;
    await tester.pump();
    container.read(_accountProvider.notifier).state = _user;
    await tester.pump();
    await _tapVisible(tester, _choice('Dagbani'));
    expect(backends.expand((backend) => backend.requests), isEmpty);
    expect(find.text('Loading'), findsNothing);
    expect(find.text('Playing'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
