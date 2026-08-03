/// Postnatal care for the mother — Ghana Health Service PNC schedule plus WHO
/// postnatal recommendations.
///
/// The postpartum period is where the deaths cluster: most maternal deaths
/// happen within 24 hours of delivery, and the majority within the first week.
/// Yet PNC coverage is the weakest link in the chain — a woman who delivered at
/// home has often had no contact at all by day 7.
///
/// Ghana PNC contact schedule: **day 1 (within 24h), day 3, day 7, week 6**.
///
/// This engine also handles the scenario the field actually presents: a mother
/// who has already delivered and comes in for a check-up with what she calls a
/// minor illness. The engine's job is to decide whether it really is minor.
library;

import '../enums.dart';
import '../entities/visit.dart';

const String _protocol = 'Ghana PNC schedule / WHO Postnatal Care';

/// Days after delivery at which a postnatal contact is due.
const List<int> pncContactDays = [1, 3, 7, 42];

class PostpartumInput {
  const PostpartumInput({
    required this.daysSinceDelivery,
    this.maternalAgeYears,
    this.deliveryPlace,
    this.deliveryMode,
    this.plurality = BirthPlurality.singleton,
    this.hadPostpartumHaemorrhage = false,
    this.babyAlive = true,

    // Measurements.
    this.systolic,
    this.diastolic,
    this.temperatureCelsius,
    this.haemoglobin,
    this.muacCm,
    this.pulse,

    // Danger signs.
    this.heavyBleeding = false,
    this.foulSmellingDischarge = false,
    this.fever = false,
    this.severeHeadache = false,
    this.blurredVision = false,
    this.convulsions = false,
    this.severeAbdominalPain = false,
    this.painfulSwollenLeg = false,
    this.difficultyBreathing = false,
    this.breastPainOrLump = false,
    this.crackedNipples = false,
    this.painfulUrination = false,
    this.perinealPainOrPus = false,
    this.caesareanWoundRedOrDraining = false,
    this.faecalOrUrinaryLeakage = false,
    this.dizzinessOrFainting = false,

    // The "minor complaint" she actually came with.
    this.presentingComplaint,

    // Mental health — routinely missed, and a real driver of poor caregiving.
    this.feelingSadMostDays,
    this.lostInterestInBaby,
    this.thoughtsOfSelfHarm = false,

    // Feeding and newborn link.
    this.breastfeedingEstablished,
    this.breastfedWithinOneHourOfBirth,
    this.givingOtherFoodsOrWater = false,

    // Services.
    this.familyPlanningDiscussed,
    this.familyPlanningAccepted,
    this.ironFolateTaken,
    this.vitaminAGivenPostpartum,

    // Context.
    this.householdHasValidNhis,
    this.walkingMinutesToFacility,
    this.pncContactsCompleted = 0,
  });

  final int daysSinceDelivery;
  final int? maternalAgeYears;
  final DeliveryPlace? deliveryPlace;
  final DeliveryMode? deliveryMode;
  final BirthPlurality plurality;
  final bool hadPostpartumHaemorrhage;

  /// A bereaved mother needs a different conversation, and must never be handed
  /// cheerful breastfeeding advice by a machine.
  final bool babyAlive;

  final int? systolic;
  final int? diastolic;
  final double? temperatureCelsius;
  final double? haemoglobin;
  final double? muacCm;
  final int? pulse;

  final bool heavyBleeding;
  final bool foulSmellingDischarge;
  final bool fever;
  final bool severeHeadache;
  final bool blurredVision;
  final bool convulsions;
  final bool severeAbdominalPain;
  final bool painfulSwollenLeg;
  final bool difficultyBreathing;
  final bool breastPainOrLump;
  final bool crackedNipples;
  final bool painfulUrination;
  final bool perinealPainOrPus;
  final bool caesareanWoundRedOrDraining;
  final bool faecalOrUrinaryLeakage;
  final bool dizzinessOrFainting;

  final String? presentingComplaint;

  final bool? feelingSadMostDays;
  final bool? lostInterestInBaby;
  final bool thoughtsOfSelfHarm;

  final bool? breastfeedingEstablished;
  final bool? breastfedWithinOneHourOfBirth;
  final bool givingOtherFoodsOrWater;

  final bool? familyPlanningDiscussed;
  final bool? familyPlanningAccepted;
  final bool? ironFolateTaken;
  final bool? vitaminAGivenPostpartum;

