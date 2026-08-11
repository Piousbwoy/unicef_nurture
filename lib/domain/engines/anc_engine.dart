/// WHO ANC 2016 (eight contacts) + Ghana Health Service safe-motherhood
/// protocol, encoded for a CHO working at a compound.
///
/// This engine carries the weight of the hackathon's headline number: maternal
/// deaths across the five northern regions rose from 164 in 2024 to 216 in 2025,
/// a 24.1% increase, with Upper East up 50% and Northern up 32%. Almost every
/// one of those deaths was preceded by a sign somebody could have seen.
///
/// Verified thresholds:
///   * Hypertension in pregnancy: **>= 140/90**; severe **>= 160/110**
///   * Anaemia: Hb **< 11 g/dL**; moderate 7–9.9; severe **< 7 g/dL**
///     (maternal anaemia reaches 44.2% in Upper West)
///   * IPTp-SP: from **16 weeks**, monthly, at least **3 doses**
///   * WHO ANC 2016: **8 contacts** — 12, 20, 26, 30, 34, 36, 38, 40 weeks
library;

import '../enums.dart';
import '../entities/visit.dart';

const String _protocol = 'WHO ANC 2016 / Ghana Safe Motherhood Protocol';

/// The eight WHO contact points, in gestational weeks.
const List<int> ancContactWeeks = [12, 20, 26, 30, 34, 36, 38, 40];

class PregnancyInput {
  const PregnancyInput({
    required this.gestationalWeeks,
    this.maternalAgeYears,
    this.gravida,
    this.parity,
    this.previousLosses = 0,
    this.previousCaesarean = false,
    this.previousStillbirth = false,
    this.previousPostpartumHaemorrhage = false,
    this.plurality = BirthPlurality.singleton,

    // Measurements.
    this.systolic,
    this.diastolic,
    this.haemoglobin,
    this.weightKg,
    this.heightCm,
    this.muacCm,
    this.fundalHeightCm,
    this.foetalHeartRate,
    this.proteinuria,

    // Danger signs — the ones that precede maternal death.
    this.vaginalBleeding = false,
    this.severeHeadache = false,
    this.blurredVision = false,
    this.convulsions = false,
    this.severeAbdominalPain = false,
    this.reducedFoetalMovement = false,
    this.noFoetalMovement = false,
    this.leakingFluid = false,
    this.fever = false,
    this.swellingOfFaceAndHands = false,
    this.difficultyBreathing = false,
    this.painfulUrination = false,
    this.persistentVomiting = false,

    // Coverage and service history.
    this.ancContactsCompleted = 0,
    this.iptpDoses = 0,
    this.tdDoses = 0,
    this.ironFolateTaken,
    this.sleepsUnderTreatedNet,
    this.hivTested,
    this.syphilisTested,
    this.birthPlanMade,
    this.plannedDeliveryPlace,

    // Context — determines whether the plan is realistic at all.
    this.householdHasValidNhis,
    this.walkingMinutesToFacility,
    this.hasSkilledSupportAtHome,
  });

  final int gestationalWeeks;
  final int? maternalAgeYears;
  final int? gravida;
  final int? parity;
  final int previousLosses;
  final bool previousCaesarean;
  final bool previousStillbirth;
  final bool previousPostpartumHaemorrhage;
  final BirthPlurality plurality;

  final int? systolic;
  final int? diastolic;
  final double? haemoglobin;
  final double? weightKg;
  final double? heightCm;
  final double? muacCm;
  final int? fundalHeightCm;
  final int? foetalHeartRate;

  /// Dipstick protein, 0–4 (+). Combined with blood pressure this separates
  /// gestational hypertension from pre-eclampsia.
  final int? proteinuria;

  final bool vaginalBleeding;
  final bool severeHeadache;
  final bool blurredVision;
  final bool convulsions;
  final bool severeAbdominalPain;
  final bool reducedFoetalMovement;
  final bool noFoetalMovement;
  final bool leakingFluid;
  final bool fever;
  final bool swellingOfFaceAndHands;
  final bool difficultyBreathing;
  final bool painfulUrination;
  final bool persistentVomiting;

