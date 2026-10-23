/// Rebuilding a [ChildInput] from a stored measurement map — and refusing to use
/// it unless it reproduces the verdict on screen.
///
/// ## Why this file has to exist
///
/// `protocol_counterfactual.dart` answers "what would have to be different for
/// this call to change?" That question needs the *input object* the classifier
/// consumed. The result screen does not hold one: it holds the map the form
/// persisted (`danger_signs`, `respiratory_rate`, …), and it renders saved
/// records as readily as live ones, so there is no object to thread through.
///
/// ## Why it is safe
///
/// The form writes the same values it read. The sign tokens are stored verbatim,
/// the rate as an integer, the skin-pinch and pallor grades as their code strings.
/// So the map can be read back into the same shape.
///
/// But "can be" is a claim, not a fact, and a reconstruction that quietly drops
/// or misreads one field would compute a confident counterfactual about a child
/// the protocol never saw. So the output is **gated on agreement**: the rebuilt
/// input is re-assessed, and unless its classification string equals the stored
/// one, this returns `null`. Callers show nothing.
///
/// A missing line beats a speculative one. `ChildInput` has 63 fields; this file
/// maps every one the child form writes, because the gate can only prove what it
/// is given — and a field left out by mistake would show up as a refused
/// reconstruction rather than a silent wrong answer.
library;

import '../enums.dart';
import 'child_engine.dart';
import 'immunisation_engine.dart';

abstract final class ChildInputReconstruction {
  /// The protocol tag `child_form.dart` writes for a 2–59 month IMCI visit.
  static const String childProtocolTag = 'imci_child';

  /// Whether this cohort's record can be rebuilt at all. The child engine knows
  /// one protocol; running a young-infant or maternal map through it would answer
  /// a different question with the same confidence.
  static bool supports(ClientType cohort) => cohort == ClientType.childUnderFive;

