import 'package:flutter_tts/flutter_tts.dart';

Future<dynamic> offlineDeviceVoices(FlutterTts tts) => tts.getVoices;
bool deviceCommandAccepted(dynamic value) => value == 1 || value == true;
