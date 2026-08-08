/// Domain enumerations shared across CareBridge AI.
///
/// These deliberately mirror the vocabulary a Ghanaian CHO already uses on
/// paper — ANC contact, PNC day 3, IMCI classification, OTP — so that the app
/// never asks a health worker to learn a second language for the same job.
library;

import 'dart:ui' show Color;

// ---------------------------------------------------------------------- Roles

enum UserRole {
  /// Community Health Officer / Nurse at a CHPS compound. Full clinical scope.
  frontlineHealthWorker('Frontline Health Worker', 'FHW'),

  /// Mother, father, grandmother or guardian. Danger-sign triage only —
  /// never diagnosis, never clinical data entry.
  caregiver('Caregiver', 'Caregiver');

  const UserRole(this.label, this.shortLabel);
  final String label;
  final String shortLabel;

  bool get isFhw => this == UserRole.frontlineHealthWorker;
  bool get isCaregiver => this == UserRole.caregiver;
}

/// Capability-based permissions. Screens ask "can I?" rather than "which role
/// am I?", so adding a role later (CHV, TBA, district officer) does not require
/// touching every widget.
enum Permission {
  registerHousehold,
  viewAllHouseholds,
  viewOwnFamilyOnly,
  manageOwnFamily,
  recordClinicalVitals,
  runClinicalAssessment,
  runCaregiverTriage,
  issueReferral,
  confirmReferralArrival,
  overrideAiRecommendation,
  viewCommunityInsights,
  recordBarrier,
  planVisitRoute,
  exportRecords;

  static const Set<Permission> _fhw = {
    registerHousehold,
    viewAllHouseholds,
    recordClinicalVitals,
    runClinicalAssessment,
    issueReferral,
    confirmReferralArrival,
    overrideAiRecommendation,
    viewCommunityInsights,
    recordBarrier,
    planVisitRoute,
    exportRecords,
  };

  static const Set<Permission> _caregiver = {
    viewOwnFamilyOnly,
    runCaregiverTriage,
    recordBarrier,
    // A family can start its own record before a health worker ever reaches
    // it: create the household and add the people they care for. Strictly
    // self-service — the repository refuses any household other than the one
    // the account is bound to, and no clinical field is writable with it.
    manageOwnFamily,
  };

  static Set<Permission> forRole(UserRole role) =>
      role.isFhw ? _fhw : _caregiver;
}

// --------------------------------------------------------------- Client types

/// Who is being assessed. Drives which protocol engine runs.
enum ClientType {
  /// Pregnant woman — ANC protocol.
  pregnantWoman('Pregnant woman', 'ANC'),

  /// Delivered within the last 42 days — PNC protocol.
  postpartumWoman('Mother after delivery', 'PNC'),

  /// Woman of reproductive age presenting for general or family-planning care.
  womanOfReproductiveAge('Woman (general care)', 'General'),

  /// 0–59 days. IMCI "sick young infant" protocol.
  newborn('Newborn (0–2 months)', 'Young infant'),

  /// 2–59 months. IMCI "sick child" protocol.
  childUnderFive('Child (2–59 months)', 'IMCI');

  const ClientType(this.label, this.protocolLabel);
  final String label;
  final String protocolLabel;

  /// The newborn window is 0–59 days inclusive; IMCI child protocol starts at
  /// 2 months. Anything past 59 months has aged out of this app's scope.
  static ClientType? forChildAgeInDays(int days) {
    if (days < 0) return null;
    if (days <= 59) return ClientType.newborn;
    if (days <= 59 * 30.4375) return ClientType.childUnderFive;
    return null;
  }
}

enum Sex {
  male('Male'),
  female('Female');

  const Sex(this.label);
  final String label;
}

// ------------------------------------------------------------- Visit context

/// Why the CHO opened this visit. Multiple reasons can apply to one household
/// visit, because in reality a mother presents with three children and her own
/// complaint at the same time.
enum VisitReason {
  newPregnancy('New pregnancy (ANC registration)'),
  ancFollowUp('ANC follow-up contact'),
  pncFollowUp('Postnatal (PNC) contact'),
  newbornRegistration('Newborn registration after delivery'),
  childWelfare('Child welfare / growth monitoring'),
  motherUnwell('Mother reports illness'),
  childUnwell('Child reports illness'),
  dangerSignReported('Danger sign reported'),
  routineHomeVisit('Routine check-up'),
  referralFollowUp('Referral follow-up'),
  defaulterTracing('Defaulter tracing'),
  familyPlanning('Family planning counselling');

  const VisitReason(this.label);
  final String label;
}

enum DeliveryPlace {
  chpsCompound('CHPS compound'),
  healthCentre('Health centre'),
  districtHospital('District hospital'),
  regionalHospital('Regional / teaching hospital'),
  home('At home'),
  tba('With a traditional birth attendant'),
  enRoute('On the way to a facility');

