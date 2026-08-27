/// On-device speech bank — which WAV plays for which screen moment, in
/// which language.
///
/// [DagbaniStrings] holds the *wording*; this file holds the *clip map*: the
/// runtime audio ids the banks carry and the draft words each clip speaks in
/// Dagbani, Hausa and Twi, so the script sheet can show exactly what was
/// heard. Every clip id is language-neutral — the meaning (`level_urgent`,
/// `q_newborn.feed`) — and the *folder* picks the voice:
/// `assets/audio/dagbani_mms/`, `assets/audio/hausa_mms/`,
/// `assets/audio/twi_mms/`.
///
/// The map only covers closed sets — the five audio topics, the 24 triage
/// questions, triage levels, the three caregiver verdicts, the
/// words-for-the-nurse frame, and the two standalone moments. Open-ended
/// text (engine rationale, growth numbers) is deliberately absent: the
/// honest chain degrades it to the Hausa bridge or read-aloud rather than
/// pretending a clip exists.
///
/// Every entry is a **draft** — the audio pill and the sheet badge say so. Hausa is drafted at high confidence;
/// Twi is a plain-language draft whose clinical terms (`sɛsɛa`, `dua`,
/// `pampɔn`, `abere`, `rebu`) need a Twi-speaking health educator's ear
/// before the words are trusted for teaching. The `notes` field lists what
/// to confirm, entry by entry.
///
/// The WAV files come from `tool/generate_dagbani_speech.py`, which mirrors
/// the text below; `test/speech_bank_test.dart` fails the build if any id
/// here is missing from a bundled bank, or if a Dagbani draft drifts from
/// `dagbani_strings.dart`.
library;

import 'package:flutter/foundation.dart';

/// One bundled clip: its asset id, the English sentence it carries, and the
/// draft words it speaks in each bank language.
@immutable
class BankScript {
  const BankScript({
    required this.id,
    required this.english,
    required this.dagbani,
    required this.hausa,
    required this.twi,
    this.notes,
  });

  /// The bank file name without the extension, e.g. `level_urgent`.
  /// Language-suffixed standalones (`setup_preview_Hausa`) name their own
  /// file inside their language's folder.
  final String id;

  /// What the clip says, in English — the gloss a reviewer reads.
  final String english;

  /// The draft Dagbani the clip speaks (mirrors `dagbani_strings.dart`).
  final String dagbani;

  /// The draft Hausa the clip speaks.
  final String hausa;

  /// The draft Twi the clip speaks.
  final String twi;

  /// What still needs a native speaker's ear — same convention as the
  /// `notes` field on strings in `dagbani_strings.dart`.
  final String? notes;

  /// The draft words this clip speaks in [language] — null for languages
  /// the bank does not carry.
  String? textFor(String language) => switch (language) {
    'Dagbani' => dagbani,
    'Hausa' => hausa,
    'Twi' => twi,
    _ => null,
  };
}

abstract final class SpeechBank {
  /// Language name → bank folder under `assets/audio/`. The chain tries the
  /// bank before system TTS for exactly these languages, because a bundled
  /// machine voice speaking the user's words beats a phone voice speaking
  /// English words.
  static const bankLanguages = <String, String>{
    'Dagbani': 'dagbani_mms',
    'Hausa': 'hausa_mms',
    'Twi': 'twi_mms',
  };

  static String? folderFor(String language) => bankLanguages[language];

  // ------------------------------------------------------------- Audio topics
  // The five caregiver audio-guide cards. Plain sentences, no clinical
  // jargon, each ending with the return-immediately signs.

  static const childDangerSigns = BankScript(
    id: 'child_danger_signs',
    english:
        'If your child cannot drink or breastfeed, vomits everything, has '
        'fits, becomes very sleepy or hard to wake, breathes fast or with '
        'difficulty, or has blood in the stool — go to the health facility '
        'at once. Do not wait until tomorrow. These signs mean the child '
        'needs help today.',
    dagbani:
        'Ni bini maa ti niŋ ka o nui tana bee ka o nu tana, o yiɣiri, o '
        'ti zuɣa, o wum kpibu, bee o maani nɔri ŋɔ zaɣa — yi tiŋ bɛ ni '
        'kpeeni pam. Tɔ di mali kpeenim maa nyɛla din gbanŋɛ. Bini maa '
        'bɔri sɔŋsi ŋɔ.',
    hausa:
        'Idan yaro ba zai iya sha ko shan nono ba, ko yana fitar da '
        'abinci gaba ɗaya, ko yana tautsiya, ko ya kwanta ba za a iya '
        'farkar da shi ba, ko numfashinsa ya yi sauri ko ya yi wahala, '
        'ko akwai jini a cikin latto — ku tafi asibiti yanzu. Kar ku '
        'jira har gobe. Waɗannan alamu sun nuna cewa yaron buƙatar '
        'taimako take a yau.',
    twi:
        'Sɛ akwadaa ntumi nnom nsuo anaasɛ ɔnnom nono, anaasɛ ɔto '
        'aduane nyinaa, anaasɛ sɛsɛa si no, anaasɛ ɔda dɛ a ɛyɛ den sɛ '
        'wobɛbue no, anaasɛ n\'ehome yɛ ntɛm anaasɛ ɛyɛ no den, anaasɛ '
        'mogya wɔ ne dua mu — kɔ ayaresabea ntɛm ara. Ntwɛn nyɛ anɔpa. '
        'Saa nsɛnkyerɛnne yi kyerɛ sɛ akwadaa no hia mmoa nnɛ.',
    notes:
        'Twi terms to confirm with a health educator: sɛsɛa (fits), dua '
        '(stool), wobɛbue no (wake them).',
  );

