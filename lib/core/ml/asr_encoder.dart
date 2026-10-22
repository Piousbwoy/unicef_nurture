/// Platform-conditional abstraction over a loaded recogniser graph.
///
/// `onnxruntime` is a native FFI binding: there is no `dart:ffi` on the web, so
/// importing it from anything in the app's main import graph breaks the JS
/// compile — the same reason [piper_tts_runner] and [translation_runner] exist.
/// The contract, the frontend and the decoder in this folder are pure Dart and
/// run anywhere; only the encoder needs the seam.
library;

import 'dart:typed_data';

import 'asr_contract.dart';
import 'asr_encoder_stub.dart'
    if (dart.library.io) 'asr_encoder_native.dart';
import 'model_artifact.dart';

/// One loaded encoder: `frames x inputDim` features in, frame posteriors out.
abstract class AsrEncoder {
  /// The rows are the graph's own, not the caller's frame count: both Ghanaian
  /// packs downsample internally, so the count has to come back from the run.
  Future<List<Float32List>> encode(Float32List features, int frames);

  Future<void> dispose();
}

/// Null when this platform cannot run a recogniser at all. Callers must treat
/// that as "no microphone to offer", not as an error to retry: a browser has no
/// native ONNX runtime, and a listening affordance that can only ever apologise
/// is worse than no affordance.
Future<({AsrEncoder encoder, AsrModelSpec spec})?> createAsrEncoder({
  required Uint8List model,
  required ModelArtifact artifact,
  required String config,
}) => buildAsrEncoder(model: model, artifact: artifact, config: config);
