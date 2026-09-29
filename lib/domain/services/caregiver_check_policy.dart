import '../../core/i18n/speech_bank.dart';
import '../entities/caregiver.dart';
import '../entities/core.dart';
import '../enums.dart';

class CaregiverQuestion {
  const CaregiverQuestion(this.key, this.label);
  final String key;
  final String label;
}

class CaregiverQuestionSet {
  const CaregiverQuestionSet({
    required this.group,
    required this.cohortKey,
    required this.clientType,
    required this.questions,
  });
  final String group;
  final String cohortKey;
  final ClientType clientType;
  final List<CaregiverQuestion> questions;
  String speechId(CaregiverQuestion question) => '$group.${question.key}';

  CaregiverQuestion? byKey(String key) {
    for (final q in questions) {
      if (q.key == key) return q;
    }
    return null;
  }
}

/// One worry a caregiver can name before the battery starts (Step 0 of the
/// realistic journey: she arrives with a fear, not a questionnaire). Each
/// concern maps to the danger-sign questions it relates to; the battery is
/// never shortened — concerns only decide which questions lead.
class CaregiverConcern {
  const CaregiverConcern(this.key, this.label, this.questionKeys);
  final String key;
  final String label;
  final List<String> questionKeys;
}

/// How long the signs have been present, asked as a real question instead of
/// a buried note. Keys are stable for drafts and the nurse summary.
enum CaregiverDuration {
  today('today', 'Started today or yesterday'),
  fewDays('fewDays', 'About 2–3 days ago'),
  weekOrMore('weekOrMore', 'A week or more'),
  comesAndGoes('comesAndGoes', 'It comes and goes');

  const CaregiverDuration(this.key, this.label);
  final String key;
  final String label;

  static CaregiverDuration? byKey(String? key) {
    for (final d in values) {
      if (d.key == key) return d;
    }
    return null;
  }
}

/// What the family already tried before checking — recorded so the nurse
/// knows, never judged and never advised about here.
enum CaregiverGivenCare {
  ors('ors', 'ORS or lean drink'),
  paracetamol('paracetamol', 'Paracetamol'),
  herbal('herbal', 'Herbal medicine'),
  kioskAntibiotic('kioskAntibiotic', 'Medicine bought from a kiosk'),
  other('other', 'Something else'),
  nothing('nothing', 'Nothing yet');

  const CaregiverGivenCare(this.key, this.label);
  final String key;
  final String label;

  static CaregiverGivenCare? byKey(String? key) {
    for (final g in values) {
      if (g.key == key) return g;
    }
    return null;
  }
}

enum CaregiverCheckDecision {
  urgent,
  contactToday,
  routine,
  incomplete,
  unsupported,
}

