/// WHO IMCI — **Sick Young Infant, age 0 up to 2 months (0–59 days)**.
///
/// This is the highest-stakes engine in CareBridge. The Northern Region alone
/// accounted for 10% of Ghana's neonatal deaths between 2019 and 2023, and
/// birth asphyxia drove the rise in Upper East neonatal mortality. Young
/// infants deteriorate in hours, and almost every sign in this chart means
/// "refer now".
///
/// Classification and cut-offs follow the WHO IMCI chart booklet:
///   * Fast breathing in a young infant: **>= 60 breaths/minute**
///   * Fever: **>= 37.5 degrees C**   Hypothermia: **< 35.5 degrees C**
///   * Severe jaundice: onset < 24 hours of age, yellow palms/soles at any age,
///     or jaundice persisting beyond 14 days
///
/// Deliberate design choice: this engine is **biased toward referral**. In a
/// setting where the nearest theatre is two hours away over a flooded road, the
/// cost of a false alarm is a wasted trip; the cost of a missed sign is a dead
/// baby. Where data is missing, it says so and escalates rather than reassures.
library;

import '../enums.dart';
import '../entities/visit.dart';

const String _protocol = 'WHO IMCI — Sick Young Infant (0–59 days)';

/// Everything a CHO can observe on a young infant at a compound, using nothing
/// but their eyes, hands, a watch, a thermometer and a scale.
class YoungInfantInput {
  const YoungInfantInput({
    required this.ageInDays,
    this.respiratoryRate,
    this.temperatureCelsius,
    this.weightKg,
    this.birthWeightKg,
    this.gestationWeeksAtBirth,
    this.isMultipleBirth = false,
    this.deliveryPlace,
    this.requiredResuscitation = false,

    // Danger signs — the pink row of the chart.
    this.notFeedingWell = false,
    this.unableToFeedAtAll = false,
    this.convulsions = false,
    this.movesOnlyWhenStimulated = false,
    this.noMovementAtAll = false,
    this.severeChestIndrawing = false,
    this.bulgingFontanelle = false,

    // Local infection.
    this.umbilicusRedOrDraining = false,
    this.umbilicalRednessExtendsToSkin = false,
    this.skinPustulesCount = 0,

    // Jaundice.
    this.jaundicePresent = false,
    this.jaundiceOnsetWithin24Hours = false,
    this.yellowPalmsOrSoles = false,

    // Diarrhoea and dehydration.
    this.diarrhoea = false,
    this.sunkenEyes = false,
    this.skinPinchGoesBackVerySlowly = false,
    this.skinPinchGoesBackSlowly = false,
    this.restlessOrIrritable = false,
    this.bloodInStool = false,

    // Feeding assessment.
    this.breastfeedsPerDay,
    this.attachmentPoor = false,
    this.notSucklingEffectively = false,
    this.receivesOtherFoodsOrDrinks = false,
    this.oralThrush = false,
    this.breastfedWithinOneHourOfBirth,
  });

  final int ageInDays;
  final int? respiratoryRate;
  final double? temperatureCelsius;
  final double? weightKg;
  final double? birthWeightKg;
  final int? gestationWeeksAtBirth;
  final bool isMultipleBirth;
  final DeliveryPlace? deliveryPlace;
  final bool requiredResuscitation;

  final bool notFeedingWell;
  final bool unableToFeedAtAll;
  final bool convulsions;
  final bool movesOnlyWhenStimulated;
  final bool noMovementAtAll;
  final bool severeChestIndrawing;
  final bool bulgingFontanelle;

  final bool umbilicusRedOrDraining;
  final bool umbilicalRednessExtendsToSkin;
  final int skinPustulesCount;

  final bool jaundicePresent;
  final bool jaundiceOnsetWithin24Hours;
  final bool yellowPalmsOrSoles;

  final bool diarrhoea;
  final bool sunkenEyes;
  final bool skinPinchGoesBackVerySlowly;
  final bool skinPinchGoesBackSlowly;
  final bool restlessOrIrritable;
  final bool bloodInStool;

