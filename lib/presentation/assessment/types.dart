/// Shared types for the assessment flow.
///
/// Kept in their own file so the protocol forms, the shell and the result
/// screen can all depend on them without importing each other.
library;

import '../../domain/entities/core.dart';
import '../../domain/entities/visit.dart';

/// Everything a protocol form is allowed to know before it asks a question.
///
/// The forms prefill from this rather than re-asking: a CHO should never be
/// made to type the birth weight of a baby whose birth record is already in
/// the app, and a form that re-asks what the record knows teaches its users
/// that the record does not matter.
class AssessmentContext {
  const AssessmentContext({
    required this.user,
    required this.household,
    required this.person,
    this.maternal,
    this.birth,
  });

  final AppUser user;
  final Household household;
  final Person person;

  /// Present for mothers — carries the LMP, delivery facts and history.
  final MaternalRecord? maternal;

  /// Present for newborns — carries birth weight, gestation, resuscitation.
  final BirthRecord? birth;

  bool? get hasValidNhis => household.hasValidNhis;
  int? get walkingMinutes => household.walkingMinutesToFacility;
}

/// What a protocol form hands back when the engine has run: the raw answers,
/// the verdict, and any growth measurement worth keeping in the child's
/// series so the trajectory engine can see the slope, not just the points.
class AssessmentDraft {
  const AssessmentDraft({
    required this.inputs,
    required this.result,
    this.growth,
    this.snapshot,
  });

  /// Every answer, verbatim. Stored with the assessment so the record is
  /// auditable and the model can be re-run when it improves.
  final Map<String, Object?> inputs;

  final AssessmentResult result;

  /// MUAC / weight / height taken during this assessment, if any.
  final GrowthMeasurement? growth;

  /// Structured IMCI sick-child / young-infant snapshot of all 85+ fields,
  /// aligned with the Ghana GHS IMCI Case Recording Form. Used by the
  /// OfflineInferenceService and Plan A/B/C classifier.
  final ChildAssessmentSnapshot? snapshot;
}
