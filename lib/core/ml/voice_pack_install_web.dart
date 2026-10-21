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
    if (translation && !['Twi', 'Hausa'].contains(language)) {
      throw ArgumentError('Unsupported language');
    }
    if (!['Twi', 'Hausa', 'Dagbani'].contains(language)) {
      throw ArgumentError('Unsupported language');
    }
    return translation
        ? 'assets/assets/models/translation_${language.toLowerCase()}'
        : 'assets/assets/tts/${language.toLowerCase()}_piper';
  }

  static String _asrBase(String language) {
    if (!['Twi', 'Dagbani'].contains(language)) {
      throw ArgumentError('Unsupported language');
    }
    return 'assets/assets/asr/${language.toLowerCase()}';
  }

  Future<bool> installed(String language, {bool translation = false}) =>
      _statusFor(_base(language, translation));

  /// A recogniser is browser-cached the same way a voice is, under the same
  /// integrity check — and 355 MB is why the button that calls this is on a
  /// diagnostics screen and says how big it is, not on the check flow.
  Future<bool> speechInstalled(String language) =>
      _statusFor(_asrBase(language));

  Future<bool> _statusFor(String base) async {
    try {
      final result =
          (await VoiceWebBridge.call('status', {
                'base': base,
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
  }) => _installBase(_base(language, translation), progress);

  Future<void> installSpeech(
    String language, {
    required void Function(int, int) progress,
  }) => _installBase(_asrBase(language), progress);

  Future<void> _installBase(
    String base,
    void Function(int, int) progress,
  ) async {
    if (_installation != null) throw StateError('Installation already active');
    final task = VoiceWebBridge.start(
      'install',
      {'base': base},
      progress: progress,
    );
    _installation = task;
    try {
      await task.result;
    } finally {
      if (identical(_installation, task)) _installation = null;
    }
  }

  void cancel() => _installation?.cancel();
}
