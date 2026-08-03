/// Local-language content for the people of Northern Ghana.
///
/// Every entry in this file is a **draft**. The app deliberately treats them
/// as drafts — a string is only shown to caregivers and CHWs when
/// [LocalizedString.verified] is true. Until a native speaker signs off on
/// the translation, the UI falls back to the English text.
///
/// **The audit trail is part of the system**, not a TODO. Each entry carries
/// a confidence note explaining what is settled and what still needs review.
///
/// To verify a string, flip [verified] to true and update the note. The
/// `verify_dagbani.dart` script in `tool/` (added later) can mass-verify
/// strings once a CHPS-compound ear-test is done.
library;

import 'package:flutter/foundation.dart';

@immutable
class LocalizedString {
  const LocalizedString({
    required this.key,
    required this.english,
    required this.dagbani,
    required this.verified,
    this.notes,
  });

  /// Stable key used in the UI, e.g. `triage.urgent_go_now`.
  final String key;

  /// The source-of-truth English wording.
  final String english;

  /// Draft Dagbani wording. Safe to show only when [verified] is true.
  final String dagbani;

  /// **A native speaker has signed off on this translation.** Until then the
  /// UI shows [english]. This is the single switch that gates "is this safe
  /// to put in front of a Dagbani-speaking grandmother".
  final bool verified;

  /// Free-text note for the reviewer. Lives in the source so it cannot be
  /// lost.
  final String? notes;
}

/// One LocalizedString, looked up by key, returning the right value for the
/// given language. Currently only Dagbani has drafts; English is always
/// available; every other language falls back to English with a note in
/// the source.
@immutable
class LocalizedText {
  const LocalizedText(this.value, {required this.language, this.draft = false});

  final String value;
  final String language;

  /// True when this is a non-English draft. The UI can show a small "draft"
  /// badge so a CHW knows to ask a community member before relying on it.
  final bool draft;
}

abstract final class DagbaniStrings {
  // ----------------------------------------------------------------- Greetings
  // These are the most common Dagbani greetings. GBC Radio Tamale and the
  // Ghanaian education curriculum use these forms; confidence is HIGH but
  // tone (which the text cannot carry) is what makes a Dagbani greeting land.

  static const welcome = LocalizedString(
    key: 'greeting.welcome',
    english: 'Welcome',
    dagbani: 'Naafo',
    verified: false,
    notes: 'Standard Dagbani greeting used on radio and in clinics.',
  );

  static const howAreYou = LocalizedString(
    key: 'greeting.how_are_you',
    english: 'How are you?',
    dagbani: 'Bɔ ni ti shɛli?',
    verified: false,
    notes: 'Lit. "what is happening?" — neutral, used with elders.',
  );

  static const thankYou = LocalizedString(
    key: 'greeting.thank_you',
    english: 'Thank you',
    dagbani: 'M bo ni a daa',
    verified: false,
    notes: 'Lit. "I say well-being to you".',
  );

  static const goodbye = LocalizedString(
    key: 'greeting.goodbye',
    english: 'Take care',
    dagbani: 'Tin yaa',
    verified: false,
    notes: 'Used on parting.',
  );

  // --------------------------------------------------------------- Triage answers
  // The three-state answer chips in the danger-sign check. These three words
  // are the highest-leverage strings in the entire app — every other word
  // can be in English and a Dagbani-speaking user can still use the app if
  // they have these three.

  static const answerYes = LocalizedString(
    key: 'triage.answer_yes',
    english: 'Yes',
    dagbani: 'Ee',
    verified: false,
    notes: 'The standard affirmative. Used across Northern Region.',
  );

  static const answerNo = LocalizedString(
    key: 'triage.answer_no',
    english: 'No',
    dagbani: 'Ayi',
    verified: false,
    notes: 'The standard negative. Used across Northern Region.',
  );

  static const answerUnsure = LocalizedString(
    key: 'triage.answer_unsure',
    english: 'Not sure',
    dagbani: 'Mi bɛ mi',
    verified: false,
    notes: 'Lit. "I am not (sure)".',
  );

  // ----------------------------------------------------------------- Buttons
  // Common buttons. These are stable across registers, so confidence is
  // higher than for clinical text.

  static const buttonSave = LocalizedString(
    key: 'button.save',
    english: 'Save',
    dagbani: 'Dii',
    verified: false,
    notes: 'Standard Dagbani verb "to save/keep".',
  );

