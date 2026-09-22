import 'dart:js_interop';
import 'package:flutter_tts/flutter_tts.dart';

@JS('CareBridgeOfflineVoice.voices')
external JSPromise<JSAny?> _voices();

Future<dynamic> offlineDeviceVoices(FlutterTts tts) async =>
    (await _voices().toDart)?.dartify();
// flutter_tts web configuration/stop methods return void. Playback still needs
// both invocation success and the matching start/completion callbacks.
bool deviceCommandAccepted(dynamic value) =>
    value == null || value == 1 || value == true;
