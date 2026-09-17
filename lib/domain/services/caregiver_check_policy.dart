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
    CaregiverQuestion('feed', 'Is the baby not breastfeeding or feeding poorly?'),
    CaregiverQuestion('fast', 'Is the baby breathing fast or making grunting sounds?'),
    CaregiverQuestion('fits', 'Has the baby had any fits or convulsions?'),
    CaregiverQuestion('sleepy', 'Is the baby unusually sleepy or hard to wake?'),
    CaregiverQuestion('temp', 'Does the baby feel very hot or very cold?'),
    CaregiverQuestion('yellow', 'Do the baby\u2019s hands or feet look yellow?'),
    CaregiverQuestion('cord', 'Is the umbilical cord red, swollen, or smelly?'),
    CaregiverQuestion('vomit', 'Is the baby vomiting everything?'),
  ];
  static const childQuestions = [
    CaregiverQuestion('drink', 'Is the child unable to drink or breastfeed?'),
    CaregiverQuestion('vomit', 'Is the child vomiting everything?'),
    CaregiverQuestion('fits', 'Has the child had any fits or convulsions?'),
    CaregiverQuestion('sleepy', 'Is the child unusually sleepy or hard to wake?'),
    CaregiverQuestion('breath', 'Is the child breathing fast or struggling to breathe?'),
    CaregiverQuestion('blood', 'Is there blood in the child\u2019s stool?'),
    CaregiverQuestion('thin', 'Is the child becoming very thin or are the feet swollen?'),
    CaregiverQuestion('fever', 'Has the child had fever for more than three days?'),
  ];
  static const maternalQuestions = [
    CaregiverQuestion('bleed', 'Is there heavy bleeding?'),
    CaregiverQuestion('head', 'Is there a severe headache with blurred vision?'),
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
    'fits' => 'Any fit, however short, means the facility now — note the time it started.',
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
    'blood' => 'Any blood in the stool needs to be shown to a health worker today.',
    'thin' =>
      'Check the arms and feet this week. Swelling of both feet, or visible wasting, needs the clinic.',
    'fever' =>
      'Note the time of day it rises. Fever past three days, or with any danger sign, needs a test.',
    'bleed' =>
      'Change pads on a schedule and count. Soaking more than one pad an hour is heavy bleeding.',
    'head' =>
      'Ask her to describe it. Headache with blurred vision or swelling means come in now.',
    'pain' => 'Watch where it sits and what makes it worse. Sudden severe pain needs the clinic.',
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
    if (cohort == ClientType.postpartumWoman.name) {
      return maternalQuestions.where((q) => q.key != 'move').toList();
    }
    return null;
  }

  CaregiverQuestionSet? questionsFor(
    Person person, {
    List<String>? concerns,
  }) {
    final type = person.clientType;
    if (type == ClientType.newborn || type == ClientType.childUnderFive) {
      final dob = person.dateOfBirth;
      if (dob == null) return null;
      final now = clock().toLocal();
      final born = dob.toLocal();
      final days = DateTime.utc(
        now.year,
        now.month,
        now.day,
      ).difference(DateTime.utc(born.year, born.month, born.day)).inDays;
      final valid = ClientType.forChildAgeInDays(days);
      if (valid == null) return null;
      final group = valid == ClientType.newborn ? 'newborn' : 'child';
      return reorder(
        CaregiverQuestionSet(
          group: group,
          cohortKey: '$group:${caregiverDateKey(dob)}',
          clientType: valid,
          questions: valid == ClientType.newborn
              ? newbornQuestions
              : childQuestions,
        ),
        concerns ?? const [],
      );
    }
    if (type != ClientType.pregnantWoman && type != ClientType.postpartumWoman)
      return null;
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

  CaregiverCheckDecision decide(
    CaregiverQuestionSet? set,
    Map<String, CaregiverAnswer> answers,
  ) {
    if (set == null) return CaregiverCheckDecision.unsupported;
    final values = set.questions.map((q) => answers[q.key]);
    if (values.contains(CaregiverAnswer.yes))
      return CaregiverCheckDecision.urgent;
    if (answers.keys.any((k) => !set.questions.any((q) => q.key == k)))
      return CaregiverCheckDecision.incomplete;
    if (values.contains(CaregiverAnswer.unsure))
      return CaregiverCheckDecision.contactToday;
    if (values.any((v) => v != CaregiverAnswer.no))
      return CaregiverCheckDecision.incomplete;
    return CaregiverCheckDecision.routine;
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
    final first = person.fullName.split(" ").first;
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

  /// Personalised advice that names the person and references the specific
  /// signs found. Falls back to a safe generic message if nothing specific
  /// applies.
  static String contextualAdvice({
    required Person person,
    required CaregiverCheckDecision decision,
    required CaregiverQuestionSet set,
    required Map<String, CaregiverAnswer> answers,
  }) {
    final first = person.fullName.split(" ").first;
    final yesSigns = signsFound(set, answers);
    final hasUnsure = answers.values.contains(CaregiverAnswer.unsure);
    final mother =
        person.effectiveClientType != ClientType.newborn &&
        person.effectiveClientType != ClientType.childUnderFive;

    switch (decision) {
      case CaregiverCheckDecision.urgent:
        final buf = StringBuffer();
        buf.write("You noticed danger signs in $first. ");
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
}
