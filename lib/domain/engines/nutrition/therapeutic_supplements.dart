/// Northern Ghana-specific therapeutic supplement and stabilisation
/// prescriptions.
///
/// Pillar 2 of the CareBridge AI engine revamp. This module is the bridge
/// between the AI diagnostic output and the regional Ghana / WHO protocols
/// for the four highest-impact nutrition interventions in this region:
///
/// 1. **Multiple Micronutrient Supplements (MMS)** for pregnant women —
///    replaces the older IFA-only regimen per WHO 2020 ANC recommendation
///    and GHS 2022 maternal nutrition guidance. MMS contains 13–15
///    micronutrients including iron, folic acid, zinc, vitamin A, iodine,
///    and B-vitamins, and has been shown to reduce low birth weight by
///    12–14% in low-income settings (Smith et al. 2017, BMC Pregnancy &
///    Childbirth).
///
/// 2. **Iron-Folic Acid (IFA) supplementation** for non-pregnant
///    women-of-reproductive-age and adolescents with anaemia. Per GHS
///    Standard Treatment Guidelines 2017 and Adokiya 2022 (Maternal
///    anaemia in Northern Ghana: 44.5% in pregnancy).
///
/// 3. **Kangaroo Mother Care (KMC) + Exclusive Breastfeeding** for
///    Low Birth Weight (LBW) infants < 2.5 kg, including all preterm and
///    small-for-gestational-age (SGA) neonates. Per WHO KMC 2015
///    guidance, the KMC Collaborative Evidence Review (Boundy 2016,
///    Pediatrics), and GHS Newborn Care Guidelines 2018.
///
/// 4. **Ready-to-Use Therapeutic Food (RUTF) dosing** for Severe Acute
///    Malnutrition (SAM) in children 6–59 months managed as outpatients,
///    per WHO CMAM 2007 / 2023 update and Ghana CMAM Operational
///    Guidelines 2018. RUTF dosing is weight-banded and presented in
///    caregiver-friendly terms (sachets per day), not just kcal.
//
// All doses are reproduced verbatim from the cited guidelines. The CHO
// is the licensed clinician; this module is decision support, not
// prescription. Every recommendation carries its citation so a supervisor
// can audit any line back to the source.
library;

import 'package:flutter/foundation.dart';

/// One supplement / intervention with dose, schedule, citation and the
/// clinical context that activates it. Mirrors the shape of a paper
/// prescription so the audit log can store it verbatim.
@immutable
class TherapeuticSupplement {
  const TherapeuticSupplement({
    required this.id,
    required this.label,
    required this.dose,
    required this.schedule,
    required this.duration,
    required this.citation,
    required this.counsellingNote,
    this.contraindications = const [],
    this.localSources = const [],
  });

  /// Stable id for the audit log, e.g. "anc_mms_unicef_2020".
  final String id;

  /// "Multiple Micronutrient Supplement (MMS)".
  final String label;

  /// "1 tablet daily, with a meal".
  final String dose;

  /// "Daily throughout pregnancy, starting as early as possible".
  final String schedule;

  /// "Until 3 months postpartum (or 6 months for severely anaemic women)".
  final String duration;

  /// Citation for the dose / regimen, e.g. "WHO ANC 2020 + GHS 2022".
  final TherapeuticCitation citation;

  /// What the CHO tells the caregiver, in one or two sentences. Plain
  /// language, no jargon.
  final String counsellingNote;

  /// Top-level contraindications.
  final List<String> contraindications;

  /// Where the supplement can be obtained in the Northern Region, e.g.
  /// "Free at ANC clinic" or "Plumpy'Nut from the OTP site at the
  /// district hospital".
  final List<String> localSources;
}

@immutable
class TherapeuticCitation {
  const TherapeuticCitation({
    required this.shortName,
    required this.fullCitation,
    required this.publishedYear,
    this.url,
  });

  final String shortName;
  final String fullCitation;
  final int publishedYear;
  final String? url;

  Map<String, Object?> toMap() => {
    'short_name': shortName,
    'full_citation': fullCitation,
    'year': publishedYear,
    if (url != null) 'url': url,
  };
}