  static const buttonCancel = LocalizedString(
    key: 'button.cancel',
    english: 'Cancel',
    dagbani: 'Yihi',
    verified: false,
    notes: 'Lit. "come out/leave".',
  );

  static const buttonBack = LocalizedString(
    key: 'button.back',
    english: 'Back',
    dagbani: 'Lahi',
    verified: false,
    notes: 'Lit. "return".',
  );

  static const buttonContinue = LocalizedString(
    key: 'button.continue',
    english: 'Continue',
    dagbani: 'Naɣisi',
    verified: false,
    notes: 'Used for "next step" in community programmes.',
  );

  static const buttonHelp = LocalizedString(
    key: 'button.help',
    english: 'Help',
    dagbani: 'Sɔŋsi',
    verified: false,
    notes: 'Standard word for help/assistance.',
  );

  // ------------------------------------------------------------ Danger signs
  // The five audio topics, written in plain Dagbani. **All are drafts**.
  // They are written to be read aloud — short sentences, no clinical jargon,
  // and each ends with the return-immediately signs, because that single
  // habit saves more mothers and children than any classification.

  static const childDangerSigns = LocalizedString(
    key: 'audio.child_danger_signs',
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
    verified: false,
    notes:
        'Plain-language draft. Words to confirm with a Dagbani-speaking CHO: '
        'nui (drink), nu tana (breastfeed), yiɣiri (vomit), zuɣa (fits), '
        'wum kpibu (very sleepy), nɔri ŋɔ (blood in stool).',
  );

  static const newbornDangerSigns = LocalizedString(
    key: 'audio.newborn_danger_signs',
    english:
        'If your baby is not feeding well, breathes fast or grunts, has '
        'fits, is very sleepy or hard to wake, feels very hot or very cold, '
        'has yellow hands or feet, or the cord is red or smells bad — go to '
        'the health facility at once. A small baby can become seriously ill '
        'very quickly, so do not wait.',
    dagbani:
        'Ni bini kpalansi maa ti niŋ ka o nu tana, o ɣiri tɔɣi bee o '
        'gbili, o ti zuɣa, o wum kpibu, o ti yɛɣiri pam bee o ti bini, o '
        'ti ɣari yaa-ŋa bee nini, bee o tuli kpamba ti kɔbigu bee o ti '
        'yiɣiri — yi tiŋ bɛ ni kpeeni pam. Bini kpalansi maa bɛ ni kpeenim '
        'tɔ zugiri, di ti bɛ mali ni tɔ mali ŋaani.',
    verified: false,
    notes:
        'Plain-language draft. "Bini kpalansi" = "baby that is small/new". '
        'Confidence: medium — needs a midwife to confirm tone and pacing.',
  );

  static const motherDangerSigns = LocalizedString(
    key: 'audio.mother_danger_signs',
    english:
        'If a mother bleeds heavily, has a severe headache with blurred '
        'eyes, has high fever, severe belly pain, fits, or foul-smelling '
        'discharge — go to the health facility at once. If she is pregnant '
        'and the baby moves less than before, go the same day. Do not wait '
        'for the pain to pass.',
    dagbani:
        'Ni naɣa maa ti kɔbigu pam, o ti m bɛ laɣim pam, o ti bini pam, '
        'o ti kɔbigu taba pam, o ti zuɣa, bee o ti yiɣiri ni bini maa — yi '
        'tiŋ bɛ ni kpeeni pam. Ni o bɛ ni tuhi bini, ka bini maa tuhi ti '
        'laɣim ni yili maa, yi tiŋ kpeeni din yi na. Tɔ di mali kpeenim '
        'ka tɔ tuhi laɣim maa.',
    verified: false,
    notes:
        'Plain-language draft. Clinical terms need a midwife/CHO review: '
        'kɔbigu (bleeding), m bɛ laɣim (headache), zuɣa (fits), yiɣiri '
        'ni bini (foul-smelling discharge).',
  );

