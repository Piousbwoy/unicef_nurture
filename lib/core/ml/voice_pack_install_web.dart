import 'dart:js_interop';
import 'voice_web_bridge.dart';

@JS('CareBridgeOfflineVoice.installShell')
external JSPromise<JSBoolean> _installShell();
@JS('CareBridgeOfflineVoice.shellStatus')
external JSPromise<JSBoolean> _shellStatus();

class VoicePackInstaller {
  VoiceWebTask? _installation;
  bool get downloadable => true;
  Future<bool> shellReady() async {
    try {
      return (await _shellStatus().toDart).toDart;
    } catch (_) {
      return false;
    }
  }

  Future<bool> installShell() async => (await _installShell().toDart).toDart;
  String _base(String language, bool translation) {
    if (!['Twi', 'Hausa'].contains(language)) {
      throw ArgumentError('Unsupported language');
    }
    return translation
        ? 'assets/assets/models/translation_${language.toLowerCase()}'
        : 'assets/assets/tts/${language.toLowerCase()}_piper';
  }

  Future<bool> installed(String language, {bool translation = false}) async {
    try {
      final result =
          (await VoiceWebBridge.call('status', {
                'base': _base(language, translation),
              }))!.dartify()
              as Map;
      return result['integrityReady'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> install(
    String language, {
    bool translation = false,
    required void Function(int, int) progress,
  }) async {
    if (_installation != null) throw StateError('Installation already active');
    final task = VoiceWebBridge.start('install', {
      'base': _base(language, translation),
    }, progress: progress);
    _installation = task;
    try {
      await task.result;
    } finally {
      if (identical(_installation, task)) _installation = null;
    }
  }

  void cancel() => _installation?.cancel();
}