/// Caregiver-only safety policy; no FHW classifiers or research models change.
/// Question labels/keys retain the existing speech-bank contract.
/// Basis for clinical review: WHO IMCI Chart Booklet (2014), sick young infant
/// updates (2019), WHO Pregnancy, Childbirth, Postpartum and Newborn Care (2015).
/// Uncertainty -> same-day contact is a conservative product safety rule, not a
/// validated diagnostic algorithm. All revised advice requires clinical review.
class CaregiverCheckPolicy {
  CaregiverCheckPolicy({required this.clock});
  final DateTime Function() clock;
  static const questionVersion = 1;
  static const newbornQuestions = [
    CaregiverQuestion(
      'feed',
      'Is the baby not breastfeeding or feeding poorly?',
    ),
    CaregiverQuestion(
      'fast',
      'Is the baby breathing fast or making grunting sounds?',
    ),
    CaregiverQuestion('fits', 'Has the baby had any fits or convulsions?'),
    CaregiverQuestion(
      'sleepy',
      'Is the baby unusually sleepy or hard to wake?',
    ),
    CaregiverQuestion('temp', 'Does the baby feel very hot or very cold?'),
    CaregiverQuestion(
      'yellow',
      'Do the baby\u2019s hands or feet look yellow?',
    ),
    CaregiverQuestion('cord', 'Is the umbilical cord red, swollen, or smelly?'),
    CaregiverQuestion('vomit', 'Is the baby vomiting everything?'),
  ];
  static const childQuestions = [
    CaregiverQuestion('drink', 'Is the child unable to drink or breastfeed?'),
    CaregiverQuestion('vomit', 'Is the child vomiting everything?'),
    CaregiverQuestion('fits', 'Has the child had any fits or convulsions?'),
    CaregiverQuestion(
      'sleepy',
      'Is the child unusually sleepy or hard to wake?',
    ),
    CaregiverQuestion(
      'breath',
      'Is the child breathing fast or struggling to breathe?',
    ),
    CaregiverQuestion('blood', 'Is there blood in the child\u2019s stool?'),
    CaregiverQuestion(
      'thin',
      'Is the child becoming very thin or are the feet swollen?',
    ),
    CaregiverQuestion(
      'fever',
      'Has the child had fever for more than three days?',
    ),
  ];
  static const maternalQuestions = [
    CaregiverQuestion('bleed', 'Is there heavy bleeding?'),
    CaregiverQuestion(
      'head',
      'Is there a severe headache with blurred vision?',
    ),
    CaregiverQuestion('fever', 'Is there a high fever?'),
    CaregiverQuestion('pain', 'Is there severe belly pain?'),
    CaregiverQuestion('fits', 'Have there been any fits or convulsions?'),
    CaregiverQuestion('smell', 'Is there a foul-smelling discharge?'),
    CaregiverQuestion('move', 'Is the baby moving less than usual?'),
    CaregiverQuestion('vomit', 'Is everything being vomited?'),
  ];

  /// The worries a caregiver can name before the battery starts. Selecting
  /// some reorders the battery so those questions lead — it never removes
  /// questions, because the safety net cannot depend on what she thought
  /// was relevant.
  static const newbornConcerns = [
    CaregiverConcern('hot', 'Feels very hot or cold', ['temp']),
    CaregiverConcern('feeding', 'Not feeding well', ['feed']),
    CaregiverConcern('breathing', 'Breathing or grunting', ['fast']),
    CaregiverConcern('fits', 'Fits or convulsions', ['fits']),
    CaregiverConcern('sleepy', 'Unusually sleepy', ['sleepy']),
    CaregiverConcern('yellow', 'Looking yellow', ['yellow']),
    CaregiverConcern('cord', 'Cord looks bad', ['cord']),
    CaregiverConcern('vomiting', 'Vomiting', ['vomit']),
  ];
  static const childConcerns = [
    CaregiverConcern('fever', 'Fever', ['fever']),
    CaregiverConcern('breathing', 'Cough or breathing', ['breath']),
    CaregiverConcern('drinking', 'Not drinking or feeding', ['drink']),
    CaregiverConcern('vomiting', 'Vomiting or loose stool', ['vomit', 'blood']),
    CaregiverConcern('fits', 'Fits or convulsions', ['fits']),
    CaregiverConcern('sleepy', 'Unusually sleepy', ['sleepy']),
    CaregiverConcern('thin', 'Very thin or swollen feet', ['thin']),
  ];
  static const maternalConcerns = [
    CaregiverConcern('bleeding', 'Bleeding', ['bleed']),
    CaregiverConcern('headache', 'Headache or vision', ['head']),
    CaregiverConcern('fever', 'Fever', ['fever']),
    CaregiverConcern('pain', 'Severe belly pain', ['pain']),
    CaregiverConcern('fits', 'Fits or convulsions', ['fits']),
    CaregiverConcern('discharge', 'Foul-smelling discharge', ['smell']),
    CaregiverConcern('movement', 'Baby moving less', ['move']),
    CaregiverConcern('vomiting', 'Vomiting', ['vomit']),
  ];

