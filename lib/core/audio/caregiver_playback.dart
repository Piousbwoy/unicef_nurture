import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../i18n/speech_bank.dart';
import '../ml/piper_tts_service.dart';
import '../ml/translation_service.dart';
import 'speech_content_policy.dart';

enum CaregiverPlaybackPhase { loading, playing, stopped, completed, fallback }

class CaregiverSpeech {
  const CaregiverSpeech({
    required this.id,
    required this.english,
    required this.language,
    this.clipId,
    this.clipIds,
    this.policy = SpeechContentPolicy.guidance,
  });
  final SpeechContentPolicy policy;
  final String id;
  final String english;
  final String language;
  // Only explicitly matched, unchanged bank wording is eligible for playback.
  final String? clipId;
  final List<String>? clipIds;

  BankScript? get matchingClip {
    final clip = clipId == null ? null : SpeechBank.byId(clipId!);
    return clip?.english == english ? clip : null;
  }

  List<BankScript>? get matchingClips {
    final ids = clipIds ?? (clipId == null ? null : [clipId!]);
    if (ids == null || ids.isEmpty) return null;
    final clips = <BankScript>[];
    for (final id in ids) {
      final clip = SpeechBank.byId(id);
      if (clip == null) return null;
      clips.add(clip);
    }
    String normalize(String text) => text.trim().replaceAll(RegExp(r'\s+'), ' ');
    return normalize(clips.map((clip) => clip.english).join(' ')) ==
            normalize(english)
        ? List.unmodifiable(clips)
        : null;
  }

  /// Bank translations are drafts, not clinically verified translations.
  /// Falls back to the phrase-dictionary TranslationService for pure dynamic
  /// text (no clip references). When clip IDs are specified but don't match,
  /// returns null to preserve the safety invariant.
  String? get localizedText {
    final selected = OfflineSpeechLanguage.canonical(language);
    if (selected == 'English') return english;
    if (SpeechSafety.requiresEnglish(english, policy)) return null;
    final clips = matchingClips;
    if (clips != null) {
      final parts = <String>[];
      for (final clip in clips) {
        final text = clip.textFor(selected);
        if (text == null || text.trim().isEmpty) return null;
        parts.add(text);
      }
      return parts.join(' ');
    }
    // If clip references were specified but didn't match, preserve the safety
    // invariant: don't translate. Only use TranslationService for pure dynamic
    // text with no clip references at all.
    if (clipId != null || (clipIds != null && clipIds!.isNotEmpty)) {
      return null;
    }
    // Pure dynamic text — try the phrase-dictionary translation engine.
    final result = TranslationService.instance.translate(english, selected);
    return result != null && result.coverage == 1 &&
        SpeechSafety.preservesTokens(english, result.text) ? result.text : null;
  }

  bool get hasTranslation => localizedText != null;

  CaregiverSpeech withLanguage(String language) => CaregiverSpeech(
    id: id,
    english: english,
    language: language,
    clipId: clipId,
    clipIds: clipIds,
    policy: policy,
  );
}

/// Strict language identity and explicit evidence of offline device voices.
abstract final class OfflineSpeechLanguage {
  static const names = ['English', 'Twi', 'Dagbani', 'Hausa'];

  static String canonical(String language) {
    final value = language.trim().toLowerCase().replaceAll('_', '-');
    if (value == 'english' || value == 'en' || value.startsWith('en-')) {
      return 'English';
    }
    return switch (value) {
      'tw' || 'twi' => 'Twi',
      'dag' || 'dagbani' => 'Dagbani',
      'ha' || 'hausa' => 'Hausa',
      _ => language,
    };
  }

  static bool? _flag(dynamic value) => switch (value) {
    true || 'true' => true,
    false || 'false' => false,
    _ => value is String ? switch (value.trim().toLowerCase()) {
      'true' => true,
      'false' => false,
      _ => null,
    } : null,
  };