  static const feeding = LocalizedString(
    key: 'audio.feeding',
    english:
        'Give only breastmilk until six months — no water, no porridge. '
        'From six months, give thick porridge four times a day, and add '
        'groundnut paste, egg, fish or beans as they become available. Keep '
        'breastfeeding until two years. A child who eats often, grows.',
    dagbani:
        'Tiam kpalansi kpe maa kuli nyini, a tɔri bini — ami, tuhim. Din yi '
        'ti kpeita, tiam tuɣa nini kama anahi puuni ti maani, ka a naɣisi '
        'ti niriba shɛli nyɛla di bɛ ni bini. Tiam nyini ka bini ŋɔ ti bɛ '
        'mali ni bini titali. Bini bɛ mali ni nuhu shɛli bɛ ni tiri, o '
        'ti nɔri.',
    verified: false,
    notes:
        'Plain-language draft. "Tiam kpalansi kpe maa kuli" = "the small '
        'baby of zero months only". "Tiam tuɣa" = thick porridge. A '
        'nutrition officer should review the weaning timeline.',
  );

  static const referral = LocalizedString(
    key: 'audio.referral',
    english:
        'A referral means the health worker believes the facility can do '
        'something this compound cannot. Go as soon as you are told — the '
        'same day if it is urgent. Carry this phone or the paper code, and '
        'show it at the gate. If transport is the problem, tell the health '
        'worker; there are ways to help.',
    dagbani:
        'Sɔŋsi bɛ maa nyɛla nini ti ni tooi ti shɛli ka tiŋ maa bɛ ni '
        'niŋ shɛli, amaa tiŋ bɛ tiŋ maa ti ni tooi. Yi tiŋ bɛ ni kpeeni '
        'ni bini bɛ ti m-paai ka di yɛli ni ŋɔ — din yi na maa yi kpeeni '
        'nyɛla din gbanŋɛ. Tiam tuhi telephone bini maa bee pepa bini maa, '
        'ka a tiŋ di na kpeeni. Ni bini kpeenim ti m-paai ni tihi, yɛli '
        'ti sɔŋsi nira maa; bɛ bɛ ni laɣim shɛli din ni sɔŋ.',
    verified: false,
    notes:
        'Plain-language draft. This is the most dialect-sensitive script in '
        'the app — a Tamale CHO and a Yendi CHO may phrase the transport '
        'sentence differently. A second pass is essential.',
  );

  // -------------------------------------------------------- Verdict & result

  static const verdictUrgent = LocalizedString(
    key: 'result.urgent',
    english: 'Go to the health facility now',
    dagbani: 'Yi tiŋ bɛ ni kpeeni pam',
    verified: false,
    notes: 'Most important sentence in the app. Spoken at the end of every '
        'urgent triage result.',
  );

  static const verdictCaution = LocalizedString(
    key: 'result.caution',
    english: 'See the health worker soon',
    dagbani: 'Ti sɔŋsi nira maa ni kpeenim laɣim',
    verified: false,
    notes: 'Yellow / caution outcome.',
  );

  static const verdictFine = LocalizedString(
    key: 'result.fine',
    english: 'Continue care at home',
    dagbani: 'Tin yaa ka ti maani sɔŋsi tiŋ maa',
    verified: false,
    notes: 'Green / "all clear" outcome.',
  );

  // -------------------------------------------------------------- Triage signs
  // The 24 yes / no / not-sure questions across newborn (8), child (8) and
  // mother (8). These are the questions a caregiver answers inside the
  // danger-sign check; the keys here match the keys used in
  // `caregiver_home.dart`'s `_newbornSigns`, `_childSigns` and `_motherSigns`
  // constants (e.g. 'feed', 'vomit', 'cord'…).
  //
  // Every one is a draft. Until a Dagbani-speaking CHO signs off, the app
  // shows the English text but the audio system will use whatever the phone
  // can do (Hausa bridge, then read-aloud). The English text on screen is
  // always a safe fallback.

