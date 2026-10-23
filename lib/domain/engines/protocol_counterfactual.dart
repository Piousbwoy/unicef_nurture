/// How far a measurement sat from the line that decided it, and what value
/// would have decided differently.
///
/// Both halves re-run the real engine. Nothing here paraphrases a guideline or
/// quotes a stored sentence: `ChildEngine.assess` is pure, so asking it what it
/// would have said at 48 breaths per minute is a question it can actually answer
/// — the same discipline the offline runtime already applies when it re-runs a
/// model with one feature removed.
///
/// Why this belongs on a verdict screen: two children can carry the same
/// classification with completely different comfort behind it. A rate of 51
/// against a cut-off of 50 is pneumonia on precisely as firm a footing as 62 —
/// and precisely as worth re-counting. A single blended confidence percentage
/// cannot say that; a margin can, in one number a nurse can check.
library;

import 'child_engine.dart';

/// Which side of the cut-off makes a value abnormal.
enum AbnormalSide { above, below }

/// One threshold, the value it was applied to, and the distance between them.
class CriterionMargin {
  const CriterionMargin({
    required this.label,
    required this.measurement,
    required this.cutoff,
    required this.abnormalSide,
    required this.unit,
    this.value,
  });

  /// What the guideline calls it, e.g. "Fast breathing".
  final String label;

  /// The input field this threshold reads, used by the counterfactual probe.
  final String measurement;

  final double cutoff;
  final AbnormalSide abnormalSide;
  final String unit;

  /// The recorded value, null when the measurement was never taken.
  final double? value;

  /// A distance is only meaningful against the scale it is measured on: 1 beat
  /// out of 50 is nothing, 1 cm out of 11.5 is nearly 9%.
  static const double _borderlineShare = 0.10;

  bool get measured => value != null;

  /// Fractional distance from the cut-off.
  double get relativeDistance {
    if (value == null || cutoff == 0) return double.infinity;
    return ((value! - cutoff).abs() / cutoff.abs());
  }

  /// True when the verdict rests on a hair of the line. Reported as a fact about
  /// the arithmetic, not as a claim that the classification is wrong.
  bool get borderline => measured && relativeDistance <= _borderlineShare;

  bool get abnormal {
    if (value == null) return false;
    return abnormalSide == AbnormalSide.above
        ? value! >= cutoff
        : value! <= cutoff;
  }

  String get statement {
    if (value == null) {
      return '$label not counted — no margin can be computed';
    }
    final v = _fmt(value!, unit);
    final line = _fmt(cutoff, unit);
    final side = abnormalSide == AbnormalSide.above ? '≥' : '≤';
    final edge = borderline
        ? ' — within ${(relativeDistance * 100).toStringAsFixed(0)}% of the line'
        : '';
    return '$label $v $side $line$edge';
  }
}

/// The result of asking the engine what it would have said.
class ProtocolCounterfactualResult {
  const ProtocolCounterfactualResult({
    required this.measurement,
    required this.fromValue,
    required this.toValue,
    required this.unit,
    required this.conditionBefore,
    required this.conditionAfter,
    required this.verdictChanges,
    required this.sentence,
  });

  final String measurement;
  final num fromValue;
  final num toValue;
  final String unit;

  /// The engine's own classification string, verbatim, both times.
  final String conditionBefore;
  final String conditionAfter;
  final bool verdictChanges;
  final String sentence;
}

abstract final class ProtocolThresholds {
  /// The numeric cut-offs the sick-child protocol applies to this child's age
  /// band. Read from the same expressions the engine uses, so a change in the
  /// guideline cannot leave a stale threshold here unnoticed.
  static List<CriterionMargin> forChild(ChildInput i) => [
    CriterionMargin(
      label: 'Fast breathing',
      measurement: 'respiratoryRate',
      cutoff: i.fastBreathingThreshold.toDouble(),
      abnormalSide: AbnormalSide.above,
      unit: '/min',
      value: i.respiratoryRate?.toDouble(),
    ),
    CriterionMargin(
      label: 'Fever',
      measurement: 'temperatureCelsius',
      cutoff: 37.5,
      abnormalSide: AbnormalSide.above,
      unit: '°C',
      value: i.temperatureCelsius,
    ),
    if (i.muacApplies)
      CriterionMargin(
        label: 'Severe acute malnutrition',
        measurement: 'muacCm',
        cutoff: 11.5,
        abnormalSide: AbnormalSide.below,
        unit: 'cm',
        value: i.muacCm,
      ),
  ];

