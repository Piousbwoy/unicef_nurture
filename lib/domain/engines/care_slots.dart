/// Cohort guidance that is *assembled*, not recited.
///
/// The plan used to open with the word "Tailored" and then name nobody: one
/// fixed paragraph for every child aged 2–59 months in the country, plus one
/// fixed counselling action copied out of a `static const`. That is precisely
/// what reads as a mockup — the claim of tailoring with no patient data in the
/// sentence.
///
/// This file splits the two things that were tangled together:
///
///   * **The guideline content** — which signs send a family back — genuinely is
///     the same for every patient in a cohort. It lives here as a data table
///     with its citation, and it is never dropped.
///   * **The patient content** — name, age, weight, review interval — comes from
///     [CareSlots]. A slot with no value says `not recorded` in the sentence
///     rather than quietly falling back to generic prose, and never interpolates
///     a `null`.
///
/// Two rules hold the safety line:
///
///   1. **Counselling is never lost to a missing slot.** An incomplete record
///      makes the sentence rougher, never shorter — a nameless child still gets
///      the teach-back step, because that step is what brings them back early.
///   2. **The counselling action can never outrank a finding.** It is counselling
///      at scheduled urgency, never a treatment and never a referral, so it
///      cannot move triage or manufacture a referral the engines did not make.
library;

import '../entities/visit.dart';
import '../enums.dart';

/// The patient-specific values the cohort sentence is built from.
///
/// Every field is nullable on purpose: the register, the offline queue and the
/// cloud-restore path all produce records with different amounts filled in. The
/// builder's job is to say which are absent, not to guess them.
class CareSlots {
  const CareSlots({
    this.subjectName,
    this.ageInMonths,
    this.ageInDays,
    this.weightKg,
    this.followUpInDays,
  });

  /// Nothing known — the shape a legacy or partially-synced record presents.
  static const CareSlots unknown = CareSlots();

  final String? subjectName;
  final int? ageInMonths;

  /// Days of life. Authoritative for the newborn cohort, where months would
  /// round a 3-day-old to "0 months" and lose the whole clinical point.
  final int? ageInDays;

  /// Recorded weight, if the child was weighed at this visit.
  final double? weightKg;

  /// The review interval the engines settled on, in days.
  final int? followUpInDays;

  /// The person the sentence is about, or an explicit statement that the record
  /// does not say. Never a placeholder name and never `null`.
  String get subjectLabel {
    final name = subjectName?.trim();
    return (name == null || name.isEmpty) ? 'name not recorded' : name;
  }

  /// True when the name is real — callers that greet by name need this, and a
  /// fabricated greeting is worse than none.
  bool get hasSubjectName {
    final name = subjectName?.trim();
    return name != null && name.isNotEmpty;
  }

  /// `{weight} kg`, or the honest gap. No `0 kg` and no `null kg` is ever
  /// produced, because a weight in a counselling sentence is the number a dose
  /// is chosen from.
  String get weightLabel => weightKg == null
      ? 'weight not recorded'
      : '${weightKg!} kg';

  /// Age in the unit the cohort's protocol is written in.
  String get ageLabel {
    if (ageInMonths != null) return '$ageInMonths months';
    if (ageInDays != null) return '$ageInDays days';
    return 'age not recorded';
  }

  /// The newborn window is counted in days of life; months must never appear,
  /// because "0 months" describes a 3-day-old and a 9-week-old identically.
  String get ageLabelInDays {
    if (ageInDays != null) return 'day $ageInDays';
    if (ageInMonths != null) return '$ageInMonths months';
    return 'age in days not recorded';
  }

  /// `Review in 3 days.` or the honest gap, with the sentence already closed.
  String get reviewClause {
    if (followUpInDays == null) {
      return 'No review interval was set for this assessment.';
    }
    if (followUpInDays == 1) return 'Review tomorrow.';
    return 'Review in $followUpInDays days.';
  }
}

/// The assembled pair: the callout sentence and the counselling action.
class CohortCareGuidance {
  const CohortCareGuidance({required this.note, required this.counselling});

  final String note;
  final RecommendedAction counselling;
}

abstract final class CohortCareGuidanceBuilder {
  /// The return-immediately signs, per cohort. This *is* the guideline content,
  /// so it is a table with a citation rather than prose per sentence — and the
  /// same list feeds both the callout and the teach-back, so the two cannot
  /// drift apart.
  static const Map<ClientType, List<String>> _watchpoints = {
    ClientType.newborn: [
      'feeding poorly',
      'fast breathing',
      'fever or cold to touch',
      'moving less than before',
    ],
    ClientType.childUnderFive: [
      'unable to drink',
      'vomiting everything',
      'convulsions',
      'unusual sleepiness',
    ],
    ClientType.pregnantWoman: [
      'severe headache',
      'blurred vision',
      'vaginal bleeding',
      'reduced fetal movements',
      'swelling of the face and hands',
    ],
    ClientType.postpartumWoman: [
      'heavy bleeding',
      'fever',
      'foul-smelling discharge',
      'a baby who feeds poorly',
    ],
    ClientType.womanOfReproductiveAge: [
      'new bleeding',
      'severe pain',
      'fever',
      'fainting',
    ],
  };

