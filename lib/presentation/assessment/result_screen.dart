/// The verdict screen: what the protocol found, what to do about it, and the
/// three things that must not be lost on the way out — nutrition, immunisation
/// and the referral/follow-up loop.
///
/// Everything here is *explainable by construction*. Findings carry the value
/// and the cut-off they crossed and the guideline they come from; the nutrition
/// plan states its pathway and its seasonal reasoning; the referral names the
/// facility and the capability it needs. A CHO who cannot see the arithmetic
/// cannot defend the decision, and a decision they cannot defend gets ignored.
///
/// Saving is one repository call, so the assessment, its referral and its
/// follow-up schedule land together or not at all — and the repository re-runs
/// the permission check on each, because this screen is UI and UI is not a
/// security boundary.
library;

import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/reference/facilities.dart';
import '../../data/reference/local_foods.dart';
import '../../data/repositories/care_repository.dart';
import '../../domain/engines/growth_zscore_engine.dart';
import '../../domain/engines/immunisation_engine.dart';
import '../../domain/engines/measurement_safety_engine.dart';
import '../../domain/engines/nutrition_engine.dart';
import '../../domain/engines/recommendation_engine.dart';
import '../../domain/engines/treatment_response_engine.dart';
import '../../domain/entities/core.dart';
import '../../domain/entities/visit.dart';
import '../../domain/enums.dart';
import '../shared/app_image.dart';
import '../shared/ui.dart';
import 'form_kit.dart';
import 'types.dart';

const _uuid = Uuid();

class AssessmentResultScreen extends ConsumerStatefulWidget {
  const AssessmentResultScreen({
    super.key,
    required this.input,
    required this.draft,
    required this.visitId,
    this.priorGrowth = const [],
  });

  final AssessmentContext input;
  final AssessmentDraft draft;
  final String visitId;

  /// Growth measurements recorded before this visit, oldest first. The
  /// comparison point for treatment-response monitoring (weight-gain rate) of
  /// a child on therapeutic feeding. Loaded before navigation so the verdict
  /// that seeds the referral toggle already knows the trend — a child losing
  /// weight on treatment must not wait on an async load to be escalated.
  final List<GrowthMeasurement> priorGrowth;

  @override
  ConsumerState<AssessmentResultScreen> createState() =>
      _AssessmentResultScreenState();
}