  /// The worries that apply to one cohort, in a stable display order.
  static List<CaregiverConcern> concernsFor(CaregiverQuestionSet set) =>
      switch (set.group) {
        'newborn' => newbornConcerns,
        'child' => childConcerns,
        _ => maternalConcerns.where((c) {
          final keys = set.questions.map((q) => q.key);
          return c.questionKeys.every(keys.contains);
        }).toList(),
      };

  /// Reorder so the caregiver's stated worries lead. All questions stay —
  /// this is presentation order, not triage scope.
  static CaregiverQuestionSet reorder(
    CaregiverQuestionSet set,
    List<String> concernKeys,
  ) {
    if (concernKeys.isEmpty) return set;
    final all = concernsFor(set);
    final lead = <String>[];
    for (final key in concernKeys) {
      CaregiverConcern? concern;
      for (final c in all) {
        if (c.key == key) concern = c;
      }
      if (concern == null) continue;
      for (final qk in concern.questionKeys) {
        if (set.byKey(qk) != null && !lead.contains(qk)) lead.add(qk);
      }
    }
    if (lead.isEmpty) return set;
    final ordered = [
      for (final key in lead) set.byKey(key)!,
      ...set.questions.where((q) => !lead.contains(q.key)),
    ];
    return CaregiverQuestionSet(
      group: set.group,
      cohortKey: set.cohortKey,
      clientType: set.clientType,
      questions: List.unmodifiable(ordered),
    );
  }

  /// One concrete thing to watch at home for a sign the caregiver was unsure
  /// about — the difference between "watch closely" and knowing what to
  /// watch. Cues are observation prompts, never diagnoses.
  static String? watchCue(String questionKey) => switch (questionKey) {
    'feed' || 'drink' =>
      'Offer a feed when calm. Refusing twice in a row is a danger sign.',
    'fast' || 'breath' =>
      'Watch the chest between the ribs while calm. If the skin pulls in, or breathing looks fast, go the same day.',
    'fits' =>
      'Any fit, however short, means the facility now — note the time it started.',
    'sleepy' =>
      'Try to wake them gently for a feed. Hard to wake, or floppy, is a danger sign.',
    'temp' =>
      'Feel the tummy or back, not hands and feet. Very hot or unusually cold counts.',
    'yellow' =>
      'Check in daylight: press the cheeks or palms — skin that stays yellow needs to be seen.',
    'cord' =>
      'Look at the cord base each change. Redness spreading, pus, or smell needs the compound same day.',
    'vomit' =>
      'Give small sips often. If everything comes back up, the facility today.',
    'blood' =>
      'Any blood in the stool needs to be shown to a health worker today.',
    'thin' =>
      'Check the arms and feet this week. Swelling of both feet, or visible wasting, needs the clinic.',
    'fever' =>
      'Note the time of day it rises. Fever past three days, or with any danger sign, needs a test.',
    'bleed' =>
      'Change pads on a schedule and count. Soaking more than one pad an hour is heavy bleeding.',
    'head' =>
      'Ask her to describe it. Headache with blurred vision or swelling means come in now.',
    'pain' =>
      'Watch where it sits and what makes it worse. Sudden severe pain needs the clinic.',
    'smell' =>
      'Any foul smell from the discharge means the compound today — do not wait.',
    'move' =>
      'Rest on your side and count movements after a meal. Fewer than before needs a check today.',
    _ => null,
  };

  /// Historical questions follow the saved version/cohort, not today's age.
  static List<CaregiverQuestion>? historicalQuestions(
    String cohort,
    int version,
  ) {
    if (version != questionVersion) return null;
    if (cohort.startsWith('newborn:')) return newbornQuestions;
    if (cohort.startsWith('child:')) return childQuestions;
    if (cohort == ClientType.pregnantWoman.name) return maternalQuestions;
    if (cohort == ClientType.postpartumWoman.name ||
        cohort == ClientType.womanOfReproductiveAge.name) {
      return maternalQuestions.where((q) => q.key != 'move').toList();
    }
    return null;
  }

