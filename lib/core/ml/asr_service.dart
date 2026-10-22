import 'dart:typed_data';

import 'asr_contract.dart';
import 'asr_decoder.dart';
import 'asr_features.dart';
import 'asr_encoder.dart';
import 'model_artifact.dart';
import 'native_pack_store.dart';

/// A speech pack that cannot spell an answer is not half-usable.
///
/// Same rule as the text frontend: a character outside the model's label
/// inventory would silently decode into something else, and in a triage flow
/// "something else" is a wrong clinical answer.
class UnspellableAnswerException implements Exception {
  const UnspellableAnswerException(this.answer, this.missing);
  final String answer;
  final List<String> missing;

  @override
  String toString() =>
      'This voice pack cannot hear "$answer": ${missing.join(' ')} is not in its label inventory.';
}

class AsrHearing {
  const AsrHearing({required this.scores, required this.reading});

  /// Ranked, with a real posterior per candidate. Empty when nothing was asked.
  final List<CandidateScore> scores;

  /// Independent free transcription of the same frames: the cross-check for a
  /// closed set, and the result for dictation.
  final AsrReading reading;
}

/// One loaded recogniser. It answers a closed set and transcribes from the same
/// encoder pass, so a screen that listens and a screen that dictates cost one
/// model rather than two.
///
/// The tensor call is injected, which keeps the decisions — feature geometry,
/// label spelling, both decodings — testable without a native session.
class AsrEngine {
  AsrEngine({
    required this.spec,
    required AsrFrontend frontend,
    required CtcDecoder decoder,
    required Future<List<Float32List>> Function(
      Float32List features,
      int frames,
    )
    encode,
  }) : _frontend = frontend,
       _decoder = decoder,
       _encode = encode;

  final AsrModelSpec spec;
  final AsrFrontend _frontend;
  final CtcDecoder _decoder;
  final Future<List<Float32List>> Function(Float32List, int) _encode;

  /// Which of [candidates] this pack can hear at all. An answer it cannot spell
  /// is dropped, so the caller hides the affordance instead of promising a
  /// listener that can only refuse.
  List<String> heardAnswers(Map<String, List<String>> candidates) {
    final out = <String>[];
    for (final entry in candidates.entries) {
      if (_spellable(entry.value).isNotEmpty) out.add(entry.key);
    }
    return out;
  }

  /// [pcm] is mono audio at [AsrModelSpec.sampleRate].
  Future<AsrHearing> hear(
    Float32List pcm,
    Map<String, List<String>> candidates,
  ) async {
    final features = _frontend.process(pcm);
    final frames = spec.framesFor(pcm.length);
    if (frames == 0) {
      throw const FormatException('Take too short to feature');
    }
    if (features.length != frames * spec.inputDim) {
      throw const FormatException('Feature length disagrees with the model');
    }
    final posteriors = await _encode(features, frames);
    final indices = {
      for (final entry in candidates.entries)
        entry.key: _spellable(entry.value),
    };
    for (final entry in candidates.entries) {
      if (indices[entry.key]!.isEmpty) {
        throw UnspellableAnswerException(
          entry.value.first,
          _missing(entry.value.first),
        );
      }
    }
    return AsrHearing(
      scores: _decoder.restricted(posteriors, indices),
      reading: _decoder.greedy(posteriors),
    );
  }

  /// Every spoken form this pack can spell. A synonym the pack cannot spell is
  /// dropped rather than guessed at, but an answer whose forms are ALL outside
  /// the inventory is the caller's problem, not something to score as silence.
  List<List<int>> _spellable(List<String> utterances) => [
    for (final utterance in utterances)
      if (_missing(utterance).isEmpty) _spell(utterance),
  ];

  List<String> _missing(String utterance) => [
    for (final glyph in utterance.toLowerCase().split(''))
      if (glyph != ' ' && !spec.labels.contains(glyph)) glyph,
  ];

  List<int> _spell(String utterance) {
    final missing = <String>[];
    final ids = <int>[];
    for (final glyph in utterance.toLowerCase().split('')) {
      if (glyph == ' ') continue;
      final index = spec.labels.indexOf(glyph);
      if (index < 0) {
        missing.add(glyph);
      } else {
        ids.add(index);
      }
    }
    if (missing.isNotEmpty) {
      throw UnspellableAnswerException(utterance, missing);
    }
    return ids;
  }
}

/// Owns the loaded packs, one per language, and serialises their lifecycle so
/// two screens warming up at once cannot allocate the same model twice.
class AsrService {
  AsrService._();
  static final AsrService instance = AsrService._();

  final _models = <String, _Pack>{};
  Future<void> _tail = Future.value();

  bool isReady(String language) => _models.containsKey(language);

  AsrEngine? engine(String language) => _models[language]?.engine;

  /// Bundled packs at `assets/asr/{language}`, and hosted packs under the same
  /// name in the offline pack store: `NativePackStore.bundle` prefers an
  /// installed `ready-*` revision and falls back to the bundle, so one path
  /// serves a preloaded device and a downloaded pack.
  static String assetPath(String language) => NativePackStore.asrBase(language);

  Future<void> ensureLoaded(String language) => _serialize(() async {
    if (_models.containsKey(language)) return;
    final path = assetPath(language);
    final bundle = await NativePackStore().bundle(path);
    final manifest = await ModelArtifactManifest.load(
      path,
      'asr-v1',
      bundle: bundle,
    );
    NativePackStore.validateInventory(manifest, path);
    // The recipe travels with the pack: the contract plus the mel matrix and
    // window the model was trained on, so the frontend cannot drift from it.
    final config = await manifest.text(path, 'frontend.json', bundle: bundle);
    final data = await bundle.load('$path/model.onnx');
    final loaded = await createAsrEncoder(
      model: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      artifact: manifest.file('model.onnx'),
      config: config,
    );
    // No encoder on this platform: the pack stays unloaded, `isReady` stays
    // false, and every voice affordance renders nothing.
    if (loaded == null) return;
    final native = loaded.encoder;
    final spec = loaded.spec;
    // The recipe travels with the pack: a mel pack carries the matrix and window
    // it was trained on, so the frontend cannot drift from it, and a waveform
    // pack carries neither because its spectrogram is inside the model.
    final geometry = spec.fbank;
    _models[language] = _Pack(
      native: native,
      engine: AsrEngine(
        spec: spec,
        frontend: AsrFrontend.fromPack(
          spec: spec,
          filters: geometry == null
              ? null
              : await manifest.text(path, 'mel_filters.json', bundle: bundle),
          window: geometry == null
              ? null
              : await manifest.text(path, 'window.json', bundle: bundle),
        ),
        decoder: CtcDecoder(spec),
        encode: native.encode,
      ),
    );
  });

  Future<void> dispose() => _serialize(() async {
    for (final pack in _models.values) {
      await pack.native.dispose();
    }
    _models.clear();
  });

  Future<T> _serialize<T>(Future<T> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then((_) {}, onError: (_) {});
    return next;
  }
}

class _Pack {
  _Pack({required this.engine, required this.native});
  final AsrEngine engine;
  final AsrEncoder native;
}
