import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:carebridge_ai/core/audio/audio_guide.dart';
import 'package:carebridge_ai/core/audio/caregiver_playback.dart';
import 'package:carebridge_ai/core/audio/voice_service.dart';
import 'package:carebridge_ai/core/i18n/speech_bank.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';

const _ids = ['nurse_intro', 'q_newborn.feed', 'nurse_close'];
String _english(List<String> ids) =>
    ids.map((id) => SpeechBank.byId(id)!.english).join(' ');
CaregiverSpeech _speech(String language, {List<String> ids = _ids}) =>
    CaregiverSpeech(id: 'guidance', english: _english(ids), language: language, clipIds: ids);
Map<String, dynamic> _offline(String locale) =>
    {'name': '$locale-local', 'locale': locale, 'network_required': false};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('exact transcript coverage', () {
    test('preserves const single-clip API and exact equality', () {
      const speech = CaregiverSpeech(
        id: 'q', english: 'Not breastfeeding or feeding well',
        language: 'Dagbani', clipId: 'q_newborn.feed',
      );
      expect(speech.matchingClip, SpeechBank.qNewbornFeed);
      expect(speech.matchingClips, [SpeechBank.qNewbornFeed]);
      const spaced = CaregiverSpeech(
        id: 'q', english: 'Not breastfeeding  or feeding well',
        language: 'Dagbani', clipId: 'q_newborn.feed',
      );
      expect(spaced.matchingClip, isNull);
      expect(spaced.matchingClips, [SpeechBank.qNewbornFeed]);
    });

    test('sequences cover every word; only whitespace can differ', () {
      final speech = CaregiverSpeech(
        id: 'sequence', english: '  ${_english(_ids).replaceAll(' ', '\n ')}  ',
        language: 'dag', clipIds: _ids,
      );
      expect(speech.matchingClips!.map((c) => c.id), _ids);
      expect(speech.localizedText, SpeechBank.scriptFor(language: 'Dagbani', ids: _ids));
      expect(speech.hasTranslation, isTrue);
      for (final changed in [
        '${_english(_ids)} Give medicine.',
        _english(_ids).replaceAll('Not breastfeeding', 'Breastfeeding'),
        _english(_ids).toLowerCase(),
        'Ama: ${_english(_ids)}',
      ]) {
        final altered = CaregiverSpeech(
          id: 'sequence', english: changed, language: 'Twi', clipIds: _ids,
        );
        expect(altered.matchingClips, isNull);
        expect(altered.hasTranslation, isFalse);
      }
    });

    test('rejects absent, empty, missing, reordered and partial ids', () {
      for (final ids in <List<String>?>[
        null, [], ['not-in-bank'], ['nurse_intro'], _ids.reversed.toList(),
        ['nurse_intro', 'missing', 'nurse_close'],
      ]) {
        expect(CaregiverSpeech(
          id: 'nurse_intro', english: _english(_ids), language: 'Hausa', clipIds: ids,
        ).matchingClips, isNull);
      }
      const overridden = CaregiverSpeech(
        id: 'q', english: 'Not breastfeeding or feeding well',
        language: 'Twi', clipId: 'q_newborn.feed', clipIds: [],
      );
      expect(overridden.matchingClip, isNotNull);
      expect(overridden.matchingClips, isNull);
      expect(overridden.localizedText, isNull);
    });

    test('withLanguage retains all metadata and English remains exact', () {
      const original = CaregiverSpeech(
        id: 'q', english: 'Not breastfeeding or feeding well',
        language: 'Dagbani', clipId: 'q_newborn.feed', clipIds: ['q_newborn.feed'],
      );
      for (final language in OfflineSpeechLanguage.names) {
        final changed = original.withLanguage(language);
        expect(changed.id, original.id);
        expect(changed.english, original.english);
        expect(changed.clipId, original.clipId);
        expect(changed.clipIds, same(original.clipIds));
        expect(changed.localizedText, language == 'English'
            ? original.english : SpeechBank.qNewbornFeed.textFor(language));
      }
      expect(original.withLanguage('en-GB').localizedText, original.english);
      expect(original.withLanguage('French').hasTranslation, isFalse);
      expect(const CaregiverSpeech(id: 'free', english: 'Exact  English.', language: 'en')
          .localizedText, 'Exact  English.');
    });
  });

  group('offline language identity', () {
    test('canonical names and aliases never bridge languages', () {
      expect(OfflineSpeechLanguage.names, ['English', 'Twi', 'Dagbani', 'Hausa']);
      for (final entry in {
        'EN': 'English', 'en-NG': 'English', 'English': 'English',
        'tw': 'Twi', 'TWI': 'Twi', 'dag': 'Dagbani', 'Dagbani': 'Dagbani',
        'ha': 'Hausa', 'HAUSA': 'Hausa', 'Gurene': 'Gurene',
        'english-like': 'english-like', 'dagger': 'dagger',
      }.entries) {
        expect(OfflineSpeechLanguage.canonical(entry.key), entry.value);
      }
      expect(OfflineSpeechLanguage.deviceVoice('Dagbani', [
        _offline('ha-NG'), _offline('en-GH'), _offline('dagger-GH'),
      ]), isNull);
      expect(OfflineSpeechLanguage.deviceVoice('Dagbani', [_offline('dag-GH')]),
          {'name': 'dag-GH-local', 'locale': 'dag-GH'});
      expect(OfflineSpeechLanguage.deviceVoice('Twi', [_offline('ak-GH')]), isNotNull);
      expect(OfflineSpeechLanguage.deviceVoice('Unknown', [_offline('en-US')]), isNull);
    });

    test('requires explicit offline evidence and rejects conflicting flags', () {
      for (final flags in <Map<String, dynamic>>[
        {}, {'network_required': true}, {'network_required': 'true'},
        {'localService': false}, {'localService': 'false'},
        {'network_required': 'unknown'}, {'network_required': null},
        {'network_required': false, 'localService': false},
        {'network_required': true, 'localService': true},
      ]) {
        expect(OfflineSpeechLanguage.deviceVoice('English', [
          {'name': 'voice', 'locale': 'en-US', ...flags},
        ]), isNull, reason: '$flags');
      }
      for (final flags in <Map<String, dynamic>>[
        {'network_required': false}, {'network_required': 'false'},
        {'network_required': ' FALSE '}, {'localService': true},
        {'localService': 'true'},
      ]) {
        expect(OfflineSpeechLanguage.deviceVoice('English', [
          {'name': 'voice', 'locale': 'en-US', ...flags},
        ]), {'name': 'voice', 'locale': 'en-US'});
      }
      expect(OfflineSpeechLanguage.deviceVoice('English', [
        null, 'en-US', {'locale': 'en-US', 'network_required': false},
        {'name': '', 'locale': 'en-US', 'network_required': false},
      ]), isNull);
    });
  });

  group('device playback', () {
    test('untranslated guidance tries English device TTS before giving up', () async {
      final harness = _Harness();
      addTearDown(harness.voice.dispose);
      final events = <CaregiverPlayback>[];
      await harness.voice.play(const CaregiverSpeech(
        id: 'level_urgent', english: 'Amina needs a new assessment today.',
        language: 'Dagbani', clipId: 'level_urgent',
      ), events.add);
      // English TTS fallback creates the TTS instance but no voices are
      // available, so it still falls back to readable text.
      expect(harness.ttsCreated, 1);
      expect(events.last.phase, CaregiverPlaybackPhase.fallback);
      expect(events.last.language, 'English');
      expect(events.last.transcript, 'Amina needs a new assessment today.');
      expect(events.last.reasonCode, 'translation_fallback_english');
    });

    for (final language in ['Dagbani', 'Hausa', 'Twi']) {
      test('$language sequence waits for every completion with full transcript', () async {
        final players = List.generate(_ids.length, (_) => _FakePlayer());
        final harness = _Harness(players: players);
        addTearDown(harness.voice.dispose);
        final events = <CaregiverPlayback>[];
        var finished = false;
        final playback = harness.voice.play(_speech(language), events.add)
            .then((_) => finished = true);
        for (var i = 0; i < players.length; i++) {
          await players[i].resumed.future;
          expect(harness.assets.loaded.length, _ids.length);
          expect(harness.playersCreated, i + 1);
          expect(finished, isFalse);
          expect(events.any((e) => e.phase == CaregiverPlaybackPhase.completed), isFalse);
          expect((players[i].source as AssetSource).path,
              'audio/${SpeechBank.folderFor(language)}/${_ids[i]}.wav');
          players[i].completeClip();
        }
        await playback;
        expect(events.last.phase, CaregiverPlaybackPhase.completed);
        expect(events.every((e) => e.language == language), isTrue);
        expect(events.every((e) => e.transcript == SpeechBank.scriptFor(
          language: language, ids: _ids,
        )), isTrue);
        expect(events.last.source, contains('draft translation'));
        expect(harness.ttsCreated, 0);
      });
    }

    test('completion emitted synchronously by start is not lost', () async {
      final harness = _Harness(players: [_FakePlayer()..autoComplete = true]);
      addTearDown(harness.voice.dispose);
      final events = <CaregiverPlayback>[];
      await harness.voice.play(_speech('Twi', ids: ['nurse_close']), events.add);
      expect(events.last.phase, CaregiverPlaybackPhase.completed);
    });

    test('missing second asset prevents even the first clip from starting', () async {
      final harness = _Harness();
      harness.assets.missing.add('assets/audio/dagbani_mms/q_newborn.feed.wav');
      addTearDown(harness.voice.dispose);
      final events = <CaregiverPlayback>[];
      await harness.voice.play(_speech('Dagbani'), events.add);
      expect(harness.playersCreated, 0);
      expect(events.last.phase, CaregiverPlaybackPhase.fallback);
      expect(events.last.language, 'Dagbani');
      expect(events.last.transcript, _speech('Dagbani').localizedText);
    });

    test('Dagbani with translation but no voice falls back to readable text', () async {
      final harness = _Harness()..assets.failAll = true;
      harness.tts.voices = [_offline('ha-NG'), _offline('en-GB')];
      addTearDown(harness.voice.dispose);
      final events = <CaregiverPlayback>[];
      await harness.voice.play(_speech('Dagbani'), events.add);
      // Translation succeeds (SpeechBank provides Dagbani text) but no
      // Dagbani device voice exists. Hausa/English voices are not used for
      // Dagbani text — the readable text is shown instead.
      expect(harness.tts.utterances, isEmpty);
      expect(events.last.language, 'Dagbani');
      expect(events.last.source, contains('draft translation'));
      expect(events.last.phase, CaregiverPlaybackPhase.fallback);
    });

    test('voice enumeration exceptions give a readable localized fallback', () async {
      final harness = _Harness()..assets.failAll = true;
      harness.tts.enumerationError = true;
      addTearDown(harness.voice.dispose);
      final events = <CaregiverPlayback>[];
      await harness.voice.play(_speech('Hausa'), events.add);
      expect(events.last.phase, CaregiverPlaybackPhase.fallback);
      expect(events.last.language, 'Hausa');
      expect(events.last.transcript, _speech('Hausa').localizedText);
      expect(harness.tts.utterances, isEmpty);
    });

    for (final pair in {'English': 'en-GH', 'Twi': 'tw-GH', 'Dagbani': 'dag-GH', 'Hausa': 'ha-NG'}.entries) {
      test('${pair.key} TTS uses only its localized text and selected offline voice', () async {
        final harness = _Harness()..assets.failAll = true;
        harness.tts.voices = [
          {'name': 'online', 'locale': pair.value, 'network_required': true},
          _offline(pair.value),
        ];
        harness.tts.autoComplete = true;
        addTearDown(harness.voice.dispose);
        final events = <CaregiverPlayback>[];
        await harness.voice.play(_speech(pair.key), events.add);
        expect(harness.tts.locales, [pair.value]);
        expect(harness.tts.selectedVoices, [{'name': '${pair.value}-local', 'locale': pair.value}]);
        expect(harness.tts.commands.take(2), ['setLanguage', 'setVoice']);
        expect(harness.tts.utterances.single.text, _speech(pair.key).localizedText);
        if (pair.key != 'English') {
          expect(harness.tts.utterances.single.text, isNot(_english(_ids)));
        }
        expect(events.last.phase, CaregiverPlaybackPhase.completed);
        expect(events.last.language, pair.key);
        expect(events.last.source, contains('offline device speech'));
      });
    }

    test('failed voice configuration does not start speech', () async {
      final harness = _Harness()..assets.failAll = true;
      harness.tts.voices = [_offline('tw-GH')];
      harness.tts.voiceResult = 0;
      addTearDown(harness.voice.dispose);
      final events = <CaregiverPlayback>[];
      await harness.voice.play(_speech('Twi'), events.add);
      expect(harness.tts.utterances, isEmpty);
      expect(events.last.phase, CaregiverPlaybackPhase.fallback);
    });

    for (final failure in ['error', 'cancel', 'timeout']) {
      test('TTS $failure is never reported as completion', () async {
        final harness = _Harness(playbackTimeout: const Duration(milliseconds: 30));
        harness.assets.failAll = true;
        harness.tts.voices = [_offline('ha-NG')];
        addTearDown(harness.voice.dispose);
        final events = <CaregiverPlayback>[];
        final playback = harness.voice.play(_speech('Hausa'), events.add);
        await harness.tts.spoken.future;
        final utterance = harness.tts.utterances.single;
        if (failure == 'error') utterance.error('engine failure');
        if (failure == 'cancel') utterance.cancel();
        await playback;
        expect(events.last.phase, CaregiverPlaybackPhase.fallback);
        expect(events.any((e) => e.phase == CaregiverPlaybackPhase.completed), isFalse);
        expect(harness.tts.stops, greaterThan(0));
      });
    }

    test('a failing second clip never reports partial success', () async {
      final harness = _Harness(players: [
        _FakePlayer()..autoComplete = true,
        _FakePlayer()..resumeError = true,
      ]);
      addTearDown(harness.voice.dispose);
      final events = <CaregiverPlayback>[];
      await harness.voice.play(_speech('Dagbani', ids: _ids.take(2).toList()), events.add);
      expect(harness.playersCreated, 2);
      expect(events.last.phase, CaregiverPlaybackPhase.fallback);
      expect(events.any((e) => e.phase == CaregiverPlaybackPhase.completed), isFalse);
    });

    test('audio stream errors and timeouts cannot complete a sequence', () async {
      for (final streamError in [true, false]) {
        final player = _FakePlayer();
        final harness = _Harness(players: [player], playbackTimeout: const Duration(milliseconds: 30));
        final events = <CaregiverPlayback>[];
        final playback = harness.voice.play(_speech('Twi', ids: ['nurse_intro']), events.add);
        await player.resumed.future;
        if (streamError) player.completions.addError(StateError('player failure'));
        await playback;
        expect(events.last.phase, CaregiverPlaybackPhase.fallback);
        expect(events.any((e) => e.phase == CaregiverPlaybackPhase.completed), isFalse);
        await harness.voice.dispose();
      }
    });

    test('stopped asset and player loads cannot revive playback', () async {
      for (final blockAsset in [true, false]) {
        final player = _FakePlayer()..sourceGate = Completer<void>();
        final harness = _Harness(players: [player]);
        if (blockAsset) harness.assets.gate = Completer<void>();
        final events = <CaregiverPlayback>[];
        final playback = harness.voice.play(_speech('Dagbani'), events.add);
        await (blockAsset ? harness.assets.requested.future : player.preparing.future);
        await harness.voice.stop();
        await playback;
        if (blockAsset) harness.assets.gate!.complete();
        player.sourceGate!.complete();
        await Future<void>.delayed(Duration.zero);
        expect(player.resumes, 0);
        expect(events.last.phase, CaregiverPlaybackPhase.stopped);
        expect(harness.tts.utterances, isEmpty);
        await harness.voice.dispose();
      }
    });

    test('new owner stops old speech and old callbacks cannot complete new speech', () async {
      // Share the TTS object just as the real plugin's single method channel is shared.
      final tts = _FakeTts()..voices = [_offline('en-GH')];
      final old = _Harness(tts: tts);
      final next = _Harness(tts: tts);
      addTearDown(old.voice.dispose);
      addTearDown(next.voice.dispose);
      final oldEvents = <CaregiverPlayback>[];
      final nextEvents = <CaregiverPlayback>[];
      final oldPlayback = old.voice.play(const CaregiverSpeech(
        id: 'old', english: 'Old owner guidance.', language: 'English',
      ), oldEvents.add);
      await tts.spoken.future;
      final stale = tts.utterances.single;
      tts.spoken = Completer<void>();
      final nextPlayback = next.voice.play(const CaregiverSpeech(
        id: 'next', english: 'New owner guidance.', language: 'English',
      ), nextEvents.add);
      await tts.spoken.future;
      await oldPlayback;
      expect(oldEvents.last.phase, CaregiverPlaybackPhase.stopped);
      final oldCount = oldEvents.length;
      final stopCount = tts.stops;
      await old.voice.stop();
      expect(tts.stops, stopCount, reason: 'An old owner must not stop new audio');
      stale.start();
      stale.complete();
      stale.error('late old error');
      await Future<void>.delayed(Duration.zero);
      expect(oldEvents.length, oldCount);
      expect(nextEvents.last.phase, CaregiverPlaybackPhase.playing);
      expect(nextEvents.every((e) => e.transcript == 'New owner guidance.'), isTrue);
      tts.utterances.last.complete();
      await nextPlayback;
      expect(nextEvents.last.phase, CaregiverPlaybackPhase.completed);
    });

    test('dispose cancels speech and suppresses subsequent callbacks', () async {
      final harness = _Harness();
      harness.tts.voices = [_offline('en-US')];
      final events = <CaregiverPlayback>[];
      final playback = harness.voice.play(const CaregiverSpeech(
        id: 'dispose', english: 'Read this.', language: 'English',
      ), events.add);
      await harness.tts.spoken.future;
      await harness.voice.dispose();
      await playback;
      final count = events.length;
      harness.tts.utterances.single.complete();
      await harness.voice.play(_speech('English'), events.add);
      expect(events.length, count);
      expect(events.last.phase, CaregiverPlaybackPhase.stopped);
    });
  });

  group('VoiceService strict adapter with plugin failures', () {
    const channel = MethodChannel('flutter_tts');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late List<MethodCall> calls;
    late List<String> assetLoads;

    setUp(() {
      calls = [];
      assetLoads = [];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'getVoices' || call.method == 'getLanguages') {
          throw PlatformException(code: 'unavailable');
        }
        return 1;
      });
      messenger.setMockMessageHandler('flutter/assets', (message) async {
        assetLoads.add(const StringCodec().decodeMessage(message)!);
        return null;
      });
    });
    tearDown(() async {
      await VoiceService.stop();
      messenger.setMockMethodCallHandler(channel, null);
      messenger.setMockMessageHandler('flutter/assets', null);
    });

    test('arbitrary text cannot borrow a named bank clip', () async {
      final events = <CaregiverPlayback>[];
      final outcome = await VoiceService.speak(const VoiceRequest(
        id: 'level_urgent', preferredLanguage: 'Dagbani',
        preferredScript: 'A different clinical recommendation.',
        bridgeScript: 'Do not speak this bridge.',
      ), onPlayback: events.add);
      expect(outcome.source, VoiceSource.readAloud);
      expect(outcome.spokenScript, 'A different clinical recommendation.');
      expect(outcome.actualLanguage, 'English');
      expect(events.last.phase, CaregiverPlaybackPhase.fallback);
      expect(assetLoads, isEmpty);
      expect(calls.where((c) => c.method != 'stop'), isEmpty);
    });

    test('id candidate accepts only exact English or selected translation', () async {
      for (final text in [SpeechBank.levelUrgent.english, SpeechBank.levelUrgent.dagbani]) {
        final outcome = await VoiceService.speak(VoiceRequest(
          id: 'level_urgent', preferredLanguage: 'Dagbani', preferredScript: text,
        ));
        expect(outcome.source, VoiceSource.readAloud);
        expect(outcome.spokenScript, SpeechBank.levelUrgent.dagbani);
        expect(outcome.actualLanguage, 'Dagbani');
      }
      expect(assetLoads, everyElement('assets/audio/dagbani_mms/level_urgent.wav'));
      expect(assetLoads, hasLength(2));
      expect(calls.any((c) => c.method == 'speak'), isFalse);
    });

    test('explicit sequence cannot substitute partial or changed guidance', () async {
      final translated = SpeechBank.scriptFor(language: 'Twi', ids: _ids)!;
      for (final text in [_english(_ids), translated]) {
        final outcome = await VoiceService.speak(VoiceRequest(
          id: 'sequence', preferredLanguage: 'Twi', preferredScript: text, bankClips: _ids,
        ));
        expect(outcome.spokenScript, translated);
        expect(outcome.actualLanguage, 'Twi');
        expect(outcome.source, VoiceSource.readAloud);
      }
      final before = assetLoads.length;
      final outcome = await VoiceService.speak(VoiceRequest(
        id: 'sequence', preferredLanguage: 'Twi',
        preferredScript: '${_english(_ids)} Give extra medicine.', bankClips: _ids,
      ));
      expect(outcome.actualLanguage, 'English');
      expect(assetLoads.length, before);
    });

    test('speakText English cannot be spoken using a non-English voice', () async {
      final outcome = await VoiceService.speakText(
        id: 'open', text: 'A new personalized recommendation.', language: 'Hausa',
      );
      expect(outcome.source, VoiceSource.readAloud);
      expect(outcome.actualLanguage, 'English');
      expect(calls.any((c) => c.method == 'speak'), isFalse);
    });

    test('diagnostics catches plugin errors once and reports installed locales', () async {
      expect(await VoiceService.availableTtsLanguages(), isEmpty);
      expect(calls.where((c) => c.method == 'getLanguages'), hasLength(1));
      messenger.setMockMethodCallHandler(channel, (call) async =>
          call.method == 'getLanguages' ? ['en-GH', 'ha-NG', 'en-GH'] : 1);
      expect(await VoiceService.availableTtsLanguages(), ['en-GH', 'ha-NG']);
    });

    test('no studio recording is claimed without a verified manifest', () {
      for (final topic in AudioTopic.values) {
        for (final language in OfflineSpeechLanguage.names) {
          expect(VoiceService.hasRecording(topic, language), isFalse);
        }
      }
      expect(VoiceSource.linguaFranca.labelFor('Dagbani'), 'Hausa bridge');
    });
  });
}