  /// Whole days between a recorded birth date and today, counted on calendar
  /// days so a time-of-day in the stored date cannot shift the cohort.
  int _daysOld(DateTime dob) {
    final now = clock().toLocal();
    final born = dob.toLocal();
    return DateTime.utc(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime.utc(born.year, born.month, born.day)).inDays;
  }

  /// The battery for any registered person, mirroring the nurse's tolerant
  /// routing: a child past five is still observed as a child, a record with
  /// no usable date keeps the battery it was registered under, and a
  /// general-care woman gets the maternal signs minus the fetal-movement
  /// question. This is conservative home observation screening, not a
  /// validated adult or older-child chart.
  CaregiverQuestionSet? questionsFor(Person person, {List<String>? concerns}) {
    final type = person.clientType;
    if (type == ClientType.newborn || type == ClientType.childUnderFive) {
      final dob = person.dateOfBirth;
      final days = dob == null ? null : _daysOld(dob);
      final derived = days == null ? null : ClientType.forChildAgeInDays(days);
      final effective =
          derived ??
          (days != null && days > 59 ? ClientType.childUnderFive : type);
      final group = effective == ClientType.newborn ? 'newborn' : 'child';
      return reorder(
        CaregiverQuestionSet(
          group: group,
          cohortKey:
              '$group:${dob == null ? 'unregistered' : caregiverDateKey(dob)}',
          clientType: effective,
          questions: effective == ClientType.newborn
              ? newbornQuestions
              : childQuestions,
        ),
        concerns ?? const [],
      );
    }
    if (type != ClientType.pregnantWoman &&
        type != ClientType.postpartumWoman &&
        type != ClientType.womanOfReproductiveAge) {
      return null;
    }
    return reorder(
      CaregiverQuestionSet(
        group: 'mother',
        cohortKey: type.name,
        clientType: type,
        questions: List.unmodifiable(
          maternalQuestions.where(
            (q) => q.key != 'move' || type == ClientType.pregnantWoman,
          ),
        ),
      ),
      concerns ?? const [],
    );
  }

  /// Why [questionsFor] refuses this person, or null when a check is possible.
  ///
  /// Every registered type now has a battery, so this only fires if a future
  /// [ClientType] arrives before its questions are written — a safety net,
  /// not a routine screen.
  ({String headline, String detail})? blockReasonFor(Person person) {
    if (questionsFor(person) != null) return null;
    return (
      headline: 'This record needs a fix first',
      detail:
          '${person.fullName} is recorded as "${person.clientType.label}". No home check has been written for that kind of record yet.',
    );
  }

  bool compatible(CaregiverDraft draft, Person person) {
    final set = questionsFor(person);
    return set != null &&
        draft.kind == CaregiverDraftKind.homeCheck &&
        draft.personId == person.id &&
        draft.scope.householdId == person.householdId &&
        draft.questionVersion == questionVersion &&
        draft.cohortKey == set.cohortKey &&
        draft.answers.keys.every((k) => set.questions.any((q) => q.key == k));
  }

  /// [growth] is the last arm-tape reading already stored on this device, if
  /// there is one. A mother's answers and a health worker's tape are two views
  /// of the same child, so when the tape already says severe wasting an
  /// all-clear answer set is not all-clear. The tape can only raise a verdict,
  /// never lower one, and it can never finish an unfinished check.
  CaregiverCheckDecision decide(
    CaregiverQuestionSet? set,
    Map<String, CaregiverAnswer> answers, {
    GrowthMeasurement? growth,
  }) {
    if (set == null) return CaregiverCheckDecision.unsupported;
    final values = set.questions.map((q) => answers[q.key]);
    if (values.contains(CaregiverAnswer.yes))
      return CaregiverCheckDecision.urgent;
    if (answers.keys.any((k) => !set.questions.any((q) => q.key == k)))
      return CaregiverCheckDecision.incomplete;
    if (values.contains(CaregiverAnswer.unsure))
      return _raisedByTape(
        CaregiverCheckDecision.contactToday,
        growth,
        set.clientType,
      );
    if (values.any((v) => v != CaregiverAnswer.no))
      return CaregiverCheckDecision.incomplete;
    return _raisedByTape(CaregiverCheckDecision.routine, growth, set.clientType);
  }

