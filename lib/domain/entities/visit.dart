import 'dart:convert';

import '../enums.dart';

/// A single household encounter. One visit can carry several assessments —
/// a mother plus her newborn twins plus a three-year-old, all in one sitting.
/// Modelling it this way means the CHO records the *visit* once and the app
/// keeps the queue of people straight.
class Visit {
  const Visit({
    required this.id,
    required this.householdId,
    required this.conductedBy,
    required this.startedAt,
    required this.reasons,
    this.completedAt,
    this.latitude,
    this.longitude,
    this.notes,
    this.syncState = SyncState.pending,
  });

  final String id;
  final String householdId;
  final String conductedBy;
  final DateTime startedAt;
  final List<VisitReason> reasons;
  final DateTime? completedAt;
  final double? latitude;
  final double? longitude;
  final String? notes;
  final SyncState syncState;

  bool get isComplete => completedAt != null;

  Map<String, Object?> toMap() => {
    'id': id,
    'household_id': householdId,
    'conducted_by': conductedBy,
    'started_at': startedAt.toIso8601String(),
    'completed_at': completedAt?.toIso8601String(),
    'reasons': reasons.map((r) => r.name).join(','),
    'latitude': latitude,
    'longitude': longitude,
    'notes': notes,
    'sync_state': syncState.name,
  };

  factory Visit.fromMap(Map<String, Object?> m) => Visit(
    id: m['id'] as String,
    householdId: m['household_id'] as String,
    conductedBy: m['conducted_by'] as String,
    startedAt: DateTime.parse(m['started_at'] as String),
    completedAt: DateTime.tryParse((m['completed_at'] as String?) ?? ''),
    reasons: ((m['reasons'] as String?) ?? '')
        .split(',')
        .where((s) => s.isNotEmpty)
        .map(
          (s) => VisitReason.values.firstWhere(
            (r) => r.name == s,
            orElse: () => VisitReason.routineHomeVisit,
          ),
        )
        .toList(),
    latitude: (m['latitude'] as num?)?.toDouble(),
    longitude: (m['longitude'] as num?)?.toDouble(),
    notes: m['notes'] as String?,
    syncState: SyncState.values.firstWhere(
      (s) => s.name == m['sync_state'],
      orElse: () => SyncState.pending,
    ),
  );

  Visit copyWith({
    DateTime? completedAt,
    List<VisitReason>? reasons,
    String? notes,
    SyncState? syncState,
  }) => Visit(
    id: id,
    householdId: householdId,
    conductedBy: conductedBy,
    startedAt: startedAt,
    reasons: reasons ?? this.reasons,
    completedAt: completedAt ?? this.completedAt,
    latitude: latitude,
    longitude: longitude,
    notes: notes ?? this.notes,
    syncState: syncState ?? this.syncState,
  );
}

/// A single explainable contribution to a decision.
///
/// Every recommendation the app makes is decomposed into these. This is what
/// turns "HIGH RISK" — which a CHO cannot audit or defend — into "MUAC 10.9 cm
/// is below the 11.5 cm SAM cut-off (IMCI, Malnutrition)", which they can.
class ClinicalFinding {
  const ClinicalFinding({
    required this.label,
    required this.detail,
    required this.severity,
    this.protocolSource,
    this.measuredValue,
    this.threshold,
    this.weight = 0,
    this.isDangerSign = false,
  });

  /// Short name, e.g. "Severe acute malnutrition".
  final String label;

  /// The reasoning shown to the CHO, stating the value and the cut-off it
  /// crossed.
  final String detail;

  final TriageLevel severity;

  /// The published guideline this comes from — "IMCI 2019, Malnutrition" or
  /// "WHO ANC 2016". Never present a recommendation without one.
  final String? protocolSource;

  final String? measuredValue;
  final String? threshold;

  /// Points contributed to a composite risk score, where one applies.
  final double weight;

  /// Marks an absolute danger sign — convulsions, unconsciousness, eclampsia,
  /// severe dehydration and the rest of the set that must never be
  /// under-triaged. The synthesizer's never-miss guard-rail keys off this
  /// flag structurally, so a danger sign cannot be missed because of how its
  /// label happens to be worded.
  final bool isDangerSign;

  Map<String, Object?> toJson() => {
    'label': label,
    'detail': detail,
    'severity': severity.name,
    'protocol_source': protocolSource,
    'measured_value': measuredValue,
    'threshold': threshold,
    'weight': weight,
    'is_danger_sign': isDangerSign,
  };

