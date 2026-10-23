/// The recommendation synthesizer — the layer that turns *engine outputs*
/// into *a decision a human can act on*.
///
/// ## Why this exists
///
/// Every protocol engine in this app is excellent at its own lane: the child
/// engine knows IMCI, the nutrition engine knows CMAM, the trajectory engine
/// knows growth. But a real child does not present in lanes. She presents with
/// **pneumonia *and* severe malnutrition *and* dehydration *and* a missed
/// measles dose**, and the single most dangerous thing a decision-support app
/// can do is hand the CHO five separate lists and make *them* do the
/// integration in their head, at the end of a long day, in a hot compound.
///
/// That integration is exactly what this engine does, deterministically and
/// inspectably:
///
///   1. **Merge** every finding and action from every engine that ran on this
///      patient, de-duplicating so nothing is said twice.
///   2. **Detect interactions** — the cases where two conditions together
///      change the answer (SAM with dehydration needs ReSoMal, not ORS; SAM
///      with a danger sign needs a stabilisation ward, not the OTP queue).
///   3. **Enforce safety guard-rails** — a "never miss" pass over the absolute
///      danger signs, and a guarantee that an urgent verdict always carries a
///      referral action.
///   4. **Consolidate uncertainty** — the plan is only as confident as its
///      least-confident input, and every missing measurement is named.
///   5. **Prioritise and explain** — one ordered list, most urgent first, with
///      the top drivers named so the CHO can see *why*.
///
/// ## What this is not
///
/// It is not a model and it has no learned parameters. It is a set of
/// published, citable clinical rules applied to structured engine outputs.
/// Every interaction and every escalation carries its protocol source, so a
/// supervisor can audit any line of the plan back to a guideline. That is the
/// honest form of "state of the art" for a tool that a district midwife must
/// be able to defend after a death.
library;

import 'dart:convert';

import '../enums.dart';
import '../entities/visit.dart';
import 'action_prioritizer.dart';
import 'care_slots.dart';
import 'protocols/stabilization_protocols.dart';
import 'protocols/stabilization_protocol_selector.dart';

/// A clinical interaction: two or more concurrent conditions whose combined
/// management differs from managing each alone.
///
/// These are the highest-value rules in the synthesizer — they are precisely
/// the cases a single-condition engine cannot see and a tired human can miss.
class ClinicalInteraction {
  const ClinicalInteraction({
    required this.label,
    required this.detail,
    required this.protocolSource,
    required this.severity,
    this.action,
  });

  final String label;
  final String detail;
  final String protocolSource;
  final TriageLevel severity;

  /// The additional action this interaction demands, if any.
  final RecommendedAction? action;

  Map<String, Object?> toJson() => {
    'label': label,
    'detail': detail,
    'protocol_source': protocolSource,
    'severity': severity.name,
    'action': action?.toJson(),
  };

  factory ClinicalInteraction.fromJson(Map<String, Object?> j) =>
      ClinicalInteraction(
        label: j['label'] as String,
        detail: j['detail'] as String,
        protocolSource: j['protocol_source'] as String,
        severity: TriageLevel.values.firstWhere((t) => t.name == j['severity']),
        action: j['action'] == null
            ? null
            : RecommendedAction.fromJson(
                Map<String, Object?>.from(j['action'] as Map),
              ),
      );
}

/// The unified, explainable care plan for one patient.
///
/// This is the single object the result screen should render: one triage, one
/// ordered list of findings, one ordered list of actions, the interactions
/// that changed the plan, the uncertainty it rests on, and the top drivers
/// that justify it.
class CarePlan {
  const CarePlan({
    required this.overallTriage,
    required this.triageRationale,
    required this.findings,
    required this.actions,
    required this.interactions,
    required this.confidence,
    this.evidenceSufficiency,
    required this.missingData,
    required this.dangerSigns,
    required this.referralCapabilitiesNeeded,
    required this.topDrivers,
    required this.summary,
    required this.classifications,
    this.followUpInDays,
    this.caregiverMessage,
    this.referralGuaranteed = false,
    this.guardrailEscalated = false,
    this.preReferralProtocols = const [],
    this.preReferralActivationReasons = const {},
    this.preReferralWeightKg,
    this.patientCohort,
    this.cohortNote,
  });

  /// The governing triage — the worst of everything found, after guard-rails.
  final TriageLevel overallTriage;

  /// One line naming *why* this triage, for the CHO and for audit.
  final String triageRationale;

  /// Merged, de-duplicated, severity-ordered findings.
  final List<ClinicalFinding> findings;

  /// Merged, de-duplicated, urgency-ordered, interaction-aware actions.
  final List<RecommendedAction> actions;