class _Harness {
  _Harness({List<_FakePlayer>? players, _FakeTts? tts, Duration? playbackTimeout})
      : players = players ?? [], tts = tts ?? _FakeTts() {
    voice = DeviceCaregiverVoice(
      assets: assets,
      playerFactory: () {
        final index = playersCreated++;
        return this.players[index];
      },
      ttsFactory: () { ttsCreated++; return this.tts; },
      operationTimeout: const Duration(seconds: 2),
      playbackTimeout: playbackTimeout ?? const Duration(seconds: 2),
    );
  }
  final List<_FakePlayer> players;
  final _FakeTts tts;
  final assets = _FakeAssets();
  late final DeviceCaregiverVoice voice;
  int playersCreated = 0;
  int ttsCreated = 0;
}

class _FakeAssets extends CachingAssetBundle {
  final loaded = <String>[];
  final missing = <String>{};
  final requested = Completer<void>();
  Completer<void>? gate;
  bool failAll = false;

  @override
  Future<ByteData> load(String key) async {
    loaded.add(key);
    if (!requested.isCompleted) requested.complete();
    await gate?.future;
    if (failAll || missing.contains(key)) throw StateError('Missing asset');
    return ByteData.sublistView(Uint8List.fromList([1, 2, 3]));
  }
}

