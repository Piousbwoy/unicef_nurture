/// "What can this phone speak?" — the diagnostic the CHO opens when they
/// want to know whether their device can handle Dagbani, Hausa, English, or
/// nothing at all.
///
/// The screen never claims more than the engine delivers. The four outcomes
/// ([VoiceSource]) are shown in the same colours the audio button uses, so
/// the language the CHO chooses during setup cannot surprise them later.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/audio/recording_script.dart';
import '../../core/audio/voice_service.dart';
import '../../core/i18n/dagbani_strings.dart';
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
            subtitle: 'This screen tests the languages CareBridge uses for '
                'spoken guidance. The result is honest: a green dot means a '
                'real voice is available, amber means a bridge, grey means '
                'the words will be on the screen instead.',
            icon: Icons.record_voice_over_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: Gap.xs),
                Row(
                  children: [
                    _LegendDot(
                      colour: AppColors.triageGreen,
                      label: 'Real voice',
                    ),
                    const SizedBox(width: Gap.md),
                    _LegendDot(
                      colour: AppColors.primary,
                      label: 'Phone voice',
                    ),
                    const SizedBox(width: Gap.md),
                    _LegendDot(
                      colour: AppColors.triageAmber,
                      label: 'Bridge',
                    ),
                    const SizedBox(width: Gap.md),
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
          const SizedBox(height: Gap.md),

          // ---------------------------------------------------- Dagbani text drafts
          SectionCard(
            title: 'Dagbani text drafts',
            subtitle: 'The plain-language Dagbani wording for the danger '
                'signs. These are drafts — a native Dagbani speaker should '
                'review and flip the "verified" flag in the source before '
                'the app shows them to caregivers.',
            icon: Icons.translate_rounded,
            child: Column(
              children: [
                for (final s in const [
                  DagbaniStrings.childDangerSigns,
                  DagbaniStrings.newbornDangerSigns,
                  DagbaniStrings.motherDangerSigns,
                  DagbaniStrings.feeding,
                  DagbaniStrings.referral,
                ])
                  _DagbaniDraftRow(s: s),
              ],
            ),
          ),
          const SizedBox(height: Gap.md),

          // ---------------------------------------------------- How to record
          SectionCard(
            title: 'How to add a real Dagbani voice',
            subtitle: 'The honest version: no commercial TTS engine supports '
                'Dagbani, and the developer of this app cannot produce one '
                'from themselves. A real Dagbani voice has to come from a real '
                'Dagbani speaker. The fastest way to get one is to put any '
                'Dagbani-speaking CHO, midwife or community member in front '
                'of a phone for 30 minutes with the script below.',
            icon: Icons.mic_external_on_rounded,
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HowToStep(
                  step: '1',
                  title: 'What a speaker can do in 30 minutes',
                  body: 'A native Dagbani speaker records 29 short lines on a '
                      'phone — 5 audio guidance topics + 24 triage questions. '
                      'The script below is the prompt. Drop the files into '
                      'assets/audio/ and the app picks them up with no code '
                      'change.',
                ),
                SizedBox(height: Gap.sm),
                _HowToStep(
                  step: '2',
                  title: 'What you, the developer, cannot do',
                  body: 'You cannot synthesise a Dagbani voice from yourself, '
                      'and you should not. Pretending to speak a language you '
                      'do not is the single fastest way to lose a CHW\'s trust. '
                      'CareBridge never invents a voice it does not have — '
                      'the pill on the audio card always says which voice '
                      'actually played.',
                ),
                SizedBox(height: Gap.sm),
                _HowToStep(
                  step: '3',
                  title: 'What works today, without any recording',
                  body: 'Hausa is the trade language across Northern Ghana. '
                      'When the phone cannot speak Dagbani, CareBridge speaks '
                      'the same message in Hausa (the amber "Bridge" pill) '
                      'or shows the words on screen (the grey "Read aloud" '
                      'pill). Care never waits on an MP3.',
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.md),

          // ---------------------------------------------------- Recording script
          SectionCard(
            title: 'The recording script',
            subtitle: '${RecordingScript.total} short lines for a Dagbani '
                'speaker to record. Open the script, share it, or copy it to '
                'your clipboard. The speaker can stop early if some questions '
                'are not relevant in their dialect.',
            icon: Icons.assignment_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.content_copy_rounded),
                        label: const Text('Copy the script'),
                        onPressed: () => _copyScript(context),
                      ),
                    ),
                    const SizedBox(width: Gap.sm),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.visibility_rounded),
                        label: const Text('Read it here'),
                        onPressed: () => _showScript(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.sm),
                Text(
                  '29 lines • 5 audio topics + 24 triage questions • '
                  '≈ 30 minutes in a quiet room. The Dagbani wording in the '
                  'script is a draft — a starting point, not a final answer. '
                  'A native speaker is the authority on what sounds natural.',
                  style: AppType.caption,
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.xl),
        ],
      ),
    );
  }

  Future<void> _copyScript(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: RecordingScript.toPlainText()));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Copied — paste it into a message to a Dagbani-speaking CHO.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showScript(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) => _ScriptSheetView(
          text: RecordingScript.toPlainText(),
          scrollController: controller,
        ),
      ),
    );
  }
}

class _ScriptSheetView extends StatelessWidget {
  const _ScriptSheetView({required this.text, required this.scrollController});
  final String text;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.sm),
            child: Row(
              children: [
                const Icon(Icons.assignment_rounded, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Recording script', style: AppType.title),
                ),
                IconButton(
                  tooltip: 'Copy',
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: text));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Copied'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.content_copy_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(Gap.lg),
              children: [
                SelectableText(
                  text,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontFamily: 'monospace',
                    height: 1.5,
                    color: AppColors.ink,
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

class _DagbaniDraftRow extends StatelessWidget {
  const _DagbaniDraftRow({required this.s});
  final LocalizedString s;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: Gap.sm),
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(Gap.radius),
        border: Border.all(color: AppColors.line, width: Gap.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.translate_rounded,
                  size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  s.key,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryDeep,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: s.verified
                      ? AppColors.triageGreenBg
                      : AppColors.triageAmberBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  s.verified ? 'VERIFIED' : 'DRAFT',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: s.verified
                        ? AppColors.triageGreen
                        : AppColors.triageAmber,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            s.english,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.ink,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            s.dagbani,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.primaryDeep,
              fontWeight: FontWeight.w600,
              height: 1.4,
              fontStyle: FontStyle.italic,
            ),
          ),
          if (s.notes != null) ...[
            const SizedBox(height: 4),
            Text(
              s.notes!,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.inkFaint,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HowToStep extends StatelessWidget {
  const _HowToStep({
    required this.step,
    required this.title,
    required this.body,
  });
  final String step;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            step,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.inkMuted,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