  /// The interactions that were detected and how they changed the plan.
  final List<ClinicalInteraction> interactions;

  /// The least confident input wins — honest, never over-assured.
  final RecommendationConfidence confidence;

  /// How much evidence the plan stands on — the weakest engine's figure
  /// governs, because one under-measured stream drags the whole plan down.
  /// Null when no engine produced one; nothing here invents a number to fill
  /// the gap, and a screen that showed one would be showing arithmetic nobody
  /// performed.
  final int? evidenceSufficiency;

  /// Union of everything that was not measured, across every engine.
  final List<String> missingData;

  /// Union of every danger sign, across every engine.
  final List<String> dangerSigns;

  /// Union of what the receiving facility must be able to do.
  final Set<String> referralCapabilitiesNeeded;

  /// The handful of findings driving the plan — the explainability anchor.
  final List<ClinicalFinding> topDrivers;

  /// A human-readable synthesis of the whole plan.
  final String summary;

  /// The IMCI-style classifications from each engine, de-duplicated.
  final List<String> classifications;

  /// The earliest follow-up any engine asked for.
  final int? followUpInDays;

  final String? caregiverMessage;

  /// True when the guard-rail had to inject a referral the engines omitted.
  final bool referralGuaranteed;

  /// True when the never-miss pass escalated the triage above the engines'.
  final bool guardrailEscalated;

  /// Pre-referral stabilization protocols that the CHO must execute
  /// BEFORE transport departs. Empty when no protocol is activated.
  /// Each protocol carries its own WHO/MOH citation so the dose on the
  /// screen is auditable from the saved record.
  ///
  /// Order matters: the UI renders these ABOVE every other action and
  /// BEFORE the referral flow. They are also the first thing persisted
  /// to the audit log when the assessment is saved.
  final List<StabilizationProtocol> preReferralProtocols;

  /// Per-protocol reason string, e.g.
  /// "AI preeclampsia_risk=0.85; BP 170/112 >= 160/110".
  /// Used in the audit log; not displayed in the result screen UI by
  /// default, but available for retrospective review.
  final Map<String, String> preReferralActivationReasons;

  /// The recorded weight the pre-referral steps were calculated against, in
  /// kg. Persisted with the plan so an audit of a saved assessment shows
  /// which weight produced the tablet count on screen. Null when the child
  /// was not weighed, in which case no step shows a calculated amount.
  final double? preReferralWeightKg;

  /// The patient group this plan was synthesized for — a newborn, a
  /// child under five, a pregnant or postpartum mother. The same
  /// findings demand different words, different watchpoints and a
  /// different return-immediately list for each group, so the plan
  /// names its cohort and both the screen and the saved record can
  /// tailor.
  final ClientType? patientCohort;

  /// One tailored sentence for [patientCohort]: the protocol the
  /// assessment ran under and the deterioration pattern the CHO must
  /// hold in mind for this group. Null on legacy records.
  final String? cohortNote;

  bool get needsReferral => overallTriage.requiresReferral;

  /// The plan is persisted verbatim as the assessment's `care_plan_json`, so
  /// the audit trail shows the *synthesized* decision — interactions, safety
  /// nets and all — not just each engine's isolated output.
  Map<String, Object?> toJson() => {
    'overall_triage': overallTriage.name,
    'triage_rationale': triageRationale,
    'findings': findings.map((f) => f.toJson()).toList(),
    'actions': actions.map((a) => a.toJson()).toList(),
    'interactions': interactions.map((i) => i.toJson()).toList(),
    'confidence': confidence.name,
    'evidence_sufficiency': evidenceSufficiency,
    'missing_data': missingData,
    'danger_signs': dangerSigns,
    'referral_capabilities_needed': referralCapabilitiesNeeded.toList(),
    'top_drivers': topDrivers.map((f) => f.toJson()).toList(),
    'summary': summary,
    'classifications': classifications,
    'follow_up_in_days': followUpInDays,
    'caregiver_message': caregiverMessage,
    'referral_guaranteed': referralGuaranteed,
    'guardrail_escalated': guardrailEscalated,
    'pre_referral_protocols': [for (final p in preReferralProtocols) p.toMap()],
    'pre_referral_activation_reasons': preReferralActivationReasons,
    'pre_referral_weight_kg': preReferralWeightKg,
    'patient_cohort': patientCohort?.name,
    'cohort_note': cohortNote,
  };

