import 'dart:typed_data';

import 'asr_contract.dart';
import 'asr_encoder.dart';
import 'asr_native_engine.dart';
import 'model_artifact.dart';

Future<({AsrEncoder encoder, AsrModelSpec spec})?> buildAsrEncoder({
  required Uint8List model,
  required ModelArtifact artifact,
  required String config,
}) async {
  final (engine: native, spec: spec) = await AsrNativeEngine.load(
    model: model,
    artifact: artifact,
    config: config,
  );
  return (encoder: native, spec: spec);
}