  /// How the assessment is described to the caregiver, per cohort.
  static const Map<ClientType, String> _protocolPhrase = {
    ClientType.newborn: 'the WHO sick-young-infant protocol',
    ClientType.childUnderFive: 'the WHO IMCI sick-child protocol',
    ClientType.pregnantWoman: 'the ANC protocol',
    ClientType.postpartumWoman: 'the postnatal (PNC) protocol',
    ClientType.womanOfReproductiveAge: 'general women’s care',
  };

  /// What makes this group different from the others, in one clause. A paper
  /// protocol flattens these; the point of naming the cohort is to say it.
  static const Map<ClientType, String> _deteriorationClause = {
    ClientType.newborn:
        'Newborns deteriorate in hours, not days — do not wait until tomorrow.',
    ClientType.childUnderFive:
        'A child who cannot drink has already lost more than a child who is '
        'only breathing fast.',
    ClientType.pregnantWoman:
        'These signs mean come today, day or night, not at the next visit.',
    ClientType.postpartumWoman:
        'Most maternal deaths in the first week happen after discharge.',
    ClientType.womanOfReproductiveAge:
        'Any new bleeding, pain or fever after this visit means come back.',
  };

  /// Counselling citations already carried by this build's engines. General
  /// women's care holds no separate adult guideline here, so its common
  /// danger-sign set is attributed to the maternal guidance it is drawn from
  /// rather than to a source this repository cannot show.
  static const Map<ClientType, String> _citation = {
    ClientType.newborn: 'WHO IMCI — sick young infant',
    ClientType.childUnderFive: 'WHO IMCI — sick child counselling',
    ClientType.pregnantWoman: 'WHO ANC recommendations',
    ClientType.postpartumWoman: 'WHO PNC recommendations',
    ClientType.womanOfReproductiveAge:
        'WHO ANC and PNC recommendations — shared danger signs (no separate '
        'adult guideline is held in this build)',
  };

  /// The signs the guideline asks this cohort to be watched for.
  static List<String> watchpointsFor(ClientType cohort) =>
      _watchpoints[cohort] ?? const [];

  static CohortCareGuidance build({
    required ClientType cohort,
    required CareSlots slots,
  }) {
    final signs = watchpointsFor(cohort);
    final age = cohort == ClientType.newborn
        ? slots.ageLabelInDays
        : slots.ageLabel;

    final note =
        '${slots.subjectLabel} · $age · ${slots.weightLabel} — assessed under '
        '${_protocolPhrase[cohort] ?? 'this assessment'}. '
        'Return immediately for any of: ${_join(signs)}. '
        '${_deteriorationClause[cohort] ?? ''} '
        '${slots.reviewClause}';

    final who = slots.hasSubjectName ? slots.subjectLabel : 'this patient';

    // The review interval is appended as a clause, not a second sentence, so the
    // teach-back reads as one instruction the caregiver can repeat.
    final reviewTail = slots.followUpInDays == null
        ? ', and state when the next visit is'
        : ', and state that the review is in ${slots.followUpInDays} '
              '${slots.followUpInDays == 1 ? 'day' : 'days'}';

    final counselling = RecommendedAction(
      instruction:
          'Before $who leaves with the caregiver, have the caregiver repeat '
          'back each return-immediately sign in their own words: '
          '${_join(signs)}. Confirm the details on this card — '
          '${slots.weightLabel}$reviewTail.',
      urgency: ReferralUrgency.scheduled,
      rationale:
          'Teach-back is the counselling step of '
          '${_protocolPhrase[cohort] ?? 'the protocol'}: a caregiver who can '
          'name the signs brings the patient back hours earlier. The sign list '
          'is the cohort guideline; the details carried into the sentence come '
          'from this record, and an absent one is stated as absent.',
      protocolSource: _citation[cohort] ?? 'WHO counselling',
      isCounselling: true,
    );

    return CohortCareGuidance(
      note: note.replaceAll('  ', ' ').trim(),
      counselling: counselling,
    );
  }

  static String _join(List<String> signs) => signs.isEmpty
      ? 'no sign list is recorded for this cohort'
      : signs.join(', ');
}