  final int ancContactsCompleted;
  final int iptpDoses;
  final int tdDoses;
  final bool? ironFolateTaken;
  final bool? sleepsUnderTreatedNet;
  final bool? hivTested;
  final bool? syphilisTested;
  final bool? birthPlanMade;
  final DeliveryPlace? plannedDeliveryPlace;

  final bool? householdHasValidNhis;
  final int? walkingMinutesToFacility;
  final bool? hasSkilledSupportAtHome;

  bool get hasHypertension =>
      (systolic != null && systolic! >= 140) ||
      (diastolic != null && diastolic! >= 90);

  bool get hasSevereHypertension =>
      (systolic != null && systolic! >= 160) ||
      (diastolic != null && diastolic! >= 110);

  bool get hasProteinuria => proteinuria != null && proteinuria! >= 1;

  int get trimester =>
      gestationalWeeks < 13 ? 1 : (gestationalWeeks < 28 ? 2 : 3);

  bool get isTerm => gestationalWeeks >= 37;

  /// How many contacts she *should* have had by now under the WHO schedule.
  int get expectedContactsByNow =>
      ancContactWeeks.where((w) => w <= gestationalWeeks).length;

  /// IPTp starts at 16 weeks and repeats monthly, so roughly one dose per four
  /// weeks after 16, capped at the practical maximum.
  int get expectedIptpDoses {
    if (gestationalWeeks < 16) return 0;
    return ((gestationalWeeks - 16) ~/ 4 + 1).clamp(0, 6);
  }
}

