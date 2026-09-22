/// Compatibility adapter for strict, same-language offline caregiver speech.
library;

import 'package:flutter/foundation.dart';

import '../i18n/speech_bank.dart';
import 'audio_guide.dart';
import 'caregiver_playback.dart';
import 'speech_content_policy.dart';

/// Legacy variants remain for callers with exhaustive switches. This service
/// never returns studio or linguaFranca: neither is an available offline source.
enum VoiceSource { studio, synthesized, systemTts, linguaFranca, readAloud }

extension VoiceSourceLabel on VoiceSource {
  String labelFor(String language) => switch (this) {
    VoiceSource.studio => 'Studio recording',
    VoiceSource.synthesized => '$language voice • on-device',
    VoiceSource.systemTts => 'Phone voice',
    VoiceSource.linguaFranca => 'Hausa bridge',
    VoiceSource.readAloud => 'Read the words',
  };

  String pillFor(String language) => '▸ ${labelFor(language)}';
}

@immutable
class VoiceRequest {
  const VoiceRequest({
    required this.id,
    required this.preferredLanguage,
    required this.preferredScript,
    this.bridgeScript,
    this.bridgeLanguage = 'Hausa',
    this.bankClips,
    this.sourceLanguage = 'English',
    this.policy = SpeechContentPolicy.guidance,
    this.owner,
    this.revision = '1',
  });
  final Object? owner;
  final String revision;
  final String sourceLanguage;
  final SpeechContentPolicy policy;

  final String id;
  final String preferredLanguage;

  /// English guidance, or the exact selected-language bank translation.
  /// An id alone never authorizes replacing these words with a generic clip.
  final String preferredScript;

  /// Retained for source compatibility; cross-language bridges are not used.
  final String? bridgeScript;
  final String bridgeLanguage;

  /// Explicit ordered candidates. Their entire English or localized transcript
  /// must cover preferredScript; partial matches never authorize playback.
  final List<String>? bankClips;
}

class VoiceOutcome {
  const VoiceOutcome({
    required this.source,
    required this.request,
    this.spokenScript,
    this.actualLanguage,
    this.reasonCode,
    this.detail,
  });
  final String? reasonCode;
  final String? detail;

  final VoiceSource source;
  final VoiceRequest request;

  /// Final playback transcript, also available as readable text on fallback.
  /// Only a non-readAloud source indicates that the whole message completed.
  final String? spokenScript;
  final String? actualLanguage;
}

abstract final class VoiceService {
  static final DeviceCaregiverVoice _backend = DeviceCaregiverVoice();

  static Object? _owner;
  static int _generation = 0;

  static Future<void> stop({Object? owner}) {
    if (owner != null && !identical(owner, _owner)) return Future.value();
    ++_generation;
    _owner = null;
    return _backend.stop();
  }

  static CaregiverSpeech _speech(VoiceRequest request) {
    final selected = OfflineSpeechLanguage.canonical(request.preferredLanguage);
    List<String>? candidates = request.bankClips;
    if (candidates == null) {
      final clip = SpeechBank.byId(request.id);
      if (clip != null &&
          (request.preferredScript == clip.english ||
              request.preferredScript == clip.textFor(selected))) {
        candidates = [clip.id];
      }
    }
    final ids = candidates == null
        ? null
        : List<String>.unmodifiable(candidates);
    var english = request.preferredScript;
    if (ids != null && ids.isNotEmpty) {
      final clips = ids.map(SpeechBank.byId).toList();
      if (clips.every((clip) => clip != null)) {
        final joinedEnglish = clips.map((clip) => clip!.english).join(' ');
        final localized = selected == 'English'
            ? joinedEnglish
            : SpeechBank.scriptFor(language: selected, ids: ids);
        // Recover the English gloss only for an EXACT localized bank script.
        if (localized != null && request.preferredScript == localized) {
          english = joinedEnglish;
        }
      }
    }
    return CaregiverSpeech(
      id: request.id,
      english: english,
      language: selected,
      clipId: ids?.length == 1 ? ids!.single : null,
      clipIds: ids,
      sourceLanguage: english != request.preferredScript
          ? 'English'
          : request.sourceLanguage,
      policy: request.policy,
      owner: request.owner,
      revision: request.revision,
    );
  }

  /// Waits for the complete message, not just a successful start command.
  static Future<VoiceOutcome> speak(
    VoiceRequest request, {
    void Function(CaregiverPlayback)? onPlayback,
  }) async {
    final generation = ++_generation;
    _owner = request.owner;
    final speech = _speech(request);
    CaregiverPlayback? finalPlayback;
    try {
      await _backend.play(speech, (playback) {
        if (generation != _generation &&
            playback.phase != CaregiverPlaybackPhase.stopped) {
          return;
        }
        finalPlayback = playback;
        onPlayback?.call(playback);
      });
    } catch (_) {
      // A missing plugin must never turn readable guidance into an exception.
      finalPlayback = CaregiverPlayback(
        phase: CaregiverPlaybackPhase.fallback,
        transcript: speech.localizedText ?? speech.english,
        language: speech.localizedText == null
            ? speech.sourceLanguage
            : speech.language,
        source: 'Readable text • offline audio unavailable',
        reasonCode: 'offline_audio_unavailable',
      );
    } finally {
      if (generation == _generation) _owner = null;
    }
    final playback = finalPlayback;
    final completed = playback?.phase == CaregiverPlaybackPhase.completed;
    final source = !completed
        ? VoiceSource.readAloud
        : playback!.source.startsWith('Bundled synthetic voice') ||
              playback.source.startsWith('Piper offline voice')
        ? VoiceSource.synthesized
        : playback.source.contains('offline device speech')
        ? VoiceSource.systemTts
        : VoiceSource.readAloud;
    return VoiceOutcome(
      source: source,
      request: request,
      spokenScript:
          playback?.transcript ?? speech.localizedText ?? speech.english,
      actualLanguage: playback?.language,
      reasonCode: playback?.reasonCode,
      detail: playback?.source,
    );
  }

  /// [text] remains plain English guidance, never an inferred translation.
  static Future<VoiceOutcome> speakText({
    required String id,
    required String text,
    required String language,
    List<String>? bankClips,
  }) => speak(
    VoiceRequest(
      id: id,
      preferredLanguage: language,
      preferredScript: text,
      bankClips: bankClips,
    ),
  );

  /// Engine-reported locales for diagnostics. Playback separately requires
  /// explicit offline voice metadata. No polling or download is attempted.
  static Future<List<String>> availableTtsLanguages() =>
      _backend.availableTtsLanguages();

  /// There is no verified studio-recording manifest in this application.
  static bool hasRecording(AudioTopic topic, String language) => false;
}
