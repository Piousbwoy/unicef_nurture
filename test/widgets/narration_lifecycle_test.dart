import 'dart:async';
import 'package:carebridge_ai/app/providers.dart';
import 'package:carebridge_ai/core/audio/caregiver_playback.dart';
import 'package:carebridge_ai/core/audio/speakable_service.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:carebridge_ai/presentation/shared/ai_pitch_copilot.dart';
import 'package:carebridge_ai/presentation/shared/speakable_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

AppUser user(String id, [String language = 'Twi']) => AppUser(
  id: id,
  fullName: 'Test',
  phone: '000',
  role: UserRole.caregiver,
  region: 'Northern',
  district: 'Karaga',
  community: 'Karaga',
  preferredLanguage: language,
);
final account = StateProvider<AppUser?>((_) => user('first'));

class Backend implements CaregiverVoiceBackend {
  final requests = <CaregiverSpeech>[];
  final callbacks = <void Function(CaregiverPlayback)>[];
  final pending = <Completer<void>>[];
  var stops = 0;
  var fail = false;
  void emit(int index, CaregiverPlaybackPhase phase) {
    callbacks[index](
      CaregiverPlayback(
        phase: phase,
        transcript: requests[index].english,
        language: requests[index].language,
        source: 'Test offline voice',
      ),
    );
  }

  @override
  Future<void> play(
    CaregiverSpeech speech,
    void Function(CaregiverPlayback) callback,
  ) async {
    if (pending.isNotEmpty && !pending.last.isCompleted) await stop();
    requests.add(speech);
    callbacks.add(callback);
    final done = Completer<void>();
    pending.add(done);
    emit(requests.length - 1, CaregiverPlaybackPhase.loading);
    if (fail) {
      done.complete();
      throw StateError('Unavailable');
    }
    await done.future;
  }

  @override
  Future<void> stop() async {
    stops++;
    for (var i = 0; i < pending.length; i++) {
      if (!pending[i].isCompleted) {
        emit(i, CaregiverPlaybackPhase.stopped);
        pending[i].complete();
      }
    }
  }

  @override
  Future<void> dispose() => stop();
}

void main() {
  late Backend backend;
  late SpeakableService service;
  late ProviderContainer container;
  setUp(() {
    backend = Backend();
    service = SpeakableService(backend: backend);
    container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWith((ref) => ref.watch(account)),
        speakableServiceProvider.overrideWithValue(service),
        narrationPreferenceReaderProvider.overrideWithValue(() async => true),
        narrationPreferenceWriterProvider.overrideWithValue((_) async {}),
      ],
    );
  });
  tearDown(() async {
    await service.dispose();
    container.dispose();
  });
  Widget app(Widget child) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      builder: (context, page) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: page!,
      ),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  NarrationSection section(String text, {bool enabled = true}) =>
      NarrationSection(
        text: text,
        enabled: enabled,
        child: const Text('Content'),
      );
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pumpAndSettle();
  }

  testWidgets(
    'account change with the same language resets automatic narration',
    (tester) async {
      await tester.pumpWidget(app(section('First message.')));
      await settle(tester);
      expect(backend.requests, hasLength(1));
      container.read(account.notifier).state = user('second');
      await settle(tester);
      expect(backend.requests, hasLength(2));
      expect(backend.requests.last.language, 'Twi');
      backend.emit(0, CaregiverPlaybackPhase.playing);
      await settle(tester);
      expect(find.textContaining(' - playing'), findsNothing);
    },
  );

  testWidgets(
    'content, language and enabled changes invalidate old narration',
    (tester) async {
      await tester.pumpWidget(app(section('First message.')));
      await settle(tester);
      await tester.pumpWidget(app(section('Second message.')));
      await settle(tester);
      expect(backend.requests.last.english, 'Second message.');
      container.read(account.notifier).state = user('first', 'Hausa');
      await settle(tester);
      expect(backend.requests.last.language, 'Hausa');
      final count = backend.requests.length;
      await tester.pumpWidget(app(section('Second message.', enabled: false)));
      await settle(tester);
      expect(find.text('Stop reading'), findsNothing);
      await tester.pumpWidget(app(section('Second message.')));
      await settle(tester);
      expect(backend.requests.length, count + 1);
    },
  );

  testWidgets(
    'hidden and background narration stops without stale active feedback',
    (tester) async {
      await tester.pumpWidget(
        app(TickerMode(enabled: false, child: section('Message.'))),
      );
      await settle(tester);
      expect(backend.requests, isEmpty);
      await tester.pumpWidget(
        app(TickerMode(enabled: true, child: section('Message.'))),
      );
      await settle(tester);
      expect(backend.requests, hasLength(1));
      backend.emit(0, CaregiverPlaybackPhase.playing);
      await settle(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(backend.stops, greaterThan(0));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
      expect(find.text('Stop reading'), findsNothing);
      backend.emit(0, CaregiverPlaybackPhase.playing);
      await settle(tester);
      expect(find.text('Stop reading'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    },
  );

  testWidgets('failed narration has explicit retry without a rebuild loop', (
    tester,
  ) async {
    backend.fail = true;
    await tester.pumpWidget(app(section('Message.')));
    await settle(tester);
    expect(backend.requests, hasLength(1));
    expect(find.text('Retry'), findsOneWidget);
    backend.fail = false;
    await tester.tap(find.text('Retry'));
    await settle(tester);
    expect(backend.requests, hasLength(2));
    expect(find.text('Stop reading'), findsOneWidget);
  });

  testWidgets(
    'localized manual text keeps its source language and no English action',
    (tester) async {
      backend.fail = true;
      await tester.pumpWidget(
        app(const SpeakableText('Maakye.', sourceLanguage: 'Twi')),
      );
      await tester.longPress(find.text('Maakye.'));
      await settle(tester);
      expect(backend.requests.single.sourceLanguage, 'Twi');
      expect(find.text('Hear English'), findsNothing);
    },
  );

  testWidgets('pitch shares the service and respects reduced motion', (
    tester,
  ) async {
    await tester.pumpWidget(app(AiPitchCopilotPanel(onClose: () {})));
    await settle(tester);
    expect(backend.requests, hasLength(1));
    expect(backend.requests.single.language, 'Twi');
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(app(const Text('Closed')));
    await settle(tester);
    expect(backend.stops, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  test(
    'superseded observers receive cancellation but never stale completion',
    () async {
      final first = <CaregiverPlaybackPhase>[];
      final second = <CaregiverPlaybackPhase>[];
      final oldOwner = Object();
      final newOwner = Object();
      final old = service.speak(
        'First',
        language: 'Twi',
        owner: oldOwner,
        onPlayback: (event) => first.add(event.phase),
      );
      await Future<void>.delayed(Duration.zero);
      final current = service.speak(
        'Second',
        language: 'Hausa',
        owner: newOwner,
        onPlayback: (event) => second.add(event.phase),
      );
      await Future<void>.delayed(Duration.zero);
      expect(first.last, CaregiverPlaybackPhase.stopped);
      backend.emit(0, CaregiverPlaybackPhase.completed);
      expect(first.last, CaregiverPlaybackPhase.stopped);
      await service.stop(owner: oldOwner);
      expect(second.last, CaregiverPlaybackPhase.loading);
      await service.stop(owner: newOwner);
      expect(second.last, CaregiverPlaybackPhase.stopped);
      expect(await old, isFalse);
      expect(await current, isFalse);
    },
  );
}
