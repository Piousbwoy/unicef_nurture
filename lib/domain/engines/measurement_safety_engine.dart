/// Measurement plausibility screening — the guard against garbage-in.
///
/// Every clinical engine downstream is only as safe as the numbers fed into
/// it. A temperature typed as **98.6** (Fahrenheit, not Celsius), a MUAC
/// recorded as **115** (millimetres, not centimetres), or a weight keyed as
/// **1.6** (a misplaced decimal) will each drive a confident, protocol-cited —
/// and wrong — recommendation. That is the most dangerous kind of error an
/// app can make: a precise answer to a misheard question.
///
/// This engine sits **in front of** the clinical engines. It applies absolute
/// physiological bounds to each measurement and flags anything outside them as
/// a likely recording or device error, with a plain instruction to re-measure.
/// It never diagnoses and never triages — it only says *"this number cannot be
/// right, check it before you act on it."*
///
/// The bounds are deliberately wide so a true value is never flagged, while
/// still catching the common field errors: unit mix-ups (°F for °C, mm for
/// cm, g/L for g/dL), transposed decimals, and blanks typed as digits.
library;

import '../entities/visit.dart';
import '../enums.dart';

/// A measurement the app collects, with the absolute range a living human
/// could plausibly produce. Anything outside is a data error, not a patient.
enum MeasurementKind {
  weightKg(
    'Weight',
    'kg',
    1.0,
    200.0,
    'Check the scale was zeroed and the child was not held. Re-weigh.',
  ),
  heightCm(
    'Height / length',
    'cm',
    20.0,
    250.0,
    'A value this small usually means metres were entered instead of '
        'centimetres. Re-measure with the board.',
  ),
  muacCm(
    'MUAC',
    'cm',
    4.0,
    40.0,
    'A value this large usually means millimetres were entered instead of '
        'centimetres. Re-wrap the tape at the mid-upper arm.',
  ),
  temperatureC(
    'Temperature',
    '°C',
    30.0,
    45.0,
    'This reads like Fahrenheit, not Celsius. Re-take with the thermometer '
        'set to °C.',
  ),
  respiratoryRate(
    'Respiratory rate',
    'breaths/min',
    5.0,
    150.0,
    'Count a full 60 seconds again while the child is calm.',
  ),
  heartRate(
    'Heart rate',
    'beats/min',
    20.0,
    300.0,
    'Re-check the pulse for a full 60 seconds.',
  ),
  systolicBp(
    'Systolic blood pressure',
    'mmHg',
    30.0,
    300.0,
    'Re-take the blood pressure after five minutes of rest.',
  ),
  diastolicBp(
    'Diastolic blood pressure',
    'mmHg',
    20.0,
    200.0,
    'Re-take the blood pressure after five minutes of rest.',
  ),
  haemoglobin(
    'Haemoglobin',
    'g/dL',
    2.0,
    25.0,
    'This reads like g/L, not g/dL. Check the meter units and re-test.',
  ),
  oxygenSaturation(
    'Oxygen saturation',
    '%',
    50.0,
    100.0,
    'Warm the hand and re-attach the probe, away from bright light.',
  ),
  gestationalWeeks(
    'Gestational age',
    'weeks',
    4.0,
    45.0,
    'Check the dates against the ANC card and fundal height.',
  );

  const MeasurementKind(this.label, this.unit, this.min, this.max, this.advice);

  final String label;
  final String unit;
  final double min;
  final double max;

  /// What to do when a value falls outside the plausible range.
  final String advice;
}

/// A flagged implausible value. This is a *data-quality* signal, not a
/// clinical finding — it tells the CHO to re-measure, not to treat.
class PlausibilityFlag {
  const PlausibilityFlag({
    required this.kind,
    required this.value,
    required this.problem,
    required this.advice,
  });

  final MeasurementKind kind;
  final double value;

  /// What is wrong in one line, e.g. "above the plausible range (20–250 cm)".
  final String problem;

  final String advice;

  /// Expressed as a data-quality clinical finding so it can ride along in the
  /// same results stream, clearly labelled as a measurement concern.
  ClinicalFinding toFinding() => ClinicalFinding(
    label: 'Check the ${kind.label.toLowerCase()} reading',
    detail: '${kind.label} of $value ${kind.unit} is $problem. '
        '$advice Do not act on this value until it is confirmed.',
    severity: TriageLevel.watch,
    protocolSource: 'CareBridge measurement-quality screen',
    measuredValue: '$value ${kind.unit}',
    threshold: 'plausible ${kind.min}–${kind.max} ${kind.unit}',
  );
}

abstract final class MeasurementSafetyEngine {
  /// Checks a single value against its plausible range. Returns `null` when
  /// the value is plausible (or absent — `null` inputs are skipped, because
  /// *missing* data is handled by the engines' uncertainty logic, not here).
  static PlausibilityFlag? check(MeasurementKind kind, double? value) {
    if (value == null) return null;
    if (value < kind.min) {
      return PlausibilityFlag(
        kind: kind,
        value: value,
        problem: 'below the plausible range '
            '(${_fmt(kind.min)}–${_fmt(kind.max)} ${kind.unit})',
        advice: kind.advice,
      );
    }
    if (value > kind.max) {
      return PlausibilityFlag(
        kind: kind,
        value: value,
        problem: 'above the plausible range '
            '(${_fmt(kind.min)}–${_fmt(kind.max)} ${kind.unit})',
        advice: kind.advice,
      );
    }
    return null;
  }

  /// Checks a batch of measurements, returning every implausible one.
  static List<PlausibilityFlag> checkAll(
    Map<MeasurementKind, double?> values,
  ) {
    final flags = <PlausibilityFlag>[];
    for (final entry in values.entries) {
      final flag = check(entry.key, entry.value);
      if (flag != null) flags.add(flag);
    }
    return flags;
  }

  /// A relational check the per-value screen cannot do: diastolic pressure
  /// must be lower than systolic. When it is not, the two were almost
  /// certainly transposed or misread.
  static PlausibilityFlag? checkBloodPressure({
    required double? systolic,
    required double? diastolic,
  }) {
    if (systolic == null || diastolic == null) return null;
    if (diastolic >= systolic) {
      return PlausibilityFlag(
        kind: MeasurementKind.diastolicBp,
        value: diastolic,
        problem: 'not lower than the systolic reading ($systolic mmHg) — '
            'the two values look swapped or misread',
        advice: 'Re-take the blood pressure and record systolic over '
            'diastolic.',
      );
    }
    return null;
  }

  /// Convenience: run the full screen over a typical child-assessment set and
  /// return the findings ready to append to the results stream.
  static List<ClinicalFinding> screenFindings(
    Map<MeasurementKind, double?> values, {
    double? systolic,
    double? diastolic,
  }) {
    final flags = checkAll(values);
    final bp = checkBloodPressure(systolic: systolic, diastolic: diastolic);
    if (bp != null) flags.add(bp);
    return flags.map((f) => f.toFinding()).toList();
  }

  static String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toString();
}