  final int? breastfeedsPerDay;
  final bool attachmentPoor;
  final bool notSucklingEffectively;
  final bool receivesOtherFoodsOrDrinks;
  final bool oralThrush;
  final bool? breastfedWithinOneHourOfBirth;

  bool get hasFastBreathing =>
      respiratoryRate != null && respiratoryRate! >= 60;
  bool get hasFever =>
      temperatureCelsius != null && temperatureCelsius! >= 37.5;
  bool get isHypothermic =>
      temperatureCelsius != null && temperatureCelsius! < 35.5;
  bool get isLowBirthWeight => birthWeightKg != null && birthWeightKg! < 2.5;
  bool get isPreterm =>
      gestationWeeksAtBirth != null && gestationWeeksAtBirth! < 37;

  /// The first week carries the overwhelming majority of neonatal deaths, and
  /// the chart treats several signs more severely inside it.
  bool get isFirstWeekOfLife => ageInDays < 7;
}

abstract final class YoungInfantEngine {
  static AssessmentResult assess(YoungInfantInput i) {
    final findings = <ClinicalFinding>[];
    final actions = <RecommendedAction>[];
    final dangerSigns = <String>[];
    final missing = <String>[];
    final capabilities = <String>{};

    // ---------------------------------------------------------------------
    // 1. CLINICAL SEVERE INFECTION / VERY SEVERE DISEASE  (pink — refer now)
    // ---------------------------------------------------------------------
    void severe(String label, String detail, {String? value, String? cutoff}) {
      findings.add(
        ClinicalFinding(
          label: label,
          detail: detail,
          severity: TriageLevel.urgent,
          protocolSource: _protocol,
          measuredValue: value,
          threshold: cutoff,
          weight: 10,
          isDangerSign: true,
        ),
      );
      dangerSigns.add(label);
    }

    if (i.unableToFeedAtAll) {
      severe(
        'Not able to feed at all',
        'An infant who cannot feed cannot maintain blood sugar or hydration. '
            'This is a sign of very severe disease.',
      );
    } else if (i.notFeedingWell) {
      severe(
        'Not feeding well',
        'Poor feeding is often the only early sign of sepsis in a newborn.',
      );
    }

    if (i.convulsions) {
      severe(
        'Convulsions',
        'Fits in a young infant indicate sepsis, meningitis, low blood sugar or '
            'birth asphyxia.',
      );
    }

    if (i.noMovementAtAll) {
      severe(
        'No movement at all',
        'Absent movement indicates very severe disease.',
      );
    } else if (i.movesOnlyWhenStimulated) {
      severe(
        'Moves only when stimulated',
        'Reduced activity is a cardinal sign of severe infection in a newborn.',
      );
    }

    if (i.severeChestIndrawing) {
      severe(
        'Severe chest indrawing',
        'The lower chest wall drawing in on breathing indicates severe '
            'respiratory distress.',
      );
    }

    if (i.hasFever) {
      severe(
        'Fever',
        'Temperature ${i.temperatureCelsius!.toStringAsFixed(1)} degrees C is at '
            'or above the 37.5 degrees C threshold. In an infant under 2 months '
            'any fever is treated as severe infection.',
        value: '${i.temperatureCelsius!.toStringAsFixed(1)} C',
        cutoff: '>= 37.5 C',
      );
    }

    if (i.isHypothermic) {
      severe(
        'Hypothermia',
        'Temperature ${i.temperatureCelsius!.toStringAsFixed(1)} degrees C is '
            'below 35.5 degrees C. A cold newborn is as dangerous as a hot one. '
            'Warm by skin-to-skin contact immediately, on the way to care.',
        value: '${i.temperatureCelsius!.toStringAsFixed(1)} C',
        cutoff: '< 35.5 C',
      );
    }

    if (i.bulgingFontanelle) {
      severe(
        'Bulging fontanelle',
        'Suggests meningitis or raised intracranial pressure.',
      );
    }

    if (i.umbilicalRednessExtendsToSkin) {
      severe(
        'Umbilical infection spreading to the skin',
        'Redness extending from the cord stump onto the abdominal wall means '
            'the infection has spread beyond the umbilicus.',
      );
    }

    if (i.skinPustulesCount >= 10) {
      severe(
        'Many skin pustules',
        '${i.skinPustulesCount} pustules — ten or more, or any large pustule, '
            'indicates severe skin infection.',
        value: '${i.skinPustulesCount} pustules',
        cutoff: '>= 10',
      );
    }

    // Fast breathing: severe in the first week, PNEUMONIA thereafter.
    if (i.hasFastBreathing && i.isFirstWeekOfLife) {
      severe(
        'Fast breathing in the first week of life',
        'Respiratory rate ${i.respiratoryRate} breaths per minute is at or above '
            '60. In an infant under 7 days old this is classified as severe '
            'disease, not simple pneumonia.',
        value: '${i.respiratoryRate}/min',
        cutoff: '>= 60/min',
      );
    }

    // ---------------------------------------------------------------------
    // 2. SEVERE JAUNDICE  (pink — refer now)
    // ---------------------------------------------------------------------
    if (i.jaundicePresent) {
      if (i.jaundiceOnsetWithin24Hours) {
        severe(
          'Severe jaundice — onset within 24 hours of birth',
          'Jaundice appearing in the first day of life is always severe and '
              'risks kernicterus (permanent brain damage).',
        );
      } else if (i.yellowPalmsOrSoles) {
        severe(
          'Severe jaundice — yellow palms and soles',
          'Yellow staining reaching the palms and soles indicates a high '
              'bilirubin level at any age.',
        );
      } else if (i.ageInDays > 14) {
        severe(
          'Prolonged jaundice — beyond 14 days',
          'Jaundice persisting past two weeks needs investigation for liver or '
              'metabolic disease.',
        );
      } else {
        findings.add(
          const ClinicalFinding(
            label: 'Jaundice',
            detail:
                'Jaundice after the first day, with palms and soles not yellow. '
                'Continue frequent breastfeeding and review in 1 day.',
            severity: TriageLevel.priority,
            protocolSource: _protocol,
            weight: 3,
          ),
        );
      }
    }

    // ---------------------------------------------------------------------
    // 3. DIARRHOEA AND DEHYDRATION
    // ---------------------------------------------------------------------
    if (i.diarrhoea) {
      final severeSignCount = [
        i.movesOnlyWhenStimulated || i.noMovementAtAll,
        i.sunkenEyes,
        i.skinPinchGoesBackVerySlowly,
      ].where((s) => s).length;

      if (severeSignCount >= 2) {
        severe(
          'Severe dehydration',
          'Two or more of: reduced movement, sunken eyes, skin pinch returning '
              'very slowly. Start IMCI Plan C and refer urgently.',
        );
        capabilities.add('intravenousFluids');
      } else {
        final someSignCount = [
          i.restlessOrIrritable,
          i.sunkenEyes,
          i.skinPinchGoesBackSlowly,
        ].where((s) => s).length;

        if (someSignCount >= 2) {
          findings.add(
            const ClinicalFinding(
              label: 'Some dehydration',
              detail:
                  'Two or more of: restless or irritable, sunken eyes, skin '
                  'pinch returning slowly. Any young infant with dehydration '
                  'needs referral — they have very little reserve.',
              severity: TriageLevel.urgent,
              protocolSource: _protocol,
              weight: 8,
              isDangerSign: true,
            ),
          );
          dangerSigns.add('Some dehydration');
        } else {
          findings.add(
            const ClinicalFinding(
              label: 'Diarrhoea, no dehydration',
              detail:
                  'Give ORS after every loose stool and continue breastfeeding '
                  'more often. Return immediately if the infant feeds poorly, '
                  'becomes less active, or the eyes look sunken.',
              severity: TriageLevel.priority,
              protocolSource: _protocol,
              weight: 3,
            ),
          );
        }
      }

      if (i.bloodInStool) {
        findings.add(
          const ClinicalFinding(
            label: 'Blood in the stool',
            detail:
                'Dysentery in a young infant requires urgent assessment at a '
                'facility.',
            severity: TriageLevel.urgent,
            protocolSource: _protocol,
            weight: 8,
            isDangerSign: true,
          ),
        );
        dangerSigns.add('Blood in stool');
      }
    }

    // ---------------------------------------------------------------------
    // 4. PNEUMONIA — fast breathing in a young infant 0–59 days is
    //    "SEVERE PNEUMONIA OR VERY SEVERE DISEASE" on the IMCI chart: it
    //    always needs urgent pre-referral treatment and referral. We never
    //    down-classify it to a home-treatable pneumonia inside this age band.
    // ---------------------------------------------------------------------
    if (i.hasFastBreathing && !i.isFirstWeekOfLife) {
      findings.add(
        ClinicalFinding(
          label: 'Severe pneumonia',
          detail:
              'Respiratory rate ${i.respiratoryRate} breaths per minute (>= 60) '
              'in an infant aged ${i.ageInDays} days. Per IMCI this is severe '
              'pneumonia in a young infant and needs urgent referral after the '
              'first dose of antibiotic.',
          severity: TriageLevel.urgent,
          protocolSource: _protocol,
          measuredValue: '${i.respiratoryRate}/min',
          threshold: '>= 60/min',
          weight: 8,
          isDangerSign: true,
        ),
      );
      actions.add(
        const RecommendedAction(
          instruction:
              'Give first dose of intramuscular or oral amoxicillin before '
              'leaving, treat to prevent low blood sugar, keep the infant '
              'warm, and refer URGENTLY',
          urgency: ReferralUrgency.immediate,
          rationale:
              'WHO IMCI: in a young infant 0–59 days, fast breathing is '
              'classified as severe pneumonia / very severe disease and must '
              'be referred, not treated at home.',
          protocolSource: _protocol,
          isReferral: true,
        ),
      );
    }

    // ---------------------------------------------------------------------
    // 5. LOCAL BACTERIAL INFECTION
    // ---------------------------------------------------------------------
    if ((i.umbilicusRedOrDraining && !i.umbilicalRednessExtendsToSkin) ||
        (i.skinPustulesCount > 0 && i.skinPustulesCount < 10)) {
      findings.add(
        ClinicalFinding(
          label: 'Local bacterial infection',
          detail: i.umbilicusRedOrDraining
              ? 'Umbilicus red or draining pus, not extending to the skin. '
                    'Treat with oral amoxicillin, teach the mother to keep the '
                    'cord clean and dry, and review in 2 days.'
              : '${i.skinPustulesCount} skin pustules (fewer than 10). Treat '
                    'with oral amoxicillin and local care, review in 2 days.',
          severity: TriageLevel.priority,
          protocolSource: _protocol,
          weight: 4,
        ),
      );
      actions.add(
        const RecommendedAction(
          instruction:
              'Give oral amoxicillin for 5 days, apply local treatment, and '
              'review in 2 days',
          urgency: ReferralUrgency.sameDay,
          protocolSource: _protocol,
          isTreatment: true,
        ),
      );
    }

    // ---------------------------------------------------------------------
    // 6. FEEDING PROBLEM OR LOW WEIGHT
    // ---------------------------------------------------------------------
    final feedingProblems = <String>[
      if (i.attachmentPoor) 'not well attached to the breast',
      if (i.notSucklingEffectively) 'not suckling effectively',
      if (i.breastfeedsPerDay != null && i.breastfeedsPerDay! < 8)
        'breastfeeding only ${i.breastfeedsPerDay} times in 24 hours (fewer than 8)',
      if (i.receivesOtherFoodsOrDrinks)
        'receiving other foods or drinks before 6 months',
      if (i.oralThrush) 'oral thrush',
    ];

    if (feedingProblems.isNotEmpty) {
      findings.add(
        ClinicalFinding(
          label: 'Feeding problem',
          detail:
              'Found: ${feedingProblems.join('; ')}. Counsel the mother on '
              'positioning and attachment, and review in 2 days.',
          severity: TriageLevel.priority,
          protocolSource: _protocol,
          weight: 3,
        ),
      );
      actions.add(
        const RecommendedAction(
          instruction:
              'Observe a full breastfeed, correct positioning and attachment, '
              'then review in 2 days',
          urgency: ReferralUrgency.withinTwoDays,
          rationale:
              'Correcting attachment resolves most feeding problems and prevents '
              'weight loss without any medicine.',
          protocolSource: _protocol,
          isCounselling: true,
        ),
      );
    }

    if (i.receivesOtherFoodsOrDrinks) {
      actions.add(
        const RecommendedAction(
          instruction:
              'Counsel on exclusive breastfeeding — no water, no koko, no herbs '
              'before 6 months',
          urgency: ReferralUrgency.scheduled,
          rationale:
              'Water and herbal preparations given to newborns are a major route '
              'for diarrhoea and sepsis in this setting.',
          protocolSource: 'WHO IYCF',
          isCounselling: true,
        ),
      );
    }

    // ---------------------------------------------------------------------
    // 7. BIRTH-RELATED VULNERABILITY (not IMCI classification, but predictive)
    // ---------------------------------------------------------------------
    if (i.isLowBirthWeight) {
      final veryLow = i.birthWeightKg! < 1.5;
      findings.add(
        ClinicalFinding(
          label: veryLow ? 'Very low birth weight' : 'Low birth weight',
          detail:
              'Birth weight ${i.birthWeightKg!.toStringAsFixed(2)} kg is below '
              '${veryLow ? '1.5' : '2.5'} kg. This infant needs kangaroo mother '
              'care, extra warmth, and weight checked at every contact.',
          severity: veryLow ? TriageLevel.urgent : TriageLevel.priority,
          protocolSource: 'WHO Newborn care',
          measuredValue: '${i.birthWeightKg!.toStringAsFixed(2)} kg',
          threshold: veryLow ? '< 1.5 kg' : '< 2.5 kg',
          weight: veryLow ? 8 : 4,
        ),
      );
      actions.add(
        const RecommendedAction(
          instruction:
              'Teach kangaroo mother care — skin-to-skin on the mother\'s chest, '
              'as many hours a day as possible',
          urgency: ReferralUrgency.sameDay,
          rationale:
              'Kangaroo care reduces mortality in low-birth-weight infants and '
              'needs no equipment, no electricity and no supplies.',
          protocolSource: 'WHO Kangaroo Mother Care',
          isTreatment: true,
        ),
      );
      if (veryLow) capabilities.add('newbornCare');
    }

    if (i.isPreterm) {
      findings.add(
        ClinicalFinding(
          label: 'Preterm birth',
          detail:
              'Born at ${i.gestationWeeksAtBirth} weeks (before 37). Preterm '
              'infants lose heat quickly, tire while feeding, and need closer '
              'follow-up.',
          severity: TriageLevel.priority,
          protocolSource: 'WHO Newborn care',
          weight: 4,
        ),
      );
    }

    if (i.isMultipleBirth) {
      findings.add(
        const ClinicalFinding(
          label: 'Multiple birth',
          detail:
              'Twins and higher-order births carry markedly higher neonatal '
              'mortality: lower birth weight, competition for breast milk, and '
              'more heat loss. Weigh both babies at every contact and check that '
              'each is feeding.',
          severity: TriageLevel.priority,
          protocolSource: 'WHO Newborn care',
          weight: 4,
        ),
      );
      actions.add(
        const RecommendedAction(
          instruction:
              'Confirm each baby is breastfeeding and gaining weight — weigh '
              'both at every visit',
          urgency: ReferralUrgency.scheduled,
          rationale:
              'The smaller twin is routinely under-fed. Tracking them separately '
              'is the only way to notice.',
          isCounselling: true,
        ),
      );
    }

    if (i.deliveryPlace?.isUnattendedBySkilledProvider ?? false) {
      findings.add(
        ClinicalFinding(
          label: 'Delivered without a skilled provider',
          detail:
              'Delivery place: ${i.deliveryPlace!.label}. Confirm cord care, '
              'vitamin K, eye care and BCG/OPV0 — these are usually missed '
              'outside a facility.',
          severity: TriageLevel.priority,
          protocolSource: 'Ghana Health Service newborn care',
          weight: 3,
        ),
      );
    }

    if (i.requiredResuscitation) {
      findings.add(
        const ClinicalFinding(
          label: 'Needed resuscitation at birth',
          detail:
              'Birth asphyxia is the leading cause of neonatal death in the '
              'Upper East Region. Watch closely for feeding difficulty, '
              'abnormal tone and fits over the coming days.',
          severity: TriageLevel.priority,
          protocolSource: 'Ghana Health Service newborn care',
          weight: 5,
        ),
      );
    }

    if (i.breastfedWithinOneHourOfBirth == false) {
      findings.add(
        const ClinicalFinding(
          label: 'Breastfeeding not started within the first hour',
          detail:
              'Early initiation protects against newborn death. Support the '
              'mother to establish feeding now and check attachment.',
          severity: TriageLevel.watch,
          protocolSource: 'WHO IYCF',
          weight: 2,
        ),
      );
    }

    // ---------------------------------------------------------------------
    // 8. MISSING DATA — stated openly, never silently assumed to be normal
    // ---------------------------------------------------------------------
    if (i.temperatureCelsius == null) {
      missing.add(
        'Temperature not measured — fever and hypothermia are the two commonest '
        'severe signs in this age group and cannot be judged by touch alone',
      );
    }
    if (i.respiratoryRate == null) {
      missing.add(
        'Breathing rate not counted — count for a full 60 seconds while the '
        'infant is calm',
      );
    }
    if (i.weightKg == null) missing.add('Current weight not recorded');
    if (i.birthWeightKg == null) {
      missing.add('Birth weight unknown — ask to see the child health record');
    }

    // ---------------------------------------------------------------------
    // 9. Compose the verdict
    // ---------------------------------------------------------------------
    final triage = findings.isEmpty
        ? TriageLevel.routine
        : findings
              .map((f) => f.severity)
              .reduce((a, b) => a.severity >= b.severity ? a : b);

    final classification = _classify(findings, triage);

    if (triage == TriageLevel.urgent) {
      capabilities.addAll({'newbornCare', 'laboratory'});
      actions.insert(
        0,
        RecommendedAction(
          instruction:
              'Refer to hospital NOW. Give the first dose of antibiotic before '
              'leaving, keep the baby warm skin-to-skin, and keep '
              'breastfeeding on the way.',
          urgency: ReferralUrgency.immediate,
          rationale:
              'Signs found: ${dangerSigns.join(', ')}. A young infant with any '
              'of these can die within hours.',
          protocolSource: _protocol,
          isReferral: true,
        ),
      );
    }

    if (triage == TriageLevel.routine) {
      actions.add(
        const RecommendedAction(
          instruction:
              'Continue exclusive breastfeeding, keep the baby warm, and keep '
              'the cord clean and dry',
          urgency: ReferralUrgency.scheduled,
          protocolSource: _protocol,
          isCounselling: true,
        ),
      );
    }

    // Every young infant gets the return-immediately advice. Non-negotiable.
    actions.add(
      const RecommendedAction(
        instruction:
            'Return IMMEDIATELY if the baby: feeds poorly or stops feeding, '
            'becomes hot or cold to touch, breathes fast or with difficulty, '
            'has fits, becomes less active, or the eyes or skin turn yellow',
        urgency: ReferralUrgency.immediate,
        rationale:
            'These are the signs that mean the difference between a live baby '
            'and a death at home. Make sure the mother can repeat them back.',
        protocolSource: _protocol,
        isCounselling: true,
      ),
    );

    return AssessmentResult(
      clientType: ClientType.newborn,
      triage: triage,
      classification: classification,
      findings: findings,
      actions: actions,
      confidence: _confidence(i, missing),
      confidenceScore: protocolConfidenceScore(
        measuredKeyInputs: (i.temperatureCelsius != null ? 1 : 0) +
            (i.respiratoryRate != null ? 1 : 0),
        keyInputCount: 2,
      ),
      protocolSource: _protocol,
      dangerSignsPresent: dangerSigns,
      missingData: missing,
      referralCapabilitiesNeeded: capabilities,
      followUpInDays: _followUp(triage, findings),
      caregiverMessage: _caregiverMessage(triage, dangerSigns),
    );
  }

