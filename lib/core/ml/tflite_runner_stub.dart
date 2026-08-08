library;

import 'dart:typed_data';

import 'tflite_runner.dart';

TfliteRunner createTfliteRunner() => _StubTfliteRunner();

class _StubTfliteRunner implements TfliteRunner {
  @override
  Future<double> run({required String assetPath, required Float32List input}) {
    throw UnsupportedError('TFLite is not available on this platform.');
  }
}

