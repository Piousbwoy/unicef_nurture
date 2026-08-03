/// Growth **trajectory** analysis — the part a paper card cannot do.
///
/// A weighing card holds the numbers, but nobody computes the slope. So a child
/// whose MUAC goes 13.8 → 13.1 → 12.7 cm over three months gets marked "green,
/// green, yellow" and is sent home twice before anybody worries. By the time a
/// single reading crosses 11.5 cm the child has been falling for a quarter of a
/// year.
///
/// This engine looks at the *direction and speed of travel*, not the latest
/// value, and answers two questions:
///   * Is this child deteriorating, even while still inside a normal band?
///   * If nothing changes, when will they cross into SAM?
///
/// That forecast is the honest, explainable form of "predicting risk before
/// crisis": it is linear extrapolation of measured values, it states its own
/// arithmetic, and it never pretends to more precision than three tape readings
/// can support.
library;

import '../enums.dart';
import '../entities/core.dart';
import '../entities/visit.dart';

enum GrowthTrend {
  falling('Falling', 'Losing ground measurably between visits.'),
  flat('Static', 'Not growing. In a young child, static is not neutral.'),
  rising('Growing', 'Gaining as expected.'),
  insufficientData(
    'Not enough measurements',
    'At least two measurements at least 14 days apart are needed to see a trend.',
  );

  const GrowthTrend(this.label, this.meaning);
  final String label;
  final String meaning;
}

class TrajectoryResult {
  const TrajectoryResult({
    required this.trend,
    required this.pointsUsed,
    this.muacChangePerMonth,
    this.weightChangePerMonth,
    this.daysToSamThreshold,
    this.projectedSamDate,
    this.findings = const [],
    this.explanation = '',
  });

  final GrowthTrend trend;
  final int pointsUsed;

  /// Centimetres per 30 days. Negative means shrinking.
  final double? muacChangePerMonth;

  /// Kilograms per 30 days.
  final double? weightChangePerMonth;

  /// Days until MUAC would reach 11.5 cm at the current rate. Null when the
  /// child is not falling, or is already below the threshold.
  final int? daysToSamThreshold;

  final DateTime? projectedSamDate;

  final List<ClinicalFinding> findings;

  /// The arithmetic, in words, so a CHO can check it against the card.
  final String explanation;

  bool get isDeteriorating =>
      trend == GrowthTrend.falling || trend == GrowthTrend.flat;

  /// The finding that justifies acting before a single reading crosses a cut-off.
  bool get warrantsEarlyAction =>
      trend == GrowthTrend.falling &&
      daysToSamThreshold != null &&
      daysToSamThreshold! <= 90;
}

abstract final class TrajectoryEngine {
  static const double _samMuac = 11.5;

  /// Below this many centimetres lost per month, a fall is treated as noise —
  /// MUAC tapes read to about 0.1 cm and different hands read differently.
  static const double _muacNoiseFloor = 0.15;

