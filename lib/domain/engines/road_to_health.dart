/// The **Road to Health** reading: every weighing this child has, placed on the
/// WHO weight-for-age standard, in the order a CHPS card draws them.
///
/// Ghana's Road to Health card is the most trusted piece of paper in the
/// district. A mother keeps it, a supervisor can audit it, and its meaning is
/// visual before it is numerical: the line should climb through the green zone,
/// and the moment it flattens or slips down across a line, somebody acts. This
/// engine is that card — the same three zones, the same direction of travel —
/// computed from the measurements already in the local database instead of
/// trusting that the paper one was brought today.
///
/// ## What it is, and what it is not
///
/// It is a **position on a published standard**, not a diagnosis. Weight-for-age
/// is a composite: a child below the −2 line may be thin, or short, or both, and
/// this table cannot tell them apart. So the reading never stands alone — the
/// MUAC tape (which needs no scales and no date of birth) and the
/// weight-for-height z-score in `GrowthZScoreEngine` (which separates wasting
/// from stunting) both stay in the assessment, and the card says so.
///
/// It is also not a forecast. `TrajectoryEngine` owns the rate of fall and the
/// projection toward SAM; this file only reports where each weighing sits and
/// whether the last step moved the child down across a line.
///
/// ## Refusal is a first-class result
///
/// A weight-for-age position needs three things: a weight, a date of birth, and
/// an age inside the 0–60 months WHO publishes. When any is missing this engine
/// says which, and the chart declines to draw rather than inventing an axis. A
/// guessed date of birth is how a healthy child ends up on a referral list.
library;

import '../../data/reference/weight_for_age_reference.dart';
import '../entities/core.dart';
import '../enums.dart';

/// Where a weighing sits against the WHO standard, in the zones a CHPS worker
/// reads off the card.
enum RoadToHealthZone {
  /// Below −3 SD. On the card, the red band.
  red('Below −3 SD', 'Severe underweight for age.'),

  /// −3 to −2 SD. The yellow band.
  yellow('−3 to −2 SD', 'Underweight for age.'),

  /// −2 to +2 SD. The green band, where the track is meant to run.
  green('−2 to +2 SD', 'Within the standard band for this age.'),

  /// Above +2 SD. Not an emergency, and not a pass either: worth a look at
  /// feeding if it persists.
  high('Above +2 SD', 'Above the standard band for this age.');

  const RoadToHealthZone(this.label, this.meaning);

  /// The band name as it appears on the card.
  final String label;

  /// What crossing into it means, in one line.
  final String meaning;

  /// How far down the card this sits. `high` is not worse than `green`, so
  /// both rank above the yellow band.
  int get rank => switch (this) {
    RoadToHealthZone.red => 3,
    RoadToHealthZone.yellow => 2,
    RoadToHealthZone.green || RoadToHealthZone.high => 1,
  };
}

/// Why a chart could not be drawn, in the words a worker needs.
enum RoadToHealthGap {
  noDateOfBirth(
    'Date of birth not recorded',
    'A growth chart is drawn against age, so it needs a date of birth. Add one '
        'and the chart will appear.',
  ),
  noWeighings(
    'No weights recorded',
    'Nothing recorded for this child includes a weight, so there is no '
        'weight-for-age to plot. Weigh the child to start the track.',
  ),
  nothingRecorded(
    'No measurements recorded',
    'This child has no growth measurements saved on this phone yet.',
  ),
  pastTheStandard(
    'Past the end of the standard',
    'The WHO weight-for-age standard runs to 60 months. This child is older, so '
        'the card stops — height-for-age and MUAC carry on past it.',
  );

  const RoadToHealthGap(this.label, this.detail);
  final String label;
  final String detail;
}

/// One weighing, placed.
class RoadToHealthPoint {
  const RoadToHealthPoint({
    required this.takenAt,
    required this.ageMonths,
    required this.weightKg,
    required this.z,
    required this.zone,
  });

  final DateTime takenAt;

  /// Exact age at the weighing, in months to one decimal, from the recorded
  /// date of birth — not the age as written on the card.
  final double ageMonths;

  final double weightKg;

  /// Standard deviations from the WHO median for this age and sex.
  final double z;

  final RoadToHealthZone zone;
}

/// Every weighing this child has, read against the standard.
class RoadToHealthReading {
  const RoadToHealthReading({
    required this.sex,
    required this.points,
    this.gap,
    this.unweighedVisits = 0,
    this.offStandardVisits = 0,
    this.movedDown = false,
    this.explanation = '',
  });

  final Sex sex;

  /// Chronological, and only the weighings that could be placed.
  final List<RoadToHealthPoint> points;

  /// Set when the chart must decline. Null when it can draw.
  final RoadToHealthGap? gap;

  /// Visits with a measurement but no weight on it. A track that quietly
  /// drops these reads as a child who was not growing between them.
  final int unweighedVisits;

  /// Weighings taken past 60 months, which the standard does not cover.
  final int offStandardVisits;

  /// True when the last step down the card crossed into a worse band. This is
  /// the observation the paper chart exists to provoke.
  final bool movedDown;

  /// The arithmetic in words, so it can be checked against the card.
  final String explanation;

  bool get canPlot => gap == null && points.isNotEmpty;

  RoadToHealthZone? get zone => points.isEmpty ? null : points.last.zone;

