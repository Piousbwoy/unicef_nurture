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
import '../../core/ml/offline_inference_service.dart';
import '../../core/ml/recalibration_export.dart';
import '../../core/ml/recalibration_store.dart';
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
import '../../domain/engines/protocols/stabilization_protocols.dart';
import '../../domain/engines/recommendation_engine.dart';
import '../../domain/engines/treatment_response_engine.dart';
import '../../domain/entities/core.dart';
import '../../domain/entities/visit.dart';
import '../../domain/enums.dart';
import '../shared/app_image.dart';
import '../shared/audio_button.dart';
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

  // ------------------------------------------------------- Care-plan worklist
  /// Indices of plan actions the worker has ticked off (T3). A plan you can
  /// check off is a worklist, not a memo.
  final Set<int> _doneActions = {};

  // ---------------------------------------------------------------- Override
  /// The triage the CHO chose instead of the engine's, or null while the
  /// engine's verdict stands. Persisted with their name and reason — the human
  /// is accountable for the care, and the override is the honest training
  /// signal for the model.
  TriageLevel? _override;
  final _overrideReason = TextEditingController();
  late Future<Map<String, OfflineRiskPrediction>> _mlPredictions;
  Map<String, OfflineRiskPrediction>? _mlPredictionsValue;

  /// Model provenance (validation metrics, integrity, priors) loaded in
  /// parallel with the predictions — the evidence panel shows each number's
  /// precision and CI next to the risk itself.
  late Future<List<OfflineModelStatus>> _modelStatuses;

  /// Which evidence cards the CHO has unfolded.
  final Set<String> _openModels = {};
  bool _referTouched = false;

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
    final service = OfflineInferenceService.instance;
    final bag = _buildFeatureBag();
    // The TFLite models run FIRST, on-device: runAllPredictions feeds every
    // bag to the interpreter and only falls back to the deterministic rules
    // when a model cannot load or fails its integrity check. Model
    // provenance loads in parallel so the evidence panel can state each
    // number's precision without waiting on a second round-trip.
    _mlPredictions = service.runAllPredictions(bag);
    _modelStatuses = service.modelStatuses();
    _mlPredictions.then((p) {
      if (!mounted) return;
      setState(() {
        _mlPredictionsValue = p;
        if (!_referTouched) {
          final updated = _carePlan;
          if (updated.needsReferral) {
            _refer = true;
            _urgency = ReferralUrgency.immediate;
          }
        }
      });
    });
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

  OfflineFeatureBag _buildFeatureBag() {
    final inputs = draft.inputs;
    final maternal = input.maternal;
    final birth = input.birth;
    final isMaternal =
        result.clientType == ClientType.pregnantWoman ||
        inputs.containsKey('gestational_weeks');
    final int? ageDays =
        inputs['age_in_days'] as int? ?? input.person.ageInDays;
    final int? ageMonths =
        inputs['age_in_months'] as int? ?? input.person.ageInMonths;
    final computedAgeDays =
        ageDays ?? (ageMonths == null ? null : (ageMonths * 30.4375).round());
    final dangerSigns = inputs['danger_signs'] as List?;
    bool? hasSign(String name) =>
        dangerSigns == null ? null : dangerSigns.contains(name) == true;
    final muacCmRaw = inputs['muac_cm'];
    final int? muacMmFromCm = muacCmRaw is num
        ? (muacCmRaw * 10).round()
        : null;
    final int? muacMmDirect = inputs['muac_mm'] as int?;
    final int? anyMuacMm = muacMmDirect ?? muacMmFromCm;
    final temp = inputs['temperature_celsius'] as num?;
    return OfflineFeatureBag(
      ageDays: computedAgeDays,
      gestationalWeeksAtBirth: birth?.gestationWeeksAtBirth,
      heartRatePerMin: (inputs['pulse'] as num?)?.toInt(),
      respiratoryRatePerMin: (inputs['respiratory_rate'] as num?)?.toInt(),
      temperatureCelsius: temp?.toDouble(),
      oxygenSaturationPerCent: (inputs['oxygen_saturation'] as num?)?.toInt(),
      systolicBloodPressureMmhg: (inputs['systolic'] as num?)?.toInt(),
      diastolicBloodPressureMmhg: (inputs['diastolic'] as num?)?.toInt(),
      maternalMuacMm: isMaternal ? anyMuacMm : null,
      haemoglobinGDl: (inputs['haemoglobin'] as num?)?.toDouble(),
      urineProtein0To4:
          (inputs['proteinuria'] as int?) ?? (inputs['urine_protein'] as int?),
      urineKetones0To3: inputs['urine_ketones'] as int?,
      urineBlood0To3: inputs['urine_blood'] as int?,
      urineGlucose0To4: inputs['urine_glucose'] as int?,
      previousPregnancyLosses: maternal?.previousLosses,
      prevCaesareanSection: maternal?.previousCaesarean,
      maternalAgeYears: input.person.ageInYears,
      gravida: maternal?.gravida ?? (inputs['gravida'] as int?),
      parity: maternal?.parity,
      oedemaHandsOrFace: maternal?.oedemaHandsOrFace,
      epigastricPain: maternal?.epigastricPain,
      headacheSevere: maternal?.headacheSevere,
      blurredVision: maternal?.blurredVision,
      briskReflexes: maternal?.briskReflexes,
      oliguria: maternal?.oliguria,
      weightGainOver1kgPerWeek: maternal?.weightGainOver1kgPerWeek,
      birthWeightKg:
          (inputs['birth_weight_kg'] as num?)?.toDouble() ??
          birth?.birthWeightKg,
      birthLengthCm: birth?.birthLengthCm,
      apgar5Minute: birth?.apgar5Minute,
      historyOfConvulsions:
          birth?.historyOfConvulsions ?? hasSign('convulsions'),
      severeChestIndrawing: birth?.severeChestIndrawing ?? hasSign('indrawing'),
      nasalFlaring: birth?.nasalFlaring ?? hasSign('nasalFlaring'),
      grunting: birth?.grunting ?? hasSign('grunting'),
      bulgingFontanelle:
          birth?.bulgingFontanelle ?? hasSign('bulgingFontanelle'),
      jaundiceBefore24h: birth?.jaundiceBefore24h,
      feedingDifficulty:
          birth?.feedingDifficulty ?? hasSign('feedingDifficulty'),
      abdominalDistension:
          birth?.abdominalDistension ?? hasSign('abdominalDistension'),
      cordRednessBeyondBase: birth?.cordRednessBeyondBase,
      cordPus: birth?.cordPus,
      skinPustules: birth?.skinPustules ?? hasSign('skinPustules'),
      lethargicOrUnconscious:
          birth?.lethargicOrUnconscious ?? hasSign('lethargic'),
      bleedingFromAnySite: birth?.bleedingFromAnySite ?? hasSign('bleeding'),
      coughPresent: hasSign('cough'),
      chestIndrawing: hasSign('indrawing'),
      stridorCalm: hasSign('stridor'),
      generalDangerSign:
          hasSign('unconscious') ??
          hasSign('lethargic') ??
          hasSign('cannotDrink') ??
          hasSign('vomitsEverything'),
      multipleBirth: birth == null
          ? null
          : birth.plurality != BirthPlurality.singleton,
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
    final hbDouble = hb is num ? hb.toDouble() : null;
    final anaemic =
        (hb is num && hb < 11) ||
        draft.inputs['danger_signs'] is List &&
            ((draft.inputs['danger_signs'] as List).contains('pallorSevere') ||
                (draft.inputs['danger_signs'] as List).contains('pallorSome'));

    // Pillar 2: build the therapeutic context from the inputs + AI risk
    // (lbw_sga) so the supplement selector can pick MMS, IFA, RUTF, KMC.
    final birth = input.birth;
    final isPostpartum = result.clientType == ClientType.postpartumWoman;
    final gestationalWeeks = (draft.inputs['gestational_weeks'] as num?)
        ?.toInt();
    final ageDays =
        input.person.ageInDays ?? (draft.inputs['age_in_days'] as int? ?? 0);
    final birthWeightKg =
        (draft.inputs['birth_weight_kg'] as num?)?.toDouble() ??
        birth?.birthWeightKg;
    final lbwSgaRisk = _mlPredictionsValue?['lbw_sga']?.riskProbability;
    final therapeuticContext = TherapeuticContext(
      gestationalWeeks: gestationalWeeks,
      haemoglobinGDl: hbDouble,
      isPostpartum: isPostpartum,
      birthWeightKg:
          birthWeightKg ??
          (lbwSgaRisk != null && lbwSgaRisk >= 0.5 ? 2.3 : null),
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

    final ml = _mlPredictionsValue;
    if (ml != null) {
      final parts = _mlAsAssessmentParts(ml);
      extraFindings.addAll(parts.$1);
      extraActions.addAll(parts.$2);
    }

    return RecommendationEngine.synthesize(
      results: [result],
      extraFindings: extraFindings,
      extraActions: extraActions,
      stabilizationContext: _buildStabilizationContext(),
      stabilizationRisks: StabilizationAiRisks.fromPredictions(
        _mlPredictionsValue,
      ),
    );
  }

  /// Build the [StabilizationContext] used by the pre-referral protocol
  /// selector. The context is intentionally narrow — only the inputs the
  /// WHO/GHS triggers actually need (BP, danger signs, age, temperature)
  /// — so the selector is testable in isolation and the data flow stays
  /// audit-defensible.
  StabilizationContext _buildStabilizationContext() {
    final inputs = draft.inputs;
    final birth = input.birth;
    final int? ageDays =
        inputs['age_in_days'] as int? ?? input.person.ageInDays;
    final int? gestationalWeeks = (inputs['gestational_weeks'] as num?)
        ?.toInt();
    final dangerSigns = inputs['danger_signs'] as List?;
    bool hasSign(String name) =>
        dangerSigns is List && dangerSigns.contains(name) == true;
    return StabilizationContext(
      patientAgeDays: ageDays,
      gestationalWeeks: gestationalWeeks,
      systolicBp: (inputs['systolic'] as num?)?.toInt(),
      diastolicBp: (inputs['diastolic'] as num?)?.toInt(),
      urineProtein0To4:
          (inputs['proteinuria'] as int?) ?? (inputs['urine_protein'] as int?),
      hasEclampsiaConvulsions: hasSign('convulsions'),
      temperatureCelsius: (inputs['temperature_celsius'] as num?)?.toDouble(),
      oxygenSaturation: (inputs['oxygen_saturation'] as num?)?.toInt(),
      respiratoryRate: (inputs['respiratory_rate'] as num?)?.toInt(),
      unableToFeed: hasSign('cannotDrink'),
      convulsions:
          hasSign('convulsions') || (birth?.historyOfConvulsions ?? false),
      severeChestIndrawing:
          hasSign('indrawing') || (birth?.severeChestIndrawing ?? false),
      bulgingFontanelle:
          hasSign('bulgingFontanelle') || (birth?.bulgingFontanelle ?? false),
      lethargicOrUnconscious:
          hasSign('lethargic') || (birth?.lethargicOrUnconscious ?? false),
      historyOfConvulsions: birth?.historyOfConvulsions ?? false,
      cordPus: birth?.cordPus ?? false,
      feedingDifficulty:
          hasSign('feedingDifficulty') || (birth?.feedingDifficulty ?? false),
      skinPustules: hasSign('skinPustules') || (birth?.skinPustules ?? false),
      coughPresent: hasSign('cough'),
      generalDangerSign:
          hasSign('unconscious') ||
          hasSign('lethargic') ||
          hasSign('cannotDrink') ||
          hasSign('vomitsEverything'),
    );
  }

  (List<ClinicalFinding>, List<RecommendedAction>) _mlAsAssessmentParts(
    Map<String, OfflineRiskPrediction> ml,
  ) {
    final findings = <ClinicalFinding>[];
    final actions = <RecommendedAction>[];

    void addRisk({
      required String key,
      required String label,
      required String protocolSource,
      required TriageLevel severity,
      required ReferralUrgency? referralUrgency,
      required String referralInstruction,
      bool ruleInTier = false,
    }) {
      final p = ml[key];
      if (p == null) return;
      final rp = p.riskProbability;
      // Drift-suppressed: the AI is out of its training window, so no
      // AI-risk finding is shown; the deterministic rule findings below
      // carry this screen (and the stabilization selector) instead.
      if (rp == null) return;
      if (ruleInTier) {
        // Two-tier triage (neonatal sepsis): only a rule-in candidate
        // (probability >= the rule-in threshold on the 2%-prior scale)
        // produces the urgent AI finding. Below it the AI is the
        // screening tier and stays silent — the deterministic WHO/GHS
        // findings below keep the rule-out coverage.
        if (!p.ruleInCandidate) return;
      } else if (p.classification != 'high' && rp < 0.7) {
        return;
      }
      final via = p.usingModel ? 'TFLite' : 'offline calculator';
      findings.add(
        ClinicalFinding(
          label: label,
          detail: 'Risk ${(rp * 100).toStringAsFixed(0)}% ($via).',
          severity: severity,
          protocolSource: protocolSource,
          measuredValue: '${(rp * 100).toStringAsFixed(1)}%',
          threshold: ruleInTier && p.ruleInThreshold != null
              ? 'Rule-in ≥ ${(p.ruleInThreshold! * 100).toStringAsFixed(0)}%'
              : 'High risk',
        ),
      );
      if (referralUrgency != null) {
        actions.add(
          RecommendedAction(
            instruction: referralInstruction,
            urgency: referralUrgency,
            rationale:
                'High-risk signal (${(rp * 100).toStringAsFixed(0)}%). '
                '${p.featuresUsed.length} features used.',
            protocolSource: protocolSource,
            isReferral: true,
          ),
        );
      }
    }

    final ageDays =
        input.person.ageInDays ??
        ((draft.inputs['age_in_months'] as int? ?? 0) * 30.4375).round();

    if (ageDays <= 59) {
      addRisk(
        key: 'neonatal_sepsis',
        label: 'Rule-in candidate: possible severe bacterial infection (PSBI)',
        protocolSource: 'WHO IMCI Young Infant 0–59 days (PSBI)',
        severity: TriageLevel.urgent,
        referralUrgency: ReferralUrgency.immediate,
        referralInstruction:
            'Refer urgently for possible severe bacterial infection (PSBI).',
        ruleInTier: true,
      );
    } else {
      addRisk(
        key: 'child_pneumonia',
        label: 'High risk of pneumonia',
        protocolSource: 'WHO IMCI Sick Child 2–59 months (Pneumonia)',
        severity: TriageLevel.priority,
        referralUrgency: ReferralUrgency.sameDay,
        referralInstruction:
            'Refer today for assessment and treatment of pneumonia if worsening or not improving.',
      );
    }

    if (result.clientType == ClientType.pregnantWoman ||
        draft.inputs.containsKey('gestational_weeks')) {
      addRisk(
        key: 'preeclampsia_risk',
        label: 'High risk of pre-eclampsia',
        protocolSource:
            'WHO ANC 2016 / Ghana ANC guidance (Hypertensive disorders)',
        severity: TriageLevel.priority,
        referralUrgency: ReferralUrgency.sameDay,
        referralInstruction: 'Refer today for evaluation of pre-eclampsia.',
      );
      addRisk(
        key: 'lbw_sga',
        label: 'High risk of low birth weight',
        protocolSource: 'Ghana ANC guidance (risk screening)',
        severity: TriageLevel.watch,
        referralUrgency: null,
        referralInstruction: '',
      );
    }

    return (findings, actions);
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
  String _classificationOf(CarePlan plan) => plan.classifications.isNotEmpty
      ? plan.classifications.join(' + ')
      : result.classification;

  /// The triage that actually governs care — the CHO's override when they
  /// overruled, otherwise the engine's synthesized verdict. Mirrors
  /// [Assessment.effectiveTriage] so what the screen shows is what the record
  /// will say.
  TriageLevel get _effectiveTriage => _override ?? _carePlan.overallTriage;

  /// Regional base-rate priors the calibrated probabilities are expressed
  /// on. They mirror the fallback bases in [OfflineInferenceService] (GHS /
  /// Kintampo surveillance) and are what let a calibrated posterior be
  /// turned into an honest precision estimate via Bayes' theorem.
  static const Map<String, double> _regionalPriors = {
    'neonatal_sepsis': 0.02,
    'child_pneumonia': 0.03,
    'preeclampsia_risk': 0.025,
    'lbw_sga': 0.10,
  };

  /// Precision (positive predictive value) of a positive flag at the
  /// model's screening operating point: the hold-out sensitivity and
  /// specificity combined with the regional prior via Bayes' theorem —
  /// P(disease | flag). This is the number that answers "if the app flags
  /// this child, how often is it right here?", so it is the honest way to
  /// present the AI's confidence to a CHO.
  static double? _flagPrecision(String modelName, OfflineModelStatus? status) {
    final prior = _regionalPriors[modelName];
    if (prior == null || status == null) return null;
    // Believe the headline block only: cross-validation for a model trained
    // on real patient records, the external real-patient check for a
    // simulator-seeded one — never the circular simulator self-check when
    // an external check exists.
    final headline = status.headlineValidation;
    final sens = headline['sensitivity'];
    final spec = headline['specificity'];
    if (sens is! num || spec is! num) return null;
    final truePositives = sens.toDouble() * prior;
    final falsePositives = (1 - spec.toDouble()) * (1 - prior);
    final total = truePositives + falsePositives;
    if (total <= 0) return null;
    return (truePositives / total).clamp(0.0, 1.0);
  }

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

    final mlPredictions = await _mlPredictions;
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
          // --------------------------------------- PRE-REFERRAL STABILIZATION
          // Rendered ABOVE the verdict banner. These are life-saving
          // interventions that must happen *before* transport is dispatched.
          // If we showed them below the triage / "What to do" sections, the
          // CHO might never scroll far enough during the second-delay window.
          if (plan.preReferralProtocols.isNotEmpty) ...[
            _PreReferralSection(plan: plan),
            const SizedBox(height: Gap.lg),
          ],
          // ------------------------------------------------- Verdict hero
          // The moment the whole assessment builds to: what was found, the
          // level that governs the care, and how far the data can be
          // trusted — readable in one glance, in white on the royal-blue
          // gradient. IMCI colour appears only inside the white verdict
          // band, where it carries the clinical-safety signal.
          AppMotion.reveal(
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: AppColors.heroGradient,
                borderRadius: BorderRadius.circular(Gap.radius),
                boxShadow: const [AppShadows.glow],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Gap.radius),
                child: Stack(
                  children: [
                    // The level's own mark, oversized and barely there —
                    // the depth cue that makes the hero feel built, not flat.
                    Positioned(
                      right: -28,
                      bottom: -32,
                      child: Icon(
                        triageIcon(effective),
                        size: 168,
                        color: Colors.white.withValues(alpha: 0.07),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(Gap.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  ('${result.clientType.protocolLabel} · '
                                          '${input.person.ageLabel}')
                                      .toUpperCase(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.4,
                                    color: Colors.white70,
                                  ),
                                ),
                              ),
                              const SizedBox(width: Gap.sm),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: Gap.sm,
                                  vertical: Gap.xs,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      Colors.white.withValues(alpha: 0.14),
                                  borderRadius:
                                      BorderRadius.circular(Gap.radiusXs),
                                  border: Border.all(
                                    color: Colors.white.withValues(
                                      alpha: 0.30,
                                    ),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.signal_wifi_off_outlined,
                                      size: 11,
                                      color: Colors.white,
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      'OFFLINE',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.8,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: Gap.md),
                          Text(
                            _classificationOf(plan),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              height: 1.3,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: Gap.md),
                          _VerdictBand(
                            level: effective,
                            confidenceScore: plan.effectiveConfidenceScore,
                          ),
                          if (_override != null) ...[
                            const SizedBox(height: Gap.sm),
                            _OverrideNote(
                              engine: plan.overallTriage,
                              chosen: effective,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: Gap.lg),

          // ------------------------------------------- Why this verdict
          // The explainability anchor: one line naming *why* this triage,
          // plus any safety net that fired. The banner above already states
          // the classification and the confidence; restating the full
          // synthesis here was clutter, so only the reasoning survives.
          SectionCard(
            title: 'Why this result',
            icon: Icons.psychology_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ----------------------------------------- Read it aloud
                // The verdict in the language this worker chose, so the
                // family hears exactly what the screen says. The voice
                // chain — recording, phone voice, Hausa bridge, text —
                // is the same one every other button uses.
                Row(
                  children: [
                    AudioButton(
                      text: '${_classificationOf(plan)}. '
                          '${plan.triageRationale}',
                      language: input.user.preferredLanguage,
                      id: 'result_verdict',
                      compact: true,
                    ),
                    const SizedBox(width: Gap.sm),
                    Expanded(
                      child: Text(
                        'Read the result aloud in '
                        '${input.user.preferredLanguage}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.inkMuted,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.md),
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
                  const _SafetyNetNote(
                    text:
                        'Safety net: a danger sign was detected, so this '
                        'plan was raised to urgent automatically.',
                  ),
                ],
                if (plan.referralGuaranteed) ...[
                  const SizedBox(height: Gap.md),
                  const _SafetyNetNote(
                    text:
                        'Safety net: an urgent verdict always carries a '
                        'referral — one was added because none was listed.',
                  ),
                ],
                const SizedBox(height: Gap.md),
                _ConfidenceScoreCard(
                  score: plan.effectiveConfidenceScore,
                  confidence: plan.confidence,
                  missingCount: plan.missingData.length,
                  followUpInDays: plan.followUpInDays,
                ),
                if (plan.missingData.isNotEmpty) ...[
                  const SizedBox(height: Gap.sm),
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

          // --------------------------------------------- Offline AI evidence
          // The on-device models are the primary: each card states whether
          // the TFLite binary ran or the deterministic rules stood in, and
          // pairs every risk with its 95% CI and its precision so a CHO can
          // weigh the number instead of trusting it blindly.
          SectionCard(
            title: 'A second opinion from this phone',
            icon: Icons.memory_rounded,
            subtitle:
                'Each check runs entirely on this phone — no internet, and '
                'nothing about the family leaves the device. The standard '
                'rule charts stand in when a check cannot run. Tap a card '
                'to unfold its evidence.',
            child: FutureBuilder<Map<String, OfflineRiskPrediction>>(
              future: _mlPredictions,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const _AnalysisProgressCard();
                }
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(Gap.md),
                    child: Text(
                      'Could not run predictions: ${snapshot.error}',
                      style: const TextStyle(color: AppColors.triageRed),
                    ),
                  );
                }
                final predictions = snapshot.data ?? const {};
                if (predictions.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(Gap.md),
                    child: Text('No models available on this device.'),
                  );
                }
                return FutureBuilder<List<OfflineModelStatus>>(
                  future: _modelStatuses,
                  builder: (context, statusSnap) {
                    final byName = {
                      for (final s in statusSnap.data ??
                          const <OfflineModelStatus>[])
                        s.name: s,
                    };
                    final entries = predictions.entries.toList()
                      // Most urgent first: rule-in candidates, then the
                      // highest risks, with drift-suppressed models last.
                      ..sort((a, b) {
                        final pa = a.value;
                        final pb = b.value;
                        if (pa.ruleInCandidate != pb.ruleInCandidate) {
                          return pa.ruleInCandidate ? -1 : 1;
                        }
                        final ra = pa.riskProbability;
                        final rb = pb.riskProbability;
                        if ((ra == null) != (rb == null)) {
                          return ra == null ? 1 : -1;
                        }
                        if (ra != null && rb != null && ra != rb) {
                          return rb.compareTo(ra);
                        }
                        return pa.modelName.compareTo(pb.modelName);
                      });
                    final measureNext = <String>{
                      for (final e in entries) ...e.value.featuresMissing,
                    }.toList();
                    return Column(
                      children: [
                        if (measureNext.isNotEmpty)
                          _MeasureNextCard(featureNames: measureNext),
                        for (final e in entries)
                          _AiModelCard(
                            prediction: e.value,
                            status: byName[e.key],
                            precision: _flagPrecision(e.key, byName[e.key]),
                            prior: _regionalPriors[e.key],
                            open: _openModels.contains(e.key),
                            onToggle: () => setState(() {
                              if (!_openModels.add(e.key)) {
                                _openModels.remove(e.key);
                              }
                            }),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: Gap.lg),

          // ------------------------------------------------------- Findings
          if (plan.findings.isNotEmpty) ...[
            SectionCard(
              title: 'What this check found',
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
              title: 'When problems combine',
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
              subtitle:
                  '${_doneActions.length} of ${plan.actions.length} done — '
                  'tap a step as you complete it.',
              icon: Icons.checklist_rounded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Speak the full plan — every step, in order — in the
                  // language the worker picked, so it can be played to the
                  // family before they leave the compound.
                  if (plan.actions.isNotEmpty)
                    Row(
                      children: [
                        AudioButton(
                          text: 'What to do. '
                              '${plan.actions.map((a) => a.instruction).join('. ')}.',
                          language: input.user.preferredLanguage,
                          id: 'result_actions',
                          compact: true,
                        ),
                        const SizedBox(width: Gap.sm),
                        Expanded(
                          child: Text(
                            'Speak the full plan in '
                            '${input.user.preferredLanguage}',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.inkMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  if (plan.actions.isNotEmpty) const SizedBox(height: Gap.md),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: plan.actions.isEmpty
                          ? 0
                          : _doneActions.length / plan.actions.length,
                      minHeight: 6,
                      backgroundColor:
                          AppColors.inkFaint.withValues(alpha: 0.2),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.accent,
                      ),
                    ),
                  ),
                  const SizedBox(height: Gap.md),
                  for (var i = 0; i < plan.actions.length; i++)
                    _ActionTile(
                      plan.actions[i],
                      done: _doneActions.contains(i),
                      onToggle: () => setState(() {
                        if (_doneActions.contains(i)) {
                          _doneActions.remove(i);
                        } else {
                          _doneActions.add(i);
                        }
                      }),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Gap.lg),
          ],

          // ------------------------------------------------------ Nutrition
          if (nutrition != null) ...[
            _NutritionSection(
              plan: nutrition,
              cost: _cost,
              onCost: (tier) {
                setState(() => _cost = tier);
              },
            ),
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

          // -------------------------------- UNICEF Nurturing Care (PILLAR 3)
          // The five-pillar framework in one cohesive card. Pillar 3 of the
          // engine revamp: every visit produces an action list organised
          // by Good Health / Adequate Nutrition / Responsive Caregiving /
          // Early Learning / Security and Safety, each with a citation.
          if (nurturingCare.isNotEmpty &&
              (result.clientType == ClientType.newborn ||
                  result.clientType == ClientType.childUnderFive ||
                  result.clientType == ClientType.pregnantWoman ||
                  result.clientType == ClientType.postpartumWoman)) ...[
            _NurturingCareSection(assessment: nurturingCare),
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
            onRefer: (v) => setState(() {
              _referTouched = true;
              _refer = v;
            }),
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
                'Added to your queue. The worker who started this case '
                'should be the one who closes it.',
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

// -------------------------------------------------------------- Verdict band

/// The white band inside the verdict hero: the level that governs the care,
/// in its IMCI colour, beside the confidence the data earned. A CHO quoting
/// the result into the register should need nothing past this band.
class _VerdictBand extends StatelessWidget {
  const _VerdictBand({required this.level, required this.confidenceScore});

  final TriageLevel level;
  final int confidenceScore;

  @override
  Widget build(BuildContext context) {
    final c = triageColours(level);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Gap.radiusSm),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2E0B1B33),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: c.bg, shape: BoxShape.circle),
            child: Icon(triageIcon(level), size: 22, color: c.fg),
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Text(
              level.label.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: c.fg,
                height: 1.25,
              ),
            ),
          ),
          const SizedBox(width: Gap.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$confidenceScore%',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: c.fg,
                  height: 1,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'CONFIDENCE',
                style: TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: AppColors.inkFaint,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------- Action

class _ActionTile extends StatelessWidget {
  const _ActionTile(this.action, {this.done = false, this.onToggle});

  final RecommendedAction action;
  final bool done;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final (icon, colour) = action.isReferral
        ? (Icons.local_hospital_outlined, AppColors.triageRed)
        : action.isTreatment
        ? (Icons.medication_outlined, AppColors.triageAmber)
        : (Icons.chat_bubble_outline_rounded, AppColors.accent);

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(Gap.radiusSm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Tick circle — the satisfying "done" micro-interaction (T3).
            Container(
              width: 22,
              height: 22,
              margin: const EdgeInsets.only(right: Gap.md),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? AppColors.accent : Colors.transparent,
                border: Border.all(
                  color: done ? AppColors.accent : AppColors.inkFaint,
                  width: 1.5,
                ),
              ),
              child: done
                  ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                  : null,
            ),
            Icon(icon, size: 18, color: done ? AppColors.inkFaint : colour),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    action.instruction,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      height: 1.4,
                      color: done ? AppColors.inkFaint : null,
                      decoration:
                          done ? TextDecoration.lineThrough : TextDecoration.none,
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
      ),
    );
  }
}

// ----------------------------------------------------------- Safety net note

/// The confidence score — the number, not just the wording.
///
/// The engines derive it from how many decisive measurements were actually
/// taken (temperature, MUAC, blood pressure, weight…). It sits inside the
/// verdict banner so a CHO can quote it in the register without hunting for
/// it, and the bar underneath makes "thin data" visible at a glance.
class _ConfidenceScoreCard extends StatelessWidget {
  const _ConfidenceScoreCard({
    required this.score,
    required this.confidence,
    required this.missingCount,
    this.followUpInDays,
  });

  final int score;
  final RecommendationConfidence confidence;
  final int missingCount;
  final int? followUpInDays;

  @override
  Widget build(BuildContext context) {
    final (colour, icon) = switch (confidence) {
      RecommendationConfidence.protocolCertain => (
        AppColors.triageGreen,
        Icons.verified_outlined,
      ),
      RecommendationConfidence.high => (
        AppColors.accent,
        Icons.thumb_up_outlined,
      ),
      RecommendationConfidence.moderate => (
        AppColors.triageAmber,
        Icons.help_outline_rounded,
      ),
      RecommendationConfidence.low => (
        AppColors.inkMuted,
        Icons.info_outline_rounded,
      ),
    };

    return Container(
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(Gap.radiusSm),
        border: Border.all(color: colour.withValues(alpha: 0.25), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: colour),
              const SizedBox(width: Gap.xs),
              Text(
                '$score%',
                style: TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w800,
                  color: colour,
                  height: 1,
                ),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      confidence.label,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      missingCount > 0
                          ? '$missingCount item'
                                '${missingCount == 1 ? '' : 's'} not measured'
                          : 'All key measurements taken',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (followUpInDays != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'REVIEW IN',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: AppColors.inkFaint,
                      ),
                    ),
                    Text(
                      '$followUpInDays day${followUpInDays == 1 ? '' : 's'}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: score / 100,
              minHeight: 5,
              backgroundColor: colour.withValues(alpha: 0.15),
              color: colour,
            ),
          ),
        ],
      ),
    );
  }
}

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
          why:
              'Engine\u2019s verdict: ${engineTriage.label}. Tap a level to '
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
              hintText:
                  'e.g. Child looks more unwell than the score suggests '
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
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.sm),
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
          why:
              'A recommendation the family cannot buy is not a recommendation.',
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
    if (f.contains('egg') && !f.contains('garden')) {
      return AppImages.foodBoiledEgg;
    }
    if (f.contains('fish')) {
      return AppImages.foodDriedFish;
    }
    if (f.contains('groundnut') || f.contains('peanut')) {
      return AppImages.foodGroundnutPaste;
    }
    if (f.contains('sweet potato')) {
      return AppImages.foodSweetPotato;
    }
    if (f.contains('pawpaw') || f.contains('papaya')) {
      return AppImages.foodPawpaw;
    }
    if (f.contains('dawadawa') || f.contains('locust')) {
      return AppImages.foodDawadawa;
    }
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
        f.contains('zogale') ||
        f.contains('leaf') ||
        f.contains('leaves') ||
        f.contains('vegetable') ||
        f.contains('fruit') ||
        f.contains('mango') ||
        f.contains('pumpkin')) {
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

/// Pre-referral emergency stabilisation section. Rendered ABOVE the
/// verdict banner because the steps must be executed *before* transport
/// is dispatched — the second-delay window is the entire reason this
/// module exists.
///
/// Each protocol carries its own WHO / MOH citation. The citation is
/// shown on the card so a CHO who is unfamiliar with the dose can verify
/// it against the published guidance before administering.
class _PreReferralSection extends StatelessWidget {
  const _PreReferralSection({required this.plan});

  final CarePlan plan;

  @override
  Widget build(BuildContext context) {
    // Red background with a "DO NOW" pill — the only section of the app
    // that overrides the theme to grab attention. A CHO skimming for what
    // to do first must see this before anything else.
    final protocols = plan.preReferralProtocols;
    return Container(
      padding: const EdgeInsets.all(Gap.lg),
      decoration: BoxDecoration(
        color: AppColors.triageRed,
        borderRadius: BorderRadius.circular(Gap.radius),
        boxShadow: [
          BoxShadow(
            color: AppColors.triageRed.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Gap.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(Gap.radiusSm),
                ),
                child: const Text(
                  'DO NOW — BEFORE TRANSPORT',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    color: AppColors.triageRed,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const Spacer(),
              const Icon(
                Icons.medical_services_outlined,
                color: Colors.white,
                size: 22,
              ),
            ],
          ),
          const SizedBox(height: Gap.md),
          const Text(
            'Pre-referral stabilisation',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              height: 1.2,
            ),
          ),
          const SizedBox(height: Gap.xs),
          Text(
            '${protocols.length} WHO / GHS protocol'
            '${protocols.length == 1 ? '' : 's'} activated. '
            'Initiate before transport is dispatched.',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: Gap.md),
          for (final p in protocols) ...[
            _ProtocolCard(
              protocol: p,
              reason:
                  plan.preReferralActivationReasons[p.id] ?? 'See audit log.',
            ),
            const SizedBox(height: Gap.md),
          ],
          // Decision-support framing — required for clinical-decision
          // software and a deliberate trust signal: the app does not
          // pretend to be the clinician.
          Container(
            padding: const EdgeInsets.all(Gap.md),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(Gap.radiusSm),
            ),
            child: const Text(
              'DECISION SUPPORT — You are the licensed clinician. Verify the '
              'dose, route and contraindications against the patient before '
              'administration. Each card below cites the published guideline.',
              style: TextStyle(
                fontSize: 11,
                color: Colors.white,
                height: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One pre-referral protocol card, with the headline, citation badge,
/// urgency note, ordered steps (with dose / when / contraindication per
/// step), and the protocol-level contraindications.
class _ProtocolCard extends StatelessWidget {
  const _ProtocolCard({required this.protocol, required this.reason});

  final StabilizationProtocol protocol;
  final String reason;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Gap.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.local_hospital_rounded,
                color: AppColors.triageRed,
                size: 20,
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text(
                  protocol.headline,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          // Citation badge — the audit-defensible anchor.
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Gap.sm,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: AppColors.triageRedBg,
              borderRadius: BorderRadius.circular(Gap.radiusSm),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.menu_book_outlined,
                  size: 12,
                  color: AppColors.triageRed,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    protocol.citation.shortName,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.triageRed,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (protocol.urgencyNote != null) ...[
            const SizedBox(height: Gap.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.timer_outlined,
                  size: 14,
                  color: AppColors.triageAmber,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    protocol.urgencyNote!,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (protocol.contraindications.isNotEmpty) ...[
            const SizedBox(height: Gap.sm),
            Container(
              padding: const EdgeInsets.all(Gap.sm),
              decoration: BoxDecoration(
                color: AppColors.triageAmberBg,
                borderRadius: BorderRadius.circular(Gap.radiusSm),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'CONTRAINDICATIONS',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: AppColors.triageAmber,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final c in protocol.contraindications)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      child: Text(
                        '• $c',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.ink,
                          height: 1.4,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: Gap.md),
          const Text(
            'STEPS',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              color: AppColors.inkMuted,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: Gap.xs),
          for (final s in protocol.steps)
            _ProtocolStepTile(step: s, reason: reason),
        ],
      ),
    );
  }
}

/// One numbered step in a pre-referral protocol.
class _ProtocolStepTile extends StatelessWidget {
  const _ProtocolStepTile({required this.step, required this.reason});

  final ProtocolStep step;

  /// The reason string for the protocol. Shown once at the bottom of
  /// the steps, so the CHO can see *why* the protocol was activated.
  final String reason;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(
              color: AppColors.triageRed,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${step.order}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.action,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 2),
                // Dose, in a clinically-faithful format.
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Gap.sm,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.canvas,
                    borderRadius: BorderRadius.circular(Gap.radiusSm),
                    border: Border.all(color: AppColors.line, width: 0.5),
                  ),
                  child: Text(
                    'DOSE: ${step.dose}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                      height: 1.4,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'WHEN: ${step.whenToDo}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                    height: 1.4,
                  ),
                ),
                Text(
                  'WHY: ${step.rationale}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.inkMuted,
                    height: 1.4,
                  ),
                ),
                if (step.contraindication != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'CAUTION: ${step.contraindication!}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.triageAmber,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// UNICEF Nurturing Care Framework section. Pillar 3 of the engine
/// revamp. Renders the five canonical pillars as a single, cohesive
/// card: Good Health, Adequate Nutrition, Responsive Caregiving,
/// Opportunities for Early Learning, Security and Safety. Each
/// action carries a citation, and actions already delivered at this
/// visit are checked off.
class _NurturingCareSection extends StatelessWidget {
  const _NurturingCareSection({required this.assessment});

  final NurturingCareAssessment assessment;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Nurturing care for early development',
      subtitle:
          'WHO / UNICEF / World Bank 2018 Nurturing Care Framework. Five '
          'pillars, applied to this visit.',
      icon: Icons.child_care_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Pillar strip — visual indicator of which pillars have
          // actions.
          Row(
            children: [
              for (final p in NurturingCarePillar.values) ...[
                Expanded(
                  child: _PillarChip(
                    pillar: p,
                    summary: assessment.pillarSummaries[p] ?? '',
                  ),
                ),
                if (p != NurturingCarePillar.values.last)
                  const SizedBox(width: 4),
              ],
            ],
          ),
          const SizedBox(height: Gap.md),
          // Actions grouped by pillar.
          for (final p in NurturingCarePillar.values) ...[
            ...assessment.actions
                .where((a) => a.pillar == p)
                .map(
                  (a) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: _NurturingCareActionTile(action: a),
                  ),
                ),
          ],
          const SizedBox(height: Gap.sm),
          // Citation footer — the audit-defensible anchor.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.menu_book_outlined,
                size: 12,
                color: AppColors.inkMuted,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Framework: WHO / UNICEF / World Bank 2018, Nurturing '
                  'care for early childhood development. CC BY-NC-SA 3.0 '
                  'IGO. Each action cites a WHO/UNICEF/GHS implementing '
                  'guideline.',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: AppColors.inkMuted,
                    fontStyle: FontStyle.italic,
                    height: 1.4,
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

/// One pillar's chip, shown in the pillar strip at the top of the
/// section.
class _PillarChip extends StatelessWidget {
  const _PillarChip({required this.pillar, required this.summary});

  final NurturingCarePillar pillar;
  final String summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(Gap.radiusSm),
        border: Border.all(color: AppColors.line, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            pillar.displayName,
            style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
              height: 1.2,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            summary,
            style: const TextStyle(
              fontSize: 8.5,
              color: AppColors.inkMuted,
              height: 1.2,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// One action tile within a pillar.
class _NurturingCareActionTile extends StatelessWidget {
  const _NurturingCareActionTile({required this.action});

  final NurturingCareAction action;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Checkmark or hollow circle: delivered or pending.
        Container(
          width: 18,
          height: 18,
          margin: const EdgeInsets.only(top: 1),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: action.deliveredAtVisit
                ? AppColors.triageGreen
                : Colors.transparent,
            border: Border.all(
              color: action.deliveredAtVisit
                  ? AppColors.triageGreen
                  : AppColors.inkMuted,
              width: 1.5,
            ),
          ),
          child: action.deliveredAtVisit
              ? const Icon(Icons.check, size: 12, color: Colors.white)
              : null,
        ),
        const SizedBox(width: Gap.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                action.title,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                action.counsellingNote,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.ink,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  if (action.deliveredAtVisit)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                        color: AppColors.triageGreenBg,
                        borderRadius: BorderRadius.circular(Gap.radiusSm),
                      ),
                      child: const Text(
                        'DELIVERED',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: AppColors.triageGreen,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  if (action.referToService)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                        color: AppColors.triageAmberBg,
                        borderRadius: BorderRadius.circular(Gap.radiusSm),
                      ),
                      child: const Text(
                        'REFER',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: AppColors.triageAmber,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  Flexible(
                    child: Text(
                      action.citation.shortName,
                      style: const TextStyle(
                        fontSize: 10,
                        fontStyle: FontStyle.italic,
                        color: AppColors.inkMuted,
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
    );
  }
}

// ------------------------------------------------------------ AI evidence UI

/// Shown while the on-device models are still running. The spinner is what
/// the widget tests key on to know inference is in flight; the copy tells
/// the CHO what is happening underneath — the TFLite models run first, and
/// the deterministic rules are only the stand-in.
class _AnalysisProgressCard extends StatelessWidget {
  const _AnalysisProgressCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Gap.lg),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(Gap.radiusSm),
        boxShadow: const [AppShadows.glow],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              const SizedBox(width: Gap.md),
              const Expanded(
                child: Text(
                  'Running the on-device AI models…',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.md),
          Text(
            'The TFLite model scores this assessment first, on this phone. '
            'The rule-based engine only steps in if the model cannot load. '
            'No internet is needed and nothing leaves the device.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.85),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// One model's evidence card: what engine produced the number, the risk with
/// its 95% CI, the precision of a positive flag at the regional prevalence,
/// and — unfolded on tap — the features, the validation metrics and the
/// integrity check behind it. The triage badge keeps the IMCI colour
/// contract; everything else is the blue brand voice.
/// The "measure this next" prompt: the union of every input the models
/// wanted but did not get, translated into nurse-speak. Each gap filled —
/// now or at the next contact — raises the precision of the next result.
class _MeasureNextCard extends StatelessWidget {
  const _MeasureNextCard({required this.featureNames});

  final List<String> featureNames;

  /// Nurse-speak names for every input the four models can ask for.
  /// Anything unmapped falls back to a humanised raw name.
  static const Map<String, String> _friendlyNames = {
    'age_days': 'age in days',
    'temperature_celsius': 'temperature',
    'respiratory_rate_per_min': 'breathing rate (count a full minute)',
    'heart_rate_per_min': 'heart rate',
    'oxygen_saturation_per_cent': 'oxygen saturation (pulse oximeter)',
    'oxygen_saturation': 'oxygen saturation (pulse oximeter)',
    'birth_weight_kg': 'birth weight',
    'apgar_5_minute': 'Apgar score at 5 minutes',
    'history_of_convulsions': 'convulsions history',
    'severe_chest_indrawing': 'severe chest indrawing',
    'nasal_flaring_grunting': 'nasal flaring or grunting',
    'bulging_fontanelle': 'bulging fontanelle',
    'jaundice_before_24h': 'jaundice within 24 hours of birth',
    'feeding_difficulty': 'feeding difficulty',
    'abdominal_distension': 'swollen belly',
    'cord_infection': 'cord redness or pus',
    'skin_pustules': 'skin pustules',
    'lethargic_unconscious': 'lethargy or unconsciousness',
    'bleeding': 'bleeding from any site',
    'hiv_exposed': 'HIV exposure status',
    'multiple_birth': 'twin or multiple birth',
    'cough_present': 'cough',
    'chest_indrawing': 'chest indrawing',
    'stridor_calm': 'stridor when calm',
    'general_danger_sign': 'IMCI general danger sign',
    'maternal_age': "mother's age",
    'gravida': 'gravida',
    'parity': 'parity',
    'systolic_bp': 'systolic BP',
    'diastolic_bp': 'diastolic BP',
    'haemoglobin': 'haemoglobin (Hb)',
    'urine_protein': 'urine protein (dipstick)',
    'maternal_muac_mm': "mother's MUAC",
    'maternal_bmi': "mother's BMI",
    'oedema_hands_or_face': 'swelling of hands or face',
    'epigastric_pain': 'upper belly pain',
    'headache_severe': 'severe headache',
    'blurred_vision': 'blurred vision',
    'brisk_reflexes': 'brisk reflexes',
    'oliguria': 'passing little urine',
    'weight_gain_over_1kg_per_week': 'weight gain over 1 kg a week',
    'weight_gain_kg_this_pregnancy': 'weight gained this pregnancy',
    'previous_losses': 'previous pregnancy losses',
    'prev_caesarean': 'previous caesarean',
  };

  static String _friendly(String raw) =>
      _friendlyNames[raw] ?? raw.replaceAll('_', ' ');

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: Gap.sm),
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceTint,
        borderRadius: BorderRadius.circular(Gap.radiusXs),
        border: Border(
          left: BorderSide(color: AppColors.primary, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.pending_actions_rounded,
                size: 15,
                color: AppColors.primary,
              ),
              SizedBox(width: Gap.xs),
              Expanded(
                child: Text(
                  'MEASURE THESE NEXT',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.xs),
          const Text(
            'The checks in this section ran without these inputs. Each one '
            'you measure — now or at the next contact — sharpens the next '
            'result.',
            style: TextStyle(
              fontSize: 11.5,
              color: AppColors.inkMuted,
              height: 1.45,
            ),
          ),
          const SizedBox(height: Gap.sm),
          Wrap(
            spacing: Gap.xs,
            runSpacing: Gap.xs,
            children: [
              for (final f in featureNames)
                _FeatureChip(_friendly(f), present: false),
            ],
          ),
        ],
      ),
    );
  }
}

class _AiModelCard extends StatelessWidget {
  const _AiModelCard({
    required this.prediction,
    required this.status,
    required this.precision,
    required this.prior,
    required this.open,
    required this.onToggle,
  });

  final OfflineRiskPrediction prediction;
  final OfflineModelStatus? status;

  /// Precision (PPV) of a positive flag via Bayes on the regional prior.
  final double? precision;
  final double? prior;
  final bool open;
  final VoidCallback onToggle;

  OfflineRiskPrediction get p => prediction;

  String get _title => switch (p.modelName) {
    'neonatal_sepsis' => 'Newborn sepsis (PSBI)',
    'child_pneumonia' => 'Childhood pneumonia',
    'preeclampsia_risk' => 'Pre-eclampsia',
    'lbw_sga' => 'Low birthweight / small-for-gestational-age',
    _ => p.modelName,
  };

  IconData get _icon => switch (p.modelName) {
    'neonatal_sepsis' => Icons.coronavirus_outlined,
    'child_pneumonia' => Icons.air_outlined,
    'preeclampsia_risk' => Icons.monitor_heart_outlined,
    'lbw_sga' => Icons.monitor_weight_outlined,
    _ => Icons.analytics_outlined,
  };

  (Color, Color) get _badge =>
      p.ruleInCandidate || p.classification == 'high'
      ? (AppColors.triageRedBg, AppColors.triageRed)
      : p.classification == 'moderate'
      ? (AppColors.triageAmberBg, AppColors.triageAmber)
      : (AppColors.triageGreenBg, AppColors.triageGreen);

  /// Tier wording only when the model actually produced a number — a
  /// drift-suppressed prediction is neither screening nor rule-in.
  String? get _tierText => p.riskProbability == null
      ? null
      : p.ruleInCandidate
      ? 'rule-in candidate'
      : p.ruleInThreshold != null
      ? 'screening tier'
      : null;

  @override
  Widget build(BuildContext context) {
    final (badgeBg, badgeFg) = _badge;
    final tierText = _tierText;
    final riskPct = p.riskProbability == null
        ? null
        : '${(p.riskProbability! * 100).toStringAsFixed(1)}%';

    return Container(
      margin: const EdgeInsets.only(bottom: Gap.md),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(Gap.radiusSm),
        border: Border.all(
          color: p.ruleInCandidate
              ? AppColors.triageRed.withValues(alpha: 0.40)
              : AppColors.line,
          width: p.ruleInCandidate ? 1.4 : Gap.hairline,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(Gap.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(Gap.radiusXs),
                    ),
                    child: Icon(_icon, size: 19, color: AppColors.primary),
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _title,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: Gap.xs),
                        Row(
                          children: [
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: p.usingModel
                                      ? AppColors.primaryLight
                                      : AppColors.surfaceTint,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      p.usingModel
                                          ? Icons.memory_rounded
                                          : Icons.rule_rounded,
                                      size: 11,
                                      color: p.usingModel
                                          ? AppColors.primary
                                          : AppColors.inkMuted,
                                    ),
                                    const SizedBox(width: 3),
                                    Flexible(
                                      child: Text(
                                        p.usingModel
                                            ? 'TFLite on-device'
                                            : 'rule-based fallback',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.5,
                                          color: p.usingModel
                                              ? AppColors.primary
                                              : AppColors.inkMuted,
                                        ),
                                      ),
                                    ),
                                    if (p.usingModel &&
                                        status?.integrityVerified == true) ...[
                                      const SizedBox(width: 3),
                                      const Icon(
                                        Icons.verified_outlined,
                                        size: 11,
                                        color: AppColors.primary,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: Gap.sm),
                            Flexible(
                              child: Text(
                                '${p.inferenceMs ?? 0} ms',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: AppColors.inkFaint,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Gap.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Gap.sm,
                      vertical: Gap.xs,
                    ),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(Gap.radiusXs),
                      border: Border.all(
                        color: badgeFg.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      p.ruleInCandidate ? 'rule-in' : p.classification,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: badgeFg,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.md),
            child: p.riskProbability == null
                ? _suppressedBody()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Risk $riskPct',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          color: badgeFg,
                          height: 1.1,
                        ),
                      ),
                      if (tierText != null) ...[
                        const SizedBox(height: Gap.xs),
                        Text(
                          tierText,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: badgeFg,
                          ),
                        ),
                      ],
                      const SizedBox(height: Gap.md),
                      _RiskGauge(
                        probability: p.riskProbability!,
                        colour: badgeFg,
                        ruleInThreshold: p.ruleInThreshold,
                      ),
                      if (p.confidenceInterval95 != null) ...[
                        const SizedBox(height: Gap.sm),
                        Text(
                          '95% CI: '
                          '${(p.confidenceInterval95!.low * 100).toStringAsFixed(1)}% – '
                          '${(p.confidenceInterval95!.high * 100).toStringAsFixed(1)}% '
                          'on the calibrated probability',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.inkMuted,
                            height: 1.4,
                          ),
                        ),
                      ],
                      const SizedBox(height: Gap.md),
                      _precisionBlock(),
                    ],
                  ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: _details(),
            crossFadeState: open
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: AppMotion.fast,
          ),
          InkWell(
            onTap: onToggle,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: Gap.sm),
              color: AppColors.surfaceTint.withValues(alpha: 0.5),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    open ? 'Hide evidence' : 'Show evidence',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: Gap.xs),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: AppMotion.fast,
                    child: const Icon(
                      Icons.expand_more_rounded,
                      size: 16,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The honest no-number state: the AI sat this one out, and the card says
  /// why instead of pretending to know.
  Widget _suppressedBody() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: AppColors.triageAmberBg,
        borderRadius: BorderRadius.circular(Gap.radiusXs),
        border: Border(
          left: BorderSide(color: AppColors.triageAmber, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Risk n/a · out of training window',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: AppColors.triageAmber,
            ),
          ),
          const SizedBox(height: Gap.xs),
          Text(
            'One or more inputs fall outside the range this model was '
            'trained on, so the AI withholds a number rather than guess. '
            'The deterministic WHO/GHS rules still apply.',
            style: TextStyle(
              fontSize: 11.5,
              color: AppColors.triageAmber.withValues(alpha: 0.9),
              height: 1.45,
            ),
          ),
          if (p.driftFeatures.isNotEmpty) ...[
            const SizedBox(height: Gap.sm),
            Wrap(
              spacing: Gap.xs,
              runSpacing: Gap.xs,
              children: [
                for (final f in p.driftFeatures) _FeatureChip(f, present: false),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// The confidence, stated as precision: at this region's prevalence, how
  /// often a positive flag from this model is a true positive.
  Widget _precisionBlock() {
    final hasPrecision = precision != null && prior != null;
    // Name the evidence the precision stands on, so a CHO (and an auditor)
    // can tell a real-patient estimate from a simulator self-check.
    final st = status;
    final basis = st == null
        ? 'the bundled validation metrics'
        : st.trainedOnRealPatients
            ? 'the cross-validation on real patient records'
            : st.externalValidation.isNotEmpty
                ? 'the external check on real patients'
                : 'the simulator self-check (not yet checked on real patients)';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceTint,
        borderRadius: BorderRadius.circular(Gap.radiusXs),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.insights_outlined,
            size: 18,
            color: AppColors.primary,
          ),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'PRECISION OF A POSITIVE FLAG',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasPrecision
                      ? '≈ ${(precision! * 100).toStringAsFixed(0)}%'
                      : 'n/a',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasPrecision
                      ? 'At the ~${(prior! * 100).toStringAsFixed(1)}% '
                            'regional prevalence, about '
                            '${(precision! * 100).round()} in 100 positive '
                            'flags are true positives — Bayes on $basis.'
                      : 'No validation metrics are bundled for this model, '
                            'so the precision cannot be stated honestly.',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.inkMuted,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The unfolded audit trail: provenance, validation metrics, tier
  /// explanation and the feature list the model actually saw.
  Widget _details() {
    final st = status;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.md),
      color: AppColors.surface.withValues(alpha: 0.6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: Gap.md),
          Row(
            children: [
              Flexible(
                child: Text(
                  '${p.modelName} v${p.modelVersion ?? "?"}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
              const Spacer(),
              Icon(
                status?.integrityVerified == true
                    ? Icons.verified_outlined
                    : Icons.help_outline_outlined,
                size: 13,
                color: status?.integrityVerified == true
                    ? AppColors.triageGreen
                    : AppColors.inkFaint,
              ),
              const SizedBox(width: 3),
              Text(
                status?.integrityVerified == true
                    ? 'SHA-256 verified'
                    : 'integrity not verified',
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.inkMuted,
                ),
              ),
            ],
          ),
          if (st != null) ...[
            const SizedBox(height: Gap.sm),
            Text(
              st.trainedOnRealPatients
                  ? 'Trained on real patient records — the cross-validation '
                        'below is the evidence for this score.'
                  : st.externalValidation.isNotEmpty
                        ? 'Seeded from published studies — believe the '
                              'external check below, not the self-check.'
                        : 'Seeded from published studies — not yet checked '
                              'on real patients, so treat the score as a '
                              'screening aid only.',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
                height: 1.4,
              ),
            ),
          ],
          if (p.ruleInThreshold != null) ...[
            const SizedBox(height: Gap.sm),
            Text(
              p.ruleInCandidate
                  ? 'Rule-in candidate — the calibrated posterior cleared the '
                        '${(p.ruleInThreshold! * 100).toStringAsFixed(0)}% '
                        'rule-in tier on the 2%-prior scale, so the AI alone '
                        'justifies urgent referral.'
                  : p.riskProbability == null
                        ? 'No tier: the AI sat this one out and the '
                              'deterministic GHS rules carry the decision.'
                        : 'Screening tier — below the '
                              '${(p.ruleInThreshold! * 100).toStringAsFixed(0)}% '
                              'rule-in cut-off; the deterministic WHO/GHS '
                              'rules decide the referral.',
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.inkMuted,
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: Gap.md),
          ..._validationBlocks(st),
          const Text(
            'FEATURES USED',
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: AppColors.inkMuted,
            ),
          ),
          const SizedBox(height: Gap.xs),
          if (p.featuresUsed.isEmpty)
            const Text(
              'None',
              style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
            )
          else
            Wrap(
              spacing: Gap.xs,
              runSpacing: Gap.xs,
              children: [
                for (final f in p.featuresUsed) _FeatureChip(f, present: true),
              ],
            ),
          const SizedBox(height: Gap.md),
          const Text(
            'FEATURES MISSING',
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: AppColors.inkMuted,
            ),
          ),
          const SizedBox(height: Gap.xs),
          if (p.featuresMissing.isEmpty)
            const Text(
              'None — complete!',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppColors.triageGreen,
              ),
            )
          else ...[
            Wrap(
              spacing: Gap.xs,
              runSpacing: Gap.xs,
              children: [
                for (final f in p.featuresMissing)
                  _FeatureChip(f, present: false),
              ],
            ),
            const SizedBox(height: Gap.xs),
            const Text(
              'Each missing item lowers the precision — measure it at the '
              'next contact when you can.',
              style: TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: AppColors.inkFaint,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The validation evidence, framed by how the model was built. A model
  /// trained on real patient records leads with its cross-validation; a
  /// simulator-seeded model leads with the external check on real patients
  /// and its internal numbers are shown as the sanity check they are.
  List<Widget> _validationBlocks(OfflineModelStatus? st) {
    final internal = st?.internalValidation ?? const <String, Object?>{};
    final external = st?.externalValidation ?? const <String, Object?>{};
    final real = st?.trainedOnRealPatients ?? false;
    final blocks = <Widget>[];
    if (real) {
      if (internal.isNotEmpty) {
        blocks.add(_metricBlock(
          'CROSS-VALIDATION — REAL PATIENT DATA',
          'Trained and tested on real patient records; this is the evidence '
              'for the score above.',
          internal,
          brier: st?.brierScore,
        ));
      }
      if (external.isNotEmpty) {
        blocks.add(_metricBlock(
          'OUT-OF-DOMAIN CHECK — EXPECTED NEAR-CHANCE',
          'Scored on patients the model was never built for, as a transfer '
              'check. A low score here is expected and does not weaken the '
              'cross-validation above.',
          external,
        ));
      }
    } else {
      if (external.isNotEmpty) {
        blocks.add(_metricBlock(
          'CHECKED ON REAL PATIENTS (EXTERNAL)',
          'This model was seeded from published studies, so this external '
              'check is the number to believe.',
          external,
        ));
      }
      if (internal.isNotEmpty) {
        blocks.add(_metricBlock(
          external.isNotEmpty
              ? 'SIMULATOR SELF-CHECK — SANITY ONLY'
              : 'SIMULATOR SELF-CHECK — NOT YET CHECKED ON REAL PATIENTS',
          'Internal hold-out against the same simulator that seeded the '
              'model. It proves the plumbing works; it is not clinical '
              'evidence.',
          internal,
          brier: st?.brierScore,
        ));
      }
    }
    if (blocks.isEmpty) {
      blocks.add(const Padding(
        padding: EdgeInsets.only(bottom: Gap.md),
        child: Text(
          'No validation metrics are bundled for this model.',
          style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
        ),
      ));
    }
    return blocks;
  }

  /// One captioned validation block: an eyebrow label, a one-line reading
  /// guide, then the four metric stats.
  Widget _metricBlock(
    String label,
    String caption,
    Map<String, Object?> block, {
    double? brier,
  }) {
    num? metric(String key) => block[key] is num ? block[key]! as num : null;
    String pct(num? x) => x == null ? '—' : '${(x * 100).toStringAsFixed(1)}%';
    final brierValue =
        brier ?? metric('brier_score') ?? metric('calibrated_brier');
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            caption,
            style: const TextStyle(
              fontSize: 10.5,
              fontStyle: FontStyle.italic,
              color: AppColors.inkFaint,
              height: 1.35,
            ),
          ),
          const SizedBox(height: Gap.xs),
          Row(
            children: [
              Expanded(
                child: _MetricStat(
                  label: 'AUC',
                  value: metric('holdout_auc') == null
                      ? '—'
                      : metric('holdout_auc')!.toStringAsFixed(2),
                ),
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: _MetricStat(
                  label: 'SENSITIVITY',
                  value: pct(metric('sensitivity')),
                ),
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: _MetricStat(
                  label: 'SPECIFICITY',
                  value: pct(metric('specificity')),
                ),
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: _MetricStat(
                  label: 'BRIER',
                  value: brierValue == null
                      ? '—'
                      : brierValue.toStringAsFixed(3),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The probability bar: triage-coloured fill on a 0–100% track, with the
/// rule-in cut-off marked where the model has one. The fill eases in once
/// (finite animation, so widget tests still settle).
class _RiskGauge extends StatelessWidget {
  const _RiskGauge({
    required this.probability,
    required this.colour,
    this.ruleInThreshold,
  });

  final double probability;
  final Color colour;
  final double? ruleInThreshold;

  @override
  Widget build(BuildContext context) {
    final fill = probability.clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 10,
              width: double.infinity,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: fill),
                    duration: AppMotion.duration,
                    curve: AppMotion.curve,
                    builder: (context, t, _) => Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: t,
                        child: Container(
                          decoration: BoxDecoration(
                            color: colour,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (ruleInThreshold != null &&
                      ruleInThreshold! > 0 &&
                      ruleInThreshold! < 1)
                    Positioned(
                      left: width * ruleInThreshold! - 1,
                      top: -2,
                      bottom: -2,
                      child: Container(
                        width: 2,
                        decoration: BoxDecoration(
                          color: AppColors.ink,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Gap.xs),
            Row(
              children: [
                const Text(
                  '0%',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.inkFaint,
                  ),
                ),
                if (ruleInThreshold != null) ...[
                  SizedBox(width: max(0, width * ruleInThreshold! - 28)),
                  Flexible(
                    child: Text(
                      'rule-in '
                      '${(ruleInThreshold! * 100).toStringAsFixed(0)}%',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                const Text(
                  '100%',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.inkFaint,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// One validation metric, labelled — the audit trail in miniature.
class _MetricStat extends StatelessWidget {
  const _MetricStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: Gap.sm),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(Gap.radiusXs),
        border: Border.all(color: AppColors.line, width: Gap.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: AppColors.inkFaint,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// A feature name as a chip: green when the model saw it, amber when it
/// was missing (an implicit "measure this next time").
class _FeatureChip extends StatelessWidget {
  const _FeatureChip(this.label, {required this.present});

  final String label;
  final bool present;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: present ? AppColors.triageGreenBg : AppColors.triageAmberBg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: present ? AppColors.triageGreen : AppColors.triageAmber,
        ),
      ),
    );
  }
}
