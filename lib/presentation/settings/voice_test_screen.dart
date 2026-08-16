/// "What can this phone speak?" — the diagnostic the CHO opens when they
/// want to know whether their device can handle Dagbani, Hausa, English, or
/// nothing at all.
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
  final Map<String, VoiceSource> _lastResults = {};

  static const _testPhrases = <String, String>{
    'English': 'If your child cannot drink or breastfeed, go to the health '
        'facility at once.',
    'Hausa':   'Idan yaranku ba ta iya sha ko nono, je asibitin yanzu.',
    'Dagbani': 'Ni bini maa ti niŋ ka o nui tana, yi tiŋ bɛ ni kpeeni pam.',
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _test(String language) async {
    final phrase = _testPhrases[language] ?? _testPhrases['English']!;
    final outcome = await VoiceService.speak(
      VoiceRequest(
        id: 'voice_test_$language',
        preferredLanguage: language,
        preferredScript: phrase,
        bridgeScript: _testPhrases['Hausa'],
      ),
    );
    if (!mounted) return;
    setState(() => _lastResults[language] = outcome.source);
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
            subtitle: 'Tap a language below to hear exactly what this phone '
                'will say in it. The pill under each button names the voice '
                'that actually played — this app never pretends.',
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
                      label: 'Real voice',
                    ),
                    _LegendDot(
                      colour: AppColors.primary,
                      label: 'Phone voice',
                    ),
                    _LegendDot(
                      colour: AppColors.triageAmber,
                      label: 'Bridge',
                    ),
                    _LegendDot(
                      colour: AppColors.inkFaint,
                      label: 'Read aloud',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.md),

          // ---------------------------------------------------- Live test
          SectionCard(
            title: 'Try a language',
            subtitle: 'Tap a language to hear what this phone says. The pill '
                'under the button tells you which voice was used.',
            icon: Icons.translate_rounded,
            child: Column(
              children: [
                for (final language in const [
                  'Dagbani',
                  'Hausa',
                  'English',
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: Gap.xs),
                    child: _LanguageTestRow(
                      language: language,
                      phrase: _testPhrases[language] ?? '',
                      isPreferred: language == preferredLanguage,
                      lastSource: _lastResults[language],
                      onPlay: () => _test(language),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Gap.md),

          // ---------------------------------------------------- Coverage matrix
          SectionCard(
            title: 'Languages CareBridge supports',
            subtitle: 'The truth about the languages this phone can and '
                'cannot speak today. Where a voice is missing, the app shows '
                'the words instead.',
            icon: Icons.language_rounded,
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(Gap.md),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _CoverageMatrix(
                    availableTts: _availableTts,
                    error: _error,
                  ),
          ),
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
    required this.lastSource,
    required this.onPlay,
  });

  final String language;
  final String phrase;
  final bool isPreferred;
  final VoiceSource? lastSource;
  final VoidCallback onPlay;

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
                Row(
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
                            horizontal: 6, vertical: 1),
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
                if (lastSource != null) ...[
                  const SizedBox(height: 6),
                  _ResultPill(source: lastSource!),
                ],
              ],
            ),
          ),
          const SizedBox(width: Gap.sm),
          AudioButton(
            text: phrase,
            language: language,
            id: 'voice_test_$language',
            compact: true,
          ),
        ],
      ),
    );
  }
}

class _ResultPill extends StatelessWidget {
  const _ResultPill({required this.source});
  final VoiceSource source;

  @override
  Widget build(BuildContext context) {
    final colour = switch (source) {
      VoiceSource.studio       => AppColors.triageGreen,
      VoiceSource.systemTts    => AppColors.primaryDeep,
      VoiceSource.linguaFranca => AppColors.triageAmber,
      VoiceSource.readAloud    => AppColors.inkFaint,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            source.label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: colour,
            ),
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
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.inkMuted,
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
    if (error != null) {
      return Text(
        'Could not read the voice engine: $error. The app will fall back to '
        'the on-screen text for every language.',
        style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
      );
    }
    return Column(
      children: [
        _CoverageRow(
          language: 'English',
          source: _has('en') ? VoiceSource.systemTts : VoiceSource.readAloud,
          notes: _has('en') ? 'Built into Android & iOS' : 'No engine on this device',
        ),
        _CoverageRow(
          language: 'Hausa',
          source: _has('ha') ? VoiceSource.systemTts : VoiceSource.readAloud,
          notes: _has('ha') ? 'Google TTS supports ha-NG' : 'Install a Hausa voice pack',
        ),
        _CoverageRow(
          language: 'Dagbani',
          source: VoiceSource.linguaFranca,
          notes: 'No Dagbani TTS yet. Bridge to Hausa.',
        ),
        _CoverageRow(
          language: 'Likpakpaln',
          source: VoiceSource.linguaFranca,
          notes: 'No TTS yet. Bridge to Hausa.',
        ),
        _CoverageRow(
          language: 'Gurene, Kusaal, Sissali, Dagaare',
          source: VoiceSource.linguaFranca,
          notes: 'No TTS yet. Bridge to Hausa.',
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
