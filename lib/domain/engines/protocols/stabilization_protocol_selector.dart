/// Pre-referral stabilization protocol selector.
///
/// Given the AI risk predictions and a clinical snapshot, this module
/// returns the set of [StabilizationProtocol]s that the CHO should see
/// at the top of the result screen BEFORE the rest of the care plan.
///
/// Selection is biased toward activation. In the rural CHPS setting, the
/// cost of missing a pre-referral dose of MgSO4 or ampicillin is a dead
/// patient two hours down a flooded road; the cost of activating a
/// protocol the patient did not strictly need is a wasted minute at the
/// compound. The asymmetry justifies the bias.
///
/// Triggers combine the AI risk with hard clinical thresholds from the
/// underlying WHO / MOH guidance, so the protocol activates even when the
/// AI is unavailable (using the deterministic fallback output).
library;

import 'package:flutter/foundation.dart';

import '../../../core/ml/offline_inference_service.dart';
import 'stabilization_protocols.dart';

/// Minimal clinical context the selector needs to make a decision. We
/// avoid depending on the full [AssessmentContext] / [PregnancyInput] /
/// [YoungInfantInput] so this module is unit-testable in isolation.
@immutable
class StabilizationContext {
  const StabilizationContext({
    this.patientAgeDays,
    this.gestationalWeeks,
    this.systolicBp,
    this.diastolicBp,
    this.urineProtein0To4,
    this.hasEclampsiaConvulsions = false,
    this.temperatureCelsius,
    this.oxygenSaturation,
    this.respiratoryRate,
    this.unableToFeed = false,
    this.convulsions = false,
    this.severeChestIndrawing = false,
    this.bulgingFontanelle = false,
    this.lethargicOrUnconscious = false,
    this.historyOfConvulsions = false,
    this.cordPus = false,
    this.feedingDifficulty = false,
    this.skinPustules = false,
    this.coughPresent = false,
    this.generalDangerSign = false,
  });

  /// Patient age in days. For adults / pregnancies, leave null and use
  /// [gestationalWeeks].
  final int? patientAgeDays;

  /// Gestational age in weeks (>= 20 means an ANC assessment).
  final int? gestationalWeeks;

  // ── ANC / pre-eclampsia signals ───────────────────────────────────────
  final int? systolicBp;
  final int? diastolicBp;
  final int? urineProtein0To4;
  final bool hasEclampsiaConvulsions;

  // ── Young-infant (0-59 d) IMCI danger signs ──────────────────────────
  final double? temperatureCelsius;
  final int? oxygenSaturation;
  final int? respiratoryRate;
  final bool unableToFeed;
  final bool convulsions;
  final bool severeChestIndrawing;
  final bool bulgingFontanelle;
  final bool lethargicOrUnconscious;
  final bool historyOfConvulsions;
  final bool cordPus;
  final bool feedingDifficulty;
  final bool skinPustules;

  // ── Child (2-59 m) IMCI signals ──────────────────────────────────────
  final bool coughPresent;
  final bool generalDangerSign;
}

/// The set of activated protocols, plus the AI risks that activated them.
/// A non-empty list MUST be rendered before any other care-plan content;
/// the empty list means "no pre-referral protocol activated, proceed to
/// the regular care plan".
@immutable
class StabilizationPlan {
  const StabilizationPlan({
    required this.protocols,
    required this.activatedBy,
  });

  final List<StabilizationProtocol> protocols;
  final Map<String, String> activatedBy;

  bool get isEmpty => protocols.isEmpty;
  bool get isNotEmpty => protocols.isNotEmpty;
}

/// The set of AI risk predictions the selector needs. Each nullable
/// because the upstream assessor may not have run all four.
@immutable
class StabilizationAiRisks {
  const StabilizationAiRisks({
    this.preeclampsiaRisk,
    this.neonatalSepsisRisk,
    this.childPneumoniaRisk,
    this.lbwSgaRisk,
  });

  /// 0..1 calibrated probability.
  final double? preeclampsiaRisk;
  final double? neonatalSepsisRisk;
  final double? childPneumoniaRisk;
  final double? lbwSgaRisk;