  /// A locale or a voice name alone does not prove offline availability.
  /// Missing (including native iOS) or conflicting metadata is declined.
  static Map<String, String>? deviceVoice(String language, List<dynamic> voices) {
    final primaries = switch (canonical(language)) {
      'English' => const ['en'],
      'Twi' => const ['tw', 'ak'],
      'Dagbani' => const ['dag'],
      'Hausa' => const ['ha'],
      _ => const <String>[],
    };
    for (final primary in primaries) {
      for (final voice in voices) {
        if (voice is! Map) continue;
        final name = voice['name'];
        final locale = voice['locale'];
        if (name is! String || name.trim().isEmpty || locale is! String) {
          continue;
        }
        if (locale.trim().toLowerCase().split(RegExp('[-_]')).first != primary) {
          continue;
        }
        final local = _flag(voice['localService']);
        final network = _flag(voice['network_required']);
        if (local == false || network == true) continue;
        if (local != true && network != false) continue;
        return {'name': name, 'locale': locale};
      }
    }
    return null;
  }
}

class CaregiverPlayback {
  const CaregiverPlayback({
    required this.phase,
    required this.transcript,
    required this.language,
    required this.source,
  });
  final CaregiverPlaybackPhase phase;
  final String transcript;
  final String language;
  final String source;
}

abstract interface class CaregiverVoiceBackend {
  Future<void> play(
    CaregiverSpeech speech,
    void Function(CaregiverPlayback) event,
  );
  Future<void> stop();
  Future<void> dispose();
}

class _PlaybackRun {
  _PlaybackRun(this.generation, this.transcript, this.language, this.event);
  final int generation;
  final void Function(CaregiverPlayback) event;
  final cancel = Completer<void>();
  String transcript;
  String language;
  String provenance = '';
  String source = 'Preparing offline audio';
  bool ended = false;

  void emit(CaregiverPlaybackPhase phase) {
    if (ended) return;
    ended = phase == CaregiverPlaybackPhase.completed ||
        phase == CaregiverPlaybackPhase.fallback ||
        phase == CaregiverPlaybackPhase.stopped;
    event(CaregiverPlayback(
      phase: phase,
      transcript: transcript,
      language: language,
      source: source,
    ));
  }

  void stop() {
    if (!cancel.isCompleted) cancel.complete();
    emit(CaregiverPlaybackPhase.stopped);
  }
}

/// One device output owner, including legacy VoiceService callers. All device
/// commands share the queue; waiting for audio completion never holds it.
abstract final class _PlaybackCoordinator {
  static DeviceCaregiverVoice? current;
  static FlutterTts? tts;
  static Future<void> tail = Future.value();
  static bool quiet = true;

  static Future<void> serialize(Future<void> Function() action) {
    final result = tail.then((_) => action());
    tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}

/// Only bundled assets or explicitly offline, same-language TTS are used.
class DeviceCaregiverVoice implements CaregiverVoiceBackend {
  DeviceCaregiverVoice({
    AudioPlayer Function()? playerFactory,
    FlutterTts Function()? ttsFactory,
    AssetBundle? assets,
    TranslationService? translation,
    PiperTtsService? piper,
    this.operationTimeout = const Duration(seconds: 5),
    this.playbackTimeout = const Duration(minutes: 3),
  }) : _playerFactory = playerFactory ?? AudioPlayer.new,
       _ttsFactory = ttsFactory ?? _sharedTts,
       _assets = assets ?? rootBundle,
       _translation = translation ?? TranslationService.instance,
       _piper = piper ?? PiperTtsService.instance;

  // Factories/bundle allow focused tests without real audio hardware.
  final AudioPlayer Function() _playerFactory;
  final FlutterTts Function() _ttsFactory;
  final AssetBundle _assets;
  final TranslationService _translation;
  final PiperTtsService _piper;

  static Future<void> stopAll() =>
      _PlaybackCoordinator.current?.stop() ?? Future<void>.value();
  final Duration operationTimeout;
  final Duration playbackTimeout;
  AudioPlayer? _player;
  FlutterTts? _tts;
  _PlaybackRun? _run;
  int _generation = 0;
  bool _disposed = false;

  static FlutterTts _sharedTts() => _PlaybackCoordinator.tts ??= FlutterTts();

  bool _current(_PlaybackRun run) => !_disposed &&
      run.generation == _generation &&
      !run.cancel.isCompleted &&
      identical(_PlaybackCoordinator.current, this);

  Future<T> _wait<T>(Future<T> future, _PlaybackRun run, Duration timeout) =>
      Future.any<T>([
        future,
        run.cancel.future.then<T>((_) => throw StateError('Playback stopped')),
      ]).timeout(timeout);

