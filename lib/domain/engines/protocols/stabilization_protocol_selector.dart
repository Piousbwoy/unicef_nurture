/// Pre-referral stabilization protocol selector.
///
/// Given an observed clinical snapshot, this module
/// returns the set of [StabilizationProtocol]s that the CHO should see
/// at the top of the result screen BEFORE the rest of the care plan.
///
/// Activations use observed clinical indications and cohort eligibility.
/// Experimental scores never initiate medication or replace clinical review.
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
    this.patientAgeMonths,
    this.isMaternal = false,
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
  final int? patientAgeMonths;
  final bool isMaternal;

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

/// The activated protocols and their observed clinical indications.
/// A non-empty list MUST be rendered before any other care-plan content;
/// the empty list means "no pre-referral protocol activated, proceed to
/// the regular care plan".
@immutable
class StabilizationPlan {
  const StabilizationPlan({required this.protocols, required this.activatedBy});

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
    this.neonatalSepsisRuleInCandidate,
  });

  /// Legacy transport fields. Ignored for every clinical decision.
  final double? preeclampsiaRisk;
  final double? neonatalSepsisRisk;
  final double? childPneumoniaRisk;
  final double? lbwSgaRisk;

  /// Legacy flag retained for source compatibility; never activates care.
  final bool? neonatalSepsisRuleInCandidate;

  factory StabilizationAiRisks.fromPredictions(
    Map<String, OfflineRiskPrediction>? predictions,
  ) {
    return const StabilizationAiRisks();
  }
}

/// Existing protocol thresholds, independent of model execution.
class _StabThresholds {
  // WHO IMCI severe hypertension = 160/110 (matches WHO 2011 PE guideline)
  static const severeSbp = 160;
  static const severeDbp = 110;
  // GHS / WHO gestational hypertension threshold
  static const gestationalSbp = 140;
  // PSBI age limit
  static const psbiMaxAgeDays = 59;
  // Child pneumonia age range
  static const childPneumoniaMinAgeDays = 60;
  static const childPneumoniaMaxAgeDays = 1825;
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
  ///   * systolic >= 160 OR diastolic >= 110 (WHO severe hypertension)
  ///   * eclampsia convulsions observed
  ///   * systolic >= 140 AND proteinuria >= 1+ (gestational hypertension
  ///     with proteinuria = pre-eclampsia per ISSHP 2021)
  ///
  /// **Young-infant PSBI protocol** when ALL of:
  ///   * age 0-59 days
  ///   * any applicable IMCI danger sign present
  ///   * (convulsions, unable to feed, lethargic/unconscious, severe chest
  ///     indrawing, bulging fontanelle, fever >= 37.5 or hypothermia
  ///     < 35.5, cord pus with skin extension, etc.)
  ///
  /// **Child pneumonia protocol** when ALL of:
  ///   * age 2-59 months
  ///   * cough AND (severe chest indrawing OR general danger sign OR SaO2 < 90)
  StabilizationPlan select({
    required StabilizationContext context,
    required StabilizationAiRisks risks,
  }) {
    final activated = <StabilizationProtocol>[];
    final reasons = <String, String>{};

    // ── Pre-eclampsia ────────────────────────────────────────────────────
    final maternal =
        context.isMaternal ||
        (context.patientAgeDays == null && context.gestationalWeeks != null);
    final sbp = context.systolicBp;
    final dbp = context.diastolicBp;
    final protein = context.urineProtein0To4 ?? 0;
    final severeHt =
        (sbp != null && sbp >= _StabThresholds.severeSbp) ||
        (dbp != null && dbp >= _StabThresholds.severeDbp);
    final gestationalHtWithProtein =
        sbp != null && sbp >= _StabThresholds.gestationalSbp && protein >= 1;
    final eclampsia = context.hasEclampsiaConvulsions;

    if (maternal && (severeHt || eclampsia || gestationalHtWithProtein)) {
      activated.add(preEclampsiaProtocol);
      final r = <String>[];
      if (severeHt) r.add('BP $sbp/$dbp >= 160/110');
      if (eclampsia) r.add('eclamptic convulsions observed');
      if (gestationalHtWithProtein) {
        r.add('gestational HTN + proteinuria ($protein+)');
      }
      reasons[preEclampsiaProtocol.id] = r.join('; ');
    }

    // ── Young-infant PSBI ────────────────────────────────────────────────
    final ageDays = context.patientAgeDays;
    final inPsbiAge =
        !maternal &&
        ageDays != null &&
        ageDays >= 0 &&
        ageDays <= _StabThresholds.psbiMaxAgeDays;
    final psbiDanger = _psbiDangerSignPresent(context);
    if (inPsbiAge && psbiDanger) {
      activated.add(psbiProtocol);
      final r = <String>[];
      if (psbiDanger) {
        r.add('IMCI danger sign present');
      }
      r.add('age ${ageDays}d');
      reasons[psbiProtocol.id] = r.join('; ');
    }

    // ── Child pneumonia ─────────────────────────────────────────────────
    final months = context.patientAgeMonths;
    final inPneuAge =
        !maternal &&
        (months != null
            ? months >= 2 && months <= 59
            : ageDays != null &&
                  ageDays >= _StabThresholds.childPneumoniaMinAgeDays &&
                  ageDays < _StabThresholds.childPneumoniaMaxAgeDays);
    final severeHypoxia =
        context.oxygenSaturation != null &&
        context.oxygenSaturation! < _StabThresholds.severeHypoxia;
    final dangerPneumonia =
        context.coughPresent &&
        (context.severeChestIndrawing ||
            context.generalDangerSign ||
            severeHypoxia);
    if (inPneuAge && dangerPneumonia) {
      activated.add(childPneumoniaProtocol);
      final r = <String>[];
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