  static String _classify(List<ClinicalFinding> findings, TriageLevel triage) {
    if (findings.any((f) => f.label.startsWith('Severe jaundice')) ||
        findings.any((f) => f.label.startsWith('Prolonged jaundice'))) {
      return 'SEVERE JAUNDICE';
    }
    if (triage == TriageLevel.urgent) {
      return 'CLINICAL SEVERE INFECTION OR VERY SEVERE DISEASE';
    }
    if (findings.any(
      (f) => f.label == 'Pneumonia' || f.label == 'Severe pneumonia',
    )) {
      return 'SEVERE PNEUMONIA OR VERY SEVERE DISEASE';
    }
    if (findings.any((f) => f.label == 'Local bacterial infection')) {
      return 'LOCAL BACTERIAL INFECTION';
    }
    if (findings.any((f) => f.label == 'Feeding problem')) {
      return 'FEEDING PROBLEM OR LOW WEIGHT';
    }
    if (findings.isEmpty) return 'NO SEVERE SIGNS — WELL YOUNG INFANT';
    return 'YOUNG INFANT NEEDING FOLLOW-UP';
  }

  /// Confidence drops when the two decisive measurements are absent. A
  /// "well baby" verdict with no thermometer reading is a guess, and the app
  /// says so rather than dressing it up.
  static RecommendationConfidence _confidence(
    YoungInfantInput i,
    List<String> missing,
  ) {
    final noTemp = i.temperatureCelsius == null;
    final noRr = i.respiratoryRate == null;
    if (noTemp && noRr) return RecommendationConfidence.low;
    if (noTemp || noRr) return RecommendationConfidence.moderate;
    if (missing.length > 2) return RecommendationConfidence.moderate;
    return RecommendationConfidence.protocolCertain;
  }