class _AssessmentResultScreenState
    extends ConsumerState<AssessmentResultScreen> {
  AssessmentContext get input => widget.input;
  AssessmentDraft get draft => widget.draft;
  AssessmentResult get result => draft.result;

  bool _saving = false;
  String? _error;

  // ------------------------------------------------------------------ Referral
  late bool _refer;
  Facility? _facility;
  late ReferralUrgency _urgency;

  // ---------------------------------------------------------------- Follow-up
  late int _followDays;

  // ---------------------------------------------------------------- Nutrition
  late CostTier _cost;

  // ---------------------------------------------------------------- Override
  /// The triage the CHO chose instead of the engine's, or null while the
  /// engine's verdict stands. Persisted with their name and reason — the human
  /// is accountable for the care, and the override is the honest training
  /// signal for the model.
  TriageLevel? _override;
  final _overrideReason = TextEditingController();

  @override
  void dispose() {
    _overrideReason.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _cost = CostTier.low;
    // Seed the referral and follow-up controls from the *synthesized* plan,
    // not the raw engine result. If the never-miss guard-rail or a clinical
    // interaction escalated the verdict to urgent, the referral toggle must
    // start ON — the CHO should not have to spot the escalation themselves.
    final plan = _carePlan;
    _refer = plan.needsReferral;
    _urgency = plan.needsReferral
        ? ReferralUrgency.immediate
        : ReferralUrgency.scheduled;
    _followDays = plan.followUpInDays ?? 7;
    _facility = _adequateFacilities().firstOrNull;
  }

  // ------------------------------------------------------------ Derived data

  List<Facility> _adequateFacilities() {
    final needed = {
      for (final s in result.referralCapabilitiesNeeded)
        ...FacilityCapability.values.where((c) => c.name == s),
    };
    return Facilities.adequateFor(
      region: input.household.region,
      district: input.household.district,
      required: needed,
    );
  }

  NutritionPlan? _nutritionPlan() {
    final status = result.nutritionStatus;
    if (status == null) return null;

    // A bereaved mother is not handed breastfeeding and lactation advice by a
    // machine. The PNC engine already switches the conversation; the food plan
    // follows suit by standing down.
    final bereaved = draft.inputs['baby_alive'] == false;

    final subject = switch (result.clientType) {
      ClientType.pregnantWoman => NutritionSubject.pregnantWoman,
      ClientType.postpartumWoman || ClientType.womanOfReproductiveAge =>
        bereaved ? null : NutritionSubject.breastfeedingWoman,
      _ => NutritionSubject.child,
    };
    if (subject == null) return null;

    final groups = <FoodGroup>{
      for (final name in (draft.inputs['food_groups'] as List? ?? const []))
        ...FoodGroup.values.where((g) => g.name == name),
    };

    final hb = draft.inputs['haemoglobin'];
    final anaemic = (hb is num && hb < 11) ||
        draft.inputs['danger_signs'] is List &&
            ((draft.inputs['danger_signs'] as List).contains('pallorSevere') ||
                (draft.inputs['danger_signs'] as List).contains('pallorSome'));

    return NutritionEngine.plan(
      subject: subject,
      status: status,
      month: DateTime.now().month,
      ageMonths: input.person.ageInMonths ??
          (draft.inputs['age_in_months'] as int? ?? 0),
      stillBreastfeeding: draft.inputs['still_breastfeeding'] as bool?,
      groupsEatenYesterday: groups,
      maxCost: _cost,
      hasBilateralOedema: draft.inputs['has_oedema'] == true,
      appetiteTestPassed: draft.inputs['appetite_test'] as bool?,
      hasAnyDangerSign: result.dangerSignsPresent.isNotEmpty,
      isAnaemic: anaemic,
    );
  }

  ImmunisationPlan? _immunisationPlan() {
    final given = draft.inputs['vaccines_given'];
    if (given is! List) return null;
    final ageDays = input.person.ageInDays ??
        ((draft.inputs['age_in_months'] as int? ?? 0) * 30.4375).round();
    return ImmunisationEngine.plan(
      ageInDays: ageDays,
      givenLabels: {for (final l in given) l as String},
    );
  }

  /// The unified care plan: every engine that ran on this patient — the
  /// primary protocol, immunisation, nutrition and the growth z-score —
  /// synthesized into one prioritized, interaction-aware, explainable
  /// decision. This, not any single engine's list, is what the CHO acts on.
  CarePlan get _carePlan {
    final extraFindings = <ClinicalFinding>[];
    final extraActions = <RecommendedAction>[];

    final imm = _immunisationPlan();
    if (imm != null) {
      final parts = ImmunisationEngine.asAssessmentParts(imm);
      extraFindings.addAll(parts.findings);
      extraActions.addAll(parts.actions);
    }

    final nut = _nutritionPlan();
    if (nut != null) {
      extraActions.addAll(NutritionEngine.asActions(nut));
    }

    // Weight-for-height wasting screen, when this visit recorded both
    // anthropometrics and the child's sex is known.
    final growth = draft.growth;
    final sex = input.person.sex;
    if (growth != null &&
        sex != null &&
        growth.weightKg != null &&
        growth.heightCm != null) {
      final z = GrowthZScoreEngine.assess(
        sex: sex,
        weightKg: growth.weightKg,
        heightCm: growth.heightCm,
        hasBilateralOedema: growth.hasBilateralOedema,
      );
      extraFindings.addAll(z.findings);
    }

    // Weight-gain rate for a child on therapeutic feeding — the loop that
    // closes SAM care. A child losing weight on treatment is deteriorating
    // until proven otherwise, and that verdict must govern the plan rather
    // than wait for a future visit to notice. Runs only when monitoring
    // applies (malnourished, with an earlier weight to compare against).
    if (growth != null) {
      final response = TreatmentResponseEngine.assessFromSeries(
        series: widget.priorGrowth,
        current: growth,
        nutritionStatus: result.nutritionStatus,
      );
      if (response != null) {
        extraFindings.addAll(response.findings);
        extraActions.addAll(response.actions);
      }
    }

    // Measurement-quality screen: even when the CHO confirmed and proceeded
    // past an implausible reading at the form, the plan itself carries the
    // concern — so the record shows the decision was made with a flagged
    // value, not that the value was trusted.
    extraFindings.addAll(_measurementSafetyFindings());

    return RecommendationEngine.synthesize(
      results: [result],
      extraFindings: extraFindings,
      extraActions: extraActions,
    );
  }

  /// Runs the plausibility screen over everything this visit recorded, reading
  /// the growth measurement first and falling back to the raw inputs, so both
  /// the child and maternal charts are covered by one pass.
  List<ClinicalFinding> _measurementSafetyFindings() {
    final inputs = draft.inputs;
    double? reading(String key) => (inputs[key] as num?)?.toDouble();
    final growth = draft.growth;
    return MeasurementSafetyEngine.screenFindings(
      {
        MeasurementKind.weightKg: growth?.weightKg ?? reading('weight_kg'),
        MeasurementKind.heightCm: growth?.heightCm ?? reading('height_cm'),
        MeasurementKind.muacCm: growth?.muacCm ?? reading('muac_cm'),
        MeasurementKind.temperatureC: reading('temperature_celsius'),
        MeasurementKind.respiratoryRate: reading('respiratory_rate'),
        MeasurementKind.heartRate: reading('pulse'),
        MeasurementKind.systolicBp: reading('systolic'),
        MeasurementKind.diastolicBp: reading('diastolic'),
        MeasurementKind.haemoglobin: reading('haemoglobin'),
        MeasurementKind.oxygenSaturation: reading('oxygen_saturation'),
        MeasurementKind.gestationalWeeks: reading('gestational_weeks'),
      },
      systolic: reading('systolic'),
      diastolic: reading('diastolic'),
    );
  }

  /// The classification to show and persist: the synthesized plan's merged
  /// classifications when present, falling back to the raw engine's wording.
  String _classificationOf(CarePlan plan) =>
      plan.classifications.isNotEmpty
          ? plan.classifications.join(' + ')
          : result.classification;

  /// The triage that actually governs care — the CHO's override when they
  /// overruled, otherwise the engine's synthesized verdict. Mirrors
  /// [Assessment.effectiveTriage] so what the screen shows is what the record
  /// will say.
  TriageLevel get _effectiveTriage => _override ?? _carePlan.overallTriage;

  // -------------------------------------------------------------------- Save

  Future<void> _save() async {
    final user = input.user;
    setState(() {
      _saving = true;
      _error = null;
    });

    final assessmentId = _uuid.v4();
    final now = DateTime.now();

    // The record is built from the *synthesized* plan — the decision the CHO
    // actually saw — so the referral, the follow-up and the stored assessment
    // all agree with what was on the screen.
    final plan = _carePlan;
    final classification = _classificationOf(plan);

    // An override without a real reason is not an override — it is a tap. The
    // reason is kept with the record (and reviewed by a supervisor), so the
    // bar is a few honest words, the same one the repository enforces.
    final overriding = _override != null;
    if (overriding && _overrideReason.text.trim().length < 10) {
      setState(() {
        _saving = false;
        _error = 'Give a clinical reason for overruling the engine — a few '
            'words. It is kept with the record.';
      });
      return;
    }

    final assessment = Assessment(
      id: assessmentId,
      visitId: widget.visitId,
      personId: input.person.id,
      clientType: result.clientType,
      performedBy: user.id,
      performedAt: now,
      inputs: draft.inputs,
      result: result,
      carePlanJson: jsonEncode(plan.toJson()),
      overriddenTriage: _override,
      overrideReason: overriding ? _overrideReason.text.trim() : null,
      overrideBy: overriding ? user.id : null,
    );

    Referral? referral;
    if (_refer) {
      final facility = _facility;
      if (facility == null) {
        setState(() {
          _saving = false;
          _error = 'Choose a facility to refer to, or turn the referral off.';
        });
        return;
      }
      referral = Referral(
        id: _uuid.v4(),
        referenceCode: _referenceCode(),
        personId: input.person.id,
        assessmentId: assessmentId,
        facilityName: facility.name,
        reason: classification,
        urgency: _urgency,
        issuedBy: user.id,
        issuedAt: now,
        clinicalSummary: [
          classification,
          if (plan.dangerSigns.isNotEmpty)
            'Danger signs: ${plan.dangerSigns.join(', ')}.',
          if (plan.interactions.isNotEmpty)
            'Conditions interact: '
                '${plan.interactions.map((i) => i.label).join('; ')}.',
          if (input.household.walkingMinutesToFacility != null)
            'Household is about ${input.household.walkingMinutesToFacility} '
                'minutes on foot from the facility.',
        ].join(' '),
      );
    }

    final followUps = [
      ScheduledContact(
        id: _uuid.v4(),
        personId: input.person.id,
        householdId: input.household.id,
        dueDate: now.add(Duration(days: _followDays)),
        purpose: '$classification — review',
        createdBy: user.id,
        assessmentId: assessmentId,
        priority: _effectiveTriage,
      ),
    ];

    try {
      await ref.read(careRepositoryProvider).saveAssessment(
        user,
        assessment,
        referral: referral,
        followUps: followUps,
      );

      // The growth measurement joins the child's series so the trajectory
      // engine sees this point. It is saved separately because it is a
      // different permission — vitals, not assessment.
      if (draft.growth != null) {
        try {
          await ref.read(careRepositoryProvider).recordGrowth(
            user,
            draft.growth!,
          );
        } on AccessDenied {
          // The assessment is already saved; do not lose it over the growth
          // point. The CHO simply does not hold the vitals permission.
        }
      }

      ref.invalidate(latestAssessmentProvider(input.person.id));
      ref.invalidate(growthSeriesProvider(input.person.id));
      ref.invalidate(householdScoreProvider(input.household.id));
      ref.invalidate(dayPlanProvider);
      ref.invalidate(openReferralsProvider);

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AccessDenied catch (e) {
      setState(() {
        _saving = false;
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _saving = false;
        _error = 'Could not save: $e';
      });
    }
  }

  /// A short, human-speakable referral code. Ambiguous letters and digits are
  /// excluded so it survives being read down a crackly phone line.
  String _referenceCode() {
    const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return 'CB-${List.generate(4, (_) => alphabet[r.nextInt(alphabet.length)]).join()}';
  }

  // ------------------------------------------------------------------- Build

  @override
  Widget build(BuildContext context) {
    final plan = _carePlan;
    final effective = _effectiveTriage;
    final c = triageColours(effective);
    final nutrition = _nutritionPlan();
    final immunisation = _immunisationPlan();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Assessment result'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(22),
          child: Padding(
            padding: const EdgeInsets.only(
              left: Gap.lg,
              right: Gap.lg,
              bottom: Gap.sm,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                input.person.fullName,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.inkMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(Gap.lg),
        children: [
          // ------------------------------------------------- Verdict banner
          Container(
            padding: const EdgeInsets.all(Gap.lg),
            decoration: BoxDecoration(
              color: c.bg,
              borderRadius: BorderRadius.circular(Gap.radius),
              border: Border(left: BorderSide(color: c.fg, width: 5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _classificationOf(plan),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: c.fg,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.sm),
                TriageBadge(effective),
                if (_override != null) ...[
                  const SizedBox(height: Gap.sm),
                  _OverrideNote(
                    engine: plan.overallTriage,
                    chosen: effective,
                  ),
                ],
                const SizedBox(height: Gap.md),
                Row(
                  children: [
                    ConfidenceChip(
                      plan.confidence,
                      missingCount: plan.missingData.length,
                    ),
                    const SizedBox(width: Gap.sm),
                    if (plan.followUpInDays != null)
                      Text(
                        'Review in ${plan.followUpInDays} days',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.inkMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
                if (plan.missingData.isNotEmpty) ...[
                  const SizedBox(height: Gap.md),
                  Text(
                    'Not measured: ${plan.missingData.join(', ')}. '
                    'These lower the confidence, not the safety — the engine '
                    'still acts on what it has.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.inkMuted,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: Gap.lg),

          // ------------------------------------------- Why this plan (NEW)
          // The explainability anchor: one place where the CHO can see the
          // governing triage, the reasoning behind it, and any safety net
          // that fired. A decision they cannot see the arithmetic of is a
          // decision they cannot defend.
          SectionCard(
            title: 'Why this plan',
            subtitle:
                'The reasoning behind every decision below, in one place.',
            icon: Icons.psychology_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plan.triageRationale,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: Gap.sm),
                Text(
                  plan.summary,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.inkMuted,
                    height: 1.5,
                  ),
                ),
                if (plan.guardrailEscalated) ...[
                  const SizedBox(height: Gap.md),
                  const _SafetyNetNote(
                    text: 'Safety net: a danger sign was detected, so this '
                        'plan was raised to urgent automatically.',
                  ),
                ],
                if (plan.referralGuaranteed) ...[
                  const SizedBox(height: Gap.md),
                  const _SafetyNetNote(
                    text: 'Safety net: an urgent verdict always carries a '
                        'referral — one was added because none was listed.',
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: Gap.lg),

          // ------------------------------------- Clinical override (Tier 4)
          // The human overrules the machine. Gated on the override permission
          // — an FHW holds it, a caregiver does not, because a family talking
          // itself out of a danger sign is the one outcome the app must never
          // produce. Recorded with a name and a reason: accountability and the
          // training signal in one gesture.
          if (input.user.can(Permission.overrideAiRecommendation)) ...[
            _OverrideSection(
              engineTriage: plan.overallTriage,
              overrideLevel: _override,
              reasonController: _overrideReason,
              onOverride: (level) {
                setState(() {
                  _override = level;
                  // An urgent override carries the same guarantee the engine
                  // applies to its own urgent verdicts: it must refer.
                  if (level == TriageLevel.urgent) {
                    _refer = true;
                    _urgency = ReferralUrgency.immediate;
                  }
                });
              },
            ),
            const SizedBox(height: Gap.lg),
          ],

          // ------------------------------------------------------- Findings
          if (plan.findings.isNotEmpty) ...[
            SectionCard(
              title: 'What the protocol found',
              subtitle:
                  'Each finding names the value, the cut-off it crossed and '
                  'the guideline it comes from.',
              icon: Icons.fact_check_outlined,
              child: Column(
                children: [
                  for (final f in plan.findings)
                    FindingTile(
                      label: f.label,
                      detail: f.detail,
                      severity: f.severity,
                      source: f.protocolSource,
                      measured: f.measuredValue,
                      threshold: f.threshold,
                    ),
                ],
              ),
            ),
            const SizedBox(height: Gap.lg),
          ],

          // ------------------------------------- Conditions interact (NEW)
          // The highest-value rules in the synthesizer: cases where two
          // conditions together change the answer. Surfaced ahead of the
          // action list because they are exactly what a single-condition
          // list cannot show a tired CHO.
          if (plan.interactions.isNotEmpty) ...[
            SectionCard(
              title: 'Conditions interact',
              subtitle: 'These change the plan — act on them first.',
              icon: Icons.warning_amber_rounded,
              child: Column(
                children: [
                  for (final i in plan.interactions)
                    FindingTile(
                      label: i.label,
                      detail: i.detail,
                      severity: i.severity,
                      source: i.protocolSource,
                    ),
                ],
              ),
            ),
            const SizedBox(height: Gap.lg),
          ],

          // -------------------------------------------------------- Actions
          if (plan.actions.isNotEmpty) ...[
            SectionCard(
              title: 'What to do',
              subtitle: 'Ordered by urgency.',
              icon: Icons.checklist_rounded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final a in plan.actions) _ActionTile(a),
                ],
              ),
            ),
            const SizedBox(height: Gap.lg),
          ],

          // ------------------------------------------------------ Nutrition
          if (nutrition != null) ...[
            _NutritionSection(plan: nutrition, cost: _cost, onCost: (tier) {
              setState(() => _cost = tier);
            }),
            const SizedBox(height: Gap.lg),
          ],

          // ------------------------------------- Early learning [49] (NEW)
          // Nurturing Care domains 3 & 5 — responsive caregiving and early
          // learning. Only for the newborn and child-under-five categories.
          if (result.clientType == ClientType.newborn ||
              result.clientType == ClientType.childUnderFive) ...[
            _EarlyLearningSection(person: input.person),
            const SizedBox(height: Gap.lg),
          ],

          // -------------------------------------------------- Immunisation
          if (immunisation != null) ...[
            _ImmunisationSection(plan: immunisation),
            const SizedBox(height: Gap.lg),
          ],

          // ------------------------------------------------------- Referral
          _ReferralSection(
            refer: _refer,
            onRefer: (v) => setState(() => _refer = v),
            facilities: _adequateFacilities(),
            facility: _facility,
            onFacility: (f) => setState(() => _facility = f),
            urgency: _urgency,
            onUrgency: (u) => setState(() => _urgency = u),
            capabilities: result.referralCapabilitiesNeeded,
          ),
          const SizedBox(height: Gap.lg),

          // ------------------------------------------------------ Follow-up
          SectionCard(
            title: 'Follow-up contact',
            subtitle:
                'Scheduled into the plan-my-day queue. The CHO who started '
                'this case is the one who should close it.',
            icon: Icons.event_repeat_outlined,
            child: ChoiceChipsField<int>(
              label: 'Review in',
              options: const [1, 2, 3, 7, 14, 30],
              labelOf: (d) => '$d day${d == 1 ? '' : 's'}',
              value: _followDays,
              onChanged: (d) => setState(() => _followDays = d ?? 7),
            ),
          ),
          const SizedBox(height: Gap.lg),

          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(Gap.md),
              decoration: BoxDecoration(
                color: AppColors.triageRedBg,
                borderRadius: BorderRadius.circular(Gap.radiusSm),
              ),
              child: Text(
                _error!,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.triageRed,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: Gap.lg),
          ],

          const SizedBox(height: Gap.xxl),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(Gap.lg),
        child: FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.save_outlined),
          label: Text(_saving ? 'Saving…' : 'Save assessment'),
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------- Action

class _ActionTile extends StatelessWidget {
  const _ActionTile(this.action);

  final RecommendedAction action;

  @override
  Widget build(BuildContext context) {
    final (icon, colour) = action.isReferral
        ? (Icons.local_hospital_outlined, AppColors.triageRed)
        : action.isTreatment
        ? (Icons.medication_outlined, AppColors.triageAmber)
        : (Icons.chat_bubble_outline_rounded, AppColors.accent);

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colour),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  action.instruction,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
                ),
                if (action.rationale != null) ...[
                  const SizedBox(height: Gap.xs),
                  Text(
                    action.rationale!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.inkMuted,
                      height: 1.4,
                    ),
                  ),
                ],
                if (action.protocolSource != null) ...[
                  const SizedBox(height: Gap.xs),
                  Text(
                    action.protocolSource!,
                    style: const TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: AppColors.inkFaint,
                    ),
                  ),
                ],
                const SizedBox(height: Gap.xs),
                Text(
                  action.urgency.label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: action.isReferral
                        ? AppColors.triageRed
                        : AppColors.inkMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------- Safety net note

/// A small amber callout shown when one of the synthesizer's safety nets —
/// the never-miss escalation or the referral guarantee — has fired. These are
/// deliberately conspicuous: a guard-rail that fires is exactly the kind of
/// thing a supervisor wants to see, not something to bury.
class _SafetyNetNote extends StatelessWidget {
  const _SafetyNetNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: AppColors.triageAmberBg,
        borderRadius: BorderRadius.circular(Gap.radiusSm),
        border: Border(
          left: BorderSide(color: AppColors.triageAmber, width: 4),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.shield_outlined,
            size: 16,
            color: AppColors.triageAmber,
          ),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.triageAmber,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ Override

/// The interactive "overrule the engine" card. Only shown to a user who holds
/// [Permission.overrideAiRecommendation]. Selecting a triage level records an
/// override; selecting it again (deselecting) returns to the engine's verdict.
class _OverrideSection extends StatelessWidget {
  const _OverrideSection({
    required this.engineTriage,
    required this.overrideLevel,
    required this.reasonController,
    required this.onOverride,
  });

  final TriageLevel engineTriage;
  final TriageLevel? overrideLevel;
  final TextEditingController reasonController;
  final ValueChanged<TriageLevel?> onOverride;

  @override
  Widget build(BuildContext context) => SectionCard(
    title: overrideLevel == null
        ? 'Your clinical judgement'
        : 'Overriding the engine',
    subtitle:
        'The protocol\u2019s verdict stands unless you overrule it. An override '
        'is saved with your name and your reason \u2014 you are accountable for '
        'the care, and it is how the recommendations get better.',
    icon: Icons.gavel_outlined,
    accent: overrideLevel == null ? null : AppColors.triageAmber,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ChoiceChipsField<TriageLevel>(
          label: 'Overrule the verdict?',
          why: 'Engine\u2019s verdict: ${engineTriage.label}. Tap a level to '
              'overrule; tap it again to keep the engine\u2019s.',
          options: TriageLevel.values,
          labelOf: (t) => t.label,
          value: overrideLevel,
          onChanged: onOverride,
        ),
        if (overrideLevel != null) ...[
          const FieldLabel('Clinical reason for overruling', required: true),
          TextField(
            controller: reasonController,
            maxLines: 3,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'e.g. Child looks more unwell than the score suggests '
                  '\u2014 referring on clinical grounds.',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Gap.radiusSm),
              ),
            ),
          ),
          const SizedBox(height: Gap.sm),
          const Text(
            'Saved with your name on the record. A supervisor can review '
            'every override.',
            style: TextStyle(
              fontSize: 11.5,
              color: AppColors.inkFaint,
              height: 1.4,
            ),
          ),
        ],
      ],
    ),
  );
}

/// A compact callout in the verdict banner when the CHO has overruled the
/// engine, so the level that actually governs care is unmistakable.
class _OverrideNote extends StatelessWidget {
  const _OverrideNote({required this.engine, required this.chosen});

  final TriageLevel engine;
  final TriageLevel chosen;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Gap.md,
        vertical: Gap.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.triageAmberBg,
        borderRadius: BorderRadius.circular(Gap.radiusSm),
        border: Border(
          left: BorderSide(color: AppColors.triageAmber, width: 4),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.gavel_outlined,
            size: 15,
            color: AppColors.triageAmber,
          ),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Text(
              'You overruled the engine (${engine.label}) and set this to '
              '${chosen.label}. Your name and reason are saved with the record.',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.triageAmber,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ Nutrition

class _NutritionSection extends StatelessWidget {
  const _NutritionSection({
    required this.plan,
    required this.cost,
    required this.onCost,
  });

  final NutritionPlan plan;
  final CostTier cost;
  final ValueChanged<CostTier> onCost;

  @override
  Widget build(BuildContext context) => SectionCard(
    title: 'Nutrition',
    subtitle: plan.pathway.label,
    icon: Icons.restaurant_outlined,
    accent: plan.therapeuticFoodRequired
        ? AppColors.triageRed
        : AppColors.accent,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(Gap.md),
          decoration: BoxDecoration(
            color: plan.therapeuticFoodRequired
                ? AppColors.triageRedBg
                : AppColors.triageGreenBg,
            borderRadius: BorderRadius.circular(Gap.radiusSm),
          ),
          child: Text(
            plan.headline,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              height: 1.4,
              color: plan.therapeuticFoodRequired
                  ? AppColors.triageRed
                  : AppColors.triageGreen,
            ),
          ),
        ),
        const SizedBox(height: Gap.md),
        Text(
          plan.seasonNote,
          style: const TextStyle(
            fontSize: 12.5,
            color: AppColors.inkMuted,
            height: 1.4,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: Gap.md),
        ChoiceChipsField<CostTier>(
          label: 'What can this household afford this month?',
          why: 'A recommendation the family cannot buy is not a recommendation.',
          options: const [
            CostTier.freeOrGathered,
            CostTier.veryLow,
            CostTier.low,
            CostTier.moderate,
          ],
          labelOf: (t) => t.label,
          value: cost,
          onChanged: (t) => onCost(t ?? CostTier.low),
        ),
        if (plan.suggestions.isNotEmpty) ...[
          const SizedBox(height: Gap.sm),
          const FieldLabel('Start with these local foods'),
          for (final s in plan.suggestions) _FoodTile(s),
        ],
        if (plan.feedingRules.isNotEmpty) ...[
          const SizedBox(height: Gap.sm),
          const FieldLabel('Feeding rules'),
          for (final rule in plan.feedingRules)
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.check_circle_outline_rounded,
                    size: 16,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: Text(
                      rule,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
        if (plan.reviewInDays != null) ...[
          const SizedBox(height: Gap.sm),
          Text(
            'Nutrition review in ${plan.reviewInDays} '
            'day${plan.reviewInDays == 1 ? '' : 's'}.',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
        ],
      ],
    ),
  );
}

class _FoodTile extends StatelessWidget {
  const _FoodTile(this.food);

  final FoodSuggestion food;

  /// Pick the bundled illustration that best matches this food. Real Northern
  /// Ghana foods, per master flow [48] — illustrated cards, not paragraphs.
  String get _image {
    final f = food.food.toLowerCase();
    if (f.contains('millet') ||
        f.contains('sorghum') ||
        f.contains('porridge') ||
        f.contains('rice') ||
        f.contains('maize') ||
        f.contains('yam') ||
        f.contains('cassava')) {
      return AppImages.foodMilletPorridge;
    }
    if (f.contains('moringa') ||
        f.contains('baobab') ||
        f.contains('kuka') ||
        f.contains('leaf') ||
        f.contains('vegetable') ||
        f.contains('fruit') ||
        f.contains('pawpaw') ||
        f.contains('mango')) {
      return AppImages.foodMoringaBaobab;
    }
    return AppImages.foodCowpeaStew;
  }

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: Gap.sm),
    padding: const EdgeInsets.all(Gap.md),
    decoration: BoxDecoration(
      color: AppColors.canvas,
      borderRadius: BorderRadius.circular(Gap.radiusSm),
      border: Border.all(color: AppColors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(Gap.radiusXs),
              child: SizedBox(
                width: 52,
                height: 52,
                child: AppImage(src: _image),
              ),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    food.localName != null
                        ? '${food.food} (${food.localName})'
                        : food.food,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: Gap.xs),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Gap.sm,
                      vertical: Gap.xs,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      food.householdMeasure,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.xs),
        Text(
          food.reason,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.inkMuted,
            height: 1.4,
          ),
        ),
        if (food.preparation != null) ...[
          const SizedBox(height: Gap.xs),
          Text(
            'How: ${food.preparation}',
            style: const TextStyle(fontSize: 12, height: 1.4),
          ),
        ],
        if (food.caution != null) ...[
          const SizedBox(height: Gap.xs),
          Text(
            'Caution: ${food.caution}',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.triageAmber,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ],
      ],
    ),
  );
}

// ---------------------------------------------------------- Early learning [49]

/// Early Learning & Responsive Care tips — master flow [49], a required NEW
/// screen that closes Nurturing Care domains 3 (responsive caregiving) and 5
/// (early learning). Two to three simple, age-appropriate things a caregiver
/// can do today, with no toys and no money — talking, playing, responding.
class _EarlyLearningSection extends StatelessWidget {
  const _EarlyLearningSection({required this.person});

  final Person person;

  List<String> get _tips {
    final months = person.ageInMonths;
    if (person.effectiveClientType == ClientType.newborn ||
        (months != null && months < 3)) {
      return const [
        'Talk and sing to your baby while feeding and bathing. Your voice is '
            'their first lesson.',
        'Hold your baby close and look into their eyes. They learn safety '
            'from your face.',
        'When your baby cries, answer quickly. A baby who is answered learns '
            'to trust the world.',
      ];
    }
    if (months != null && months < 6) {
      return const [
        'Smile back when your baby smiles. This back-and-forth builds their '
            'brain.',
        'Let them reach for a clean spoon or cup. Grasping is their first '
            'game.',
        'Name things as you touch them: "nose", "hand", "water".',
      ];
    }
    if (months != null && months < 12) {
      return const [
        'Play peek-a-boo. It teaches that things still exist when they are '
            'hidden.',
        'Give safe household objects to explore — a cup, a spoon, a cloth.',
        'Answer their sounds and babbling as if you are having a real '
            'conversation.',
      ];
    }
    if (months != null && months < 24) {
      return const [
        'Name body parts while bathing: "This is your hand, this is your '
            'foot".',
        'Let them try feeding themselves, even if it is messy. Practice '
            'builds skill.',
        'Count out loud together as you walk: one, two, three.',
      ];
    }
    return const [
      'Tell stories and ask "What happens next?" Imagination is learning.',
      'Let them draw with a stick in the sand, or with chalk on a wall.',
      'Give small jobs — fetching a spoon, carrying a small bowl. '
          'Responsibility is learning too.',
    ];
  }

  @override
  Widget build(BuildContext context) => SectionCard(
    title: 'Play, talk, respond',
    subtitle:
        'A child\u2019s brain grows fastest in the first five years. These '
        'cost nothing and need no toys \u2014 just you.',
    icon: Icons.toys_outlined,
    accent: AppColors.primary,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final tip in _tips)
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.tips_and_updates_outlined,
                  size: 16,
                  color: AppColors.primary,
                ),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text(
                    tip,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

// --------------------------------------------------------------- Immunisation

class _ImmunisationSection extends StatelessWidget {
  const _ImmunisationSection({required this.plan});

  final ImmunisationPlan plan;

  @override
  Widget build(BuildContext context) => SectionCard(
    title: 'Immunisation catch-up',
    subtitle: plan.summary,
    icon: Icons.vaccines_outlined,
    accent: plan.overdue.isEmpty ? AppColors.accent : AppColors.triageAmber,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (plan.giveToday.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(Gap.md),
            decoration: BoxDecoration(
              color: AppColors.triageAmberBg,
              borderRadius: BorderRadius.circular(Gap.radiusSm),
            ),
            child: Text(
              'Give today: '
              '${plan.giveToday.map((d) => d.label).join(', ')}.',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.triageAmber,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: Gap.md),
        ],
        for (final item in plan.items)
          if (item.status == ImmunisationStatus.overdue ||
              item.status == ImmunisationStatus.dueToday ||
              item.status == ImmunisationStatus.ageBarred)
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    item.status == ImmunisationStatus.ageBarred
                        ? Icons.block_outlined
                        : Icons.priority_high_rounded,
                    size: 16,
                    color: item.status == ImmunisationStatus.ageBarred
                        ? AppColors.inkFaint
                        : AppColors.triageAmber,
                  ),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: Text(
                      '${item.dose.label}: ${item.detail}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        if (plan.nextDueLabel != null && plan.nextDueInDays != null) ...[
          const SizedBox(height: Gap.sm),
          Text(
            'Next due: ${plan.nextDueLabel} in about ${plan.nextDueInDays} '
            'days.',
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.inkMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    ),
  );
}

// ------------------------------------------------------------------- Referral

class _ReferralSection extends StatelessWidget {
  const _ReferralSection({
    required this.refer,
    required this.onRefer,
    required this.facilities,
    required this.facility,
    required this.onFacility,
    required this.urgency,
    required this.onUrgency,
    required this.capabilities,
  });

  final bool refer;
  final ValueChanged<bool> onRefer;
  final List<Facility> facilities;
  final Facility? facility;
  final ValueChanged<Facility?> onFacility;
  final ReferralUrgency urgency;
  final ValueChanged<ReferralUrgency> onUrgency;
  final Set<String> capabilities;

  @override
  Widget build(BuildContext context) => SectionCard(
    title: refer ? 'Referral' : 'Referral (off)',
    subtitle: refer
        ? 'The receiving facility must be able to do what this case needs.'
        : 'The protocol does not require a referral. Turn this on if clinical '
              'judgement says otherwise.',
    icon: refer
        ? Icons.local_hospital_outlined
        : Icons.local_hospital_outlined,
    accent: refer ? AppColors.triageRed : null,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DangerSign(
          label: 'Issue a referral',
          value: refer,
          danger: true,
          onChanged: (v) => onRefer(v ?? false),
        ),
        if (refer) ...[
          if (capabilities.isNotEmpty) ...[
            const SizedBox(height: Gap.sm),
            Text(
              'Needs: ${capabilities.join(', ')}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.inkMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: Gap.md),
          ],
          FieldLabel('Refer to', required: true),
          for (final f in facilities.take(4))
            _FacilityTile(
              facility: f,
              selected: facility?.name == f.name,
              onTap: () => onFacility(f),
            ),
          const SizedBox(height: Gap.md),
          ChoiceChipsField<ReferralUrgency>(
            label: 'How soon?',
            options: ReferralUrgency.values,
            labelOf: (u) => u.label,
            value: urgency,
            onChanged: (u) => onUrgency(u ?? ReferralUrgency.immediate),
          ),
        ],
      ],
    ),
  );
}

class _FacilityTile extends StatelessWidget {
  const _FacilityTile({
    required this.facility,
    required this.selected,
    required this.onTap,
  });

  final Facility facility;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Gap.sm),
    child: Material(
      color: selected ? AppColors.primaryLight : AppColors.canvas,
      borderRadius: BorderRadius.circular(Gap.radiusSm),
      child: InkWell(
        borderRadius: BorderRadius.circular(Gap.radiusSm),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                size: 20,
                color: selected ? AppColors.primary : AppColors.inkFaint,
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      facility.name,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${facility.tier.label} · ${facility.district}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