  static const newbornDangerSigns = BankScript(
    id: 'newborn_danger_signs',
    english:
        'If your baby is not feeding well, breathes fast or grunts, has '
        'fits, is very sleepy or hard to wake, feels very hot or very '
        'cold, has yellow hands or feet, or the cord is red or smells '
        'bad — go to the health facility at once. A small baby can '
        'become seriously ill very quickly, so do not wait.',
    dagbani:
        'Ni bini kpalansi maa ti niŋ ka o nu tana, o ɣiri tɔɣi bee o '
        'gbili, o ti zuɣa, o wum kpibu, o ti yɛɣiri pam bee o ti bini, o '
        'ti ɣari yaa-ŋa bee nini, bee o tuli kpamba ti kɔbigu bee o ti '
        'yiɣiri — yi tiŋ bɛ ni kpeeni pam. Bini kpalansi maa bɛ ni '
        'kpeenim tɔ zugiri, di ti bɛ mali ni tɔ mali ŋaani.',
    hausa:
        'Idan jariri ba ya shan nono da kyau, ko numfashinsa ya yi '
        'sauri ko yana yi wahala, ko yana tautsiya, ko ya kwanta ba za '
        'a iya farkar da shi ba, ko jikinsa ya yi zafi sosai ko sanyi '
        'sosai, ko tafafunsa ko ƙafafunsa sun yi rawaya, ko makogwaronsa '
        'ta yi ja ko ta ɓata wari — ku tafi asibiti yanzu. Jariri ƙarami '
        'na iya yin rashin lafiya cikin gaggawa, saboda haka kar ku '
        'jira.',
    twi:
        'Sɛ abofra ketewa annom nono yie, anaasɛ n\'ehome yɛ ntɛm '
        'anaasɛ ɛyɛ no den, anaasɛ sɛsɛa si no, anaasɛ ɔda dɛ a ɛyɛ den '
        'sɛ wobɛbue no, anaasɛ ne nipadua ayɛ hyew paa anaasɛ ɔserew '
        'paa, anaasɛ ne nsa ase ne nan ase ayɛ abere, anaasɛ ne pampɔn '
        'no ayɛ kɔkɔɔ anaasɛ anyare — kɔ ayaresabea ntɛm. Abofra ketewa '
        'betumi anyare ntɛm pa, enti ntwɛn.',
    notes:
        'Twi terms to confirm: abere (yellow — jaundice), pampɔn '
        '(umbilical cord).',
  );

  static const motherDangerSigns = BankScript(
    id: 'mother_danger_signs',
    english:
        'If a mother bleeds heavily, has a severe headache with blurred '
        'eyes, has high fever, severe belly pain, fits, or foul-smelling '
        'discharge — go to the health facility at once. If she is '
        'pregnant and the baby moves less than before, go the same day. '
        'Do not wait for the pain to pass.',
    dagbani:
        'Ni naɣa maa ti kɔbigu pam, o ti m bɛ laɣim pam, o ti bini pam, '
        'o ti kɔbigu taba pam, o ti zuɣa, bee o ti yiɣiri ni bini maa — '
        'yi tiŋ bɛ ni kpeeni pam. Ni o bɛ ni tuhi bini, ka bini maa '
        'tuhi ti laɣim ni yili maa, yi tiŋ kpeeni din yi na. Tɔ di mali '
        'kpeenim ka tɔ tuhi laɣim maa.',
    hausa:
        'Idan mace na zubar da jini sosai, ko ciwon kai mai ƙarfi tare '
        'da lalacewar gani, ko zazzabi mai tsanani, ko ciwon ciki mai '
        'ƙarfi, ko tautsiya, ko fitar da abu mai ɓata wari — ku tafi '
        'asibiti yanzu. Idan tana ciki kuma jaririn ya ragu da motsi '
        'fiye da yadda yake a baya, ku tafi a ranar nan. Kar ku jira '
        'har ciwon ya wuce.',
    twi:
        'Sɛ ɔbaa no mogya re gu no kɛseɛ, anaasɛ ne ti yɛ no yaw den a '
        'ne ani nnhu pɛpɛɛpɛ, anaasɛ ɔyɛ hyew denden, anaasɛ ne yafunu '
        'yɛ no yaw den, anaasɛ sɛsɛa si no, anaasɛ afoforo a ɛfiri ne '
        'mu no ayɛ hu — kɔ ayaresabea ntɛm. Sɛ ɔyɛ ɔokafo na abofra no '
        'rebu bio sɛdeɛ ɛbɛyɛ pɛ, kɔ saa ara da no. Ntwɛn nyɛ anɔpa.',
    notes:
        'Twi terms to confirm: rebu (foetal kicks), afoforo ayɛ hu '
        '(foul discharge).',
  );