  static const List<CaregiverCheckDecision> _ladder = [
    CaregiverCheckDecision.routine,
    CaregiverCheckDecision.contactToday,
    CaregiverCheckDecision.urgent,
  ];

  /// True when a stored reading is evidence about this record at all. The arm
  /// tape is read from 6 months, so a measurement attached to a young infant,
  /// a woman or nobody is not evidence for this check.
  static bool _tapeApplies(GrowthMeasurement? growth, ClientType clientType) =>
      growth != null && clientType == ClientType.childUnderFive;

  /// Severe wasting moves a verdict two steps up the ladder, moderate one step.
  /// The IMCI cut-offs belong to [GrowthMeasurement]; nothing new is invented
  /// here.
  static CaregiverCheckDecision _raisedByTape(
    CaregiverCheckDecision decision,
    GrowthMeasurement? growth,
    ClientType clientType,
  ) {
    if (!_tapeApplies(growth, clientType)) return decision;
    final steps = growth!.isSamByMuacOrOedema
        ? 2
        : growth.isMamByMuac
        ? 1
        : 0;
    if (steps == 0) return decision;
    final index = _ladder.indexOf(decision);
    if (index < 0) return decision;
    return _ladder[(index + steps).clamp(0, _ladder.length - 1)];
  }

  /// Why a stored reading moved the verdict, in words rather than a number the
  /// caregiver never entered. Names no diagnosis and promises no transmission:
  /// the reading stays on this phone.
  String? nutritionNote(CaregiverQuestionSet? set, GrowthMeasurement? growth) {
    if (set == null || !_tapeApplies(growth, set.clientType)) return null;
    if (growth!.isSamByMuacOrOedema) {
      return growth.hasBilateralOedema
          ? 'The last recorded check found swelling in both feet. That counts '
                'as severe wasting whatever the arm tape said, so a health '
                'worker needs to see them today.'
          : 'Their last arm-tape reading was below the red line. On its own '
                'that is enough for a health worker to see them today, so this '
                'check is not all-clear.';
    }
    if (growth.isMamByMuac) {
      return 'Their last arm-tape reading was in the yellow band. That is not '
          'an emergency by itself, but a health worker should see them, so '
          'this check is not all-clear.';
    }
    return null;
  }

  static String feedingSupport(Person person, DateTime now) {
    final dob = person.dateOfBirth;
    if (person.clientType == ClientType.newborn ||
        person.clientType == ClientType.childUnderFive) {
      if (dob == null || dob.isAfter(now)) {
        return "Confirm the child\u2019s age with a health worker before choosing age-specific foods.";
      }
      final sixMonths = DateTime(dob.year, dob.month + 6, dob.day);
      if (now.isBefore(sixMonths)) {
        return "For babies under six months, support breastfeeding. Do not add water, porridge or family foods. "
            "If breastfeeding is not possible or feeding is difficult, ask a health worker for individual feeding support.";
      }
      return "Continue breastfeeding if you breastfeed, and offer age-appropriate, safely prepared foods. "
          "Ask for feeding support if eating is difficult.";
    }
    return "Eat regular meals and seek individual feeding advice if you need support. Follow any advice given by your clinician.";
  }