  const DeliveryPlace(this.label);
  final String label;

  /// Home, TBA and en-route deliveries carry materially higher newborn risk and
  /// usually mean no vitamin K, no cord care and no immediate newborn checks.
  bool get isUnattendedBySkilledProvider =>
      this == DeliveryPlace.home ||
      this == DeliveryPlace.tba ||
      this == DeliveryPlace.enRoute;
}

enum DeliveryMode {
  spontaneousVaginal('Normal vaginal delivery'),
  assistedVaginal('Assisted (vacuum / forceps)'),
  caesarean('Caesarean section'),
  breech('Breech delivery');

  const DeliveryMode(this.label);
  final String label;
}

/// Multiple births are common enough in Northern Ghana that the app must handle
/// them as a first-class case, not an edge case — and twins carry far higher
/// neonatal mortality.
enum BirthPlurality {
  singleton('Single baby', 1),
  twin('Twins', 2),
  triplet('Triplets or more', 3);

  const BirthPlurality(this.label, this.babies);
  final String label;
  final int babies;
}

// ------------------------------------------------------------------- Triage

/// Colour bands taken straight from the WHO IMCI chart booklet, which every
/// Ghanaian CHO is trained on. Reusing their convention means the app needs no
/// explanation.
enum TriageLevel {
  /// Pink row: urgent referral. Life-threatening now.
  urgent('Urgent — refer now', 4),

  /// Yellow row: needs treatment and a scheduled follow-up.
  priority('Priority — treat and follow up', 3),

  /// Yellow row, lower acuity: watch and review.
  watch('Watch — review at next contact', 2),

  /// Green row: home care and counselling.
  routine('Routine — home care advice', 1);

  const TriageLevel(this.label, this.severity);
  final String label;
  final int severity;

  bool get requiresReferral => this == TriageLevel.urgent;
  bool get isAtLeastPriority => severity >= TriageLevel.priority.severity;
}

/// The outcome of a caregiver's danger-sign check at home.
///
/// Deliberately NOT a [TriageLevel]: a mother's checklist is a report of what
/// she saw, never a clinical grading. Storing the family's own words keeps
/// the two kinds of evidence apart — the FHW reads "the family reported"
/// and not "the app diagnosed".
enum HomeCheckVerdict {
  urgent('Go to the health facility now'),
  caution('Visit the CHW soon'),
  fine('Continue routine care');

  const HomeCheckVerdict(this.label);
  final String label;
}

/// The family's read on their child's development, from the milestone check.
/// Same rule as [HomeCheckVerdict]: this is the family's words, never a
/// diagnosis — a flag means "show the health worker", nothing more.
///
/// [colourArgb] is the canonical int (ARGB) form, and [colour] is the
/// presentation-side [Color]. Both are exposed so the domain tests can
/// stay free of [Color] while the UI gets a typed colour.
enum MilestoneVerdict {
  onTrack(
    'Growing as expected',
    0xFF2F9E44, // green
  ),
  watch(
    'Keep playing — check again soon',
    0xFFE67700, // amber
  ),
  flag(
    'Show the health worker',
    0xFFE03131, // red
  );

  const MilestoneVerdict(this.label, this.colourArgb);
  final String label;
  final int colourArgb;
  Color get colour => Color(colourArgb);
}

/// Acute malnutrition bands by MUAC (mid-upper arm circumference), 6–59 months.
/// Cut-offs are WHO/Ghana Health Service standard.
enum NutritionStatus {
  severeAcute('Severe acute malnutrition (SAM)', TriageLevel.urgent),
  moderateAcute('Moderate acute malnutrition (MAM)', TriageLevel.priority),
  atRisk('At risk of malnutrition', TriageLevel.watch),
  normal('Adequate nutrition', TriageLevel.routine);

  const NutritionStatus(this.label, this.triage);
  final String label;
  final TriageLevel triage;
}

/// Where a child with acute malnutrition must actually be managed.
///
/// This distinction is the single most consequential branch in the whole app:
/// SAM is treated with **therapeutic food (RUTF or F-75)**, never with home
/// diet advice. Local-food counselling belongs to MAM and to prevention.
enum NutritionPathway {
  inpatientTherapeutic(
    'Inpatient therapeutic care',
    'SAM with danger signs, oedema, failed appetite test, or age under 6 months. '
        'Needs F-75 and 24-hour medical care.',
  ),
  outpatientTherapeutic(
    'Outpatient Therapeutic Programme (OTP)',
    'SAM with appetite and no complications. Weekly RUTF ration and review.',
  ),
  supplementaryFeeding(
    'Supplementary feeding + local-food counselling',
    'MAM. Local affordable foods plus supplementary ration where available.',
  ),
  preventiveCounselling(
    'Preventive nutrition counselling',
    'Adequate nutrition. Reinforce age-appropriate feeding and growth monitoring.',
  );

