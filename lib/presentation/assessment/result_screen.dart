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
import '../../core/i18n/speech_bank.dart';
import '../../core/ml/offline_inference_service.dart';
import '../../core/ml/recalibration_export.dart';
import '../../core/ml/recalibration_store.dart';
import '../../core/ml/verdict_feedback_store.dart';
import '../../core/theme/app_theme.dart';
import '../../data/reference/facilities.dart';
import '../../data/reference/local_foods.dart';
import '../../data/repositories/care_repository.dart';
import '../../domain/engines/growth_zscore_engine.dart';
import '../../domain/engines/immunisation_engine.dart';
import '../../domain/engines/measurement_safety_engine.dart';
import '../../domain/engines/nurturing_care_engine.dart';
import '../../domain/engines/nutrition_engine.dart';
import '../../domain/engines/nutrition/therapeutic_supplements.dart';
import '../../domain/engines/protocols/stabilization_protocol_selector.dart';
import '../../domain/engines/recommendation_engine.dart';
import '../../domain/engines/trajectory_engine.dart';
import '../../domain/engines/treatment_response_engine.dart';
import '../../domain/entities/core.dart';
import '../../domain/entities/visit.dart';
import '../../domain/enums.dart';
import '../shared/app_image.dart';
import '../shared/audio_button.dart';
import '../shared/recommendation_kit.dart';
import '../shared/ui.dart';
import 'assessment_feature_adapter.dart';
import 'decision_workspace.dart';
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
    this.inferenceService,
  });

  final AssessmentContext input;
  final AssessmentDraft draft;
  final String visitId;
  final OfflineInferenceService? inferenceService;

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

  /// Whether the full findings list is unfolded. Collapsed by default: a
  /// result screen is a decision, not a data dump — the drivers lead.
  bool _showAllFindings = false;

  /// Whether the clinical override panel is unfolded.
  bool _showOverride = false;

  /// Which page of the result experience is showing: 0 = the verdict
  /// moment (the decision, nothing else), 1 = the care plan it opens,
  /// 2 = the tailored nutrition plan, 3 = the full clinical report (the
  /// evidence behind all of it). Pages, so the decision is never buried
  /// under its own paperwork.
  int _view = 0;

  // ---------------------------------------------------------------- Override
  /// The triage the CHO chose instead of the engine's, or null while the
  /// engine's verdict stands. Persisted with their name and reason — the human
  /// is accountable for care. An override is decision audit data, not a diagnosis.
  TriageLevel? _override;
  final _overrideReason = TextEditingController();
  late Future<Map<String, OfflineRiskPrediction>> _mlPredictions;

  /// Nurse-facing model provenance, separate from clinical decision-making.
  late Future<List<OfflineModelStatus>> _modelStatuses;

  final Set<String> _completedActions = {};

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
    final service = widget.inferenceService ?? OfflineInferenceService.instance;
    final bag = _buildFeatureBag();
    // Clinical guidance and referral controls never wait for model analysis.
    _mlPredictions = service.runAllPredictions(
      bag,
      includeNeonatal: result.clientType == ClientType.newborn,
      includeChildPneumonia: result.clientType == ClientType.childUnderFive,
      includePreeclampsia: result.clientType == ClientType.pregnantWoman,
      includeLbwSga: result.clientType == ClientType.pregnantWoman,
    );
    _modelStatuses = service.modelStatuses();
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

  OfflineFeatureBag _buildFeatureBag() =>
      AssessmentFeatureAdapter(input, draft).features;

  /// The findings that drove the verdict, drivers first (severity, then
  /// weight). Collapsed to the top three unless the CHO unfolds the rest.
  List<ClinicalFinding> _displayFindings(List<ClinicalFinding> all) {
    const rank = {
      TriageLevel.urgent: 0,
      TriageLevel.priority: 1,
      TriageLevel.watch: 2,
      TriageLevel.routine: 3,
    };
    final sorted = List<ClinicalFinding>.from(all)
      ..sort((a, b) {
        final r = rank[a.severity]!.compareTo(rank[b.severity]!);
        if (r != 0) return r;
        return b.weight.compareTo(a.weight);
      });
    if (_showAllFindings || sorted.length <= 3) return sorted;
    return sorted.take(3).toList(growable: false);
  }

  /// The verdict-page deck. AI-model findings are withheld here because the
  /// decision brief already speaks their number once; the full clinical
  /// report still lists everything. Every fact, exactly once.
  List<ClinicalFinding> _verdictFindings(List<ClinicalFinding> all) =>
      _displayFindings(
        all.where((f) => !f.aiGenerated).toList(growable: false),
      );

  /// Where this child is heading, not just where they are: the slope
  /// across every recorded measurement including today's, shown on the
  /// verdict page only when a real trend exists. A first-ever reading
  /// gets no card — absence of data is stated by the engine, never
  /// guessed by the UI.
  TrajectoryResult? get _trajectory {
    if (widget.priorGrowth.isEmpty) return null;
    final series = [
      ...widget.priorGrowth,
      if (draft.growth != null) draft.growth!,
    ];
    final result = TrajectoryEngine.analyse(series);
    return result.trend == GrowthTrend.insufficientData ? null : result;
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
    final hbDouble = hb is num ? hb.toDouble() : null;
    final anaemic =
        (hb is num && hb < 11) ||
        draft.inputs['danger_signs'] is List &&
            ((draft.inputs['danger_signs'] as List).contains('pallorSevere') ||
                (draft.inputs['danger_signs'] as List).contains('pallorSome'));

    // Therapeutic context uses measured observations and documented history.
    final birth = input.birth;
    final isPostpartum = result.clientType == ClientType.postpartumWoman;
    final gestationalWeeks = (draft.inputs['gestational_weeks'] as num?)
        ?.toInt();
    final ageDays =
        input.person.ageInDays ?? (draft.inputs['age_in_days'] as int? ?? 0);
    final birthWeightKg =
        (draft.inputs['birth_weight_kg'] as num?)?.toDouble() ??
        birth?.birthWeightKg;
    final therapeuticContext = TherapeuticContext(
      gestationalWeeks: gestationalWeeks,
      haemoglobinGDl: hbDouble,
      isPostpartum: isPostpartum,
      birthWeightKg: birthWeightKg,
      ageDays: ageDays,
      nutritionStatus: status.name,
      appetiteTestPassed: draft.inputs['appetite_test'] as bool?,
      hasBilateralOedema: draft.inputs['has_oedema'] == true,
      hasAnyDangerSign: result.dangerSignsPresent.isNotEmpty,
    );

    return NutritionEngine.plan(
      subject: subject,
      status: status,
      month: DateTime.now().month,
      ageMonths:
          input.person.ageInMonths ??
          (draft.inputs['age_in_months'] as int? ?? 0),
      stillBreastfeeding: draft.inputs['still_breastfeeding'] as bool?,
      groupsEatenYesterday: groups,
      maxCost: _cost,
      hasBilateralOedema: draft.inputs['has_oedema'] == true,
      appetiteTestPassed: draft.inputs['appetite_test'] as bool?,
      hasAnyDangerSign: result.dangerSignsPresent.isNotEmpty,
      isAnaemic: anaemic,
      hasDiarrhoea:
          draft.inputs['danger_signs'] is List &&
          (draft.inputs['danger_signs'] as List).contains('diarrhoea'),
      therapeuticContext: therapeuticContext,
    );
  }

  ImmunisationPlan? _immunisationPlan() {
    final given = draft.inputs['vaccines_given'];
    if (given is! List) return null;
    final ageDays =
        input.person.ageInDays ??
        ((draft.inputs['age_in_months'] as int? ?? 0) * 30.4375).round();
    return ImmunisationEngine.plan(
      ageInDays: ageDays,
      givenLabels: {for (final l in given) l as String},
    );
  }

  /// Pillar 3: build the UNICEF Nurturing Care Framework assessment from
  /// the visit context + immunisation + nutrition plans. Returns a
  /// per-pillar action list that the result screen renders as one
  /// cohesive "Nurturing Care" card.
  NurturingCareAssessment _nurturingCareAssessment(
    ImmunisationPlan? imm,
    NutritionPlan? nutrition,
  ) {
    final ageMonths =
        input.person.ageInMonths ??
        (draft.inputs['age_in_months'] as int? ?? 0);
    final isYoungInfant = result.clientType == ClientType.newborn;
    final stillBreastfeeding =
        draft.inputs['still_breastfeeding'] as bool? ??
        (isYoungInfant || (ageMonths < 24));
    final vitaminADue = draft.inputs['vitamin_a_due'] as bool? ?? false;
    return NurturingCareEngine.assess(
      context: NurturingCareContext(
        clientType: result.clientType,
        ageMonths: ageMonths,
        stillBreastfeeding: stillBreastfeeding,
        vitaminADue: vitaminADue,
        immunisationItems: imm?.items ?? const [],
        therapeuticSupplements:
            nutrition?.therapeuticPlan?.supplements ?? const [],
      ),
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
      stabilizationContext: _buildStabilizationContext(),
      stabilizationRisks: const StabilizationAiRisks(),
    );
  }

  StabilizationContext _buildStabilizationContext() =>
      AssessmentFeatureAdapter(input, draft).stabilization;

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
  String _classificationOf(CarePlan plan) => plan.classifications.isNotEmpty
      ? plan.classifications.join(' + ')
      : result.classification;

  /// The triage that actually governs care — the CHO's override when they
  /// overruled, otherwise the engine's synthesized verdict. Mirrors
  /// [Assessment.effectiveTriage] so what the screen shows is what the record
  /// will say.
  TriageLevel get _effectiveTriage => _override ?? _carePlan.overallTriage;

  /// The speech-bank clip for the triage that governs this result — the
  /// level's family message, in whatever bank language the user chose. The
  /// clinical headline and rationale stay in English for the CHO; what the
  /// speaker buttons play the family is the sentence they must act on, in
  /// the language they speak.
  BankScript? get _levelClip => SpeechBank.levelClip(_effectiveTriage.name);

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
        _error =
            'Give a clinical reason for overruling the engine — a few '
            'words. It is kept with the record.';
      });
      return;
    }

    // Saving care does not wait for research model execution.
    final mlPredictions = await _mlPredictions
        .timeout(
          const Duration(seconds: 2),
          onTimeout: () => <String, OfflineRiskPrediction>{},
        )
        .catchError((Object _) => <String, OfflineRiskPrediction>{});
    final inputsWithMl = Map<String, Object?>.from(
      draft.inputs,
    )..['ml_predictions'] = mlPredictions.map((k, v) => MapEntry(k, v.toMap()));

    final assessment = Assessment(
      id: assessmentId,
      visitId: widget.visitId,
      personId: input.person.id,
      clientType: result.clientType,
      performedBy: user.id,
      performedAt: now,
      inputs: inputsWithMl,
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
      await ref
          .read(careRepositoryProvider)
          .saveAssessment(
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
          await ref
              .read(careRepositoryProvider)
              .recordGrowth(user, draft.growth!);
        } on AccessDenied {
          // The assessment is already saved; do not lose it over the growth
          // point. The CHO simply does not hold the vitals permission.
        }
      }

      // Kintampo/Navrongo pathway: one de-identified record per model joins
      // the on-device batch — but only on a device the district officer has
      // armed with the GHS linkage salt. Never blocks or fails a save.
      await _appendRecalibrationRecords(mlPredictions);

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

  /// Appends one de-identified [RecalibrationRecord] per model prediction
  /// to the on-device recalibration batch. Fail-safe by design: an unarmed
  /// device (no GHS salt provisioned) collects nothing, and any storage
  /// error is swallowed — the export pathway must never cost a CHO a saved
  /// assessment.
  Future<void> _appendRecalibrationRecords(
    Map<String, OfflineRiskPrediction> predictions,
  ) async {
    try {
      final store = await RecalibrationStore.forDevice();
      if (store == null || !store.isArmed) return;
      final engineTriage = _carePlan.overallTriage.name;
      for (final prediction in predictions.values) {
        await store.append(
          RecalibrationRecord.build(
            modelName: prediction.modelName,
            modelVersion: prediction.modelVersion,
            district: input.household.district,
            clientType: _exportClientStream(result.clientType),
            ageDays: input.person.ageInDays,
            createdAt: DateTime.now(),
            features: prediction.featureValues,
            predictedProbability: prediction.riskProbability,
            predictedTier: prediction.classification,
            engineTriage: engineTriage,
            finalTriage: _effectiveTriage.name,
            referralIssued: _refer,
            referralUrgency: _refer ? _urgency.name : null,
            personId: input.person.id,
            salt: store.salt!,
          ),
        );
      }
    } catch (_) {
      // Deliberately silent — see the doc comment above.
    }
  }

  /// The export vocabulary for the client stream — `newborn` | `child` |
  /// `mother`. Kept stable by mapping explicitly, so a rename of the app's
  /// own enum can never silently change the cohort schema.
  static String _exportClientStream(ClientType type) => switch (type) {
    ClientType.newborn => 'newborn',
    ClientType.childUnderFive => 'child',
    _ => 'mother',
  };

  // ------------------------------------------------------------------- Build

  @override
  Widget build(BuildContext context) {
    final plan = _carePlan;
    final effective = _effectiveTriage;
    final nutrition = _nutritionPlan();
    final immunisation = _immunisationPlan();
    final nurturingCare = _nurturingCareAssessment(immunisation, nutrition);

    return Scaffold(
      appBar: _view == 0
          ? AppBar(
              title: Text(input.person.fullName),
              bottom: PreferredSize(
                preferredSize: Size.fromHeight(
                  MediaQuery.textScalerOf(context).scale(24) + 8,
                ),
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: Gap.lg,
                    right: Gap.lg,
                    bottom: Gap.sm,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${result.clientType.protocolLabel} · '
                      '${input.person.ageLabel}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.inkMuted,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
            )
          : AppBar(
              leading: BackButton(
                // The nutrition page backs into the care plan that opened
                // it; everything else backs into the verdict.
                onPressed: () => setState(() => _view = _view == 2 ? 1 : 0),
              ),
              title: Text(switch (_view) {
                1 => 'Care plan',
                2 => 'Nutrition plan',
                _ => 'Clinical report',
              }),
            ),
      // Three pages, one state: the verdict moment, the care plan it opens,
      // and the full clinical report behind both. The switch animates so each
      // page feels earned — a document you open, not a scroll you drown in.
      body: AnimatedSwitcher(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : AppMotion.duration,
        switchInCurve: AppMotion.curve,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.05, 0),
            end: Offset.zero,
          ).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: _view == 0
            ? KeyedSubtree(
                key: const ValueKey('verdict'),
                child: ListView(
                  padding: const EdgeInsets.all(Gap.lg),
                  children: [
                    // -------------------------------- PRE-REFERRAL (SAFETY)
                    // Life-saving pre-transport interventions outrank the
                    // verdict: they render first, because in the
                    // second-delay window the CHO must not scroll to find
                    // them.
                    if (plan.preReferralProtocols.isNotEmpty) ...[
                      _Entrance(child: PreReferralRecSection(plan: plan)),
                      const SizedBox(height: Gap.lg),
                    ],

                    // -------------------------------------- Danger signs
                    // A danger sign is the clearest sentence this
                    // assessment can speak: it leads the page, in red,
                    // so the urgency is impossible to scroll past.
                    if (result.dangerSignsPresent.isNotEmpty) ...[
                      _Entrance(
                        child: _DangerSignsBanner(
                          signs: result.dangerSignsPresent,
                        ),
                      ),
                      const SizedBox(height: Gap.lg),
                    ],

                    // --------------------------------------- The verdict
                    // The whole assessment as one premium moment: the
                    // severity-coloured hero, IMCI level chip, the
                    // classification, one-line rationale and the
                    // data-confidence ring. Colour is the first sentence;
                    // the words only confirm it.
                    _Entrance(
                      index: 1,
                      child: ClinicalDecisionHeader(
                        classification: _classificationOf(plan),
                        level: effective,
                        onNext: () => setState(() => _view = 1),
                        missingCount: plan.missingData.length,
                        rationale: plan.triageRationale,
                        audio: AudioButton(
                          text:
                              '${_classificationOf(plan)}. '
                              '${plan.triageRationale}',
                          language: input.user.preferredLanguage,
                          id: 'result_verdict',
                          // The bank languages: the level's family
                          // message, not the clinical classification —
                          // the mother hears the sentence she can act
                          // on, in her language.
                          bankClips: _levelClip == null
                              ? null
                              : [_levelClip!.id],
                          compact: true,
                        ),
                        overrideNote: _override == null
                            ? null
                            : _OverrideNote(
                                engine: plan.overallTriage,
                                chosen: effective,
                              ),
                      ),
                    ),

                    // ------------------------- The decision, handoff-ready
                    // One structured card a receiving clinician can act on
                    // without scrolling: what was found, the honest AI
                    // line, and the plan of action. Every number on it
                    // appears nowhere else on this page.
                    _Entrance(
                      index: 2,
                      child: Padding(
                        padding: const EdgeInsets.only(top: Gap.md),
                        child: _DecisionBriefCard(
                          level: effective,
                          classification: _classificationOf(plan),
                          plan: plan,
                          drivers: plan.topDrivers,
                          aiLine: null,
                          trajectory: _trajectory,
                          needsReferral: _refer,
                          onOpenReport: () => setState(() => _view = 3),
                        ),
                      ),
                    ),

                    const SizedBox(height: Gap.md),

                    ResearchAnalysisPanel(
                      predictions: _mlPredictions,
                      statuses: _modelStatuses,
                      onEdit: () => Navigator.of(context).pop(),
                    ),

                    // ------------------------------- The measured numbers
                    // The verdict is a conclusion; these are its evidence.
                    // Every value this visit actually measured sits under
                    // the verdict with the cut-off it crossed.
                    _Entrance(
                      index: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _VitalsStrip(findings: plan.findings),
                          const RecHairline(),

                          // -------------------------------------- What we found
                          // The findings as severity-coloured cards: each one wears
                          // the IMCI colour of its severity, its measured number and
                          // its cut-off — the verdict is shown, not asserted.
                          RecSection(
                            title: 'What we found',
                            icon: Icons.assignment_turned_in_outlined,
                            subtitle:
                                'Each card wears the colour of its severity — red '
                                'refers, amber watches, green continues routine care.',
                            child: _FindingsDeck(
                              findings: _verdictFindings(plan.findings),
                              totalCount: plan.findings.length,
                            ),
                          ),

                          // --------------------- The slope, not just today
                          // A child with earlier measurements gets the
                          // trajectory at the moment of decision: the
                          // direction of travel a paper card cannot show.
                          if (_trajectory != null) ...[
                            const SizedBox(height: Gap.lg),
                            _TrajectoryCard(result: _trajectory!),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: Gap.lg),

                    // ------------------------- The care plan, one tap away
                    // The recommendations live behind one deliberate tap: the
                    // nurse reads what the assessment found first, then opens
                    // what to do about it.
                    _Entrance(
                      index: 4,
                      child: _RecommendationsCta(
                        actionsCount: plan.actions.length,
                        needsReferral: _refer,
                        followUpInDays: plan.followUpInDays,
                        onOpen: () => setState(() => _view = 1),
                      ),
                    ),
                    const SizedBox(height: Gap.md),

                    // ------------------------- The food plan, one tap away
                    // Nutrition is the half of the decision the family lives
                    // on, so it gets its own doorway on the verdict page —
                    // pictured foods leading, impossible to miss.
                    if (nutrition != null) ...[
                      _Entrance(
                        index: 4,
                        child: _NutritionCta(
                          onOpen: () => setState(() => _view = 2),
                        ),
                      ),
                      const SizedBox(height: Gap.md),
                    ],

                    // ---------------------- What to say before they leave
                    // The verdict translated into the sentence the family
                    // carries home — plain words, speakable aloud, with
                    // the return date attached.
                    _Entrance(
                      index: 5,
                      child: _FamilyBrief(
                        message: plan.caregiverMessage ?? plan.summary,
                        followUpInDays: plan.followUpInDays,
                        audio: AudioButton(
                          text: plan.caregiverMessage ?? plan.summary,
                          language: input.user.preferredLanguage,
                          id: 'result_family_brief',
                          bankClips: _levelClip == null
                              ? null
                              : [_levelClip!.id],
                          compact: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: Gap.md),

                    // ----------------------------- The report, one tap away
                    _Entrance(
                      index: 6,
                      child: _ReportTeaser(
                        findingsCount: plan.findings.length,
                        actionsCount: plan.actions.length,
                        needsReferral: _refer,
                        onOpen: () => setState(() => _view = 3),
                      ),
                    ),
                    const SizedBox(height: Gap.xxl),
                  ],
                ),
              )
            : _view == 2
            ? KeyedSubtree(
                key: const ValueKey('nutrition'),
                child: ListView(
                  padding: const EdgeInsets.all(Gap.lg),
                  children: [
                    // Who this basket was chosen for, before the food:
                    // the cohort callout leads the page exactly as it
                    // leads the care plan.
                    if (plan.patientCohort != null &&
                        plan.cohortNote != null) ...[
                      CohortCallout(
                        cohort: plan.patientCohort!,
                        note: plan.cohortNote!,
                      ),
                      const SizedBox(height: Gap.lg),
                    ],
                    if (nutrition != null)
                      NutritionRecSection(
                        plan: nutrition,
                        cost: _cost,
                        onCost: (tier) {
                          setState(() => _cost = tier);
                        },
                      )
                    else
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(Gap.md),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(Gap.radiusSm),
                          border: Border.all(color: AppColors.line),
                        ),
                        child: const Text(
                          'No tailored food plan for this visit — the model '
                          'withholds food counselling when it is not safe '
                          'or not applicable.',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.inkMuted,
                            height: 1.45,
                          ),
                        ),
                      ),
                    const SizedBox(height: Gap.lg),
                    // The evidence stays one tap away here too.
                    Center(
                      child: TextButton.icon(
                        onPressed: () => setState(() => _view = 3),
                        icon: const Icon(Icons.description_outlined, size: 17),
                        label: const Text('Open full clinical report'),
                      ),
                    ),
                    const SizedBox(height: Gap.xxl),
                  ],
                ),
              )
            : _view == 3
            ? KeyedSubtree(
                key: const ValueKey('report'),
                child: ListView(
                  padding: const EdgeInsets.all(Gap.lg),
                  children: [
                    // ------------------------------------------ Handoff summary
                    // The report stands alone: a receiving clinician reads
                    // this card in five seconds — verdict, drivers, the
                    // honest AI line, and what to do — before the evidence
                    // unfolds below. Deliberately self-contained: a handoff
                    // document must not ask its reader to open other pages.
                    Padding(
                      padding: const EdgeInsets.only(bottom: Gap.lg),
                      child: _HandoffSummary(
                        level: effective,
                        classification: _classificationOf(plan),
                        plan: plan,
                        // Protocol findings only: the AI's number already
                        // speaks exactly once in the AI-check line below,
                        // and the full findings list follows in this same
                        // report. One fact, one place — even in the handoff.
                        drivers: plan.topDrivers
                            .where((f) => !f.aiGenerated)
                            .toList(growable: false),
                        aiLine: null,
                        needsReferral: _refer,
                      ),
                    ),

                    // ------------------------------------------- Why this verdict
                    // The explainability anchor, stripped to what changes behaviour:
                    // the one-line rationale, any safety net that fired, the findings
                    // that drove the verdict (drivers first, the rest one tap away),
                    // and — in the open — what was not measured.
                    RecSection(
                      title: 'Why this result',
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
                          if (plan.guardrailEscalated) ...[
                            const SizedBox(height: Gap.md),
                            const SafetyNetNote(
                              text:
                                  'Safety net: a danger sign was detected, so this '
                                  'plan was raised to urgent automatically.',
                            ),
                          ],
                          if (plan.referralGuaranteed) ...[
                            const SizedBox(height: Gap.md),
                            const SafetyNetNote(
                              text:
                                  'Safety net: an urgent verdict always carries a '
                                  'referral — one was added because none was listed.',
                            ),
                          ],
                          if (plan.interactions.isNotEmpty) ...[
                            const SizedBox(height: Gap.md),
                            for (final i in plan.interactions)
                              FindingTile(
                                label: i.label,
                                detail: i.detail,
                                severity: i.severity,
                                source: i.protocolSource,
                              ),
                          ],
                          if (plan.findings.isNotEmpty) ...[
                            const SizedBox(height: Gap.md),
                            for (final f in _displayFindings(plan.findings))
                              FindingTile(
                                label: f.label,
                                detail: f.detail,
                                severity: f.severity,
                                source: f.protocolSource,
                                measured: f.measuredValue,
                                threshold: f.threshold,
                              ),
                            if (plan.findings.length > 3)
                              TextButton(
                                onPressed: () => setState(
                                  () => _showAllFindings = !_showAllFindings,
                                ),
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(0, Gap.tapTarget),
                                ),
                                child: Text(
                                  _showAllFindings
                                      ? 'Show only the drivers'
                                      : 'Show all ${plan.findings.length} findings',
                                ),
                              ),
                          ],
                          if (plan.missingData.isNotEmpty) ...[
                            const SizedBox(height: Gap.sm),
                            Text(
                              'Not measured: ${plan.missingData.join(', ')}. '
                              'These are input-completeness gaps. The protocol '
                              'still acts on observed danger signs.',
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
                    const RecHairline(),

                    ResearchAnalysisPanel(
                      predictions: _mlPredictions,
                      statuses: _modelStatuses,
                      showEvidence: true,
                      onEdit: () => Navigator.of(context).pop(),
                    ),

                    // --------------------------- The flywheel, one tap wide
                    // The CHO's word on the verdict, captured in one slim
                    // strip at the end of the evidence — never a modal, never
                    // a chore. On-device, de-identified, out of the way.
                    const SizedBox(height: Gap.lg),
                    _VerdictFeedbackStrip(
                      clientType: _exportClientStream(result.clientType),
                      engineTriage: plan.overallTriage.name,
                      finalTriage: effective.name,
                    ),
                    const SizedBox(height: Gap.xxl),
                  ],
                ),
              )
            : KeyedSubtree(
                key: const ValueKey('careplan'),
                child: ListView(
                  padding: const EdgeInsets.all(Gap.lg),
                  children: [
                    const Text(
                      'Protocol action worklist',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),

                    // ----------------------------------- Tailored plan
                    // Who this plan is for, before what to do: the
                    // synthesizer names the cohort and its deterioration
                    // pattern, so the same screen reads differently for a
                    // newborn, a child under five and a mother.
                    if (plan.patientCohort != null &&
                        plan.cohortNote != null) ...[
                      const SizedBox(height: Gap.lg),
                      _Entrance(
                        child: CohortCallout(
                          cohort: plan.patientCohort!,
                          note: plan.cohortNote!,
                        ),
                      ),
                    ],

                    // ------------------------------------- Do this now
                    // The worklist is the decision: numbered, tickable,
                    // urgency-tagged, and speakable in the worker's
                    // language — what the CHO acts on before leaving the
                    // compound. One deliberate tap away, behind the results:
                    // the nurse reads the verdict first.
                    if (plan.actions.isNotEmpty) ...[
                      const SizedBox(height: Gap.lg),
                      _Entrance(
                        index: 1,
                        child: RecSection(
                          title: 'Prioritized actions',
                          icon: Icons.checklist_rounded,
                          trailing: AudioButton(
                            text:
                                'What to do. '
                                '${plan.actions.map((a) => a.instruction).join('. ')}.',
                            language: input.user.preferredLanguage,
                            id: 'result_actions',
                            compact: true,
                          ),
                          child: ActionWorklist(
                            actions: plan.actions,
                            completed: _completedActions,
                            onCompletedChanged: (values) => setState(() {
                              _completedActions
                                ..clear()
                                ..addAll(values);
                            }),
                          ),
                        ),
                      ),
                    ],

                    // ------------------------------------------------------- Referral
                    const SizedBox(height: Gap.lg),
                    _Entrance(
                      index: 2,
                      child: _ReferralSection(
                        refer: _refer,
                        onRefer: (v) => setState(() {
                          _refer = v;
                        }),
                        facilities: _adequateFacilities(),
                        facility: _facility,
                        onFacility: (f) => setState(() => _facility = f),
                        urgency: _urgency,
                        onUrgency: (u) => setState(() => _urgency = u),
                        capabilities: result.referralCapabilitiesNeeded,
                      ),
                    ),

                    // ------------------------------------------------------ Follow-up
                    const SizedBox(height: Gap.lg),
                    _Entrance(
                      index: 3,
                      child: RecSection(
                        title: 'Follow-up contact',
                        icon: Icons.event_repeat_outlined,
                        subtitle:
                            'Added to your queue. The worker who started this case '
                            'should be the one who closes it.',
                        child: ChoiceChipsField<int>(
                          label: 'Review in',
                          options: const [1, 2, 3, 7, 14, 30],
                          labelOf: (d) => '$d day${d == 1 ? '' : 's'}',
                          value: _followDays,
                          onChanged: (d) =>
                              setState(() => _followDays = d ?? 7),
                        ),
                      ),
                    ),

                    // ---------------- Secondary care, quietly collapsible
                    // Early learning, nurturing care and the immunisation
                    // detail are important but rarely the fire: they wait
                    // in collapsible cards so the page the nurse works
                    // stays short. Any dose due today already sits in the
                    // worklist above.
                    if (result.clientType == ClientType.newborn ||
                        result.clientType == ClientType.childUnderFive) ...[
                      const SizedBox(height: Gap.lg),
                      _Entrance(
                        index: 4,
                        child: EarlyLearningRecSection(
                          person: input.person,
                          collapsible: true,
                        ),
                      ),
                    ],

                    // -------------------------------- UNICEF Nurturing Care (PILLAR 3)
                    if (nurturingCare.isNotEmpty &&
                        (result.clientType == ClientType.newborn ||
                            result.clientType == ClientType.childUnderFive ||
                            result.clientType == ClientType.pregnantWoman ||
                            result.clientType ==
                                ClientType.postpartumWoman)) ...[
                      const SizedBox(height: Gap.md),
                      _Entrance(
                        index: 4,
                        child: NurturingCareRecSection(
                          assessment: nurturingCare,
                          collapsible: true,
                        ),
                      ),
                    ],

                    // -------------------------------------------------- Immunisation
                    if (immunisation != null) ...[
                      const SizedBox(height: Gap.md),
                      _Entrance(
                        index: 4,
                        child: ImmunisationRecSection(
                          plan: immunisation,
                          collapsible: true,
                        ),
                      ),
                    ],

                    // ------------------------- The food plan, one doorway
                    // The full nutrition plan lives on its own page; here a
                    // single pictured doorway — never an inline duplicate
                    // of the plan the verdict already links to.
                    if (nutrition != null) ...[
                      const SizedBox(height: Gap.lg),
                      _Entrance(
                        index: 5,
                        child: _NutritionCta(
                          onOpen: () => setState(() => _view = 2),
                        ),
                      ),
                    ],

                    // ------------------------------------------------ Clinical override
                    // Demoted to one quiet line: the verdict owns the screen. Only
                    // when the worker disagrees does the override form unfold —
                    // saved with their name, reviewable by a supervisor.
                    if (input.user.can(
                      Permission.overrideAiRecommendation,
                    )) ...[
                      const SizedBox(height: Gap.md),
                      if (!_showOverride)
                        Center(
                          child: TextButton(
                            onPressed: () =>
                                setState(() => _showOverride = true),
                            child: const Text(
                              'Disagree with this plan? Record a clinical override',
                            ),
                          ),
                        )
                      else
                        _OverrideSection(
                          engineTriage: plan.overallTriage,
                          overrideLevel: _override,
                          reasonController: _overrideReason,
                          onOverride: (level) {
                            setState(() {
                              _override = level;
                              if (level == TriageLevel.urgent) {
                                _refer = true;
                                _urgency = ReferralUrgency.immediate;
                              }
                            });
                          },
                        ),
                    ],

                    if (_error != null) ...[
                      const SizedBox(height: Gap.md),
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

                    // ------------------------ The evidence, still one tap away
                    Center(
                      child: TextButton.icon(
                        onPressed: () => setState(() => _view = 3),
                        icon: const Icon(Icons.description_outlined, size: 17),
                        label: const Text('Open full clinical report'),
                      ),
                    ),
                    const SizedBox(height: Gap.xxl),
                  ],
                ),
              ),
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

// -------------------------------------------------------------- Verdict hero

/// The verdict as one premium moment: the deep royal hero (the brand's
/// authority voice), the IMCI level chip (the safety colours, untouched),
/// the classification in large type, the data-confidence ring, and the
/// honesty meta line. This is the card the nurse remembers — and the one
/// card that carries the entire decision.
/// The handoff card — the piece a receiving doctor reads and can defend.
///
/// The verdict page states each fact exactly once: the hero speaks the
/// verdict, this card *defends* it (the drivers with their measured
/// numbers, the honest AI line), then states what happens next and what
/// was not measured. Nothing here repeats the hero; the measured values
/// here are the only place the driver numbers appear outside the deck.
class _DecisionBriefCard extends StatelessWidget {
  const _DecisionBriefCard({
    required this.level,
    required this.classification,
    required this.plan,
    required this.drivers,
    required this.aiLine,
    required this.trajectory,
    required this.needsReferral,
    required this.onOpenReport,
  });

  final TriageLevel level;
  final String classification;
  final CarePlan plan;
  final List<ClinicalFinding> drivers;
  final String? aiLine;
  final TrajectoryResult? trajectory;
  final bool needsReferral;
  final VoidCallback onOpenReport;

  @override
  Widget build(BuildContext context) {
    final c = triageColours(level);
    final shown = drivers.take(2).toList(growable: false);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Gap.radius),
        border: Border.all(color: AppColors.line),
        boxShadow: const [AppShadows.card],
      ),
      child: AccentEdge(
        accent: c.fg,
        width: 3,
        borderRadius: BorderRadius.circular(Gap.radius),
        child: Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'CLINICAL DECISION BRIEF',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                  color: AppColors.inkMuted,
                ),
              ),
              const SizedBox(height: Gap.sm),
              // THE DECISION — one line, handoff-ready.
              Text(
                classification,
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                needsReferral
                    ? 'A referral is issued — this brief travels with the child.'
                    : 'Care continues here, under the plan this verdict opens.',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.inkMuted,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: Gap.md),
              const Divider(height: 1, thickness: 1, color: AppColors.line),
              const SizedBox(height: Gap.md),
              // WHAT DROVE IT — the drivers with their measured numbers:
              // the sentence a supervisor can audit against the card.
              _BriefEyebrow(text: 'What drove it', icon: Icons.flag_outlined),
              const SizedBox(height: Gap.xs),
              if (shown.isEmpty)
                const _BriefLine(
                  'No single number led this verdict — the protocol rules '
                  'carried it.',
                )
              else
                for (final f in shown)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.only(top: 6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: triageColours(f.severity).fg,
                          ),
                        ),
                        const SizedBox(width: Gap.sm),
                        Expanded(
                          child: Text(
                            f.measuredValue == null
                                ? f.detail
                                : '${f.label} — ${f.measuredValue}'
                                      '${f.threshold == null ? '' : ' (cut-off ${f.threshold})'}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              if (aiLine != null) ...[
                const SizedBox(height: Gap.md),
                // THE AI CHECK — one honest sentence, never a second copy
                // of the number: the full evidence sits in the report.
                _BriefEyebrow(text: 'The AI check', icon: Icons.memory_rounded),
                const SizedBox(height: Gap.xs),
                _BriefLine(aiLine!),
              ],
              const SizedBox(height: Gap.md),
              // ACT NOW — the next physical step, then the return date.
              _BriefEyebrow(text: 'Act now', icon: Icons.double_arrow_rounded),
              const SizedBox(height: Gap.xs),
              _BriefLine(
                needsReferral
                    ? 'Refer. Give the pre-transport steps above first, then '
                          'send this brief and the full report with the child.'
                    : 'Open the care plan below and work through it in order.',
              ),
              if (plan.followUpInDays != null) ...[
                const SizedBox(height: 3),
                _BriefLine(
                  'Re-check in ${plan.followUpInDays} '
                  'day${plan.followUpInDays == 1 ? '' : 's'}.',
                ),
              ],
              if (trajectory != null) ...[
                const SizedBox(height: Gap.md),
                // DIRECTION OF TRAVEL — the word, not the numbers: the
                // slope is charted once, in the trajectory card below.
                _BriefEyebrow(
                  text: 'Direction of travel',
                  icon: Icons.trending_up_rounded,
                ),
                const SizedBox(height: Gap.xs),
                _BriefLine(
                  'The growth trend is ${trajectory!.trend.label.toLowerCase()} '
                  '— the slope is charted below.',
                ),
              ],
              if (plan.missingData.isNotEmpty) ...[
                const SizedBox(height: Gap.md),
                // HONESTY ROW — what was not measured, in the open.
                _BriefEyebrow(
                  text: 'What we did not measure',
                  icon: Icons.help_outline_rounded,
                ),
                const SizedBox(height: Gap.xs),
                _BriefLine(
                  'Not measured: ${plan.missingData.join(', ')}. This lowers '
                  'input completeness; danger-sign care remains active.',
                ),
              ],
              const SizedBox(height: Gap.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onOpenReport,
                  icon: const Icon(Icons.description_outlined, size: 16),
                  label: const Text('Open the full evidence'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, Gap.tapTarget),
                    foregroundColor: c.fg,
                    padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A labelled eyebrow for one row of the decision brief.
class _BriefEyebrow extends StatelessWidget {
  const _BriefEyebrow({required this.text, required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 13, color: AppColors.inkMuted),
      const SizedBox(width: 5),
      Expanded(
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: AppColors.inkMuted,
          ),
        ),
      ),
    ],
  );
}

/// One quiet line of brief text.
class _BriefLine extends StatelessWidget {
  const _BriefLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
      color: AppColors.ink,
      height: 1.45,
    ),
  );
}

