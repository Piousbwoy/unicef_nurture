library;

import 'dart:typed_data';

import 'package:tflite_flutter/tflite_flutter.dart';

import 'tflite_runner.dart';

TfliteRunner createTfliteRunner() => _IoTfliteRunner();

class _IoTfliteRunner implements TfliteRunner {
  final Map<String, Interpreter> _cache = {};

  @override
  Future<double> run({required String assetPath, required Float32List input}) async {
    final interpreter = await _loadInterpreter(assetPath);
    final inputTensor = interpreter.getInputTensor(0);
    final outputTensor = interpreter.getOutputTensor(0);

    final inputObj = _materializeInput(inputTensor, input);
    final output = _allocateOutput(outputTensor);
    interpreter.run(inputObj, output);
    final p = _readProbability(outputTensor, output);
    return p.clamp(0.0, 1.0);
  }

  Future<Interpreter> _loadInterpreter(String assetPath) async {
    final existing = _cache[assetPath];
    if (existing != null) return existing;
    final options = InterpreterOptions()..threads = 2;
    final interpreter = await Interpreter.fromAsset(assetPath, options: options);
    _cache[assetPath] = interpreter;
    return interpreter;
  }

  static Object _materializeInput(Tensor tensor, Float32List input) {
    final params = tensor.params;
    final isQuantized = params.scale != 0;
    if (!isQuantized) {
      return <List<double>>[input.map((e) => e.toDouble()).toList()];
    }
    if (params.zeroPoint < 0) {
      return <Int8List>[_quantizeInt8(tensor, input)];
    }
    return <Uint8List>[_quantizeUint8(tensor, input)];
  }

  static Int8List _quantizeInt8(Tensor tensor, Float32List input) {
    final params = tensor.params;
    final scale = params.scale == 0 ? 1.0 : params.scale;
    final zeroPoint = params.zeroPoint;
    final out = Int8List(input.length);
    for (int i = 0; i < input.length; i++) {
      final q = (input[i] / scale + zeroPoint).round();
      out[i] = q.clamp(-128, 127).toInt();
    }
    return out;
  }

  static Uint8List _quantizeUint8(Tensor tensor, Float32List input) {
    final params = tensor.params;
    final scale = params.scale == 0 ? 1.0 : params.scale;
    final zeroPoint = params.zeroPoint;
    final out = Uint8List(input.length);
    for (int i = 0; i < input.length; i++) {
      final q = (input[i] / scale + zeroPoint).round();
      out[i] = q.clamp(0, 255).toInt();
    }
    return out;
  }

  static Object _allocateOutput(Tensor outputTensor) {
    final shape = outputTensor.shape;
    final channels = shape.isEmpty ? 1 : shape.last;
    final params = outputTensor.params;
    if (params.scale != 0) {
      if (params.zeroPoint < 0) {
        return <Int8List>[Int8List(channels)];
      }
      return <Uint8List>[Uint8List(channels)];
    }
    return <List<double>>[List<double>.filled(channels, 0.0)];
  }

  static double _readProbability(Tensor outputTensor, Object output) {
    final params = outputTensor.params;
    final scale = params.scale == 0 ? null : params.scale;
    final zeroPoint = params.zeroPoint;

    double deq(num v) =>
        scale == null ? v.toDouble() : ((v.toDouble() - zeroPoint) * scale);

    if (output is List && output.isNotEmpty) {
      final first = output.first;
      if (first is List && first.isNotEmpty) {
        if (first.length == 1) return deq(first[0] as num);
        return deq(first[1] as num);
      }
      if (first is Int8List && first.isNotEmpty) {
        if (first.length == 1) return deq(first[0]);
        return deq(first.length > 1 ? first[1] : first[0]);
      }
      if (first is Uint8List && first.isNotEmpty) {
        if (first.length == 1) return deq(first[0]);
        return deq(first.length > 1 ? first[1] : first[0]);
      }
    }
    return 0.5;
  }
}