  static const feeding = BankScript(
    id: 'feeding',
    english:
        'Give only breastmilk until six months — no water, no porridge. '
        'From six months, give thick porridge four times a day, and add '
        'groundnut paste, egg, fish or beans when they are available. '
        'Keep breastfeeding until two years. A child who eats often, '
        'grows.',
    dagbani:
        'Tiam kpalansi kpe maa kuli nyini, a tɔri bini — ami, tuhim. '
        'Din yi ti kpeita, tiam tuɣa nini kama anahi puuni ti maani, ka '
        'a naɣisi ti niriba shɛli nyɛla di bɛ ni bini. Tiam nyini ka '
        'bini ŋɔ ti bɛ mali ni bini titali. Bini bɛ mali ni nuhu shɛli '
        'bɛ ni tiri, o ti nɔri.',
    hausa:
        'Ba nono kawai har watanni shida — ba ruwa, ba fura. Daga '
        'watanni shida, ku ba da fura mai ƙauri sau huɗu a rana, ku '
        'kuma ƙara man gyada, ƙwai, kifi ko wake idan suna nan. Ku ci '
        'gaba da shan nono har shekaru biyu. Yaro da ke cin abinci '
        'akai-akai, girma yake yi.',
    twi:
        'Fa nono nko ara ma no kɔsi bosome nsia — nsuo biara, koko '
        'biara nni hɔ. Firi bosome nsia, fa koko a emu yɛ den ma no '
        'mpɛn nan da biara, na fa nkate, kosua, nam anaasɛ abubuo ka '
        'ho berɛ a wobɛnya. San ma no nono kɔsi mfeɛ mmienu. Akwadaa a '
        'ɔdi aduane mpɛn pii, ɔnyin.',
    notes: 'Twi term to confirm: abubuo (beans).',
  );

  static const referral = BankScript(
    id: 'referral',
    english:
        'A referral means the health worker believes the facility can do '
        'something this compound cannot. Go as soon as you are told — '
        'the same day if it is urgent. Carry this phone or the paper '
        'code, and show it at the gate. If transport is the problem, '
        'tell the health worker; there are ways to help.',
    dagbani:
        'Sɔŋsi bɛ maa nyɛla nini ti ni tooi ti shɛli ka tiŋ maa bɛ ni '
        'niŋ shɛli, amaa tiŋ bɛ tiŋ maa ti ni tooi. Yi tiŋ bɛ ni '
        'kpeeni ni bini bɛ ti m-paai ka di yɛli ni ŋɔ — din yi na maa '
        'yi kpeeni nyɛla din gbanŋɛ. Tiam tuhi telephone bini maa bee '
        'pepa bini maa, ka a tiŋ di na kpeeni. Ni bini kpeenim ti '
        'm-paai ni tihi, yɛli ti sɔŋsi nira maa; bɛ bɛ ni laɣim shɛli '
        'din ni sɔŋ.',
    hausa:
        'Nufin turo ita ce, asibitin na iya yin abin da wannan gida ba '
        'zai iya ba. Ku tafi da zarar an ce muku — ranar nan idan '
        'lamari ne na gaggawa. Ku ɗauki waya ko takardar lamba, ku '
        'nuna ta a ƙofa. Idan sufuri shine matsalar, ku faɗi wa '
        'ma\'aikacin lafiya; akwai hanyoyin taimako.',
    twi:
        'Wɔde wo referral kɔ ayaresabea a ɛso sen deɛ ɛwɔ mpɔtam hɔ, '
        'ɛfiri sɛ ɛhɔ na wɔtumi yɛ biribi a yɛntumi nyɛ wɔ ha. Kɔ ntɛm '
        'ara sɛ wɔka kyerɛ wo — da no ara sɛ ɛyɛ ntɛm. Fa wote yi '
        'anaasɛ krataa no kɔ, na kyerɛ wɔn a wɔwɔ anim. Sɛ akwan ne '
        'tebea na ɛma wontumi nkɔ a, ka kyerɛ akwankwaa no; yɛwɔ '
        'akwan a yɛfa so boa.',
    notes:
        'The most dialect-sensitive script — the transport sentence '
        'needs a local ear in every language.',
  );