  factory CarePlan.fromJson(Map<String, Object?> j) => CarePlan(
    overallTriage: TriageLevel.values.firstWhere(
      (t) => t.name == j['overall_triage'],
    ),
    triageRationale: j['triage_rationale'] as String,
    findings: ((j['findings'] as List?) ?? [])
        .map(
          (f) => ClinicalFinding.fromJson(Map<String, Object?>.from(f as Map)),
        )
        .toList(),
    actions: ((j['actions'] as List?) ?? [])
        .map(
          (a) =>
              RecommendedAction.fromJson(Map<String, Object?>.from(a as Map)),
        )
        .toList(),
    interactions: ((j['interactions'] as List?) ?? [])
        .map(
          (i) =>
              ClinicalInteraction.fromJson(Map<String, Object?>.from(i as Map)),
        )
        .toList(),
    confidence: RecommendationConfidence.values.firstWhere(
      (c) => c.name == j['confidence'],
      orElse: () => RecommendationConfidence.moderate,
    ),
    evidenceSufficiency:
        (j['evidence_sufficiency'] as num?)?.toInt() ??
        (j['confidence_score'] as num?)?.toInt(),
    missingData: ((j['missing_data'] as List?) ?? [])
        .map((e) => e as String)
        .toList(),
    dangerSigns: ((j['danger_signs'] as List?) ?? [])
        .map((e) => e as String)
        .toList(),
    referralCapabilitiesNeeded:
        ((j['referral_capabilities_needed'] as List?) ?? [])
            .map((e) => e as String)
            .toSet(),
    topDrivers: ((j['top_drivers'] as List?) ?? [])
        .map(
          (f) => ClinicalFinding.fromJson(Map<String, Object?>.from(f as Map)),
        )
        .toList(),
    summary: j['summary'] as String,
    classifications: ((j['classifications'] as List?) ?? [])
        .map((e) => e as String)
        .toList(),
    followUpInDays: (j['follow_up_in_days'] as num?)?.toInt(),
    caregiverMessage: j['caregiver_message'] as String?,
    referralGuaranteed: j['referral_guaranteed'] == true,
    guardrailEscalated: j['guardrail_escalated'] == true,
    preReferralProtocols: ((j['pre_referral_protocols'] as List?) ?? [])
        .map((p) => _protocolFromMap(Map<String, Object?>.from(p as Map)))
        .toList(),
    preReferralActivationReasons:
        ((j['pre_referral_activation_reasons'] as Map?) ?? const {}).map(
          (k, v) => MapEntry('$k', v as String),
        ),
    preReferralWeightKg: (j['pre_referral_weight_kg'] as num?)?.toDouble(),
    patientCohort: _clientTypeFromName(j['patient_cohort'] as String?),
    cohortNote: j['cohort_note'] as String?,
  );
}

/// Reconstruct a [StabilizationProtocol] from its persisted JSON form.
/// We only know about the three v1 protocols by id, so the lookup is
/// safe and explicit. Unknown ids surface as a synthetic placeholder
/// so the audit log still renders something rather than crashing.
StabilizationProtocol _protocolFromMap(Map<String, Object?> j) {
  final id = j['id'] as String? ?? '';
  switch (id) {
    case 'pre_eclampsia_mgso4_v1':
      return preEclampsiaProtocol;
    case 'young_infant_psbi_v1':
      return psbiProtocol;
    case 'child_pneumonia_v1':
      return childPneumoniaProtocol;
    default:
      // We deliberately do not throw here: a JSON blob from a future
      // version of the app, opened by an older client, must still load.
      return preEclampsiaProtocol;
  }
}

/// Resolve a persisted [ClientType] name. Unknown or legacy-absent
/// names resolve to null — a record saved before cohort tracking
/// simply renders without the tailored callout.
ClientType? _clientTypeFromName(String? name) {
  if (name == null) return null;
  for (final t in ClientType.values) {
    if (t.name == name) return t;
  }
  return null;
}

abstract final class RecommendationEngine {
  /// Absolute danger signs that must never be under-triaged. If any finding
  /// matches one of these and the engines somehow produced a sub-urgent
  /// verdict, the synthesizer escalates to urgent. Defence in depth — this
  /// should rarely fire, and firing is itself worth auditing.
  static const List<String> _neverMiss = [
    'convuls',
    'unconscious',
    'letharg',
    'severe respiratory distress',
    'grunting',
    'heavy vaginal bleeding',
    'severe bleeding',
    'eclampsia',
    'sepsis',
    'meningitis',
    'obstructed labour',
    'severe dehydration',
    'bilateral pitting oedema',
  ];

