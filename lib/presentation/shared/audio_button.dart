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
    this.bankClips,
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

  /// Ordered speech-bank clips that compose the spoken message (see
  /// [VoiceRequest.bankClips]). When the user's language has an on-device
  /// bank (Dagbani, Hausa, Twi), the chain plays the sequence —
  /// all-or-nothing — before falling back.
  final List<String>? bankClips;

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
        bankClips: widget.bankClips,
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
      builder: (_) => _ScriptSheet(outcome: outcome, resolved: resolved),
    );
  }

  /// Picks the right text to show in the script sheet for [outcome].
  _ResolvedScript _resolveScript(VoiceOutcome outcome) {
    final id = outcome.request.id;
    final language = outcome.request.preferredLanguage;

    // The bank playback reports exactly what was heard, in the user's
    // language — the sheet leads with it so the screen matches the
    // speaker, whatever the language.
    final spoken = outcome.spokenScript;
    if (spoken != null) {
      return _ResolvedScript(
        english: outcome.request.preferredScript,
        spoken: spoken,
        spokenLanguage: language,
        spokenIsAudible: true,
      );
    }

    // Triage question — id starts with 'q_'. Before anything plays (long
    // press), a Dagbani draft still previews in the user's language, with
    // the verified badge honest about its status.
    if (id.startsWith('q_')) {
      final key = id.substring(2); // child.drink
      final s = DagbaniStrings.forQuestionKey(key);
      if (s != null && language == 'Dagbani') {
        return _ResolvedScript(
          english: s.english,
          spoken: s.dagbani,
          spokenLanguage: 'Dagbani',
          verified: s.verified,
        );
      }
      if (s != null) {
        return _ResolvedScript(english: s.english);
      }
    }

    // Audio topic — id matches an AudioTopic.id.
    final s = DagbaniStrings.forAudioTopicId(id);
    if (s != null && language == 'Dagbani') {
      return _ResolvedScript(
        english: s.english,
        spoken: s.dagbani,
        spokenLanguage: 'Dagbani',
        verified: s.verified,
      );
    }
    if (s != null) {
      return _ResolvedScript(english: s.english);
    }

    // No draft — show whatever the caller passed in.
    return _ResolvedScript(english: outcome.request.preferredScript);
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
            onLongPress: () => _showScriptSheet(
              VoiceOutcome(
                source: _lastSource ?? VoiceSource.readAloud,
                request: VoiceRequest(
                  id: widget.id ?? 'inline',
                  preferredLanguage: widget.language,
                  preferredScript: widget.text,
                ),
              ),
            ),
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
                _playing ? Icons.stop_rounded : Icons.volume_up_rounded,
                size: iconSize,
                color: _playing ? Colors.white : colour,
              ),
            ),
          ),
        ),
        if (_lastSource != null) ...[
          const SizedBox(height: 4),
          _SourcePill(source: _lastSource!, language: widget.language),
        ],
      ],
    );
  }
}

class _SourcePill extends StatelessWidget {
  const _SourcePill({required this.source, required this.language});
  final VoiceSource source;

  /// The language the bank speaks — only used for the synthesized label.
  final String language;

  Color get _bg => switch (source) {
    VoiceSource.studio => AppColors.triageGreenBg,
    VoiceSource.synthesized => AppColors.primaryLight,
    VoiceSource.systemTts => AppColors.primaryLight,
    VoiceSource.linguaFranca => AppColors.triageAmberBg,
    VoiceSource.readAloud => AppColors.canvas,
  };

  Color get _fg => switch (source) {
    VoiceSource.studio => AppColors.triageGreen,
    VoiceSource.synthesized => AppColors.primaryDeep,
    VoiceSource.systemTts => AppColors.primaryDeep,
    VoiceSource.linguaFranca => AppColors.triageAmber,
    VoiceSource.readAloud => AppColors.inkFaint,
  };

  IconData get _icon => switch (source) {
    VoiceSource.studio => Icons.mic_rounded,
    VoiceSource.synthesized => Icons.graphic_eq_rounded,
    VoiceSource.systemTts => Icons.record_voice_over_rounded,
    VoiceSource.linguaFranca => Icons.translate_rounded,
    VoiceSource.readAloud => Icons.menu_book_rounded,
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
            source.labelFor(language),
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
    this.spoken,
    this.spokenLanguage,
    this.verified = false,
    this.spokenIsAudible = false,
  });
  final String english;

  /// The words in the user's language — what the clips speak (bank
  /// playback) or the draft a preview shows.
  final String? spoken;
  final String? spokenLanguage;
  final bool verified;

  /// True when the bank actually played [spoken] — the sheet leads with
  /// those words, because the sheet is titled "The spoken message" and
  /// that is what was heard. Draft previews only surface their words when
  /// a speaker has signed off.
  final bool spokenIsAudible;
}

class _ScriptSheet extends StatelessWidget {
  const _ScriptSheet({required this.outcome, required this.resolved});
  final VoiceOutcome outcome;
  final _ResolvedScript resolved;

  @override
  Widget build(BuildContext context) {
    // The sheet leads with the words that were heard — in the user's
    // language when the bank played — and always shows the English card
    // text below it. The pill tells the truth about which voice played.
    final hasSpoken = resolved.spoken != null;
    final showSpoken =
        resolved.spokenIsAudible || (hasSpoken && resolved.verified);
    final displayText = showSpoken ? resolved.spoken! : resolved.english;

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
                Text('The spoken message', style: AppType.title),
              ],
            ),
            const SizedBox(height: 4),
            _SourcePill(
              source: outcome.source,
              language: outcome.request.preferredLanguage,
            ),
            if (hasSpoken) ...[
              const SizedBox(height: 6),
              _LangBadge(
                language: resolved.spokenLanguage!,
                verified: resolved.verified,
              ),
            ],
            const SizedBox(height: Gap.md),
            Text(
              outcome.source == VoiceSource.readAloud
                  ? 'There is no voice on this phone for this language yet. '
                        'The words are below — read them aloud, or ask '
                        'someone to.'
                  : outcome.source == VoiceSource.synthesized
                  ? 'This is a ${outcome.request.preferredLanguage} voice '
                        'built into the app — synthesized offline from '
                        'Meta\'s open MMS model speaking draft words. A '
                        'human recording would sound warmer; a native '
                        'speaker should listen and sign off.'
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
                  if (hasSpoken &&
                      (resolved.verified || resolved.spokenIsAudible)) ...[
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
