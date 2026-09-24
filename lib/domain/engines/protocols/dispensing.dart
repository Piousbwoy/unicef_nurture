/// Bedside arithmetic for weight-based doses.
///
/// Turns a published per-kilogram figure and the child's recorded weight into
/// the physical amount a CHO measures out — tablets, or millilitres — and
/// states the working so the number can be checked by eye at the bedside
/// rather than trusted.
///
/// This is presentation arithmetic and nothing more. It does not decide
/// whether a drug is indicated, does not know any indication, and does not
/// invent a dose the citation did not publish. Where the strength on hand
/// cannot deliver the target, it says so and says by how far it missed,
/// instead of quietly rounding into a number that looks authoritative.
library;

import 'package:flutter/foundation.dart';

/// How far the counted-unit amount may sit from the calculated target before
/// the module stops presenting it as a usable measure. This is a tolerance on
/// *pack geometry*, not a clinical one — it exists so the screen never shows
/// a confidently-rounded number that the CHO might read as the dose. Judging
/// whether a given overshoot is acceptable for a given child stays with the
/// clinician.
const double kMaxAcceptableDriftPercent = 20.0;

/// One dispensable unit of one medicine, as the pack states it.
@immutable
class DrugUnit {
  const DrugUnit({
    required this.label,
    required this.mg,
    this.halvable = false,
  });

  /// How the CHO names it out loud: "250 mg dispersible tablet".
  final String label;

  /// Drug per unit.
  final double mg;

  /// Whether the unit may be split, which halves the smallest measurable step.
  /// Dispersible amoxicillin tablets are; a sealed suppository is not.
  final bool halvable;

  String get pluralLabel => '${label}s';
}

/// What a [Dispensing] produced for one specific child.
@immutable
class Dispensed {
  const Dispensed({
    required this.working,
    required this.measure,
    required this.citationNote,
    this.driftPercent,
    this.unmeasurable = false,
    this.caution,
  });

  /// The arithmetic, e.g. "40 mg/kg × 11.2 kg = 448 mg".
  final String working;

  /// What to actually give, e.g. "2 × 250 mg dispersible tablet = 500 mg".
  final String measure;

  /// Where the per-kg figure comes from — never implied, always shown.
  final String citationNote;

  /// How far the amount that can be measured sits from the calculated
  /// target, in per cent. Null when the two are equal.
  final double? driftPercent;

  /// True when the presentation on hand cannot reach the target closely
  /// enough to be given as counted units: the CHO needs a different
  /// strength, not a rounded number.
  final bool unmeasurable;

  /// What to do instead when [unmeasurable] is true. Null otherwise.
  final String? caution;
}

/// A weight-based instruction attached to a protocol step.
@immutable
sealed class Dispensing {
  const Dispensing();

  /// Null when the weight is missing — a missing weight must suppress the
  /// computed line, never produce a guessed one.
  Dispensed? dispense(double? weightKg);

  /// Doses below this weight are outside what the citation covers.
  double? get minimumWeightKg => null;
}

/// A solid dose: mg per kg, given in counted units of one [DrugUnit].
@immutable
final class DosePerKilogram extends Dispensing {
  const DosePerKilogram({
    required this.mgPerKg,
    required this.unit,
    required this.citation,
    this.maximumSingleDoseMg,
    this.minimumWeightKg,
  });

  final double mgPerKg;
  final DrugUnit unit;
  final String citation;

  /// A ceiling the citation itself states. Left null unless a source says so:
  /// guessing an adult-max cap is how a child gets an adult dose.
  final double? maximumSingleDoseMg;

  @override
  final double? minimumWeightKg;

