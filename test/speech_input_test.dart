import 'dart:convert';
import 'dart:typed_data';

import 'package:carebridge_ai/core/audio/speech_answers.dart';
import 'package:carebridge_ai/core/audio/speech_input_service.dart';
import 'package:carebridge_ai/core/audio/speech_match.dart';
import 'package:carebridge_ai/core/audio/voice_activity.dart';
import 'package:carebridge_ai/core/ml/asr_contract.dart';
import 'package:carebridge_ai/core/ml/asr_decoder.dart';
import 'package:carebridge_ai/core/ml/asr_features.dart';
import 'package:carebridge_ai/core/ml/asr_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// A microphone that replays a scripted take, so the decision layer can be
/// argued about without a room, a device or a model.
class _Gate implements AudioGate {
  _Gate({this.granted = true, this.result});
  final bool granted;
  final SpeechTake? result;
  int takes = 0;
  bool cancelled = false;

  @override
  Future<bool> hasMicrophone() async => granted;

  @override
  Future<SpeechTake> take(
    SpeechCapturePolicy policy, {
    Future<void> Function(double)? onLevel,
  }) async {
    takes++;
    return result ?? SpeechTake(pcm: Float32List(0), end: SpeechEnd.silent);
  }

  @override
  void cancel() => cancelled = true;

  @override
  Future<void> dispose() async {}
}

class _Listener implements SpeechListener {
  _Listener(this.hearing, {this.ready = true});
  final AsrHearing hearing;
  final bool ready;
  Map<String, List<String>>? asked;

  @override
  bool isReady(String language) => ready;

  @override
  Future<AsrHearing> hear(
    Float32List pcm, {
    required String language,
    required Map<String, List<String>> candidates,
  }) async {
    asked = candidates;
    return hearing;
  }
}

String _config({Map<String, Object?>? audio, Map<String, Object?>? model}) {
  return jsonEncode({
    'language': {'code': 'dag'},
    'audio': {
      'sample_rate': 16000,
      'features': 'seamless-fbank',
      'frame_length': 400,
      'hop_length': 160,
      'fft_length': 512,
      'mel_bins': 80,
      'input_dim': 160,
      'stride': 2,
      'power': 2.0,
      'preemphasis': 0.97,
      'remove_dc_offset': true,
      'mel_floor': 1.192092955078125e-07,
      'log': 'log',
      'per_band_normalize': {
        'mode': 'zero-mean-unit-variance',
        'epsilon': 1e-7,
        'ddof': 1,
      },
      'pad_with': 1,
      'frames_per_second': 49.1667,
      'max_frames': 400,
      ...?audio,
    },
    'model': {
      'inputs': ['input_features', 'attention_mask'],
      'labels': _labels,
      'num_labels': _labels.length,
      'blank_index': 0,
      ...?model,
    },
  });
}

const _labels = ['<blank>', 'e', 'i', 'ɛ', 'a', 'y', 'm', 'b', 'ŋ', 'Ɛ'];

/// An identity mel bank and a flat window: enough to exercise the geometry and
/// the normalisation without a second copy of the pack's tables. The feature
/// equality itself is proved against the real tables, in
/// `asr_frontend_fixture_test.dart`.
AsrFrontend _frontend(AsrModelSpec spec) {
  final g = spec.fbank!;
  return AsrFrontend.mel(
    spec: spec,
    filters: [
      for (var b = 0; b < g.frequencyBins; b++)
        for (var m = 0; m < g.melBins; m++) if (b == m) 1.0 else 0.0,
    ],
    window: List.filled(g.frameLength, 1.0),
  );
}

/// `frames x labels`, one-hot on [path] with everything else at [floor].
List<Float32List> _frames(List<int> path, int labels, {double floor = 0.001}) {
  return [
    for (final token in path)
      Float32List.fromList([
        for (var l = 0; l < labels; l++)
          l == token ? 1 - floor : floor / labels,
      ]),
  ];
}

