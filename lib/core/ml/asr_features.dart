import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'asr_contract.dart';

/// Turns a take into the tensor the pack's encoder was trained to receive.
///
/// Which recipe runs is decided by the pack, never by the caller:
/// [AsrModelSpec.fbank] is null exactly for a raw-waveform pack, so a contract
/// cannot be paired with the wrong arithmetic.
/// `test/asr_frontend_fixture_test.dart` proves the mel path reproduces the real
/// extractor to float tolerance; a frontend that disagrees still transcribes,
/// fluently, of the wrong audio.
abstract class AsrFrontend {
  /// The pack's own recipe. A `seamless-fbank` pack must carry its mel matrix
  /// and window; a `waveform` pack must carry neither, because the spectrogram
  /// it was trained on lives inside its own learned convolutions.
  factory AsrFrontend.fromPack({
    required AsrModelSpec spec,
    String? filters,
    String? window,
  }) {
    final geometry = spec.fbank;
    if (geometry == null) {
      if (filters != null || window != null) {
        throw const FormatException(
          'A raw-waveform ASR pack cannot carry mel tables',
        );
      }
      return WaveformFrontend(spec.waveformEpsilon!);
    }
    if (filters == null || window == null) {
      throw const FormatException(
        'This ASR pack does not carry the frontend it asks for',
      );
    }
    return MelFrontend.fromPack(
      spec: spec,
      geometry: geometry,
      filters: filters,
      window: window,
    );
  }

  /// A mel frontend built from decoded tables instead of pack files.
  factory AsrFrontend.mel({
    required AsrModelSpec spec,
    required List<double> filters,
    required List<double> window,
  }) => MelFrontend.decoded(
    spec: spec,
    geometry: spec.fbank!,
    filters: filters,
    window: window,
  );

  /// Row-major `frames x inputDim`, ready for `AsrNativeEngine.encode`. A take
  /// too short for the recipe yields nothing at all.
  Float32List process(Float32List pcm);
}

/// HuggingFace's SeamlessM4T log-mel recipe, in Dart: what
/// `KhayaAI/w2v-bert-dga` was trained on. The pack ships its own mel matrix and
/// window so nothing here has to re-derive Kaldi's filter bank: the two tables
/// plus the scalars in [AsrFbankGeometry] are the whole recipe.
class MelFrontend implements AsrFrontend {
  /// The pack's tables: `mel_filters.json` is `(frequency bin, mel band)`,
  /// row-major, and its recorded axes are checked rather than assumed, because
  /// the transposed bank is the one mistake that still decodes.
  factory MelFrontend.fromPack({
    required AsrModelSpec spec,
    required AsrFbankGeometry geometry,
    required String filters,
    required String window,
  }) {
    final bank = jsonDecode(filters);
    final frame = jsonDecode(window);
    if (bank is! Map<String, dynamic> || frame is! Map<String, dynamic>) {
      throw const FormatException('Invalid ASR frontend tables');
    }
    final axes = bank['axes'];
    final shape = bank['shape'];
    final values = bank['values'];
    if (axes is! List ||
        (axes.length != 2 ||
            axes[0] != 'frequency_bin' ||
            axes[1] != 'mel_filter') ||
        shape is! List ||
        shape.length != 2 ||
        shape[0] != geometry.frequencyBins ||
        shape[1] != geometry.melBins ||
        values is! List ||
        values.length != shape[0] ||
        values.any((row) => row is! List || row.length != shape[1]) ||
        frame['values'] is! List ||
        (frame['values'] as List).length != geometry.frameLength) {
      throw const FormatException(
        'ASR frontend tables disagree with the contract',
      );
    }
    return MelFrontend.decoded(
      spec: spec,
      geometry: geometry,
      filters: [
        for (final row in values)
          for (final v in row) (v as num).toDouble(),
      ],
      window: (frame['values'] as List)
          .map((v) => (v as num).toDouble())
          .toList(),
    );
  }

  MelFrontend.decoded({
    required this.spec,
    required this.geometry,
    required List<double> filters,
    required List<double> window,
  }) : assert(
         geometry.fftLength & (geometry.fftLength - 1) == 0,
         'fft_length must be a power of two',
       ),
       assert(
         filters.length == geometry.frequencyBins * geometry.melBins,
         'mel matrix shape mismatch',
       ),
       assert(window.length == geometry.frameLength, 'window length mismatch'),
       _filters = Float64List.fromList(filters),
       _window = Float64List.fromList(window);

  final AsrModelSpec spec;
  final AsrFbankGeometry geometry;
  final Float64List _filters;
  final Float64List _window;