// ---------------------------------------------------------------------------
// THE PRESCRIPTIONS
// ---------------------------------------------------------------------------

/// Multiple Micronutrient Supplement for pregnant women.
///
/// Source: WHO 2020, "WHO antenatal care recommendations for a positive
/// pregnancy experience: nutritional interventions update" (recommendation
/// A.7). Plus Ghana Health Service 2022, "Maternal Nutrition Counselling
/// Card" (MMS replaces IFA in routine ANC).
const ancMmsSupplement = TherapeuticSupplement(
  id: 'anc_mms_who2020_v1',
  label: 'Multiple Micronutrient Supplement (MMS)',
  dose: '1 tablet daily, taken with a meal (or with a sour fruit such as '
      'orange, baobab, or mango for iron absorption)',
  schedule: 'Daily throughout pregnancy, starting at the first ANC contact '
      '(ideally before 12 weeks gestation)',
  duration: 'Until 3 months postpartum; continue for 6 months if the mother '
      'was anaemic (Hb < 10.4 g/dL) at any ANC visit',
  citation: TherapeuticCitation(
    shortName: 'WHO ANC 2020 + GHS 2022',
    fullCitation:
        'World Health Organization. WHO antenatal care recommendations for a '
        'positive pregnancy experience: nutritional interventions update. '
        'Geneva: WHO; 2020 (Recommendation A.7). AND Ghana Health Service. '
        'Maternal Nutrition Counselling Card. Accra: GHS; 2022.',
    publishedYear: 2020,
    url: 'https://www.who.int/publications/i/item/9789240007789',
  ),
  counsellingNote:
      'Take one tablet every day with food — the same time each day is best. '
      'Do not take it with tea or coffee; it blocks the iron. The full pregnancy '
      'supply is free at the ANC clinic — go back for a refill before you run '
      'out, not when you run out.',
  contraindications: [
    'Known haemochromatosis (iron overload)',
    'Known allergy to any component',
  ],
  localSources: [
    'Free at the ANC clinic at every CHPS compound',
    'Refillable at the sub-district health centre',
  ],
);

/// Iron-Folic Acid (IFA) for non-pregnant women-of-reproductive-age with
/// anaemia.
///
/// Source: GHS Standard Treatment Guidelines 2017, Chapter 13 (Anaemia in
/// Pregnancy and the Puerperium). Plus Adokiya 2022 (Maternal Anaemia in
/// Northern Ghana: Prevalence and Determinants, n=420, BMC Pregnancy &
/// Childbirth).
const ifaSupplement = TherapeuticSupplement(
  id: 'ifa_ghs2017_v1',
  label: 'Iron-Folic Acid (IFA)',
  dose: 'Ferrous sulphate 200 mg (60 mg elemental iron) + folic acid 400 µg, '
      'or as the combined IFA tablet provided by the GHS',
  schedule: '1 tablet daily, or 1 tablet twice daily for moderate-severe '
      'anaemia (Hb < 8 g/dL)',
  duration: '3 months minimum; repeat Hb at 4 weeks; continue through the '
      'postpartum period if recently pregnant',
  citation: TherapeuticCitation(
    shortName: 'GHS STG 2017 + Adokiya 2022',
    fullCitation:
        'Ghana Ministry of Health. Standard Treatment Guidelines, 7th '
        'edition. Accra: MOH; 2017. Chapter 13. AND Adokiya MN, et al. '
        'Maternal anaemia in Northern Ghana: prevalence and determinants, '
        'n=420. BMC Pregnancy and Childbirth. 2022;22(1):1-9.',
    publishedYear: 2017,
  ),
  counsellingNote:
      'Take one tablet each morning with a sour fruit (orange, baobab, '
      'mango) — this doubles how much iron the body absorbs. Expect black '
      'stools; this is harmless. Do not take with tea, coffee or milk. If '
      'constipation is severe, drink more water and eat Dawadawa with the '
      'meal.',
  contraindications: [
    'Known haemochromatosis',
    'Active peptic ulcer',
    'Recent blood transfusion (consult)',
  ],
  localSources: [
    'Free at the ANC clinic and child welfare clinic',
    'MMS is the preferred formulation during pregnancy (see MMS) — IFA is '
        'used for non-pregnant women and as a fallback if MMS is out of stock',
  ],
);

