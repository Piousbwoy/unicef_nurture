import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

@JS('CareBridgeOfflineVoice.available')
external JSBoolean _available();
@JS('CareBridgeOfflineVoice.request')
external JSPromise<JSAny?> _request(
  JSNumber id,
  JSString operation,
  JSAny? args,
  JSFunction? progress,
);
@JS('CareBridgeOfflineVoice.cancel')
external void _cancel(JSNumber id);
@JS('CareBridgeOfflineVoice.playAudio')
external JSPromise<JSBoolean> _play(
  JSFloat32Array samples,
  JSNumber rate,
  JSFunction started,
);
@JS('CareBridgeOfflineVoice.stopAudio')
external void _stop();

class VoiceWebTask {
  VoiceWebTask(this.id, this.result);
  final int id;
  final Future<JSAny?> result;
  void cancel() => _cancel(id.toJS);
}

abstract final class VoiceWebBridge {
  static int _id = 0;
  static bool get available {
    try {
      return _available().toDart;
    } catch (_) {
      return false;
    }
  }

  static VoiceWebTask start(
    String operation,
    Map<String, Object?> args, {
    void Function(int received, int total)? progress,
  }) {
    final id = ++_id;
    final callback = progress == null
        ? null
        : ((JSAny value) {
            final data = value.dartify() as Map;
            progress(
              (data['received'] as num).toInt(),
              (data['total'] as num).toInt(),
            );
          }).toJS;
    final result = _request(
      id.toJS,
      operation.toJS,
      args.jsify(),
      callback,
    ).toDart;
    return VoiceWebTask(id, result);
  }

  static Future<JSAny?> call(String operation, Map<String, Object?> args) =>
      start(operation, args).result;
  static Future<Map> metadata(String base) async =>
      (await call('metadata', {'base': base}))!.dartify() as Map;
  static Future<Uint8List> read(String base, String name, String cache) async =>
      ((await call('read', {'base': base, 'name': name, 'cache': cache}))
              as JSUint8Array)
          .toDart;
  static Future<String> text(String base, String name, String cache) async =>
      utf8.decode(await read(base, name, cache));
  static Future<bool> play(
    Float32List samples,
    int rate,
    void Function() started,
  ) async => (await _play(samples.toJS, rate.toJS, started.toJS).toDart).toDart;
  static void stop() => _stop();
}
