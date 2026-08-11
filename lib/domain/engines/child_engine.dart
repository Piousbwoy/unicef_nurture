/// WHO IMCI — **Sick Child, age 2 months up to 5 years (2–59 months)**.
///
/// The classic IMCI sequence, in order, because the order is clinical, not
/// cosmetic: general danger signs first, then cough, diarrhoea, fever, ear,
/// then nutrition and anaemia, then immunisation. A child with a general danger
/// sign is referred regardless of what the later sections find.
///
/// Verified cut-offs used here:
///   * Fast breathing: **>= 50/min** at 2–11 months, **>= 40/min** at 12–59 months
///   * Fever: **>= 37.5 degrees C**
///   * MUAC (6–59 months): SAM **< 11.5 cm**, MAM **11.5–12.4 cm**
///   * Bilateral pitting oedema = SAM regardless of MUAC
///
/// Northern Ghana specifics deliberately built in: malaria is endemic and
/// stable, so any fever is treated as possible malaria and an RDT is expected;
/// stunting runs near 30% in the Northern and North East regions, so nutrition
/// is never skipped even when the child presents with something else.
library;

import '../enums.dart';
import '../entities/visit.dart';

const String _protocol = 'WHO IMCI — Sick Child (2–59 months)';

/// Everything a CHO can gather on a child at a compound.
class ChildInput {
  const ChildInput({
    required this.ageInMonths,
    this.respiratoryRate,
    this.temperatureCelsius,
    this.weightKg,
    this.heightCm,
    this.muacCm,
    this.hasBilateralOedema = false,

    // General danger signs — the pink row.
    this.unableToDrinkOrBreastfeed = false,
    this.vomitsEverything = false,
    this.convulsions = false,
    this.lethargicOrUnconscious = false,
    this.convulsingNow = false,

    // Cough / difficult breathing.
    this.cough = false,
    this.coughDurationDays,
    this.difficultBreathing = false,
    this.chestIndrawing = false,
    this.stridor = false,
    this.wheeze = false,
    this.oxygenSaturation,

    // Diarrhoea.
    this.diarrhoea = false,
    this.diarrhoeaDurationDays,
    this.bloodInStool = false,
    this.sunkenEyes = false,
    this.skinPinchVerySlow = false,
    this.skinPinchSlow = false,
    this.restlessOrIrritable = false,
    this.drinksEagerly = false,

    // Fever / malaria.
    this.feverReported = false,
    this.feverDurationDays,
    this.malariaRdtDone = false,
    this.malariaRdtPositive,
    this.stiffNeck = false,
    this.runnyNose = false,
    this.measlesRash = false,
    this.mouthUlcers = false,
    this.pusDrainingFromEye = false,
    this.corneaClouding = false,

    // Ear.
    this.earPain = false,
    this.earDischarge = false,
    this.earDischargeDurationDays,
    this.tenderSwellingBehindEar = false,

    // Anaemia.
    this.severePalmarPallor = false,
    this.somePalmarPallor = false,
    this.haemoglobin,

    // Feeding (6–23 months in particular).
    this.stillBreastfeeding,
    this.mealsPerDay,
    this.foodGroupsEatenYesterday = 0,
    this.feedingChangedDuringIllness = false,
    this.appetiteTestPassed,

    // Immunisation / supplements.
    this.immunisationsUpToDate,
    this.overdueVaccines = const [],
    this.vitaminALastSixMonths,
    this.dewormedLastSixMonths,

    // Context that changes what is realistic to recommend.
    this.householdHasValidNhis,
    this.walkingMinutesToFacility,
  });

  final int ageInMonths;
  final int? respiratoryRate;
  final double? temperatureCelsius;
  final double? weightKg;
  final double? heightCm;
  final double? muacCm;
  final bool hasBilateralOedema;

  final bool unableToDrinkOrBreastfeed;
  final bool vomitsEverything;
  final bool convulsions;
  final bool lethargicOrUnconscious;
  final bool convulsingNow;

  final bool cough;
  final int? coughDurationDays;
  final bool difficultBreathing;
  final bool chestIndrawing;
  final bool stridor;
  final bool wheeze;
  final int? oxygenSaturation;

  final bool diarrhoea;
  final int? diarrhoeaDurationDays;
  final bool bloodInStool;
  final bool sunkenEyes;
  final bool skinPinchVerySlow;
  final bool skinPinchSlow;
  final bool restlessOrIrritable;
  final bool drinksEagerly;

  final bool feverReported;
  final int? feverDurationDays;
  final bool malariaRdtDone;
  final bool? malariaRdtPositive;
  final bool stiffNeck;
  final bool runnyNose;
  final bool measlesRash;
  final bool mouthUlcers;
  final bool pusDrainingFromEye;
  final bool corneaClouding;

