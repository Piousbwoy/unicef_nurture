import '../../core/ml/offline_inference_service.dart';
import '../../domain/engines/protocols/stabilization_protocol_selector.dart';
import '../../domain/enums.dart';
import 'types.dart';

/// Separates this encounter's observations from birth and obstetric history.
/// An absent checklist is unknown, not a collection of negative answers.
class AssessmentFeatureAdapter {
  const AssessmentFeatureAdapter(this.context, this.draft);
  final AssessmentContext context;
  final AssessmentDraft draft;

  Map<String, Object?> get inputs => draft.inputs;
  bool get isMaternal => switch (draft.result.clientType) {
    ClientType.pregnantWoman ||
    ClientType.postpartumWoman ||
    ClientType.womanOfReproductiveAge => true,
    _ => false,
  };
  int? integer(String key) {
    final v = inputs[key];
    return v is num && v.isFinite && v == v.roundToDouble() ? v.toInt() : null;
  }

  double? number(String key) =>
      inputs[key] is num ? (inputs[key] as num).toDouble() : null;
  int? get ageDays => isMaternal
      ? null
      : inputs.containsKey('age_in_days')
      ? integer('age_in_days')
      : context.person.ageInDays;
  int? get ageMonths => isMaternal
      ? null
      : inputs.containsKey('age_in_months')
      ? integer('age_in_months')
      : context.person.ageInMonths;
  bool get isObstetric =>
      draft.result.clientType == ClientType.pregnantWoman ||
      draft.result.clientType == ClientType.postpartumWoman;

  bool? signs(List<String> names, {String key = 'danger_signs'}) {
    final collected = inputs[key];
    if (collected is! List) return null;
    if (names.any(collected.contains)) return true;
    final available = key == 'pre_eclampsia_flags'
        ? const {
            'oedema_hands_or_face',
            'epigastric_pain',
            'headache_severe',
            'blurred_vision',
            'brisk_reflexes',
            'oliguria',
            'weight_gain_over_1kg_per_week',
          }
        : switch (draft.result.clientType) {
            ClientType.newborn => const {
              'notFeeding',
              'noFeed',
              'convulsions',
              'movesStim',
              'noMove',
              'indrawing',
              'fontanelle',
              'cordRed',
              'cordSpread',
              'jaundice24',
            },
            ClientType.childUnderFive => const {
              'noDrink',
              'vomitsAll',
              'convulsions',
              'convulsingNow',
              'lethargic',
              'cough',
              'diffBreath',
              'indrawing',
              'stridor',
            },
            ClientType.pregnantWoman => const {
              'headache',
              'vision',
              'swelling',
              'convulsions',
            },
            ClientType.postpartumWoman || ClientType.womanOfReproductiveAge =>
              const {'headache', 'vision', 'convulsions'},
          };
    return names.any(available.contains) ? false : null;
  }

  static bool? positive(bool? value) => value == true ? true : null;

  static bool? either(bool? a, bool? b) => a == true || b == true
      ? true
      : a == false && b == false
      ? false
      : null;
  bool? pe(String flag, [String? general]) => general == null
      ? signs([flag], key: 'pre_eclampsia_flags')
      : either(signs([flag], key: 'pre_eclampsia_flags'), signs([general]));

