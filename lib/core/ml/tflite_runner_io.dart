library;

import 'dart:typed_data';

import 'package:tflite_flutter/tflite_flutter.dart';

import 'tflite_runner.dart';
import 'tflite_dart_interpreter.dart';

TfliteRunner createTfliteRunner() => _IoTfliteRunner();

class _IoTfliteRunner implements TfliteRunner {
  final Map<String, Future<Interpreter>> _cache = {};

  @override
  Future<double> run({
    required String assetPath,
    required Float32List input,
  }) async {
    final interpreter = await _loadInterpreter(assetPath);
    final inputTensor = interpreter.getInputTensor(0);
    final outputTensor = interpreter.getOutputTensor(0);

    if (interpreter.getInputTensors().length != 1 ||
        interpreter.getOutputTensors().length != 1 ||
        inputTensor.shape.length != 2 ||
        inputTensor.shape[0] != 1 ||
        inputTensor.shape[1] != input.length ||
        outputTensor.shape.length != 2 ||
        outputTensor.shape[0] != 1 ||
        outputTensor.shape[1] != 1 ||
        input.any((v) => !v.isFinite)) {
      throw const FormatException('Incompatible model signature or input');
    }
    for (final tensor in [inputTensor, outputTensor]) {
      if (![
        TensorType.float32,
        TensorType.int8,
        TensorType.uint8,
      ].contains(tensor.type)) {
        throw const FormatException('Unsupported tensor type');
      }
      if (tensor.type != TensorType.float32 &&
          (!tensor.params.scale.isFinite ||
              tensor.params.scale <= 0 ||
              tensor.params.zeroPoint <
                  (tensor.type == TensorType.int8 ? -128 : 0) ||
              tensor.params.zeroPoint >
                  (tensor.type == TensorType.int8 ? 127 : 255))) {
        throw const FormatException('Invalid quantization scale or zero point');
      }
    }
    final inputObj = _materializeInput(inputTensor, input);
    final output = _allocateOutput(outputTensor);
    interpreter.run(inputObj, output);
    final p = _readProbability(outputTensor, output);
    if (!p.isFinite || p < 0 || p > 1) {
      throw const FormatException('Invalid model output');
    }
    return p;
  }

  Future<Interpreter> _loadInterpreter(String assetPath) => _cache.putIfAbsent(
    assetPath,
    () => Interpreter.fromAsset(
      assetPath,
      options: InterpreterOptions()..threads = 2,
    ),
  );

  static Object _materializeInput(Tensor tensor, Float32List input) {
    if (tensor.type == TensorType.float32) {
      return <List<double>>[input.map((e) => e.toDouble()).toList()];
    }
    if (tensor.type == TensorType.int8) {
      return <Int8List>[_quantizeInt8(tensor, input)];
    }
    return <Uint8List>[_quantizeUint8(tensor, input)];
  }

  static Int8List _quantizeInt8(Tensor tensor, Float32List input) {
    final params = tensor.params;
    final scale = params.scale;
    final zeroPoint = params.zeroPoint;
    final out = Int8List(input.length);
    for (int i = 0; i < input.length; i++) {
      final q = TfliteDartModel.quantizeInputValue(input[i], scale, zeroPoint);
      out[i] = q.clamp(-128, 127).toInt();
    }
    return out;
  }

  static Uint8List _quantizeUint8(Tensor tensor, Float32List input) {
    final params = tensor.params;
    final scale = params.scale;
    final zeroPoint = params.zeroPoint;
    final out = Uint8List(input.length);
    for (int i = 0; i < input.length; i++) {
      final q = TfliteDartModel.quantizeInputValue(input[i], scale, zeroPoint);
      out[i] = q.clamp(0, 255).toInt();
    }
    return out;
  }

  static Object _allocateOutput(Tensor outputTensor) {
    final shape = outputTensor.shape;
    final channels = shape.isEmpty ? 1 : shape.last;
    if (outputTensor.type != TensorType.float32) {
      if (outputTensor.type == TensorType.int8) {
        return <Int8List>[Int8List(channels)];
      }
      return <Uint8List>[Uint8List(channels)];
    }
    return <List<double>>[List<double>.filled(channels, 0.0)];
  }

  static double _readProbability(Tensor outputTensor, Object output) {
    final params = outputTensor.params;
    final scale = outputTensor.type == TensorType.float32 ? null : params.scale;
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
    throw const FormatException('Unrecognized model output');
  }
}