  RoadToHealthPoint? get last => points.isEmpty ? null : points.last;
}

abstract final class RoadToHealth {
  /// A month is 30.4375 days: 365.25 / 12. Exact-enough fractional ages keep a
  /// two-week-old off the 1-month line rather than guessing a whole month.
  static const double _daysPerMonth = 30.4375;

  /// [measurements] may arrive in any order; they are sorted here.
  static RoadToHealthReading read({
    required Sex sex,
    required DateTime? dateOfBirth,
    required List<GrowthMeasurement> measurements,
  }) {
    if (measurements.isEmpty) {
      return RoadToHealthReading(
        sex: sex,
        points: const [],
        gap: RoadToHealthGap.nothingRecorded,
      );
    }
    if (dateOfBirth == null) {
      return RoadToHealthReading(
        sex: sex,
        points: const [],
        gap: RoadToHealthGap.noDateOfBirth,
        unweighedVisits: _withoutWeight(measurements),
      );
    }

    final born = dateOfBirth;
    final ordered = [...measurements]
      ..sort((a, b) => a.takenAt.compareTo(b.takenAt));

    final points = <RoadToHealthPoint>[];
    var unweighed = 0;
    var offStandard = 0;
    for (final m in ordered) {
      final weight = m.weightKg;
      if (weight == null || weight <= 0) {
        unweighed++;
        continue;
      }
      final ageMonths = m.takenAt.difference(born).inDays / _daysPerMonth;
      final z = WeightForAgeReference.zScore(
        sex: sex,
        ageMonths: ageMonths,
        weightKg: weight,
      );
      if (z == null) {
        // Either before birth or past 60 months; the table refuses both, and
        // the count is what the card reports instead of a dot.
        if (ageMonths > WeightForAgeReference.maxAgeMonths) offStandard++;
        continue;
      }
      points.add(
        RoadToHealthPoint(
          takenAt: m.takenAt,
          ageMonths: ageMonths,
          weightKg: weight,
          z: z,
          zone: _zoneOf(z),
        ),
      );
    }

    if (points.isEmpty) {
      return RoadToHealthReading(
        sex: sex,
        points: const [],
        gap: unweighed > 0
            ? RoadToHealthGap.noWeighings
            : RoadToHealthGap.pastTheStandard,
        unweighedVisits: unweighed,
        offStandardVisits: offStandard,
      );
    }

    var movedDown = false;
    if (points.length >= 2) {
      final prev = points[points.length - 2];
      final last = points[points.length - 1];
      movedDown = last.zone.rank > prev.zone.rank;
    }

    return RoadToHealthReading(
      sex: sex,
      points: points,
      unweighedVisits: unweighed,
      offStandardVisits: offStandard,
      movedDown: movedDown,
      explanation: _explain(sex, points, movedDown, unweighed, offStandard),
    );
  }

  static RoadToHealthZone _zoneOf(double z) {
    if (z < -3) return RoadToHealthZone.red;
    if (z < -2) return RoadToHealthZone.yellow;
    if (z > 2) return RoadToHealthZone.high;
    return RoadToHealthZone.green;
  }

  /// A z-score to one decimal, in the one form every surface here prints.
  /// Rounding the WHO median weight exactly produces "-0.0", which reads as a
  /// fall that has not happened.
  static String zText(double z) {
    final s = z.toStringAsFixed(1);
    return s == '-0.0' ? '0.0' : s;
  }

  static int _withoutWeight(List<GrowthMeasurement> ms) =>
      ms.where((m) => (m.weightKg ?? 0) <= 0).length;

  static String _explain(
    Sex sex,
    List<RoadToHealthPoint> points,
    bool movedDown,
    int unweighed,
    int offStandard,
  ) {
    final last = points.last;
    final median = WeightForAgeReference.weightAt(sex, last.ageMonths, 0);
    final buffer = StringBuffer()
      ..write(
        'At ${last.ageMonths.toStringAsFixed(1)} months this child weighed '
        '${last.weightKg.toStringAsFixed(1)} kg against a WHO median of '
        '${median == null ? '—' : '${median.toStringAsFixed(1)} kg'} for a '
        '${sex == Sex.male ? 'boy' : 'girl'} of that age — '
        '${zText(last.z)} SD, which is '
        '${last.zone.meaning.toLowerCase()}',
      );
    if (movedDown) {
      final prev = points[points.length - 2];
      buffer.write(
        '. The track has crossed down from ${prev.zone.label} since '
        '${prev.ageMonths.toStringAsFixed(1)} months',
      );
    }
    if (points.length == 1) {
      buffer.write(
        '. One weighing gives a position, never a direction — the next one is '
        'what turns this into a trend',
      );
    }
    final omitted = <String>[
      if (unweighed > 0)
        '$unweighed visit${unweighed == 1 ? '' : 's'} had no weight recorded',
      if (offStandard > 0)
        '$offStandard weighing${offStandard == 1 ? '' : 's'} fell past the '
            '60-month end of the standard',
    ];
    if (omitted.isNotEmpty) {
      buffer.write(
        '. Left out of the plot: ${omitted.join(' and ')} — weight-for-age '
        'cannot be placed without a weight and an age inside the standard',
      );
    }
    return '${buffer.toString()}.';
  }
}