abstract final class AncEngine {
  static AssessmentResult assess(PregnancyInput i) {
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
    // 1. OBSTETRIC EMERGENCIES — the five that kill
    // ---------------------------------------------------------------------
    if (i.convulsions) {
      classifications.add('ECLAMPSIA');
      add(
        'Convulsions — eclampsia',
        'Fits in pregnancy are eclampsia until proven otherwise. Give the '
            'loading dose of magnesium sulphate if you are trained and stocked, '
            'lie her on her left side, and travel immediately.',
        TriageLevel.urgent,
        weight: 10,
        isDangerSign: true,
      );
      capabilities.addAll({'caesarean', 'bloodTransfusion'});
      actions.add(
        const RecommendedAction(
          instruction:
              'Give magnesium sulphate loading dose now if trained, protect the '
              'airway, left lateral position, and move immediately to a facility '
              'with a theatre.',
          urgency: ReferralUrgency.immediate,
          rationale:
              'Magnesium sulphate before transfer more than halves the risk of a '
              'further fit.',
          protocolSource: _protocol,
          isTreatment: true,
        ),
      );
    }

    if (i.hasSevereHypertension) {
      classifications.add('SEVERE PRE-ECLAMPSIA');
      add(
        'Severe hypertension',
        'Blood pressure ${i.systolic}/${i.diastolic} is at or above 160/110. '
            'This is severe pre-eclampsia and can progress to a fit within '
            'hours.',
        TriageLevel.urgent,
        value: '${i.systolic}/${i.diastolic} mmHg',
        cutoff: '>= 160/110',
        weight: 10,
        isDangerSign: true,
      );
      capabilities.addAll({'caesarean', 'bloodTransfusion', 'laboratory'});
    } else if (i.hasHypertension) {
      final withProtein = i.hasProteinuria;
      final withSymptoms =
          i.severeHeadache || i.blurredVision || i.swellingOfFaceAndHands;
      if (withProtein || withSymptoms) {
        classifications.add('PRE-ECLAMPSIA');
        add(
          'Pre-eclampsia',
          'Blood pressure ${i.systolic}/${i.diastolic} is at or above 140/90 '
              '${withProtein ? 'with protein in the urine' : 'with warning symptoms'}. '
              'She needs facility assessment today.',
          TriageLevel.urgent,
          value: '${i.systolic}/${i.diastolic} mmHg',
          cutoff: '>= 140/90 with protein or symptoms',
          weight: 8,
          isDangerSign: true,
        );
        capabilities.addAll({'caesarean', 'laboratory'});
      } else {
        classifications.add('GESTATIONAL HYPERTENSION');
        add(
          'Raised blood pressure',
          'Blood pressure ${i.systolic}/${i.diastolic} is at or above 140/90 '
              'without protein or warning symptoms. Recheck within 2 days and '
              'test the urine.',
          TriageLevel.priority,
          value: '${i.systolic}/${i.diastolic} mmHg',
          cutoff: '>= 140/90',
          weight: 6,
        );
        if (i.proteinuria == null) {
          missing.add(
            'Urine protein not tested — needed to separate gestational '
            'hypertension from pre-eclampsia',
          );
        }
      }
    }

    if (i.vaginalBleeding) {
      final late = i.gestationalWeeks >= 28;
      classifications.add(late ? 'ANTEPARTUM HAEMORRHAGE' : 'BLEEDING IN PREGNANCY');
      add(
        'Vaginal bleeding',
        late
            ? 'Bleeding after 28 weeks may be placenta praevia or abruption. Do '
                  'not examine her vaginally. Travel now to a facility that can '
                  'operate and transfuse.'
            : 'Bleeding in early pregnancy may be miscarriage or an ectopic '
                  'pregnancy. Both need facility assessment today.',
        TriageLevel.urgent,
        weight: 10,
        isDangerSign: true,
      );
      capabilities.addAll({'caesarean', 'bloodTransfusion'});
    }

    if (i.severeAbdominalPain) {
      add(
        'Severe abdominal pain',
        'Constant severe pain, especially with a hard tender abdomen, suggests '
            'placental abruption or uterine rupture — particularly after a '
            'previous caesarean.',
        TriageLevel.urgent,
        weight: 9,
        isDangerSign: true,
      );
      capabilities.addAll({'caesarean', 'bloodTransfusion'});
    }

    if (i.noFoetalMovement) {
      add(
        'No foetal movement felt',
        'Absent movements need immediate assessment of the foetal heart. Do not '
            'reassure her over the phone.',
        TriageLevel.urgent,
        weight: 9,
        isDangerSign: true,
      );
      capabilities.add('delivery');
    } else if (i.reducedFoetalMovement) {
      add(
        'Reduced foetal movement',
        'Fewer movements than usual. Assess the foetal heart today; reduced '
            'movement precedes many stillbirths.',
        TriageLevel.priority,
        weight: 6,
      );
    }

    if (i.foetalHeartRate != null &&
        (i.foetalHeartRate! < 110 || i.foetalHeartRate! > 160)) {
      add(
        'Abnormal foetal heart rate',
        'Foetal heart ${i.foetalHeartRate} beats per minute is outside the '
            'normal 110–160 range. The baby is in distress.',
        TriageLevel.urgent,
        value: '${i.foetalHeartRate} bpm',
        cutoff: '110–160 bpm',
        weight: 9,
        isDangerSign: true,
      );
      capabilities.add('caesarean');
    }

    if (i.leakingFluid) {
      final preterm = i.gestationalWeeks < 37;
      add(
        preterm
            ? 'Waters broken before 37 weeks'
            : 'Waters broken at term',
        preterm
            ? 'Preterm rupture of membranes at ${i.gestationalWeeks} weeks risks '
                  'infection and preterm birth. She needs antibiotics and '
                  'facility care.'
            : 'Labour is likely to start. She should go to the facility now '
                  'rather than wait at home.',
        preterm ? TriageLevel.urgent : TriageLevel.priority,
        weight: preterm ? 8 : 5,
      );
      capabilities.add('delivery');
      if (preterm) capabilities.add('newbornCare');
    }

    if (i.fever) {
      add(
        'Fever in pregnancy',
        'Fever may be malaria, urinary infection or chorioamnionitis. All three '
            'threaten mother and baby. Test for malaria and start treatment.',
        TriageLevel.priority,
        weight: 6,
      );
      capabilities.add('laboratory');
    }

    if (i.difficultyBreathing) {
      add(
        'Difficulty breathing',
        'Breathlessness with severe anaemia or hypertension can mean heart '
            'failure or pulmonary oedema.',
        TriageLevel.urgent,
        weight: 8,
        isDangerSign: true,
      );
      capabilities.add('bloodTransfusion');
    }

    if (i.painfulUrination) {
      add(
        'Painful urination',
        'Urinary infection in pregnancy causes preterm labour if untreated. '
            'Treat with a pregnancy-safe antibiotic.',
        TriageLevel.priority,
        weight: 3,
      );
    }

    if (i.persistentVomiting && i.trimester == 1) {
      add(
        'Persistent vomiting',
        'Vomiting that prevents eating and drinking causes dehydration and '
            'weight loss, and needs fluids at a facility.',
        TriageLevel.priority,
        weight: 4,
      );
    }

    // ---------------------------------------------------------------------
    // 2. ANAEMIA — 44.2% of pregnant women in Upper West
    // ---------------------------------------------------------------------
    if (i.haemoglobin != null) {
      final hb = i.haemoglobin!;
      if (hb < 7) {
        classifications.add('SEVERE ANAEMIA IN PREGNANCY');
        add(
          'Severe anaemia',
          'Haemoglobin ${hb.toStringAsFixed(1)} g/dL is below 7 g/dL. She may '
              'need transfusion, and she will not survive a normal blood loss at '
              'delivery. Delivery must be at a facility that can transfuse.',
          TriageLevel.urgent,
          value: '${hb.toStringAsFixed(1)} g/dL',
          cutoff: '< 7 g/dL',
          weight: 9,
          isDangerSign: true,
        );
        capabilities.addAll({'bloodTransfusion', 'laboratory'});
      } else if (hb < 10) {
        classifications.add('MODERATE ANAEMIA');
        add(
          'Moderate anaemia',
          'Haemoglobin ${hb.toStringAsFixed(1)} g/dL falls between 7 and 10. '
              'Give double-dose iron and folic acid, deworm after the first '
              'trimester, and recheck in 4 weeks.',
          TriageLevel.priority,
          value: '${hb.toStringAsFixed(1)} g/dL',
          cutoff: '7.0–9.9 g/dL',
          weight: 6,
        );
      } else if (hb < 11) {
        classifications.add('MILD ANAEMIA');
        add(
          'Mild anaemia',
          'Haemoglobin ${hb.toStringAsFixed(1)} g/dL is just below 11 g/dL. '
              'Continue iron and folic acid daily and counsel on iron-rich local '
              'foods.',
          TriageLevel.watch,
          value: '${hb.toStringAsFixed(1)} g/dL',
          cutoff: '< 11 g/dL',
          weight: 3,
        );
      }
    } else {
      missing.add(
        'Haemoglobin not tested — anaemia is the commonest treatable risk here',
      );
    }

    // ---------------------------------------------------------------------
    // 3. MATERNAL NUTRITION
    // ---------------------------------------------------------------------
    NutritionStatus? nutrition;
    if (i.muacCm != null) {
      final muac = i.muacCm!;
      if (muac < 21) {
        nutrition = NutritionStatus.severeAcute;
        add(
          'Severe maternal undernutrition',
          'MUAC ${muac.toStringAsFixed(1)} cm is below 21 cm. She is at high '
              'risk of a low-birth-weight baby and needs a supplementary ration '
              'plus facility review.',
          TriageLevel.priority,
          value: '${muac.toStringAsFixed(1)} cm',
          cutoff: '< 21 cm',
          weight: 6,
        );
        capabilities.add('therapeuticFeeding');
      } else if (muac < 23) {
        nutrition = NutritionStatus.moderateAcute;
        add(
          'Maternal undernutrition',
          'MUAC ${muac.toStringAsFixed(1)} cm is below 23 cm. Intensive '
              'counselling on affordable energy- and protein-dense local foods, '
              'plus a supplementary ration where available.',
          TriageLevel.priority,
          value: '${muac.toStringAsFixed(1)} cm',
          cutoff: '21.0–22.9 cm',
          weight: 4,
        );
      } else {
        nutrition = NutritionStatus.normal;
      }
    } else {
      missing.add('Maternal MUAC not measured');
    }

    // ---------------------------------------------------------------------
    // 4. STANDING OBSTETRIC RISK — history that does not change with symptoms
    // ---------------------------------------------------------------------
    if (i.maternalAgeYears != null) {
      if (i.maternalAgeYears! < 18) {
        add(
          'Adolescent pregnancy',
          'At ${i.maternalAgeYears} years she faces higher risk of obstructed '
              'labour, pre-eclampsia and a low-birth-weight baby. Plan a '
              'facility delivery and keep her contacts close together.',
          TriageLevel.priority,
          value: '${i.maternalAgeYears} years',
          cutoff: '< 18 years',
          weight: 5,
        );
        capabilities.add('caesarean');
      } else if (i.maternalAgeYears! >= 35) {
        add(
          'Maternal age 35 or over',
          'At ${i.maternalAgeYears} years the risk of hypertension, bleeding and '
              'stillbirth is raised.',
          TriageLevel.watch,
          value: '${i.maternalAgeYears} years',
          cutoff: '>= 35 years',
          weight: 3,
        );
      }
    }

    if (i.heightCm != null && i.heightCm! < 145) {
      add(
        'Short stature',
        'Height ${i.heightCm!.toStringAsFixed(0)} cm is below 145 cm, which is '
            'associated with a contracted pelvis and obstructed labour. She '
            'should deliver where a caesarean is possible.',
        TriageLevel.priority,
        value: '${i.heightCm!.toStringAsFixed(0)} cm',
        cutoff: '< 145 cm',
        weight: 5,
      );
      capabilities.add('caesarean');
    }

    if (i.previousCaesarean) {
      add(
        'Previous caesarean section',
        'A scarred uterus can rupture in labour. She must deliver in a facility '
            'with a theatre — never at home or with a TBA.',
        TriageLevel.priority,
        weight: 6,
      );
      capabilities.addAll({'caesarean', 'bloodTransfusion'});
    }

    if (i.previousStillbirth || i.previousLosses >= 2) {
      add(
        i.previousStillbirth
            ? 'Previous stillbirth'
            : 'Two or more previous pregnancy losses',
        'A previous loss is the single strongest predictor of another. Increase '
            'contact frequency and plan a facility delivery.',
        TriageLevel.priority,
        value: i.previousStillbirth
            ? 'stillbirth'
            : '${i.previousLosses} losses',
        weight: 6,
      );
      capabilities.add('newbornCare');
    }

    if (i.previousPostpartumHaemorrhage) {
      add(
        'Previous heavy bleeding after delivery',
        'Postpartum haemorrhage recurs. She must deliver where blood and '
            'uterotonics are available, and active management of the third stage '
            'is mandatory.',
        TriageLevel.priority,
        weight: 7,
      );
      capabilities.addAll({'bloodTransfusion', 'delivery'});
    }

    if (i.plurality != BirthPlurality.singleton) {
      add(
        i.plurality.label,
        'A multiple pregnancy raises the risk of preterm birth, anaemia, '
            'pre-eclampsia and bleeding after delivery. Facility delivery with '
            'newborn care is essential, and two or more babies will need warmth '
            'and feeding support immediately.',
        TriageLevel.priority,
        weight: 7,
      );
      capabilities.addAll({'caesarean', 'newbornCare', 'bloodTransfusion'});
    }

    if ((i.parity ?? 0) >= 5) {
      add(
        'Grand multiparity',
        'Five or more previous births raises the risk of bleeding after delivery '
            'and of a poorly contracting uterus.',
        TriageLevel.watch,
        value: 'parity ${i.parity}',
        cutoff: '>= 5',
        weight: 4,
      );
      capabilities.add('bloodTransfusion');
    }

    // ---------------------------------------------------------------------
    // 5. COVERAGE GAPS — the quiet ones that get missed on paper
    // ---------------------------------------------------------------------
    final contactGap = i.expectedContactsByNow - i.ancContactsCompleted;
    if (contactGap >= 2) {
      add(
        'Behind on antenatal contacts',
        'At ${i.gestationalWeeks} weeks she should have completed '
            '${i.expectedContactsByNow} of the 8 recommended contacts but has '
            'had ${i.ancContactsCompleted}. Find out what stopped her before '
            'scheduling another appointment she may also miss.',
        TriageLevel.priority,
        value: '${i.ancContactsCompleted} of ${i.expectedContactsByNow}',
        cutoff: 'WHO 8 contacts',
        weight: 5,
      );
      actions.add(
        const RecommendedAction(
          instruction:
              'Ask what stopped her attending, record the barrier, and act on it '
              '— money, distance, permission or a bad past experience each need a '
              'different answer.',
          urgency: ReferralUrgency.sameDay,
          rationale:
              'Scheduling another appointment without removing the obstacle just '
              'produces another missed appointment.',
          isCounselling: true,
        ),
      );
    } else if (contactGap == 1) {
      add(
        'One antenatal contact missed',
        'She has had ${i.ancContactsCompleted} of the '
            '${i.expectedContactsByNow} contacts due by ${i.gestationalWeeks} '
            'weeks. Catch up at the next contact.',
        TriageLevel.watch,
        weight: 2,
      );
    }

    final iptpGap = i.expectedIptpDoses - i.iptpDoses;
    if (i.gestationalWeeks >= 16 && iptpGap >= 1) {
      add(
        'Malaria prevention doses overdue',
        'She has had ${i.iptpDoses} IPTp-SP doses; by ${i.gestationalWeeks} '
            'weeks about ${i.expectedIptpDoses} are due. Give a dose today under '
            'direct observation. Malaria in pregnancy causes anaemia, '
            'miscarriage and low birth weight.',
        TriageLevel.priority,
        value: '${i.iptpDoses} doses',
        cutoff: '>= ${i.expectedIptpDoses} by now',
        weight: 5,
      );
      actions.add(
        const RecommendedAction(
          instruction:
              'Give IPTp-SP now as directly observed therapy, and record the '
              'date. Doses handed over to take later are often not taken.',
          urgency: ReferralUrgency.sameDay,
          protocolSource: 'Ghana Malaria in Pregnancy Policy',
          isTreatment: true,
        ),
      );
    }

    if (i.tdDoses < 2) {
      add(
        'Tetanus protection incomplete',
        'Only ${i.tdDoses} tetanus-diphtheria doses recorded. At least two are '
            'needed to protect the newborn from tetanus, which is still fatal '
            'here after an unclean cord cut.',
        TriageLevel.priority,
        value: '${i.tdDoses} doses',
        cutoff: '>= 2 doses',
        weight: 4,
      );
    }

    if (i.sleepsUnderTreatedNet == false) {
      add(
        'Not sleeping under a treated net',
        'An insecticide-treated net is the cheapest protection available for '
            'both her and the baby. Issue one today if you have stock.',
        TriageLevel.priority,
        weight: 3,
      );
    }

    if (i.ironFolateTaken == false) {
      add(
        'Not taking iron and folic acid',
        'Ask why — the commonest reasons are nausea, constipation, running out, '
            'or nobody explained why it matters. Each has a different answer.',
        TriageLevel.priority,
        weight: 4,
      );
    }

    if (i.hivTested == false) {
      add(
        'HIV test not done',
        'Testing enables treatment that almost eliminates transmission to the '
            'baby. Offer it today.',
        TriageLevel.priority,
        weight: 4,
      );
      capabilities.add('laboratory');
    }
    if (i.syphilisTested == false) {
      add(
        'Syphilis test not done',
        'Untreated syphilis causes stillbirth and congenital infection, and is '
            'cured by a single injection.',
        TriageLevel.priority,
        weight: 4,
      );
      capabilities.add('laboratory');
    }

    // ---------------------------------------------------------------------
    // 6. BIRTH PREPAREDNESS — where the referral chain is won or lost
    // ---------------------------------------------------------------------
    if (i.gestationalWeeks >= 28) {
      if (i.birthPlanMade != true) {
        add(
          'No birth plan yet',
          'At ${i.gestationalWeeks} weeks she needs a plan agreed with the '
              'family: where she will deliver, how she will get there at night, '
              'who will go with her, who will mind the other children, and where '
              'the money will come from.',
          TriageLevel.priority,
          weight: 5,
        );
        actions.add(
          const RecommendedAction(
            instruction:
                'Make the birth plan today with the husband or a family '
                'decision-maker present. A plan the family has not agreed to is '
                'not a plan.',
            urgency: ReferralUrgency.sameDay,
            rationale:
                'Most delays that kill are decision delays and transport delays, '
                'not clinical delays.',
            protocolSource: _protocol,
            isCounselling: true,
          ),
        );
      }
      if (i.plannedDeliveryPlace != null &&
          i.plannedDeliveryPlace!.isUnattendedBySkilledProvider) {
        add(
          'Plans to deliver without a skilled provider',
          'She plans to deliver ${i.plannedDeliveryPlace!.label.toLowerCase()}. '
              'Discuss this respectfully but clearly, and agree on the facility '
              'she will go to instead.',
          capabilities.contains('caesarean')
              ? TriageLevel.urgent
              : TriageLevel.priority,
          weight: 8,
        );
        capabilities.add('delivery');
      }
      if (i.walkingMinutesToFacility != null &&
          i.walkingMinutesToFacility! > 60) {
        add(
          'More than an hour on foot from the facility',
          '${i.walkingMinutesToFacility} minutes walking. She should move closer '
              'as term approaches, or use a maternity waiting home if one is '
              'available. Labour at night over that distance is how women die.',
          TriageLevel.priority,
          value: '${i.walkingMinutesToFacility} min walk',
          cutoff: '> 60 min',
          weight: 5,
        );
      }
    }

    if (i.householdHasValidNhis == false) {
      actions.add(
        const RecommendedAction(
          instruction:
              'Register her for NHIS now. Maternal care is exempt from premiums '
              'under the free maternal health policy — many women do not know '
              'this and stay away because of cost.',
          urgency: ReferralUrgency.sameDay,
          rationale: 'Removes the commonest reported barrier to delivery care.',
          isCounselling: true,
        ),
      );
    }

    // ---------------------------------------------------------------------
    // 7. MISSING MEASUREMENTS
    // ---------------------------------------------------------------------
    if (i.systolic == null || i.diastolic == null) {
      missing.add(
        'Blood pressure not taken — pre-eclampsia cannot be detected without it',
      );
    }
    if (i.gestationalWeeks >= 20 && i.fundalHeightCm == null) {
      missing.add('Fundal height not measured');
    }
    if (i.gestationalWeeks >= 24 && i.foetalHeartRate == null) {
      missing.add('Foetal heart not listened to');
    }

    // Growth check where both are available.
    if (i.fundalHeightCm != null && i.gestationalWeeks >= 24) {
      final diff = i.fundalHeightCm! - i.gestationalWeeks;
      if (diff <= -3) {
        add(
          'Uterus smaller than expected',
          'Fundal height ${i.fundalHeightCm} cm at ${i.gestationalWeeks} weeks '
              'is more than 3 cm below the gestation. This may mean the baby is '
              'not growing. Needs facility assessment.',
          TriageLevel.priority,
          value: '${i.fundalHeightCm} cm at ${i.gestationalWeeks} wks',
          cutoff: 'within 3 cm of gestation',
          weight: 6,
        );
      } else if (diff >= 4) {
        add(
          'Uterus larger than expected',
          'Fundal height ${i.fundalHeightCm} cm at ${i.gestationalWeeks} weeks '
              'is well above the gestation. Consider twins, excess fluid or a '
              'wrong date.',
          TriageLevel.priority,
          value: '${i.fundalHeightCm} cm at ${i.gestationalWeeks} wks',
          cutoff: 'within 3 cm of gestation',
          weight: 5,
        );
      }
    }

    // ---------------------------------------------------------------------
    // 8. VERDICT
    // ---------------------------------------------------------------------
    final triage = findings.isEmpty
        ? TriageLevel.routine
        : findings
              .map((f) => f.severity)
              .reduce((a, b) => a.severity >= b.severity ? a : b);

    if (classifications.isEmpty) {
      classifications.add(
        triage == TriageLevel.routine
            ? 'PREGNANCY PROGRESSING NORMALLY'
            : 'PREGNANCY WITH RISK FACTORS',
      );
    }

    if (triage == TriageLevel.urgent) {
      actions.insert(
        0,
        RecommendedAction(
          instruction:
              'Refer her now, and do not let her leave alone. Arrange transport '
              'before she goes and phone the receiving facility so they expect '
              'her.',
          urgency: ReferralUrgency.immediate,
          rationale: dangerSigns.isEmpty
              ? 'An urgent classification was reached.'
              : 'Urgent signs: ${dangerSigns.join('; ')}.',
          protocolSource: _protocol,
          isReferral: true,
        ),
      );
    }

    if (nutrition == NutritionStatus.moderateAcute ||
        nutrition == NutritionStatus.severeAcute ||
        (i.haemoglobin != null && i.haemoglobin! < 11)) {
      actions.add(
        const RecommendedAction(
          instruction:
              'Go through the local-food plan with her: iron-rich foods she can '
              'actually get this month — dawadawa, moringa and baobab leaf, '
              'groundnut paste, cowpea, dried fish, liver — taken with something '
              'sour or a citrus fruit so the iron is absorbed. Avoid tea with '
              'meals, which blocks it.',
          urgency: ReferralUrgency.scheduled,
          rationale:
              'Iron tablets alone rarely correct anaemia here; the diet has to '
              'carry part of the load, and it has to be affordable.',
          protocolSource: 'Ghana IYCF / maternal nutrition counselling',
          isCounselling: true,
        ),
      );
    }

    return AssessmentResult(
      clientType: ClientType.pregnantWoman,
      triage: triage,
      classification: classifications.join(' + '),
      findings: findings,
      actions: actions,
      confidence: _confidence(i, missing),
      confidenceScore: protocolConfidenceScore(
        measuredKeyInputs: [
          i.systolic != null && i.diastolic != null,
          i.haemoglobin != null,
          i.muacCm != null,
          i.gestationalWeeks > 0,
        ].where((m) => m).length,
        keyInputCount: 4,
        observedDangerSign: i.convulsions || i.vaginalBleeding || i.hasSevereHypertension,
      ),
      protocolSource: _protocol,
      nutritionStatus: nutrition,
      nutritionPathway: nutrition == NutritionStatus.normal
          ? NutritionPathway.preventiveCounselling
          : (nutrition == null ? null : NutritionPathway.supplementaryFeeding),
      dangerSignsPresent: dangerSigns,
      missingData: missing,
      referralCapabilitiesNeeded: capabilities,
      followUpInDays: _followUp(triage, i),
      caregiverMessage: _caregiverMessage(triage, dangerSigns),
    );
  }