  /// Row-major frames x encoder dims, stacked so frame t of the output is the
  /// analysis frames `t*stride` and `t*stride+1` concatenated. Kaldi framing is
  /// non-centred, so a take that does not fill one whole window has nothing to
  /// pad and no frame to emit.
  @override
  Float32List process(Float32List pcm) {
    final g = geometry;
    final analysis = g.melFrames(pcm.length);
    final frames = analysis ~/ g.stride;
    if (frames == 0) return Float32List(0);
    final logMel = Float64List(analysis * g.melBins);
    final buffer = Float64List(g.fftLength);
    final re = Float64List(g.fftLength);
    final im = Float64List(g.fftLength);
    final half = g.frequencyBins;
    final power = Float64List(half);
    for (var f = 0; f < analysis; f++) {
      final start = f * g.hopLength;
      var sum = 0.0;
      for (var i = 0; i < g.frameLength; i++) {
        final v = pcm[start + i] * 32768.0; // Kaldi compliance: 16-bit integers
        buffer[i] = v;
        sum += v;
      }
      final mean = sum / g.frameLength;
      for (var i = 0; i < g.frameLength; i++) {
        buffer[i] -= mean; // DC offset, before pre-emphasis
      }
      var previous = buffer[0];
      buffer[0] *= 1 - g.preemphasis;
      for (var i = 1; i < g.frameLength; i++) {
        final current = buffer[i];
        buffer[i] = current - g.preemphasis * previous;
        previous = current;
      }
      for (var i = 0; i < g.fftLength; i++) {
        re[i] = i < g.frameLength ? buffer[i] * _window[i] : 0.0;
        im[i] = 0.0;
      }
      _fft(re, im);
      for (var k = 0; k < half; k++) {
        power[k] = re[k] * re[k] + im[k] * im[k];
      }
      for (var m = 0; m < g.melBins; m++) {
        var energy = 0.0;
        for (var k = 0; k < half; k++) {
          final w = _filters[k * g.melBins + m];
          if (w != 0) energy += w * power[k];
        }
        logMel[f * g.melBins + m] = math.log(math.max(energy, g.melFloor));
      }
    }
    // Each mel band is zero-mean/unit-variance over time, then `stride` analysis
    // frames are laid side by side per encoder step.
    final out = Float32List(frames * spec.inputDim);
    final divisor = math.max(analysis - g.normDdof, 1);
    for (var m = 0; m < g.melBins; m++) {
      var mean = 0.0;
      for (var f = 0; f < analysis; f++) {
        mean += logMel[f * g.melBins + m];
      }
      mean /= analysis;
      var variance = 0.0;
      for (var f = 0; f < analysis; f++) {
        final deviation = logMel[f * g.melBins + m] - mean;
        variance += deviation * deviation;
      }
      final scale = math.sqrt(variance / divisor + g.normEpsilon);
      for (var t = 0; t < frames; t++) {
        for (var s = 0; s < g.stride; s++) {
          final f = t * g.stride + s;
          out[t * spec.inputDim + s * g.melBins + m] =
              (logMel[f * g.melBins + m] - mean) / scale;
        }
      }
    }
    return out;
  }
}

/// `Wav2Vec2FeatureExtractor` with `feature_size: 1, do_normalize: true`, which
/// is what `asr-africa/wav2vec2-xls-r-akan-20-hours` asks for: the samples,
/// layer-normalised over the whole take. There is no filter bank here to get
/// wrong, and none for the pack to carry — the model's seven convolution layers
/// compute the spectrogram themselves, so all this frontend does is take the
/// recording's loudness out of the signal.
class WaveformFrontend implements AsrFrontend {
  WaveformFrontend(this.epsilon);

  /// Added to the variance, exactly as the Python extractor adds it, because a
  /// silent take would otherwise divide by zero and decode into confident noise.
  final double epsilon;

  @override
  Float32List process(Float32List pcm) {
    if (pcm.isEmpty) return Float32List(0);
    var mean = 0.0;
    for (final sample in pcm) {
      mean += sample;
    }
    mean /= pcm.length;
    var variance = 0.0;
    for (final sample in pcm) {
      final deviation = sample - mean;
      variance += deviation * deviation;
    }
    // Population variance, the numpy default: a ddof of 1 would scale every take
    // by a factor that depends on its own length.
    final scale = math.sqrt(variance / pcm.length + epsilon);
    return Float32List.fromList(
      [for (final sample in pcm) (sample - mean) / scale],
    );
  }
}

/// In-place iterative radix-2 Cooley-Tukey on separate re/im arrays.
void _fft(Float64List re, Float64List im) {
  final n = re.length;
  for (var i = 1, j = 0; i < n; i++) {
    var bit = n >> 1;
    for (; j & bit != 0; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) {
      var t = re[i];
      re[i] = re[j];
      re[j] = t;
      t = im[i];
      im[i] = im[j];
      im[j] = t;
    }
  }
  for (var size = 2; size <= n; size <<= 1) {
    final half = size >> 1;
    final step = 2 * math.pi / size;
    for (var start = 0; start < n; start += size) {
      for (var k = 0; k < half; k++) {
        final angle = -step * k;
        final wr = math.cos(angle), wi = math.sin(angle);
        final a = start + k, b = a + half;
        final tr = re[b] * wr - im[b] * wi;
        final ti = re[b] * wi + im[b] * wr;
        re[b] = re[a] - tr;
        im[b] = im[a] - ti;
        re[a] += tr;
        im[a] += ti;
      }
    }
  }
}