  @override
  Future<void> stop() {
    _generation++;
    final run = _run;
    _run = null;
    final ownsOutput = identical(_PlaybackCoordinator.current, this);
    if (ownsOutput) _PlaybackCoordinator.current = null;
    // Queue the stop before notifying a listener that may start another request.
    final stopped = ownsOutput
        ? _PlaybackCoordinator.serialize(() async {
            _PlaybackCoordinator.quiet = await _stopDevices();
          })
        : Future<void>.value();
    run?.stop();
    return stopped;
  }

  Future<bool> _stopDevices() async {
    var quiet = true;
    try {
      await _piper.stop().timeout(operationTimeout);
    } catch (_) {
      quiet = false;
    }
    try {
      await _player?.stop().timeout(operationTimeout);
    } catch (_) {
      quiet = false;
    }
    try {
      final tts = _tts;
      if (tts != null) {
        final result = await tts.stop().timeout(operationTimeout);
        if (result != 1 && result != true) quiet = false;
      }
    } catch (_) {
      quiet = false;
    }
    return quiet;
  }

  @override
  Future<void> play(
    CaregiverSpeech speech,
    void Function(CaregiverPlayback) event,
  ) async {
    if (_disposed) return;
    final previous = _PlaybackCoordinator.current;
    final stopped = previous?.stop() ?? Future<void>.value();
    // Capture ownership before any await, including asset loads/enumeration.
    final generation = ++_generation;
    final selected = OfflineSpeechLanguage.canonical(speech.language);
    var localized = speech.matchingClips != null || selected == 'English'
        ? speech.localizedText : null;
    final run = _PlaybackRun(
      generation,
      localized ?? speech.english,
      localized == null ? 'English' : selected,
      event,
    );
    _run = run;
    _PlaybackCoordinator.current = this;
    run.emit(CaregiverPlaybackPhase.loading);
    try {
      await stopped;
      // Also wait for a stop queued by a different, superseded owner.
      await _PlaybackCoordinator.tail;
      if (!_current(run)) return;
      if (selected != 'English' &&
          SpeechSafety.requiresEnglish(speech.english, speech.policy)) {
        run.transcript = speech.english;
        run.language = 'English';
        run.source = 'English for safety: treatment, measurements and identifiers '
            'are not machine-translated. Choose English playback.';
        run.emit(CaregiverPlaybackPhase.fallback);
        return;
      }
      if (localized == null && speech.clipId == null && speech.clipIds == null) {
        final result = await _wait(
          _translation.translateAsync(speech.english, selected),
          run, operationTimeout,
        );
        if (!_current(run)) return;
        if (result != null && result.language == selected &&
            result.coverage == 1 && result.text.trim().isNotEmpty &&
            SpeechSafety.preservesTokens(speech.english, result.text)) {
          localized = result.text;
          run.transcript = result.text;
          run.language = selected;
          run.provenance = result.isNeural
              ? 'neural model draft' : 'phrase dictionary draft';
        }
      }
      if (localized == null) {
        run.source = '$selected translation is not bundled. Choose English or '
            'ask a health worker to read the guidance.';
        run.emit(CaregiverPlaybackPhase.fallback);
        return;
      }
      if (!_PlaybackCoordinator.quiet || localized.trim().isEmpty) {
        _fallback(run);
        return;
      }
      final clips = speech.matchingClips;
      final folder = SpeechBank.folderFor(selected);
      if (clips != null && folder != null) {
        final paths = [for (final clip in clips) 'audio/$folder/${clip.id}.wav'];
        try {
          // Preflight the WHOLE sequence before any audio starts.
          for (final path in paths) {
            await _wait(_assets.load('assets/$path'), run, operationTimeout);
            if (!_current(run)) return;
          }
          run.source = 'Bundled synthetic voice • draft translation';
          for (final path in paths) {
            if (!await _playClip(path, run)) {
              throw StateError('Incomplete clip sequence');
            }
            if (!_current(run)) return;
          }
          run.emit(CaregiverPlaybackPhase.completed);
          return;
        } catch (_) {
          if (!_current(run)) return;
          // Never report a partly played sequence as completed.
          var quiet = false;
          await _PlaybackCoordinator.serialize(() async {
            if (_current(run)) quiet = await _stopDevices();
          });
          if (!_current(run)) return;
          if (!quiet) {
            _fallback(run);
            return;
          }
        }
      }
      if (!_current(run)) return;

      // Piper neural TTS: native-quality speech for dynamic translated text.
      if (await _piperSpeak(run)) {
        if (_current(run)) run.emit(CaregiverPlaybackPhase.completed);
        return;
      }
      if (!_current(run)) return;

      if (!_PlaybackCoordinator.quiet) { _fallback(run); return; }
      // Device fallback requires a proven offline voice in the same language.
      if (await _synthesize(run)) {
        if (_current(run)) run.emit(CaregiverPlaybackPhase.completed);
      } else if (_current(run)) {
        await _PlaybackCoordinator.serialize(() async {
          if (_current(run)) _PlaybackCoordinator.quiet = await _stopDevices();
        });
        if (_current(run)) _fallback(run);
      }
    } catch (_) {
      if (_current(run)) {
        await _PlaybackCoordinator.serialize(() async {
          if (_current(run)) _PlaybackCoordinator.quiet = await _stopDevices();
        });
        if (_current(run)) _fallback(run);
      }
    } finally {
      if (identical(_run, run)) _run = null;
    }
  }