/// The report's opening statement, for the receiving clinician.
///
/// A doctor picking up this report reads one card before anything else:
/// the verdict, the ≤2 findings that drove it with their measured numbers,
/// the honest AI line, the first actions and the review date. Everything
/// on it is re-derived from the same engines as the verdict page — this
/// card re-words the decision for a handoff, it never invents a fact.
class _HandoffSummary extends StatelessWidget {
  const _HandoffSummary({
    required this.level,
    required this.classification,
    required this.plan,
    required this.drivers,
    required this.aiLine,
    required this.needsReferral,
  });

  final TriageLevel level;
  final String classification;
  final CarePlan plan;
  final List<ClinicalFinding> drivers;
  final String? aiLine;
  final bool needsReferral;

  @override
  Widget build(BuildContext context) {
    final c = triageColours(level);
    final shown = drivers.take(2).toList(growable: false);
    final actions = plan.actions.take(2).toList(growable: false);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Gap.radius),
        border: Border.all(color: AppColors.line),
        boxShadow: const [AppShadows.card],
      ),
      child: Container(
        // The verdict colour rides the left edge as a border, not as an
        // AccentEdge: the IntrinsicHeight inside AccentEdge forces
        // tight-height layout passes on this card, and a handoff document
        // is exactly the kind of card that grows tall in a scrollable
        // list. Same accent edge, none of the intrinsic machinery.
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Gap.radius),
          border: Border(left: BorderSide(color: c.fg, width: 3)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'HANDOFF SUMMARY',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.4,
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ),
                  // The chip carries the verdict word: it may wrap inside a
                  // bounded width, but it can never push past the card edge —
                  // long classifications are exactly when the chip matters.
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Gap.sm,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: c.bg,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Center(
                        child: Text(
                          // The one-word verdict, never the full sentence —
                          // the sentence lives in the classification line
                          // below, and a chip must stay chip-sized.
                          level.name.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: c.fg,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              const Text(
                'For the receiving clinician — the full evidence follows below.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppColors.inkMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: Gap.md),
              const Divider(height: 1, thickness: 1, color: AppColors.line),
              const SizedBox(height: Gap.md),
              Text(
                classification,
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                needsReferral
                    ? 'Referral issued — pre-referral steps are listed in this report.'
                    : 'Managed here — review date on the plan.',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.inkMuted,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
              if (shown.isNotEmpty) ...[
                const SizedBox(height: Gap.md),
                const _BriefEyebrow(
                  text: 'Drove the verdict',
                  icon: Icons.flag_outlined,
                ),
                const SizedBox(height: Gap.xs),
                for (final f in shown)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: _BriefLine(
                      f.measuredValue == null
                          ? f.detail
                          : '${f.label} — ${f.measuredValue}'
                                '${f.threshold == null ? '' : ' (cut-off ${f.threshold})'}',
                    ),
                  ),
              ] else ...[
                const SizedBox(height: Gap.md),
                const _BriefEyebrow(
                  text: 'Drove the verdict',
                  icon: Icons.flag_outlined,
                ),
                const SizedBox(height: Gap.xs),
                const _BriefLine(
                  'No measured number led — the protocol rules carried this '
                  'verdict.',
                ),
              ],
              if (aiLine != null) ...[
                const SizedBox(height: Gap.md),
                const _BriefEyebrow(
                  text: 'The AI check',
                  icon: Icons.memory_rounded,
                ),
                const SizedBox(height: Gap.xs),
                _BriefLine(aiLine!),
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: Gap.md),
                const _BriefEyebrow(
                  text: 'Do now',
                  icon: Icons.double_arrow_rounded,
                ),
                const SizedBox(height: Gap.xs),
                for (final a in actions)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: _BriefLine('• ${a.instruction}'),
                  ),
              ],
              if (plan.followUpInDays != null) ...[
                const SizedBox(height: Gap.md),
                _BriefLine(
                  'Review in ${plan.followUpInDays} '
                  'day${plan.followUpInDays == 1 ? '' : 's'}.',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The flywheel in one slim strip: did the verdict hold up?
///
/// One question, two taps, no modal. The answer lands in the on-device
/// [VerdictFeedbackStore] beside the engine/final triage pair — the gap
/// between what the engine said and what the CHO let stand is the most
/// valuable training signal the next model review gets. Storage failures
/// are swallowed: capturing feedback must never interrupt care.
class _VerdictFeedbackStrip extends StatefulWidget {
  const _VerdictFeedbackStrip({
    required this.clientType,
    required this.engineTriage,
    required this.finalTriage,
  });

  final String clientType;
  final String engineTriage;
  final String finalTriage;

  @override
  State<_VerdictFeedbackStrip> createState() => _VerdictFeedbackStripState();
}

class _VerdictFeedbackStripState extends State<_VerdictFeedbackStrip> {
  bool? _answer;

  Future<void> _record(bool correct) async {
    setState(() => _answer = correct);
    try {
      final store = await VerdictFeedbackStore.forDevice();
      await store?.append(
        clientType: widget.clientType,
        engineTriage: widget.engineTriage,
        finalTriage: widget.finalTriage,
        correct: correct,
      );
    } catch (_) {
      // Deliberately silent — see the class doc.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Gap.radiusSm),
        border: Border.all(color: AppColors.line),
      ),
      child: _answer == null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Did this plan match your clinical judgment? Feedback is '
                  'decision audit data, not a confirmed diagnosis.',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                    height: 1.4,
                  ),
                ),
                // Each button flexes to its half of the strip, so long
                // translations can never push the pair past the card edge.
                Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () => _record(true),
                        icon: const Icon(Icons.thumb_up_outlined, size: 15),
                        label: const Text('It held up'),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, Gap.tapTarget),
                          foregroundColor: AppColors.triageGreen,
                          padding: const EdgeInsets.symmetric(
                            horizontal: Gap.sm,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () => _record(false),
                        icon: const Icon(Icons.thumb_down_outlined, size: 15),
                        label: const Text("It didn't"),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, Gap.tapTarget),
                          foregroundColor: AppColors.triageAmber,
                          padding: const EdgeInsets.symmetric(
                            horizontal: Gap.sm,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  size: 16,
                  color: _answer!
                      ? AppColors.triageGreen
                      : AppColors.triageAmber,
                ),
                const SizedBox(width: Gap.sm),
                const Expanded(
                  child: Text(
                    'Thank you — logged on this device, de-identified, for '
                    'the next model review.',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.inkMuted,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Entrance extends StatefulWidget {
  const _Entrance({required this.child, this.index = 0});

  final Widget child;
  final int index;

  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance>
    with SingleTickerProviderStateMixin {
  static const _beat = Duration(milliseconds: 90);

  late final AnimationController _controller;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: AppMotion.duration,
      vsync: this,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final delay = _beat * widget.index;
    if (delay == Duration.zero || MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      Future<void>.delayed(delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) {
      final t = CurvedAnimation(
        parent: _controller,
        curve: AppMotion.curve,
      ).value;
      return Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - t)),
          child: child,
        ),
      );
    },
    child: widget.child,
  );
}

// ---------------------------------------------------------- Findings deck

/// The findings as severity-coloured cards.
///
/// Colour here is clinical, never decorative: every card wears the IMCI band
/// of the finding it carries, so a nurse scanning the deck reads the severity
/// before she reads a single word.
class _FindingsDeck extends StatelessWidget {
  const _FindingsDeck({required this.findings, required this.totalCount});

  final List<ClinicalFinding> findings;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    if (findings.isEmpty) return const _AllClearCard();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final f in findings) _FindingCard(finding: f),
        if (totalCount > findings.length)
          Padding(
            padding: const EdgeInsets.only(top: Gap.xs, left: Gap.xs),
            child: Text(
              '${totalCount - findings.length} more '
              '${totalCount - findings.length == 1 ? 'finding' : 'findings'} '
              '— the full clinical report lists them all.',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.inkMuted,
                height: 1.4,
              ),
            ),
          ),
      ],
    );
  }
}