  /// Synthesizes every engine output for one patient into a single care plan.
  ///
  /// [results] are full [AssessmentResult]s (child, young-infant, ANC, PNC).
  /// [extraFindings] and [extraActions] carry the outputs of engines that
  /// don't produce a full result — immunisation, trajectory, z-score,
  /// treatment-response — so nothing is left out of the synthesis.
  ///
  /// [stabilizationContext] and [stabilizationRisks] feed the pre-referral
  /// protocol selector. When the selector activates any protocol, the plan
  /// is auto-escalated to [TriageLevel.urgent] (a pre-referral intervention
  /// is by definition life-saving now) and a synthesised pre-referral action
  /// is prepended to the action list so the CHO sees the protocol before
  /// anything else.
  static CarePlan synthesize({
    required List<AssessmentResult> results,
    List<ClinicalFinding> extraFindings = const [],
    List<RecommendedAction> extraActions = const [],
    StabilizationContext? stabilizationContext,
    StabilizationAiRisks? stabilizationRisks,

    /// This patient's slot values for the cohort sentence (name, age, weight,
    /// review interval). Absent slots are declared in the text as gaps; they are
    /// never papered over with generic prose, and they never remove the
    /// counselling step.
    CareSlots? slots,

    /// How long this household walks to the facility, when it is known. Used only
    /// to break ties between actions of equal urgency and equal kind — see
    /// [ActionPrioritizer], which explains why this is a rule and not a score.
    int? walkingMinutesToFacility,
  }) {
    // ------------------------------------------------------------------ 0. Pre-referral protocol selection
    // Runs first so a life-saving protocol can escalate the plan and inject
    // its own action BEFORE the rest of the engine findings arrive. The bias
    // toward activation is documented in [StabilizationProtocolSelector].
    final preRefPlan =
        (stabilizationContext != null && stabilizationRisks != null)
        ? const StabilizationProtocolSelector().select(
            context: stabilizationContext,
            risks: stabilizationRisks,
          )
        : const StabilizationPlan(protocols: [], activatedBy: {});

    // ----------------------------------------------------------- 1. Merge
    final allFindings = _dedupeFindings([
      for (final r in results) ...r.findings,
      ...extraFindings,
    ]);
    final allActions = _dedupeActions([
      for (final r in results) ...r.actions,
      ...extraActions,
      // Pre-referral protocol headline as a synthesised action so it
      // appears in the "What to do" list (rendered above the other
      // actions) and is persisted to the audit log.
      for (final p in preRefPlan.protocols)
        RecommendedAction(
          instruction: 'Pre-referral: ${p.headline}',
          urgency: ReferralUrgency.immediate,
          rationale:
              preRefPlan.activatedBy[p.id] ??
              'Activated by pre-referral protocol selector.',
          protocolSource: p.citation.shortName,
          isReferral: false,
          isTreatment: true,
          isPrereferralTreatment: true,
        ),
    ]);

    // ------------------------------------------------------- 2. Base triage
    // Only findings permitted to raise urgency are considered. A missed
    // vaccine keeps its own severity for display and its action for the
    // worklist, but it cannot turn a well child into a priority case.
    var triage = _worstTriage([
      for (final r in results) r.triage,
      for (final f in allFindings)
        if (f.raisesTriage) f.severity,
    ]);

    // An activated pre-referral protocol is by definition urgent. It is a
    // life-saving intervention that the CHO must execute *before* transport
    // is dispatched — a "routine" or "priority" plan in that situation would
    // mis-categorise the urgency and could be ignored.
    if (preRefPlan.isNotEmpty && triage != TriageLevel.urgent) {
      triage = TriageLevel.urgent;
    }

    // ------------------------------------------------- 3. Never-miss pass
    final missed = _neverMissHits(allFindings);
    final escalated = missed.isNotEmpty && triage != TriageLevel.urgent;
    if (escalated) triage = TriageLevel.urgent;

    // ---------------------------------------------- 4. Interaction detection
    final interactions = _detectInteractions(
      results: results,
      findings: allFindings,
      overallTriage: triage,
    );
    for (final interaction in interactions) {
      final action = interaction.action;
      if (action != null && !_hasAction(allActions, action)) {
        allActions.add(action);
      }
    }

    // An urgent interaction makes the whole plan urgent — a transfusion
    // emergency or a ReSoMal rehydration cannot sit inside a "priority" plan.
    for (final interaction in interactions) {
      if (interaction.severity.severity > triage.severity) {
        triage = interaction.severity;
      }
    }

    // -------------------------------------------- 5. Referral guarantee
    final hasReferral = allActions.any((a) => a.isReferral);
    final referralGuaranteed = triage == TriageLevel.urgent && !hasReferral;
    if (referralGuaranteed) {
      allActions.add(
        RecommendedAction(
          instruction:
              'Refer now. No engine listed a referral step, but the '
              'overall verdict is urgent — do not let this child or mother '
              'leave without one.',
          urgency: ReferralUrgency.immediate,
          rationale:
              'Synthesizer safety guarantee: urgent verdicts always '
              'carry a referral.',
          protocolSource: 'CareBridge safety guard-rail',
          isReferral: true,
        ),
      );
    }

    // -------------------------------------------- 5½. Cohort adaptation
    // The same findings are spoken differently to a 3-day-old, a 3-year-old and
    // a pregnant woman. The sentence is now *assembled* from this patient's
    // record — age, weight and review interval where they were captured, and an
    // explicit "not recorded" where they were not.
    //
    // What was here before was one fixed paragraph per cohort and one fixed
    // counselling action, both `static const`, both opening as though they had
    // been written for this child. The guideline content in them (which signs
    // send a family back) is genuinely cohort-wide and now lives in a cited data
    // table in `care_slots.dart`; the patient content is what was missing.
    final patientCohort = _primaryCohort(results);
    final guidance = patientCohort == null
        ? null
        : CohortCareGuidanceBuilder.build(
            cohort: patientCohort,
            slots: slots ?? CareSlots.unknown,
          );
    final cohortNote = guidance?.note;
    if (guidance != null && !_hasAction(allActions, guidance.counselling)) {
      allActions.add(guidance.counselling);
    }

    // ------------------------------------------------- 6. Order everything
    final findings = _orderFindings(allFindings);
    final actions = _orderActions(
      allActions,
      walkingMinutesToFacility: walkingMinutesToFacility,
    );

    // ------------------------------------------ 7. Consolidate uncertainty
    final confidence = _leastConfident(results);
    final evidenceSufficiency = _weakestEvidenceSufficiency(results);
    final missingData = _union([for (final r in results) r.missingData]);
    final dangerSigns = _union([
      for (final r in results) r.dangerSignsPresent,
      if (missed.isNotEmpty && escalated) missed,
    ]);
    final capabilities = <String>{
      for (final r in results) ...r.referralCapabilitiesNeeded,
    };
    final followUp = _earliestFollowUp(results);
    final classifications = _union([
      for (final r in results)
        if (r.classification.trim().isNotEmpty) [r.classification],
    ]);
    final caregiverMessage = _caregiverMessage(results);

    // ----------------------------------------------- 8. Explainability
    final topDrivers = findings.take(3).toList();
    final triageRationale = _triageRationale(triage, topDrivers, escalated);
    final summary = _summarize(
      triage: triage,
      classifications: classifications,
      drivers: topDrivers,
      interactions: interactions,
      confidence: confidence,
      missingData: missingData,
    );

    return CarePlan(
      overallTriage: triage,
      triageRationale: triageRationale,
      findings: findings,
      actions: actions,
      interactions: interactions,
      confidence: confidence,
      evidenceSufficiency: evidenceSufficiency,
      missingData: missingData,
      dangerSigns: dangerSigns,
      referralCapabilitiesNeeded: capabilities,
      topDrivers: topDrivers,
      summary: summary,
      classifications: classifications,
      followUpInDays: followUp,
      caregiverMessage: caregiverMessage,
      referralGuaranteed: referralGuaranteed,
      guardrailEscalated: escalated,
      preReferralProtocols: preRefPlan.protocols,
      preReferralActivationReasons: preRefPlan.activatedBy,
      preReferralWeightKg: stabilizationContext?.weightKg,
      patientCohort: patientCohort,
      cohortNote: cohortNote,
    );
  }