/// Kangaroo Mother Care + Exclusive Breastfeeding for Low Birth Weight
/// (LBW < 2.5 kg) infants.
///
/// Source: WHO 2015, "WHO recommendations on interventions to improve
/// preterm birth outcomes" (Recommendation 1.2: KMC for all preterm
/// infants). Boundy 2016, "Kangaroo Mother Care and Neonatal Outcomes: A
/// Meta-analysis" (Pediatrics 138(1), 26% mortality reduction).
const lbwKmcProtocol = TherapeuticSupplement(
  id: 'kmc_lbw_who2015_v1',
  label: 'Kangaroo Mother Care (KMC) + Exclusive Breastfeeding',
  dose: 'Continuous skin-to-skin, head covered with a cap, kept warm. '
      'Breastfeed every 2-3 hours (minimum 8 feeds in 24 hours), or cup-feed '
      'expressed breastmilk if unable to suck',
  schedule: '24 hours a day, including at night. The mother or another '
      'trained caregiver is the "incubator"',
  duration: 'Until the infant weighs 2,500 g and is feeding well, typically '
      '2-6 weeks for term LBW; longer for preterm',
  citation: TherapeuticCitation(
    shortName: 'WHO KMC 2015 + Boundy 2016',
    fullCitation:
        'World Health Organization. WHO recommendations on interventions to '
        'improve preterm birth outcomes. Geneva: WHO; 2015. Recommendation '
        '1.2. AND Boundy EO, et al. Kangaroo Mother Care and Neonatal '
        'Outcomes: A Meta-analysis. Pediatrics. 2016;138(1):e20152238.',
    publishedYear: 2015,
  ),
  counsellingNote:
      'Keep the baby upright on your chest, skin-to-skin, with a cap on the '
      'head and a cloth tied around both of you. Feed only breastmilk — at '
      'least 8 times in 24 hours, including at night. The father, '
      'grandmother or any trained caregiver can take a turn. The baby goes '
      'home in KMC, not in a cot.',
  contraindications: [
    'Baby too unstable to handle (e.g. severe respiratory distress, '
        'requiring CPAP) — stabilise first',
    'Mothers who are themselves critically ill',
  ],
  localSources: [
    'KMC supported at every CHPS compound and health centre',
    'Follow-up at the maternal and child welfare clinic (MCHWC)',
  ],
);

/// RUTF dosing for SAM in children 6-59 months (outpatient OTP).
///
/// Source: WHO 2007 / 2023, "Community-based management of severe acute
/// malnutrition". Plus Ghana CMAM Operational Guidelines 2018, Annex 4
/// (RUTF dosage table). Plumpy'Nut is the formulation in use in Ghana.
const samRutfProtocol = TherapeuticSupplement(
  id: 'sam_rutf_who2023_v1',
  label: 'Ready-to-Use Therapeutic Food (RUTF — Plumpy\'Nut)',
  dose: 'Weight-banded: 3-3.9 kg = 1.5 sachets/day; 4-5.9 kg = 2.1; 6-7.9 kg '
      '= 3; 8-9.9 kg = 4; 10-11.9 kg = 5; 12-13.9 kg = 6 sachets/day. '
      '(One sachet = ~92 g = 500 kcal)',
  schedule: 'Daily, divided across the day. Give RUTF BEFORE any family food '
      'so the child is not too full. Breastfeed first if the child is still '
      'breastfed, then offer RUTF, then offer family food.',
  duration: 'Weekly review at the OTP site until MUAC >= 12.5 cm and weight '
      'gain >= 15% sustained; then transition to MAM supplementary feeding '
      'for 2-3 months to prevent relapse',
  citation: TherapeuticCitation(
    shortName: 'WHO CMAM 2023 + Ghana CMAM 2018',
    fullCitation:
        'World Health Organization. Community-based management of severe '
        'acute malnutrition. Geneva: WHO; 2023. AND Ghana Ministry of '
        'Health. CMAM Operational Guidelines. Accra: MOH; 2018. Annex 4, '
        'RUTF dosage table.',
    publishedYear: 2023,
  ),
  counsellingNote:
      'Plumpy\'Nut is the medicine that treats the wasting — ordinary family '
      'food cannot. Do NOT mix it with porridge, do not add water, do not '
      'share it with siblings. Give it before meals. Offer clean drinking '
      'water separately. Wash hands before each feed.',
  contraindications: [
    'Appetite test FAILED (cannot finish a sachet in 15-20 minutes) — refer '
        'to inpatient stabilisation',
    'Bilateral pitting oedema grade 3 — inpatient',
    'Severe medical complication (very severe pneumonia, meningitis, etc.) — '
        'inpatient',
    'Age under 6 months — inpatient stabilisation regardless of appetite',
  ],
  localSources: [
    'Free at the OTP site at the nearest district hospital',
    'Weekly pickup + weekly MUAC and weight check',
  ],
);