  factory StabilizationAiRisks.fromPredictions(
    Map<String, OfflineRiskPrediction>? predictions,
  ) {
    if (predictions == null) return const StabilizationAiRisks();
    return StabilizationAiRisks(
      preeclampsiaRisk: predictions['preeclampsia_risk']?.riskProbability,
      neonatalSepsisRisk: predictions['neonatal_sepsis']?.riskProbability,
      childPneumoniaRisk: predictions['child_pneumonia']?.riskProbability,
      lbwSgaRisk: predictions['lbw_sga']?.riskProbability,
    );
  }
}

/// GHS / WHO-aligned classification thresholds. These mirror the
/// `OfflineInferenceService._GhsThresholds` constants and the WHO IMCI
/// 2014 classification cutoffs.
class _StabThresholds {
  // TriageLevel.urgent threshold = 0.30 (neonatal sepsis) / 0.22 (preeclampsia)
  // TriageLevel.priority threshold = 0.28 (child pneumonia)
  static const peUrgent = 0.22;
  static const psbiUrgent = 0.30;
  static const pneumoniaUrgent = 0.28;

  // WHO IMCI severe hypertension = 160/110 (matches WHO 2011 PE guideline)
  static const severeSbp = 160;
  static const severeDbp = 110;
  // GHS / ACOG treatment threshold for severe hypertension = >= 160/110
  static const treatSbp = 160;
  static const treatDbp = 110;
  // GHS / WHO gestational hypertension threshold
  static const gestationalSbp = 140;
  static const gestationalDbp = 90;
  // PSBI age limit
  static const psbiMaxAgeDays = 59;
  // Child pneumonia age range
  static const childPneumoniaMinAgeDays = 60;
  static const childPneumoniaMaxAgeDays = 60 * 59;
  // Severe hypoxia
  static const severeHypoxia = 90;
}

class StabilizationProtocolSelector {
  const StabilizationProtocolSelector();