  final bool? householdHasValidNhis;
  final int? walkingMinutesToFacility;
  final int pncContactsCompleted;

  bool get hasFever =>
      (temperatureCelsius != null && temperatureCelsius! >= 38.0) || fever;

  bool get hasHypertension =>
      (systolic != null && systolic! >= 140) ||
      (diastolic != null && diastolic! >= 90);

  bool get hasSevereHypertension =>
      (systolic != null && systolic! >= 160) ||
      (diastolic != null && diastolic! >= 110);

  bool get isTachycardic => pulse != null && pulse! > 110;

  /// The first 24 hours carry the greatest share of maternal deaths.
  bool get isFirstDay => daysSinceDelivery <= 1;

  /// The first week carries most of the rest.
  bool get isFirstWeek => daysSinceDelivery <= 7;

  bool get isWithinPuerperium => daysSinceDelivery <= 42;

  int get expectedContactsByNow =>
      pncContactDays.where((d) => d <= daysSinceDelivery).length;
}

abstract final class PncEngine {
  static AssessmentResult assess(PostpartumInput i) {
    final findings = <ClinicalFinding>[];
    final actions = <RecommendedAction>[];
    final dangerSigns = <String>[];
    final missing = <String>[];
    final capabilities = <String>{};
    final classifications = <String>[];

    void add(
      String label,
      String detail,
      TriageLevel severity, {
      String? value,
      String? cutoff,
      double weight = 1,
      bool isDangerSign = false,
    }) {
      findings.add(
        ClinicalFinding(
          label: label,
          detail: detail,
          severity: severity,
          protocolSource: _protocol,
          measuredValue: value,
          threshold: cutoff,
          weight: weight,
          isDangerSign: isDangerSign,
        ),
      );
      if (severity == TriageLevel.urgent) dangerSigns.add(label);
    }

    // ---------------------------------------------------------------------
    // 1. POSTPARTUM HAEMORRHAGE — the leading direct cause of maternal death
    // ---------------------------------------------------------------------
    if (i.heavyBleeding) {
      classifications.add('POSTPARTUM HAEMORRHAGE');
      add(
        'Heavy vaginal bleeding',
        'Soaking more than one pad an hour, or passing large clots, after '
            'delivery is postpartum haemorrhage. Rub up the uterus, give a '
            'uterotonic if you have one, and travel immediately. A woman can '
            'bleed to death in under two hours.',
        TriageLevel.urgent,
        weight: 10,
        isDangerSign: true,
      );
      capabilities.addAll({'bloodTransfusion', 'caesarean', 'delivery'});
      actions.add(
        const RecommendedAction(
          instruction:
              'Massage the uterus firmly, give oxytocin or misoprostol if '
              'available, keep her flat and warm, and move now. Send someone '
              'ahead to warn the facility that she is bleeding.',
          urgency: ReferralUrgency.immediate,
          rationale: 'Uterine massage and a uterotonic buy the time needed to '
              'reach the facility.',
          protocolSource: _protocol,
          isTreatment: true,
        ),
      );
    }

    if (i.dizzinessOrFainting || i.isTachycardic) {
      add(
        i.isTachycardic ? 'Fast pulse' : 'Dizziness or fainting',
        i.isTachycardic
            ? 'Pulse ${i.pulse} beats per minute is above 110. With any bleeding '
                  'this points to significant blood loss even if the bleeding '
                  'looks modest from outside.'
            : 'Feeling faint on standing after delivery usually means blood loss '
                  'or severe anaemia.',
        TriageLevel.urgent,
        value: i.isTachycardic ? '${i.pulse} bpm' : 'reported',
        cutoff: i.isTachycardic ? '> 110 bpm' : null,
        weight: 8,
        isDangerSign: true,
      );
      capabilities.add('bloodTransfusion');
    }

    // ---------------------------------------------------------------------
    // 2. PUERPERAL SEPSIS — the second great killer
    // ---------------------------------------------------------------------
    final sepsisSigns = [
      i.hasFever,
      i.foulSmellingDischarge,
      i.severeAbdominalPain,
      i.perinealPainOrPus,
      i.caesareanWoundRedOrDraining,
    ].where((s) => s).length;

    if (sepsisSigns >= 2) {
      classifications.add('PUERPERAL SEPSIS');
      add(
        'Infection after delivery',
        '$sepsisSigns signs of puerperal sepsis together. She needs intravenous '
            'antibiotics, which cannot be given at a compound. Give the first '
            'oral or intramuscular dose and refer now.',
        TriageLevel.urgent,
        value: '$sepsisSigns signs',
        cutoff: '>= 2 signs',
        weight: 9,
        isDangerSign: true,
      );
      capabilities.addAll({'laboratory', 'bloodTransfusion'});
    } else if (i.hasFever) {
      classifications.add('FEVER AFTER DELIVERY');
      add(
        'Fever after delivery',
        i.temperatureCelsius != null
            ? 'Temperature ${i.temperatureCelsius!.toStringAsFixed(1)} degrees C '
                  'is at or above 38. After delivery, fever means infection until '
                  'proven otherwise — and malaria is also endemic here.'
            : 'Reported fever after delivery. Measure it, test for malaria, and '
                  'look for a source: womb, breast, wound or urine.',
        TriageLevel.urgent,
        value: i.temperatureCelsius == null
            ? 'reported'
            : '${i.temperatureCelsius!.toStringAsFixed(1)} C',
        cutoff: '>= 38.0 C',
        weight: 8,
        isDangerSign: true,
      );
      capabilities.add('laboratory');
    } else if (i.foulSmellingDischarge) {
      add(
        'Foul-smelling vaginal discharge',
        'A bad-smelling lochia suggests retained products or infection of the '
            'womb. Needs antibiotics and facility assessment today.',
        TriageLevel.priority,
        weight: 6,
      );
    }

    if (i.caesareanWoundRedOrDraining) {
      add(
        'Caesarean wound infected',
        'Redness, heat or discharge from the wound needs antibiotics and wound '
            'review at the facility that operated.',
        TriageLevel.priority,
        weight: 6,
      );
      capabilities.add('laboratory');
    }

    if (i.painfulUrination) {
      add(
        'Painful urination',
        'Urinary infection is common after delivery, especially after a '
            'catheter. Treat with a breastfeeding-safe antibiotic.',
        TriageLevel.priority,
        weight: 3,
      );
    }

    // ---------------------------------------------------------------------
    // 3. POSTPARTUM PRE-ECLAMPSIA AND ECLAMPSIA
    // ---------------------------------------------------------------------
    if (i.convulsions) {
      classifications.add('POSTPARTUM ECLAMPSIA');
      add(
        'Convulsions after delivery',
        'Eclampsia happens after delivery as well as before — often on day 2 or '
            '3, when everyone has stopped watching. Give magnesium sulphate if '
            'trained and travel immediately.',
        TriageLevel.urgent,
        weight: 10,
        isDangerSign: true,
      );
      capabilities.addAll({'bloodTransfusion', 'laboratory'});
    } else if (i.hasSevereHypertension) {
      classifications.add('SEVERE POSTPARTUM HYPERTENSION');
      add(
        'Severe hypertension after delivery',
        'Blood pressure ${i.systolic}/${i.diastolic} is at or above 160/110. '
            'Delivery does not end the risk of a fit; it can still come.',
        TriageLevel.urgent,
        value: '${i.systolic}/${i.diastolic} mmHg',
        cutoff: '>= 160/110',
        weight: 9,
        isDangerSign: true,
      );
      capabilities.add('laboratory');
    } else if (i.hasHypertension) {
      add(
        'Raised blood pressure after delivery',
        'Blood pressure ${i.systolic}/${i.diastolic} is at or above 140/90. '
            'Recheck within 2 days and refer if it stays up or if she gets a '
            'headache or visual change.',
        TriageLevel.priority,
        value: '${i.systolic}/${i.diastolic} mmHg',
        cutoff: '>= 140/90',
        weight: 6,
      );
    }

    if (i.severeHeadache || i.blurredVision) {
      add(
        i.severeHeadache ? 'Severe headache' : 'Blurred vision',
        'With any raised blood pressure this is a warning of an impending fit. '
            'With normal pressure it still needs assessment today.',
        i.hasHypertension ? TriageLevel.urgent : TriageLevel.priority,
        weight: i.hasHypertension ? 9 : 5,
      );
    }

    // ---------------------------------------------------------------------
    // 4. THROMBOSIS AND OTHER SERIOUS CAUSES
    // ---------------------------------------------------------------------
    if (i.painfulSwollenLeg) {
      add(
        'Painful swollen leg',
        'A hot, tender, swollen calf after delivery may be a clot. If part of it '
            'travels to the lung it is fatal. Refer today; do not massage the '
            'leg.',
        TriageLevel.urgent,
        weight: 8,
        isDangerSign: true,
      );
      capabilities.add('laboratory');
    }

    if (i.difficultyBreathing) {
      add(
        'Difficulty breathing',
        'Breathlessness after delivery can be a clot on the lung, heart failure '
            'or severe anaemia. All three are emergencies.',
        TriageLevel.urgent,
        weight: 9,
        isDangerSign: true,
      );
      capabilities.addAll({'bloodTransfusion', 'laboratory'});
    }

    if (i.faecalOrUrinaryLeakage) {
      add(
        'Leaking urine or stool',
        'This suggests a fistula, usually after prolonged obstructed labour. It '
            'is repairable, and it is the injury women hide. Refer to the '
            'regional hospital and tell her plainly that it can be fixed.',
        TriageLevel.priority,
        weight: 6,
      );
      capabilities.add('caesarean');
    }

    // ---------------------------------------------------------------------
    // 5. ANAEMIA — very common after delivery, and compounded by the region's
    //    baseline maternal anaemia burden
    // ---------------------------------------------------------------------
    if (i.haemoglobin != null) {
      final hb = i.haemoglobin!;
      if (hb < 7) {
        add(
          'Severe anaemia after delivery',
          'Haemoglobin ${hb.toStringAsFixed(1)} g/dL is below 7 g/dL. She may '
              'need transfusion, and she cannot care for a newborn in this state.',
          TriageLevel.urgent,
          value: '${hb.toStringAsFixed(1)} g/dL',
          cutoff: '< 7 g/dL',
          weight: 9,
          isDangerSign: true,
        );
        capabilities.addAll({'bloodTransfusion', 'laboratory'});
      } else if (hb < 10) {
        add(
          'Moderate anaemia after delivery',
          'Haemoglobin ${hb.toStringAsFixed(1)} g/dL. Give double-dose iron and '
              'folic acid for 3 months and recheck.',
          TriageLevel.priority,
          value: '${hb.toStringAsFixed(1)} g/dL',
          cutoff: '7.0–9.9 g/dL',
          weight: 5,
        );
      }
    } else if (i.hadPostpartumHaemorrhage || i.heavyBleeding) {
      missing.add(
        'Haemoglobin not checked after a bleed — anaemia is very likely',
      );
    }

    // ---------------------------------------------------------------------
    // 6. BREAST AND FEEDING
    // ---------------------------------------------------------------------
    if (i.babyAlive) {
      if (i.breastPainOrLump) {
        final withFever = i.hasFever;
        add(
          withFever ? 'Mastitis' : 'Breast pain or lump',
          withFever
              ? 'A painful, red, hot breast with fever is mastitis. Keep '
                    'breastfeeding from that breast — stopping makes it worse — '
                    'and start antibiotics.'
              : 'A blocked duct or engorgement. Feed frequently, express after '
                    'feeds, and apply a warm compress before feeding.',
          withFever ? TriageLevel.priority : TriageLevel.watch,
          weight: withFever ? 5 : 2,
        );
      }
      if (i.crackedNipples) {
        add(
          'Cracked or sore nipples',
          'Almost always a sign of poor attachment, not of weak skin. Watch a '
              'full feed and correct the latch — this is the commonest reason '
              'mothers give up breastfeeding.',
          TriageLevel.priority,
          weight: 3,
        );
      }
      if (i.breastfeedingEstablished == false) {
        add(
          'Breastfeeding not established',
          'The baby is not feeding well. Observe a full feed now, correct '
              'position and attachment, and review tomorrow. Poor feeding in the '
              'first week is how newborns end up in hospital.',
          TriageLevel.priority,
          weight: 6,
        );
        capabilities.add('newbornCare');
      }
      if (i.breastfedWithinOneHourOfBirth == false && i.isFirstWeek) {
        add(
          'Not breastfed within the first hour',
          'The first feed was delayed, so the baby missed the colostrum window. '
              'Support exclusive breastfeeding intensively now to recover ground.',
          TriageLevel.watch,
          weight: 2,
        );
      }
      if (i.givingOtherFoodsOrWater) {
        add(
          'Giving water or other foods',
          'Nothing but breast milk for the first six months — not water, not '
              'herbal preparations, not porridge. Water in a newborn causes '
              'diarrhoea and displaces milk. Ask respectfully what is being given '
              'and why, because there is usually a family reason behind it.',
          TriageLevel.priority,
          weight: 5,
        );
      }
      if (i.plurality != BirthPlurality.singleton) {
        add(
          'Feeding ${i.plurality.label.toLowerCase()}',
          'Two or more babies can be exclusively breastfed, but she needs '
              'practical help with positioning, far more food and fluid herself, '
              'and someone to share the load. Twins are where exclusive '
              'breastfeeding most often collapses.',
          TriageLevel.priority,
          weight: 5,
        );
      }
    }

    // ---------------------------------------------------------------------
    // 7. MATERNAL MENTAL HEALTH — routinely absent from paper registers
    // ---------------------------------------------------------------------
    if (i.thoughtsOfSelfHarm) {
      add(
        'Thoughts of self-harm',
        'This is an emergency and must never be dismissed as tiredness. Do not '
            'leave her alone. Refer today and tell the family plainly that she '
            'needs company and support.',
        TriageLevel.urgent,
        weight: 10,
      );
    } else if (i.feelingSadMostDays == true || i.lostInterestInBaby == true) {
      add(
        'Possible postnatal depression',
        'Persistent low mood or loss of interest in the baby affects feeding, '
            'responsive care and the child\'s development, not just the mother. '
            'It is treatable. Refer for assessment and arrange family support.',
        TriageLevel.priority,
        weight: 6,
      );
      actions.add(
        const RecommendedAction(
          instruction:
              'Talk with her alone, without the mother-in-law present, and ask '
              'directly how she is coping. Arrange practical help in the compound '
              'and refer for assessment.',
          urgency: ReferralUrgency.withinTwoDays,
          rationale:
              'Maternal mental health is the foundation of responsive caregiving '
              '— one of the five nurturing care components.',
          isCounselling: true,
        ),
      );
    } else if (i.feelingSadMostDays == null) {
      missing.add('Mood not asked about');
    }

    // ---------------------------------------------------------------------
    // 8. DELIVERY CIRCUMSTANCES THAT RAISE STANDING RISK
    // ---------------------------------------------------------------------
    if (i.deliveryPlace != null &&
        i.deliveryPlace!.isUnattendedBySkilledProvider) {
      add(
        'Delivered without a skilled provider',
        'Delivered ${i.deliveryPlace!.label.toLowerCase()}. That usually means '
            'no active management of the third stage, no clean cord care, no '
            'newborn vitamin K and no immediate checks. Examine both mother and '
            'baby carefully, and check her tetanus status.',
        TriageLevel.priority,
        weight: 6,
      );
      capabilities.add('newbornCare');
    }

    if (i.hadPostpartumHaemorrhage && !i.heavyBleeding) {
      add(
        'Bled heavily at delivery',
        'She has already had a postpartum haemorrhage in this delivery. Watch '
            'for anaemia and for further bleeding, and check her haemoglobin.',
        TriageLevel.priority,
        weight: 5,
      );
    }

    if (i.deliveryMode == DeliveryMode.caesarean && i.daysSinceDelivery <= 14) {
      add(
        'Recent caesarean section',
        'Check the wound at every contact, ensure she is not lifting heavily, '
            'and make sure she completed her antibiotics.',
        TriageLevel.watch,
        weight: 2,
      );
    }

    if (i.muacCm != null && i.muacCm! < 23) {
      add(
        'Maternal undernutrition',
        'MUAC ${i.muacCm!.toStringAsFixed(1)} cm is below 23 cm while '
            'breastfeeding. She needs an extra meal a day plus energy- and '
            'protein-dense local foods, or her milk supply and her own recovery '
            'both suffer.',
        TriageLevel.priority,
        value: '${i.muacCm!.toStringAsFixed(1)} cm',
        cutoff: '< 23 cm',
        weight: 5,
      );
    }

    // ---------------------------------------------------------------------
    // 9. THE "MINOR ILLNESS" CHECK-UP
    // ---------------------------------------------------------------------
    if (i.presentingComplaint != null &&
        i.presentingComplaint!.trim().isNotEmpty) {
      final serious = findings.any((f) => f.severity == TriageLevel.urgent);
      add(
        'Presenting complaint: ${i.presentingComplaint}',
        serious
            ? 'She came about "${i.presentingComplaint}", but the assessment has '
                  'found something that needs urgent care. Address the urgent '
                  'finding first and explain clearly why.'
            : 'She came about "${i.presentingComplaint}". Nothing urgent was '
                  'found, so treat the complaint, but complete the full postnatal '
                  'check while she is here — this may be her only contact.',
        serious ? TriageLevel.priority : TriageLevel.watch,
        weight: serious ? 3 : 1,
      );
    }

    // ---------------------------------------------------------------------
    // 10. COVERAGE AND SERVICES
    // ---------------------------------------------------------------------
    final contactGap = i.expectedContactsByNow - i.pncContactsCompleted;
    if (contactGap >= 1 && i.isWithinPuerperium) {
      add(
        'Behind on postnatal contacts',
        'By day ${i.daysSinceDelivery} she should have had '
            '${i.expectedContactsByNow} contacts (day 1, 3, 7 and week 6) but has '
            'had ${i.pncContactsCompleted}. Postnatal care is the weakest link in '
            'the whole chain, and the days she has missed are the most dangerous '
            'ones.',
        i.isFirstWeek ? TriageLevel.priority : TriageLevel.watch,
        value: '${i.pncContactsCompleted} of ${i.expectedContactsByNow}',
        cutoff: 'day 1, 3, 7, week 6',
        weight: i.isFirstWeek ? 5 : 2,
      );
    }

    if (i.daysSinceDelivery >= 3 && i.familyPlanningDiscussed != true) {
      add(
        'Family planning not discussed',
        'Birth spacing of at least 24 months protects both her and the next '
            'baby. Fertility returns sooner than most families expect, '
            'especially once breastfeeding is not exclusive. Discuss options now '
            'rather than at week 6.',
        TriageLevel.priority,
        weight: 4,
      );
      actions.add(
        const RecommendedAction(
          instruction:
              'Discuss birth spacing and the methods that are safe while '
              'breastfeeding. Include the husband in the conversation if she '
              'agrees — decisions here are rarely hers alone.',
          urgency: ReferralUrgency.scheduled,
          rationale:
              'Short birth intervals are a strong and modifiable driver of both '
              'maternal and neonatal death.',
          protocolSource: _protocol,
          isCounselling: true,
        ),
      );
    }

    if (i.ironFolateTaken == false) {
      add(
        'Not taking iron and folic acid',
        'Iron should continue for three months after delivery, especially after '
            'any blood loss.',
        TriageLevel.priority,
        weight: 3,
      );
    }

    if (i.vitaminAGivenPostpartum == false && i.daysSinceDelivery <= 42) {
      add(
        'Postpartum vitamin A not given',
        'A single high dose within 6 weeks of delivery benefits both her and the '
            'breastfed baby.',
        TriageLevel.watch,
        weight: 2,
      );
    }

    // ---------------------------------------------------------------------
    // 11. MISSING MEASUREMENTS
    // ---------------------------------------------------------------------
    if (i.systolic == null || i.diastolic == null) {
      missing.add(
        'Blood pressure not taken — postpartum pre-eclampsia is missed without '
        'it',
      );
    }
    if (i.temperatureCelsius == null && !i.fever) {
      missing.add('Temperature not taken — sepsis cannot be excluded');
    }

    // ---------------------------------------------------------------------
    // 12. VERDICT
    // ---------------------------------------------------------------------
    final triage = findings.isEmpty
        ? TriageLevel.routine
        : findings
              .map((f) => f.severity)
              .reduce((a, b) => a.severity >= b.severity ? a : b);

    if (classifications.isEmpty) {
      classifications.add(
        triage == TriageLevel.routine
            ? 'NORMAL POSTNATAL RECOVERY'
            : 'POSTNATAL PERIOD WITH RISK FACTORS',
      );
    }

    if (triage == TriageLevel.urgent) {
      actions.insert(
        0,
        RecommendedAction(
          instruction:
              'Refer her now and go with her if you can. Arrange transport '
              'before she leaves and phone ahead so the facility is ready.',
          urgency: ReferralUrgency.immediate,
          rationale: dangerSigns.isEmpty
              ? 'An urgent classification was reached.'
              : 'Urgent signs: ${dangerSigns.join('; ')}.',
          protocolSource: _protocol,
          isReferral: true,
        ),
      );
    }

    if (i.isFirstDay && triage != TriageLevel.urgent) {
      actions.add(
        const RecommendedAction(
          instruction:
              'Stay with her, or arrange for a family member to watch her, for '
              'the next several hours. Check her bleeding and her uterus every '
              'hour.',
          urgency: ReferralUrgency.immediate,
          rationale:
              'Most maternal deaths occur within 24 hours of delivery. The first '
              'day is a watching job, not a paperwork job.',
          protocolSource: _protocol,
        ),
      );
    }

    if (!i.babyAlive) {
      actions.insert(
        0,
        const RecommendedAction(
          instruction:
              'Acknowledge the loss before anything clinical. Ask what she needs. '
              'Do not offer feeding advice. Suppress lactation with support, '
              'screen for depression at every contact, and discuss spacing only '
              'when she raises it.',
          urgency: ReferralUrgency.immediate,
          rationale:
              'A bereaved mother still needs her physical postnatal checks, but '
              'the order of the conversation matters more than its content.',
          isCounselling: true,
        ),
      );
    }

    return AssessmentResult(
      clientType: ClientType.postpartumWoman,
      triage: triage,
      classification: classifications.join(' + '),
      findings: findings,
      actions: actions,
      confidence: _confidence(i, missing),
      protocolSource: _protocol,
      nutritionStatus: i.muacCm == null
          ? null
          : (i.muacCm! < 21
                ? NutritionStatus.severeAcute
                : (i.muacCm! < 23
                      ? NutritionStatus.moderateAcute
                      : NutritionStatus.normal)),
      nutritionPathway: i.muacCm == null
          ? null
          : (i.muacCm! < 23
                ? NutritionPathway.supplementaryFeeding
                : NutritionPathway.preventiveCounselling),
      dangerSignsPresent: dangerSigns,
      missingData: missing,
      referralCapabilitiesNeeded: capabilities,
      followUpInDays: _followUp(triage, i),
      caregiverMessage: _caregiverMessage(triage, dangerSigns, i),
    );
  }