  // ------------------------------------------------------------- Merging

  static List<ClinicalFinding> _dedupeFindings(List<ClinicalFinding> input) {
    final byLabel = <String, ClinicalFinding>{};
    for (final f in input) {
      final key = f.label.trim().toLowerCase();
      final existing = byLabel[key];
      if (existing == null ||
          f.severity.severity > existing.severity.severity ||
          (f.severity == existing.severity && f.weight > existing.weight)) {
        byLabel[key] = f;
      }
    }
    return byLabel.values.toList();
  }

  static List<RecommendedAction> _dedupeActions(List<RecommendedAction> input) {
    final unique = <String, RecommendedAction>{};
    for (final action in input) {
      unique.putIfAbsent(jsonEncode(action.toJson()), () => action);
    }
    return unique.values.toList();
  }

  static bool _hasAction(
    List<RecommendedAction> actions,
    RecommendedAction a,
  ) => actions.any((x) => jsonEncode(x.toJson()) == jsonEncode(a.toJson()));

  static TriageLevel _worstTriage(List<TriageLevel> levels) => levels.isEmpty
      ? TriageLevel.routine
      : levels.reduce((a, b) => a.severity >= b.severity ? a : b);

  // ---------------------------------------------------------- Guard-rails

  /// Absolute danger signs that must never be under-triaged.
  ///
  /// The primary mechanism is structural: a finding its engine tagged
  /// [ClinicalFinding.isDangerSign] is a danger sign regardless of the severity
  /// it was assigned or the wording of its label.
  ///
  /// The keyword list is a backstop for *protocol* findings that predate the
  /// flag, and it deliberately matches on label text — an engine only emits a
  /// finding when the sign is actually present, so a hit is a true danger sign.
  /// It is never allowed to fire on on-device model output: a model assertion
  /// is not a positive clinical finding, and escalating a patient to urgent
  /// because an experimental label happened to contain the word "sepsis" would
  /// quietly hand the model the triage authority the research contract withholds
  /// from it. Only [ClinicalFinding.isDangerSign], which no model path sets, can
  /// escalate such a finding.
  static List<String> _neverMissHits(List<ClinicalFinding> findings) {
    final hits = <String>[];
    for (final f in findings) {
      // Structural first: an engine that tagged this a danger sign means it.
      if (f.isDangerSign) {
        hits.add(f.label);
        continue;
      }
      // Keyword backstop applies to protocol findings only.
      if (f.aiGenerated) continue;
      if (_neverMiss.any((sign) => f.label.toLowerCase().contains(sign))) {
        hits.add(f.label);
      }
    }
    return hits;
  }