void main() {
  group('asr-v1 contract', () {
    test('reads a pack that agrees with the app frontend', () {
      final spec = AsrModelSpec.fromJson(_config());
      expect(spec.sampleRate, 16000);
      expect(spec.fbank!.melBins, 80);
      expect(spec.inputDim, 160);
      expect(spec.framesPerSecond, closeTo(49.1667, 1e-4));
      // 4 s of audio: 1 + (64000 - 400) ~/ 160 = 398 analysis frames, and two
      // of them per encoder step.
      expect(spec.fbank!.melFrames(4 * 16000), 398);
      expect(spec.framesFor(4 * 16000), 199);
      expect(spec.labelIndex('ɛ'), 3);
      expect(
        () => spec.validateInputs(['input_values']),
        throwsFormatException,
      );
      spec.validateInputs(['input_features', 'attention_mask']);
    });

    test('refuses a pack whose frame geometry cannot be produced', () {
      expect(
        () => AsrModelSpec.fromJson(_config(audio: {'hop_length': 480})),
        throwsFormatException,
      );
      // The transform runs in Dart, so a non-power-of-two buffer is not a
      // rounding question, it is a frontend the app does not have.
      expect(
        () => AsrModelSpec.fromJson(_config(audio: {'fft_length': 400})),
        throwsFormatException,
      );
      expect(
        () => AsrModelSpec.fromJson(_config(audio: {'input_dim': 80})),
        throwsFormatException,
      );
      // A measured frame rate that contradicts the framing is a pack whose
      // tables came from a different recipe.
      expect(
        () => AsrModelSpec.fromJson(_config(audio: {'frames_per_second': 25})),
        throwsFormatException,
      );
    });

    test('refuses a frontend the app does not implement', () {
      expect(
        () =>
            AsrModelSpec.fromJson(_config(audio: {'features': 'raw-waveform'})),
        throwsFormatException,
      );
      // `Wav2Vec2ForCTC` (the Akan pack) asks for the raw normalised waveform.
      expect(
        () => AsrModelSpec.fromJson(_config(audio: {'log': 'dB'})),
        throwsFormatException,
      );
      expect(
        () => AsrModelSpec.fromJson(
          _config(
            audio: {
              'per_band_normalize': {
                'mode': 'zero-mean-unit-variance',
                'epsilon': 1e-7,
                'ddof': 2,
              },
            },
          ),
        ),
        throwsFormatException,
      );
    });

    test('refuses an input the app cannot feed', () {
      expect(
        () => AsrModelSpec.fromJson(
          _config(
            model: {
              'inputs': ['input_values'],
            },
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => AsrModelSpec.fromJson(
          _config(
            model: {
              'inputs': ['labels'],
            },
          ),
        ),
        throwsFormatException,
      );
    });

    test('refuses a blank index outside the label inventory', () {
      expect(
        () => AsrModelSpec.fromJson(_config(model: {'blank_index': 42})),
        throwsFormatException,
      );
    });
  });

  group('seamless-fbank frontend', () {
    final spec = AsrModelSpec.fromJson(_config());

    test('turns seconds into the frame count the encoder expects', () {
      // 1 s at a 160-sample hop with a 400-sample window: 98 analysis frames of
      // 80 mel bands, stacked to 49 of 160.
      expect(spec.fbank!.melFrames(16000), 98);
      final features = _frontend(spec).process(Float32List(16000));
      expect(features.length ~/ spec.inputDim, spec.framesFor(16000));
      expect(spec.framesFor(16000), 49);
    });

    test('stays finite on digital silence', () {
      // Silence floors every band to the same number, so the variance is zero
      // and the epsilon is what keeps the division finite.
      final features = _frontend(spec).process(Float32List(4000));
      expect(features.every((v) => v.isFinite), isTrue);
    });

    test('refuses a mel bank that is not the shape the contract claims', () {
      final g = spec.fbank!;
      expect(
        () => AsrFrontend.mel(
          spec: spec,
          filters: List.filled(g.melBins * g.melBins, 1.0),
          window: List.filled(g.frameLength, 1.0),
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('CTC decoding', () {
    test('ranks the emitted answer first and calls it certain', () {
      final decoder = CtcDecoder(_spec());
      final heard = decoder.restricted(_frames([1, 5, 0], 10), {
        'yes': [[1, 5]],
        'no': [[4, 4]],
      });
      expect(heard.first.id, 'yes');
      expect(heard.first.posterior, greaterThan(0.99));
    });

    test('an all-blank take separates no answers at all', () {
      final decoder = CtcDecoder(_spec());
      final heard = decoder.restricted(_frames([0, 0, 0, 0], 10), {
        'yes': [[1, 5]],
        'no': [[4, 4]],
        'unsure': [[2, 9]],
      });
      // Not exactly a third each: with the blank-skip rule a two-label answer is
      // cheaper to assert than a repeated letter, so silence nudges the ranking.
      // What matters is that no answer is singled out, and that the absolute
      // measure — not the ranking — is what lets the app refuse.
      expect(heard.first.posterior, lessThan(0.6));
      expect(heard.first.perFrame, lessThan(-3));
    });

    test('a doubled letter needs the blank between the two frames', () {
      final decoder = CtcDecoder(_spec());
      final candidates = {
        'aa': [[4, 4]],
        'a': [[4]],
      };
      final held = decoder.restricted(_frames([4, 0, 4, 0], 10), candidates);
      final runOn = decoder.restricted(_frames([4, 4, 0], 10), candidates);
      expect(held.first.id, 'aa');
      expect(runOn.first.id, 'a');
    });

    test('greedy collapses repeats and reads word pieces as words', () {
      final decoder = CtcDecoder(_spec(extra: ['▁mi', 'bɛ']));
      final reading = decoder.greedy(_frames([1, 1, 0, 1, 10, 0, 11], 12));
      expect(reading.text, 'ee mibɛ');
    });

    test('the CTC word boundary becomes a space, not a bar in the note', () {
      // Both Ghanaian packs carry `|` as the boundary token the model was
      // trained to emit between words. It is not a letter of either orthography,
      // so printing it would put punctuation into a caregiver's free text.
      final decoder = CtcDecoder(_spec(extra: ['|']));
      expect(decoder.greedy(_frames([1, 10, 4, 0, 1], 11)).text, 'e ae');
      expect(decoder.greedy(_frames([10, 1, 4, 10], 11)).text, 'ea');
    });

    test('a second spoken form is the same answer', () {
      // The take emits `i ɛ` and then blank: that is the second way this answer
      // is said, and the first way (`e y`) is nowhere in the audio. Scoring only
      // the first form handed the clip to whichever answer did match, which is a
      // wrong clinical proposal rather than a refusal.
      final decoder = CtcDecoder(_spec());
      final frames = _frames([2, 3, 0], 10);
      final firstFormOnly = decoder.restricted(frames, {
        'yes': [[1, 5]],
        'no': [[3]],
      });
      final everyForm = decoder.restricted(frames, {
        'yes': [[1, 5], [2, 3]],
        'no': [[3]],
      });
      expect(firstFormOnly.first.id, 'no');
      expect(everyForm.first.id, 'yes');
      expect(
        everyForm.first.logLikelihood,
        greaterThan(firstFormOnly.first.logLikelihood),
      );
    });

    test('the empty transcription is scored, not skipped', () {
      final decoder = CtcDecoder(_spec());
      final heard = decoder.restricted(_frames([0, 0, 0], 10), {
        'none': [[]],
      });
      expect(heard.single.posterior, 1);
    });
  });

  group('closed-set matching', () {
    const dagbani = SpeechAnswerSet(
      language: 'Dagbani',
      answers: [
        SpeechAnswer(answer: 'yes', utterances: ['Ee'], verified: true),
        SpeechAnswer(answer: 'no', utterances: ['Ayi'], verified: true),
        SpeechAnswer(
          answer: 'unsure',
          utterances: ['Mi bɛ mi'],
          verified: true,
        ),
      ],
    );

    test('exact, contained and near-miss all resolve to one answer', () {
      expect(matchSpeech('Ee', dagbani)?.answer, 'yes');
      expect(matchSpeech('Ee.', dagbani)?.answer, 'yes');
      expect(matchSpeech(' ee ', dagbani)?.strength, MatchStrength.exact);
      expect(matchSpeech('Ee la', dagbani)?.strength, MatchStrength.contained);
      // One edit from Ayi and two from Ee: the near miss lands on the closer
      // answer, which is the whole point of scoring distance rather than hope.
      expect(matchSpeech('eyi', dagbani)?.answer, 'no');
      // 'Ee' is two letters long, so it tolerates no near miss at all: at that
      // length an edit distance of 1 reaches half the language.
      expect(matchSpeech('eea', dagbani), isNull);
      expect(matchSpeech('mi bɛ mi', dagbani)?.answer, 'unsure');
    });

    test('a contradiction between two answers is no answer', () {
      // 'Ayi' and 'Ee' both readable from one transcript: refuse the coin toss.
      expect(matchSpeech('ee ayi', dagbani), isNull);
    });

    test('ɛ is never folded to e', () {
      // Folding them would make two different words one hearing.
      expect(matchSpeech('ɛ', dagbani), isNull);
    });

    test('equally far from two answers, it is neither', () {
      const tied = SpeechAnswerSet(
        language: 'Dagbani',
        answers: [
          SpeechAnswer(answer: 'yes', utterances: ['abe'], verified: true),
          SpeechAnswer(answer: 'no', utterances: ['abf'], verified: true),
        ],
      );
      // 'abc' is one edit from both. A tie is a refusal, not a coin toss.
      expect(matchSpeech('abc', tied), isNull);
      expect(matchSpeech('abe', tied)?.answer, 'yes');
    });

    test('nothing outside the set becomes an answer', () {
      expect(matchSpeech('tuma zɔ', dagbani), isNull);
      expect(matchSpeech('', dagbani), isNull);
    });
  });

  group('endpointing', () {
    const policy = SpeechCapturePolicy(
      frameMs: 20,
      silenceLimitMs: 200,
      minSpeechMs: 40,
      trailingSilenceMs: 60,
      maxSpeechMs: 200,
    );

    test('gives up before anything is said', () {
      final tracker = VoiceTracker(policy);
      SpeechEnd? end;
      for (var i = 0; i < 20 && end == null; i++) {
        end = tracker.feed(0.001);
      }
      expect(end, SpeechEnd.silent);
    });

    test('closes on a word after a short silence', () {
      final tracker = VoiceTracker(policy);
      for (var i = 0; i < 5; i++) {
        expect(tracker.feed(0.4), isNull);
      }
      SpeechEnd? end;
      for (var i = 0; i < 5 && end == null; i++) {
        end = tracker.feed(0.001);
      }
      expect(end, SpeechEnd.spoke);
    });

    test('a sound shorter than any word is too short', () {
      final tracker = VoiceTracker(policy);
      expect(tracker.feed(0.4), isNull);
      SpeechEnd? end;
      for (var i = 0; i < 5 && end == null; i++) {
        end = tracker.feed(0.001);
      }
      expect(end, SpeechEnd.tooShort);
    });

    test('stops a ramble at the ceiling', () {
      final tracker = VoiceTracker(policy);
      SpeechEnd? end;
      for (var i = 0; i < 40 && end == null; i++) {
        end = tracker.feed(0.4);
      }
      expect(end, SpeechEnd.limit);
    });
  });

  group('listening policy', () {
    const set = SpeechAnswerSet(
      language: 'Dagbani',
      answers: [
        SpeechAnswer(answer: 'yes', utterances: ['Ee'], verified: true),
        SpeechAnswer(answer: 'no', utterances: ['Ayi'], verified: true),
      ],
    );
    final pcm = Float32List.fromList([0.1, 0.2, 0.3]);

    SpeechInputService service({
      bool granted = true,
      bool ready = true,
      required AsrHearing hearing,
      SpeechCapturePolicy policy = const SpeechCapturePolicy(),
    }) => SpeechInputService(
      gate: _Gate(
        granted: granted,
        result: SpeechTake(pcm: pcm, end: SpeechEnd.spoke),
      ),
      listener: _Listener(hearing, ready: ready),
      policy: policy,
    );

    AsrHearing certain(String answer, {String reading = 'Ee'}) => AsrHearing(
      scores: [
        CandidateScore(
          id: answer,
          logLikelihood: -10,
          perFrame: -1,
          posterior: 0.97,
        ),
      ],
      reading: AsrReading(text: reading, meanFrameProbability: 0.9),
    );

    test('a confident, uncontradicted hearing names the answer', () async {
      final reply = await service(
        hearing: certain('yes'),
      ).listen(language: 'Dagbani', set: set);
      expect(reply, isA<SpeechHeard>());
      expect((reply as SpeechHeard).answer, 'yes');
      expect(reply.utterance, 'Ee');
      expect(reply.verified, isTrue);
    });

    test(
      'the closed set is asked in the app language, with every spoken form',
      () async {
        final listener = _Listener(certain('yes'));
        await SpeechInputService(
          gate: _Gate(
            result: SpeechTake(pcm: pcm, end: SpeechEnd.spoke),
          ),
          listener: listener,
        ).listen(language: 'Dagbani', set: set);
        expect(listener.asked?.keys, containsAll(['yes', 'no']));
        expect(listener.asked?['yes'], ['Ee']);
      },
    );

    test('a low ranking is unclear, never a guess', () async {
      final reply = await service(
        hearing: AsrHearing(
          scores: [
            CandidateScore(
              id: 'yes',
              logLikelihood: -60,
              perFrame: -6,
              posterior: 0.51,
            ),
          ],
          reading: AsrReading(text: '', meanFrameProbability: 0.2),
        ),
      ).listen(language: 'Dagbani', set: set);
      expect(reply, isA<SpeechUnclear>());
    });

    test(
      'a confident closed set contradicted by the free reading is unclear',
      () async {
        final reply = await service(
          hearing: certain('yes', reading: 'Ayi'),
        ).listen(language: 'Dagbani', set: set);
        expect(reply, isA<SpeechUnclear>());
      },
    );

    test('silence is reported as silence', () async {
      final reply = await SpeechInputService(
        gate: _Gate(
          result: SpeechTake(pcm: pcm, end: SpeechEnd.silent),
        ),
        listener: _Listener(certain('yes')),
      ).listen(language: 'Dagbani', set: set);
      expect(reply, isA<SpeechSilent>());
    });

    test('a refused microphone never reaches the model', () async {
      final listener = _Listener(certain('yes'));
      final reply = await SpeechInputService(
        gate: _Gate(
          granted: false,
          result: SpeechTake(pcm: pcm, end: SpeechEnd.spoke),
        ),
        listener: listener,
      ).listen(language: 'Dagbani', set: set);
      expect((reply as SpeechRefused).reason, SpeechRefusal.microphoneMissing);
      expect(listener.asked, isNull);
    });

    test('no pack means no listening', () async {
      final reply = await service(
        ready: false,
        hearing: certain('yes'),
      ).listen(language: 'Dagbani', set: set);
      expect((reply as SpeechRefused).reason, SpeechRefusal.packMissing);
    });

    test('an answer set from another language is not listened to', () async {
      final reply = await service(
        hearing: certain('yes'),
      ).listen(language: 'Twi', set: set);
      expect(
        (reply as SpeechRefused).reason,
        SpeechRefusal.unsupportedLanguage,
      );
    });

    test('dictation hands back words for a human to edit', () async {
      final reply = await service(
        hearing: AsrHearing(
          scores: const [],
          reading: AsrReading(
            text: 'the baby feeds well',
            meanFrameProbability: 0.93,
          ),
        ),
      ).dictate(language: 'Twi');
      expect((reply as SpeechTranscript).text, 'the baby feeds well');
    });

    test('dictation refuses a quiet room', () async {
      final reply = await service(
        hearing: AsrHearing(
          scores: const [],
          reading: AsrReading(text: '', meanFrameProbability: 0.1),
        ),
      ).dictate(language: 'Twi');
      expect(reply, isA<SpeechUnclear>());
    });

    test('the Dagbani floor is the measured one, Twi stays conservative', () {
      // −2.5 sits between `Ayi`/`Ee` (−1.67, −1.74) and the best of 33 narration
      // sentences (−2.73) on that pack. Twi has no such gap, so it keeps the
      // default and `SpeechConfidence.forLanguage` says why.
      expect(SpeechConfidence.forLanguage('Dagbani').perFrameFloor, -2.5);
      expect(SpeechConfidence.forLanguage('Twi').perFrameFloor, -3.0);
      expect(SpeechConfidence.forLanguage('Hausa').perFrameFloor, -3.0);
      for (final language in ['Twi', 'Dagbani']) {
        expect(SpeechConfidence.forLanguage(language).posteriorFloor, 0.85);
      }
    });

    test('the floor separates a spoken answer from prose on that pack', () async {
      SpeechInputService serviceAt(double perFrame) => service(
        hearing: AsrHearing(
          scores: [
            CandidateScore(
              id: 'no',
              logLikelihood: perFrame * 30,
              perFrame: perFrame,
              posterior: 0.99,
            ),
            const CandidateScore(
              id: 'yes',
              logLikelihood: -100,
              perFrame: -8,
              posterior: 0.01,
            ),
          ],
          reading: AsrReading(text: 'ayi', meanFrameProbability: 0.99),
        ),
      );
      final answer = await serviceAt(-1.67).listen(
        language: 'Dagbani',
        set: SpeechAnswerSet.forLanguage('Dagbani')!,
      );
      expect(answer, isA<SpeechHeard>());
      final prose = await serviceAt(-2.73).listen(
        language: 'Dagbani',
        set: SpeechAnswerSet.forLanguage('Dagbani')!,
      );
      expect(prose, isA<SpeechUnclear>());
    });

    test('dictation is offered only where it was measured', () async {
      // Held-out CER decides, not pack availability: Dagbani's DONDO measured
      // 0.42 median character error, so its pack may answer a closed set but
      // must not transcribe a sentence.
      expect(service(hearing: certain('yes')).dictates('Twi'), isTrue);
      expect(service(hearing: certain('yes')).dictates('Dagbani'), isFalse);
      final reply = await service(
        hearing: AsrHearing(
          scores: const [],
          reading: AsrReading(
            text: 'mi bɛ mi',
            meanFrameProbability: 0.93,
          ),
        ),
      ).dictate(language: 'Dagbani');
      expect((reply as SpeechRefused).reason, SpeechRefusal.dictationUnproven);
    });

    test('one microphone at a time', () async {
      final gate = _Gate(
        result: SpeechTake(pcm: pcm, end: SpeechEnd.spoke),
      );
      final subject = SpeechInputService(
        gate: gate,
        listener: _Listener(certain('yes')),
      );
      final first = subject.listen(language: 'Dagbani', set: set);
      expect(
        (await subject.listen(language: 'Dagbani', set: set)),
        isA<SpeechRefused>(),
      );
      await first;
    });

    test('cancelling a take is a result, not a hang', () async {
      final gate = _Gate(
        result: SpeechTake(pcm: pcm, end: SpeechEnd.cancelled),
      );
      final reply = await SpeechInputService(
        gate: gate,
        listener: _Listener(certain('yes')),
      ).listen(language: 'Dagbani', set: set);
      expect(reply, isA<SpeechCancelled>());
      expect(gate.cancelled, isFalse);
    });
  });

  group('answer sets', () {
    test('Dagbani and Twi are offered, Hausa is not', () {
      expect(SpeechAnswerSet.forLanguage('Dagbani')?.answers.length, 3);
      expect(SpeechAnswerSet.forLanguage('Twi')?.answers.length, 3);
      expect(SpeechAnswerSet.forLanguage('Hausa'), isNull);
      expect(SpeechAnswerSet.forLanguage('English'), isNull);
    });

    test('nothing is signed off yet, and the app says so', () {
      // The forms are authored, not verified by a native ear. An unverified set
      // may only ever propose, and that must stay true until the sign-off.
      for (final language in ['Dagbani', 'Twi']) {
        expect(
          SpeechAnswerSet.forLanguage(language)!.isVerified,
          isFalse,
          reason: language,
        );
      }
    });

    test('one unverified form makes the whole set unverified', () {
      const set = SpeechAnswerSet(
        language: 'Dagbani',
        answers: [
          SpeechAnswer(answer: 'yes', utterances: ['Ee'], verified: true),
          SpeechAnswer(answer: 'no', utterances: ['Ayi'], verified: false),
        ],
      );
      expect(set.isVerified, isFalse);
    });
  });

  group('pack spelling', () {
    test('an answer the pack cannot pronounce is not offered', () {
      final engine = AsrEngine(
        spec: _spec(),
        frontend: _frontend(_spec()),
        decoder: CtcDecoder(_spec()),
        encode: (_, _) async => const [],
      );
      final heard = engine.heardAnswers({
        'yes': ['Ee'],
        'no': ['Ayi'],
        'unsure': ['Mi bɛ mi'],
        'bleeding': ['Suŋa'],
      });
      // 'u' and 'g' are absent from this label inventory.
      expect(heard, containsAll(<String>['yes', 'no', 'unsure']));
      expect(heard, isNot(contains('bleeding')));
    });
  });

  group('hearing a take', () {
    AsrEngine engine(void Function(int frames) fed) {
      final spec = _spec();
      return AsrEngine(
        spec: spec,
        frontend: _frontend(spec),
        decoder: CtcDecoder(spec),
        encode: (features, frames) async {
          fed(frames);
          return _frames([1, 0, 1, 0], spec.labels.length);
        },
      );
    }

    test('one take feeds one encoder pass and both decodings', () async {
      var fedFrames = 0;
      final heard = await engine((frames) => fedFrames = frames).hear(
        Float32List(16000),
        {
          'yes': ['Ee'],
          'no': ['Ayi'],
        },
      );
      // 1 s of audio: 98 analysis frames of 400 at a 160 hop, two per step.
      expect(fedFrames, 49);
      expect(heard.scores.first.id, 'yes');
      expect(heard.reading.text, 'ee');
    });

    test('a take shorter than one analysis window is refused', () async {
      var fedFrames = 0;
      await expectLater(
        engine((frames) => fedFrames = frames).hear(Float32List(200), {
          'yes': ['Ee'],
        }),
        throwsFormatException,
      );
      expect(fedFrames, 0);
    });
  });
}

AsrModelSpec _spec({List<String> extra = const []}) => AsrModelSpec.fromJson(
  _config(
    model: {
      'labels': [..._labels, ...extra],
      'num_labels': _labels.length + extra.length,
    },
  ),
);
