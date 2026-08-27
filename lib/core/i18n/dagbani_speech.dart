/// Dagbani speech-bank mapping — which WAV plays for which screen moment.
///
/// [DagbaniStrings] holds the *wording*; this file holds the *clip map*: the
/// runtime audio ids that `assets/audio/dagbani_mms/` carries and the draft
/// Dagbani each clip speaks, so the script sheet can show exactly what was
/// heard.
///
/// The map only covers closed sets — triage levels, the three caregiver
/// verdicts, the words-for-the-nurse frame. Open-ended text (engine
/// rationale, growth numbers) is deliberately absent: the honest chain
/// degrades it to the Hausa bridge or read-aloud rather than pretending a
/// clip exists. Every entry is a draft, exactly like [DagbaniStrings] —
/// the audio pill and the sheet badge say so.
///
/// The WAV files themselves come from `tool/generate_dagbani_speech.py`,
/// which mirrors the `dagbani` text below; `test/unit/dagbani_speech_test.dart`
/// fails the build if any id here is missing from the bundled bank.
library;

import 'package:flutter/foundation.dart';

import 'dagbani_strings.dart';

/// One bundled Dagbani clip: its asset id, the English sentence it carries,
/// and the draft Dagbani words it actually speaks.
@immutable
class DagbaniClip {
  const DagbaniClip({
    required this.id,
    required this.english,
    required this.dagbani,
    this.notes,
  });

  /// The bank file name without the extension, e.g. `level_urgent`.
  final String id;

  /// What the clip says, in English — the gloss a reviewer reads.
  final String english;

  /// The draft Dagbani the clip speaks. Must match
  /// `tool/generate_dagbani_speech.py` exactly.
  final String dagbani;

  /// What still needs a native speaker's ear, same convention as
  /// [LocalizedString.notes].
  final String? notes;
}

abstract final class DagbaniSpeech {
  // ------------------------------------------------- Triage-level messages
  // One clip per TriageLevel.name — the family-facing sentence for the
  // outcome. The result screen's verdict and family-brief buttons both play
  // it: the clinical classification stays in English for the CHO, while the
  // sentence the mother must act on is heard in her language.

  static const levelUrgent = DagbaniClip(
    id: 'level_urgent',
    english: 'Go to the health facility now. Do not wait until tomorrow.',
    dagbani:
        'Yi tiŋ bɛ ni kpeeni pam. Tɔ di mali kpeenim maa nyɛla din '
        'gbanŋɛ.',
    notes:
        'Reuses the verdict sentence and the "do not wait" pattern from '
        'the child danger-signs draft.',
  );

  static const levelPriority = DagbaniClip(
    id: 'level_priority',
    english:
        'The medicine has been given. Give every dose and come back in '
        'three days.',
    dagbani:
        'Tɔ sɔŋsi nira maa ti ti bini maa. Maani sɔŋsi tiŋ maa, ka yi '
        'tiŋ labina dabaasi ata nyaaŋa.',
    notes:
        '"Dabaasi ata nyaaŋa" = after three days. Dose wording needs a '
        'CHO review.',
  );

  static const levelWatch = DagbaniClip(
    id: 'level_watch',
    english:
        'Care for the person at home and watch closely. Come back if it '
        'gets worse.',
    dagbani:
        'Tin yaa ka ti maani sɔŋsi tiŋ maa. Gbilsim niŋ kpeenim. Ni '
        'bini maa ti niŋ tuma, yi tiŋ labina.',
    notes: '"Gbilsim niŋ kpeenim" = watch closely. Plain but unverified.',
  );

  static const levelRoutine = DagbaniClip(
    id: 'level_routine',
    english: 'All is well. Keep feeding well and keep the care going.',
    dagbani: 'Bini maa nyɛla din yaa. Ti maani sɔŋsi tiŋ maa ka o nu tana.',
    notes:
        '"Nu tana" = breastfeed; for an older child the feeding verb may '
        'need adjusting.',
  );

  // -------------------------------------------- Caregiver verdict messages
  // The three outcomes of the caregiver Quick Home Check, mirroring
  // `_TriageVerdict` in caregiver_home.dart. Each clip carries the headline
  // and the advice so the verdict button plays the whole result.

  static const caregiverVerdictUrgent = DagbaniClip(
    id: 'caregiver_verdict_urgent',
    english:
        'Go to the health facility now. Danger signs are present. Do '
        'not wait until tomorrow. If the CHPS compound is closed, go to '
        'the health centre or the district hospital.',
    dagbani:
        'Yi tiŋ bɛ ni kpeeni pam. Bini maa zuɣu m-beni. Tɔ di mali '
        'kpeenim maa nyɛla din gbanŋɛ. Ni CHPS tiŋ maa kpari, yi tiŋ '
        'alaafee yili bee ashibiti titali.',
    notes:
        '"Bini maa zuɣu m-beni" = the warning signs are present. Facility '
        'names need a local ear.',
  );

  static const caregiverVerdictCaution = DagbaniClip(
    id: 'caregiver_verdict_caution',
    english:
        'Visit your CHW soon. Some answers are not clear. Bring this '
        'person to the clinic at the next scheduled contact, and watch '
        'closely for the next two days.',
    dagbani:
        'Ti sɔŋsi nira maa ni kpeenim laɣim. Mi bɛ mi bini shɛŋa. Yi '
        'tiŋ labina ni tiŋ maa dabaasi ayi puuni.',
    notes:
        'Condenses the English advice; the two-day window wording needs '
        'review.',
  );

