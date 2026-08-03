/// "How to give CareBridge a Dagbani voice in 30 minutes."
///
/// This is the **only** way a real Dagbani voice reaches the app: a native
/// speaker records these lines on a phone, the recordings are dropped into
/// `assets/audio/`, and the [VoiceService] picks them up automatically — no
/// code change, no rebuild, no app update.
///
/// Why this file exists, in one paragraph: the developer of CareBridge
/// cannot produce a real Dagbani voice from themselves. No commercial TTS
/// engine supports Dagbani. No on-device model exists. Any cloud TTS that
/// *might* cover it breaks the offline-first, no-PHI-leaves-the-device
/// contract that the app depends on. A real Dagbani voice has to come from
/// a real Dagbani speaker. So the question is not "can the AI implement
/// this?" — it cannot — but "how quickly can a Dagbani speaker be put in
/// front of a phone for 30 minutes?" This file is the answer.
///
/// **The flow:**
///   1. Share this file (or the markdown version) with a Dagbani-speaking
///      CHO, midwife, or community member.
///   2. They record each line on any phone voice-memo app.
///   3. Save each recording as the file name shown here, in MP3 or M4A.
///   4. Drop the files into `assets/audio/` in this project.
///   5. Rebuild the app. The audio buttons now use the real voice.
///
/// All the [dagbaniDraft] values here mirror [DagbaniStrings]. They are
/// **drafts** — a starting point the speaker is free to improve. The
/// speaker is the authority, not this code.
library;

import '../i18n/dagbani_strings.dart';

/// One line in the recording script.
class RecordingLine {
  const RecordingLine({
    required this.id,
    required this.fileName,
    required this.english,
    required this.dagbaniDraft,
    required this.instruction,
    this.section,
  });

  /// The asset id (without language suffix), e.g. `child_danger_signs`.
  final String id;

  /// The exact file name to drop into `assets/audio/`, e.g.
  /// `child_danger_signs_dagbani.mp3`.
  final String fileName;

  /// The English source so the speaker knows what they are saying.
  final String english;

  /// A starting-point Dagbani wording. The speaker can read it as is or
  /// rephrase in their own dialect — the recording is the source of truth,
  /// not this string.
  final String dagbaniDraft;

  /// How to read the line: tone, pace, who the imagined listener is.
  final String instruction;

  /// Optional section header (e.g. "Newborn danger signs").
  final String? section;
}

/// The full recording guide. Open this in the app or share it as text.
abstract final class RecordingScript {
  /// The five audio guidance topics.
  static final List<RecordingLine> audioTopics = [
    RecordingLine(
      id: 'child_danger_signs',
      fileName: 'child_danger_signs_dagbani.mp3',
      section: 'Audio topics — read at the end of a danger-sign check',
      english:
          'If your child cannot drink or breastfeed, vomits everything, has '
          'fits, becomes very sleepy or hard to wake, breathes fast or with '
          'difficulty, or has blood in the stool — go to the health facility '
          'at once. Do not wait until tomorrow. These signs mean the child '
          'needs help today.',
      dagbaniDraft: DagbaniStrings.childDangerSigns.dagbani,
      instruction:
          'Read calmly, like telling a worried mother what to do. End with the '
          'return-immediately signs.',
    ),
    RecordingLine(
      id: 'newborn_danger_signs',
      fileName: 'newborn_danger_signs_dagbani.mp3',
      english:
          'If your baby is not feeding well, breathes fast or grunts, has '
          'fits, is very sleepy or hard to wake, feels very hot or very cold, '
          'has yellow hands or feet, or the cord is red or smells bad — go to '
          'the health facility at once. A small baby can become seriously ill '
          'very quickly, so do not wait.',
      dagbaniDraft: DagbaniStrings.newbornDangerSigns.dagbani,
      instruction:
          'Speak slowly — newborn danger signs are the most time-critical. '
          'Pause after each sign.',
    ),
    RecordingLine(
      id: 'mother_danger_signs',
      fileName: 'mother_danger_signs_dagbani.mp3',
      english:
          'If a mother bleeds heavily, has a severe headache with blurred '
          'eyes, has high fever, severe belly pain, fits, or foul-smelling '
          'discharge — go to the health facility at once. If she is pregnant '
          'and the baby moves less than before, go the same day. Do not wait '
          'for the pain to pass.',
      dagbaniDraft: DagbaniStrings.motherDangerSigns.dagbani,
      instruction:
          'Urgent but not panicked. The mother or her family is the listener.',
    ),
    RecordingLine(
      id: 'feeding',
      fileName: 'feeding_dagbani.mp3',
      english:
          'Give only breastmilk until six months — no water, no porridge. '
          'From six months, give thick porridge four times a day, and add '
          'groundnut paste, egg, fish or beans as they become available. Keep '
          'breastfeeding until two years. A child who eats often, grows.',
      dagbaniDraft: DagbaniStrings.feeding.dagbani,
      instruction: 'Reassuring, instructive tone. The grandmother is listening.',
    ),
    RecordingLine(
      id: 'referral',
      fileName: 'referral_dagbani.mp3',
      english:
          'A referral means the health worker believes the facility can do '
          'something this compound cannot. Go as soon as you are told — the '
          'same day if it is urgent. Carry this phone or the paper code, and '
          'show it at the gate. If transport is the problem, tell the health '
          'worker; there are ways to help.',
      dagbaniDraft: DagbaniStrings.referral.dagbani,
      instruction: 'Practical, action-oriented. A caregiver is about to travel.',
    ),
  ];