  /// The danger signs answered YES to, in three or four words each. The alarm
  /// has to name a sign in a line, where the full question would read like a
  /// form field shouted back at her.
  static const shortSigns = {
    'feed': 'Not feeding well',
    'fast': 'Fast breathing or grunting',
    'fits': 'Fits or convulsions',
    'sleepy': 'Hard to wake',
    'temp': 'Very hot or very cold',
    'yellow': 'Looking yellow',
    'cord': 'Cord looks infected',
    'vomit': 'Vomiting everything',
    'drink': 'Unable to drink',
    'breath': 'Struggling to breathe',
    'blood': 'Blood in the stool',
    'thin': 'Very thin or swollen feet',
    'fever': 'Fever past three days',
    'bleed': 'Heavy bleeding',
    'head': 'Headache with blurred vision',
    'pain': 'Severe belly pain',
    'smell': 'Foul-smelling discharge',
    'move': 'Baby moving less',
  };

  /// The danger-sign labels the caregiver answered YES to, in question order.
  static List<String> signsFound(
    CaregiverQuestionSet set,
    Map<String, CaregiverAnswer> answers,
  ) {
    return [
      for (final q in set.questions)
        if (answers[q.key] == CaregiverAnswer.yes) q.label,
    ];
  }

  /// Compose a short message the caregiver can show or read at the clinic gate.
  /// Uses the person\u2019s first name and the specific observations.
  static String nurseMessage({
    required Person person,
    required CaregiverQuestionSet set,
    required Map<String, CaregiverAnswer> answers,
    required DateTime now,
  }) {
    final first = _displayName(person.fullName.split(" ").first);
    final yesSigns = signsFound(set, answers);
    final unsureSigns = [
      for (final q in set.questions)
        if (answers[q.key] == CaregiverAnswer.unsure) q.label,
    ];
    final buf = StringBuffer();
    if (yesSigns.isEmpty && unsureSigns.isEmpty) {
      buf.write("I checked $first today. No danger signs were noticed.");
    } else {
      buf.write("I checked $first today and noticed: ");
      buf.write(yesSigns.map((s) => s.toLowerCase()).join(", "));
      buf.write(".");
      if (unsureSigns.isNotEmpty) {
        buf.write(" I was not sure about: ");
        buf.write(unsureSigns.map((s) => s.toLowerCase()).join(", "));
        buf.write(".");
      }
    }
    final onset = answers.entries
        .where((e) => e.value == CaregiverAnswer.yes)
        .length;
    if (onset > 0) {
      buf.write(" Please examine $first.");
    }
    return buf.toString();
  }

  /// Whether a verdict justifies asking a health worker to come.
  ///
  /// Mirrors [verdictSpeech]: urgent and caution both already tell the family to
  /// reach a worker today, so a request is the same instruction with a channel.
  /// `fine` does not — and a request a family can file when nothing is wrong
  /// stops meaning anything to whoever reads the queue.
  static bool canAskForHelp(HomeCheckVerdict verdict) =>
      verdict != HomeCheckVerdict.fine;

  /// The sentence the verdict button speaks, and the reviewed bank clip that
  /// carries it — when a clip exists whose wording is actually true of this
  /// result.
  ///
  /// Bank clips are human-reviewed in four languages, so they cannot be
  /// re-worded on the fly. "Danger signs are present" reports what the family
  /// said, never what a tape reading said, so a verdict the stored
  /// measurement raised alone uses the plain facility clip instead, and a
  /// caution raised the same way has no clip at all: it falls back to
  /// composed English, which the on-device translator voices the way the rest
  /// of her prose already does.
  static ({String english, String? clipId})? verdictSpeech(
    CaregiverCheckDecision decision, {
    required bool signsReported,
    required bool uncertain,
  }) {
    String? bank(String id) => SpeechBank.byId(id)?.english;
    return switch (decision) {
      CaregiverCheckDecision.urgent when signsReported => (
        english: bank('caregiver_verdict_urgent')!,
        clipId: 'caregiver_verdict_urgent',
      ),
      CaregiverCheckDecision.urgent => (
        english: bank('level_urgent')!,
        clipId: 'level_urgent',
      ),
      CaregiverCheckDecision.contactToday when uncertain => (
        english: bank('caregiver_verdict_caution')!,
        clipId: 'caregiver_verdict_caution',
      ),
      CaregiverCheckDecision.contactToday => (
        english:
            'A measurement taken at the clinic was in the yellow band on the '
            'arm tape. Show this check to a health worker today.',
        clipId: null,
      ),
      CaregiverCheckDecision.routine => (
        english: bank('caregiver_verdict_fine')!,
        clipId: 'caregiver_verdict_fine',
      ),
      _ => null,
    };
  }

