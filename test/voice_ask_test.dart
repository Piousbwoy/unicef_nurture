import 'dart:async';
import 'dart:typed_data';

import 'package:carebridge_ai/app/providers.dart';
import 'package:carebridge_ai/core/audio/speech_answers.dart';
import 'package:carebridge_ai/core/audio/speech_input_service.dart';
import 'package:carebridge_ai/core/audio/voice_activity.dart';
import 'package:carebridge_ai/core/ml/asr_decoder.dart';
import 'package:carebridge_ai/core/ml/asr_service.dart';
import 'package:carebridge_ai/presentation/shared/voice_ask.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Gate implements AudioGate {
  _Gate(this.result, {this.block});
  final SpeechTake result;
  final Completer<void>? block;
  bool granted = true;

  @override
  Future<bool> hasMicrophone() async => granted;

  @override
  Future<SpeechTake> take(
    SpeechCapturePolicy policy, {
    Future<void> Function(double)? onLevel,
  }) async {
    await block?.future;
    return result;
  }

  @override
  void cancel() {}

  @override
  Future<void> dispose() async {}
}

class _Listener implements SpeechListener {
  _Listener(this.hearing, {this.ready = true});
  final AsrHearing hearing;
  final bool ready;

  @override
  bool isReady(String language) => ready;

  @override
  Future<AsrHearing> hear(
    Float32List pcm, {
    required String language,
    required Map<String, List<String>> candidates,
  }) async => hearing;
}

AsrHearing _certain(String answer, {double posterior = 0.97}) => AsrHearing(
  scores: [
    CandidateScore(
      id: answer,
      logLikelihood: -8,
      perFrame: -1.2,
      posterior: posterior,
    ),
  ],
  reading: AsrReading(text: 'Ee', meanFrameProbability: 0.9),
);