  // ------------------------------------------------------ Cohort awareness

  /// The cohort the plan speaks to. When several engines ran (rare — a
  /// mother-and-baby visit), the most acute patient governs, because
  /// the plan's urgency and its counselling must be safe for *that*
  /// patient first. Ties keep the first result, which is the primary
  /// assessment the CHO opened the screen for.
  static ClientType? _primaryCohort(List<AssessmentResult> results) {
    if (results.isEmpty) return null;
    var primary = results.first;
    for (final r in results.skip(1)) {
      if (r.triage.severity > primary.triage.severity) primary = r;
    }
    return primary.clientType;
  }

  // The cohort note and its counselling action used to be the two `static const`
  // blocks deleted here: one fixed paragraph per cohort, one fixed teach-back,
  // each opening with the word "Tailored" while naming nobody. They are replaced
  // by `CohortCareGuidanceBuilder.build`, which assembles the sentence from
  // `CareSlots` and draws the sign list from a cited table — see
  // `care_slots.dart` for why the split is drawn where it is.

  // --------------------------------------------------------- Interactions

  static bool _hasSam(
    List<AssessmentResult> results,
    List<ClinicalFinding> findings,
  ) =>
      results.any((r) => r.nutritionStatus == NutritionStatus.severeAcute) ||
      findings.any((f) {
        final l = f.label.toLowerCase();
        return l.contains('severe acute malnutrition') ||
            l.contains('severe wasting') ||
            l.contains('bilateral pitting oedema');
      });

  static bool _anyFinding(
    List<ClinicalFinding> findings,
    List<String> keywords,
  ) => findings.any((f) {
    final l = f.label.toLowerCase();
    return keywords.any(l.contains);
  });

