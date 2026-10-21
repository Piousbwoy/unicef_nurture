import 'native_pack_store.dart';

class VoicePackInstaller {
  final _store = NativePackStore();
  bool get downloadable => _store.downloadOrigin != null;
  Future<bool> shellReady() async => true;
  Future<bool> installShell() async => true;
  Future<bool> installed(String language, {bool translation = false}) async {
    if (!['Twi', 'Hausa', 'Dagbani'].contains(language)) return false;
    return _store.installed(NativePackStore.base(language, translation));
  }

  Future<void> install(
    String language, {
    bool translation = false,
    required void Function(int, int) progress,
  }) async {
    await _store.install(NativePackStore.base(language, translation), progress);
  }

  /// A recogniser is installed the same way a voice is, and refuses to be
  /// smaller than the store's ceiling: 355 MB is a decision made on a screen,
  /// not one the app takes silently while someone is filling in a form.
  Future<bool> speechInstalled(String language) async =>
      _store.installed(NativePackStore.asrBase(language));

  Future<void> installSpeech(
    String language, {
    required void Function(int, int) progress,
  }) async {
    await _store.install(NativePackStore.asrBase(language), progress);
  }

  void cancel() => _store.cancel();
}
