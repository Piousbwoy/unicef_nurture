import 'dart:typed_data';

import 'asr_contract.dart';
import 'asr_encoder.dart';
import 'model_artifact.dart';

/// The browser has no `dart:ffi`, so there is no ONNX runtime to load a
/// recogniser into. Returning null — rather than throwing — is what lets
/// `AsrService` stay silent and the microphone render nothing.
Future<({AsrEncoder encoder, AsrModelSpec spec})?> buildAsrEncoder({
  required Uint8List model,
  required ModelArtifact artifact,
  required String config,
}) async => null;
