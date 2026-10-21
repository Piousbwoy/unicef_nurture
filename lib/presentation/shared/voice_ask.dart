import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/audio/speech_answers.dart';
import '../../core/audio/speech_input_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/lumina.dart';

/// Ask a question by voice, and let the human decide what was said.
///
/// This widget never records an answer on its own. A confident hearing becomes a
/// proposal the caregiver confirms with a tap, because the recogniser is a
/// hearsay and a triage answer is evidence. When it is unsure it says so and the
/// buttons underneath stay exactly as they were.
class VoiceAsk extends ConsumerStatefulWidget {
  const VoiceAsk({
    super.key,
    required this.language,
    required this.set,
    required this.onConfirmed,
    this.question,
  });

  final String language;
  final SpeechAnswerSet set;

  /// Called only after a tap on the proposal, never by the recogniser.
  final void Function(String answer) onConfirmed;

  /// Optional prompt replayed before listening, in the app's voice.
  final Future<void> Function()? question;

  @override
  ConsumerState<VoiceAsk> createState() => _VoiceAskState();
}

enum _Stage { idle, listening, heard, unclear, silent, refused }

class _VoiceAskState extends ConsumerState<VoiceAsk> {
  /// Captured during build because `ref` is already dead by the time dispose
  /// runs, and a widget that throws while unmounting hides the real failure.
  void Function()? _cancel;
  VoidCallback? _again;
  _Stage _stage = _Stage.idle;
  String? _answer;
  String? _utterance;
  bool _verified = false;
  SpeechRefusal? _refusal;

  @override
  void dispose() {
    _cancel?.call();
    super.dispose();
  }

  Future<void> _listen(SpeechInputService service) async {
    setState(() {
      _stage = _Stage.listening;
      _answer = null;
      _refusal = null;
    });
    await widget.question?.call();
    final reply = await service.listen(
      language: widget.language,
      set: widget.set,
    );
    if (!mounted) return;
    setState(() {
      switch (reply) {
        case SpeechHeard(:final answer, :final utterance, :final verified):
          _answer = answer;
          _utterance = utterance;
          _verified = verified;
          _stage = _Stage.heard;
        case SpeechUnclear():
          _stage = _Stage.unclear;
        case SpeechSilent():
          _stage = _Stage.silent;
        case SpeechRefused(:final reason):
          _refusal = reason;
          _stage = _Stage.refused;
        case SpeechCancelled():
          _stage = _Stage.idle;
        case SpeechTranscript():
          // A dictation reply cannot arrive from a closed-set listen.
          _stage = _Stage.unclear;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.read(speechInputProvider);
    _cancel = service.cancel;
    _again = () => _listen(service);
    if (!service.supports(widget.language)) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _pill(),
        if (_stage == _Stage.heard) ..._proposal(),
        if (_stage == _Stage.unclear || _stage == _Stage.silent) ..._fallback(),
      ],
    );
  }

  Widget _pill() {
    final color = switch (_stage) {
      _Stage.listening => AppColors.checkBlue,
      _Stage.heard => AppColors.checkNavy,
      _Stage.refused ||
      _Stage.unclear ||
      _Stage.silent => AppColors.caregiverMuted,
      _ => Colors.transparent,
    };
    return Semantics(
      button: true,
      label: _label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const Key('voiceAsk'),
          onTap: _stage == _Stage.listening
              ? () {
                  ref.read(speechInputProvider).cancel();
                  setState(() => _stage = _Stage.idle);
                }
              : () => _again?.call(),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _stage == _Stage.idle
                  ? Lumina.pearl
                  : color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _stage == _Stage.idle
                    ? AppColors.checkNavy.withValues(alpha: 0.14)
                    : color,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _stage == _Stage.listening
                      ? Icons.radio_button_on_rounded
                      : Icons.mic_none_rounded,
                  size: 20,
                  color: _stage == _Stage.idle ? AppColors.checkNavy : color,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _label => switch (_stage) {
    _Stage.listening => 'Listening — tap to stop',
    _Stage.heard => 'Answer by voice',
    _Stage.unclear => 'Say it again',
    _Stage.silent => 'Listen again',
    _Stage.refused => switch (_refusal) {
      SpeechRefusal.microphoneMissing => 'Microphone is not allowed',
      SpeechRefusal.packMissing => 'Voice input pack not installed',
      SpeechRefusal.unsupportedLanguage => 'Voice input is not ready',
      SpeechRefusal.dictationUnproven => 'Dictation is not accurate enough yet',
      _ => 'Voice input is busy',
    },
    _ => 'Answer by voice',
  };

  /// The proposal. It names what was heard in the speaker's own words, so the
  /// caregiver is confirming a hearing, not trusting a tick.
  List<Widget> _proposal() {
    return [
      const SizedBox(height: 10),
      Container(
        key: const Key('voiceHeard'),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: AppColors.checkNavy.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                text: 'I heard ',
                style: TextStyle(fontSize: 13, color: AppColors.caregiverMuted),
                children: [
                  TextSpan(
                    text: '“$_utterance”',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.checkNavy,
                    ),
                  ),
                ],
              ),
            ),
            if (!_verified)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'These answer words are not yet checked with a speaker.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.caregiverMuted,
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    key: const Key('voiceConfirm'),
                    onPressed: () => widget.onConfirmed(_answer!),
                    child: Text('Yes, that is what I said'),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  key: const Key('voiceAgain'),
                  onPressed: () => _again?.call(),
                  tooltip: 'Ask me again',
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _fallback() {
    return [
      const SizedBox(height: 8),
      Text(
        _stage == _Stage.silent
            ? 'I heard nothing. Tap an answer instead.'
            : 'I am not sure what you said. Tap an answer instead.',
        style: TextStyle(fontSize: 12, color: AppColors.caregiverMuted),
      ),
    ];
  }
}

/// Free-text dictation for a note field: it hands words back to edit, and it is
/// deliberately a different widget from [VoiceAsk] because the risk is
/// different — a wrong word in a note is retyped, a wrong clinical answer is
/// acted on.
class VoiceDictate extends ConsumerStatefulWidget {
  const VoiceDictate({super.key, required this.language, required this.onText});

  final String language;
  final void Function(String text) onText;

  @override
  ConsumerState<VoiceDictate> createState() => _VoiceDictateState();
}

class _VoiceDictateState extends ConsumerState<VoiceDictate> {
  bool _busy = false;

  Future<void> _dictate(SpeechInputService service) async {
    setState(() => _busy = true);
    final reply = await service.dictate(language: widget.language);
    if (!mounted) return;
    setState(() => _busy = false);
    if (reply is SpeechTranscript) widget.onText(reply.text);
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.read(speechInputProvider);
    if (!service.dictates(widget.language)) {
      return const SizedBox.shrink();
    }
    return IconButton(
      key: const Key('voiceDictate'),
      onPressed: _busy ? null : () => unawaited(_dictate(service)),
      tooltip: _busy ? 'Listening…' : 'Dictate',
      icon: Icon(
        _busy ? Icons.radio_button_on_rounded : Icons.mic_none_rounded,
      ),
    );
  }
}
