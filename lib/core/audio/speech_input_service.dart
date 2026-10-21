import 'dart:typed_data';

import '../ml/asr_service.dart';
import 'speech_answers.dart';
import 'speech_match.dart';
import 'voice_activity.dart';

/// Where microphone bytes come from. One method, so the decision layer and every
/// widget test can run without a plugin, a permission dialog or a room.
abstract interface class AudioGate {
  /// Asks once. A `false` here means the affordance is shown as unavailable,
  /// never that the app retries a dialog the caregiver already refused.
  Future<bool> hasMicrophone();

  /// Records until [policy] ends the take, or the caller cancels.
  Future<SpeechTake> take(
    SpeechCapturePolicy policy, {
    Future<void> Function(double)? onLevel,
  });

  void cancel();

  Future<void> dispose();
}

class SpeechTake {
  const SpeechTake({required this.pcm, required this.end});
  final Float32List pcm;
  final SpeechEnd end;

  bool get hasSpeech => end == SpeechEnd.spoke && pcm.isNotEmpty;
}

/// The recogniser, behind the one call the app makes. `candidates` maps an
/// app-side answer to the spoken forms it accepts; an empty map asks for a
/// free transcription instead.
abstract interface class SpeechListener {
  bool isReady(String language);

  Future<AsrHearing> hear(
    Float32List pcm, {
    required String language,
    required Map<String, List<String>> candidates,
  });
}

/// Why the app is not listening right now. Each one is shown, not swallowed.
enum SpeechRefusal {
  microphoneMissing,
  packMissing,
  unsupportedLanguage,
  dictationUnproven,
  busy,
}

/// Everything a screen needs to render, and the only thing it may act on.
sealed class SpeechReply {
  const SpeechReply();
  const factory SpeechReply.heard(
    String answer,
    String utterance, {
    required double posterior,
    required bool verified,
  }) = SpeechHeard;
  const factory SpeechReply.unclear() = SpeechUnclear;
  const factory SpeechReply.silent() = SpeechSilent;
  const factory SpeechReply.refused(SpeechRefusal reason) = SpeechRefused;
  const factory SpeechReply.cancelled() = SpeechCancelled;
  const factory SpeechReply.transcript(String text) = SpeechTranscript;
}

class SpeechHeard extends SpeechReply {
  const SpeechHeard(
    this.answer,
    this.utterance, {
    required this.posterior,
    required this.verified,
  });
  final String answer;
  final String utterance;
  final double posterior;

  /// False when the answer set has no native-speaker sign-off. Screens may
  /// record a heard answer for non-clinical fields; on a clinical question this
  /// only ever pre-selects, and this flag is part of why.
  final bool verified;
}

class SpeechUnclear extends SpeechReply {
  const SpeechUnclear();
}

class SpeechSilent extends SpeechReply {
  const SpeechSilent();
}

class SpeechRefused extends SpeechReply {
  const SpeechRefused(this.reason);
  final SpeechRefusal reason;
}

class SpeechCancelled extends SpeechReply {
  const SpeechCancelled();
}

/// Open-vocabulary output. Only ever shown into a text field a human can edit.
class SpeechTranscript extends SpeechReply {
  const SpeechTranscript(this.text);
  final String text;
}

/// Operating point, stated out loud rather than buried in a comparison.
///
/// [posteriorFloor] is how sure the closed set must be that it picked this
/// answer over the others; [perFrameFloor] is how well that answer explains the
/// audio at all, which is what separates "one of these two" from "neither of
/// these". Both must clear, and the two independent decodings must not disagree.
/// Tune them against held-out clips, never by feel: a threshold chosen by eye is
/// a claim about clinical error rates nobody measured.
class SpeechConfidence {
  const SpeechConfidence({
    this.posteriorFloor = 0.85,
    this.perFrameFloor = -3.0,
  });
  final double posteriorFloor;
  final double perFrameFloor;

  /// The seam where measured floors go, per language.
  ///
  /// Dagbani has one number behind it, measured through this app's own frontend,
  /// encoder and decoder on real spoken answers (`data/closed_set/probe/`, the
  /// app's MMS voice): `Ayi` −1.67 and `Ee` −1.74 nats a frame, against −2.73 as
  /// the highest of 33 narration sentences that answer nothing. A floor of −2.5
  /// therefore hears yes and no and refuses all 33. `Mi bɛ mi` is ranked
  /// correctly but scores −3.85, so this floor refuses it — a miss, not a wrong
  /// answer, and one of the reasons the human recording set still matters.
  ///
    /// Twi has no floor that means anything yet, and is left on the conservative
  /// default rather than given a number that looks measured. On that model the
  /// answers (−0.83 to −1.61) and the four-second prose (down to −0.66) overlap
  /// completely, so every threshold either accepts prose or refuses the answers.
  /// What protects a Twi record today is that the endpointer hands the model one
  /// utterance and that the answer set is unverified, so a hearing is a proposal
  /// the caregiver taps; `data/closed_set/record.csv` is what would replace this.
  static const _measured = <String, SpeechConfidence>{
    'Dagbani': SpeechConfidence(posteriorFloor: 0.85, perFrameFloor: -2.5),
  };

  static SpeechConfidence forLanguage(String language) =>
      _measured[language] ?? const SpeechConfidence();
}

class SpeechInputService {
  SpeechInputService({
    required this.gate,
    required this.listener,
    this.confidence,
    this.policy = const SpeechCapturePolicy(),
  });