  factory ClinicalFinding.fromJson(Map<String, Object?> j) => ClinicalFinding(
    label: j['label'] as String,
    detail: j['detail'] as String,
    severity: TriageLevel.values.firstWhere((t) => t.name == j['severity']),
    protocolSource: j['protocol_source'] as String?,
    measuredValue: j['measured_value'] as String?,
    threshold: j['threshold'] as String?,
    weight: (j['weight'] as num?)?.toDouble() ?? 0,
    isDangerSign: j['is_danger_sign'] == true,
  );
}

/// An action the CHO or caregiver should take, ordered by urgency.
class RecommendedAction {
  const RecommendedAction({
    required this.instruction,
    required this.urgency,
    this.rationale,
    this.protocolSource,
    this.isReferral = false,
    this.isTreatment = false,
    this.isCounselling = false,
  });

  final String instruction;
  final ReferralUrgency urgency;
  final String? rationale;
  final String? protocolSource;
  final bool isReferral;
  final bool isTreatment;
  final bool isCounselling;

  Map<String, Object?> toJson() => {
    'instruction': instruction,
    'urgency': urgency.name,
    'rationale': rationale,
    'protocol_source': protocolSource,
    'is_referral': isReferral,
    'is_treatment': isTreatment,
    'is_counselling': isCounselling,
  };

  factory RecommendedAction.fromJson(Map<String, Object?> j) => RecommendedAction(
    instruction: j['instruction'] as String,
    urgency: ReferralUrgency.values.firstWhere((u) => u.name == j['urgency']),
    rationale: j['rationale'] as String?,
    protocolSource: j['protocol_source'] as String?,
    isReferral: j['is_referral'] == true,
    isTreatment: j['is_treatment'] == true,
    isCounselling: j['is_counselling'] == true,
  );
}

/// The complete, explainable output of one protocol engine run.
class AssessmentResult {
  const AssessmentResult({
    required this.clientType,
    required this.triage,
    required this.classification,
    required this.findings,
    required this.actions,
    required this.confidence,
    this.protocolSource,
    this.nutritionStatus,
    this.nutritionPathway,
    this.dangerSignsPresent = const [],
    this.missingData = const [],
    this.referralCapabilitiesNeeded = const {},
    this.followUpInDays,
    this.caregiverMessage,
  });

  final ClientType clientType;
  final TriageLevel triage;

  /// The IMCI-style classification, e.g. "SEVERE PNEUMONIA OR VERY SEVERE
  /// DISEASE". Uses the wording a CHO was trained on.
  final String classification;

  final List<ClinicalFinding> findings;
  final List<RecommendedAction> actions;
  final RecommendationConfidence confidence;
  final String? protocolSource;

  final NutritionStatus? nutritionStatus;
  final NutritionPathway? nutritionPathway;
  final List<String> dangerSignsPresent;

  /// Fields that were not measured. Shown openly, because a recommendation
  /// built on gaps must say so.
  final List<String> missingData;

  /// What the receiving facility must be able to do. Prevents referring an
  /// obstructed labour somewhere with no theatre.
  final Set<String> referralCapabilitiesNeeded;

  final int? followUpInDays;

  /// Plain-language version for the caregiver, suitable for audio playback in
  /// Dagbani, Gurene, Dagaare, Sissali or Likpakpaln.
  final String? caregiverMessage;

  bool get needsReferral => triage.requiresReferral;

  List<ClinicalFinding> get urgentFindings =>
      findings.where((f) => f.severity == TriageLevel.urgent).toList();

  Map<String, Object?> toJson() => {
    'client_type': clientType.name,
    'triage': triage.name,
    'classification': classification,
    'findings': findings.map((f) => f.toJson()).toList(),
    'actions': actions.map((a) => a.toJson()).toList(),
    'confidence': confidence.name,
    'protocol_source': protocolSource,
    'nutrition_status': nutritionStatus?.name,
    'nutrition_pathway': nutritionPathway?.name,
    'danger_signs_present': dangerSignsPresent,
    'missing_data': missingData,
    'referral_capabilities_needed': referralCapabilitiesNeeded.toList(),
    'follow_up_in_days': followUpInDays,
    'caregiver_message': caregiverMessage,
  };

