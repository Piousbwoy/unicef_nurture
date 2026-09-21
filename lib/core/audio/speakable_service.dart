/// Universal narration adapter over the shared offline playback coordinator.
library;

import 'caregiver_playback.dart';
import 'speech_content_policy.dart';
import '../i18n/speech_bank.dart';

export 'speech_content_policy.dart';

class SpeakableService {
  SpeakableService({CaregiverVoiceBackend? backend})
      : _backend = backend ?? DeviceCaregiverVoice();

  static final instance = SpeakableService();
  static SpeakableService debugCreate({CaregiverVoiceBackend? backend}) =>
      SpeakableService(backend: backend);

  final CaregiverVoiceBackend _backend;
  Object? _owner;
  int _generation = 0;
  CaregiverPlayback? _playback;
  CaregiverPlayback? get playback => _playback;
  bool get isSpeaking => _playback?.phase == CaregiverPlaybackPhase.playing;

  /// Resolve only complete, case-sensitive English bank sequences.
  /// Whitespace can vary; no clinical wording may be added or removed.
  static List<String>? exactClips(String english) {
    String normalize(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');
    final text = normalize(english);
    if (text.isEmpty) return null;
    final failed = <int>{};
    List<String>? match(int start) {
      if (start == text.length) return [];
      if (!failed.add(start)) return null;
      for (final clip in SpeechBank.allScripts) {
        final part = normalize(clip.english);
        if (part.isEmpty || !text.startsWith(part, start)) continue;
        final end = start + part.length;
        if (end != text.length && text[end] != ' ') continue;
        final rest = match(end == text.length ? end : end + 1);
        if (rest != null) return [clip.id, ...rest];
      }
      return null;
    }
    return match(0);
  }

  Future<bool> speak(String text, {
    required String language,
    Object? owner,
    SpeechContentPolicy policy = SpeechContentPolicy.guidance,
    void Function(CaregiverPlayback)? onPlayback,
  }) async {
    if (text.trim().isEmpty) return false;
    final generation = ++_generation;
    _owner = owner;
    var completed = false;
    final speech = CaregiverSpeech(
      id: 'universal:$generation', english: text, language: language,
      clipIds: exactClips(text), policy: policy,
    );
    try {
      await _backend.play(speech, (event) {
        if (generation != _generation) return;
        _playback = event;
        completed = event.phase == CaregiverPlaybackPhase.completed;
        onPlayback?.call(event);
      });
    } catch (_) {
      if (generation == _generation) {
        final event = CaregiverPlayback(phase: CaregiverPlaybackPhase.fallback,
          transcript: text, language: 'English',
          source: 'Readable text - offline audio unavailable. Choose English playback.');
        _playback = event;
        onPlayback?.call(event);
      }
    }
    return generation == _generation && completed;
  }

  /// An old widget may cancel only its own request.
  Future<void> stop({Object? owner}) async {
    if (owner != null && !identical(owner, _owner)) return;
    ++_generation;
    _owner = null;
    _playback = null;
    await _backend.stop();
    if (owner == null) await DeviceCaregiverVoice.stopAll();
  }

  Future<void> dispose() async {
    ++_generation;
    _owner = null;
    await _backend.dispose();
  }
}