  // -------------------------------------------------------- Triage questions
  // The 24 yes / unsure statements. These are the clips the Quick Home
  // Check plays question-by-question and the words-for-the-nurse sheet
  // composes into statements. The Dagbani text mirrors `dagbani_strings`
  // exactly — the test enforces it.

  static const qNewbornFeed = BankScript(
    id: 'q_newborn.feed',
    english: 'Not breastfeeding or feeding well',
    dagbani: 'Bini kpalansi maa ti nu tana',
    hausa: 'Jaririn ba ya shan nono da kyau',
    twi: 'Abofra no nnom nono yie',
  );
  static const qNewbornFast = BankScript(
    id: 'q_newborn.fast',
    english: 'Breathing fast or grunting',
    dagbani: 'Bini kpalansi maa ɣiri tɔɣi bee ka o gbili',
    hausa: 'Numfashin jaririn ya yi sauri ko yana yi wahala',
    twi: 'N\'ehome yɛ ntɛm anaasɛ ɛyɛ no den',
  );
  static const qNewbornFits = BankScript(
    id: 'q_newborn.fits',
    english: 'Fits or convulsions',
    dagbani: 'Bini kpalansi maa ti zuɣa',
    hausa: 'Jaririn na tautsiya',
    twi: 'Sɛsɛa asi no',
    notes: 'Twi term to confirm: sɛsɛa (convulsions).',
  );
  static const qNewbornSleepy = BankScript(
    id: 'q_newborn.sleepy',
    english: 'Very sleepy or hard to wake',
    dagbani: 'Bini kpalansi maa wum kpibu pam bee ka o ti mɔri',
    hausa: 'Jaririn yana yawan kwanci, farkar da shi yake da wahala',
    twi: 'Ɔda dɛ, ɛyɛ den sɛ wobɛbue no',
  );
  static const qNewbornTemp = BankScript(
    id: 'q_newborn.temp',
    english: 'Very hot or very cold to touch',
    dagbani: 'Bini kpalansi maa bini pam bee ka o ti bini pam',
    hausa: 'Jikin jaririn ya yi zafi sosai ko sanyi sosai',
    twi: 'Ne nipadua ayɛ hyew paa anaasɛ ɔserew paa',
  );
  static const qNewbornYellow = BankScript(
    id: 'q_newborn.yellow',
    english: 'Hands or feet look yellow',
    dagbani: 'Bini kpalansi maa yaa-ŋa bee nini ɣari',
    hausa: 'Tafafunsa ko ƙafafunsa sun yi rawaya',
    twi: 'Ne nsa ase ne nan ase ayɛ abere',
    notes: 'Twi term to confirm: abere (yellow).',
  );
  static const qNewbornCord = BankScript(
    id: 'q_newborn.cord',
    english: 'Cord is red, swollen or smells bad',
    dagbani: 'Tuli kpamba maa kɔbigu, o pɔŋ, bee o yiɣiri ni bini',
    hausa: 'Makogwaro ta yi ja, ta kumbura, ko ta ɓata wari',
    twi: 'Ne pampɔn no ayɛ kɔkɔɔ, ayɛ kɛseɛ, anaasɛ anyare',
    notes: 'Twi term to confirm: pampɔn (cord).',
  );
  static const qNewbornVomit = BankScript(
    id: 'q_newborn.vomit',
    english: 'Vomiting everything',
    dagbani: 'Bini kpalansi maa yiɣiri bini maa pam',
    hausa: 'Jaririn na fitar da abinci gaba ɗaya',
    twi: 'Ɔto aduane nyinaa',
  );