/// The routine-verdict card: green, calm, explicit. An empty deck must still
/// say something — "nothing needs treatment today" is itself a decision.
class _AllClearCard extends StatelessWidget {
  const _AllClearCard();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(Gap.lg),
    decoration: BoxDecoration(
      color: AppColors.triageGreenBg,
      borderRadius: BorderRadius.circular(Gap.radius),
      border: Border.all(
        color: AppColors.triageGreen.withValues(alpha: 0.35),
        width: Gap.hairline,
      ),
    ),
    child: Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_circle_rounded,
            size: 24,
            color: AppColors.triageGreen,
          ),
        ),
        const SizedBox(width: Gap.md),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'No concerning findings',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.triageGreen,
                ),
              ),
              SizedBox(height: 3),
              Text(
                'Routine care continues at the next scheduled contact.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.inkMuted,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// One finding as a card: the severity badge, the IMCI pill, the measured
/// number against its cut-off. The colour is the finding's own triage band —
/// the same red/amber/green the protocol prints, never a decorative palette.
class _FindingCard extends StatelessWidget {
  const _FindingCard({required this.finding});

  final ClinicalFinding finding;

  @override
  Widget build(BuildContext context) {
    final c = triageColours(finding.severity);
    return Container(
      margin: const EdgeInsets.only(bottom: Gap.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Gap.radius),
        border: Border.all(color: AppColors.line, width: Gap.hairline),
        boxShadow: const [AppShadows.card],
      ),
      child: AccentEdge(
        accent: c.fg,
        width: 3,
        borderRadius: BorderRadius.circular(Gap.radius),
        child: Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: c.bg,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      triageIcon(finding.severity),
                      size: 20,
                      color: c.fg,
                    ),
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          finding.label,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                            height: 1.3,
                          ),
                        ),
                        if (finding.protocolSource != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            finding.protocolSource!,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                              color: AppColors.inkMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: Gap.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Gap.sm,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: c.fg,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      // The single-word band (URGENT / PRIORITY / WATCH /
                      // ROUTINE), never the full sentence label — a pill
                      // must stay a pill at 308px card width.
                      finding.severity.name.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Gap.sm),
              Padding(
                padding: const EdgeInsets.only(left: 50),
                child: Text(
                  finding.detail,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.inkMuted,
                    height: 1.45,
                  ),
                ),
              ),
              if (finding.measuredValue != null || finding.threshold != null)
                Padding(
                  padding: const EdgeInsets.only(left: 50, top: Gap.sm),
                  child: Wrap(
                    spacing: Gap.sm,
                    runSpacing: Gap.xs,
                    children: [
                      if (finding.measuredValue != null)
                        _MeasureChip(
                          label: 'Measured',
                          value: finding.measuredValue!,
                          colour: c.fg,
                        ),
                      if (finding.threshold != null)
                        _MeasureChip(
                          label: 'Cut-off',
                          value: finding.threshold!,
                          colour: AppColors.inkMuted,
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One "measured vs cut-off" chip on a finding card.
class _MeasureChip extends StatelessWidget {
  const _MeasureChip({
    required this.label,
    required this.value,
    required this.colour,
  });

  final String label;
  final String value;
  final Color colour;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: AppColors.canvas,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text.rich(
      TextSpan(
        text: '$label ',
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: AppColors.inkMuted,
        ),
        children: [
          TextSpan(
            text: value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: colour,
            ),
          ),
        ],
      ),
    ),
  );
}

/// The doorway into the care plan: the verdict is read first, the
/// recommendations open as their own page — never a wall to scroll past.
/// The danger signs this assessment found, stated before anything else.
/// In IMCI, any one general danger sign reclassifies the child upward —
/// the banner makes that weight visible in red, with the instruction to
/// act before the family leaves.
class _DangerSignsBanner extends StatelessWidget {
  const _DangerSignsBanner({required this.signs});

  final List<String> signs;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(Gap.lg),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF8F1D1D), AppColors.triageRed],
      ),
      borderRadius: BorderRadius.circular(Gap.radius + 6),
      boxShadow: const [
        BoxShadow(
          color: Color(0x59D32F2F),
          blurRadius: 30,
          offset: Offset(0, 14),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                size: 20,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: Gap.sm),
            const Expanded(
              child: Text(
                'DANGER SIGNS PRESENT',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.md),
        Wrap(
          spacing: Gap.xs,
          runSpacing: Gap.xs,
          children: [
            for (final sign in signs)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  sign,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.4,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: Gap.md),
        Text(
          'Any one of these signs makes this visit urgent — act before '
          'the family leaves.',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.85),
            height: 1.4,
          ),
        ),
      ],
    ),
  );
}

