import 'dart:async';

import 'package:carebridge_ai/app/providers.dart';
import 'package:carebridge_ai/core/audio/caregiver_playback.dart';
import 'package:carebridge_ai/core/i18n/speech_bank.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:carebridge_ai/presentation/caregiver/help/caregiver_voice.dart';
import 'package:carebridge_ai/presentation/shared/audio_button.dart';
import 'package:carebridge_ai/presentation/shared/speech_language_sheet.dart';
import 'package:flutter/material.dart';
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
    MaterialApp(
      builder: (context, page) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reducedMotion,
        ),
        child: page!,
      ),
      home: Scaffold(body: child),
    );

Widget _pickerApp(
  CaregiverSpeech speech,
  ValueChanged<String?> onResult, {
  double textScale = 1,
}) => _app(
  Builder(
    builder: (context) => Center(
      child: TextButton(
        onPressed: () async => onResult(await chooseSpeechLanguage(context, speech)),
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

Finder _choice(String language) => find.byKey(ValueKey('speech-language-$language'));

class _RecordingVoice implements CaregiverVoiceBackend {
  final requests = <CaregiverSpeech>[];
  final events = <void Function(CaregiverPlayback)>[];
  final pending = <Completer<void>>[];
  int stops = 0;
  bool fail = false;

  @override
  Future<void> play(CaregiverSpeech speech, void Function(CaregiverPlayback) event) {
    requests.add(speech);
    events.add(event);
    if (fail) return Future<void>.error(StateError('No offline voice'));
    final done = Completer<void>();
    pending.add(done);
    return done.future;
  }

  void emit(int request, CaregiverPlaybackPhase phase) {
    final speech = requests[request];
    events[request](CaregiverPlayback(
      phase: phase,
      transcript: speech.localizedText ?? speech.english,
      language: speech.localizedText == null ? 'English' : speech.language,
      source: 'Bundled synthetic voice • draft translation',
    ));
    if (phase == CaregiverPlaybackPhase.completed || phase == CaregiverPlaybackPhase.fallback) {
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

ProviderContainer _container(CaregiverVoiceBackend Function() backend) => ProviderContainer(
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
  child: _app(SingleChildScrollView(child: child), reducedMotion: reducedMotion),
);

void main() {
  testWidgets('picker offers four accessible choices and canonical saved locale', (tester) async {
    final results = <String?>[];
    await tester.pumpWidget(_pickerApp(
      const CaregiverSpeech(id: 'plain', english: 'Original message.', language: 'en_GH'),
      results.add,
    ));
    await _tapVisible(tester, find.text('Open picker'));

    expect(find.byType(ChoiceChip), findsNWidgets(4));
    for (final language in ['English', 'Twi', 'Dagbani', 'Hausa']) {
      final chip = tester.widget<ChoiceChip>(_choice(language));
      expect(chip.selected, language == 'English');
      expect(chip.onSelected, isNotNull);
      expect(chip.materialTapTargetSize, MaterialTapTargetSize.padded);
    }
    expect(find.textContaining('installed offline English voice'), findsOneWidget);
    expect(results, isEmpty);
    await _tapVisible(tester, find.text('Cancel'));
    expect(results, [null]);
  });

  testWidgets('draft preview changes language without changing the saved default', (tester) async {
    final speech = _bankSpeech(language: 'tw');
    final results = <String?>[];
    await tester.pumpWidget(_pickerApp(speech, results.add));
    await _tapVisible(tester, find.text('Open picker'));
    expect(tester.widget<ChoiceChip>(_choice('Twi')).selected, isTrue);
    expect(find.text(SpeechBank.qNewbornFeed.twi), findsOneWidget);
    expect(find.text(speech.english), findsOneWidget);
    expect(find.textContaining('Draft Twi translation'), findsOneWidget);
    expect(find.textContaining('native-speaker and clinical review'), findsOneWidget);

    await _tapVisible(tester, _choice('Hausa'));
    expect(find.text(SpeechBank.qNewbornFeed.hausa), findsOneWidget);
    expect(find.text(SpeechBank.qNewbornFeed.twi), findsNothing);
    expect(results, isEmpty);
    await _tapVisible(tester, find.text('Listen in Hausa'));
    expect(results, ['Hausa']);
    expect(speech.language, 'tw');

    await _tapVisible(tester, find.text('Open picker'));
    expect(tester.widget<ChoiceChip>(_choice('Twi')).selected, isTrue);
    await _tapVisible(tester, find.text('Cancel'));
    expect(results, ['Hausa', null]);
  });

  testWidgets('uncovered long message remains scrollable at large text size', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final original = List.generate(70, (i) => 'Original message line $i.').join('\n');
    final results = <String?>[];
    await tester.pumpWidget(_pickerApp(
      CaregiverSpeech(
        id: 'long',
        english: original,
        language: 'Hausa',
        clipId: SpeechBank.qNewbornFeed.id,
      ),
      results.add,
      textScale: 2.2,
    ));
    await _tapVisible(tester, find.text('Open picker'));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('No Hausa translation is available offline for this exact message'), findsOneWidget);
    expect(find.text(original), findsOneWidget);
    expect(find.text(SpeechBank.qNewbornFeed.english), findsNothing);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('speech-language-listen'))).onPressed, isNull);
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await _tapVisible(tester, find.text('Choose English'));
    expect(results, isEmpty); // Choosing English is not a playback request.
    expect(find.textContaining('installed offline English voice'), findsOneWidget);
    await _tapVisible(tester, find.text('Listen in English'));
    expect(results, ['English']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AudioButton tap and long press preview exact input and cancel silently', (tester) async {
    const original = 'A different message, not the registered bank wording.';
    await tester.pumpWidget(_app(const Center(
      child: AudioButton(
        id: 'q_newborn.feed',
        text: original,
        language: 'Dagbani',
        compact: true,
      ),
    )));
    await tester.tap(find.byType(AudioButton));
    await tester.pumpAndSettle();
    expect(find.byType(ChoiceChip), findsNWidgets(4));
    expect(find.text(original), findsOneWidget);
    expect(find.text(SpeechBank.qNewbornFeed.english), findsNothing);
    expect(find.textContaining('No Dagbani translation'), findsOneWidget);
    await _tapVisible(tester, find.text('Cancel'));
    expect(find.byIcon(Icons.stop_rounded), findsNothing);

    await tester.longPress(find.byType(AudioButton));
    await tester.pumpAndSettle();
    expect(find.byType(ChoiceChip), findsNWidgets(4));
    expect(find.text(original), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(ChoiceChip), findsNothing);
    expect(tester.takeException(), isNull); // No platform audio call on preview.
  });

  testWidgets('caregiver cancellation and barrier dismissal never play audio', (tester) async {
    final backend = _RecordingVoice();
    final container = _container(() => backend);
    addTearDown(container.dispose);
    await tester.pumpWidget(_listenApp(container, CaregiverListen(speech: _bankSpeech())));
    await _tapVisible(tester, find.byTooltip('Choose speech language'));
    await _tapVisible(tester, _choice('Twi'));
    await _tapVisible(tester, find.text('Cancel'));
    expect(backend.requests, isEmpty);
    expect(container.read(currentUserProvider)!.preferredLanguage, 'Dagbani');
    await _tapVisible(tester, find.byTooltip('Choose speech language'));
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(backend.requests, isEmpty);
    expect(find.text('Selected: Dagbani'), findsOneWidget);
  });

  testWidgets('caregiver shows chosen language, real phases and no reduced-motion ticker', (tester) async {
    final backend = _RecordingVoice();
    final container = _container(() => backend);
    addTearDown(container.dispose);
    await tester.pumpWidget(_listenApp(container, CaregiverListen(speech: _bankSpeech())));
    expect(backend.requests, isEmpty);
    await _tapVisible(tester, find.byTooltip('Choose speech language'));
    await _tapVisible(tester, _choice('Hausa'));
    await _tapVisible(tester, find.text('Listen in Hausa'));
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
    expect(find.textContaining('Hausa • Bundled synthetic voice'), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
    backend.emit(0, CaregiverPlaybackPhase.completed);
    await tester.pumpAndSettle();
    expect(find.text('Playback complete'), findsOneWidget);
    expect(find.byTooltip('Stop audio'), findsNothing);
    await _tapVisible(tester, find.byTooltip('Choose speech language'));
    expect(tester.widget<ChoiceChip>(_choice('Dagbani')).selected, isTrue);
    await _tapVisible(tester, find.text('Cancel'));
  });

  testWidgets('loading can be stopped and stale playback events stay stopped', (tester) async {
    final backend = _RecordingVoice();
    final container = _container(() => backend);
    addTearDown(container.dispose);
    await tester.pumpWidget(_listenApp(container, CaregiverListen(speech: _bankSpeech())));
    await _tapVisible(tester, find.byTooltip('Choose speech language'));
    await _tapVisible(tester, find.text('Listen in Dagbani'));
    expect(find.text('Loading'), findsOneWidget);
    await _tapVisible(tester, find.byTooltip('Stop audio'));
    expect(backend.stops, 1);
    expect(find.text('Stopped'), findsOneWidget);
    backend.emit(0, CaregiverPlaybackPhase.playing);
    await tester.pumpAndSettle();
    expect(find.text('Stopped'), findsOneWidget);
    expect(find.text('Playing'), findsNothing);
  });

  testWidgets('failed playback keeps translated text and an honest fallback label', (tester) async {
    final backend = _RecordingVoice()..fail = true;
    final container = _container(() => backend);
    addTearDown(container.dispose);
    await tester.pumpWidget(_listenApp(container, CaregiverListen(speech: _bankSpeech())));
    await _tapVisible(tester, find.byTooltip('Choose speech language'));
    await _tapVisible(tester, find.text('Listen in Dagbani'));
    expect(find.text('Audio unavailable'), findsOneWidget);
    expect(find.text('Dagbani transcript'), findsOneWidget);
    expect(find.textContaining('Dagbani offline audio unavailable'), findsOneWidget);
    expect(find.text(SpeechBank.qNewbornFeed.dagbani), findsOneWidget);
    expect(find.text('Playing'), findsNothing);
  });

  for (final change in ['text', 'language', 'clips']) {
    testWidgets('same-id $change change invalidates an open picker', (tester) async {
      final backend = _RecordingVoice();
      final container = _container(() => backend);
      addTearDown(container.dispose);
      final speech = ValueNotifier(_bankSpeech());
      addTearDown(speech.dispose);
      await tester.pumpWidget(_listenApp(container, ValueListenableBuilder<CaregiverSpeech>(
        valueListenable: speech,
        builder: (context, value, _) => CaregiverListen(speech: value),
      )));
      await _tapVisible(tester, find.byTooltip('Choose speech language'));
      speech.value = CaregiverSpeech(
        id: 'message',
        english: change == 'text' ? 'Updated original message.' : speech.value.english,
        language: change == 'language' ? 'Twi' : 'Dagbani',
        clipId: speech.value.clipId,
        clipIds: change == 'clips' ? [SpeechBank.qNewbornFast.id] : null,
      );
      await tester.pump();
      await _tapVisible(tester, find.text('Listen in Dagbani'));
      expect(backend.requests, isEmpty);
      expect(find.text('Loading'), findsNothing);
    });
  }

  testWidgets('same-id message replacement stops old playback and hides stale transcript', (tester) async {
    final backend = _RecordingVoice();
    final container = _container(() => backend);
    addTearDown(container.dispose);
    final speech = ValueNotifier(_bankSpeech());
    addTearDown(speech.dispose);
    await tester.pumpWidget(_listenApp(container, ValueListenableBuilder<CaregiverSpeech>(
      valueListenable: speech,
      builder: (context, value, _) => CaregiverListen(speech: value),
    )));
    await _tapVisible(tester, find.byTooltip('Choose speech language'));
    await _tapVisible(tester, find.text('Listen in Dagbani'));
    speech.value = const CaregiverSpeech(id: 'message', english: 'Updated original message.', language: 'Dagbani');
    await tester.pumpAndSettle();
    expect(backend.stops, 1);
    backend.emit(0, CaregiverPlaybackPhase.playing);
    await tester.pumpAndSettle();
    expect(find.text(SpeechBank.qNewbornFeed.dagbani), findsNothing);
    expect(find.text('Updated original message.'), findsOneWidget);
    expect(find.text('Playing'), findsNothing);
  });

  testWidgets('account switch away and back rejects an old dialog result', (tester) async {
    final backends = <_RecordingVoice>[];
    final container = _container(() {
      final backend = _RecordingVoice();
      backends.add(backend);
      return backend;
    });
    addTearDown(container.dispose);
    await tester.pumpWidget(_listenApp(container, CaregiverListen(speech: _bankSpeech())));
    await _tapVisible(tester, find.byTooltip('Choose speech language'));
    container.read(_accountProvider.notifier).state = null;
    await tester.pump();
    container.read(_accountProvider.notifier).state = _user;
    await tester.pump();
    await _tapVisible(tester, find.text('Listen in Dagbani'));
    expect(backends.expand((backend) => backend.requests), isEmpty);
    expect(find.text('Loading'), findsNothing);
    expect(find.text('Playing'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
