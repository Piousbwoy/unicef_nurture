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
  late Future<Map<String, OfflineRiskPrediction>> _mlPredictions;
  Map<String, OfflineRiskPrediction>? _mlPredictionsValue;
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
    _mlPredictions = service.runAllPredictions(bag);
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
    }) {
      final p = ml[key];
      if (p == null) return;
      if (p.classification != 'high' && p.riskProbability < 0.7) return;
      final via = p.usingModel ? 'TFLite' : 'offline calculator';
      findings.add(
        ClinicalFinding(
          label: label,
          detail:
              'Risk ${(p.riskProbability * 100).toStringAsFixed(0)}% ($via).',
          severity: severity,
          protocolSource: protocolSource,
          measuredValue: '${(p.riskProbability * 100).toStringAsFixed(1)}%',
          threshold: 'High risk',
        ),
      );
      if (referralUrgency != null) {
        actions.add(
          RecommendedAction(
            instruction: referralInstruction,
            urgency: referralUrgency,
            rationale:
                'High-risk signal (${(p.riskProbability * 100).toStringAsFixed(0)}%). '
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
        label: 'High risk of neonatal sepsis',
        protocolSource: 'WHO IMCI Young Infant 0–59 days (PSBI)',
        severity: TriageLevel.urgent,
        referralUrgency: ReferralUrgency.immediate,
        referralInstruction:
            'Refer urgently for possible severe bacterial infection (PSBI).',
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
                  _OverrideNote(engine: plan.overallTriage, chosen: effective),
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

          // --------------------------------------------- Offline AI predictions
          SectionCard(
            title: 'Offline AI risk predictions',
            icon: Icons.psychology_rounded,
            subtitle:
                'On-device TFLite INT8 models. If the .tflite weights have not yet shipped, these use calibrated deterministic fallback predictors with the exact same output shape. No internet, no PHI leaves the tablet.',
            child: FutureBuilder<Map<String, OfflineRiskPrediction>>(
              future: _mlPredictions,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(Gap.lg),
                      child: CircularProgressIndicator(),
                    ),
                  );
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
                final entries = predictions.entries.toList()
                  ..sort(
                    (a, b) => a.value.modelName.compareTo(b.value.modelName),
                  );
                if (entries.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(Gap.md),
                    child: Text('No models available on this device.'),
                  );
                }
                return Column(
                  children: entries.map((e) {
                    final p = e.value;
                    final Color badgeBg, badgeFg;
                    switch (p.classification) {
                      case 'high':
                        badgeBg = AppColors.triageRedBg;
                        badgeFg = AppColors.triageRed;
                      case 'moderate':
                        badgeBg = AppColors.triageAmberBg;
                        badgeFg = AppColors.triageAmber;
                      case 'low':
                      default:
                        badgeBg = AppColors.triageGreenBg;
                        badgeFg = AppColors.triageGreen;
                    }
                    return InkWell(
                      onTap: () {
                        showDialog<void>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text('${p.modelName} details'),
                            content: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('Model'),
                                    subtitle: Text(
                                      '${p.modelName} v${p.modelVersion ?? "?"}\n'
                                      '${p.usingModel ? "TFLite model" : "Rule-based fallback"} · '
                                      '${p.inferenceMs ?? 0} ms',
                                    ),
                                  ),
                                  const SizedBox(height: Gap.md),
                                  const Text(
                                    'Features used',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: Gap.sm),
                                  if (p.featuresUsed.isEmpty)
                                    const Text(
                                      'None',
                                      style: TextStyle(
                                        color: AppColors.inkFaint,
                                      ),
                                    )
                                  else
                                    ...p.featuresUsed.map(
                                      (f) => Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: Gap.xs,
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Icon(
                                              Icons.check_circle,
                                              size: 14,
                                              color: AppColors.triageGreen,
                                            ),
                                            const SizedBox(width: Gap.sm),
                                            Expanded(child: Text(f)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  const SizedBox(height: Gap.md),
                                  const Text(
                                    'Features missing',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: Gap.sm),
                                  if (p.featuresMissing.isEmpty)
                                    const Text(
                                      'None – complete!',
                                      style: TextStyle(
                                        color: AppColors.triageGreen,
                                      ),
                                    )
                                  else
                                    ...p.featuresMissing.map(
                                      (f) => Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: Gap.xs,
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Icon(
                                              Icons
                                                  .radio_button_unchecked_outlined,
                                              size: 14,
                                              color: AppColors.inkFaint,
                                            ),
                                            const SizedBox(width: Gap.sm),
                                            Expanded(child: Text(f)),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('Close'),
                              ),
                            ],
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: Gap.sm),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: badgeBg,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: badgeFg.withAlpha(90),
                                  width: 1,
                                ),
                              ),
                              child: Icon(
                                Icons.analytics_outlined,
                                color: badgeFg,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: Gap.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${p.modelName} ${p.usingModel ? "✓" : "(fallback)"}',
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w800,
                                      height: 1.3,
                                    ),
                                  ),
                                  const SizedBox(height: Gap.xs),
                                  Text(
                                    'Risk ${(p.riskProbability * 100).toStringAsFixed(1)}% · '
                                    '${p.featuresUsed.length} of '
                                    '${p.featuresUsed.length + p.featuresMissing.length} features used · '
                                    '${p.inferenceMs ?? 0} ms · '
                                    'model v${p.modelVersion ?? "?"}',
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: AppColors.inkMuted,
                                      height: 1.4,
                                    ),
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
                                borderRadius: BorderRadius.circular(
                                  Gap.radiusSm,
                                ),
                                border: Border.all(
                                  color: badgeFg.withValues(alpha: 0.4),
                                ),
                              ),
                              child: Text(
                                p.classification,
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
                    );
                  }).toList(),
                );
              },
            ),
          ),
          const SizedBox(height: Gap.lg),

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
                children: [for (final a in plan.actions) _ActionTile(a)],
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
