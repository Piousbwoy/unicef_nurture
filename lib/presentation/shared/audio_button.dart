/// "Read it to me" — the universal audio button.
///
/// One widget, used on every important text card in the app. Tapping it
/// speaks the card aloud using [VoiceService], which tries a real recording
/// first, then system TTS, then the Hausa bridge, then falls back to "read
/// the words". Whatever actually plays is shown as a small pill below the
/// button, so the user (or a CHW) can see *which* voice is being heard.
///
/// Long-pressing the button opens a bottom sheet with the full script in
/// both English and the user's language, so an illiterate user can hand the
/// phone to a literate friend and have it read in writing.
library;

import 'package:flutter/material.dart';

import '../../core/audio/voice_service.dart';
import '../../core/i18n/dagbani_strings.dart';
import '../../core/theme/app_theme.dart';

class AudioButton extends StatefulWidget {
  const AudioButton({
    super.key,
    required this.text,
    required this.language,
    this.id,
    this.compact = false,
  });

  /// The script to speak. This is the same plain-language text the app
  /// already shows on the card; the audio is a *spoken* copy of it.
  final String text;

  /// The language the *user* wants to hear. Drives asset lookup and TTS
  /// locale selection.
  final String language;

  /// Optional id for asset lookup, e.g. `child_danger_signs`. When null,
  /// the audio system cannot fall back to a studio recording — only TTS
  /// and the read-aloud path are available.
  final String? id;

  /// When true, draws the smaller variant used in cramped card rows.
  final bool compact;

  @override
  State<AudioButton> createState() => _AudioButtonState();
}

class _AudioButtonState extends State<AudioButton> {
  bool _playing = false;
  VoiceSource? _lastSource;

  Future<void> _toggle() async {
    if (_playing) {
      await VoiceService.stop();
      if (!mounted) return;
      setState(() => _playing = false);
      return;
    }
    final outcome = await VoiceService.speak(
      VoiceRequest(
        id: widget.id ?? 'inline_${widget.text.hashCode}',
        preferredLanguage: widget.language,
        preferredScript: widget.text,
      ),
    );
    if (!mounted) return;
    setState(() {
      _playing = outcome.source != VoiceSource.readAloud;
      _lastSource = outcome.source;
    });

    if (outcome.source == VoiceSource.readAloud) {
      // Nothing to play — show the script sheet so the user is never left
      // looking at a silent button wondering what just happened.
      _showScriptSheet(outcome);
    }
  }

  void _showScriptSheet(VoiceOutcome outcome) {
    // When the user has picked Dagbani, look up the Dagbani text for this
    // topic (or question) so the on-screen script is in the user's
    // language. The audio may still be Hausa or English — the pill tells
    // the truth — but a grandmother who can read Dagbani should never be
    // asked to read English.
    final resolved = _resolveScript(outcome);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _ScriptSheet(
        outcome: outcome,
        resolved: resolved,
      ),
    );
  }

  /// Picks the right text to show in the script sheet for [outcome].
  _ResolvedScript _resolveScript(VoiceOutcome outcome) {
    final id = outcome.request.id;
    final language = outcome.request.preferredLanguage;

    // Triage question — id starts with 'q_'.
    if (id.startsWith('q_')) {
      final key = id.substring(2); // child.drink
      final s = DagbaniStrings.forQuestionKey(key);
      if (s != null && language == 'Dagbani') {
        return _ResolvedScript(
          english: s.english,
          dagbani: s.dagbani,
          verified: s.verified,
        );
      }
      if (s != null) {
        return _ResolvedScript(english: s.english, dagbani: null);
      }
    }

    // Audio topic — id matches an AudioTopic.id.
    final s = DagbaniStrings.forAudioTopicId(id);
    if (s != null && language == 'Dagbani') {
      return _ResolvedScript(
        english: s.english,
        dagbani: s.dagbani,
        verified: s.verified,
      );
    }
    if (s != null) {
      return _ResolvedScript(english: s.english, dagbani: null);
    }

    // No Dagbani draft — show whatever the caller passed in.
    return _ResolvedScript(english: outcome.request.preferredScript, dagbani: null);
  }

  @override
  Widget build(BuildContext context) {
    final colour = _playing ? AppColors.primary : AppColors.primaryDeep;
    final size = widget.compact ? 36.0 : 44.0;
    final iconSize = widget.compact ? 18.0 : 22.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _toggle,
            onLongPress: () => _showScriptSheet(VoiceOutcome(
              source: _lastSource ?? VoiceSource.readAloud,
              request: VoiceRequest(
                id: widget.id ?? 'inline',
                preferredLanguage: widget.language,
                preferredScript: widget.text,
              ),
            )),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: _playing ? colour : AppColors.primaryLight,
                shape: BoxShape.circle,
                boxShadow: _playing
                    ? const [AppShadows.glow]
                    : const [AppShadows.card],
              ),
              child: Icon(
                _playing
                    ? Icons.stop_rounded
                    : Icons.volume_up_rounded,
                size: iconSize,
                color: _playing ? Colors.white : colour,
              ),
            ),
          ),
        ),
        if (_lastSource != null) ...[
          const SizedBox(height: 4),
          _SourcePill(source: _lastSource!),
        ],
      ],
    );
  }
}

