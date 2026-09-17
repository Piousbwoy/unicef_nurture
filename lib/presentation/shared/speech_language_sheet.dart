import 'package:flutter/material.dart';

import '../../core/audio/caregiver_playback.dart';

/// Chooses a language for this message only. Opening, previewing and dismissing
/// this sheet never starts playback or changes the saved language preference.
Future<String?> chooseSpeechLanguage(
  BuildContext context,
  CaregiverSpeech speech,
) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => _SpeechLanguageSheet(speech: speech),
);

class _SpeechLanguageSheet extends StatefulWidget {
  const _SpeechLanguageSheet({required this.speech});

  final CaregiverSpeech speech;

  @override
  State<_SpeechLanguageSheet> createState() => _SpeechLanguageSheetState();
}

class _SpeechLanguageSheetState extends State<_SpeechLanguageSheet> {
  late String _language = OfflineSpeechLanguage.canonical(widget.speech.language);

  @override
  Widget build(BuildContext context) {
    final speech = widget.speech.withLanguage(_language);
    final transcript = speech.localizedText;
    final isEnglish = _language == 'English';
    final theme = Theme.of(context);

    return FractionallySizedBox(
      heightFactor: 0.9,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text('Choose a speech language', style: theme.textTheme.titleLarge),
              ),
              const SizedBox(height: 8),
              const Text(
                'For this message only. Your saved language stays the same. '
                'Audio uses only voices already on this phone; nothing is downloaded.',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final language in OfflineSpeechLanguage.names)
                    ChoiceChip(
                      key: ValueKey('speech-language-$language'),
                      label: Text(language),
                      selected: _language == language,
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                      onSelected: (_) => setState(() => _language = language),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  isEnglish
                      ? 'English audio needs an installed offline English voice on this phone. '
                            'If none is available, you can still read the text.'
                      : transcript == null
                      ? 'No $_language translation is available offline for this exact message. '
                            'Audio in $_language is unavailable. Read the English original below, '
                            'or choose English explicitly.'
                      : 'Draft $_language translation from the bundled speech bank. '
                            'Bundled voices are synthetic. The words need native-speaker and clinical review. '
                            'Playback depends on a bundled clip or an installed offline voice in $_language.',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const ValueKey('speech-language-listen'),
                onPressed: transcript == null
                    ? null
                    : () => Navigator.of(context).pop(_language),
                icon: const Icon(Icons.volume_up_rounded),
                label: Text('Listen in $_language', textAlign: TextAlign.center),
              ),
              if (!isEnglish)
                OutlinedButton(
                  onPressed: () => setState(() => _language = 'English'),
                  child: const Text('Choose English'),
                ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(height: 12),
              if (transcript != null) ...[
                Text(
                  '$_language transcript',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(transcript, style: const TextStyle(height: 1.5)),
              ],
              if (!isEnglish) ...[
                const SizedBox(height: 16),
                Text('English original', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(widget.speech.english, style: const TextStyle(height: 1.5)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