  factory AssessmentResult.fromJson(Map<String, Object?> j) => AssessmentResult(
    clientType: ClientType.values.firstWhere((c) => c.name == j['client_type']),
    triage: TriageLevel.values.firstWhere((t) => t.name == j['triage']),
    classification: j['classification'] as String,
    findings: ((j['findings'] as List?) ?? [])
        .map((f) => ClinicalFinding.fromJson(Map<String, Object?>.from(f as Map)))
        .toList(),
    actions: ((j['actions'] as List?) ?? [])
        .map(
          (a) => RecommendedAction.fromJson(Map<String, Object?>.from(a as Map)),
        )
        .toList(),
    confidence: RecommendationConfidence.values.firstWhere(
      (c) => c.name == j['confidence'],
      orElse: () => RecommendationConfidence.moderate,
    ),
    protocolSource: j['protocol_source'] as String?,
    nutritionStatus: j['nutrition_status'] == null
        ? null
        : NutritionStatus.values.firstWhere(
            (n) => n.name == j['nutrition_status'],
          ),
    nutritionPathway: j['nutrition_pathway'] == null
        ? null
        : NutritionPathway.values.firstWhere(
            (n) => n.name == j['nutrition_pathway'],
          ),
    dangerSignsPresent: ((j['danger_signs_present'] as List?) ?? [])
        .map((e) => e as String)
        .toList(),
    missingData: ((j['missing_data'] as List?) ?? [])
        .map((e) => e as String)
        .toList(),
    referralCapabilitiesNeeded: ((j['referral_capabilities_needed'] as List?) ?? [])
        .map((e) => e as String)
        .toSet(),
    followUpInDays: (j['follow_up_in_days'] as num?)?.toInt(),
    caregiverMessage: j['caregiver_message'] as String?,
  );
}

/// A stored assessment: the raw answers plus the engine's verdict, plus any
/// clinical override.
///
/// Keeping the raw inputs alongside the output is what makes the record
/// auditable and lets the risk model be re-run or improved later without
/// losing history.
class Assessment {
  const Assessment({
    required this.id,
    required this.visitId,
    required this.personId,
    required this.clientType,
    required this.performedBy,
    required this.performedAt,
    required this.inputs,
    required this.result,
    this.carePlanJson,
    this.overriddenTriage,
    this.overrideReason,
    this.overrideBy,
    this.syncState = SyncState.pending,
  });

  final String id;
  final String visitId;
  final String personId;
  final ClientType clientType;
  final String performedBy;
  final DateTime performedAt;

  /// Everything the CHO entered, kept verbatim.
  final Map<String, Object?> inputs;

  final AssessmentResult result;

  /// The *synthesized* care plan — the single decision the CHO actually saw
  /// and acted on, produced by the recommendation engine merging every engine
  /// output for this patient. Stored verbatim as JSON so the audit trail shows
  /// the interactions and safety nets that fired, not just each engine's
  /// isolated output. Null for records created before this column existed.
  final String? carePlanJson;

  /// A CHO may overrule the engine. The app records that they did, and why —
  /// both because the human is accountable for care, and because these
  /// overrides are the training signal for improving the model.
  final TriageLevel? overriddenTriage;
  final String? overrideReason;
  final String? overrideBy;

  final SyncState syncState;

  bool get wasOverridden => overriddenTriage != null;

  /// The level that actually governs care — the human's, when they overruled.
  TriageLevel get effectiveTriage => overriddenTriage ?? result.triage;

  /// The two payload columns are stored as JSON text. SQLite cannot bind a
  /// nested map, and keeping the raw answers as one opaque column means the
  /// question set can grow between releases without a migration every time.
  Map<String, Object?> toMap() => {
    'id': id,
    'visit_id': visitId,
    'person_id': personId,
    'client_type': clientType.name,
    'performed_by': performedBy,
    'performed_at': performedAt.toIso8601String(),
    'inputs_json': jsonEncode(inputs),
    'result_json': jsonEncode(result.toJson()),
    'care_plan_json': carePlanJson,
    'overridden_triage': overriddenTriage?.name,
    'override_reason': overrideReason,
    'override_by': overrideBy,
    'sync_state': syncState.name,
  };