  /// The 24 triage yes / no questions across newborn (8), child (8) and
  /// mother (8). Each is a short question the caregiver hears before they
  /// answer yes / no / not sure.
  static final List<RecordingLine> triageQuestions = [
    // Newborn (8)
    RecordingLine(
      id: 'q_newborn_feed',
      fileName: 'q_newborn_feed_dagbani.mp3',
      section: 'Newborn danger signs — read as the question, not the answer',
      english: 'Is the baby feeding well?',
      dagbaniDraft: 'Bini kpalansi maa ti nu tana?',
      instruction: 'A simple question. Pause for the answer.',
    ),
    RecordingLine(
      id: 'q_newborn_fast',
      fileName: 'q_newborn_fast_dagbani.mp3',
      english: 'Is the baby breathing fast, or grunting when breathing?',
      dagbaniDraft: 'Bini kpalansi maa ɣiri tɔɣi bee ka o gbili?',
      instruction: 'Question tone. The grunting sign is the unusual one.',
    ),
    RecordingLine(
      id: 'q_newborn_fits',
      fileName: 'q_newborn_fits_dagbani.mp3',
      english: 'Has the baby had any fits or convulsions?',
      dagbaniDraft: 'Bini kpalansi maa ti zuɣa?',
      instruction: 'Direct question.',
    ),
    RecordingLine(
      id: 'q_newborn_sleepy',
      fileName: 'q_newborn_sleepy_dagbani.mp3',
      english: 'Is the baby very sleepy, or hard to wake?',
      dagbaniDraft: 'Bini kpalansi maa wum kpibu pam bee ka o ti mɔri?',
      instruction: 'Question tone.',
    ),
    RecordingLine(
      id: 'q_newborn_temp',
      fileName: 'q_newborn_temp_dagbani.mp3',
      english: 'Does the baby feel very hot, or very cold, to touch?',
      dagbaniDraft: 'Bini kpalansi maa bini pam bee ka o ti bini pam?',
      instruction: 'Question tone. Either-or.',
    ),
    RecordingLine(
      id: 'q_newborn_yellow',
      fileName: 'q_newborn_yellow_dagbani.mp3',
      english: 'Do the hands or feet look yellow?',
      dagbaniDraft: 'Bini kpalansi maa yaa-ŋa bee nini ɣari?',
      instruction: 'Question tone.',
    ),
    RecordingLine(
      id: 'q_newborn_cord',
      fileName: 'q_newborn_cord_dagbani.mp3',
      english: 'Is the cord red, swollen, or does it smell bad?',
      dagbaniDraft: 'Tuli kpamba maa kɔbigu, o pɔŋ, bee o yiɣiri ni bini?',
      instruction: 'Question tone.',
    ),
    RecordingLine(
      id: 'q_newborn_vomit',
      fileName: 'q_newborn_vomit_dagbani.mp3',
      english: 'Is the baby vomiting everything?',
      dagbaniDraft: 'Bini kpalansi maa yiɣiri bini maa pam?',
      instruction: 'Question tone.',
    ),

    // Child (8)
    RecordingLine(
      id: 'q_child_drink',
      fileName: 'q_child_drink_dagbani.mp3',
      section: 'Child danger signs',
      english: 'Can the child drink or breastfeed?',
      dagbaniDraft: 'Bini maa ti ni tooi nu tana bee ka o nu?',
      instruction: 'Question tone.',
    ),
    RecordingLine(
      id: 'q_child_vomit',
      fileName: 'q_child_vomit_dagbani.mp3',
      english: 'Is the child vomiting everything?',
      dagbaniDraft: 'Bini maa yiɣiri bini maa pam?',
      instruction: 'Question tone.',
    ),
    RecordingLine(
      id: 'q_child_fits',
      fileName: 'q_child_fits_dagbani.mp3',
      english: 'Has the child had any fits or convulsions?',
      dagbaniDraft: 'Bini maa ti zuɣa?',
      instruction: 'Question tone.',
    ),
    RecordingLine(
      id: 'q_child_sleepy',
      fileName: 'q_child_sleepy_dagbani.mp3',
      english: 'Is the child very sleepy, or hard to wake?',
      dagbaniDraft: 'Bini maa wum kpibu pam bee ka o ti mɔri?',
      instruction: 'Question tone.',
    ),
    RecordingLine(
      id: 'q_child_breath',
      fileName: 'q_child_breath_dagbani.mp3',
      english: 'Is the child breathing fast, or with difficulty?',
      dagbaniDraft: 'Bini maa ɣiri tɔɣi bee ka o ti ɣiri ti tuhi?',
      instruction: 'Question tone.',
    ),
    RecordingLine(
      id: 'q_child_blood',
      fileName: 'q_child_blood_dagbani.mp3',
      english: 'Is there blood in the stool?',
      dagbaniDraft: 'Nɔri bɛ bini maa tuhi?',
      instruction: 'Question tone. The topic is sensitive; matter-of-fact.',
    ),
    RecordingLine(
      id: 'q_child_thin',
      fileName: 'q_child_thin_dagbani.mp3',
      english: 'Is the child becoming very thin, or are the feet swollen?',
      dagbaniDraft: 'Bini maa ti pɔŋ nini pam, bee o ti nɔri pɔŋ?',
      instruction: 'Question tone.',
    ),
    RecordingLine(
      id: 'q_child_fever',
      fileName: 'q_child_fever_dagbani.mp3',
      english: 'Has the child had a fever for more than three days?',
      dagbaniDraft: 'Bini maa ti bini ti pii dabaasi anahi?',
      instruction: 'Question tone.',
    ),

    // Mother (8)
    RecordingLine(
      id: 'q_mother_bleed',
      fileName: 'q_mother_bleed_dagbani.mp3',
      section: 'Mother danger signs',
      english: 'Is the mother bleeding heavily?',
      dagbaniDraft: 'Naɣa maa kɔbigu pam?',
      instruction: 'Urgent question tone.',
    ),
    RecordingLine(
      id: 'q_mother_head',
      fileName: 'q_mother_head_dagbani.mp3',
      english: 'Does the mother have a severe headache with blurred eyes?',
      dagbaniDraft: 'Naɣa maa m bɛ laɣim pam ti o gɔri ti ti mali yɛn?',
      instruction: 'Question tone.',
    ),
    RecordingLine(
      id: 'q_mother_fever',
      fileName: 'q_mother_fever_dagbani.mp3',
      english: 'Does the mother have a high fever?',
      dagbaniDraft: 'Naɣa maa bini pam?',
      instruction: 'Question tone.',
    ),
    RecordingLine(
      id: 'q_mother_pain',
      fileName: 'q_mother_pain_dagbani.mp3',
      english: 'Does the mother have severe belly pain?',
      dagbaniDraft: 'Naɣa maa ti kɔbigu taba pam?',
      instruction: 'Question tone.',
    ),
    RecordingLine(
      id: 'q_mother_fits',
      fileName: 'q_mother_fits_dagbani.mp3',
      english: 'Has the mother had any fits or convulsions?',
      dagbaniDraft: 'Naɣa maa ti zuɣa?',
      instruction: 'Urgent question tone.',
    ),
    RecordingLine(
      id: 'q_mother_smell',
      fileName: 'q_mother_smell_dagbani.mp3',
      english: 'Is there a foul-smelling discharge?',
      dagbaniDraft: 'Bini yiɣiri bɛ bini maa?',
      instruction: 'Question tone, matter-of-fact.',
    ),
    RecordingLine(
      id: 'q_mother_move',
      fileName: 'q_mother_move_dagbani.mp3',
      english: 'If she is pregnant, is the baby moving less than before?',
      dagbaniDraft:
          'Ni o bɛ ni tuhi bini, bini maa tuhi ti laɣim ni yili maa?',
      instruction: 'Question tone.',
    ),
    RecordingLine(
      id: 'q_mother_vomit',
      fileName: 'q_mother_vomit_dagbani.mp3',
      english: 'Is the mother vomiting everything?',
      dagbaniDraft: 'Naɣa maa yiɣiri bini maa pam?',
      instruction: 'Question tone.',
    ),
  ];