/// The measurements behind the verdict: every value this visit actually
/// recorded, with the cut-off it was judged against. A nurse defending
/// the result to a family — or to a referral facility — points here.
class _VitalsStrip extends StatelessWidget {
  const _VitalsStrip({required this.findings});

  final List<ClinicalFinding> findings;

  @override
  Widget build(BuildContext context) {
    final vitals = findings
        .where((f) => f.measuredValue != null)
        .take(6)
        .toList(growable: false);
    if (vitals.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Gap.radius),
        border: Border.all(color: AppColors.line, width: Gap.hairline),
        boxShadow: const [AppShadows.card],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.monitor_heart_outlined,
                size: 15,
                color: AppColors.primary,
              ),
              SizedBox(width: Gap.xs),
              Expanded(
                child: Text(
                  'THE NUMBERS BEHIND THE VERDICT',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                    color: AppColors.inkMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          Wrap(
            spacing: Gap.xs,
            runSpacing: Gap.xs,
            children: [
              for (final v in vitals)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.canvas,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: AppColors.line,
                      width: Gap.hairline,
                    ),
                  ),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${v.label}: ',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.inkMuted,
                          ),
                        ),
                        TextSpan(
                          text: v.measuredValue,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w900,
                            color: triageColours(v.severity).fg,
                          ),
                        ),
                        if (v.threshold != null)
                          TextSpan(
                            text: ' \u00b7 cut-off ${v.threshold}',
                            style: const TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.inkFaint,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The verdict translated into the sentence the family carries home —
/// plain words, speakable aloud in the caregiver's language, with the
/// return date attached. This is what the nurse says on the way out.
class _FamilyBrief extends StatelessWidget {
  const _FamilyBrief({
    required this.message,
    required this.followUpInDays,
    required this.audio,
  });

  final String message;
  final int? followUpInDays;
  final Widget audio;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(Gap.lg),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(Gap.radius + 6),
      border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      boxShadow: const [AppShadows.card],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.family_restroom_outlined,
                size: 20,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: Gap.sm),
            const Expanded(
              child: Text(
                'WHAT TO TELL THE FAMILY',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.7,
                  color: AppColors.primary,
                ),
              ),
            ),
            audio,
          ],
        ),
        const SizedBox(height: Gap.md),
        // The verdict as spoken words — quoted, because this is the
        // sentence the nurse says out loud on the way out.
        Text(
          '\u201C$message\u201D',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
            height: 1.55,
          ),
        ),
        if (followUpInDays != null) ...[
          const SizedBox(height: Gap.sm),
          Text(
            'Ask them to come back in $followUpInDays '
            'day${followUpInDays == 1 ? '' : 's'} — and sooner if '
            'anything worries them.',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.inkMuted,
              fontStyle: FontStyle.italic,
              height: 1.4,
            ),
          ),
        ],
      ],
    ),
  );
}