  final AudioGate gate;
  final SpeechListener listener;
  /// Null means "use the number measured for this language": the floors are a
  /// property of the recogniser, and passing one constant to two different
  /// models silently silences the better one.
  final SpeechConfidence? confidence;
  final SpeechCapturePolicy policy;

  bool _busy = false;

  /// Whether listening is real here at all: a pack that loaded and an answer set
  /// for this language. Screens render nothing when this is false rather than
  /// offering a microphone that can only apologise.
  bool supports(String language) =>
      listener.isReady(language) &&
      SpeechAnswerSet.forLanguage(language) != null;

  /// Median character error measured on held-out WaxalNLP test speech with the
  /// best model each language has today (`tool/asr_eval/score_ctc.py`, n=8 clips
  /// per language, 2026-10-20): Twi on `asr-africa/wav2vec2-xls-r-akan-20-hours`
  /// 0.162, Dagbani on `KhayaAI/w2v-bert-dga` 0.420.
  static const _measuredDictationCer = <String, double>{
    'Twi': 0.162,
    'Dagbani': 0.420,
  };

  /// The bar this project set out loud before building: under 25% character
  /// error, or it does not get to write words into anyone's record.
  static const _dictationCerCeiling = 0.25;

  /// Whether free dictation is earned here. A pack loading is not the same claim
  /// as a transcript being trustworthy: 0.42 CER means one word in three carries
  /// a mistake, which is fine to reject inside a three-word closed set and not
  /// fine to type a caregiver's note with.
  bool dictates(String language) =>
      listener.isReady(language) &&
      (_measuredDictationCer[language] ?? 1) <= _dictationCerCeiling;

  /// Asks once, hears once, decides. Never records anything itself: the caller
  /// decides whether a reply is a proposal or an answer, which is the whole
  /// difference between a clinical surface and a note field.
  Future<SpeechReply> listen({
    required String language,
    required SpeechAnswerSet set,
    Future<void> Function(double level)? onLevel,
  }) async {
    if (_busy) return const SpeechRefused(SpeechRefusal.busy);
    if (set.language != language) {
      return const SpeechRefused(SpeechRefusal.unsupportedLanguage);
    }
    if (!listener.isReady(language)) {
      return const SpeechRefused(SpeechRefusal.packMissing);
    }
    _busy = true;
    try {
      if (!await gate.hasMicrophone()) {
        return const SpeechRefused(SpeechRefusal.microphoneMissing);
      }
      final take = await gate.take(policy, onLevel: onLevel);
      if (take.end == SpeechEnd.cancelled) {
        return const SpeechReply.cancelled();
      }
      if (!take.hasSpeech) {
        return take.end == SpeechEnd.limit
            ? const SpeechReply.unclear()
            : const SpeechReply.silent();
      }
      final candidates = {
        for (final answer in set.answers) answer.answer: answer.utterances,
      };
      final hearing = await listener.hear(
        take.pcm,
        language: language,
        candidates: candidates,
      );
      if (hearing.scores.isEmpty) return const SpeechReply.unclear();
      final best = hearing.scores.first;
      final floors = confidence ?? SpeechConfidence.forLanguage(language);
      if (best.posterior < floors.posteriorFloor ||
          best.perFrame < floors.perFrameFloor) {
        return const SpeechReply.unclear();
      }
      // Two readings of the same frames. If the free transcription lands on a
      // *different* allowed answer, the closed set is not to be trusted here.
      final cross = matchSpeech(hearing.reading.text, set);
      if (cross != null && cross.answer != best.id && cross.score >= 0.6) {
        return const SpeechReply.unclear();
      }
      return SpeechReply.heard(
        best.id,
        _utteranceFor(set, best.id),
        posterior: best.posterior,
        verified: set.isVerified,
      );
    } on UnspellableAnswerException {
      // The pack cannot pronounce this answer set at all. Saying so beats
      // reporting a confident mishearing.
      return const SpeechReply.refused(SpeechRefusal.unsupportedLanguage);
    } finally {
      _busy = false;
    }
  }

  /// Dictation for a free-text field. Refuses on silence, and otherwise hands
  /// back whatever was said for the human to edit — never a clinical value.
  Future<SpeechReply> dictate({
    required String language,
    Future<void> Function(double level)? onLevel,
  }) async {
    if (_busy) return const SpeechRefused(SpeechRefusal.busy);
    if (!listener.isReady(language)) {
      return const SpeechRefused(SpeechRefusal.packMissing);
    }
    if (!dictates(language)) {
      return const SpeechRefused(SpeechRefusal.dictationUnproven);
    }
    _busy = true;
    try {
      if (!await gate.hasMicrophone()) {
        return const SpeechRefused(SpeechRefusal.microphoneMissing);
      }
      final take = await gate.take(policy, onLevel: onLevel);
      if (take.end == SpeechEnd.cancelled) {
        return const SpeechReply.cancelled();
      }
      if (!take.hasSpeech) return const SpeechReply.silent();
      final hearing = await listener.hear(
        take.pcm,
        language: language,
        candidates: const {},
      );
      final text = hearing.reading.text.trim();
      if (text.isEmpty ||
          hearing.reading.meanFrameProbability <
          (confidence ?? SpeechConfidence.forLanguage(language)).posteriorFloor) {
        return const SpeechReply.unclear();
      }
      return SpeechReply.transcript(text);
    } finally {
      _busy = false;
    }
  }

  void cancel() {
    gate.cancel();
  }

  static String _utteranceFor(SpeechAnswerSet set, String answer) =>
      set.answers.firstWhere((a) => a.answer == answer).utterances.first;
}
