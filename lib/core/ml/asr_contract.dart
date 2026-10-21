import 'dart:convert';

/// The mel geometry a `seamless-fbank` pack asks the app to compute. Held apart
/// from [AsrModelSpec] because a raw-waveform pack has none of it: a field that
/// means nothing in half the packs is a field someone will eventually feed to
/// the wrong frontend.
class AsrFbankGeometry {
  const AsrFbankGeometry({
    required this.frameLength,
    required this.hopLength,
    required this.fftLength,
    required this.melBins,
    required this.stride,
    required this.preemphasis,
    required this.melFloor,
    required this.normEpsilon,
    required this.normDdof,
  });

  /// Analysis window, hop and FFT buffer, all in samples. The window is shorter
  /// than the FFT buffer (`400` inside `512`), which is what makes the transform
  /// a power of two without changing the frame.
  final int frameLength;
  final int hopLength;
  final int fftLength;
  final int melBins;

  /// Frames stacked into one encoder step: SeamlessM4T's `(T, 80) -> (T/2, 160)`.
  final int stride;
  final double preemphasis;
  final double melFloor;

  /// Per-mel-band time normalisation: epsilon added to the variance, and
  /// `ddof`, which is 1 for these features and would be a silent 0.8% scale
  /// error if guessed.
  final double normEpsilon;
  final int normDdof;

  int get frequencyBins => fftLength ~/ 2 + 1;

  int get inputDim => melBins * stride;

  /// Analysis frames this clip yields, before stacking. Non-centred framing
  /// drops the tail that does not fill a whole window.
  int melFrames(int samples) {
    if (samples < frameLength) return 0;
    return 1 + (samples - frameLength) ~/ hopLength;
  }
}

/// Contract for a bundled speech recogniser (`asr-v1`), carried as
/// `frontend.json` next to the mel matrix and window it names.
///
/// Delivery, not decoding: it pins the sample rate, the exact feature recipe the
/// model was trained with, the frame geometry the encoder consumes and the label
/// inventory. A pack that disagrees with any of these is rejected at load time
/// rather than half-used, because a mismatched frontend still transcribes —
/// fluently, and of the wrong audio.
///
/// Two recipes exist in the wild and both are in this app. `seamless-fbank`
/// (DONDO) wants the log-mel bank computed here; `waveform` (wav2vec2 XLS-R)
/// wants the layer-normalised samples and does its own spectrogram inside learned
/// convolutions, so it carries no tables at all.
class AsrModelSpec {
  AsrModelSpec._({
    required this.languageCode,
    required this.sampleRate,
    required this.featureType,
    required this.inputDim,
    required this.framesPerSecond,
    required this.maxFrames,
    required this.labels,
    required this.blankIndex,
    required this.inputNames,
    required this.featuresName,
    this.fbank,
    this.waveformEpsilon,
  });

  final String languageCode;
  final int sampleRate;

  /// `seamless-fbank` or `waveform`: which of the two frontends this pack is
  /// allowed to be handed to. Anything else fails at load rather than being fed
  /// numbers nobody computed.
  final String featureType;

  /// Values of [featureType].
  static const fbankFeature = 'seamless-fbank';
  static const waveformFeature = 'waveform';

  /// Dims the encoder takes per frame.
  final int inputDim;

  /// Mel geometry, present exactly when [featureType] is [fbankFeature].
  final AsrFbankGeometry? fbank;

  /// Variance epsilon for the waveform recipe's layer normalisation, present
  /// exactly when [featureType] is [waveformFeature].
  final double? waveformEpsilon;

  /// Feature frames per second of audio, measured off the real extractor rather
  /// than derived. The encoder may emit fewer still — a wav2vec2-Bert adapter
  /// halves them — and Dart never has to know: it reads the row count back from
  /// the session.
  final double framesPerSecond;

  /// Safety valve on memory, in feature frames: a pack asking for more than this
  /// over one take is misconfigured, not being handed a long word. For a
  /// waveform pack, whose frames are samples, it is a ceiling on clip length.
  final int maxFrames;
  final List<String> labels;
  final int blankIndex;
  final List<String> inputNames;

  /// The feature tensor's own name: mel packs are fed `input_features`, waveform
  /// packs `input_values`, and the graph declares which.
  final String featuresName;

  bool get isWaveform => featureType == waveformFeature;

  /// Encoder frames this clip yields. A waveform pack is fed one value per
  /// sample, so its frame count is its sample count.
  int framesFor(int samples) {
    final geometry = fbank;
    final frames = geometry == null
        ? samples
        : geometry.melFrames(samples) ~/ geometry.stride;
    return frames.clamp(0, maxFrames);
  }

  int labelIndex(String token) {
    final index = labels.indexOf(token);
    if (index < 0) {
      throw const FormatException('Spoken form is not in this model\'s labels');
    }
    return index;
  }