  static RecommendationConfidence _confidence(
    PregnancyInput i,
    List<String> missing,
  ) {
    if (i.convulsions || i.vaginalBleeding || i.hasSevereHypertension) {
      return RecommendationConfidence.protocolCertain;
    }
    final measured = [
      i.systolic != null && i.diastolic != null,
      i.haemoglobin != null,
      i.muacCm != null,
      i.gestationalWeeks > 0,
    ].where((m) => m).length;

    if (measured == 4 && missing.isEmpty) {
      return RecommendationConfidence.protocolCertain;
    }
    if (measured >= 3) return RecommendationConfidence.high;
    if (measured >= 2) return RecommendationConfidence.moderate;
    return RecommendationConfidence.low;
  }

  /// Follow-up interval respects the WHO schedule but tightens it for risk.
  static int? _followUp(TriageLevel triage, PregnancyInput i) {
    if (triage == TriageLevel.urgent) return 1;
    if (triage == TriageLevel.priority) return i.isTerm ? 3 : 7;

    final next = ancContactWeeks.firstWhere(
      (w) => w > i.gestationalWeeks,
      orElse: () => 40,
    );
    final days = (next - i.gestationalWeeks) * 7;
    return days.clamp(7, 42);
  }

  static String _caregiverMessage(
    TriageLevel triage,
    List<String> dangerSigns,
  ) {
    final buffer = StringBuffer();
    switch (triage) {
      case TriageLevel.urgent:
        buffer.write(
          'You must go to the health facility now, today, not tomorrow. This is '
          'serious for you and for your baby. ',
        );
        if (dangerSigns.isNotEmpty) {
          buffer.write('What worries us: ${dangerSigns.first.toLowerCase()}. ');
        }
      case TriageLevel.priority:
        buffer.write(
          'There are things about this pregnancy we must watch closely. Please '
          'keep the appointment we have agreed and take your tablets every day. ',
        );
      case TriageLevel.watch:
        buffer.write(
          'Your pregnancy is going well so far. Keep taking your iron tablets '
          'and sleeping under your net. ',
        );
      case TriageLevel.routine:
        buffer.write(
          'Your pregnancy is going well. Keep taking your iron tablets, sleep '
          'under your net every night, and eat as well as you can. ',
        );
    }
    buffer.write(
      'Go to the facility at once, at any hour of day or night, if you bleed, '
      'get a bad headache or blurred vision, have a fit, get swelling of your '
      'face and hands, have severe stomach pain, feel the baby move less than '
      'usual, or your waters break.',
    );
    return buffer.toString();
  }
}