  static const qChildDrink = BankScript(
    id: 'q_child.drink',
    english: 'Cannot drink or breastfeed',
    dagbani: 'Bini maa ti ni tooi nu tana bee ka o nu',
    hausa: 'Yaro ba zai iya sha ko shan nono ba',
    twi: 'Akwadaa no ntumi nnom nsuo anaasɛ nono',
  );
  static const qChildVomit = BankScript(
    id: 'q_child.vomit',
    english: 'Vomiting everything',
    dagbani: 'Bini maa yiɣiri bini maa pam',
    hausa: 'Yaron na fitar da abinci gaba ɗaya',
    twi: 'Ɔto aduane nyinaa',
  );
  static const qChildFits = BankScript(
    id: 'q_child.fits',
    english: 'Fits or convulsions',
    dagbani: 'Bini maa ti zuɣa',
    hausa: 'Yaron na tautsiya',
    twi: 'Sɛsɛa asi no',
  );
  static const qChildSleepy = BankScript(
    id: 'q_child.sleepy',
    english: 'Very sleepy or hard to wake',
    dagbani: 'Bini maa wum kpibu pam bee ka o ti mɔri',
    hausa: 'Yaron yana yawan kwanci, farkar da shi yake da wahala',
    twi: 'Ɔda dɛ, ɛyɛ den sɛ wobɛbue no',
  );
  static const qChildBreath = BankScript(
    id: 'q_child.breath',
    english: 'Breathing fast or with difficulty',
    dagbani: 'Bini maa ɣiri tɔɣi bee ka o ti ɣiri ti tuhi',
    hausa: 'Numfashin yaron ya yi sauri ko yana yi wahala',
    twi: 'N\'ehome yɛ ntɛm anaasɛ ɛyɛ no den',
  );
  static const qChildBlood = BankScript(
    id: 'q_child.blood',
    english: 'Blood in the stool',
    dagbani: 'Nɔri bɛ bini maa tuhi',
    hausa: 'Akwai jini a cikin latto',
    twi: 'Mogya wɔ ne dua mu',
    notes: 'Twi term to confirm: dua (stool).',
  );
  static const qChildThin = BankScript(
    id: 'q_child.thin',
    english: 'Becoming very thin, or swollen feet',
    dagbani: 'Bini maa ti pɔŋ nini pam, bee o ti nɔri pɔŋ',
    hausa: 'Yaron ya yi rauni sosai, ko ƙafafun sa sun kumbura',
    twi: 'Akwadaa no ayɛ baree pa ara, anaasɛ ne nan ayɛ kɛseɛ',
  );
  static const qChildFever = BankScript(
    id: 'q_child.fever',
    english: 'Fever for more than three days',
    dagbani: 'Bini maa ti bini ti pii dabaasi anahi',
    hausa: 'Zazzabin yaron ya wuce kwanaki uku',
    twi: 'Ɔyɛ hyew kyɛn nnansa',
  );

  static const qMotherBleed = BankScript(
    id: 'q_mother.bleed',
    english: 'Heavy bleeding',
    dagbani: 'Naɣa maa kɔbigu pam',
    hausa: 'Mace na zubar da jini sosai',
    twi: 'Ne mogya re gu no kɛseɛ',
  );
  static const qMotherHead = BankScript(
    id: 'q_mother.head',
    english: 'Severe headache with blurred eyes',
    dagbani: 'Naɣa maa m bɛ laɣim pam ti o gɔri ti ti mali yɛn',
    hausa: 'Ciwon kai mai ƙarfi tare da lalacewar gani',
    twi: 'Ne ti yɛ no yaw den, ne ani nso annhu pɛpɛɛpɛ',
  );
  static const qMotherFever = BankScript(
    id: 'q_mother.fever',
    english: 'High fever',
    dagbani: 'Naɣa maa bini pam',
    hausa: 'Zazzabi mai tsanani',
    twi: 'Ne nipadua ayɛ hyew paa',
  );
  static const qMotherPain = BankScript(
    id: 'q_mother.pain',
    english: 'Severe belly pain',
    dagbani: 'Naɣa maa ti kɔbigu taba pam',
    hausa: 'Ciwon ciki mai ƙarfi',
    twi: 'Ne yafunu yɛ no yaw den',
  );
  static const qMotherFits = BankScript(
    id: 'q_mother.fits',
    english: 'Fits or convulsions',
    dagbani: 'Naɣa maa ti zuɣa',
    hausa: 'Mace na tautsiya',
    twi: 'Sɛsɛa asi no',
  );
  static const qMotherSmell = BankScript(
    id: 'q_mother.smell',
    english: 'Foul-smelling discharge',
    dagbani: 'Bini yiɣiri bɛ bini maa',
    hausa: 'Fitowar abu mai ɓata wari',
    twi: 'Afoforo a ɛfiri ne mu no ayɛ hu',
    notes: 'Twi term to confirm: afoforo ayɛ hu (foul discharge).',
  );
  static const qMotherMove = BankScript(
    id: 'q_mother.move',
    english: 'Baby moving less than before (if pregnant)',
    dagbani: 'Ni o bɛ ni tuhi bini, bini maa tuhi ti laɣim ni yili maa',
    hausa: 'Idan tana ciki, jaririn ya ragu da motsi',
    twi: 'Sɛ ɔyɛ ɔokafo a, abofra no rebu bio sɛdeɛ ɛbɛyɛ pɛ',
    notes: 'Twi term to confirm: rebu (kicks).',
  );
  static const qMotherVomit = BankScript(
    id: 'q_mother.vomit',
    english: 'Vomiting everything',
    dagbani: 'Naɣa maa yiɣiri bini maa pam',
    hausa: 'Macen na fitar da abinci gaba ɗaya',
    twi: 'Ɔto aduane nyinaa',
  );

