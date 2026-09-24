/// Web stub: Piper TTS unavailable in browser (no native Rust ort bindings).
/// Falls through to system TTS or readable text.
library;

import 'piper_contract.dart';
import 'piper_tts_runner.dart';

PiperTtsRunner buildPiperTtsRunner() => _WebPiperTtsRunner();

class _WebPiperTtsRunner implements PiperTtsRunner {
  @override
  bool get available => false;

  @override
  bool get isSpeaking => false;

  @override
  Future<void> init({
    required String language,
    required String modelAssetPath,
    required int speakerId,
  }) async {
    // No-op on web.
  }

  @override
  Future<void> speak(
    String text, {
    bool waitForCompletion = true,
    void Function()? onStarted,
    SpeechProsody prosody = SpeechProsody.standard,
  }) async {
    // No-op — caller falls through to system TTS.
  }

  @override
  Future<void> speakNonBlocking(
    String text, {
    SpeechProsody prosody = SpeechProsody.standard,
  }) async {
    // No-op.
  }

  @override
  Future<void> stop() async {
    // No-op.
  }

  @override
  void setActiveLanguage(String language) {
    // No-op.
  }

  @override
  bool hasModel(String language) => false;

  @override
  Future<void> dispose(String language) async {
    // No-op.
  }
}
