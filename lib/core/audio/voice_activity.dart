/// Endpointing for one short spoken answer, from frame energies only.
///
/// The listener needs to know when to stop recording, and it needs to know the
/// difference between "she said nothing", "she said a word" and "she rambled".
/// Energy alone answers all three, costs nothing, and runs on the sample stream
/// before any model sees it.
enum SpeechEnd { spoke, silent, tooShort, limit, cancelled }

class SpeechCapturePolicy {
  const SpeechCapturePolicy({
    this.sampleRate = 16000,
    this.frameMs = 20,
    this.openAt = 0.02,
    this.closeAt = 0.012,
    this.silenceLimitMs = 1200,
    this.minSpeechMs = 120,
    this.trailingSilenceMs = 450,
    this.maxSpeechMs = 4000,
  });

  final int sampleRate;
  final int frameMs;

  /// Energy that opens the gate, and the lower one that holds it open: hysteresis
  /// so a word ending in a soft consonant is not cut off mid-syllable.
  final double openAt;
  final double closeAt;

  /// Give up before she speaks at all — the room is quiet but nobody answered.
  final int silenceLimitMs;
  final int minSpeechMs;
  final int trailingSilenceMs;

  /// Hard ceiling: a triage answer is a word, so anything longer is a runaway
  /// recording and must not be fed to the recogniser.
  final int maxSpeechMs;
}

class VoiceTracker {
  VoiceTracker(this.policy);
  final SpeechCapturePolicy policy;

  bool _open = false;
  int _speechFrames = 0;
  int _silentRun = 0;
  int _seenFrames = 0;

  bool get isOpen => _open;

  /// Frames of voiced audio held so far, for the level meter.
  int get speechMs => _speechFrames * policy.frameMs;

  SpeechEnd? feed(double rms) {
    _seenFrames++;
    if (!_open) {
      if (rms >= policy.openAt) {
        _open = true;
        _speechFrames = 1;
        _silentRun = 0;
      } else if (_seenFrames * policy.frameMs >= policy.silenceLimitMs) {
        return SpeechEnd.silent;
      }
      return null;
    }
    if (rms > policy.closeAt) {
      _speechFrames++;
      _silentRun = 0;
    } else {
      _silentRun++;
    }
    final voiced = _speechFrames * policy.frameMs;
    if (_silentRun * policy.frameMs >= policy.trailingSilenceMs) {
      return voiced < policy.minSpeechMs ? SpeechEnd.tooShort : SpeechEnd.spoke;
    }
    return voiced >= policy.maxSpeechMs ? SpeechEnd.limit : null;
  }
}
