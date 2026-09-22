import 'native_pack_store.dart';

class VoicePackInstaller {
  final _store = NativePackStore();
  bool get downloadable => _store.downloadOrigin != null;
  Future<bool> shellReady() async => true;
  Future<bool> installShell() async => true;
  Future<bool> installed(String language, {bool translation = false}) async {
    if (!['Twi', 'Hausa'].contains(language)) return false;
    return _store.installed(NativePackStore.base(language, translation));
  }

  Future<void> install(
    String language, {
    bool translation = false,
    required void Function(int, int) progress,
  }) async {
    await _store.install(NativePackStore.base(language, translation), progress);
  }

  void cancel() => _store.cancel();
}