  void _fallback(_PlaybackRun run) {
    run.source = run.language == 'English'
        ? 'Readable text • offline audio unavailable'
        : 'Readable text • draft translation • offline audio unavailable';
    run.emit(CaregiverPlaybackPhase.fallback);
  }

  Future<bool> _playClip(String path, _PlaybackRun run) async {
    AudioPlayer? player;
    StreamSubscription<void>? completion;
    StreamSubscription<PlayerState>? states;
    final done = Completer<bool>();
    var armed = false;
    void finish(bool success) {
      if (!done.isCompleted) done.complete(success);
    }
    try {
      await _PlaybackCoordinator.serialize(() async {
        if (!_current(run)) return;
        // A separate player per clip prevents delayed prior-clip events from
        // completing the next clip or another user's request.
        final activePlayer = player = _player = _playerFactory();
        completion = activePlayer.onPlayerComplete.listen(
          (_) { if (armed && _current(run)) finish(true); },
          onError: (Object _, StackTrace _) => finish(false),
          onDone: () => finish(false),
        );
        states = activePlayer.onPlayerStateChanged.listen(
          (state) {
            if (!armed || !_current(run) || done.isCompleted) return;
            if (state == PlayerState.playing) {
              run.emit(CaregiverPlaybackPhase.playing);
            } else if (state == PlayerState.stopped ||
                state == PlayerState.disposed || state == PlayerState.paused) {
              finish(false);
            }
          },
          onError: (Object _, StackTrace _) => finish(false),
          onDone: () => finish(false),
        );
        // Loading cannot revive playback after stop: resume is a separate,
        // generation-checked command, not an async player.play(asset).
        await _wait(activePlayer.setSource(AssetSource(path)), run, operationTimeout);
        if (!_current(run)) return;
        armed = true;
        await _wait(activePlayer.resume(), run, operationTimeout);
      });
      if (!_current(run)) return false;
      return await _wait(done.future, run, playbackTimeout);
    } catch (_) {
      return false;
    } finally {
      armed = false;
      await completion?.cancel();
      await states?.cancel();
      final finishedPlayer = player;
      if (finishedPlayer != null) {
        await _PlaybackCoordinator.serialize(() async {
          try {
            await finishedPlayer.dispose().timeout(operationTimeout);
            if (identical(_player, finishedPlayer)) _player = null;
          } catch (_) {
            // Keep the reference so the next stop can retry; no TTS overlap.
            _PlaybackCoordinator.quiet = false;
          }
        });
      }
    }
  }