  /// [measurements] may be in any order; they are sorted here.
  static TrajectoryResult analyse(List<GrowthMeasurement> measurements) {
    final points = measurements
        .where((m) => m.muacCm != null || m.weightKg != null)
        .toList()
      ..sort((a, b) => a.takenAt.compareTo(b.takenAt));

    if (points.length < 2) {
      return TrajectoryResult(
        trend: GrowthTrend.insufficientData,
        pointsUsed: points.length,
        explanation: points.isEmpty
            ? 'No growth measurements recorded yet. Measure MUAC and weight '
                  'today so there is something to compare against next visit.'
            : 'Only one measurement recorded. A second one, at least two weeks '
                  'from now, will show which way this child is going.',
        findings: const [
          ClinicalFinding(
            label: 'Growth trend cannot be assessed',
            detail:
                'Fewer than two measurements. A single reading tells you where a '
                'child is, never where they are heading.',
            severity: TriageLevel.watch,
            protocolSource: 'CareBridge trajectory analysis',
            weight: 1,
          ),
        ],
      );
    }

    final first = points.first;
    final last = points.last;
    final spanDays = last.takenAt.difference(first.takenAt).inDays;

    if (spanDays < 14) {
      return TrajectoryResult(
        trend: GrowthTrend.insufficientData,
        pointsUsed: points.length,
        explanation:
            'The measurements are only $spanDays days apart. Growth over less '
            'than two weeks is mostly measurement variation, not a trend.',
      );
    }

    final muacRate = _ratePerMonth(points, (m) => m.muacCm);
    final weightRate = _ratePerMonth(points, (m) => m.weightKg);

    final findings = <ClinicalFinding>[];
    final trend = _classifyTrend(muacRate, weightRate);

    int? daysToSam;
    DateTime? projectedDate;

    final latestMuac = points.reversed
        .map((p) => p.muacCm)
        .firstWhere((v) => v != null, orElse: () => null);

    if (muacRate != null &&
        muacRate < -_muacNoiseFloor &&
        latestMuac != null &&
        latestMuac > _samMuac) {
      final cmToLose = latestMuac - _samMuac;
      daysToSam = ((cmToLose / -muacRate) * 30).round();
      projectedDate = last.takenAt.add(Duration(days: daysToSam));
    }

    // ------------------------------------------------------------------
    // Findings — each one states the numbers it came from.
    // ------------------------------------------------------------------
    if (muacRate != null && muacRate < -_muacNoiseFloor) {
      // Already in SAM band: the projection is "now", not a future date. Escalate
      // to urgent so a falling-but-already-below-the-line child cannot be sent
      // home on a "watch" reading.
      final alreadyInSam = latestMuac != null && latestMuac <= _samMuac;
      final severity = alreadyInSam
          ? TriageLevel.urgent
          : daysToSam != null && daysToSam <= 60
              ? TriageLevel.priority
              : TriageLevel.watch;
      findings.add(
        ClinicalFinding(
          label: 'Arm circumference falling',
          detail:
              'MUAC has fallen from ${_fmt(first.muacCm)} cm to '
              '${_fmt(last.muacCm)} cm over $spanDays days — about '
              '${muacRate.abs().toStringAsFixed(2)} cm lost per month. '
              '${daysToSam != null ? 'At this rate the child reaches the 11.5 cm severe cut-off in about $daysToSam days. ' : ''}'
              'Each reading on its own may look acceptable; the direction is not.',
          severity: severity,
          protocolSource: 'CareBridge trajectory analysis',
          measuredValue: '${muacRate.toStringAsFixed(2)} cm/month',
          threshold: 'any sustained fall',
          weight: severity == TriageLevel.priority ? 6 : 3,
        ),
      );
    } else if (muacRate != null && muacRate.abs() <= _muacNoiseFloor) {
      findings.add(
        ClinicalFinding(
          label: 'Arm circumference not increasing',
          detail:
              'MUAC has stayed at about ${_fmt(last.muacCm)} cm over $spanDays '
              'days. A growing child should be gaining. Static is a warning, not '
              'a reassurance.',
          severity: TriageLevel.watch,
          protocolSource: 'CareBridge trajectory analysis',
          measuredValue: '${muacRate.toStringAsFixed(2)} cm/month',
          threshold: 'expected to rise',
          weight: 2,
        ),
      );
    }

    if (weightRate != null && weightRate < -0.1) {
      findings.add(
        ClinicalFinding(
          label: 'Losing weight',
          detail:
              'Weight has fallen from ${_fmt(first.weightKg)} kg to '
              '${_fmt(last.weightKg)} kg over $spanDays days — about '
              '${weightRate.abs().toStringAsFixed(2)} kg per month. Weight loss '
              'in a child under five always needs a reason found.',
          severity: TriageLevel.priority,
          protocolSource: 'CareBridge trajectory analysis',
          measuredValue: '${weightRate.toStringAsFixed(2)} kg/month',
          threshold: 'any loss',
          weight: 6,
        ),
      );
    } else if (weightRate != null && weightRate.abs() <= 0.05) {
      findings.add(
        ClinicalFinding(
          label: 'Weight static — growth faltering',
          detail:
              'Weight has not changed over $spanDays days. Growth faltering '
              'precedes wasting, and it is the earliest point at which this is '
              'cheap to fix.',
          severity: TriageLevel.priority,
          protocolSource: 'WHO growth monitoring',
          measuredValue: '${weightRate.toStringAsFixed(2)} kg/month',
          threshold: 'expected to rise',
          weight: 5,
        ),
      );
    }

    // Oedema appearing between visits is a hard flag regardless of slope.
    if (!first.hasBilateralOedema && last.hasBilateralOedema) {
      findings.add(
        const ClinicalFinding(
          label: 'Oedema has appeared since the last visit',
          detail:
              'Swelling of both feet was not present before and is now. This is '
              'severe acute malnutrition and needs inpatient care today, '
              'whatever the MUAC reads.',
          severity: TriageLevel.urgent,
          protocolSource: 'WHO SAM guidelines',
          weight: 10,
        ),
      );
    }

    return TrajectoryResult(
      trend: trend,
      pointsUsed: points.length,
      muacChangePerMonth: muacRate,
      weightChangePerMonth: weightRate,
      daysToSamThreshold: daysToSam,
      projectedSamDate: projectedDate,
      findings: findings,
      explanation: _explain(
        points.length,
        spanDays,
        muacRate,
        weightRate,
        daysToSam,
      ),
    );
  }

