@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:carebridge_ai/core/audio/device_voice_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';

void main() {
  final bridgeKey = 'CareBridgeOfflineVoice'.toJS;
  JSAny? original;

  setUp(() {
    original = globalContext.getProperty<JSAny?>(bridgeKey);
  });
  tearDown(() {
    globalContext.setProperty(bridgeKey, original);
  });

  void bridge(Future<JSAny?> Function() voices) {
    final value = JSObject();
    value.setProperty('voices'.toJS, (() => voices().toJS).toJS);
    globalContext.setProperty(bridgeKey, value);
  }

  test('missing bridge still enumerates plugin voices', () async {
    globalContext.setProperty(bridgeKey, null);
    expect(await offlineDeviceVoices(_DeviceVoices()), [
      {'name': 'Installed voice', 'locale': 'en-GH'},
    ]);
  });

  test('bridge rejection still enumerates plugin voices', () async {
    bridge(() => Future<JSAny?>.error(StateError('Bridge unavailable')));
    expect(await offlineDeviceVoices(_DeviceVoices()), [
      {'name': 'Installed voice', 'locale': 'en-GH'},
    ]);
  });

  test(
    'bridge retains local and network metadata without plugin substitution',
    () async {
      final voices = [
        {'name': 'Local', 'locale': 'en-GB', 'localService': true},
        {'name': 'Remote', 'locale': 'en-GH', 'localService': false},
      ];
      bridge(() async => voices.jsify());
      expect(await offlineDeviceVoices(_DeviceVoices()), voices);
    },
  );

  test('empty or malformed bridge results try the plugin', () async {
    for (final value in [
      <Object>[],
      {'unexpected': true},
      null,
    ]) {
      bridge(() async => value.jsify());
      expect(await offlineDeviceVoices(_DeviceVoices()), [
        {'name': 'Installed voice', 'locale': 'en-GH'},
      ]);
    }
  });

  test('plugin failure remains a failure, never an invented voice', () async {
    globalContext.setProperty(bridgeKey, null);
    await expectLater(
      offlineDeviceVoices(_DeviceVoices(fail: true)),
      throwsStateError,
    );
  });
}

class _DeviceVoices implements FlutterTts {
  _DeviceVoices({this.fail = false});
  final bool fail;

  @override
  Future<dynamic> get getVoices async {
    if (fail) throw StateError('No speech engine');
    return [
      {'name': 'Installed voice', 'locale': 'en-GH'},
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
