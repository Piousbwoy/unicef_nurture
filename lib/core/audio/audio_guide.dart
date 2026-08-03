/// Voice guidance for people who do not read.
///
/// The design is deliberately two-layered:
///
/// **The script is the product.** Every message here is written to be read
/// aloud — short sentences, no clinical vocabulary, and every topic ends with
/// the return-immediately signs, because that single habit saves more mothers
/// and children than any classification. A CHO can read it out in whatever
/// language the family speaks, and a caregiver can have it read to them.
///
/// **The voice is a chain of honest fallbacks.** When a recording is not on
/// the phone — the normal state until the studio sessions happen — the app
/// speaks the script through the device's own TTS engine, falling back to
/// the Hausa bridge when the phone cannot speak the chosen language, and
/// finally to the on-screen text. The actual voice used is exposed via
/// [VoiceService] so the UI can show an honest pill. Care never waits on
/// an MP3.
library;

import 'voice_service.dart';

/// One guidance topic. The [id] doubles as the asset file prefix.
enum AudioTopic {
  childDangerSigns(
    'child_danger_signs',
    'Danger signs in a child',
    'If your child cannot drink or breastfeed, vomits everything, has fits, '
        'becomes very sleepy or hard to wake, breathes fast or with '
        'difficulty, or has blood in the stool — go to the health facility '
        'at once. Do not wait until tomorrow. These signs mean the child '
        'needs help today.',
  ),
  newbornDangerSigns(
    'newborn_danger_signs',
    'Danger signs in a newborn baby',
    'If your baby is not feeding well, breathes fast or grunts, has fits, '
        'is very sleepy or hard to wake, feels very hot or very cold, has '
        'yellow hands or feet, or the cord is red or smells bad — go to the '
        'health facility at once. A small baby can become seriously ill very '
        'quickly, so do not wait.',
  ),
  motherDangerSigns(
    'mother_danger_signs',
    'Danger signs in a mother',
    'If a mother bleeds heavily, has a severe headache with blurred eyes, '
        'has high fever, severe belly pain, fits, or foul-smelling '
        'discharge — go to the health facility at once. If she is pregnant '
        'and the baby moves less than before, go the same day. Do not wait '
        'for the pain to pass.',
  ),
  feeding(
    'feeding',
    'Feeding your child well',
    'Give only breastmilk until six months — no water, no porridge. From six '
        'months, give thick porridge four times a day, and add groundnut '
        'paste, egg, fish or beans as they become available. Keep '
        'breastfeeding until two years. A child who eats often, grows.',
  ),
  referral(
    'referral',
    'When you are given a referral',
    'A referral means the health worker believes the facility can do '
        'something this compound cannot. Go as soon as you are told — the '
        'same day if it is urgent. Carry this phone or the paper code, and '
        'show it at the gate. If transport is the problem, tell the health '
        'worker; there are ways to help.',
  );

  const AudioTopic(this.id, this.title, this.script);

  final String id;
  final String title;

  /// The plain-language script, always available even with no recordings.
  final String script;
}

abstract final class AudioGuide {
  /// Tries to speak [topic] in [language]. Returns the full outcome so the
  /// UI can show an honest pill — studio recording, system TTS, Hausa
  /// bridge, or just the on-screen script. Never throws.
  static Future<VoiceOutcome> play(AudioTopic topic, String language) {
    return VoiceService.speak(VoiceRequest(
      id: topic.id,
      preferredLanguage: language,
      preferredScript: topic.script,
    ));
  }

  /// Tries to play one recorded question, e.g. `audio/q_feed_dagbani.mp3`.
  /// Falls back to system TTS in [language], then Hausa bridge, then text.
  /// Used by the voice-first Quick Home Check.
  static Future<VoiceOutcome> playQuestion(String key, String language) {
    return VoiceService.speak(VoiceRequest(
      id: 'q_$key',
      preferredLanguage: language,
      // The question text lives in the screen; VoiceService only needs the
      // language and a non-empty script. The caller will already have shown
      // the question text on the card, so we pass a short hint as the
      // fallback script.
      preferredScript: 'Listen to the question on the screen.',
    ));
  }

  /// Stops anything that is currently playing.
  static Future<void> stop() => VoiceService.stop();
}