  /// Least-squares slope over the available points, expressed per 30 days.
  ///
  /// Least squares rather than first-to-last, because a single mis-read tape
  /// should not be able to invent or hide a trend on its own.
  static double? _ratePerMonth(
    List<GrowthMeasurement> points,
    double? Function(GrowthMeasurement) pick,
  ) {
    final usable = points.where((p) => pick(p) != null).toList();
    if (usable.length < 2) return null;

    final t0 = usable.first.takenAt;
    final xs = usable
        .map((p) => p.takenAt.difference(t0).inDays.toDouble())
        .toList();
    final ys = usable.map((p) => pick(p)!).toList();

    final n = xs.length;
    final meanX = xs.reduce((a, b) => a + b) / n;
    final meanY = ys.reduce((a, b) => a + b) / n;

    var num = 0.0;
    var den = 0.0;
    for (var k = 0; k < n; k++) {
      num += (xs[k] - meanX) * (ys[k] - meanY);
      den += (xs[k] - meanX) * (xs[k] - meanX);
    }
    if (den == 0) return null;

    return (num / den) * 30; // per day -> per 30 days
  }

  static GrowthTrend _classifyTrend(double? muacRate, double? weightRate) {
    final signals = <double>[
      if (muacRate != null) muacRate / _muacNoiseFloor,
      if (weightRate != null) weightRate / 0.1,
    ];
    if (signals.isEmpty) return GrowthTrend.insufficientData;

    final worst = signals.reduce((a, b) => a < b ? a : b);
    if (worst < -1) return GrowthTrend.falling;
    if (worst <= 1) return GrowthTrend.flat;
    return GrowthTrend.rising;
  }

  static String _explain(
    int points,
    int spanDays,
    double? muacRate,
    double? weightRate,
    int? daysToSam,
  ) {
    final parts = <String>[
      'Based on $points measurements over $spanDays days.',
      if (muacRate != null)
        'MUAC is changing by ${muacRate.toStringAsFixed(2)} cm per month.',
      if (weightRate != null)
        'Weight is changing by ${weightRate.toStringAsFixed(2)} kg per month.',
      if (daysToSam != null)
        'Continuing at exactly this rate, MUAC would reach 11.5 cm in about '
            '$daysToSam days. This is a straight-line projection from the '
            'measurements above, not a prediction of what will happen — it is '
            'there to show how little time there is to act.',
    ];
    return parts.join(' ');
  }

  static String _fmt(double? v) => v == null ? '—' : v.toStringAsFixed(1);
}