  final bool earPain;
  final bool earDischarge;
  final int? earDischargeDurationDays;
  final bool tenderSwellingBehindEar;

  final bool severePalmarPallor;
  final bool somePalmarPallor;
  final double? haemoglobin;

  final bool? stillBreastfeeding;
  final int? mealsPerDay;
  final int foodGroupsEatenYesterday;
  final bool feedingChangedDuringIllness;
  final bool? appetiteTestPassed;

  final bool? immunisationsUpToDate;
  final List<String> overdueVaccines;
  final bool? vitaminALastSixMonths;
  final bool? dewormedLastSixMonths;

  final bool? householdHasValidNhis;
  final int? walkingMinutesToFacility;

  /// IMCI fast-breathing threshold is age-banded. Getting this wrong either
  /// floods the referral system or misses pneumonia, so it is computed, never
  /// typed by hand.
  int get fastBreathingThreshold => ageInMonths < 12 ? 50 : 40;

  bool get hasFastBreathing =>
      respiratoryRate != null && respiratoryRate! >= fastBreathingThreshold;

  bool get hasFever =>
      (temperatureCelsius != null && temperatureCelsius! >= 37.5) ||
      feverReported;

  bool get hasAnyGeneralDangerSign =>
      unableToDrinkOrBreastfeed ||
      vomitsEverything ||
      convulsions ||
      convulsingNow ||
      lethargicOrUnconscious;

  /// MUAC is only valid from 6 months. Below that, weight-for-age and the
  /// young-infant chart govern.
  bool get muacApplies => ageInMonths >= 6;

  /// The complementary-feeding window, where minimum dietary diversity and meal
  /// frequency are assessed and where stunting is set for life.
  bool get isComplementaryFeedingAge => ageInMonths >= 6 && ageInMonths <= 23;
}