  /// The input behind a stored child assessment, or `null` when it cannot be
  /// rebuilt in a way that reproduces [storedClassification].
  static ChildInput? forCounterfactual({
    required Map<String, Object?> inputs,
    required String? storedClassification,
    int? ageInMonths,
    bool? householdHasValidNhis,
    int? walkingMinutesToFacility,
  }) {
    if (storedClassification == null) return null;
    if (inputs['protocol'] != childProtocolTag) return null;

    final months = _int(inputs['age_in_months']) ?? ageInMonths;
    // The IMCI thresholds are age-banded: 50/min below 12 months, 40/min above.
    // Without months there is no band, so there is no honest counterfactual.
    if (months == null || months < 2 || months > 59) return null;

    final signs = _tokens(inputs['danger_signs']);
    final rdtDone = _bool(inputs['rdt_done']);
    final pallor = inputs['palmar_pallor_severity'] as String?;
    final pinch = inputs['skin_pinch_result'] as String?;
    final days = (inputs['age_in_days'] as num?)?.toInt() ??
        (months * 30.4375).round();
    final given = _tokens(inputs['vaccines_given']);
    final vaxPlan = ImmunisationEngine.plan(
      ageInDays: days,
      givenLabels: given.toSet(),
    );

    final input = ChildInput(
      ageInMonths: months,
      respiratoryRate: _int(inputs['respiratory_rate']),
      temperatureCelsius: _double(inputs['temperature_celsius']),
      weightKg: _double(inputs['weight_kg']),
      heightCm: _double(inputs['height_cm']),
      muacCm: _muacCm(inputs),
      hasBilateralOedema: inputs['has_oedema'] == true,
      // ------------------------------------------------ General danger signs
      unableToDrinkOrBreastfeed: signs.contains('noDrink'),
      vomitsEverything: signs.contains('vomitsAll'),
      convulsions: signs.contains('convulsions'),
      lethargicOrUnconscious: signs.contains('lethargic'),
      convulsingNow: signs.contains('convulsingNow'),
      // ------------------------------------------------------------- Cough
      cough: signs.contains('cough'),
      coughDurationDays: _int(inputs['cough_days']),
      difficultBreathing: signs.contains('diffBreath'),
      chestIndrawing: signs.contains('indrawing'),
      stridor: signs.contains('stridor'),
      wheeze: signs.contains('wheeze'),
      oxygenSaturation: _int(inputs['oxygen_saturation']),
      // ---------------------------------------------------------- Diarrhoea
      diarrhoea: signs.contains('diarrhoea'),
      diarrhoeaDurationDays: _int(inputs['diarrhoea_days']),
      bloodInStool: signs.contains('bloodStool'),
      sunkenEyes: signs.contains('sunkenEyes'),
      skinPinchVerySlow: pinch == 'very_slow',
      skinPinchSlow: pinch == 'slow',
      restlessOrIrritable: signs.contains('restless'),
      drinksEagerly: signs.contains('drinksEagerly'),
      // -------------------------------------------------------------- Fever
      feverReported: signs.contains('fever'),
      feverDurationDays: _int(inputs['fever_days']),
      malariaRdtDone: rdtDone ?? false,
      // The form itself refuses to record a result for a test that was not done;
      // reading one back would invent a result.
      malariaRdtPositive: rdtDone == true ? _bool(inputs['rdt_positive']) : null,
      stiffNeck: signs.contains('stiffNeck'),
      // ------------------------------------------------------------- Other
      runnyNose: signs.contains('runnyNose'),
      measlesRash: signs.contains('measlesRash'),
      mouthUlcers: signs.contains('mouthUlcers'),
      pusDrainingFromEye: signs.contains('eyePus'),
      corneaClouding: signs.contains('corneaClouding'),
      earPain: signs.contains('earPain'),
      earDischarge: signs.contains('earDischarge'),
      earDischargeDurationDays: _int(inputs['ear_discharge_days']),
      tenderSwellingBehindEar: signs.contains('mastoid'),
      severePalmarPallor: pallor == 'severe',
      somePalmarPallor: pallor == 'some',
      haemoglobin: _double(inputs['haemoglobin']),
      // -------------------------------------------------------- Feeding and
      // programme state, which the nurturing-care block reads as inputs.
      stillBreastfeeding: _bool(inputs['still_breastfeeding']),
      mealsPerDay: _int(inputs['meals_per_day']),
      foodGroupsEatenYesterday: (_list(inputs['food_groups'])).length,
      feedingChangedDuringIllness: _bool(inputs['feeding_changed']) ?? false,
      appetiteTestPassed: _bool(inputs['appetite_test']),
      immunisationsUpToDate: vaxPlan.isFullyUpToDate,
      overdueVaccines: vaxPlan.overdueLabels,
      vitaminALastSixMonths: _bool(inputs['vitamin_a']),
      dewormedLastSixMonths: _bool(inputs['dewormed']),
      householdHasValidNhis: householdHasValidNhis,
      walkingMinutesToFacility: walkingMinutesToFacility,
    );

    return _agreesWithStoredVerdict(input, storedClassification) ? input : null;
  }

  /// The gate. Re-running a pure function on the rebuilt input must return the
  /// very verdict we saved; anything else means the map and the record disagree,
  /// and no speculation built on top of that disagreement is worth showing.
  static bool _agreesWithStoredVerdict(
    ChildInput input,
    String storedClassification,
  ) {
    try {
      return ChildEngine.assess(input).classification == storedClassification;
    } catch (_) {
      // A restored row can hold shapes this build never wrote. Refuse quietly.
      return false;
    }
  }

  // --------------------------------------------------------------- readers
  // Lenient by design: an unreadable value becomes null, which changes the
  // verdict, which closes the gate. Strictness lives in the gate, not here.

  static int? _int(Object? v) => switch (v) {
    null => null,
    final num n => n.toInt(),
    final String s => int.tryParse(s.trim()),
    _ => null,
  };

  static double? _double(Object? v) => switch (v) {
    null => null,
    final num n => n.toDouble(),
    final String s => double.tryParse(s.trim()),
    _ => null,
  };

  static bool? _bool(Object? v) => switch (v) {
    null => null,
    final bool b => b,
    final num n => n != 0,
    _ => null,
  };

  /// MUAC is written in both units; centimetres win, because that is the unit the
  /// thresholds and the `muacApplies` rule are stated in.
  static double? _muacCm(Map<String, Object?> inputs) {
    final cm = _double(inputs['muac_cm']);
    if (cm != null) return cm;
    final mm = _double(inputs['muac_mm']);
    return mm == null ? null : mm / 10.0;
  }

  static List<String> _tokens(Object? v) => [
    for (final entry in _list(v)) entry.toString(),
  ];

  static List<Object?> _list(Object? v) => v is List ? v : const [];
}
