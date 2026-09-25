import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/audio/audio_guide.dart';
import '../../../core/audio/caregiver_playback.dart';
import '../../../core/i18n/speech_bank.dart';
import '../caregiver_providers.dart';
import '../widgets/companion.dart';
import 'caregiver_voice.dart';

class CaregiverAudioGuideScreen extends ConsumerStatefulWidget {
  const CaregiverAudioGuideScreen({super.key, required this.householdId});
  final String householdId;
  @override
  ConsumerState<CaregiverAudioGuideScreen> createState() =>
      _AudioGuideScreenState();
}

class _AudioGuideScreenState extends ConsumerState<CaregiverAudioGuideScreen> {
  String? _language;
  CaregiverVoiceController? _voice;
  @override
  void dispose() {
    _voice?.stop(notify: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(caregiverScopeProvider);
    if (scope == null || scope.householdId != widget.householdId) {
      return const SizedBox.shrink();
    }
    _voice = ref.watch(caregiverVoiceProvider(scope));
    final language =
        _language ??
        ref.watch(currentUserProvider)?.preferredLanguage ??
        'English';
    final languages = {'English', ...SpeechBank.bankLanguages.keys, language};
    return CompanionPage(
      title: 'Voice',
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          CompanionCard(
            title: 'Listen at your pace',
            eyebrow: 'YOUR OFFLINE LIBRARY',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Choose a language for each message, then listen or stop whenever you like. Bundled voices are synthetic draft translations that need native-speaker and clinical review. Untranslated guidance is clearly marked; the app never switches to English without your choice.',
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: language,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Preferred listening language',
                  ),
                  items: [
                    for (final name in languages)
                      DropdownMenuItem(value: name, child: Text(name)),
                  ],
                  onChanged: (value) {
                    _voice?.stop();
                    setState(() => _language = value);
                  },
                ),
              ],
            ),
          ),
          for (final topic in AudioTopic.values)
            CompanionCard(
              title: topic == AudioTopic.motherDangerSigns
                  ? 'Danger signs in pregnancy or after birth'
                  : topic.title,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(_script(topic)),
                  const SizedBox(height: 16),
                  CaregiverListen(
                    speech: CaregiverSpeech(
                      id: 'topic:${topic.id}:$language',
                      english: _script(topic),
                      language: language,
                      clipId: switch (topic) {
                        AudioTopic.childDangerSigns ||
                        AudioTopic.newbornDangerSigns => topic.id,
                        _ =>
                          null, // Revised copy must not play old translations as equivalents.
                      },
                    ),
                  ),
                ],
              ),
            ),
          const Text(
            'After installation or initial web caching, bundled clips and text work without internet. Device speech depends on voices installed on this device; it may be unavailable offline.',
          ),
        ],
      ),
    );
  }
}

// Review references: WHO IMCI (2014), Pregnancy, Childbirth, Postpartum and
// Newborn Care (2015), complementary feeding guideline (2023). Clinical review
// remains a deployment gate; existing translated clips are not changed.
String _script(AudioTopic topic) => switch (topic) {
  AudioTopic.childDangerSigns || AudioTopic.newbornDangerSigns => topic.script,
  AudioTopic.motherDangerSigns =>
    'Heavy bleeding, severe headache with blurred vision, high fever, severe belly pain, fits, or foul-smelling discharge need urgent assessment. If pregnant and the baby is moving less than before, seek care now. Do not wait for this app or for pain to pass.',
  AudioTopic.feeding =>
    'Under six months, support breastfeeding and seek individual feeding help when needed. Do not add water, porridge, or family foods. If breastfeeding is not possible, ask a qualified health worker for safe feeding support. From six months, offer safely prepared age-appropriate foods alongside breastfeeding if you breastfeed. Follow any prescribed feeding plan. The food planner provides general ideas, not a prescribed diet.',
  AudioTopic.referral =>
    'Follow the urgency and instructions on the referral given by your health worker. Take available records, but do not delay emergency care for missing documents. Ask a trusted person or health worker about transport if needed. This app cannot arrange transport or guarantee help. Show the readable report to the health worker at the facility.',
};