  // -------------------------------------------------- Triage-level messages
  // One clip per TriageLevel.name — the family-facing sentence for the
  // result screen's verdict and family-brief buttons. The clinical
  // classification stays in English for the CHO; the sentence the mother
  // must act on is heard in her language.

  static const levelUrgent = BankScript(
    id: 'level_urgent',
    english: 'Go to the health facility now. Do not wait until tomorrow.',
    dagbani:
        'Yi tiŋ bɛ ni kpeeni pam. Tɔ di mali kpeenim maa nyɛla din '
        'gbanŋɛ.',
    hausa: 'Ku tafi asibiti yanzu. Kar ku jira har gobe.',
    twi: 'Kɔ ayaresabea ntɛm ara. Ntwɛn nyɛ anɔpa.',
    notes:
        'Reuses the verdict sentence and the "do not wait" pattern from '
        'the child danger-signs draft.',
  );

  static const levelPriority = BankScript(
    id: 'level_priority',
    english:
        'The medicine has been given. Give every dose and come back in '
        'three days.',
    dagbani:
        'Tɔ sɔŋsi nira maa ti ti bini maa. Maani sɔŋsi tiŋ maa, ka yi '
        'tiŋ labina dabaasi ata nyaaŋa.',
    hausa: 'An ba da magani. Ku ba da shi gaba ɗaya, ku koma bayan kwana uku.',
    twi:
        'Wɔama no aduro no. Fa aduro no nyinaa ma no, na san kɔ '
        'ayaresabea akyire nna mmiɛnsa.',
    notes: 'Dose wording needs review in every language.',
  );

  static const levelWatch = BankScript(
    id: 'level_watch',
    english:
        'Care for the person at home and watch closely. Come back if it '
        'gets worse.',
    dagbani:
        'Tin yaa ka ti maani sɔŋsi tiŋ maa. Gbilsim niŋ kpeenim. Ni '
        'bini maa ti niŋ tuma, yi tiŋ labina.',
    hausa:
        'Ku kula da mutumin a gida, ku sa ido sosai. Idan lafiyar ta '
        'tabarbare, ku koma asibiti.',
    twi: 'Hwɛ no yie wɔ fie. Sɛ ne tebea yɛ no fɛw a, san kɔ ayaresabea.',
    notes: '"Watch closely" wording is plain but unverified.',
  );

  static const levelRoutine = BankScript(
    id: 'level_routine',
    english: 'All is well. Keep feeding well and keep the care going.',
    dagbani: 'Bini maa nyɛla din yaa. Ti maani sɔŋsi tiŋ maa ka o nu tana.',
    hausa: 'Duk lafiya take. Ku ci gaba da kyautata abinci da kulawa.',
    twi: 'Biribiara yɛ hɔ. San ma no nono, na toaso akwahosan no so.',
    notes:
        'For an older child the feeding verb may need adjusting in every '
        'language.',
  );

  // ---------------------------------------------- Caregiver verdict messages
  // The three outcomes of the caregiver Quick Home Check, mirroring
  // `_TriageVerdict` in caregiver_home.dart. Each clip carries the
  // headline and the advice so the verdict button plays the whole result.

  static const caregiverVerdictUrgent = BankScript(
    id: 'caregiver_verdict_urgent',
    english:
        'Go to the health facility now. Danger signs are present. Do '
        'not wait until tomorrow. If the CHPS compound is closed, go to '
        'the health centre or the district hospital.',
    dagbani:
        'Yi tiŋ bɛ ni kpeeni pam. Bini maa zuɣu m-beni. Tɔ di mali '
        'kpeenim maa nyɛla din gbanŋɛ. Ni CHPS tiŋ maa kpari, yi tiŋ '
        'alaafee yili bee ashibiti titali.',
    hausa:
        'Ku tafi asibiti yanzu. Alamomin hadari sun bayyana. Kar ku '
        'jira har gobe. Idan ofishin CHPS ya rufe, ku tafi cibiyar '
        'lafiya ko babbar asibiti.',
    twi:
        'Kɔ ayaresabea ntɛm ara. Nsɛnkyerɛnne a ɛkyerɛ ɔhaw no asisi. '
        'Ntwɛn nyɛ anɔpa. Sɛ CHPS beaeɛ no adan mu a, kɔ ayaresabea '
        'biara a ɛbɛn wo.',
    notes: 'Facility names need a local ear.',
  );