Future<void> _mount(
  WidgetTester tester, {
  required AudioGate gate,
  required SpeechListener listener,
  ValueChanged<String>? onConfirmed,
  SpeechAnswerSet? set,
  String language = 'Dagbani',
}) async {
  final recorded = <String>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        speechInputProvider.overrideWithValue(
          SpeechInputService(gate: gate, listener: listener),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: VoiceAsk(
            language: language,
            set: set ?? SpeechAnswerSet.forLanguage('Dagbani')!,
            onConfirmed: onConfirmed ?? recorded.add,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// A service whose recogniser always "hears" [text], so a dictation test can
/// check what a screen does with a transcript without owning an encoder.
SpeechInputService _dictation(String text) => SpeechInputService(
  gate: _Gate(
    SpeechTake(pcm: Float32List.fromList([0.1]), end: SpeechEnd.spoke),
  ),
  listener: _Listener(
    AsrHearing(
      scores: const [],
      reading: AsrReading(text: text, meanFrameProbability: 0.95),
    ),
  ),
);

void main() {
  testWidgets('no speech pack means no microphone on screen', (tester) async {
    await _mount(
      tester,
      gate: _Gate(SpeechTake(pcm: Float32List(0), end: SpeechEnd.spoke)),
      listener: _Listener(_certain('yes'), ready: false),
    );
    expect(find.byKey(const Key('voiceAsk')), findsNothing);
  });

  testWidgets('a hearing proposes, and only the tap records', (tester) async {
    final recorded = <String>[];
    await _mount(
      tester,
      gate: _Gate(
        SpeechTake(pcm: Float32List.fromList([0.1, 0.2]), end: SpeechEnd.spoke),
      ),
      listener: _Listener(_certain('yes')),
      onConfirmed: recorded.add,
    );
    expect(find.text('Answer by voice'), findsOneWidget);

    await tester.tap(find.byKey(const Key('voiceAsk')));
    await tester.pumpAndSettle();

    expect(find.textContaining('“Ee”'), findsOneWidget);
    // The clinical answer is still unwritten: the recogniser has only spoken.
    expect(recorded, isEmpty);

    await tester.tap(find.byKey(const Key('voiceConfirm')));
    await tester.pumpAndSettle();
    expect(recorded, ['yes']);
  });

  testWidgets('an unverified answer set says so on the proposal', (
    tester,
  ) async {
    await _mount(
      tester,
      gate: _Gate(
        SpeechTake(pcm: Float32List.fromList([0.1]), end: SpeechEnd.spoke),
      ),
      listener: _Listener(_certain('yes')),
    );
    await tester.tap(find.byKey(const Key('voiceAsk')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('not yet checked with a speaker'),
      findsOneWidget,
    );
  });

  testWidgets('unclear never pre-selects anything', (tester) async {
    final recorded = <String>[];
    await _mount(
      tester,
      gate: _Gate(
        SpeechTake(pcm: Float32List.fromList([0.1]), end: SpeechEnd.spoke),
      ),
      listener: _Listener(
        AsrHearing(
          scores: [
            const CandidateScore(
              id: 'yes',
              logLikelihood: -80,
              perFrame: -7,
              posterior: 0.52,
            ),
          ],
          reading: AsrReading(text: '', meanFrameProbability: 0.2),
        ),
      ),
      onConfirmed: recorded.add,
    );
    await tester.tap(find.byKey(const Key('voiceAsk')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('voiceConfirm')), findsNothing);
    expect(find.textContaining('not sure what you said'), findsOneWidget);
    expect(recorded, isEmpty);
  });

  testWidgets('silence is said plainly', (tester) async {
    await _mount(
      tester,
      gate: _Gate(SpeechTake(pcm: Float32List(0), end: SpeechEnd.silent)),
      listener: _Listener(_certain('yes')),
    );
    await tester.tap(find.byKey(const Key('voiceAsk')));
    await tester.pumpAndSettle();
    expect(find.textContaining('I heard nothing'), findsOneWidget);
  });

  testWidgets('a refused microphone is named, not retried silently', (
    tester,
  ) async {
    final gate = _Gate(
      SpeechTake(pcm: Float32List.fromList([0.1]), end: SpeechEnd.spoke),
    );
    gate.granted = false;
    await _mount(tester, gate: gate, listener: _Listener(_certain('yes')));
    await tester.tap(find.byKey(const Key('voiceAsk')));
    await tester.pumpAndSettle();
    expect(find.text('Microphone is not allowed'), findsOneWidget);
  });

  testWidgets('listening can be stopped from the same control', (tester) async {
    final block = Completer<void>();
    final gate = _Gate(
      SpeechTake(pcm: Float32List.fromList([0.1]), end: SpeechEnd.cancelled),
      block: block,
    );
    await _mount(tester, gate: gate, listener: _Listener(_certain('yes')));
    await tester.tap(find.byKey(const Key('voiceAsk')));
    await tester.pump();
    expect(find.text('Listening — tap to stop'), findsOneWidget);

    await tester.tap(find.byKey(const Key('voiceAsk')));
    await tester.pump();
    expect(find.text('Answer by voice'), findsOneWidget);
    block.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('the control is a labelled button with a touchable target', (
    tester,
  ) async {
    await _mount(
      tester,
      gate: _Gate(SpeechTake(pcm: Float32List(0), end: SpeechEnd.silent)),
      listener: _Listener(_certain('yes')),
    );
    final labelled = tester.widgetList<Semantics>(
      find.ancestor(
        of: find.byKey(const Key('voiceAsk')),
        matching: find.byType(Semantics),
      ),
    );
    expect(
      labelled.any(
        (s) =>
            s.properties.button == true &&
            (s.properties.label ?? '').contains('Answer by voice'),
      ),
      isTrue,
    );
    expect(
      tester.getSize(find.byType(InkWell)).height,
      greaterThanOrEqualTo(44),
    );
  });

  testWidgets('dictation writes only into the text callback', (tester) async {
    final texts = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          speechInputProvider.overrideWithValue(
            _dictation('swelling on both feet since tuesday'),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: VoiceDictate(language: 'Twi', onText: texts.add),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('voiceDictate')));
    await tester.pumpAndSettle();
    expect(texts, ['swelling on both feet since tuesday']);
  });

  testWidgets('a language that failed the dictation measurement hides the mic',
      (tester) async {
        final texts = <String>[];
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              speechInputProvider.overrideWithValue(_dictation('mi bɛ mi')),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: VoiceDictate(language: 'Dagbani', onText: texts.add),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('voiceDictate')), findsNothing);
        expect(texts, isEmpty);
      });

  testWidgets('Hausa gets no microphone: voice input is Twi and Dagbani only', (
    tester,
  ) async {
    await _mount(
      tester,
      gate: _Gate(SpeechTake(pcm: Float32List(0), end: SpeechEnd.silent)),
      listener: _Listener(_certain('yes')),
      language: 'Hausa',
      set: const SpeechAnswerSet(
        language: 'Hausa',
        answers: [
          SpeechAnswer(answer: 'yes', utterances: ['Na i'], verified: true),
        ],
      ),
    );
    expect(find.byKey(const Key('voiceAsk')), findsNothing);
  });
}
