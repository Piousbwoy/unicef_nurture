import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:record/record.dart';

import 'speech_input_service.dart';
import 'voice_activity.dart';

/// Microphone bytes for one spoken answer, through `package:record`.
///
/// PCM lives in memory and is zeroed the moment a take ends, because the app
/// records a *text* answer and never audio: nothing to persist, nothing to
/// upload, nothing to leak. The recorder is created once and reused, so the
/// permission is asked for once per session rather than once per question.
class RecordingGate implements AudioGate {
  RecordingGate({AudioRecorder Function()? factory})
    : _factory = factory ?? AudioRecorder.new;

  final AudioRecorder Function() _factory;
  AudioRecorder? _recorder;
  Completer<SpeechTake>? _pending;
  StreamSubscription<Uint8List>? _subscription;
  bool _permissionAsked = false;
  bool? _granted;

  @override
  Future<bool> hasMicrophone() async {
    final recorder = await _open();
    // A device that cannot hand us linear PCM is refused rather than accepted
    // and decoded from a container we never asked for.
    if (!await recorder.isEncoderSupported(AudioEncoder.pcm16bits)) {
      return false;
    }
    // Asked once per session: a caregiver who already said no is not shown the
    // dialog again on the next question.
    if (_permissionAsked) {
      return _granted ?? false;
    }
    _permissionAsked = true;
    return _granted = await recorder.hasPermission();
  }

  @override
  Future<SpeechTake> take(
    SpeechCapturePolicy policy, {
    Future<void> Function(double)? onLevel,
  }) async {
    if (_pending != null) {
      return SpeechTake(pcm: Float32List(0), end: SpeechEnd.cancelled);
    }
    final recorder = await _open();
    final completer = Completer<SpeechTake>();
    _pending = completer;
    final tracker = VoiceTracker(policy);
    final samples = <double>[];
    final frameLength = (policy.frameMs * policy.sampleRate / 1000).round();
    var consumed = 0;

    Future<void> finish(SpeechEnd end) async {
      await _subscription?.cancel();
      _subscription = null;
      try {
        await recorder.stop();
      } catch (_) {
        /* The platform already stopped; the take we hold is what matters. */
      }
      if (_pending == completer) _pending = null;
      final pcm = Float32List.fromList(samples);
      samples.clear();
      if (!completer.isCompleted) {
        completer.complete(SpeechTake(pcm: pcm, end: end));
      }
    }

    try {
      final stream = await recorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: policy.sampleRate,
          numChannels: 1,
          autoGain: false,
          echoCancel: true,
          noiseSuppress: false,
        ),
      );
      _subscription = stream.listen((chunk) {
        if (completer.isCompleted) return;
        final data = ByteData.sublistView(chunk);
        for (var i = 0; i + 1 < chunk.length; i += 2) {
          samples.add(data.getInt16(i, Endian.little) / 32768.0);
        }
        while (samples.length - consumed >= frameLength) {
          var sum = 0.0;
          for (var i = consumed; i < consumed + frameLength; i++) {
            sum += samples[i] * samples[i];
          }
          consumed += frameLength;
          final rms = math.sqrt(sum / frameLength);
          final end = tracker.feed(rms);
          if (end != null) {
            unawaited(finish(end));
            return;
          }
          unawaited(onLevel?.call(rms));
        }
      }, onError: (Object _) => unawaited(finish(SpeechEnd.silent)));
    } catch (_) {
      if (_pending == completer) _pending = null;
      if (!completer.isCompleted) {
        completer.complete(
          SpeechTake(pcm: Float32List(0), end: SpeechEnd.cancelled),
        );
      }
    }
    return completer.future;
  }

  @override
  void cancel() {
    final pending = _pending;
    if (pending == null || pending.isCompleted) return;
    unawaited(_close(SpeechEnd.cancelled));
  }

  Future<void> _close(SpeechEnd end) async {
    await _subscription?.cancel();
    _subscription = null;
    try {
      await _recorder?.stop();
    } catch (_) {
      /* Already stopped by the platform. */
    }
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) {
      pending.complete(SpeechTake(pcm: Float32List(0), end: end));
    }
  }

  @override
  Future<void> dispose() async {
    await _close(SpeechEnd.cancelled);
    await _recorder?.dispose();
    _recorder = null;
  }

  Future<AudioRecorder> _open() async => _recorder ??= _factory();
}