  /// Personalised advice that names the person and references the specific
  /// signs found. Falls back to a safe generic message if nothing specific
  /// applies.
  ///
  /// [growth] is the stored measurement [decide] may have used. When it did,
  /// and she reported no danger sign, the reason has to be named as the
  /// measurement: telling a mother she noticed signs she answered "no" to
  /// would attribute a report she never made.
  static String contextualAdvice({
    required Person person,
    required CaregiverCheckDecision decision,
    required CaregiverQuestionSet set,
    required Map<String, CaregiverAnswer> answers,
    GrowthMeasurement? growth,
  }) {
    final first = _displayName(person.fullName.split(" ").first);
    final yesSigns = signsFound(set, answers);
    final hasUnsure = answers.values.contains(CaregiverAnswer.unsure);
    final fromMeasurement =
        yesSigns.isEmpty && _tapeApplies(growth, set.clientType);
    final mother =
        person.effectiveClientType != ClientType.newborn &&
        person.effectiveClientType != ClientType.childUnderFive;

    switch (decision) {
      case CaregiverCheckDecision.urgent:
        final buf = StringBuffer();
        if (fromMeasurement) {
          buf.write(
            "The last measurement taken at the clinic was below the red line "
            "on the arm tape, so $first needs to be seen at a health facility "
            "now \u2014 even though you have not noticed these danger signs "
            "today. ",
          );
        } else {
          buf.write("You noticed danger signs in $first. ");
        }
        if (yesSigns.length == 1) {
          buf.write("${yesSigns.single} needs attention now. ");
        } else if (yesSigns.length > 1) {
          buf.write("Go to the health facility now \u2014 do not wait. ");
        }
        if (mother) {
          buf.write(
            "If she can swallow, give small sips of water on the way. "
            "Do not give any medicine unless the nurse tells you to.",
          );
        } else {
          buf.write(
            "Keep $first warm. If $first can swallow, keep breastfeeding or "
            "give small sips of clean water on the way. "
            "Do not give any medicine unless the nurse tells you to.",
          );
        }
        return buf.toString();

      case CaregiverCheckDecision.contactToday:
        final buf = StringBuffer();
        if (fromMeasurement) {
          buf.write(
            "The last measurement taken at the clinic was in the yellow band "
            "on the arm tape, so a health worker should see $first. "
            "Contact your health worker or CHPS compound today. "
            "If $first becomes very unwell before then, go to the health "
            "facility immediately.",
          );
          return buf.toString();
        }
        if (hasUnsure) {
          buf.write("Some of your answers for $first were not clear. ");
        }
        buf.write(
          "Contact your health worker or CHPS compound today to describe what you noticed. "
          "If $first becomes very unwell before then, go to the health facility immediately.",
        );
        return buf.toString();

      case CaregiverCheckDecision.routine:
        return "You did not notice any danger signs in $first today. "
            "Keep feeding, watching, and checking as you are doing. "
            "Check again tomorrow, or any time something worries you.";

      default:
        return "Please check again or contact your health worker.";
    }
  }

  /// Names arrive in whatever case the register holds — "cee" must read as
  /// "Cee" in words spoken to the family.
  static String _displayName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return trimmed;
    return trimmed
        .split(RegExp(r'\s+'))
        .map(
          (word) => word.isEmpty
              ? word
              : '${word[0].toUpperCase()}${word.substring(1)}',
        )
        .join(' ');
  }
}