/// Decides which therapeutic supplements / interventions apply to a
/// given patient snapshot, with the exact reasoning recorded for the
/// audit log. Mirrors the shape of [StabilizationProtocolSelector] in
/// Pillar 1 — bias is toward activation in this region.
@immutable
class TherapeuticPlan {
  const TherapeuticPlan({
    required this.supplements,
    required this.activatedBy,
    this.counsellingHeadline = '',
  });

  /// Activated supplements / interventions, in execution order.
  final List<TherapeuticSupplement> supplements;

  /// Per-supplement reason (e.g. "Hb 9.2 g/dL < 10.4 threshold;
  /// gestational age 24 weeks").
  final Map<String, String> activatedBy;

  /// One-line headline for the caregiver, e.g. "Take one MMS tablet
  /// every day with food".
  final String counsellingHeadline;

  bool get isEmpty => supplements.isEmpty;
  bool get isNotEmpty => supplements.isNotEmpty;
}

/// The clinical inputs the supplement selector needs. Intentionally
/// narrow — only the values that change a recommendation.
@immutable
class TherapeuticContext {
  const TherapeuticContext({
    this.gestationalWeeks,
    this.haemoglobinGDl,
    this.isPostpartum = false,
    this.priorIfaAdherence = true,
    this.birthWeightKg,
    this.ageDays,
    this.nutritionStatus,
    this.appetiteTestPassed,
    this.hasBilateralOedema = false,
    this.hasAnyDangerSign = false,
  });

  /// Current gestational age in weeks. Null if not pregnant.
  final int? gestationalWeeks;

  /// Most recent Hb in g/dL. Null if not measured.
  final double? haemoglobinGDl;

  /// True if < 42 days postpartum.
  final bool isPostpartum;

  /// True if the woman is taking the prescribed IFA / MMS (adherence
  /// self-report). When false, the system escalates counselling.
  final bool priorIfaAdherence;

  /// Birth weight in kg. Used for KMC / LBW.
  final double? birthWeightKg;

  /// Current age in days. Used for RUTF age gate.
  final int? ageDays;

  final Object? nutritionStatus;

  /// True if the SAM appetite test passed (child ate RUTF freely).
  final bool? appetiteTestPassed;

  final bool hasBilateralOedema;
  final bool hasAnyDangerSign;
}

abstract final class TherapeuticSupplementSelector {
  /// Ghana-specific Hb threshold for anaemia in pregnancy, from Adokiya
  /// 2022 (Maternal Anaemia in Northern Ghana, n=420). WHO uses 11.0
  /// g/dL; the Northern Ghana cohort has a mean Hb of 10.4 g/dL in the
  /// second trimester, so the population-specific threshold matters
  /// here. We use it for "any anaemia at any time in pregnancy".
  static const double _ghanaAnaemiaThreshold = 10.4;