  static const caregiverVerdictCaution = BankScript(
    id: 'caregiver_verdict_caution',
    english:
        'Visit your CHW soon. Some answers are not clear. Bring this '
        'person to the clinic at the next scheduled contact, and watch '
        'closely for the next two days.',
    dagbani:
        'Ti sɔŋsi nira maa ni kpeenim laɣim. Mi bɛ mi bini shɛŋa. Yi '
        'tiŋ labina ni tiŋ maa dabaasi ayi puuni.',
    hausa:
        'Ku ziyarci mai kula da lafiyarku nan ba da jimawa ba. Wasu '
        'amsoshi ba su bayyana ba. Ku kai wannan mutum asibiti a ziyara '
        'ta gaba, ku kuma sa ido sosai har kwana biyu.',
    twi:
        'Hwɛ wo CHW no ntɛm. Mmoa no bi nkyerɛ pefee. Fa obi no kɔ '
        'ayaresabea wɔ berɛ a wɔahyɛ no so, na hwɛ no yiye nnafua '
        'mmienu.',
    notes: 'Condenses the English advice; the two-day window needs review.',
  );

  static const caregiverVerdictFine = BankScript(
    id: 'caregiver_verdict_fine',
    english:
        'Continue routine care. None of the danger signs are present. '
        'Keep feeding, keep drinking, and check again tomorrow.',
    dagbani:
        'Tin yaa ka ti maani sɔŋsi tiŋ maa. Bini maa zuɣu maa bɛni. Ti '
        'maani sɔŋsi tiŋ maa, ka ti labina tooni.',
    hausa:
        'Ku ci gaba da kula da lafiya akai-akai. Babu wata alamar '
        'hadari da ta bayyana. Ku ci gaba da ciyar da shi, shan ruwa, '
        'ku kuma duba shi gobe.',
    twi:
        'Toaso akwahosan pa so. Nsɛnkyerɛnne biara nni hɔ. San ma no '
        'nono, ma no nsuo nom, na san hwɛ no ɔkyena.',
    notes: 'Reuses the verdict-fine draft as the opening.',
  );

  // ------------------------------------------------------ Words for nurse
  // The frame of the "words for the nurse" sheet. The sign statements
  // themselves reuse the question clips (the sign drafts are statements
  // already), so the composed audio is intro + the chosen signs + the
  // unsure preamble + close.

  static const nurseIntro = BankScript(
    id: 'nurse_intro',
    english: 'What I noticed:',
    dagbani: 'N ni nya bini shɛŋa n-yɛliya.',
    hausa: 'Waɗannan abubuwan da na gani:',
    twi: 'Nea mehunuu:',
    notes: 'Lit. "the things I saw, I have said them" in Dagbani.',
  );

  static const nurseUnsure = BankScript(
    id: 'nurse_unsure',
    english: 'I was not sure about:',
    dagbani: 'Mi bɛ mi bini shɛŋa ŋɔ.',
    hausa: 'Waɗanda ban tabbata ba:',
    twi: 'Nea mennim:',
  );

  static const nurseClose = BankScript(
    id: 'nurse_close',
    english: 'I will say when each sign started.',
    dagbani: 'N yɛn yɛliya bini kam ni daa piligi shɛm.',
    hausa: 'Zan faɗi yadda kowane alamu ya fara.',
    twi: 'Mebɛka sɛdeɛ nsɛnkyerɛnne biara fii aseɛ.',
    notes: 'The onset-timeline sentence, matching the sheet close.',
  );

  // ------------------------------------------------------------ Standalone
  // One-off clips: the language preview at registration and the voice-test
  // screen. Both speak the app's most important sentence so a new user
  // hears their language the moment they choose it. The id names the
  // language (the button id is built with the chosen language), so each
  // variant lives in its own folder — the tests read the suffix.

  static const setupPreviewDagbani = BankScript(
    id: 'setup_preview_Dagbani',
    english: 'Go to the health facility now',
    dagbani: 'Yi tiŋ bɛ ni kpeeni pam',
    hausa: 'Ku tafi asibiti yanzu',
    twi: 'Kɔ ayaresabea ntɛm ara',
    notes:
        'Same draft as DagbaniStrings.verdictUrgent — the sentence the '
        'caregiver will hear most often.',
  );

  static const setupPreviewHausa = BankScript(
    id: 'setup_preview_Hausa',
    english: 'Go to the health facility now',
    dagbani: 'Yi tiŋ bɛ ni kpeeni pam',
    hausa: 'Ku tafi asibiti yanzu',
    twi: 'Kɔ ayaresabea ntɛm ara',
  );

