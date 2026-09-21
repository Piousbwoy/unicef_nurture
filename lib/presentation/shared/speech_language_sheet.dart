import 'package:flutter/material.dart';

import '../../core/audio/caregiver_playback.dart';
import '../../core/ml/neural_translation_service.dart';
import '../../core/theme/app_theme.dart';

/// What one language can actually give for one message: the words she would
/// read, a short availability tag, and whether a voice exists for them.
typedef SpeechOffering = ({String words, String tag, bool audioReady});

/// The single source of truth for "what happens if she picks this language".
/// Every surface that offers a language shows these words, so the choice is
/// made from the message itself rather than from a language name.
SpeechOffering speechOffering(CaregiverSpeech speech, String language) {
  final name = OfflineSpeechLanguage.canonical(language);
  if (name == 'English') {
    return (
      words: speech.english,
      tag: 'Needs a phone voice',
      audioReady: true,
    );
  }
  final localized = speech.withLanguage(name).localizedText;
  if (localized != null) {
    return (words: localized, tag: 'Ready on this phone', audioReady: true);
  }
  // The neural model only stands in for text the bank never registered; a
  // clip id that failed to match must stay untranslated.
  final uncatalogued =
      speech.clipId == null &&
      (speech.clipIds == null || speech.clipIds!.isEmpty);
  if (uncatalogued &&
      NeuralTranslationService.instance.supportsLanguage(name)) {
    return (words: speech.english, tag: 'Draft words', audioReady: true);
  }
  return (words: speech.english, tag: 'English words only', audioReady: false);
}

/// One language, shown as the words it can speak. Tapping it is the request
/// to hear it — there is no confirm step and nothing disabled.
class SpeechLanguageTile extends StatelessWidget {
  const SpeechLanguageTile({
    super.key,
    required this.speech,
    required this.language,
    required this.onSelected,
    this.selected = false,
    this.onDark = false,
    this.width,
  });

  final CaregiverSpeech speech;
  final String language;
  final ValueChanged<String> onSelected;
  final bool selected;
  final bool onDark;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final offering = speechOffering(speech, language);
    final ink = onDark ? Colors.white : AppColors.checkNavy;
    final soft = onDark ? Colors.white70 : AppColors.inkMuted;
    return Semantics(
      button: true,
      selected: selected,
      child: SizedBox(
        width: width,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onSelected(language),
            borderRadius: BorderRadius.circular(18),
            child: Ink(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
              decoration: BoxDecoration(
                color: selected
                    ? (onDark ? Colors.white : AppColors.checkNavy)
                    : (onDark
                          ? Colors.white.withValues(alpha: 0.10)
                          : AppColors.checkBlueTint),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: selected
                      ? (onDark ? Colors.white : AppColors.checkNavy)
                      : (onDark
                            ? Colors.white.withValues(alpha: 0.22)
                            : AppColors.checkNavy.withValues(alpha: 0.10)),
                  width: 1.2,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: AppColors.checkNavyDeep.withValues(
                            alpha: onDark ? 0.45 : 0.18,
                          ),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ]
                    : const [],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          language,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Sora',
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.1,
                            color: selected && onDark
                                ? AppColors.checkNavy
                                : ink,
                          ),
                        ),
                      ),
                      if (selected)
                        Icon(
                          Icons.check_circle_rounded,
                          size: 16,
                          color: onDark
                              ? AppColors.checkBlue
                              : AppColors.checkBlueLight,
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    offering.tag.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.7,
                      color: selected && onDark
                          ? AppColors.checkNavy.withValues(alpha: 0.6)
                          : (onDark
                                ? Colors.white.withValues(alpha: 0.62)
                                : AppColors.checkBlue),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    offering.words,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: selected && onDark ? AppColors.checkNavy : soft,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The language row that lives inside a screen rather than in a sheet: one
/// glance at the words, one tap to hear them.
class SpeechLanguageRail extends StatelessWidget {
  const SpeechLanguageRail({
    super.key,
    required this.speech,
    required this.selected,
    required this.onSelected,
    this.onDark = true,
  });

  final CaregiverSpeech speech;
  final String selected;
  final ValueChanged<String> onSelected;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    // Content-sized rather than a fixed-height list: at 200% text the words
    // need more lines, and a clipped card hides exactly what it is for.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final language in OfflineSpeechLanguage.names)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: SpeechLanguageTile(
                key: ValueKey('speech-language-$language'),
                speech: speech,
                language: language,
                selected:
                    OfflineSpeechLanguage.canonical(language) ==
                    OfflineSpeechLanguage.canonical(selected),
                onSelected: onSelected,
                onDark: onDark,
                width: 172,
              ),
            ),
        ],
      ),
    );
  }
}

/// The same word-first choice as a short sheet, for the audio buttons that
/// are not part of a step with room for the rail. One tap picks and plays;
/// the sheet has no confirm button and nothing disabled.
Future<String?> chooseSpeechLanguage(
  BuildContext context,
  CaregiverSpeech speech,
) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  backgroundColor: Colors.white,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
  ),
  builder: (_) => _SpeechLanguageSheet(speech: speech),
);

class _SpeechLanguageSheet extends StatelessWidget {
  const _SpeechLanguageSheet({required this.speech});

  final CaregiverSpeech speech;

  @override
  Widget build(BuildContext context) {
    final current = OfflineSpeechLanguage.canonical(speech.language);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 2, 22, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Say this in',
                  style: _sora(22, AppColors.checkNavy),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, size: 22),
                color: AppColors.inkMuted,
                tooltip: 'Close',
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Each card shows the words that language can give for this '
            'message. Tap one and it plays.',
            style: TextStyle(
              fontSize: 13.5,
              height: 1.45,
              color: AppColors.inkMuted.withValues(alpha: 0.95),
            ),
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, box) => Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final language in OfflineSpeechLanguage.names)
                  SizedBox(
                    width: (box.maxWidth - 10) / 2,
                    child: SpeechLanguageTile(
                      key: ValueKey('speech-language-$language'),
                      speech: speech,
                      language: language,
                      selected:
                          OfflineSpeechLanguage.canonical(language) == current,
                      onDark: false,
                      onSelected: (chosen) => Navigator.of(context).pop(chosen),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
            decoration: BoxDecoration(
              color: AppColors.checkBlueTint,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              'Words already on this phone are used as they are; nothing is '
              "downloaded. Draft wording still needs a native speaker's ear "
              'and clinical review.',
              style: const TextStyle(
                fontSize: 12,
                height: 1.45,
                fontWeight: FontWeight.w600,
                color: AppColors.checkNavy,
              ),
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _sora(double size, Color color) => TextStyle(
    fontFamily: 'Sora',
    fontSize: size,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.3,
    color: color,
  );
}