class _SourcePill extends StatelessWidget {
  const _SourcePill({required this.source});
  final VoiceSource source;

  Color get _bg => switch (source) {
    VoiceSource.studio       => AppColors.triageGreenBg,
    VoiceSource.systemTts    => AppColors.primaryLight,
    VoiceSource.linguaFranca => AppColors.triageAmberBg,
    VoiceSource.readAloud    => AppColors.canvas,
  };

  Color get _fg => switch (source) {
    VoiceSource.studio       => AppColors.triageGreen,
    VoiceSource.systemTts    => AppColors.primaryDeep,
    VoiceSource.linguaFranca => AppColors.triageAmber,
    VoiceSource.readAloud    => AppColors.inkFaint,
  };

  IconData get _icon => switch (source) {
    VoiceSource.studio       => Icons.mic_rounded,
    VoiceSource.systemTts    => Icons.record_voice_over_rounded,
    VoiceSource.linguaFranca => Icons.translate_rounded,
    VoiceSource.readAloud    => Icons.menu_book_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, size: 11, color: _fg),
          const SizedBox(width: 4),
          Text(
            source.label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: _fg,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResolvedScript {
  const _ResolvedScript({
    required this.english,
    this.dagbani,
    this.verified = false,
  });
  final String english;
  final String? dagbani;
  final bool verified;
}

class _ScriptSheet extends StatelessWidget {
  const _ScriptSheet({required this.outcome, required this.resolved});
  final VoiceOutcome outcome;
  final _ResolvedScript resolved;

  @override
  Widget build(BuildContext context) {
    // When the user has picked Dagbani and a draft exists, the on-screen
    // script is in Dagbani (or English with a draft badge if unverified).
    // The audio pill still tells the truth about what the phone actually
    // played.
    final showDagbani = resolved.dagbani != null;
    final displayText = showDagbani && resolved.verified
        ? resolved.dagbani!
        : resolved.english;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.volume_up_rounded, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  'The spoken message',
                  style: AppType.title,
                ),
              ],
            ),
            const SizedBox(height: 4),
            _SourcePill(source: outcome.source),
            if (showDagbani) ...[
              const SizedBox(height: 6),
              _LangBadge(
                language: 'Dagbani',
                verified: resolved.verified,
              ),
            ],
            const SizedBox(height: Gap.md),
            Text(
              outcome.source == VoiceSource.readAloud
                  ? 'There is no voice on this phone for this language yet. '
                      'The words are below — read them aloud, or ask '
                      'someone to.'
                  : outcome.source == VoiceSource.linguaFranca
                  ? 'This phone cannot speak ${outcome.request.preferredLanguage} '
                      'yet, so the message is in ${outcome.request.bridgeLanguage}, '
                      'which is the trade language across Northern Ghana.'
                  : outcome.source == VoiceSource.systemTts
                  ? 'This phone is speaking in its own voice. A real '
                      'human recording would sound warmer.'
                  : 'This is the studio recording.',
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.inkMuted,
                height: 1.45,
              ),
            ),
            const SizedBox(height: Gap.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Gap.md),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(Gap.radius),
                border: Border.all(color: AppColors.line, width: Gap.hairline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayText,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: AppColors.ink,
                    ),
                  ),
                  if (showDagbani && resolved.verified) ...[
                    const SizedBox(height: 8),
                    Text(
                      'English: ${resolved.english}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.inkFaint,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: Gap.md),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded),
              label: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small badge that tells the user "this is in your language" and whether a
/// native speaker has signed off.
class _LangBadge extends StatelessWidget {
  const _LangBadge({required this.language, required this.verified});
  final String language;
  final bool verified;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: verified ? AppColors.triageGreenBg : AppColors.triageAmberBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            verified ? Icons.verified_rounded : Icons.translate_rounded,
            size: 11,
            color: verified ? AppColors.triageGreen : AppColors.triageAmber,
          ),
          const SizedBox(width: 4),
          Text(
            verified ? '$language • verified' : '$language • draft',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: verified ? AppColors.triageGreen : AppColors.triageAmber,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