  static const caregiverVerdictFine = DagbaniClip(
    id: 'caregiver_verdict_fine',
    english:
        'Continue routine care. None of the danger signs are present. '
        'Keep feeding, keep drinking, and check again tomorrow.',
    dagbani:
        'Tin yaa ka ti maani sɔŋsi tiŋ maa. Bini maa zuɣu maa bɛni. Ti '
        'maani sɔŋsi tiŋ maa, ka ti labina tooni.',
    notes: 'Reuses the verdict-fine draft as the opening.',
  );

  // ------------------------------------------------------ Words for nurse
  // The frame of the "words for the nurse" sheet. The sign statements
  // themselves reuse the question clips (the sign drafts are statements
  // already — "Bini maa ti zuɣa" = the child has fits), so the composed
  // audio is intro + the chosen signs + the unsure preamble + close.

  static const nurseIntro = DagbaniClip(
    id: 'nurse_intro',
    english: 'What I noticed:',
    dagbani: 'N ni nya bini shɛŋa n-yɛliya.',
    notes: 'Lit. "the things I saw, I have said them".',
  );

  static const nurseUnsure = DagbaniClip(
    id: 'nurse_unsure',
    english: 'I was not sure about:',
    dagbani: 'Mi bɛ mi bini shɛŋa ŋɔ.',
    notes: 'Reuses the "mi bɛ mi" unsure answer word.',
  );

  static const nurseClose = DagbaniClip(
    id: 'nurse_close',
    english: 'I will say when each sign started.',
    dagbani: 'N yɛn yɛliya bini kam ni daa piligi shɛm.',
    notes: 'The onset-timeline sentence, matching the sheet close.',
  );

  // ------------------------------------------------------------ Standalone
  // One-off clips: the language preview at registration and the voice-test
  // screen. Both speak the app's most important sentence so a new user
  // hears Dagbani the moment they choose it.

  static const setupPreview = DagbaniClip(
    id: 'setup_preview_Dagbani',
    english: 'Go to the health facility now',
    dagbani: 'Yi tiŋ bɛ ni kpeeni pam',
    notes:
        'Same draft as DagbaniStrings.verdictUrgent — the sentence the '
        'caregiver will hear most often.',
  );

  static const voiceTest = DagbaniClip(
    id: 'voice_test_Dagbani',
    english:
        'If your child cannot drink or breastfeed, go to the health '
        'facility at once.',
    dagbani: 'Ni bini maa ti niŋ ka o nui tana, yi tiŋ bɛ ni kpeeni pam.',
    notes: 'Mirrors the Dagbani test phrase on the voice-test screen.',
  );

  // ------------------------------------------------------------ The lookup

  /// Every clip this layer can name. `test/unit/dagbani_speech_test.dart`
  /// asserts each has a bundled WAV.
  static const allClips = <DagbaniClip>[
    levelUrgent,
    levelPriority,
    levelWatch,
    levelRoutine,
    caregiverVerdictUrgent,
    caregiverVerdictCaution,
    caregiverVerdictFine,
    nurseIntro,
    nurseUnsure,
    nurseClose,
    setupPreview,
    voiceTest,
  ];

  static DagbaniClip? byId(String id) {
    for (final c in allClips) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// The family message for a [TriageLevel].name, e.g. `'priority'`.
  static DagbaniClip? levelClip(String triageName) => byId('level_$triageName');

  /// The verdict message for a caregiver verdict name (`urgent`, `caution`,
  /// `fine`).
  static DagbaniClip? caregiverVerdictClip(String verdictName) =>
      byId('caregiver_verdict_$verdictName');

  /// The ordered clip ids for the words-for-the-nurse composition. [yesKeys]
  /// and [unsureKeys] are full question keys (`newborn.feed`) — the same
  /// keys the Quick Home Check plays with — because the statement clips are
  /// the question clips.
  static List<String> clipsForNurseWords({
    required List<String> yesKeys,
    required List<String> unsureKeys,
  }) => [
    nurseIntro.id,
    for (final key in yesKeys) 'q_$key',
    if (unsureKeys.isNotEmpty) nurseUnsure.id,
    for (final key in unsureKeys) 'q_$key',
    nurseClose.id,
  ];

  /// The Dagbani text a clip list speaks — for the script sheet. Question
  /// clips resolve through [DagbaniStrings]; frame clips through this
  /// registry. Returns null when any clip is unknown, so the sheet falls
  /// back to the caller's own script rather than a half-joined sentence.
  static String? scriptForClips(List<String> ids) {
    final parts = <String>[];
    for (final id in ids) {
      final clip = byId(id);
      if (clip != null) {
        parts.add(clip.dagbani);
        continue;
      }
      if (id.startsWith('q_')) {
        final s = DagbaniStrings.forQuestionKey(id.substring(2));
        if (s != null) {
          parts.add(s.dagbani);
          continue;
        }
      }
      return null;
    }
    return parts.isEmpty ? null : parts.join(' ');
  }
}