  factory Assessment.fromMap(Map<String, Object?> m) => Assessment(
    id: m['id'] as String,
    visitId: m['visit_id'] as String,
    personId: m['person_id'] as String,
    clientType: ClientType.values.firstWhere((c) => c.name == m['client_type']),
    performedBy: m['performed_by'] as String,
    performedAt: DateTime.parse(m['performed_at'] as String),
    inputs: Map<String, Object?>.from(
      jsonDecode((m['inputs_json'] as String?) ?? '{}') as Map,
    ),
    result: AssessmentResult.fromJson(
      Map<String, Object?>.from(jsonDecode(m['result_json'] as String) as Map),
    ),
    carePlanJson: m['care_plan_json'] as String?,
    overriddenTriage: m['overridden_triage'] == null
        ? null
        : TriageLevel.values.firstWhere((t) => t.name == m['overridden_triage']),
    overrideReason: m['override_reason'] as String?,
    overrideBy: m['override_by'] as String?,
    syncState: SyncState.values.firstWhere(
      (s) => s.name == m['sync_state'],
      orElse: () => SyncState.pending,
    ),
  );

  Assessment copyWith({
    String? carePlanJson,
    TriageLevel? overriddenTriage,
    String? overrideReason,
    String? overrideBy,
    SyncState? syncState,
  }) => Assessment(
    id: id,
    visitId: visitId,
    personId: personId,
    clientType: clientType,
    performedBy: performedBy,
    performedAt: performedAt,
    inputs: inputs,
    result: result,
    carePlanJson: carePlanJson ?? this.carePlanJson,
    overriddenTriage: overriddenTriage ?? this.overriddenTriage,
    overrideReason: overrideReason ?? this.overrideReason,
    overrideBy: overrideBy ?? this.overrideBy,
    syncState: syncState ?? this.syncState,
  );
}

/// A referral, with a verifiable arrival loop.
///
/// The referral ID is short and human-speakable so it survives being read down
/// a crackly phone line or written on a paper slip, and it is also encoded as a
/// QR code so a facility with a device can confirm arrival in one scan.
class Referral {
  const Referral({
    required this.id,
    required this.referenceCode,
    required this.personId,
    required this.assessmentId,
    required this.facilityName,
    required this.reason,
    required this.urgency,
    required this.issuedBy,
    required this.issuedAt,
    this.status = ReferralStatus.issued,
    this.statusUpdatedAt,
    this.clinicalSummary,
    this.arrivalConfirmedBy,
    this.outcomeNotes,
    this.escalatedAt,
    this.syncState = SyncState.pending,
  });

  final String id;

  /// Short code, e.g. `CB-7K2M`. Deliberately not the UUID.
  final String referenceCode;

  final String personId;
  final String assessmentId;
  final String facilityName;
  final String reason;
  final ReferralUrgency urgency;
  final String issuedBy;
  final DateTime issuedAt;
  final ReferralStatus status;
  final DateTime? statusUpdatedAt;
  final String? clinicalSummary;
  final String? arrivalConfirmedBy;
  final String? outcomeNotes;

  /// Set when the app auto-escalated an unconfirmed urgent referral.
  final DateTime? escalatedAt;

  final SyncState syncState;

  /// Hours since issue, used by the escalation rule.
  int get hoursOpen => DateTime.now().difference(issuedAt).inHours;

  /// An immediate or same-day referral with no confirmation after 48 hours is
  /// a probable missed case, and the trigger for tracing plus barrier capture.
  bool get needsEscalation =>
      status.isOpen &&
      escalatedAt == null &&
      hoursOpen >= 48 &&
      (urgency == ReferralUrgency.immediate ||
          urgency == ReferralUrgency.sameDay);

  /// Payload embedded in the QR code. Compact by design: it must scan reliably
  /// on a cheap phone in poor light.
  String get qrPayload => 'CAREBRIDGE|$referenceCode|$personId|${urgency.name}';

  Map<String, Object?> toMap() => {
    'id': id,
    'reference_code': referenceCode,
    'person_id': personId,
    'assessment_id': assessmentId,
    'facility_name': facilityName,
    'reason': reason,
    'urgency': urgency.name,
    'issued_by': issuedBy,
    'issued_at': issuedAt.toIso8601String(),
    'status': status.name,
    'status_updated_at': statusUpdatedAt?.toIso8601String(),
    'clinical_summary': clinicalSummary,
    'arrival_confirmed_by': arrivalConfirmedBy,
    'outcome_notes': outcomeNotes,
    'escalated_at': escalatedAt?.toIso8601String(),
    'sync_state': syncState.name,
  };