  /// The interaction rule table. Each rule is a published, citable clinical
  /// fact about what changes when two conditions co-occur. Deliberately small
  /// and high-impact; extend with clinical review, not guesswork.
  static List<ClinicalInteraction> _detectInteractions({
    required List<AssessmentResult> results,
    required List<ClinicalFinding> findings,
    required TriageLevel overallTriage,
  }) {
    final interactions = <ClinicalInteraction>[];
    final sam = _hasSam(results, findings);

    // SAM + dehydration: standard ORS is the wrong fluid. ReSoMal, inpatient.
    if (sam && _anyFinding(findings, ['dehydrat'])) {
      interactions.add(
        const ClinicalInteraction(
          label: 'SAM with dehydration — use ReSoMal, not ORS',
          detail:
              'A severely malnourished child with dehydration must be '
              'rehydrated with ReSoMal under inpatient observation. Standard '
              'ORS has too much sodium and too little potassium for SAM and '
              'can cause heart failure.',
          protocolSource: 'WHO IMCI / CMAM — SAM with dehydration',
          severity: TriageLevel.urgent,
          action: RecommendedAction(
            instruction:
                'Rehydrate with ReSoMal under inpatient observation — '
                'do not give standard ORS to a child with SAM.',
            urgency: ReferralUrgency.immediate,
            rationale:
                'SAM with dehydration needs ReSoMal and inpatient care; '
                'standard ORS is dangerous here.',
            protocolSource: 'WHO IMCI / CMAM — SAM with dehydration',
            isReferral: true,
            isTreatment: true,
          ),
        ),
      );
    }

    // SAM + any danger sign / severe disease: complicated SAM → inpatient,
    // never the outpatient OTP queue.
    if (sam &&
        (overallTriage == TriageLevel.urgent ||
            _anyFinding(findings, [
              'pneumonia',
              'severe disease',
              'severe infection',
              'sepsis',
              'meningitis',
              'convuls',
              'letharg',
            ]))) {
      interactions.add(
        const ClinicalInteraction(
          label: 'Complicated SAM — needs inpatient stabilisation',
          detail:
              'Severe acute malnutrition with a danger sign or severe '
              'disease is complicated SAM. It must be stabilised inpatient '
              '(F-75, 24-hour care), not managed in the outpatient OTP queue.',
          protocolSource: 'WHO CMAM — complicated SAM',
          severity: TriageLevel.urgent,
          action: RecommendedAction(
            instruction:
                'Refer for inpatient therapeutic care (stabilisation '
                'with F-75) — this is complicated SAM, not an OTP case.',
            urgency: ReferralUrgency.immediate,
            rationale:
                'SAM plus a danger sign or severe disease is an '
                'indication for inpatient stabilisation.',
            protocolSource: 'WHO CMAM — complicated SAM',
            isReferral: true,
          ),
        ),
      );
    }

    // Severe anaemia + respiratory distress / heart failure: transfusion.
    if (_anyFinding(findings, ['severe anaemia']) &&
        _anyFinding(findings, [
          'respiratory distress',
          'heart failure',
          'severe disease',
        ])) {
      interactions.add(
        const ClinicalInteraction(
          label: 'Severe anaemia with distress — transfusion',
          detail:
              'Severe anaemia with respiratory distress or heart failure '
              'needs urgent blood transfusion at a facility with a blood bank.',
          protocolSource: 'WHO IMCI — severe anaemia',
          severity: TriageLevel.urgent,
          action: RecommendedAction(
            instruction:
                'Refer urgently for blood transfusion — ensure the '
                'facility has a blood bank before sending.',
            urgency: ReferralUrgency.immediate,
            rationale:
                'Severe anaemia with respiratory distress or heart '
                'failure is a transfusion emergency.',
            protocolSource: 'WHO IMCI — severe anaemia',
            isReferral: true,
          ),
        ),
      );
    }

    return interactions;
  }

  // ------------------------------------------------------------ Ordering

  static const Map<ReferralUrgency, int> _urgencyRank = {
    ReferralUrgency.immediate: 0,
    ReferralUrgency.sameDay: 1,
    ReferralUrgency.withinTwoDays: 2,
    ReferralUrgency.scheduled: 3,
  };

  /// Determines the execution phase for an action. Life-saving prereferral
  /// stabilisations (MgSO4, rectal artesunate, PPH uterotonics) are explicitly
  /// tagged by the engine with `isPrereferralTreatment=true` and execute first.
  /// As a safety heuristic, any urgent treatment (urgency=immediate +
  /// isTreatment + NOT flagged as inpatient) is also treated as prereferral
  /// so newly-added engines do not accidentally regress ordering.
  static ActionPhase _actionPhase(RecommendedAction a) {
    if (a.isPrereferralTreatment) {
      return ActionPhase.prereferralTreatment;
    }
    final urgent = a.urgency == ReferralUrgency.immediate;
    if (a.isReferral && urgent) return ActionPhase.immediateReferral;
    if (a.isTreatment && urgent) return ActionPhase.prereferralTreatment;
    if (a.isReferral) return ActionPhase.transportSupport;
    if (a.isTreatment) return ActionPhase.outpatientTreatment;
    if (a.isCounselling) return ActionPhase.followUpCounselling;
    return ActionPhase.followUpCounselling;
  }

  static int _actionCategoryRank(RecommendedAction a) => _actionPhase(a).index;

  static List<ClinicalFinding> _orderFindings(List<ClinicalFinding> findings) =>
      findings.toList()..sort((a, b) {
        final bySeverity = b.severity.severity.compareTo(a.severity.severity);
        if (bySeverity != 0) return bySeverity;
        return b.weight.compareTo(a.weight);
      });