class _RecommendationsCta extends StatelessWidget {
  const _RecommendationsCta({
    required this.actionsCount,
    required this.needsReferral,
    required this.followUpInDays,
    required this.onOpen,
  });

  final int actionsCount;
  final bool needsReferral;
  final int? followUpInDays;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (actionsCount > 0)
        '$actionsCount ${actionsCount == 1 ? 'action' : 'actions'} to do now',
      if (needsReferral) 'a referral to arrange',
      if (followUpInDays != null)
        'review in $followUpInDays ${followUpInDays == 1 ? 'day' : 'days'}',
    ].join(' · ');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(Gap.radius),
        onTap: onOpen,
        child: Ink(
          decoration: BoxDecoration(
            gradient: AppColors.heroGradient,
            borderRadius: BorderRadius.circular(Gap.radius),
            boxShadow: const [
              BoxShadow(
                color: Color(0x3D1B56DB),
                blurRadius: 26,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(Gap.lg),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.checklist_rounded,
                    size: 22,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Show recommendations',
                        style: TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.75),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: Gap.sm),
                const Icon(
                  Icons.arrow_forward_rounded,
                  size: 20,
                  color: Colors.white,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The doorway to the tailored food plan: pictured local foods lead, so
/// the worker sees at a glance that this is the page with the pictures.
/// One tap from the verdict straight to the plate.
class _NutritionCta extends StatelessWidget {
  const _NutritionCta({required this.onOpen});

  final VoidCallback onOpen;

  static const _thumbs = [
    AppImages.foodMilletPorridge,
    AppImages.foodBoiledEgg,
    AppImages.foodGroundnutPaste,
    AppImages.foodPawpaw,
  ];

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(Gap.radius),
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.all(Gap.lg),
          decoration: BoxDecoration(
            color: AppColors.triageGreenBg,
            borderRadius: BorderRadius.circular(Gap.radius),
            border: Border.all(color: AppColors.accent, width: 1),
            boxShadow: const [AppShadows.card],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.restaurant_outlined,
                      size: 20,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: Gap.md),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Nutrition plan',
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'The foods for this person — pictured, measured, local',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.inkMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 20,
                    color: AppColors.accent,
                  ),
                ],
              ),
              const SizedBox(height: Gap.md),
              Row(
                children: [
                  for (final t in _thumbs) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(Gap.radiusXs),
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: AppImage(src: t),
                      ),
                    ),
                    const SizedBox(width: Gap.xs),
                  ],
                  const Expanded(
                    child: Text(
                      'Tap to open',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The care plan's opening line: who authored this plan. The on-device
/// TFLite models when they ran, the deterministic rules when they stood
/// in — one honest sentence on the brand's royal gradient, so the AI
/// story is told without a dashboard.
/// The doorway to the clinical report page: one elegant card naming what the
/// report holds, and the single button that opens it.
class _ReportTeaser extends StatelessWidget {
  const _ReportTeaser({
    required this.findingsCount,
    required this.actionsCount,
    required this.needsReferral,
    required this.onOpen,
  });

  final int findingsCount;
  final int actionsCount;
  final bool needsReferral;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Gap.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Gap.radius),
        border: Border.all(color: AppColors.line, width: Gap.hairline),
        boxShadow: const [AppShadows.card],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: AppColors.primaryLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.description_outlined,
                  size: 20,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Full clinical report',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'The evidence behind this verdict',
                      style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.md),
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            children: [
              _TeaserStat(
                label: '$findingsCount finding${findingsCount == 1 ? '' : 's'}',
              ),
              _TeaserStat(label: '$actionsCount-step plan'),
              _TeaserStat(
                label: needsReferral
                    ? 'Referral prepared'
                    : 'No referral needed',
              ),
              _TeaserStat(label: 'On-device AI evidence'),
            ],
          ),
          const SizedBox(height: Gap.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onOpen,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, Gap.tapTarget),
              ),
              child: const Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: Gap.sm,
                children: [
                  Text('Open full clinical report'),
                  Icon(Icons.arrow_forward_rounded, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One pill in the report teaser's stat strip.
class _TeaserStat extends StatelessWidget {
  const _TeaserStat({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: AppColors.canvas,
      border: Border.all(color: AppColors.line, width: Gap.hairline),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppColors.inkMuted,
      ),
    ),
  );
}

// ------------------------------------------------------------------ Override

/// The interactive "overrule the engine" card. Only shown to a user who holds
/// [Permission.overrideAiRecommendation]. Selecting a triage level records an
/// override; selecting it again (deselecting) returns to the engine's verdict.
class _OverrideSection extends StatefulWidget {
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
  State<_OverrideSection> createState() => _OverrideSectionState();
}

class _OverrideSectionState extends State<_OverrideSection>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _expandAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutQuart,
    );
    if (widget.overrideLevel != null) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(_OverrideSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.overrideLevel != null && oldWidget.overrideLevel == null) {
      _controller.forward();
    } else if (widget.overrideLevel == null &&
        oldWidget.overrideLevel != null) {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isActive = widget.overrideLevel != null;
    final accent = isActive ? AppColors.triageAmber : AppColors.inkMuted;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: isActive
            ? AppColors.triageAmberBg.withValues(alpha: 0.3)
            : Colors.white,
        borderRadius: BorderRadius.circular(Gap.radius),
        border: Border.all(
          color: isActive
              ? AppColors.triageAmber.withValues(alpha: 0.5)
              : AppColors.line,
          width: isActive ? 1.5 : Gap.hairline,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: AppColors.triageAmber.withValues(alpha: 0.1),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : const [AppShadows.card],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isActive ? Icons.gavel_rounded : Icons.shield_outlined,
                  size: 18,
                  color: accent,
                ),
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isActive
                          ? 'CLINICAL OVERRIDE ACTIVE'
                          : 'CLINICAL SAFEGUARD',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                        color: isActive
                            ? AppColors.triageAmber
                            : AppColors.inkMuted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isActive
                          ? 'You have taken accountability for this decision.'
                          : 'The protocol stands unless you overrule it.',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.inkFaint,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.md),
          ChoiceChipsField<TriageLevel>(
            label: 'Override the protocol decision?',
            why:
                'Engine\u2019s verdict: ${widget.engineTriage.label}. Tap a level to overrule; tap it again to keep the engine\u2019s.',
            options: TriageLevel.values,
            labelOf: (t) => t.label,
            value: widget.overrideLevel,
            onChanged: widget.onOverride,
          ),
          SizeTransition(
            sizeFactor: _expandAnimation,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: Gap.md),
                const FieldLabel(
                  'Clinical reason for overruling',
                  required: true,
                ),
                TextField(
                  controller: widget.reasonController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    hintText:
                        'e.g. Child appears unwell on examination — referring on clinical grounds.',
                    hintStyle: const TextStyle(
                      color: AppColors.inkFaint,
                      fontSize: 13,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Gap.radiusSm),
                      borderSide: const BorderSide(color: AppColors.line),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Gap.radiusSm),
                      borderSide: const BorderSide(color: AppColors.line),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Gap.radiusSm),
                      borderSide: const BorderSide(
                        color: AppColors.triageAmber,
                        width: 2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: Gap.sm),
                Row(
                  children: [
                    const Icon(
                      Icons.lock_outline,
                      size: 14,
                      color: AppColors.inkFaint,
                    ),
                    const SizedBox(width: 4),
                    const Expanded(
                      child: Text(
                        'Saved securely with your digital signature. A supervisor can review every override.',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.inkFaint,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
      decoration: BoxDecoration(
        color: AppColors.triageAmberBg,
        borderRadius: BorderRadius.circular(Gap.radiusSm),
      ),
      child: AccentEdge(
        accent: AppColors.triageAmber,
        borderRadius: BorderRadius.circular(Gap.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.md,
            vertical: Gap.sm,
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
        ),
      ),
    );
  }
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
  Widget build(BuildContext context) => RecSection(
    title: refer ? 'Referral' : 'Referral (off)',
    subtitle: refer
        ? 'The receiving facility must be able to do what this case needs.'
        : 'The protocol does not require a referral. Turn this on if clinical '
              'judgement says otherwise.',
    icon: refer ? Icons.local_hospital_outlined : Icons.local_hospital_outlined,
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

/// The growth slope at the moment of decision: a paper card shows the
/// points, never the direction. Rendered only when the trajectory engine
/// finds a real trend, coloured by where that trend is heading, and the
/// straight-line projection is stated as arithmetic the CHO can check.
class _TrajectoryCard extends StatelessWidget {
  const _TrajectoryCard({required this.result});

  final TrajectoryResult result;

  @override
  Widget build(BuildContext context) {
    final rising = result.trend == GrowthTrend.rising;
    final falling = result.trend == GrowthTrend.falling;
    final nearSam = (result.daysToSamThreshold ?? 10000) <= 60;
    final accent = rising
        ? AppColors.triageGreen
        : falling && nearSam
        ? AppColors.triageRed
        : AppColors.triageAmber;
    final icon = rising
        ? Icons.trending_up_rounded
        : falling
        ? Icons.trending_down_rounded
        : Icons.trending_flat_rounded;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Gap.radius),
        border: Border.all(color: AppColors.line, width: Gap.hairline),
        boxShadow: const [AppShadows.card],
      ),
      child: AccentEdge(
        accent: accent,
        width: 3,
        borderRadius: BorderRadius.circular(Gap.radius),
        child: Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 20, color: accent),
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'WHERE THIS CHILD IS HEADING',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                            color: AppColors.inkMuted,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          result.trend.label,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: accent,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Gap.sm),
              Text(
                result.trend.meaning,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                  height: 1.45,
                ),
              ),
              if (result.daysToSamThreshold != null) ...[
                const SizedBox(height: Gap.sm),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(Gap.sm + 2),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(Gap.radiusSm),
                  ),
                  child: Text(
                    'At this pace the 11.5 cm severe line is about '
                    '${result.daysToSamThreshold} days away — act while it '
                    'is still cheap to fix.',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: accent,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: Gap.sm),
              Text(
                result.explanation,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.inkMuted,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
