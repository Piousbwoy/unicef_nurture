import 'dart:typed_data';

import '../ml/asr_service.dart';
import 'speech_input_service.dart';

/// The app-facing listener, backed by whatever `asr-v1` pack is loaded.
///
/// Loading is the warm-up's job, not the question's: a screen must never pay a
/// model load between a tap and a hearing, so this refuses instead of loading.
class PackSpeechListener implements SpeechListener {
  PackSpeechListener(this._asr);

  final AsrService _asr;

  @override
  bool isReady(String language) => _asr.isReady(language);

  @override
  Future<AsrHearing> hear(
    Float32List pcm, {
    required String language,
    required Map<String, List<String>> candidates,
  }) async {
    final engine = _asr.engine(language);
    if (engine == null) {
      throw StateError('No speech pack is loaded for $language');
    }
    return engine.hear(pcm, candidates);
  }
}
