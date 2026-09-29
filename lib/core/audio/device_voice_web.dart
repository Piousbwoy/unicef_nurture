import 'dart:js_interop';
import 'package:flutter_tts/flutter_tts.dart';

@JS('CareBridgeOfflineVoice.voices')
external JSPromise<JSAny?> _voices();

Future<dynamic> offlineDeviceVoices(FlutterTts tts) async {
  try {
    final voices = (await _voices().toDart)?.dartify();
    if (voices is List && voices.isNotEmpty) return voices;
  } catch (_) {
    // An absent or failed bridge does not imply an absent device voice.
  }
  // Keep metadata unchanged: the caller still decides what is safe to use.
  return tts.getVoices;
}

// flutter_tts web configuration/stop methods return void. Playback still needs
// both invocation success and the matching start/completion callbacks.
bool deviceCommandAccepted(dynamic value) =>
    value == null || value == 1 || value == true;