class _FakePlayer implements AudioPlayer {
  final completions = StreamController<void>.broadcast(sync: true);
  final states = StreamController<PlayerState>.broadcast(sync: true);
  final resumed = Completer<void>();
  final preparing = Completer<void>();
  Completer<void>? sourceGate;
  bool autoComplete = false;
  bool resumeError = false;
  bool disposed = false;
  int resumes = 0;
  @override
  Source? source;
  @override
  Stream<void> get onPlayerComplete => completions.stream;
  @override
  Stream<PlayerState> get onPlayerStateChanged => states.stream;
  @override
  Future<void> setSource(Source value) async {
    source = value;
    preparing.complete();
    await sourceGate?.future;
  }
  @override
  Future<void> resume() async {
    resumes++;
    resumed.complete();
    if (resumeError) throw StateError('Failed second clip');
    states.add(PlayerState.playing);
    if (autoComplete) completeClip();
  }
  void completeClip() => completions.add(null);
  @override
  Future<void> stop() async {
    if (!disposed) states.add(PlayerState.stopped);
  }
  @override
  Future<void> dispose() async {
    if (disposed) return;
    disposed = true;
    await completions.close();
    await states.close();
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Utterance {
  _Utterance(this.text, this.start, this.completion, this.error, this.cancel);
  final String text;
  final void Function() start;
  final void Function() completion;
  final void Function(dynamic) error;
  final void Function() cancel;
  final result = Completer<dynamic>();
  void complete() {
    completion();
    if (!result.isCompleted) result.complete(1);
  }
}

class _FakeTts implements FlutterTts {
  List<dynamic> voices = [];
  bool enumerationError = false;
  bool autoComplete = false;
  dynamic voiceResult = 1;
  final locales = <String>[];
  final selectedVoices = <Map<String, String>>[];
  final commands = <String>[];
  final utterances = <_Utterance>[];
  Completer<void> spoken = Completer<void>();
  int stops = 0;
  void Function() _start = () {};
  void Function() _completion = () {};
  void Function(dynamic) _error = (_) {};
  void Function() _cancel = () {};

  @override
  Future<dynamic> get getVoices async {
    if (enumerationError) throw PlatformException(code: 'enumeration');
    return voices;
  }
  @override
  Future<dynamic> setLanguage(String language) async {
    commands.add('setLanguage');
    locales.add(language);
    return 1;
  }
  @override
  Future<dynamic> setVoice(Map<String, String> voice) async {
    commands.add('setVoice');
    selectedVoices.add(voice);
    return voiceResult;
  }
  @override
  Future<dynamic> setSpeechRate(double rate) async => 1;
  @override
  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion) async {
    expect(awaitCompletion, isTrue);
    return 1;
  }
  @override
  Future<dynamic> speak(String text, {bool focus = false}) {
    final utterance = _Utterance(text, _start, _completion, _error, _cancel);
    utterances.add(utterance);
    _start();
    if (!spoken.isCompleted) spoken.complete();
    if (autoComplete) utterance.complete();
    return utterance.result.future;
  }
  @override
  Future<dynamic> stop() async { stops++; return 1; }
  @override
  void setStartHandler(void Function() callback) => _start = callback;
  @override
  void setCompletionHandler(void Function() callback) => _completion = callback;
  @override
  void setErrorHandler(ErrorHandler handler) => _error = handler;
  @override
  void setCancelHandler(void Function() callback) => _cancel = callback;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