  /// Everything in one flat list — what the speaker should record.
  static List<RecordingLine> get all => [...audioTopics, ...triageQuestions];

  /// Total number of files to record (the speaker can stop early if some
  /// questions are not relevant in their dialect).
  static int get total => all.length;

  /// Renders the script as plain text — easy to share, print, or paste into
  /// a message to a Dagbani-speaking CHO.
  static String toPlainText() {
    final buf = StringBuffer();
    buf.writeln('How to give CareBridge a real Dagbani voice');
    buf.writeln('==========================================');
    buf.writeln();
    buf.writeln('What you need: a phone with a voice-memo app and 30 minutes.');
    buf.writeln();
    buf.writeln(
        'For each line below, tap record on your phone, read the English '
        'slowly (the app is built for elderly caregivers, so the slower the '
        'better), then save the recording with the file name shown in '
        'CAPITALS. Drop the files into the assets/audio/ folder of the '
        'CareBridge project — that is all. The app will start using the '
        'real voice the next time it is opened.');
    buf.writeln();
    buf.writeln(
        'The Dagbani wording under each line is a draft. Read it as a '
        'starting point, but the recording is the source of truth — if the '
        'draft does not sound natural in your dialect, please rephrase.');
    buf.writeln();
    buf.writeln('Tip: record in a quiet room, hold the phone about a hand\'s '
        'length from your mouth, and speak as if you are telling a worried '
        'mother what to do. End each line with a small pause so the user has '
        'time to react.');
    buf.writeln();
    buf.writeln('----------------------------------------');
    buf.writeln();

    RecordingLine? lastSection;
    for (final line in all) {
      if (line.section != null && line.section != lastSection?.section) {
        buf.writeln();
        buf.writeln('### ${line.section}');
        buf.writeln();
        lastSection = line;
      }
      buf.writeln('FILE: ${line.fileName}');
      buf.writeln('ENGLISH: ${line.english}');
      buf.writeln('DAGBANI (draft): ${line.dagbaniDraft}');
      buf.writeln('NOTE: ${line.instruction}');
      buf.writeln();
    }

    buf.writeln('----------------------------------------');
    buf.writeln('Total: $total recordings.');
    buf.writeln();
    buf.writeln(
        'When you are done, share the files with the CareBridge developer. '
        'Drop them into assets/audio/ and the next build of the app will '
        'speak Dagbani in your voice.');

    return buf.toString();
  }
}