  factory AsrModelSpec.fromJson(String source) {
    final config = jsonDecode(source);
    if (config is! Map<String, dynamic>) {
      throw const FormatException('Invalid ASR configuration');
    }
    final audio = config['audio'] as Map?;
    final model = config['model'] as Map?;
    // A missing or non-positive count is a pack this app cannot feed, so every
    // one of them is read through here rather than cast at the callsite.
    int count(Map? section, String key) {
      final value = section?[key];
      if (value is! int || value <= 0) {
        throw const FormatException('Invalid ASR audio contract');
      }
      return value;
    }

    /// A scale factor every recipe here needs: strictly positive, since a zero
    /// floor or epsilon means `log(0)` and a division by the mean.
    double scalar(Map? section, String key) {
      final value = section?[key];
      if (value is! num || value <= 0 || value > 1) {
        throw const FormatException('Invalid ASR audio contract');
      }
      return value.toDouble();
    }

    final language = config['language'] is Map
        ? (config['language'] as Map)['code']
        : null;
    final sampleRate = count(audio, 'sample_rate');
    final inputDim = count(audio, 'input_dim');
    final maxFrames = count(audio, 'max_frames');
    final numLabels = count(model, 'num_labels');
    final labels = model?['labels'];
    final blankIndex = model?['blank_index'];
    final inputs = model?['inputs'];
    final framesPerSecond = audio?['frames_per_second'];
    if (language is! String ||
        language.isEmpty ||
        sampleRate < 8000 ||
        labels is! List ||
        labels.isEmpty ||
        labels.length != numLabels ||
        labels.any((l) => l is! String) ||
        blankIndex is! int ||
        blankIndex < 0 ||
        blankIndex >= numLabels ||
        inputs is! List ||
        inputs.isEmpty ||
        inputs.any((n) => n is! String) ||
        framesPerSecond is! num) {
      throw const FormatException('Invalid ASR audio contract');
    }
    final inputNames = List<String>.from(inputs);
    final features = audio!['features'];
    AsrFbankGeometry? geometry;
    double? waveformEpsilon;
    String featuresName;
    if (features == fbankFeature) {
      // Only the recipe this file implements: a pack naming anything else would
      // be fed numbers nobody computed.
      final normalize = audio['per_band_normalize'] as Map?;
      final frameLength = count(audio, 'frame_length');
      final hopLength = count(audio, 'hop_length');
      final fftLength = count(audio, 'fft_length');
      final melBins = count(audio, 'mel_bins');
      final stride = count(audio, 'stride');
      final ddof = normalize?['ddof'];
      final rate = sampleRate / (hopLength * stride);
      if (audio['remove_dc_offset'] != true ||
          audio['log'] != 'log' ||
          audio['power'] != 2.0 ||
          normalize?['mode'] != 'zero-mean-unit-variance' ||
          ddof != 0 && ddof != 1 ||
          // Geometry the in-app transform can run: a power-of-two FFT buffer, a
          // window that fits inside it, and an input width that is the mel bank
          // stacked.
          (fftLength & (fftLength - 1)) != 0 ||
          hopLength > frameLength ||
          frameLength > fftLength ||
          inputDim != melBins * stride ||
          !inputNames.toSet().containsAll(
            const {'input_features', 'attention_mask'},
          ) ||
          // Measured off the real extractor, so it is the one number the
          // geometry cannot be trusted to reproduce on its own.
          (framesPerSecond - rate).abs() > rate * 0.05) {
        throw const FormatException('ASR frontend is not the one this app runs');
      }
      waveformEpsilon = null;
      featuresName = 'input_features';
      geometry = AsrFbankGeometry(
        frameLength: frameLength,
        hopLength: hopLength,
        fftLength: fftLength,
        melBins: melBins,
        stride: stride,
        preemphasis: scalar(audio, 'preemphasis'),
        melFloor: scalar(audio, 'mel_floor'),
        normEpsilon: scalar(normalize, 'epsilon'),
        normDdof: ddof as int,
      );
    } else if (features == waveformFeature) {
      // The model does its own spectrogram, so the app must not compute one: it
      // hands over normalised samples and the sample rate is the frame rate.
      if (inputDim != 1 ||
          framesPerSecond != sampleRate.toDouble() ||
          !inputNames.toSet().containsAll(
            const {'input_values', 'attention_mask'},
          )) {
        throw const FormatException('ASR frontend is not the one this app runs');
      }
      geometry = null;
      featuresName = 'input_values';
      waveformEpsilon = scalar(audio, 'normalize_epsilon');
    } else {
      throw const FormatException('ASR frontend is not the one this app runs');
    }
    return AsrModelSpec._(
      languageCode: language,
      sampleRate: sampleRate,
      featureType: features as String,
      inputDim: inputDim,
      framesPerSecond: framesPerSecond.toDouble(),
      maxFrames: maxFrames,
      labels: List<String>.from(labels),
      blankIndex: blankIndex,
      inputNames: inputNames,
      featuresName: featuresName,
      fbank: geometry,
      waveformEpsilon: waveformEpsilon,
    );
  }

  void validateInputs(List<String> names) {
    if (names.length != inputNames.length ||
        !inputNames.toSet().containsAll(names)) {
      throw const FormatException('Unsupported ASR input contract');
    }
  }
}