  const NutritionPathway(this.label, this.rationale);
  final String label;
  final String rationale;

  bool get needsTherapeuticFood =>
      this == inpatientTherapeutic || this == outpatientTherapeutic;
}

// ---------------------------------------------------------------- Referrals

enum ReferralUrgency {
  immediate('Go now — do not wait'),
  sameDay('Today'),
  withinTwoDays('Within 2 days'),
  scheduled('At the next scheduled contact');

  const ReferralUrgency(this.label);
  final String label;
}

/// Referral lifecycle. `didNotAttend` is the state that matters most — it is
/// where the last-mile follow-up challenge actually lives, and where the
/// barrier capture is triggered.
enum ReferralStatus {
  issued('Referral issued'),
  travelling('Family reported travelling'),
  arrived('Confirmed arrived at facility'),
  treated('Treated and discharged'),
  didNotAttend('Did not attend'),
  refused('Family declined referral'),
  cancelled('Cancelled');

  const ReferralStatus(this.label);
  final String label;

  bool get isOpen => this == issued || this == travelling;
  bool get isFailure => this == didNotAttend || this == refused;
}

// ----------------------------------------------------------------- Barriers

/// Why a household did not, or will not, seek care.
///
/// This is the "hidden barriers" challenge. Each barrier maps to a *different*
/// action — which is the whole point of capturing it rather than recording a
/// bare "did not attend".
enum CareBarrier {
  noTransportMoney(
    'No money for transport',
    'Link to community transport fund or arrange a motorking; consider an '
        'outreach visit instead of a facility visit.',
  ),
  distanceTooFar(
    'Facility is too far',
    'Refer to the nearest adequate facility rather than the usual one; plan a '
        'home follow-up.',
  ),
  noPermission(
    'Needs permission from husband or family',
    'Schedule a family conversation including the husband and mother-in-law '
        'before the next contact.',
  ),
  noNhisCard(
    'No valid NHIS card',
    'Start NHIS registration support; remind the family that maternal care is '
        'free under the exemption policy.',
  ),
  noChildcare(
    'No one to mind the other children',
    'Offer an outreach or home visit; arrange neighbour support.',
  ),
  facilityClosed(
    'Facility was closed or no staff',
    'Confirm facility hours and staffing before the next referral; escalate to '
        'the sub-district.',
  ),
  pastBadExperience(
    'Bad experience at the facility before',
    'Accompany the family for the next visit; report the concern through the '
        'CHPS feedback route.',
  ),
  preferredTraditional(
    'Prefers traditional or spiritual care',
    'Engage respectfully alongside the traditional provider; agree on danger '
        'signs that mean going to the facility immediately.',
  ),
  fearOfProcedure(
    'Fear of injection, surgery or blood test',
    'Explain the procedure in the local language; use the audio guide.',
  ),
  farmWorkload(
    'Farm or market work could not be left',
    'Offer an early-morning or evening contact; plan around market days and the '
        'farming calendar.',
  ),
  floodedRoad(
    'Road flooded or impassable',
    'Plan around the rains; pre-position advice and arrange a phone follow-up.',
  ),
  didNotThinkItSerious(
    'Did not think it was serious',
    'Replay the danger-sign audio with the caregiver; confirm they can name '
        'three signs that mean go now.',
  );

  const CareBarrier(this.label, this.suggestedAction);
  final String label;
  final String suggestedAction;
}

// -------------------------------------------------------------- Sync states

enum SyncState {
  /// Written locally, not yet transmitted. The normal state in the field.
  pending('Waiting to sync'),
  uploading('Uploading'),
  synced('Synced'),
  failed('Sync failed — will retry'),

  /// Server and device both changed the record; needs a human decision.
  conflict('Needs review');

  const SyncState(this.label);
  final String label;
}

// ------------------------------------------------------- Confidence framing

/// How much weight the CHO should give the recommendation.
///
/// Showing uncertainty honestly is a Responsible-AI requirement, not a
/// weakness: a tool that admits when it is guessing gets trusted when it is not.
enum RecommendationConfidence {
  protocolCertain(
    'Protocol-based',
    'Derived directly from a measured value against a published cut-off.',
  ),
  high('High confidence', 'Multiple consistent indicators.'),
  moderate(
    'Moderate confidence',
    'Some indicators are missing or were reported rather than measured.',
  ),
  low(
    'Low confidence — follow protocol',
    'Key measurements are missing. Use clinical judgement and confirm with a '
        'test or a tape before acting.',
  );

  const RecommendationConfidence(this.label, this.meaning);
  final String label;
  final String meaning;
}