  static int _followUp(TriageLevel triage, List<ClinicalFinding> findings) {
    if (triage == TriageLevel.urgent) return 1;
    if (findings.any(
      (f) => f.label == 'Pneumonia' || f.label == 'Severe pneumonia',
    )) {
      return 1;
    }
    if (findings.any(
      (f) =>
          f.label == 'Local bacterial infection' || f.label == 'Feeding problem',
    )) {
      return 2;
    }
    if (findings.any((f) => f.label.contains('birth weight'))) return 3;
    return 7;
  }

  static String _caregiverMessage(TriageLevel triage, List<String> signs) {
    switch (triage) {
      case TriageLevel.urgent:
        return 'Your baby is very sick and must go to the hospital now. Do not '
            'wait until morning. Keep the baby warm against your skin and keep '
            'breastfeeding on the way.';
      case TriageLevel.priority:
        return 'Your baby needs treatment and must be seen again in two days. '
            'Breastfeed often, keep the baby warm, and come back at once if the '
            'baby feeds poorly or becomes less active.';
      case TriageLevel.watch:
        return 'Your baby is doing fairly well but needs watching. Breastfeed '
            'often and come to the next check-up.';
      case TriageLevel.routine:
        return 'Your baby is well. Give only breast milk — no water, no koko, '
            'no herbs — until six months. Keep the baby warm and the cord clean '
            'and dry.';
    }
  }
}