  /// Returns the list of activated protocols, plus a per-protocol reason
  /// string for the audit log.
  ///
  /// Activation logic (each line is "if TRUE, activate"):
  ///
  /// **Pre-eclampsia / eclampsia protocol** when ANY of:
  ///   * AI `preeclampsia_risk` >= 0.22 (the "urgent" triage threshold)
  ///   * systolic >= 160 OR diastolic >= 110 (WHO severe hypertension)
  ///   * eclampsia convulsions observed
  ///   * systolic >= 140 AND proteinuria >= 1+ (gestational hypertension
  ///     with proteinuria = pre-eclampsia per ISSHP 2021)
  ///
  /// **Young-infant PSBI protocol** when ALL of:
  ///   * age 0-59 days
  ///   * AI `neonatal_sepsis` >= 0.30 OR any IMCI danger sign present
  ///   * (convulsions, unable to feed, lethargic/unconscious, severe chest
  ///     indrawing, bulging fontanelle, fever >= 37.5 or hypothermia
  ///     < 35.5, cord pus with skin extension, etc.)
  ///
  /// **Child pneumonia protocol** when ALL of:
  ///   * age 2-59 months
  ///   * AI `child_pneumonia` >= 0.28 OR (cough AND (severe
  ///     chest indrawing OR general danger sign OR SaO2 < 90))
  StabilizationPlan select({
    required StabilizationContext context,
    required StabilizationAiRisks risks,
  }) {
    final activated = <StabilizationProtocol>[];
    final reasons = <String, String>{};

    // ── Pre-eclampsia ────────────────────────────────────────────────────
    final aiPe = risks.preeclampsiaRisk ?? 0.0;
    final sbp = context.systolicBp;
    final dbp = context.diastolicBp;
    final protein = context.urineProtein0To4 ?? 0;
    final aiPeHigh = aiPe >= _StabThresholds.peUrgent;
    final severeHt = (sbp != null && sbp >= _StabThresholds.severeSbp) ||
        (dbp != null && dbp >= _StabThresholds.severeDbp);
    final gestationalHtWithProtein =
        sbp != null && sbp >= _StabThresholds.gestationalSbp && protein >= 1;
    final eclampsia = context.hasEclampsiaConvulsions;

    if (aiPeHigh || severeHt || eclampsia || gestationalHtWithProtein) {
      activated.add(preEclampsiaProtocol);
      final r = <String>[];
      if (aiPeHigh) r.add('AI preeclampsia_risk=${aiPe.toStringAsFixed(2)}');
      if (severeHt) r.add('BP $sbp/$dbp >= 160/110');
      if (eclampsia) r.add('eclamptic convulsions observed');
      if (gestationalHtWithProtein) {
        r.add('gestational HTN + proteinuria ($protein+)');
      }
      reasons[preEclampsiaProtocol.id] = r.join('; ');
    }

    // ── Young-infant PSBI ────────────────────────────────────────────────
    final aiPsbi = risks.neonatalSepsisRisk ?? 0.0;
    final ageDays = context.patientAgeDays;
    final inPsbiAge =
        ageDays != null && ageDays <= _StabThresholds.psbiMaxAgeDays;
    final psbiDanger = _psbiDangerSignPresent(context);
    if (inPsbiAge && (aiPsbi >= _StabThresholds.psbiUrgent || psbiDanger)) {
      activated.add(psbiProtocol);
      final r = <String>[];
      if (aiPsbi >= _StabThresholds.psbiUrgent) {
        r.add('AI neonatal_sepsis=${aiPsbi.toStringAsFixed(2)}');
      }
      if (psbiDanger) {
        r.add('IMCI danger sign present');
      }
      r.add('age ${ageDays}d');
      reasons[psbiProtocol.id] = r.join('; ');
    }

    // ── Child pneumonia ─────────────────────────────────────────────────
    final aiPneu = risks.childPneumoniaRisk ?? 0.0;
    final inPneuAge = ageDays != null &&
        ageDays >= _StabThresholds.childPneumoniaMinAgeDays &&
        ageDays <= _StabThresholds.childPneumoniaMaxAgeDays;
    final severeHypoxia = context.oxygenSaturation != null &&
        context.oxygenSaturation! < _StabThresholds.severeHypoxia;
    final dangerPneumonia = context.coughPresent &&
        (context.severeChestIndrawing ||
            context.generalDangerSign ||
            severeHypoxia);
    if (inPneuAge &&
        (aiPneu >= _StabThresholds.pneumoniaUrgent || dangerPneumonia)) {
      activated.add(childPneumoniaProtocol);
      final r = <String>[];
      if (aiPneu >= _StabThresholds.pneumoniaUrgent) {
        r.add('AI child_pneumonia=${aiPneu.toStringAsFixed(2)}');
      }
      if (dangerPneumonia) {
        r.add('cough + severe chest indrawing / danger sign / SaO2 < 90');
      }
      r.add('age ${ageDays}d');
      reasons[childPneumoniaProtocol.id] = r.join('; ');
    }

    return StabilizationPlan(protocols: activated, activatedBy: reasons);
  }

  /// True if at least one of the WHO IMCI 2014 "pink row" danger signs
  /// for a young infant is present. These are the signs that mandate
  /// "URGENT referral + pre-referral antibiotic" per the chart booklet.
  static bool _psbiDangerSignPresent(StabilizationContext c) {
    if (c.convulsions) return true;
    if (c.unableToFeed) return true;
    if (c.lethargicOrUnconscious) return true;
    if (c.severeChestIndrawing) return true;
    if (c.bulgingFontanelle) return true;
    if (c.historyOfConvulsions) return true;
    // Fever >= 37.5 or hypothermia < 35.5 (WHO IMCI 2014)
    final t = c.temperatureCelsius;
    if (t != null && (t >= 37.5 || t < 35.5)) return true;
    // Hypoxia is in the IMCI "Severe pneumonia / very severe disease" row
    if (c.oxygenSaturation != null && c.oxygenSaturation! < 90) return true;
    // Tachypnoea: WHO IMCI fast breathing for 0-59d is >= 60
    if (c.respiratoryRate != null && c.respiratoryRate! >= 60) return true;
    // Local infection that has escalated
    if (c.cordPus) return true;
    if (c.skinPustules) return true;
    if (c.feedingDifficulty) return true;
    return false;
  }
}