  static const setupPreviewTwi = BankScript(
    id: 'setup_preview_Twi',
    english: 'Go to the health facility now',
    dagbani: 'Yi tiŋ bɛ ni kpeeni pam',
    hausa: 'Ku tafi asibiti yanzu',
    twi: 'Kɔ ayaresabea ntɛm ara',
  );

  static const voiceTestDagbani = BankScript(
    id: 'voice_test_Dagbani',
    english:
        'If your child cannot drink or breastfeed, go to the health '
        'facility at once.',
    dagbani: 'Ni bini maa ti niŋ ka o nui tana, yi tiŋ bɛ ni kpeeni pam.',
    hausa: 'Idan yaranku ba ta iya sha ko nono, je asibitin yanzu.',
    twi: 'Sɛ akwadaa ntumi nnom nsuo anaasɛ nono a, kɔ ayaresabea ntɛm ara.',
    notes:
        'Mirrors the test phrase shown on the voice-test screen, per '
        'language.',
  );

  static const voiceTestHausa = BankScript(
    id: 'voice_test_Hausa',
    english:
        'If your child cannot drink or breastfeed, go to the health '
        'facility at once.',
    dagbani: 'Ni bini maa ti niŋ ka o nui tana, yi tiŋ bɛ ni kpeeni pam.',
    hausa: 'Idan yaranku ba ta iya sha ko nono, je asibitin yanzu.',
    twi: 'Sɛ akwadaa ntumi nnom nsuo anaasɛ nono a, kɔ ayaresabea ntɛm ara.',
  );

  static const voiceTestTwi = BankScript(
    id: 'voice_test_Twi',
    english:
        'If your child cannot drink or breastfeed, go to the health '
        'facility at once.',
    dagbani: 'Ni bini maa ti niŋ ka o nui tana, yi tiŋ bɛ ni kpeeni pam.',
    hausa: 'Idan yaranku ba ta iya sha ko nono, je asibitin yanzu.',
    twi: 'Sɛ akwadaa ntumi nnom nsuo anaasɛ nono a, kɔ ayaresabea ntɛm ara.',
  );

  // -------------------------------------------------------------- The lookup

  /// Every clip this layer can name. `test/speech_bank_test.dart` asserts
  /// each has a bundled WAV in the right folder.
  static const allScripts = <BankScript>[
    // Topics
    childDangerSigns,
    newbornDangerSigns,
    motherDangerSigns,
    feeding,
    referral,
    // Questions
    qNewbornFeed,
    qNewbornFast,
    qNewbornFits,
    qNewbornSleepy,
    qNewbornTemp,
    qNewbornYellow,
    qNewbornCord,
    qNewbornVomit,
    qChildDrink,
    qChildVomit,
    qChildFits,
    qChildSleepy,
    qChildBreath,
    qChildBlood,
    qChildThin,
    qChildFever,
    qMotherBleed,
    qMotherHead,
    qMotherFever,
    qMotherPain,
    qMotherFits,
    qMotherSmell,
    qMotherMove,
    qMotherVomit,
    // Levels, verdicts, nurse frame
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
    // Standalones
    setupPreviewDagbani,
    setupPreviewHausa,
    setupPreviewTwi,
    voiceTestDagbani,
    voiceTestHausa,
    voiceTestTwi,
  ];

  static BankScript? byId(String id) {
    for (final c in allScripts) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// The draft words a single clip speaks in [language] — null when the id
  /// is unknown or the language has no bank.
  static String? scriptForId(String language, String id) {
    if (!bankLanguages.containsKey(language)) return null;
    return byId(id)?.textFor(language);
  }

  /// The draft words a clip *list* speaks in [language] — for composed
  /// messages. Returns null when any clip is unknown, so the sheet falls
  /// back to the caller's own script rather than a half-joined sentence.
  static String? scriptFor({
    required String language,
    required List<String> ids,
  }) {
    if (!bankLanguages.containsKey(language)) return null;
    final parts = <String>[];
    for (final id in ids) {
      final clip = byId(id);
      if (clip == null) return null;
      parts.add(clip.textFor(language)!);
    }
    return parts.isEmpty ? null : parts.join(' ');
  }

  /// The family message for a [TriageLevel].name, e.g. `'priority'`.
  static BankScript? levelClip(String triageName) => byId('level_$triageName');

  /// The verdict message for a caregiver verdict name (`urgent`, `caution`,
  /// `fine`).
  static BankScript? caregiverVerdictClip(String verdictName) =>
      byId('caregiver_verdict_$verdictName');

  /// The ordered clip ids for the words-for-the-nurse composition. [yesKeys]
  /// and [unsureKeys] are full question keys (`newborn.feed`) — the same
  /// keys the Quick Home Check plays with — because the statement clips are
  /// the question clips. The ids are language-neutral; the folder follows
  /// the user's language.
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
}