  OfflineFeatureBag get features {
    final birth = context.birth;
    final history = context.maternal;
    final snapshot = draft.snapshot;
    final weight = number('weight_kg');
    final height = number('height_cm');
    return OfflineFeatureBag(
      ageDays: ageDays,
      ageMonths: ageMonths,
      isMaternal: isMaternal,
      gestationalWeeks: draft.result.clientType == ClientType.pregnantWoman
          ? integer('gestational_weeks')
          : null,
      gestationalWeeksAtBirth: birth?.gestationWeeksAtBirth,
      heartRatePerMin: integer('pulse'),
      respiratoryRatePerMin:
          integer('respiratory_rate') ?? snapshot?.respiratoryRatePerMin,
      temperatureCelsius:
          number('temperature_celsius') ?? snapshot?.temperatureCelsius,
      oxygenSaturationPerCent:
          integer('oxygen_saturation') ?? snapshot?.oxygenSaturationPerCent,
      systolicBloodPressureMmhg: integer('systolic'),
      diastolicBloodPressureMmhg: integer('diastolic'),
      maternalMuacMm: isMaternal
          ? integer('muac_mm') ??
                (number('muac_cm')?.isFinite == true
                    ? (number('muac_cm')! * 10).round()
                    : null)
          : null,
      maternalBmi: isMaternal && weight != null && height != null && height > 0
          ? weight / ((height / 100) * (height / 100))
          : null,
      haemoglobinGDl: number('haemoglobin'),
      urineProtein0To4: integer('proteinuria') ?? integer('urine_protein'),
      urineKetones0To3: integer('urine_ketones'),
      urineBlood0To3: integer('urine_blood'),
      urineGlucose0To4: integer('urine_glucose'),
      maternalAgeYears: isMaternal ? context.person.ageInYears : null,
      gravida: isMaternal ? integer('gravida') ?? history?.gravida : null,
      parity: isMaternal ? integer('parity') ?? history?.parity : null,
      previousPregnancyLosses: isMaternal ? history?.previousLosses : null,
      prevCaesareanSection: isMaternal ? history?.previousCaesarean : null,
      oedemaHandsOrFace: pe('oedema_hands_or_face', 'swelling'),
      epigastricPain: pe('epigastric_pain'),
      headacheSevere: pe('headache_severe', 'headache'),
      blurredVision: pe('blurred_vision', 'vision'),
      briskReflexes: pe('brisk_reflexes'),
      oliguria: pe('oliguria'),
      weightGainOver1kgPerWeek: pe('weight_gain_over_1kg_per_week'),
      birthWeightKg: number('birth_weight_kg') ?? birth?.birthWeightKg,
      birthLengthCm: birth?.birthLengthCm,
      apgar5Minute: birth?.apgar5Minute,
      historyOfConvulsions:
          signs(['convulsions', 'convulsingNow']) ??
          positive(snapshot?.hasConvulsionsThisVisit),
      severeChestIndrawing:
          signs(['indrawing']) ?? positive(snapshot?.chestIndrawing),
      nasalFlaring: signs(['nasalFlaring']) ?? positive(snapshot?.nasalFlaring),
      grunting: signs(['grunting']),
      bulgingFontanelle: signs(['fontanelle', 'bulgingFontanelle']),
      jaundiceBefore24h: signs(['jaundice24']),
      feedingDifficulty: signs(['notFeeding', 'noFeed', 'feedingDifficulty']),
      abdominalDistension: signs(['abdominalDistension']),
      cordRednessBeyondBase: signs(['cordSpread']),
      cordPus: signs(['cordPus']),
      skinPustules: integer('skin_pustules') != null
          ? integer('skin_pustules')! > 0
          : signs(['skinPustules']),
      lethargicOrUnconscious:
          signs(['lethargic', 'unconscious', 'noMove', 'movesStim']) ??
          positive(snapshot?.isLethargicOrUnconscious),
      bleedingFromAnySite: signs(['bleeding']),
      coughPresent: signs(['cough']) ?? positive(snapshot?.coughPresent),
      chestIndrawing:
          signs(['indrawing']) ?? positive(snapshot?.chestIndrawing),
      stridorCalm: signs(['stridor']) ?? positive(snapshot?.stridorCalm),
      generalDangerSign: signs([
        'unconscious',
        'lethargic',
        'noMove',
        'movesStim',
        'noDrink',
        'cannotDrink',
        'noFeed',
        'vomitsAll',
        'vomitsEverything',
        'convulsions',
        'convulsingNow',
      ]),
      multipleBirth: birth == null
          ? null
          : birth.plurality != BirthPlurality.singleton,
    );
  }

  StabilizationContext get stabilization {
    final bag = features;
    return StabilizationContext(
      isMaternal: isObstetric,
      patientAgeDays: ageDays,
      patientAgeMonths: ageMonths,
      gestationalWeeks: bag.gestationalWeeks,
      systolicBp: bag.systolicBloodPressureMmhg,
      diastolicBp: bag.diastolicBloodPressureMmhg,
      urineProtein0To4: bag.urineProtein0To4,
      hasEclampsiaConvulsions: isObstetric && signs(['convulsions']) == true,
      temperatureCelsius: bag.temperatureCelsius,
      oxygenSaturation: bag.oxygenSaturationPerCent,
      respiratoryRate: bag.respiratoryRatePerMin,
      unableToFeed: signs(['noFeed', 'noDrink', 'cannotDrink']) == true,
      convulsions: bag.historyOfConvulsions == true,
      severeChestIndrawing: bag.severeChestIndrawing == true,
      bulgingFontanelle: bag.bulgingFontanelle == true,
      lethargicOrUnconscious: bag.lethargicOrUnconscious == true,
      cordPus: bag.cordPus == true,
      feedingDifficulty: bag.feedingDifficulty == true,
      skinPustules: bag.skinPustules == true,
      coughPresent: bag.coughPresent == true,
      generalDangerSign: bag.generalDangerSign == true,
    );
  }
}
