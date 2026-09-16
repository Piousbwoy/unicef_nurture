library;

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import 'tflite_dart_interpreter.dart';
import 'tflite_runner.dart';

TfliteRunner createTfliteRunner() => _WebDartTfliteRunner();

/// Web execution of supported TFLite graphs. Failures are explicit; clinical
/// rules remain independent of model execution and do not fabricate scores.
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
    final p = model.run(input);
    if (!p.isFinite || p < 0 || p > 1)
      throw const FormatException('Invalid model output');
    return p;
  }
}