  @override
  Dispensed? dispense(double? weightKg) {
    if (weightKg == null || weightKg <= 0) return null;
    final targetMg = mgPerKg * weightKg;
    final wantedMg = maximumSingleDoseMg != null &&
            targetMg > maximumSingleDoseMg!
        ? maximumSingleDoseMg!
        : targetMg;

    final step = unit.halvable ? 0.5 : 1.0;
    var units = (wantedMg / unit.mg / step).roundToDouble() * step;
    if (units < step) units = 0;

    final deliveredMg = units * unit.mg;
    final drift = deliveredMg == targetMg
        ? null
        : (deliveredMg - targetMg) / targetMg * 100;
    final unmeasurable = units == 0 ||
        (drift != null && drift.abs() > kMaxAcceptableDriftPercent);

    return Dispensed(
      working:
          '${_n(mgPerKg)} mg/kg × ${_n(weightKg)} kg = ${_n(targetMg)} mg',
      measure: units == 0
          ? 'Less than one ${unit.label} is needed — this cannot be counted '
                'out accurately'
          : '${_n(units)} × ${unit.label} = ${_n(deliveredMg)} mg',
      citationNote: citation,
      driftPercent: drift,
      unmeasurable: unmeasurable,
      caution: _caution(
        units: units,
        unit: unit,
        drift: drift,
        unmeasurable: unmeasurable,
      ),
    );
  }

  /// What to say instead of a number when the pack cannot deliver this dose
  /// as counted units. Null whenever the measure is sound.
  static String? _caution({
    required double units,
    required DrugUnit unit,
    required double? drift,
    required bool unmeasurable,
  }) {
    if (!unmeasurable) return null;
    if (units == 0) {
      return 'One ${unit.label} (${_n(unit.mg)} mg) is the smallest amount '
          'this presentation can give and it overshoots the calculated dose. '
          'Use a weaker strength.';
    }
    return 'The closest amount measurable with ${unit.pluralLabel} is '
        '${_n(drift!.abs())}% from the calculated dose. Do not round to this '
        'figure — measure it with a suspension or a strength that fits.';
  }
}

/// A weight-based milligram target with no countable presentation attached.
///
/// For the cases where the per-kg figure is published but this build holds no
/// citable strength table to convert it into units: the CHO gets the exact
/// figure and picks the presentation, instead of the app guessing one.
@immutable
final class MilligramTarget extends Dispensing {
  const MilligramTarget({
    required this.mgPerKg,
    required this.citation,
    required this.selectNote,
    this.minimumWeightKg,
  });

  final double mgPerKg;
  final String citation;

  /// How to act on the figure, e.g. "Choose the rectal strength closest to
  /// this figure."
  final String selectNote;

  @override
  final double? minimumWeightKg;

  @override
  Dispensed? dispense(double? weightKg) {
    if (weightKg == null || weightKg <= 0) return null;
    final targetMg = mgPerKg * weightKg;
    return Dispensed(
      working:
          '${_n(mgPerKg)} mg/kg × ${_n(weightKg)} kg = ${_n(targetMg)} mg',
      measure: '${_n(targetMg)} mg total. $selectNote',
      citationNote: citation,
    );
  }
}

/// A fluid volume: ml per kg, given over a fixed number of hours.
@immutable
final class FluidPerKilogram extends Dispensing {
  const FluidPerKilogram({
    required this.mlPerKg,
    required this.hours,
    required this.citation,
    this.mlPerSachet = 1000,
    this.minimumWeightKg,
  });

  final double mlPerKg;
  final double hours;
  final String citation;

  /// Solution one sachet makes, per the sachet label. Defaults to the
  /// one-litre WHO low-osmolarity sachet.
  final double mlPerSachet;

  @override
  final double? minimumWeightKg;

  @override
  Dispensed? dispense(double? weightKg) {
    if (weightKg == null || weightKg <= 0) return null;
    final totalMl = mlPerKg * weightKg;
    final sachets = (totalMl / mlPerSachet).ceil();
    return Dispensed(
      working:
          '${_n(mlPerKg)} ml/kg × ${_n(weightKg)} kg = ${_n(totalMl)} ml',
      measure:
          'Give ${_n(totalMl)} ml over ${_n(hours)} hours — about '
          '${_n(totalMl / hours)} ml an hour, from ${_n(sachets.toDouble())} '
          '× ${_n(mlPerSachet)} ml sachet${sachets == 1 ? '' : 's'}',
      citationNote: citation,
    );
  }
}

/// A number for a caregiver-facing sentence: one decimal, trailing zero cut.
String _n(double value) {
  final text = value.toStringAsFixed(1);
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}