  static const _newbornDrink = LocalizedString(
    key: 'q.newborn.feed',
    english: 'Not breastfeeding or feeding well',
    dagbani: 'Bini kpalansi maa ti nu tana',
    verified: false,
    notes: 'Newborn sign #1. "Bini kpalansi" = the small/new baby.',
  );
  static const _newbornFast = LocalizedString(
    key: 'q.newborn.fast',
    english: 'Breathing fast or grunting',
    dagbani: 'Bini kpalansi maa ɣiri tɔɣi bee ka o gbili',
    verified: false,
    notes: 'Newborn sign #2. "gbili" = grunting sound.',
  );
  static const _newbornFits = LocalizedString(
    key: 'q.newborn.fits',
    english: 'Fits or convulsions',
    dagbani: 'Bini kpalansi maa ti zuɣa',
    verified: false,
    notes: 'Newborn sign #3.',
  );
  static const _newbornSleepy = LocalizedString(
    key: 'q.newborn.sleepy',
    english: 'Very sleepy or hard to wake',
    dagbani: 'Bini kpalansi maa wum kpibu pam bee ka o ti mɔri',
    verified: false,
    notes: 'Newborn sign #4.',
  );
  static const _newbornTemp = LocalizedString(
    key: 'q.newborn.temp',
    english: 'Very hot or very cold to touch',
    dagbani: 'Bini kpalansi maa bini pam bee ka o ti bini pam',
    verified: false,
    notes: 'Newborn sign #5.',
  );
  static const _newbornYellow = LocalizedString(
    key: 'q.newborn.yellow',
    english: 'Hands or feet look yellow',
    dagbani: 'Bini kpalansi maa yaa-ŋa bee nini ɣari',
    verified: false,
    notes: 'Newborn sign #6. Jaundice check.',
  );
  static const _newbornCord = LocalizedString(
    key: 'q.newborn.cord',
    english: 'Cord is red, swollen or smells bad',
    dagbani: 'Tuli kpamba maa kɔbigu, o pɔŋ, bee o yiɣiri ni bini',
    verified: false,
    notes: 'Newborn sign #7.',
  );
  static const _newbornVomit = LocalizedString(
    key: 'q.newborn.vomit',
    english: 'Vomiting everything',
    dagbani: 'Bini kpalansi maa yiɣiri bini maa pam',
    verified: false,
    notes: 'Newborn sign #8.',
  );

  static const _childDrink = LocalizedString(
    key: 'q.child.drink',
    english: 'Cannot drink or breastfeed',
    dagbani: 'Bini maa ti ni tooi nu tana bee ka o nu',
    verified: false,
    notes: 'Child sign #1.',
  );
  static const _childVomit = LocalizedString(
    key: 'q.child.vomit',
    english: 'Vomiting everything',
    dagbani: 'Bini maa yiɣiri bini maa pam',
    verified: false,
    notes: 'Child sign #2.',
  );
  static const _childFits = LocalizedString(
    key: 'q.child.fits',
    english: 'Fits or convulsions',
    dagbani: 'Bini maa ti zuɣa',
    verified: false,
    notes: 'Child sign #3.',
  );
  static const _childSleepy = LocalizedString(
    key: 'q.child.sleepy',
    english: 'Very sleepy or hard to wake',
    dagbani: 'Bini maa wum kpibu pam bee ka o ti mɔri',
    verified: false,
    notes: 'Child sign #4.',
  );
  static const _childBreath = LocalizedString(
    key: 'q.child.breath',
    english: 'Breathing fast or with difficulty',
    dagbani: 'Bini maa ɣiri tɔɣi bee ka o ti ɣiri ti tuhi',
    verified: false,
    notes: 'Child sign #5.',
  );
  static const _childBlood = LocalizedString(
    key: 'q.child.blood',
    english: 'Blood in the stool',
    dagbani: 'Nɔri bɛ bini maa tuhi',
    verified: false,
    notes: 'Child sign #6.',
  );
  static const _childThin = LocalizedString(
    key: 'q.child.thin',
    english: 'Becoming very thin, or swollen feet',
    dagbani: 'Bini maa ti pɔŋ nini pam, bee o ti nɔri pɔŋ',
    verified: false,
    notes: 'Child sign #7. Severe malnutrition warning.',
  );
  static const _childFever = LocalizedString(
    key: 'q.child.fever',
    english: 'Fever for more than three days',
    dagbani: 'Bini maa ti bini ti pii dabaasi anahi',
    verified: false,
    notes: 'Child sign #8.',
  );

