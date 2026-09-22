/// "What can this phone speak?" — the diagnostic the CHO opens when they
/// want to know whether their device can handle Dagbani, Hausa, Twi,
/// English, or nothing at all.
///
/// The screen never claims more than the engine delivers. The four outcomes
/// ([VoiceSource]) are shown in the same colours the audio button uses, so
/// the language the CHO chooses during setup cannot surprise them later.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/audio/voice_service.dart';
import '../../core/i18n/speech_bank.dart';
import '../shared/offline_voice_check.dart';
import '../../core/theme/app_theme.dart';
import '../shared/audio_button.dart';
import '../shared/ui.dart';

class VoiceTestScreen extends ConsumerStatefulWidget {
  const VoiceTestScreen({super.key});

  @override
  ConsumerState<VoiceTestScreen> createState() => _VoiceTestScreenState();
}

class _VoiceTestScreenState extends ConsumerState<VoiceTestScreen> {
  List<String> _availableTts = const [];
  bool _loading = true;
  String? _error;
  static final _testPhrases = <String, String>{
    for (final language in ['English', 'Hausa', 'Dagbani', 'Twi'])
      language: language == 'English'
          ? SpeechBank.qNewbornFeed.english
          : SpeechBank.qNewbornFeed.textFor(language)!,
  };

  @override
  void initState() {
    super.initState();
    _probe();
  }

  Future<void> _probe() async {
    try {
      final langs = await VoiceService.availableTtsLanguages();
      if (!mounted) return;
      setState(() {
        _availableTts = langs;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Voice enumeration unavailable';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final preferredLanguage = user?.preferredLanguage ?? 'English';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice test'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(Gap.lg),
        children: [
          // ---------------------------------------------------- Intro
          SectionCard(
            title: 'What can this phone speak?',
            subtitle:
                'Test a fixed question in each language. Open the details '
                'beside a play button for the transcript, playback result, '
                'or voice setup. This does not certify other text.',
            icon: Icons.record_voice_over_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: Gap.xs),
                Wrap(
                  spacing: Gap.md,
                  runSpacing: Gap.xs,
                  children: const [
                    _LegendDot(
                      colour: AppColors.triageGreen,
                      label: 'Synthetic recording',
                    ),
                    _LegendDot(colour: AppColors.primary, label: 'Phone voice'),
                    _LegendDot(colour: AppColors.inkFaint, label: 'Read aloud'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.md),

          // ---------------------------------------------------- Live test
          SectionCard(
            title: 'Try a language',
            subtitle:
                'These samples use exact-content recordings when available. '
                'Use Offline voice check below to test installed dynamic voices.',
            icon: Icons.translate_rounded,
            child: Column(
              children: [
                for (final language in const [
                  'Dagbani',
                  'Hausa',
                  'Twi',
                  'English',
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: Gap.xs),
                    child: _LanguageTestRow(
                      language: language,
                      phrase: _testPhrases[language] ?? '',
                      isPreferred: language == preferredLanguage,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Gap.md),

          // ---------------------------------------------------- Coverage matrix
          SectionCard(
            title: 'Languages CareBridge supports',
            subtitle:
                'The truth about the languages this phone can and '
                'cannot speak today. Where a voice is missing, the app shows '
                'the words instead.',
            icon: Icons.language_rounded,
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(Gap.md),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _CoverageMatrix(availableTts: _availableTts, error: _error),
          ),
          OfflineVoiceCheck(language: preferredLanguage),
          const SizedBox(height: Gap.xl),
        ],
      ),
    );
  }
}

class _LanguageTestRow extends StatelessWidget {
  const _LanguageTestRow({
    required this.language,
    required this.phrase,
    required this.isPreferred,
  });

  final String language;
  final String phrase;
  final bool isPreferred;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: Gap.sm),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.line, width: Gap.hairline),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      language,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (isPreferred) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'YOUR LANGUAGE',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primaryDeep,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  phrase,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.inkMuted,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Gap.sm),
          AudioButton(
            text: phrase,
            language: language,
            sourceLanguage: language,
            id: SpeechBank.qNewbornFeed.id,
            showLanguagePicker: false,
            compact: true,
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.colour, required this.label});
  final Color colour;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.inkMuted,
            ),
          ),
        ),
      ],
    );
  }
}

class _CoverageMatrix extends StatelessWidget {
  const _CoverageMatrix({required this.availableTts, this.error});
  final List<String> availableTts;
  final String? error;

  bool _has(String locale) =>
      availableTts.any((l) => l.toLowerCase().startsWith(locale.toLowerCase()));

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (error != null)
          const Text(
            'Could not list device voices. Recordings and installed neural '
            'packs can still be tested below.',
            style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
          ),
        _CoverageRow(
          language: 'English',
          source: VoiceSource.readAloud,
          notes: _has('en')
              ? 'English locale reported. Offline capability and playback still need a test.'
              : 'No English locale reported by the phone engine.',
        ),
        _CoverageRow(
          language: 'Hausa',
          source: VoiceSource.synthesized,
          notes:
              'Exact-content synthetic recordings are bundled. Dynamic speech '
              'requires an installed voice pack. Human sign-off is pending.'
              '${_has('ha') ? ' A reported Hausa device locale is not proof of offline playback.' : ''}',
        ),
        _CoverageRow(
          language: 'Twi',
          source: VoiceSource.synthesized,
          notes:
              'Exact-content synthetic recordings are bundled. Dynamic speech '
              'requires an installed voice pack. Human sign-off is pending.',
        ),
        _CoverageRow(
          language: 'Dagbani',
          source: VoiceSource.synthesized,
          notes:
              'Exact-content synthetic recordings only; arbitrary dynamic '
              'speech is not supported. Human sign-off is pending.',
        ),
        _CoverageRow(
          language: 'Likpakpaln',
          source: VoiceSource.readAloud,
          notes:
              'No supported offline voice. Read the transcript or explicitly choose another language.',
        ),
        _CoverageRow(
          language: 'Gurene, Kusaal, Sissali, Dagaare',
          source: VoiceSource.readAloud,
          notes:
              'No supported offline voice. Read the transcript or explicitly choose another language.',
        ),
      ],
    );
  }
}

class _CoverageRow extends StatelessWidget {
  const _CoverageRow({
    required this.language,
    required this.source,
    required this.notes,
  });
  final String language;
  final VoiceSource source;
  final String notes;

  Color get _colour => switch (source) {
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(_icon, size: 18, color: _colour),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  language,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  notes,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.inkMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