  static RecommendationConfidence _confidence(
    PostpartumInput i,
    List<String> missing,
  ) {
    if (i.heavyBleeding || i.convulsions || i.thoughtsOfSelfHarm) {
      return RecommendationConfidence.protocolCertain;
    }
    final measured = [
      i.systolic != null && i.diastolic != null,
      i.temperatureCelsius != null,
      i.haemoglobin != null,
      i.muacCm != null,
    ].where((m) => m).length;

    if (measured >= 3 && missing.isEmpty) {
      return RecommendationConfidence.protocolCertain;
    }
    if (measured >= 3) return RecommendationConfidence.high;
    if (measured >= 1) return RecommendationConfidence.moderate;
    return RecommendationConfidence.low;
  }

  /// Follows the Ghana PNC schedule, tightened for risk.
  static int? _followUp(TriageLevel triage, PostpartumInput i) {
    if (triage == TriageLevel.urgent) return 1;
    if (triage == TriageLevel.priority) return i.isFirstWeek ? 1 : 3;

    final next = pncContactDays.firstWhere(
      (d) => d > i.daysSinceDelivery,
      orElse: () => 42,
    );
    final days = next - i.daysSinceDelivery;
    return days <= 0 ? 7 : days;
  }

  static String _caregiverMessage(
    TriageLevel triage,
    List<String> dangerSigns,
    PostpartumInput i,
  ) {
    final buffer = StringBuffer();

    if (!i.babyAlive) {
      buffer.write(
        'We are very sorry for your loss. Your own health still matters and we '
        'will keep checking on you. ',
      );
    }

    switch (triage) {
      case TriageLevel.urgent:
        buffer.write(
          'You must go to the health facility now. Do not wait for morning and '
          'do not travel alone. ',
        );
        if (dangerSigns.isNotEmpty) {
          buffer.write('What worries us: ${dangerSigns.first.toLowerCase()}. ');
        }
      case TriageLevel.priority:
        buffer.write(
          'There are things we must watch closely. Take the medicine as given '
          'and let us see you again soon. ',
        );
      case TriageLevel.watch:
      case TriageLevel.routine:
        buffer.write(
          'You are recovering well. Rest when the baby sleeps, eat more than '
          'usual because you are feeding a baby, and keep taking your iron. ',
        );
    }

    buffer.write(
      'Go to the facility at once, at any hour, if you bleed heavily, get a '
      'fever, have a bad headache or blurred vision, have a fit, have severe '
      'stomach pain, have a bad smell from your discharge, or if you feel you '
      'cannot cope.',
    );
    return buffer.toString();
  }
}