  factory Referral.fromMap(Map<String, Object?> m) => Referral(
    id: m['id'] as String,
    referenceCode: m['reference_code'] as String,
    personId: m['person_id'] as String,
    assessmentId: m['assessment_id'] as String,
    facilityName: m['facility_name'] as String,
    reason: m['reason'] as String,
    urgency: ReferralUrgency.values.firstWhere((u) => u.name == m['urgency']),
    issuedBy: m['issued_by'] as String,
    issuedAt: DateTime.parse(m['issued_at'] as String),
    status: ReferralStatus.values.firstWhere(
      (s) => s.name == m['status'],
      orElse: () => ReferralStatus.issued,
    ),
    statusUpdatedAt: DateTime.tryParse((m['status_updated_at'] as String?) ?? ''),
    clinicalSummary: m['clinical_summary'] as String?,
    arrivalConfirmedBy: m['arrival_confirmed_by'] as String?,
    outcomeNotes: m['outcome_notes'] as String?,
    escalatedAt: DateTime.tryParse((m['escalated_at'] as String?) ?? ''),
    syncState: SyncState.values.firstWhere(
      (s) => s.name == m['sync_state'],
      orElse: () => SyncState.pending,
    ),
  );

  Referral copyWith({
    ReferralStatus? status,
    String? arrivalConfirmedBy,
    String? outcomeNotes,
    DateTime? escalatedAt,
    SyncState? syncState,
  }) => Referral(
    id: id,
    referenceCode: referenceCode,
    personId: personId,
    assessmentId: assessmentId,
    facilityName: facilityName,
    reason: reason,
    urgency: urgency,
    issuedBy: issuedBy,
    issuedAt: issuedAt,
    status: status ?? this.status,
    statusUpdatedAt: status != null ? DateTime.now() : statusUpdatedAt,
    clinicalSummary: clinicalSummary,
    arrivalConfirmedBy: arrivalConfirmedBy ?? this.arrivalConfirmedBy,
    outcomeNotes: outcomeNotes ?? this.outcomeNotes,
    escalatedAt: escalatedAt ?? this.escalatedAt,
    syncState: syncState ?? this.syncState,
  );
}

/// Why care did not happen. The missing sixth challenge, captured as data.
class BarrierReport {
  const BarrierReport({
    required this.id,
    required this.householdId,
    required this.barriers,
    required this.recordedBy,
    required this.recordedAt,
    this.personId,
    this.referralId,
    this.notes,
    this.resolved = false,
    this.syncState = SyncState.pending,
  });

  final String id;
  final String householdId;
  final List<CareBarrier> barriers;
  final String recordedBy;
  final DateTime recordedAt;
  final String? personId;
  final String? referralId;
  final String? notes;
  final bool resolved;
  final SyncState syncState;

  /// The barrier-specific actions, which is the only reason to collect this.
  List<String> get suggestedActions =>
      barriers.map((b) => b.suggestedAction).toList();

  Map<String, Object?> toMap() => {
    'id': id,
    'household_id': householdId,
    'person_id': personId,
    'referral_id': referralId,
    'barriers': barriers.map((b) => b.name).join(','),
    'recorded_by': recordedBy,
    'recorded_at': recordedAt.toIso8601String(),
    'notes': notes,
    'resolved': resolved ? 1 : 0,
    'sync_state': syncState.name,
  };

  factory BarrierReport.fromMap(Map<String, Object?> m) => BarrierReport(
    id: m['id'] as String,
    householdId: m['household_id'] as String,
    personId: m['person_id'] as String?,
    referralId: m['referral_id'] as String?,
    barriers: ((m['barriers'] as String?) ?? '')
        .split(',')
        .where((s) => s.isNotEmpty)
        .map(
          (s) => CareBarrier.values.firstWhere(
            (b) => b.name == s,
            orElse: () => CareBarrier.didNotThinkItSerious,
          ),
        )
        .toList(),
    recordedBy: m['recorded_by'] as String,
    recordedAt: DateTime.parse(m['recorded_at'] as String),
    notes: m['notes'] as String?,
    resolved: (m['resolved'] as num?) == 1,
    syncState: SyncState.values.firstWhere(
      (s) => s.name == m['sync_state'],
      orElse: () => SyncState.pending,
    ),
  );
}

/// A scheduled future contact: next ANC, PNC day 3, growth monitoring, or a
/// defaulter trace. Generated by the engines so follow-up is never left to
/// memory.
class ScheduledContact {
  const ScheduledContact({
    required this.id,
    required this.personId,
    required this.householdId,
    required this.dueDate,
    required this.purpose,
    required this.createdBy,
    this.completedAt,
    this.assessmentId,
    this.priority = TriageLevel.routine,
    this.syncState = SyncState.pending,
  });