  /// The margins worth showing on a verdict: the abnormal ones first, and the
  /// unmeasured ones as gaps rather than as silence.
  static List<CriterionMargin> decisiveForChild(ChildInput i) {
    final all = forChild(i);
    final abnormal = all.where((m) => m.abnormal).toList();
    final gaps = all.where((m) => !m.measured).toList();
    return [...abnormal, ...gaps];
  }
}

abstract final class ProtocolCounterfactual {
  /// Re-runs the sick-child assessment with one measurement changed.
  ///
  /// Returns null when the measurement was not taken (there is nothing to vary)
  /// or when the name is not one this probe understands. Both answers are
  /// honest; a number for either would be invented.
  static ProtocolCounterfactualResult? forChild({
    required ChildInput input,
    required String measurement,
    required num toValue,
  }) {
    final current = _valueOrNull(input, measurement);
    if (current == null) return null;
    final unit = _unitFor(measurement);

    final before = ChildEngine.assess(input);
    final after = ChildEngine.assess(_apply(input, measurement, toValue));

    final changed = before.classification != after.classification;
    return ProtocolCounterfactualResult(
      measurement: measurement,
      fromValue: current,
      toValue: toValue,
      unit: unit,
      conditionBefore: before.classification,
      conditionAfter: after.classification,
      verdictChanges: changed,
      sentence: changed
          ? 'At ${_fmt(toValue, unit)} this visit would no longer read as '
                '${before.classification}. It would read: ${after.classification}.'
          : 'At ${_fmt(toValue, unit)} the verdict is still '
                '${after.classification} — this call does not turn on a hair.',
    );
  }

  /// Steps the measurement one unit at a time towards normal and returns the
  /// first value where the real engine says something different.
  ///
  /// Searched rather than assumed, so it stays correct if the band logic or the
  /// threshold ever moves. Bounded, because a value that can never flip is an
  /// answer too — it means the verdict does not depend on this measurement.
  static ProtocolCounterfactualResult? nearestFlipForChild({
    required ChildInput input,
    required String measurement,
    int maxSteps = 80,
  }) {
    final current = _valueOrNull(input, measurement);
    if (current == null) return null;

    final isAbove = _abnormalSideFor(measurement) == AbnormalSide.above;
    final step = _stepFor(measurement);
    var probe = current;

    for (var n = 0; n < maxSteps; n++) {
      probe = isAbove ? probe - step : probe + step;
      if (_outOfRange(measurement, probe)) return null;
      final cf = forChild(
        input: input,
        measurement: measurement,
        toValue: probe,
      );
      if (cf == null) return null;
      if (cf.verdictChanges) return cf;
    }
    return null;
  }

  /// Null for a measurement that was never taken, and null for a name this
  /// probe does not understand. Both callers must refuse rather than substitute
  /// a zero: an absent respiratory rate read as 0/min would look like the most
  /// abnormal value in the register.
  static num? _valueOrNull(ChildInput i, String measurement) =>
      switch (measurement) {
        'respiratoryRate' => i.respiratoryRate,
        'temperatureCelsius' => i.temperatureCelsius,
        'muacCm' => i.muacCm,
        _ => null,
      };

  static ChildInput _apply(ChildInput i, String measurement, num value) =>
      switch (measurement) {
        'respiratoryRate' => i.copyWith(respiratoryRate: value.toInt()),
        'temperatureCelsius' => i.copyWith(
          temperatureCelsius: value.toDouble(),
        ),
        'muacCm' => i.copyWith(muacCm: value.toDouble()),
        _ => i,
      };

  static AbnormalSide _abnormalSideFor(String measurement) =>
      measurement == 'muacCm' ? AbnormalSide.below : AbnormalSide.above;

  static num _stepFor(String measurement) =>
      measurement == 'respiratoryRate' ? 1 : 0.5;

  static String _unitFor(String measurement) => switch (measurement) {
    'respiratoryRate' => '/min',
    'temperatureCelsius' => '°C',
    'muacCm' => 'cm',
    _ => '',
  };

  /// A probe that wanders into impossible physiology is stopped, not answered.
  static bool _outOfRange(String measurement, num v) => switch (measurement) {
    'respiratoryRate' => v < 5 || v > 120,
    'temperatureCelsius' => v < 30 || v > 43,
    'muacCm' => v < 5 || v > 25,
    _ => true,
  };
}

String _fmt(num v, String unit) {
  final s = v is int || v == v.roundToDouble()
      ? v.round().toString()
      : v.toStringAsFixed(1);
  return '$s$unit';
}