  /// Synthesize speech via on-device Piper VITS (native-quality Hausa/Twi).
  /// Returns true if Piper handled playback, false if caller should fall through.
  Future<bool> _piperSpeak(_PlaybackRun run) async {
    final service = _piper;
    if (!service.isConfigured(run.language)) return false;
    // Only use Piper for non-English text (dynamic translations).
    if (run.language == 'English') return false;
    final text = run.transcript;
    if (text.trim().isEmpty) return false;
    try {
      await _wait(service.initializeLanguage(run.language), run, operationTimeout);
      if (!_current(run) || !service.supportsLanguage(run.language)) return false;
      run.source = 'Piper offline voice - ${run.provenance.isEmpty ? 'bank draft translation' : run.provenance}';
      final handled = await _wait(service.speak(text, run.language,
        onStarted: () {
          if (_current(run)) run.emit(CaregiverPlaybackPhase.playing);
        },
      ), run, playbackTimeout);
      return handled && _current(run);
    } catch (_) {
      if (_current(run)) {
        await _PlaybackCoordinator.serialize(() async {
          if (_current(run)) _PlaybackCoordinator.quiet = await _stopDevices();
        });
      }
      return false;
    }
  }

  Future<bool> _synthesize(_PlaybackRun run) async {
    final failed = Completer<bool>();
    final completedEvent = Completer<void>();
    var armed = false;
    var started = false;
    Future<dynamic>? utterance;
    bool listening() => armed && _current(run) && !failed.isCompleted;
    void fail() { if (!failed.isCompleted) failed.complete(false); }
    try {
      await _PlaybackCoordinator.serialize(() async {
        if (!_current(run)) return;
        final tts = _tts ??= _ttsFactory();
        final voices = await _wait(tts.getVoices, run, operationTimeout);
        if (!_current(run)) return;
        final voice = voices is List
            ? OfflineSpeechLanguage.deviceVoice(run.language, voices)
            : null;
        if (voice == null) throw StateError('No explicitly offline voice');
        Future<void> configure(Future<dynamic> result) async {
          final accepted = await _wait(result, run, operationTimeout);
          if (!_current(run) || (accepted != 1 && accepted != true)) {
            throw StateError('Device rejected offline voice configuration');
          }
        }
        // setLanguage may reset the engine's default voice. Pin the proven
        // offline voice AFTER setting its locale, never the other way around.
        await configure(tts.setLanguage(voice['locale']!));
        await configure(tts.setVoice(voice));
        await configure(tts.setSpeechRate(0.45));
        await configure(tts.awaitSpeakCompletion(true));
        if (!_current(run)) return;
        run.source = '${run.language} offline device speech'
            '${run.language == 'English' ? '' : ' • draft translation'}';
        if (run.provenance.isNotEmpty) run.source += ' - ${run.provenance}';
        tts.setStartHandler(() {
          if (!listening()) return;
          started = true;
          run.emit(CaregiverPlaybackPhase.playing);
        });
        tts.setCompletionHandler(() {
          if (listening() && started && !completedEvent.isCompleted) {
            completedEvent.complete();
          }
        });
        tts.setErrorHandler((_) { if (listening()) fail(); });
        tts.setCancelHandler(() { if (listening()) fail(); });
        armed = true;
        // Do not hold the command queue while speaking: stop must interrupt it.
        // The invocation-bound future AND a completion event are required, so
        // an old queued callback alone cannot complete a new utterance.
        utterance = tts.speak(run.transcript);
        // Attach an error listener immediately, before leaving the queue.
        utterance = utterance!.then<dynamic>((result) => result,
            onError: (Object _, StackTrace _) { fail(); return 0; });
      });
      if (!_current(run) || utterance == null) return false;
      final success = () async {
        final accepted = await utterance!;
        if (accepted != 1 && accepted != true) return false;
        await completedEvent.future;
        return _current(run);
      }();
      return await _wait(Future.any([success, failed.future]), run, playbackTimeout);
    } catch (_) {
      return false;
    } finally {
      // Captured handlers from an older request can no longer emit events.
      armed = false;
    }
  }

  /// Diagnostic engine-reported locales, not proof of an offline voice.
  Future<List<String>> availableTtsLanguages() async {
    try {
      final languages = await (_tts ??= _ttsFactory()).getLanguages.timeout(operationTimeout);
      return languages is List
          ? languages.whereType<String>().where((s) => s.trim().isNotEmpty).toSet().toList()
          : [];
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
    final player = _player;
    _player = null;
    if (player != null) {
      await _PlaybackCoordinator.serialize(() async {
        try { await player.dispose().timeout(operationTimeout); } catch (_) {
          // Disposal must not throw into a controller's lifecycle callback.
        }
      });
    }
  }
}