abstract final class ChildEngine {
  static AssessmentResult assess(ChildInput i) {
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
    // 1. GENERAL DANGER SIGNS — checked first, override everything after.
    // ---------------------------------------------------------------------
    if (i.convulsingNow) {
      add(
        'Convulsing now',
        'The child is fitting at this moment. Position on the side, do not put '
            'anything in the mouth, and get to a facility immediately.',
        TriageLevel.urgent,
        weight: 10,
        isDangerSign: true,
      );
    }
    if (i.unableToDrinkOrBreastfeed) {
      add(
        'Not able to drink or breastfeed',
        'A child who cannot take fluid will dehydrate quickly and cannot take '
            'oral treatment.',
        TriageLevel.urgent,
        weight: 10,
        isDangerSign: true,
      );
    }
    if (i.vomitsEverything) {
      add(
        'Vomits everything',
        'Nothing stays down, so oral rehydration and oral medicine will fail.',
        TriageLevel.urgent,
        weight: 10,
        isDangerSign: true,
      );
    }
    if (i.convulsions) {
      add(
        'Convulsions during this illness',
        'Fits during this illness point to severe malaria, meningitis or another '
            'severe cause.',
        TriageLevel.urgent,
        weight: 10,
        isDangerSign: true,
      );
    }
    if (i.lethargicOrUnconscious) {
      add(
        'Lethargic or unconscious',
        'Abnormally sleepy or not responding normally. A cardinal sign of very '
            'severe illness.',
        TriageLevel.urgent,
        weight: 10,
        isDangerSign: true,
      );
    }

    if (i.hasAnyGeneralDangerSign) {
      classifications.add('VERY SEVERE DISEASE');
      capabilities.addAll({'bloodTransfusion', 'laboratory'});
    }

    // ---------------------------------------------------------------------
    // 2. COUGH OR DIFFICULT BREATHING
    // ---------------------------------------------------------------------
    if (i.cough || i.difficultBreathing) {
      if (i.chestIndrawing || i.stridor) {
        classifications.add('SEVERE PNEUMONIA OR VERY SEVERE DISEASE');
        add(
          i.chestIndrawing ? 'Chest indrawing' : 'Stridor when calm',
          i.chestIndrawing
              ? 'The lower chest wall goes in when the child breathes in. This '
                    'is severe pneumonia.'
              : 'A harsh noise on breathing in while calm indicates upper airway '
                    'obstruction.',
          TriageLevel.urgent,
          weight: 9,
          isDangerSign: true,
        );
        capabilities.add('laboratory');
      } else if (i.hasFastBreathing) {
        classifications.add('PNEUMONIA');
        add(
          'Fast breathing — pneumonia',
          'Respiratory rate ${i.respiratoryRate} per minute is at or above the '
              '${i.fastBreathingThreshold} per minute cut-off for a child aged '
              '${i.ageInMonths} months. Classified as pneumonia; treat with oral '
              'amoxicillin and review in 3 days.',
          TriageLevel.priority,
          value: '${i.respiratoryRate}/min',
          cutoff: '>= ${i.fastBreathingThreshold}/min',
          weight: 5,
        );
        actions.add(
          const RecommendedAction(
            instruction:
                'Give oral amoxicillin dispersible tablets for 5 days, dosed by '
                'weight, and show the caregiver how to give the first dose now.',
            urgency: ReferralUrgency.sameDay,
            rationale: 'Pneumonia without chest indrawing is treated at '
                'community level under IMCI/iCCM.',
            protocolSource: _protocol,
            isTreatment: true,
          ),
        );
      } else {
        classifications.add('COUGH OR COLD');
        add(
          'Cough or cold',
          'No fast breathing and no chest indrawing. This is a simple cough. '
              'Antibiotics are not needed and would do harm.',
          TriageLevel.routine,
          weight: 1,
        );
      }

      if (i.respiratoryRate == null) {
        missing.add(
          'Respiratory rate not counted — pneumonia cannot be excluded',
        );
      }
      if ((i.coughDurationDays ?? 0) >= 14) {
        add(
          'Cough for 14 days or more',
          'A cough lasting two weeks or more needs assessment for TB, which is '
              'under-diagnosed in children.',
          TriageLevel.priority,
          value: '${i.coughDurationDays} days',
          cutoff: '>= 14 days',
          weight: 4,
        );
        capabilities.add('laboratory');
      }
      if (i.oxygenSaturation != null && i.oxygenSaturation! < 90) {
        add(
          'Low oxygen saturation',
          'SpO2 ${i.oxygenSaturation}% is below 90%. Hypoxia needs oxygen, which '
              'is not available at community level.',
          TriageLevel.urgent,
          value: '${i.oxygenSaturation}%',
          cutoff: '< 90%',
          weight: 9,
          isDangerSign: true,
        );
      }
    }

    // ---------------------------------------------------------------------
    // 3. DIARRHOEA AND DEHYDRATION
    // ---------------------------------------------------------------------
    if (i.diarrhoea) {
      final severeSigns = [
        i.lethargicOrUnconscious,
        i.sunkenEyes,
        i.skinPinchVerySlow,
        i.unableToDrinkOrBreastfeed,
      ].where((s) => s).length;

      final someSigns = [
        i.restlessOrIrritable,
        i.sunkenEyes,
        i.skinPinchSlow,
        i.drinksEagerly,
      ].where((s) => s).length;

      if (severeSigns >= 2) {
        classifications.add('SEVERE DEHYDRATION');
        add(
          'Severe dehydration',
          '$severeSigns severe dehydration signs present. Needs intravenous '
              'fluids (Plan C) — this cannot be done at a compound.',
          TriageLevel.urgent,
          value: '$severeSigns signs',
          cutoff: '>= 2 signs',
          weight: 9,
          isDangerSign: true,
        );
        capabilities.add('laboratory');
        actions.add(
          const RecommendedAction(
            instruction:
                'Start ORS by mouth or nasogastric tube on the way if the child '
                'can swallow, and travel immediately for IV fluids.',
            urgency: ReferralUrgency.immediate,
            rationale: 'Plan C requires IV or NG rehydration at a facility.',
            protocolSource: _protocol,
            isTreatment: true,
          ),
        );
      } else if (someSigns >= 2) {
        classifications.add('SOME DEHYDRATION');
        add(
          'Some dehydration',
          '$someSigns signs of some dehydration. Treat with ORS under '
              'observation (Plan B) and continue feeding.',
          TriageLevel.priority,
          value: '$someSigns signs',
          cutoff: '>= 2 signs',
          weight: 5,
        );
        actions.add(
          const RecommendedAction(
            instruction:
                'Give ORS over 4 hours in front of you, plus zinc for 14 days. '
                'Continue breastfeeding throughout.',
            urgency: ReferralUrgency.sameDay,
            rationale: 'IMCI Plan B.',
            protocolSource: _protocol,
            isTreatment: true,
          ),
        );
      } else {
        classifications.add('NO DEHYDRATION');
        add(
          'Diarrhoea, no dehydration',
          'Treat at home with extra fluids, ORS and zinc, and keep feeding '
              '(Plan A).',
          TriageLevel.watch,
          weight: 2,
        );
        actions.add(
          const RecommendedAction(
            instruction:
                'Give ORS after every loose stool and zinc daily for 14 days. '
                'Zinc shortens the episode and prevents the next one.',
            urgency: ReferralUrgency.scheduled,
            rationale: 'IMCI Plan A. Zinc is routinely under-used.',
            protocolSource: _protocol,
            isTreatment: true,
          ),
        );
      }

      if ((i.diarrhoeaDurationDays ?? 0) >= 14) {
        classifications.add('PERSISTENT DIARRHOEA');
        add(
          'Persistent diarrhoea — 14 days or more',
          'Diarrhoea lasting two weeks or more damages the gut and drives '
              'wasting. Needs facility assessment and a special diet.',
          TriageLevel.priority,
          value: '${i.diarrhoeaDurationDays} days',
          cutoff: '>= 14 days',
          weight: 5,
        );
      }
      if (i.bloodInStool) {
        classifications.add('DYSENTERY');
        add(
          'Blood in the stool — dysentery',
          'Bloody diarrhoea needs ciprofloxacin, not ORS alone.',
          TriageLevel.priority,
          weight: 5,
        );
      }
    }

    // ---------------------------------------------------------------------
    // 4. FEVER — malaria is endemic and stable across all five northern regions
    // ---------------------------------------------------------------------
    if (i.hasFever) {
      final tempText = i.temperatureCelsius == null
          ? 'Fever reported by the caregiver'
          : 'Temperature ${i.temperatureCelsius!.toStringAsFixed(1)} degrees C';

      if (i.stiffNeck || i.hasAnyGeneralDangerSign) {
        classifications.add('VERY SEVERE FEBRILE DISEASE');
        add(
          i.stiffNeck ? 'Fever with stiff neck' : 'Fever with a danger sign',
          '$tempText together with '
              '${i.stiffNeck ? 'neck stiffness' : 'a general danger sign'}. '
              'Treat as severe malaria or meningitis. Give the first dose of '
              'rectal artesunate and refer now.',
          TriageLevel.urgent,
          value: i.temperatureCelsius == null
              ? 'reported'
              : '${i.temperatureCelsius!.toStringAsFixed(1)} C',
          cutoff: '>= 37.5 C',
          weight: 9,
          isDangerSign: true,
        );
        capabilities.addAll({'bloodTransfusion', 'laboratory'});
        actions.add(
          const RecommendedAction(
            instruction:
                'Give pre-referral rectal artesunate now, then travel. Do not '
                'wait for a test result.',
            urgency: ReferralUrgency.immediate,
            rationale:
                'Pre-referral treatment for suspected severe malaria measurably '
                'reduces deaths in transit.',
            protocolSource: _protocol,
            isTreatment: true,
          ),
        );
      } else if (i.malariaRdtDone && i.malariaRdtPositive == true) {
        classifications.add('MALARIA');
        add(
          'Malaria — RDT positive',
          '$tempText with a positive rapid diagnostic test. Treat with '
              'artemether-lumefantrine and review in 3 days.',
          TriageLevel.priority,
          weight: 5,
        );
        actions.add(
          const RecommendedAction(
            instruction:
                'Give artemether-lumefantrine by weight for 3 days, with a fatty '
                'food or breast milk so it is absorbed. Paracetamol only if the '
                'fever distresses the child.',
            urgency: ReferralUrgency.sameDay,
            protocolSource: _protocol,
            isTreatment: true,
          ),
        );
      } else if (i.malariaRdtDone && i.malariaRdtPositive == false) {
        classifications.add('FEVER — MALARIA UNLIKELY');
        add(
          'Fever with a negative malaria test',
          '$tempText but the RDT is negative. Do not give an antimalarial. '
              'Look for another cause and review in 2 days if the fever persists.',
          TriageLevel.watch,
          weight: 2,
        );
      } else {
        classifications.add('FEVER — MALARIA TEST NEEDED');
        add(
          'Fever, not yet tested for malaria',
          '$tempText in a region where malaria transmission is year-round. Test '
              'before treating: presumptive treatment drives resistance and '
              'hides other causes.',
          TriageLevel.priority,
          weight: 4,
        );
        missing.add('Malaria RDT not done');
        actions.add(
          const RecommendedAction(
            instruction: 'Do a malaria RDT now, or refer to the nearest CHPS '
                'compound that has test kits today.',
            urgency: ReferralUrgency.sameDay,
            protocolSource: _protocol,
            isTreatment: true,
          ),
        );
      }

      if ((i.feverDurationDays ?? 0) >= 7) {
        add(
          'Fever for 7 days or more',
          'Fever every day for a week or more needs a facility assessment for '
              'typhoid, TB or another cause.',
          TriageLevel.priority,
          value: '${i.feverDurationDays} days',
          cutoff: '>= 7 days',
          weight: 4,
        );
      }

      if (i.measlesRash) {
        if (i.corneaClouding || i.mouthUlcers) {
          classifications.add('SEVERE COMPLICATED MEASLES');
          add(
            'Measles with complications',
            i.corneaClouding
                ? 'Clouding of the cornea threatens permanent blindness.'
                : 'Deep or extensive mouth ulcers stop the child feeding.',
            TriageLevel.urgent,
            weight: 8,
          );
        } else {
          classifications.add('MEASLES');
          add(
            'Measles',
            'Generalised rash with fever and either cough, runny nose or red '
                'eyes. Give vitamin A today and tomorrow.',
            TriageLevel.priority,
            weight: 5,
          );
        }
        actions.add(
          const RecommendedAction(
            instruction:
                'Give vitamin A today and repeat tomorrow, and check every other '
                'child in the compound for measles vaccination.',
            urgency: ReferralUrgency.sameDay,
            rationale:
                'Vitamin A in measles reduces mortality; one case in a compound '
                'means others are exposed.',
            protocolSource: _protocol,
            isTreatment: true,
          ),
        );
      }
      if (i.pusDrainingFromEye) {
        add(
          'Pus draining from the eye',
          'Treat with tetracycline eye ointment and review in 2 days.',
          TriageLevel.priority,
          weight: 3,
        );
      }
    }

    // ---------------------------------------------------------------------
    // 5. EAR PROBLEM
    // ---------------------------------------------------------------------
    if (i.earPain || i.earDischarge || i.tenderSwellingBehindEar) {
      if (i.tenderSwellingBehindEar) {
        classifications.add('MASTOIDITIS');
        add(
          'Tender swelling behind the ear — mastoiditis',
          'Infection has spread to the bone and can reach the brain. Refer '
              'urgently with the first dose of antibiotic.',
          TriageLevel.urgent,
          weight: 8,
        );
      } else if (i.earDischarge && (i.earDischargeDurationDays ?? 0) >= 14) {
        classifications.add('CHRONIC EAR INFECTION');
        add(
          'Ear discharge for 14 days or more',
          'Chronic infection. Keep the ear dry by wicking; it causes hearing '
              'loss and delays speech if untreated.',
          TriageLevel.watch,
          value: '${i.earDischargeDurationDays} days',
          cutoff: '>= 14 days',
          weight: 2,
        );
      } else {
        classifications.add('ACUTE EAR INFECTION');
        add(
          'Acute ear infection',
          'Ear pain or discharge for less than 14 days. Give oral amoxicillin '
              'for 5 days, wick the ear dry, and review in 5 days.',
          TriageLevel.priority,
          weight: 3,
        );
      }
    }

    // ---------------------------------------------------------------------
    // 6. NUTRITION — never skipped. Stunting is near 30% in this region.
    // ---------------------------------------------------------------------
    NutritionStatus? nutrition;
    NutritionPathway? pathway;

    if (i.hasBilateralOedema) {
      nutrition = NutritionStatus.severeAcute;
      classifications.add('SEVERE ACUTE MALNUTRITION WITH OEDEMA');
      add(
        'Bilateral pitting oedema',
        'Swelling of both feet that pits when pressed is severe acute '
            'malnutrition (kwashiorkor) whatever the MUAC reads. It always '
            'needs inpatient care.',
        TriageLevel.urgent,
        weight: 10,
        isDangerSign: true,
      );
    } else if (i.muacApplies && i.muacCm != null) {
      final muac = i.muacCm!;
      if (muac < 11.5) {
        nutrition = NutritionStatus.severeAcute;
        classifications.add('SEVERE ACUTE MALNUTRITION');
        add(
          'Severe acute malnutrition',
          'MUAC ${muac.toStringAsFixed(1)} cm is below the 11.5 cm cut-off. '
              'This child needs therapeutic food — RUTF or F-75 — not home diet '
              'advice. Mortality without treatment is very high.',
          TriageLevel.urgent,
          value: '${muac.toStringAsFixed(1)} cm',
          cutoff: '< 11.5 cm',
          weight: 10,
        );
      } else if (muac < 12.5) {
        nutrition = NutritionStatus.moderateAcute;
        classifications.add('MODERATE ACUTE MALNUTRITION');
        add(
          'Moderate acute malnutrition',
          'MUAC ${muac.toStringAsFixed(1)} cm falls in the 11.5–12.4 cm band. '
              'Intensive local-food counselling now, with supplementary feeding '
              'where available, prevents this becoming severe.',
          TriageLevel.priority,
          value: '${muac.toStringAsFixed(1)} cm',
          cutoff: '11.5–12.4 cm',
          weight: 6,
        );
      } else if (muac < 13.5) {
        nutrition = NutritionStatus.atRisk;
        add(
          'At risk of malnutrition',
          'MUAC ${muac.toStringAsFixed(1)} cm is above the MAM band but below '
              '13.5 cm. Measure again in one month; the direction of travel '
              'matters more than this single reading.',
          TriageLevel.watch,
          value: '${muac.toStringAsFixed(1)} cm',
          cutoff: '12.5–13.4 cm',
          weight: 2,
        );
      } else {
        nutrition = NutritionStatus.normal;
        add(
          'Adequate arm circumference',
          'MUAC ${muac.toStringAsFixed(1)} cm is in the green band. Reinforce '
              'what the family is already doing well.',
          TriageLevel.routine,
          value: '${muac.toStringAsFixed(1)} cm',
          cutoff: '>= 13.5 cm',
        );
      }
    } else if (i.muacApplies) {
      missing.add('MUAC not measured — malnutrition cannot be ruled out');
    }

    // The SAM branch that the design review flagged: pathway, not porridge.
    if (nutrition == NutritionStatus.severeAcute) {
      final complicated = i.hasAnyGeneralDangerSign ||
          i.hasBilateralOedema ||
          i.appetiteTestPassed == false ||
          i.ageInMonths < 6;
      pathway = complicated
          ? NutritionPathway.inpatientTherapeutic
          : NutritionPathway.outpatientTherapeutic;
      capabilities.add(
        complicated ? 'therapeuticFeeding' : 'otp',
      );
      actions.add(
        RecommendedAction(
          instruction: complicated
              ? 'Refer today for inpatient therapeutic care with F-75. Do not '
                    'send the family home with feeding advice.'
              : 'Refer to the nearest Outpatient Therapeutic Programme for RUTF '
                    'and weekly review. Give the first RUTF sachet under '
                    'observation if you have stock.',
          urgency: ReferralUrgency.immediate,
          rationale: complicated
              ? 'SAM with complications, oedema, failed appetite test or age '
                    'under 6 months requires 24-hour medical care.'
              : 'SAM with appetite and no complications is managed in OTP.',
          protocolSource: 'Ghana CMAM / WHO SAM guidelines',
          isReferral: true,
          isTreatment: true,
        ),
      );
      if (i.appetiteTestPassed == null) {
        missing.add(
          'Appetite test not done — decides between inpatient care and OTP',
        );
      }
    } else if (nutrition == NutritionStatus.moderateAcute) {
      pathway = NutritionPathway.supplementaryFeeding;
    } else if (nutrition != null) {
      pathway = NutritionPathway.preventiveCounselling;
    }

    // Feeding practice, for the 6–23 month window where diversity is decisive.
    if (i.isComplementaryFeedingAge) {
      final minMeals = i.stillBreastfeeding == false
          ? 4
          : (i.ageInMonths <= 8 ? 2 : 3);
      if (i.foodGroupsEatenYesterday > 0 && i.foodGroupsEatenYesterday < 5) {
        add(
          'Diet not diverse enough',
          'The child ate ${i.foodGroupsEatenYesterday} of the 8 food groups '
              'yesterday. Five or more is the minimum for adequate growth. Only '
              '26% of children this age in Ghana reach an acceptable diet.',
          TriageLevel.priority,
          value: '${i.foodGroupsEatenYesterday} of 8 groups',
          cutoff: '>= 5 groups',
          weight: 4,
        );
      }
      if (i.mealsPerDay != null && i.mealsPerDay! < minMeals) {
        add(
          'Not fed often enough',
          'Fed ${i.mealsPerDay} times yesterday; a '
              '${i.ageInMonths}-month-old '
              '${i.stillBreastfeeding == false ? 'who is no longer breastfeeding ' : ''}'
              'needs at least $minMeals meals a day. A small stomach cannot take '
              'enough in two sittings.',
          TriageLevel.priority,
          value: '${i.mealsPerDay} meals',
          cutoff: '>= $minMeals meals',
          weight: 4,
        );
      }
      if (i.stillBreastfeeding == false && i.ageInMonths < 24) {
        add(
          'Breastfeeding stopped before 24 months',
          'Breast milk still supplies a meaningful share of energy and immune '
              'protection up to two years.',
          TriageLevel.watch,
          weight: 2,
        );
      }
      if (i.foodGroupsEatenYesterday == 0) {
        missing.add('24-hour food recall not taken');
      }
    }

    if (i.feedingChangedDuringIllness) {
      add(
        'Feeding reduced during this illness',
        'Illness is exactly when a child needs more, not less. Feed small '
            'amounts often and add one extra meal a day for two weeks after '
            'recovery.',
        TriageLevel.watch,
        weight: 2,
      );
    }

    // ---------------------------------------------------------------------
    // 7. ANAEMIA
    // ---------------------------------------------------------------------
    if (i.severePalmarPallor || (i.haemoglobin != null && i.haemoglobin! < 7)) {
      classifications.add('SEVERE ANAEMIA');
      add(
        'Severe anaemia',
        i.haemoglobin != null
            ? 'Haemoglobin ${i.haemoglobin!.toStringAsFixed(1)} g/dL is below '
                  '7 g/dL. May need transfusion.'
            : 'The palms are very pale, almost white. This is severe anaemia and '
                  'may need transfusion.',
        TriageLevel.urgent,
        value: i.haemoglobin == null
            ? 'severe pallor'
            : '${i.haemoglobin!.toStringAsFixed(1)} g/dL',
        cutoff: '< 7 g/dL',
        weight: 9,
        isDangerSign: true,
      );
      capabilities.addAll({'bloodTransfusion', 'laboratory'});
    } else if (i.somePalmarPallor ||
        (i.haemoglobin != null && i.haemoglobin! < 11)) {
      classifications.add('ANAEMIA');
      add(
        'Anaemia',
        i.haemoglobin != null
            ? 'Haemoglobin ${i.haemoglobin!.toStringAsFixed(1)} g/dL is below '
                  '11 g/dL.'
            : 'The palms are paler than yours. Treat with iron for 14 days, '
                  'deworm if over 1 year, and counsel on iron-rich local foods.',
        TriageLevel.priority,
        value: i.haemoglobin == null
            ? 'some pallor'
            : '${i.haemoglobin!.toStringAsFixed(1)} g/dL',
        cutoff: '< 11 g/dL',
        weight: 5,
      );
      actions.add(
        const RecommendedAction(
          instruction:
              'Give iron for 14 days and counsel on iron-rich foods that are '
              'actually available — dawadawa, moringa leaves, groundnut paste, '
              'liver, dried fish, cowpea.',
          urgency: ReferralUrgency.scheduled,
          rationale: 'Iron plus a diet the household can afford, not a diet it '
              'cannot.',
          protocolSource: _protocol,
          isTreatment: true,
          isCounselling: true,
        ),
      );
    }

    // ---------------------------------------------------------------------
    // 8. IMMUNISATION AND SUPPLEMENTS — checked at every contact
    // ---------------------------------------------------------------------
    if (i.overdueVaccines.isNotEmpty) {
      add(
        'Immunisation overdue',
        'Overdue: ${i.overdueVaccines.join(', ')}. Give what is due today unless '
            'the child is being referred for inpatient care, and record the '
            'catch-up plan.',
        TriageLevel.priority,
        weight: 3,
      );
      actions.add(
        RecommendedAction(
          instruction:
              'Vaccinate today for ${i.overdueVaccines.join(', ')}. A sick visit '
              'is a vaccination opportunity — a mild illness is not a '
              'contraindication.',
          urgency: ReferralUrgency.sameDay,
          rationale:
              'Missed opportunities are a leading cause of under-immunisation in '
              'rural districts.',
          protocolSource: 'Ghana EPI schedule',
          isTreatment: true,
        ),
      );
    } else if (i.immunisationsUpToDate == null) {
      missing.add('Immunisation card not seen');
    }

    if (i.ageInMonths >= 6 && i.vitaminALastSixMonths == false) {
      add(
        'Vitamin A due',
        'No vitamin A in the last 6 months. Give a dose today — it reduces '
            'child mortality and protects sight.',
        TriageLevel.watch,
        weight: 2,
      );
    }
    if (i.ageInMonths >= 12 && i.dewormedLastSixMonths == false) {
      add(
        'Deworming due',
        'No albendazole in the last 6 months. Worms drive anaemia and stunting.',
        TriageLevel.watch,
        weight: 2,
      );
    }

    // ---------------------------------------------------------------------
    // 9. MISSING MEASUREMENTS
    // ---------------------------------------------------------------------
    if (i.temperatureCelsius == null && !i.feverReported) {
      missing.add('Temperature not taken');
    }
    if (i.weightKg == null) {
      missing.add('Weight not taken — needed to dose medicines safely');
    }

    // ---------------------------------------------------------------------
    // 10. VERDICT
    // ---------------------------------------------------------------------
    final triage = findings.isEmpty
        ? TriageLevel.routine
        : findings
              .map((f) => f.severity)
              .reduce((a, b) => a.severity >= b.severity ? a : b);

    if (classifications.isEmpty) {
      classifications.add('NO IMCI CLASSIFICATION — WELL CHILD');
    }

    if (triage == TriageLevel.urgent) {
      actions.insert(
        0,
        RecommendedAction(
          instruction:
              'Refer this child now. Write the referral note, give any '
              'pre-referral treatment listed above, and help the family solve '
              'transport before they leave your sight.',
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
        nutrition == NutritionStatus.atRisk ||
        i.isComplementaryFeedingAge) {
      actions.add(
        const RecommendedAction(
          instruction:
              'Work through the local-food plan with the caregiver: choose foods '
              'that are in season now and within what this household can spend, '
              'and agree on two changes rather than ten.',
          urgency: ReferralUrgency.scheduled,
          rationale:
              'Advice a family cannot afford is advice that will not be '
              'followed. Two changes that happen beat ten that do not.',
          protocolSource: 'WHO IYCF / Ghana IYCF counselling',
          isCounselling: true,
        ),
      );
    }

    if (i.householdHasValidNhis == false) {
      actions.add(
        const RecommendedAction(
          instruction:
              'Start NHIS registration for this child. Without it, every '
              'referral you write carries a cost the family may not pay.',
          urgency: ReferralUrgency.scheduled,
          rationale: 'Insurance status is a strong predictor of whether a '
              'referral is completed.',
          isCounselling: true,
        ),
      );
    }

    return AssessmentResult(
      clientType: ClientType.childUnderFive,
      triage: triage,
      classification: classifications.join(' + '),
      findings: findings,
      actions: actions,
      confidence: _confidence(i, missing),
      confidenceScore: protocolConfidenceScore(
        measuredKeyInputs: [
          i.temperatureCelsius != null,
          i.respiratoryRate != null,
          i.muacCm != null || !i.muacApplies,
          i.weightKg != null,
        ].where((m) => m).length,
        keyInputCount: 4,
        observedDangerSign: i.hasAnyGeneralDangerSign || i.hasBilateralOedema,
      ),
      protocolSource: _protocol,
      nutritionStatus: nutrition,
      nutritionPathway: pathway,
      dangerSignsPresent: dangerSigns,
      missingData: missing,
      referralCapabilitiesNeeded: capabilities,
      followUpInDays: _followUp(triage, nutrition),
      caregiverMessage: _caregiverMessage(triage, dangerSigns, nutrition),
    );
  }

  /// Confidence is a function of what was actually measured. A verdict built on
  /// a caregiver's report of fever, with no thermometer, no MUAC tape and no
  /// breath count, must not be presented with the same weight as one built on
  /// three measurements.
  static RecommendationConfidence _confidence(
    ChildInput i,
    List<String> missing,
  ) {
    final measured = [
      i.temperatureCelsius != null,
      i.respiratoryRate != null,
      i.muacCm != null || !i.muacApplies,
      i.weightKg != null,
    ].where((m) => m).length;

    if (i.hasAnyGeneralDangerSign || i.hasBilateralOedema) {
      // Observed danger signs need no instrument to be certain.
      return RecommendationConfidence.protocolCertain;
    }
    if (measured == 4 && missing.isEmpty) {
      return RecommendationConfidence.protocolCertain;
    }
    if (measured >= 3) return RecommendationConfidence.high;
    if (measured >= 2) return RecommendationConfidence.moderate;
    return RecommendationConfidence.low;
  }

  static int? _followUp(TriageLevel triage, NutritionStatus? nutrition) {
    if (triage == TriageLevel.urgent) return 1;
    if (nutrition == NutritionStatus.moderateAcute) return 14;
    if (nutrition == NutritionStatus.atRisk) return 30;
    if (triage == TriageLevel.priority) return 3;
    if (triage == TriageLevel.watch) return 14;
    return 30;
  }

  /// Plain language for the caregiver, written to be read aloud or played as
  /// recorded audio in Dagbani, Gurene, Dagaare, Sissali or Likpakpaln. Every
  /// message ends with the return-immediately signs, because that single habit
  /// saves more children than any classification.
  static String _caregiverMessage(
    TriageLevel triage,
    List<String> dangerSigns,
    NutritionStatus? nutrition,
  ) {
    final buffer = StringBuffer();
    switch (triage) {
      case TriageLevel.urgent:
        buffer.write(
          'Your child is seriously ill and must be seen at the health facility '
          'today. Please do not wait until tomorrow. ',
        );
        if (dangerSigns.isNotEmpty) {
          buffer.write('What worries us: ${dangerSigns.first.toLowerCase()}. ');
        }
      case TriageLevel.priority:
        buffer.write(
          'Your child needs the medicine we have given and must be seen again '
          'in three days. Give every dose, even when the child looks better. ',
        );
      case TriageLevel.watch:
        buffer.write(
          'Your child can be cared for at home. Keep feeding and give plenty of '
          'fluids. ',
        );
      case TriageLevel.routine:
        buffer.write(
          'Your child is doing well. Keep doing what you are doing. ',
        );
    }

    if (nutrition == NutritionStatus.severeAcute) {
      buffer.write(
        'Your child is too thin and needs special feeding medicine from the '
        'health facility. Ordinary food at home is not enough now. ',
      );
    } else if (nutrition == NutritionStatus.moderateAcute) {
      buffer.write(
        'Your child is becoming too thin. We will choose foods you already have '
        'so the child gains weight again. ',
      );
    }

    buffer.write(
      'Come back at once, at any hour, if the child cannot drink or breastfeed, '
      'vomits everything, has fits, becomes very sleepy or hard to wake, or '
      'breathes with difficulty.',
    );
    return buffer.toString();
  }
}
