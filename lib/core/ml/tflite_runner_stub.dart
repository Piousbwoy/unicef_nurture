library;

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import 'tflite_dart_interpreter.dart';
import 'tflite_runner.dart';

TfliteRunner createTfliteRunner() => _WebDartTfliteRunner();

/// Web build: there is no dart:ffi, so the native tflite_flutter runtime
/// cannot load. The SHA-pinned int8 weights are instead executed on-device
/// by the pure-Dart flatbuffer interpreter, which has been cross-validated
/// bit-exact (24/24 trials, maxAbsDiff 0.0) against the official TFLite
/// runtime (`tf.lite.Interpreter`) on the exact shipped flatbuffers.
///
/// Failure semantics are preserved: any load/parse/run error throws, so
/// `OfflineInferenceService` keeps falling back to the deterministic
/// rules path exactly as before.
class _WebDartTfliteRunner implements TfliteRunner {
  final Map<String, TfliteDartModel> _models = {};

  @override
  Future<double> run({
    required String assetPath,
    required Float32List input,
  }) async {
    var model = _models[assetPath];
    if (model == null) {
      final bytes = (await rootBundle.load(assetPath)).buffer.asUint8List();
      model = TfliteDartModel.fromBytes(bytes);
      _models[assetPath] = model;
    }
    return model.run(input).clamp(0.0, 1.0);
  }
}
