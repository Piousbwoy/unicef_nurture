library;

import 'dart:typed_data';

import 'tflite_runner_stub.dart' if (dart.library.io) 'tflite_runner_io.dart';

abstract class TfliteRunner {
  Future<double> run({
    required String assetPath,
    required Float32List input,
  });
}

TfliteRunner getTfliteRunner() => createTfliteRunner();

