import 'dart:convert';
import 'dart:typed_data';

/// Shared, testable tensor/audio contract for ONNX native and WASM runners.
class PiperModelSpec {
  PiperModelSpec._(this.sampleRate, this.numSpeakers, this.scales);
  final int sampleRate;
  final int numSpeakers;
  final Float32List scales;

  factory PiperModelSpec.fromJson(String json) {
    final config = jsonDecode(json) as Map<String, dynamic>;
    final sampleRate = (config['audio'] as Map?)?['sample_rate'];
    final speakers = config['num_speakers'];
    final inference = config['inference'] as Map? ?? const {};
    final values = [
      inference['noise_scale'] ?? 0.667,
      inference['length_scale'] ?? 1.0,
      inference['noise_w'] ?? 0.8,
    ];
    if (sampleRate is! int ||
        sampleRate < 8000 ||
        sampleRate > 96000 ||
        speakers is! int ||
        speakers < 1 ||
        values.any((v) => v is! num || !v.isFinite || v <= 0)) {
      throw const FormatException('Invalid Piper audio configuration');
    }
    return PiperModelSpec._(
      sampleRate,
      speakers,
      Float32List.fromList(values.map((v) => (v as num).toDouble()).toList()),
    );
  }

  void validateSpeaker(int speaker) {
    if (speaker < 0 || speaker >= numSpeakers) {
      throw const FormatException('Speaker is not part of this model');
    }
  }

  void validateInputs(List<String> names) {
    final expected = {
      'input',
      'input_lengths',
      'scales',
      if (numSpeakers > 1) 'sid',
    };
    if (names.length != expected.length || !expected.containsAll(names)) {
      throw const FormatException('Unsupported Piper input contract');
    }
  }
}

abstract final class PiperAudio {
  static Float32List samples(Object? output) {
    var value = output;
    while (value is List && value.length == 1 && value.first is List) {
      value = value.first;
    }
    if (value is! List ||
        value.isEmpty ||
        value.any((v) => v is! num || !v.isFinite)) {
      throw const FormatException('Invalid Piper audio tensor');
    }
    final samples = Float32List.fromList(
      value.map((v) => (v as num).toDouble()).toList(),
    );
    if (!samples.any((s) => s.abs() > 0.0000001) ||
        samples.any((s) => !s.isFinite)) {
      throw const FormatException('Piper returned silent or invalid audio');
    }
    return samples;
  }

  static Uint8List wav(Float32List samples, int sampleRate) {
    final result = Uint8List(44 + samples.length * 2);
    final data = ByteData.sublistView(result);
    result.setRange(0, 4, ascii.encode('RIFF'));
    data.setUint32(4, result.length - 8, Endian.little);
    result.setRange(8, 12, ascii.encode('WAVE'));
    result.setRange(12, 16, ascii.encode('fmt '));
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(28, sampleRate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    result.setRange(36, 40, ascii.encode('data'));
    data.setUint32(40, samples.length * 2, Endian.little);
    for (var i = 0; i < samples.length; i++) {
      data.setInt16(
        44 + 2 * i,
        (samples[i].clamp(-1, 1) * 32767).round(),
        Endian.little,
      );
    }
    return result;
  }

  static List<String> chunks(String text, {int maxCharacters = 220}) {
    if (maxCharacters < 8) throw ArgumentError.value(maxCharacters);
    final parts = text.trim().split(RegExp(r'(?<=[.!?])\s+'));
    final chunks = <String>[];
    for (var part in parts) {
      while (part.length > maxCharacters) {
        final split = part.lastIndexOf(RegExp(r'\s'), maxCharacters);
        if (split <= 0) {
          throw const FormatException('Speech token exceeds the length limit');
        }
        chunks.add(part.substring(0, split).trim());
        part = part.substring(split).trim();
      }
      if (part.isNotEmpty) chunks.add(part);
    }
    return chunks;
  }
}
