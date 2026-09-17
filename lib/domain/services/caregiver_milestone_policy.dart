import '../engines/nurturing_care_engine.dart';
import '../entities/caregiver.dart';
import '../entities/core.dart';
import '../entities/visit.dart';
import '../enums.dart';

/// Persistence adapter for the existing milestone screen's screening rules.
/// Trying a play activity never calls this policy or records an achievement.
abstract final class CaregiverMilestonePolicy {
  static const questionVersion = 2;

  // Caregiver-only positive wording makes YES consistently mean an observed
  // skill. Stable IDs remain intact; v1 drafts cannot reuse inverted answers.
  // Review against WHO CCD / CDC surveillance guidance before deployment.
  static const _positiveQuestions = {
    'no_eye_contact_4m': 'Looks at your face or eyes during interaction',
    'no_words_12m': 'Babbles strings of sounds like "ba-ba-ba"',
    'not_walking_15m': 'Has started walking',
    'no_2word_phrases_24m': 'Has started saying 2 words together',
  };
  static int? ageMonths(Person person, DateTime now) {
    if (person.clientType != ClientType.newborn &&
        person.clientType != ClientType.childUnderFive) {
      return null;
    }
    final dob = person.dateOfBirth;
    if (dob == null || dob.isAfter(now)) return null;
    return (now.difference(dob).inDays / 30.4375).floor();
  }

  static NcAgeBand? bandFor(Person person, DateTime now) {
    final band = NurturingCareEngine.bandFor(ageMonths(person, now));
    if (band == null) return null;
    final milestones = band.milestones
        .map(
          (m) => NcMilestone(
            id: m.id,
            domain: m.domain,
            question: _positiveQuestions[m.id] ?? m.question,
            isFlag: m.isFlag,
          ),
        )
        .toList(growable: false);
    return NcAgeBand(
      minMonths: band.minMonths,
      maxMonths: band.maxMonths,
      label: band.label,
      milestones: milestones,
      activities: band.activities,
      tip: band.tip,
      flags: milestones.where((m) => m.isFlag).toList(),
    );
  }

  static bool compatible(CaregiverDraft draft, Person person, DateTime now) {
    final band = bandFor(person, now);
    return band != null &&
        draft.kind == CaregiverDraftKind.milestone &&
        draft.personId == person.id &&
        draft.questionVersion == questionVersion &&
        draft.cohortKey == cohortKey(person, band) &&
        draft.questionIndex >= 0 &&
        draft.questionIndex < band.milestones.length &&
        draft.answers.entries.every(
          (entry) =>
              band.milestones.any((m) => m.id == entry.key) &&
              entry.value != CaregiverAnswer.unsure,
        );
  }

  static String cohortKey(Person person, NcAgeBand band) =>
      '${caregiverDateKey(person.dateOfBirth!)}:${band.minMonths}:${band.maxMonths}';
  static MilestoneCheck report(
    CaregiverDraft draft,
    Person person,
    DateTime now,
  ) {
    final band = bandFor(person, now);
    if (band == null ||
        draft.kind != CaregiverDraftKind.milestone ||
        draft.questionVersion != questionVersion ||
        draft.cohortKey != cohortKey(person, band) ||
        draft.answers.length != band.milestones.length ||
        band.milestones.any(
          (m) =>
              draft.answers[m.id] != CaregiverAnswer.yes &&
              draft.answers[m.id] != CaregiverAnswer.no,
        )) {
      throw const CaregiverDataException(
        'Review all milestone answers for the child’s current age before saving.',
      );
    }
    final notYet = band.milestones
        .where((m) => draft.answers[m.id] == CaregiverAnswer.no)
        .toList();
    final flags = notYet.where((m) => m.isFlag).map((m) => m.question).toList();
    return MilestoneCheck(
      id: draft.id,
      householdId: draft.scope.householdId,
      personId: person.id,
      ageMonths: ageMonths(person, draft.startedAt)!,
      bandLabel: band.label,
      verdict: flags.isNotEmpty
          ? MilestoneVerdict.flag
          : notYet.length >= 2
          ? MilestoneVerdict.watch
          : MilestoneVerdict.onTrack,
      canDo: band.milestones
          .where((m) => draft.answers[m.id] == CaregiverAnswer.yes)
          .map((m) => m.question)
          .toList(),
      notYet: notYet.map((m) => m.question).toList(),
      flags: flags,
      checkedBy: draft.scope.userId,
      checkedAt: draft.startedAt,
    );
  }
}