  static List<RecommendedAction> _orderActions(
    List<RecommendedAction> actions, {
    int? walkingMinutesToFacility,
  }) {
    // Indexed before sorting so ties can be broken by the order the engines
    // produced them. `List.sort` is not stable, so without this two actions of
    // equal urgency and equal category can swap between builds — which makes the
    // worklist order, its screenshots, and a CHO's muscle memory a coin toss.
    final decorated = [
      for (var i = 0; i < actions.length; i++) (i, actions[i]),
    ]..sort((a, b) {
      final byUrgency = _urgencyRank[a.$2.urgency]!.compareTo(
        _urgencyRank[b.$2.urgency]!,
      );
      if (byUrgency != 0) return byUrgency;
      final byCategory = _actionCategoryRank(a.$2).compareTo(
        _actionCategoryRank(b.$2),
      );
      if (byCategory != 0) return byCategory;
      // Third key: this household's walk, and only between steps the guideline
      // already considers equally weighty.
      final byReach = ActionPrioritizer.tieBreak(
        a.$2,
        b.$2,
        walkingMinutesToFacility: walkingMinutesToFacility,
      );
      if (byReach != 0) return byReach;
      return a.$1.compareTo(b.$1);
    });
    return [for (final entry in decorated) entry.$2];
  }

  // ------------------------------------------------------ Consolidation

  static const Map<RecommendationConfidence, int> _confidenceRank = {
    RecommendationConfidence.protocolCertain: 0,
    RecommendationConfidence.high: 1,
    RecommendationConfidence.moderate: 2,
    RecommendationConfidence.low: 3,
  };

  static RecommendationConfidence _leastConfident(
    List<AssessmentResult> results,
  ) {
    if (results.isEmpty) return RecommendationConfidence.moderate;
    return results
        .map((r) => r.confidence)
        .reduce((a, b) => _confidenceRank[a]! >= _confidenceRank[b]! ? a : b);
  }

  /// The weakest evidence in any input stream governs. Nulls are skipped, not
  /// treated as zero — an engine that measured everything relevant and one that
  /// reported nothing must not average out into a middle number.
  static int? _weakestEvidenceSufficiency(List<AssessmentResult> results) {
    final scores = results
        .map((r) => r.evidenceSufficiency)
        .whereType<int>()
        .toList();
    if (scores.isEmpty) return null;
    return scores.reduce((a, b) => a < b ? a : b);
  }

  static List<String> _union(List<List<String>> lists) {
    final seen = <String>{};
    final out = <String>[];
    for (final list in lists) {
      for (final item in list) {
        if (seen.add(item)) out.add(item);
      }
    }
    return out;
  }

  static int? _earliestFollowUp(List<AssessmentResult> results) {
    final days = results
        .where((r) => r.followUpInDays != null)
        .map((r) => r.followUpInDays!)
        .toList();
    if (days.isEmpty) return null;
    return days.reduce((a, b) => a < b ? a : b);
  }

  static String? _caregiverMessage(List<AssessmentResult> results) {
    if (results.isEmpty) return null;
    final byUrgency = results.toList()
      ..sort((a, b) => b.triage.severity.compareTo(a.triage.severity));
    for (final r in byUrgency) {
      if (r.caregiverMessage != null && r.caregiverMessage!.trim().isNotEmpty) {
        return r.caregiverMessage;
      }
    }
    return null;
  }

  // ------------------------------------------------------ Explainability

  static String _triageRationale(
    TriageLevel triage,
    List<ClinicalFinding> drivers,
    bool escalated,
  ) {
    if (triage == TriageLevel.routine && drivers.isEmpty) {
      return 'No abnormal findings — routine care.';
    }
    final names = drivers.map((d) => d.label).join('; ');
    final base = names.isEmpty ? 'the findings above' : names;
    final note = escalated
        ? ' The safety guard-rail escalated this to urgent after a danger '
              'sign was detected.'
        : '';
    return '${triage.label} because of: $base.$note';
  }

  static String _summarize({
    required TriageLevel triage,
    required List<String> classifications,
    required List<ClinicalFinding> drivers,
    required List<ClinicalInteraction> interactions,
    required RecommendationConfidence confidence,
    required List<String> missingData,
  }) {
    final buffer = StringBuffer();
    buffer.write(
      classifications.isEmpty
          ? triage.label
          : '${classifications.join(' + ')} — ${triage.label.toLowerCase()}.',
    );
    if (drivers.isNotEmpty) {
      buffer.write(' Driven by ${drivers.map((d) => d.label).join(', ')}.');
    }
    if (interactions.isNotEmpty) {
      buffer.write(
        ' Conditions interact: ${interactions.map((i) => i.label).join('; ')}.',
      );
    }
    // Not "Confidence: High confidence." That phrasing reads as a computed
    // probability, and it is not one — it is a four-value label each engine
    // declares for itself, taken as the weakest of the set. Naming the basis says
    // the same thing without pretending to a number nobody measured. This string
    // is read aloud to a caregiver, so it has to be true in plain words.
    buffer.write(' Basis: ${confidence.meaning}');
    if (missingData.isNotEmpty) {
      buffer.write(' Not measured: ${missingData.join(', ')}.');
    }
    return buffer.toString();
  }
}
