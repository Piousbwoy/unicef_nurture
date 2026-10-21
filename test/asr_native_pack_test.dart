import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:carebridge_ai/core/audio/speech_answers.dart';
import 'package:carebridge_ai/core/audio/speech_input_service.dart';
import 'package:carebridge_ai/core/ml/asr_contract.dart';
import 'package:carebridge_ai/core/ml/asr_decoder.dart';
import 'package:carebridge_ai/core/ml/asr_features.dart';
import 'package:carebridge_ai/core/ml/asr_native_engine.dart';
import 'package:carebridge_ai/core/ml/asr_service.dart';
import 'package:carebridge_ai/core/ml/model_artifact.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

// Requires the platform ONNX shared library, and a pack in the `asr-v1` shape:
// the throwaway graph from `tool/asr_export/make_throwaway_pack.py` (random
// weights, so it hears nothing), or a real export through ASR_PACK. Deliberately
// separate from the mocks, because the inputs a session declares and the rows a
// graph returns are the two things a mock cannot lie about.
void main() {
  const enabled = bool.fromEnvironment('RUN_NATIVE_VOICE');
  // Defaults to the throwaway graph; ASR_PACK points it at a real exported pack
  // (data/asr_dev/dagbani_dondo, data/asr_dev/twi_akan) so one set of assertions
  // covers both frontends.
  final base = Platform.environment['ASR_PACK'] ?? 'data/asr_dev/dagbani_tiny';
  setUpAll(() {
    final library = Platform.environment['ORT_TEST_LIBRARY'];
    if (enabled && library != null) DynamicLibrary.open(library);
  });

  test(
    'the app feeds a real session its features and its mask',
    () async {
      final pack = await SpeechPack.open(base);
      if (pack == null) return;
      addTearDown(pack.dispose);
      // The clip this pack was scored on in Python, from whichever fixture
      // matches its recipe: the two packs do not share a reference, and a
      // frontend measured against the wrong audio proves nothing.
      final clip =
          ((jsonDecode(
                        File(
                          pack.spec.isWaveform
                              ? 'test/fixtures/asr/waveform_fixtures.json'
                              : 'test/fixtures/asr/frontend_fixtures.json',
                        ).readAsStringSync(),
                      )
                      as List)
                  .first)
              as Map<String, dynamic>;
      final pcm = Float32List.fromList(
        (clip['samples'] as List).cast<num>().map((v) => v.toDouble()).toList(),
      );
      final frames = pack.spec.framesFor(pcm.length);
      expect(frames, greaterThan(0));
      final stopwatch = Stopwatch()..start();
      final posteriors = await pack.native.encode(
        pack.frontend.process(pcm),
        frames,
      );
      stopwatch.stop();
      // The rows are the encoder's own and are usually fewer than the frames it
      // was handed: DONDO's adapter halves them, and the Akan convolution
      // frontend takes 320 samples per row, which is why the count has to come
      // from the graph rather than from the input.
      expect(posteriors, isNotEmpty);
      expect(posteriors.length, lessThanOrEqualTo(frames));
      expect(posteriors.first, hasLength(pack.spec.labels.length));
      expect(
        posteriors.every((row) => row.every((value) => value.isFinite)),
        isTrue,
      );
      final heard = await pack.engine.hear(pcm, pack.candidates);
      expect(heard.scores, hasLength(pack.candidates.length));
      expect(heard.scores.first.posterior, inInclusiveRange(0, 1));
      expect(
        heard.scores.fold<double>(0, (sum, score) => sum + score.posterior),
        closeTo(1, 1e-3),
      );
      // ignore: avoid_print
      print(
        'ASR pack $base on "${clip['name']}": $frames frames -> '
        '${posteriors.length} rows x ${pack.spec.labels.length} labels, '
        'encode ${stopwatch.elapsedMilliseconds} ms for '
        '${(pcm.length / pack.spec.sampleRate).toStringAsFixed(2)} s, '
        'greedy "${heard.reading.text}"',
      );
      await pack.dispose();
      await expectLater(pack.native.encode(Float32List(0), 1), throwsStateError);
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 8)),
  );

  test(
    'the pack hears the words a caregiver would actually say',
    () async {
      // Real Dagbani and Twi audio of the clinical answers, scored by the app's
      // own frontend, encoder and CTC decoder, at the floors the measurement
      // produced. `tool/closed_set/make_answer_probe.py` builds the folder: the
      // app's MMS voice saying `Ee`, `Ɛyɛ`, `Nni`…, and 41 narration sentences
      // that answer nothing at all.
      //
      // What this deliberately does not claim: `Ayi`, `Mi bɛ mi`, `Mmo` and
      // `Minnim` are absent because they fail. DONDO scores `Ayi` at −5.2 nats a
      // frame, inside the range of ordinary prose (−5.4), and the Twi model hears
      // `Nnim` (*I don't know*) as `no`. Asserting the words that work and
      // staying quiet about the ones that do not would turn a measurement into
      // an advertisement.
      final pack = await SpeechPack.open(base);
      if (pack == null || !pack.probe.existsSync()) return;
      addTearDown(pack.dispose);
      final floor = SpeechConfidence.forLanguage(pack.language).perFrameFloor;
      final rows = File(p.join(pack.probe.path, 'manifest.csv'))
          .readAsLinesSync()
          .skip(1)
          .map((line) => line.split(','))
          .where((parts) => parts.length >= 2)
          .toList();
      // ASR_PROBE_REPORT=1 prints what every clip scored instead of asserting.
      // The floors have to come from this decoder, not from a Python
      // approximation of it: the two disagreed once the blank-skip rule was
      // fixed, and a floor copied across that difference is a number the app
      // never produced.
      if (Platform.environment['ASR_PROBE_REPORT'] == '1') {
        for (final row in rows) {
          final heard = await pack.engine.hear(
            readWav(pack.clip(row[0])),
            pack.candidates,
          );
          // ignore: avoid_print
          print(
            'PROBE ${pack.language}	${row[1]}	${row[0]}	'
            '${heard.scores.first.id}	'
            '${heard.scores.first.perFrame.toStringAsFixed(2)}	'
            '${heard.scores.first.posterior.toStringAsFixed(3)}	'
            '"${heard.reading.text}"',
          );
        }
        return;
      }
      var asserted = 0;
      for (final row
          in rows.where((parts) => pack.mustHear.contains(parts[0]))) {
        final heard = await pack.engine.hear(
          readWav(pack.clip(row[0])),
          pack.candidates,
        );
        expect(
          heard.scores.first.id,
          row[1],
          reason: '${row[0]} read as "${heard.reading.text}"',
        );
        expect(
          heard.scores.first.perFrame,
          greaterThanOrEqualTo(floor),
          reason: '${row[0]} is audible but under the measured floor',
        );
        asserted++;
      }
      // A renamed or deleted probe clip must fail the test, not shrink it.
      expect(asserted, pack.mustHear.length);
      // Dagbani prose is measurably refused by the floor, so that is asserted
      // where it is true. For Twi it is not: prose and answers overlap on that
      // model, and asserting a refusal there would be theatre.
      if (!pack.spec.isWaveform) {
        for (final row in rows
            .where((parts) => parts[1] == 'none')
            .take(12)) {
          final heard = await pack.engine.hear(
            readWav(pack.clip(row[0])),
            pack.candidates,
          );
          expect(
            heard.scores.first.perFrame,
            lessThan(floor),
            reason: '${row[0]} would be accepted as ${heard.scores.first.id}: '
                '"${heard.reading.text}"',
          );
        }
      }
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

/// One real pack, opened through the classes the app itself uses.
class SpeechPack {
  SpeechPack._(this.spec, this.native, this.frontend, this.engine);

  final AsrModelSpec spec;
  final AsrNativeEngine native;
  final AsrFrontend frontend;
  final AsrEngine engine;

  String get language => spec.isWaveform ? 'Twi' : 'Dagbani';

  Directory get probe =>
      Directory('data/closed_set/probe/${language.toLowerCase()}');

  File clip(String name) => File(p.join(probe.path, name));

  /// The forms the app would offer this pack, taken from its own answer set so
  /// the measurement cannot drift from what ships.
  Map<String, List<String>> get candidates => {
    for (final answer in SpeechAnswerSet.forLanguage(language)!.answers)
      answer.answer: answer.utterances,
  };

  /// The answer words that measurably work. Everything else in the probe folder
  /// is refused or mis-heard, and the test says so out loud.
  List<String> get mustHear => spec.isWaveform
      ? const [
          'pos_yes_Ɛyɛ.wav',
          'pos_yes_Aane.wav',
          'pos_yes_Yes.wav',
          'pos_no_Nni.wav',
          'pos_no_Mmo.wav',
        ]
      : const ['pos_yes_Ee.wav', 'pos_no_Ayi.wav'];

  Future<void> dispose() => native.dispose();

  /// Null when the weights are not on disk, so a checkout without 1.2 GB of
  /// models passes for the right reason rather than the wrong one.
  static Future<SpeechPack?> open(String base) async {
    final model = File('$base/model.onnx');
    if (!model.existsSync()) return null;
    final bytes = await model.readAsBytes();
    final config = await File('$base/frontend.json').readAsString();
    final spec = AsrModelSpec.fromJson(config);
    final (engine: native, spec: _) = await AsrNativeEngine.load(
      model: bytes,
      artifact: ModelArtifact(
        'model.onnx',
        bytes.length,
        sha256.convert(bytes).toString(),
      ),
      config: config,
    );
    // The recipe decides whether there are tables to read at all: a waveform
    // pack that shipped a mel matrix is refused by the frontend, not ignored.
    final geometry = spec.fbank;
    final frontend = AsrFrontend.fromPack(
      spec: spec,
      filters: geometry == null
          ? null
          : await File('$base/mel_filters.json').readAsString(),
      window: geometry == null
          ? null
          : await File('$base/window.json').readAsString(),
    );
    return SpeechPack._(
      spec,
      native,
      frontend,
      AsrEngine(
        spec: spec,
        frontend: frontend,
        decoder: CtcDecoder(spec),
        encode: native.encode,
      ),
    );
  }
}

/// Mono 16-bit PCM only, and no resampling: `make_answer_probe.py` writes the
/// probe at 16 kHz, and a resampler inside a test would be a second frontend
/// that nothing pinned.
Float32List readWav(File file) {
  final bytes = file.readAsBytesSync();
  final view = bytes.buffer.asByteData(
    bytes.offsetInBytes,
    bytes.lengthInBytes,
  );
  var offset = 12;
  var rate = 0;
  var dataStart = -1;
  var dataEnd = -1;
  while (offset + 8 <= bytes.length) {
    final name = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final size = view.getUint32(offset + 4, Endian.little);
    final body = offset + 8;
    if (name == 'fmt ') {
      rate = view.getUint32(body + 4, Endian.little);
      final channels = view.getUint16(body + 2, Endian.little);
      final width = view.getUint16(body + 14, Endian.little);
      if (channels != 1 || width != 16) {
        throw FormatException('expected mono 16-bit, got $channels x $width');
      }
    } else if (name == 'data') {
      dataStart = body;
      dataEnd = body + size;
    }
    offset = body + size + (size.isOdd ? 1 : 0);
  }
  if (rate != 16000 || dataStart < 0) {
    throw FormatException('expected 16 kHz mono PCM, got $rate');
  }
  return Float32List.fromList([
    for (var i = dataStart; i + 1 < dataEnd; i += 2)
      view.getInt16(i, Endian.little) / 32768.0,
  ]);
}