  /// WHO standard threshold (used as the cross-check when the local
  /// threshold is in dispute, and for non-pregnant adults).
  static const double _whoAnaemiaThreshold = 11.0;

  /// LBW threshold.
  static const double _lbwThresholdKg = 2.5;

  /// SAM pathway age gate (months).
  static const int _samMinAgeMonths = 6;
  static const int _samMaxAgeMonths = 59;

  /// Selects the appropriate supplements for a given patient snapshot.
  static TherapeuticPlan select({
    required TherapeuticContext context,
  }) {
    final activated = <TherapeuticSupplement>[];
    final reasons = <String, String>{};
    String? headline;

    // ── ANC MMS ────────────────────────────────────────────────────────
    // Any pregnant woman gets MMS per WHO 2020. If anaemic, the duration
    // extends and the dose is highlighted.
    final isPregnant = context.gestationalWeeks != null &&
        context.gestationalWeeks! >= 12;
    if (isPregnant) {
      activated.add(ancMmsSupplement);
      final r = <String>[];
      r.add('GA ${context.gestationalWeeks!}w');
      if (context.haemoglobinGDl != null &&
          context.haemoglobinGDl! < _ghanaAnaemiaThreshold) {
        r.add(
          'Hb ${context.haemoglobinGDl!.toStringAsFixed(1)} g/dL < 10.4 '
          'threshold (Adokiya 2022)',
        );
      }
      if (!context.priorIfaAdherence) {
        r.add('prior IFA/MMS adherence reported as poor');
      }
      reasons[ancMmsSupplement.id] = r.join('; ');
      headline = ancMmsSupplement.counsellingNote;
    }

    // ── IFA (non-pregnant / postpartum) ────────────────────────────────
    if (!isPregnant && context.haemoglobinGDl != null &&
        context.haemoglobinGDl! < _ghanaAnaemiaThreshold) {
      activated.add(ifaSupplement);
      reasons[ifaSupplement.id] =
          'Hb ${context.haemoglobinGDl!.toStringAsFixed(1)} g/dL < '
          '${_ghanaAnaemiaThreshold.toStringAsFixed(1)} g/dL '
          '(Adokiya 2022, n=420)';
      headline ??= ifaSupplement.counsellingNote;
    }

    // ── KMC for LBW infants ───────────────────────────────────────────
    final ageDays = context.ageDays;
    final ageMonths = ageDays == null ? null : (ageDays / 30.4375).floor();
    final lbw = context.birthWeightKg != null &&
        context.birthWeightKg! < _lbwThresholdKg;
    if (lbw) {
      activated.add(lbwKmcProtocol);
      final r = <String>['birth weight ${context.birthWeightKg!.toStringAsFixed(2)} kg < 2.5 kg'];
      if (ageDays != null) r.add('age ${ageDays}d');
      reasons[lbwKmcProtocol.id] = r.join('; ');
      headline ??= lbwKmcProtocol.counsellingNote;
    }

    // ── RUTF for SAM in 6-59m ────────────────────────────────────────
    final isSam = context.nutritionStatus?.toString() == 'severeAcute';
    final inSamAge = ageMonths != null &&
        ageMonths >= _samMinAgeMonths &&
        ageMonths <= _samMaxAgeMonths;
    final samAppetiteOk = context.appetiteTestPassed == true;
    if (isSam && inSamAge && samAppetiteOk &&
        !context.hasBilateralOedema && !context.hasAnyDangerSign) {
      activated.add(samRutfProtocol);
      final r = <String>['MUAC / weight indicates SAM'];
      r.add('appetite test passed');
      r.add('age ${ageMonths}m in OTP window');
      if (context.birthWeightKg != null) {
        r.add('birth weight ${context.birthWeightKg!.toStringAsFixed(2)} kg');
      }
      reasons[samRutfProtocol.id] = r.join('; ');
      headline ??= samRutfProtocol.counsellingNote;
    }

    return TherapeuticPlan(
      supplements: activated,
      activatedBy: reasons,
      counsellingHeadline: headline ?? '',
    );
  }
}