  final String id;
  final String personId;
  final String householdId;
  final DateTime dueDate;
  final String purpose;
  final String createdBy;
  final DateTime? completedAt;
  final String? assessmentId;
  final TriageLevel priority;
  final SyncState syncState;

  bool get isDone => completedAt != null;

  int get daysUntilDue =>
      DateTime(dueDate.year, dueDate.month, dueDate.day)
          .difference(DateTime.now().dateOnly)
          .inDays;

  bool get isOverdue => !isDone && daysUntilDue < 0;
  bool get isDueToday => !isDone && daysUntilDue == 0;

  Map<String, Object?> toMap() => {
    'id': id,
    'person_id': personId,
    'household_id': householdId,
    'due_date': dueDate.toIso8601String(),
    'purpose': purpose,
    'created_by': createdBy,
    'completed_at': completedAt?.toIso8601String(),
    'assessment_id': assessmentId,
    'priority': priority.name,
    'sync_state': syncState.name,
  };

  factory ScheduledContact.fromMap(Map<String, Object?> m) => ScheduledContact(
    id: m['id'] as String,
    personId: m['person_id'] as String,
    householdId: m['household_id'] as String,
    dueDate: DateTime.parse(m['due_date'] as String),
    purpose: m['purpose'] as String,
    createdBy: m['created_by'] as String,
    completedAt: DateTime.tryParse((m['completed_at'] as String?) ?? ''),
    assessmentId: m['assessment_id'] as String?,
    priority: TriageLevel.values.firstWhere(
      (t) => t.name == m['priority'],
      orElse: () => TriageLevel.routine,
    ),
    syncState: SyncState.values.firstWhere(
      (s) => s.name == m['sync_state'],
      orElse: () => SyncState.pending,
    ),
  );
}

extension DateOnly on DateTime {
  DateTime get dateOnly => DateTime(year, month, day);
}

/// One danger-sign check a caregiver ran at home.
///
/// This is the family's own report — what they saw and what the app advised —
/// and it is stored separately from clinical assessments on purpose. It carries
/// no measurements and no diagnosis, and it is **deliberately local-only**: no
/// [SyncState], no outbox row. A mother must be able to check danger signs
/// honestly without the check itself becoming a record that travels; the
/// clinical conversation starts when she tells or shows the health worker.
class HomeCheck {
  const HomeCheck({
    required this.id,
    required this.householdId,
    required this.personId,
    required this.clientType,
    required this.verdict,
    required this.yesSigns,
    required this.unsureSigns,
    required this.checkedBy,
    required this.checkedAt,
  });

  final String id;
  final String householdId;
  final String personId;
  final ClientType clientType;
  final HomeCheckVerdict verdict;

  /// The sign labels the caregiver answered YES to, exactly as worded on
  /// screen, so the FHW reads the family's words rather than coded keys.
  final List<String> yesSigns;
  final List<String> unsureSigns;
  final String checkedBy;
  final DateTime checkedAt;

  Map<String, Object?> toMap() => {
    'id': id,
    'household_id': householdId,
    'person_id': personId,
    'client_type': clientType.name,
    'verdict': verdict.name,
    'yes_signs': yesSigns.join('|'),
    'unsure_signs': unsureSigns.join('|'),
    'checked_by': checkedBy,
    'checked_at': checkedAt.toIso8601String(),
  };

  factory HomeCheck.fromMap(Map<String, Object?> m) => HomeCheck(
    id: m['id'] as String,
    householdId: m['household_id'] as String,
    personId: m['person_id'] as String,
    clientType: ClientType.values.firstWhere(
      (t) => t.name == m['client_type'],
      orElse: () => ClientType.womanOfReproductiveAge,
    ),
    verdict: HomeCheckVerdict.values.firstWhere(
      (v) => v.name == m['verdict'],
      orElse: () => HomeCheckVerdict.caution,
    ),
    yesSigns: _splitSigns(m['yes_signs'] as String?),
    unsureSigns: _splitSigns(m['unsure_signs'] as String?),
    checkedBy: m['checked_by'] as String,
    checkedAt: DateTime.parse(m['checked_at'] as String),
  );

  static List<String> _splitSigns(String? raw) => (raw ?? '')
      .split('|')
      .where((s) => s.isNotEmpty)
      .toList(growable: false);
}