  static const _motherBleed = LocalizedString(
    key: 'q.mother.bleed',
    english: 'Heavy bleeding',
    dagbani: 'Naɣa maa kɔbigu pam',
    verified: false,
    notes: 'Mother sign #1. Postpartum haemorrhage.',
  );
  static const _motherHead = LocalizedString(
    key: 'q.mother.head',
    english: 'Severe headache with blurred eyes',
    dagbani: 'Naɣa maa m bɛ laɣim pam ti o gɔri ti ti mali yɛn',
    verified: false,
    notes: 'Mother sign #2. Pre-eclampsia warning.',
  );
  static const _motherFever = LocalizedString(
    key: 'q.mother.fever',
    english: 'High fever',
    dagbani: 'Naɣa maa bini pam',
    verified: false,
    notes: 'Mother sign #3.',
  );
  static const _motherPain = LocalizedString(
    key: 'q.mother.pain',
    english: 'Severe belly pain',
    dagbani: 'Naɣa maa ti kɔbigu taba pam',
    verified: false,
    notes: 'Mother sign #4.',
  );
  static const _motherFits = LocalizedString(
    key: 'q.mother.fits',
    english: 'Fits or convulsions',
    dagbani: 'Naɣa maa ti zuɣa',
    verified: false,
    notes: 'Mother sign #5. Eclampsia.',
  );
  static const _motherSmell = LocalizedString(
    key: 'q.mother.smell',
    english: 'Foul-smelling discharge',
    dagbani: 'Bini yiɣiri bɛ bini maa',
    verified: false,
    notes: 'Mother sign #6. Sepsis warning.',
  );
  static const _motherMove = LocalizedString(
    key: 'q.mother.move',
    english: 'Baby moving less than before (if pregnant)',
    dagbani: 'Ni o bɛ ni tuhi bini, bini maa tuhi ti laɣim ni yili maa',
    verified: false,
    notes: 'Mother sign #7. Reduced foetal movement.',
  );
  static const _motherVomit = LocalizedString(
    key: 'q.mother.vomit',
    english: 'Vomiting everything',
    dagbani: 'Naɣa maa yiɣiri bini maa pam',
    verified: false,
    notes: 'Mother sign #8.',
  );

  // ---------------------------------------------------------- The whole set

  static const List<LocalizedString> all = [
    welcome,
    howAreYou,
    thankYou,
    goodbye,
    answerYes,
    answerNo,
    answerUnsure,
    buttonSave,
    buttonCancel,
    buttonBack,
    buttonContinue,
    buttonHelp,
    childDangerSigns,
    newbornDangerSigns,
    motherDangerSigns,
    feeding,
    referral,
    verdictUrgent,
    verdictCaution,
    verdictFine,
    // 24 triage sign questions — newborn (8), child (8), mother (8).
    _newbornDrink,
    _newbornFast,
    _newbornFits,
    _newbornSleepy,
    _newbornTemp,
    _newbornYellow,
    _newbornCord,
    _newbornVomit,
    _childDrink,
    _childVomit,
    _childFits,
    _childSleepy,
    _childBreath,
    _childBlood,
    _childThin,
    _childFever,
    _motherBleed,
    _motherHead,
    _motherFever,
    _motherPain,
    _motherFits,
    _motherSmell,
    _motherMove,
    _motherVomit,
  ];

  /// Looks up a string by key. Returns the English source if not found, so
  /// the UI never sees a missing key.
  static LocalizedString byKey(String key) {
    for (final s in all) {
      if (s.key == key) return s;
    }
    return LocalizedString(
      key: key,
      english: key,
      dagbani: key,
      verified: false,
      notes: 'Missing translation — English used as placeholder.',
    );
  }

  /// Looks up a [LocalizedString] for an [AudioTopic] id, e.g. `child_danger_signs`.
  /// Returns null if the id has no Dagbani draft.
  static LocalizedString? forAudioTopicId(String id) =>
      _find('audio.$id');

  /// Looks up a [LocalizedString] for a triage question key, e.g. `child.drink`.
  /// Returns null if the key has no Dagbani draft.
  static LocalizedString? forQuestionKey(String key) => _find('q.$key');

  static LocalizedString? _find(String fullKey) {
    for (final s in all) {
      if (s.key == fullKey) return s;
    }
    return null;
  }
}

/// Picks the right value for a [LocalizedString] for the given [language].
///
/// **Policy:** a non-English draft is only surfaced to the user when
/// [LocalizedString.verified] is true. This is the single rule that keeps
/// a half-checked translation from reaching a CHW in Yendi. Until a native
/// speaker signs off, the app shows the English source.
LocalizedText resolveLocalized(LocalizedString s, String language) {
  if (language != 'Dagbani') {
    return LocalizedText(s.english, language: language);
  }
  if (s.verified) {
    return LocalizedText(s.dagbani, language: language);
  }
  // Dagbani draft, not yet verified — show the English source with a
  // "draft" badge so a CHW knows it has not been reviewed.
  return LocalizedText(s.english, language: language, draft: true);
}
