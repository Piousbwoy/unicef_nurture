/// The Road-to-Health reading: WHO weight-for-age, placed and refused.
///
/// Two things are pinned here, and both matter more than the picture. First,
/// the numbers: every curve this app draws must land on the weight the WHO
/// itself publishes for that month and that standard deviation, because a band
/// boundary moved by hand is a child mislabelled. Second, the refusals: a child
/// with no date of birth, no weights, or past the 60-month end of the standard
/// must produce a sentence explaining the gap, never a chart that quietly
/// implies "nothing wrong here".
library;

import 'package:carebridge_ai/data/reference/weight_for_age_reference.dart';
import 'package:carebridge_ai/domain/engines/road_to_health.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

/// The WHO's own published weight (kg) at each SD line, read straight out of
/// the two `wfa_*_0-to-5-years_zscores.xlsx` workbooks whose LMS columns are
/// bundled in `weight_for_age_reference.dart`.
/// (month, −3 SD, −2 SD, median, +2 SD, +3 SD.)
const _whoPublished = <Sex, List<List<double>>>{
  Sex.male: [
    [0, 2.1, 2.5, 3.3, 4.4, 5.0],
    [2, 3.8, 4.3, 5.6, 7.1, 8.0],
    [6, 5.7, 6.4, 7.9, 9.8, 10.9],
    [12, 6.9, 7.7, 9.6, 12.0, 13.3],
    [18, 7.8, 8.8, 10.9, 13.7, 15.3],
    [24, 8.6, 9.7, 12.2, 15.3, 17.1],
    [36, 10.0, 11.3, 14.3, 18.3, 20.7],
    [48, 11.2, 12.7, 16.3, 21.2, 24.2],
    [60, 12.4, 14.1, 18.3, 24.2, 27.9],
  ],
  Sex.female: [
    [0, 2.0, 2.4, 3.2, 4.2, 4.8],
    [2, 3.4, 3.9, 5.1, 6.6, 7.5],
    [6, 5.1, 5.7, 7.3, 9.3, 10.6],
    [12, 6.3, 7.0, 8.9, 11.5, 13.1],
    [18, 7.2, 8.1, 10.2, 13.2, 15.1],
    [24, 8.1, 9.0, 11.5, 14.8, 17.0],
    [36, 9.6, 10.8, 13.9, 18.1, 20.9],
    [48, 10.9, 12.3, 16.1, 21.5, 25.2],
    [60, 12.1, 13.7, 18.2, 24.9, 29.5],
  ],
};

const _sdLines = [-3.0, -2.0, 0.0, 2.0, 3.0];

GrowthMeasurement _weighing({
  required String id,
  required DateTime at,
  double? weightKg,
  int? muacMm,
}) => GrowthMeasurement(
  id: id,
  personId: 'p-1',
  takenAt: at,
  weightKg: weightKg,
  muacMm: muacMm,
  muacCm: muacMm == null ? null : muacMm / 10,
);

/// A date [months] of age after [dob], in whole days — which is how the engine
/// sees age, since it converts days back to months itself.
DateTime _at(DateTime dob, double months) =>
    dob.add(Duration(days: (months * 30.4375).round()));

void main() {
  group('WeightForAgeReference', () {
    test('every curve lands on the weight the WHO publishes', () {
      // WHO prints these to 0.1 kg, so agreement inside half of that rounding
      // step is exact agreement for anything a card can show.
      _whoPublished.forEach((sex, rows) {
        for (final row in rows) {
          final month = row.first;
          for (var i = 0; i < _sdLines.length; i++) {
            final published = row[1 + i];
            final computed = WeightForAgeReference.weightAt(
              sex,
              month,
              _sdLines[i],
            );
            expect(
              computed,
              isNotNull,
              reason: '$sex at $month months, z ${_sdLines[i]}',
            );
            expect(
              computed!,
              closeTo(published, 0.05),
              reason:
                  '$sex at $month months, z ${_sdLines[i]}: the WHO prints '
                  '$published kg, the curve gives '
                  '${computed.toStringAsFixed(2)} kg',
            );
          }
        }
      });
    });

    test('the forward direction agrees with the same published line', () {
      // The WHO's 12-month boys −2 SD weight is 7.7 kg, so 7.7 kg must score
      // at −2 SD rather than at any neighbouring band.
      final z = WeightForAgeReference.zScore(
        sex: Sex.male,
        ageMonths: 12,
        weightKg: 7.7,
      );
      expect(z, isNotNull);
      expect(z!, closeTo(-2.0, 0.05));
    });

    test('nothing is extrapolated past the end of the standard', () {
      expect(WeightForAgeReference.covers(60), isTrue);
      expect(WeightForAgeReference.covers(60.1), isFalse);
      expect(WeightForAgeReference.covers(-0.1), isFalse);
      expect(
        WeightForAgeReference.lmsAt(Sex.male, 72),
        isNull,
        reason: 'a six-year-old is outside the weight-for-age standard',
      );
      expect(WeightForAgeReference.weightAt(Sex.female, 61, 0), isNull);
      expect(
        WeightForAgeReference.zScore(
          sex: Sex.male,
          ageMonths: 66,
          weightKg: 20,
        ),
        isNull,
      );
    });

    test('a weight that cannot mean anything is refused, not scored', () {
      for (final w in [0.0, -3.0]) {
        expect(
          WeightForAgeReference.zScore(
            sex: Sex.male,
            ageMonths: 12,
            weightKg: w,
          ),
          isNull,
          reason: '$w kg is not a weighing',
        );
      }
    });

    test('between tabulated months the median moves between the two', () {
      final lo = WeightForAgeReference.weightAt(Sex.male, 12, 0)!;
      final mid = WeightForAgeReference.weightAt(Sex.male, 12.5, 0)!;
      final hi = WeightForAgeReference.weightAt(Sex.male, 13, 0)!;
      expect(mid, greaterThan(lo));
      expect(mid, lessThan(hi));
    });
  });

  group('RoadToHealth.read', () {
    final dob = DateTime(2025, 1, 1);

    test('a weighing is placed by exact age at the weighing', () {
      // Boys at ~14 months, 8.0 kg, against the WHO median of ~10.1 kg: a
      // little under the −2 line.
      final reading = RoadToHealth.read(
        sex: Sex.male,
        dateOfBirth: dob,
        measurements: [_weighing(id: 'g1', at: _at(dob, 14), weightKg: 8.0)],
      );

      expect(reading.canPlot, isTrue);
      expect(reading.points, hasLength(1));
      expect(reading.points.single.ageMonths, closeTo(14, 0.05));
      expect(reading.points.single.z, closeTo(-2.11, 0.05));
      expect(reading.zone, RoadToHealthZone.yellow);
      expect(
        reading.explanation,
        allOf(
          contains('8.0 kg'),
          contains('10.1 kg'),
          contains('boy'),
          contains('-2.1 SD'),
        ),
        reason: 'the median it was compared against is part of the sentence',
      );
    });

    test('a child on the published −2 line is still on the standard', () {
      // Boys 24 months: WHO prints 9.7 kg at −2 SD, and the unfitted curve
      // resolves that to −1.98 SD. A child standing on a line is read as on it,
      // not under it.
      final reading = RoadToHealth.read(
        sex: Sex.male,
        dateOfBirth: dob,
        measurements: [_weighing(id: 'g1', at: _at(dob, 24), weightKg: 9.7)],
      );
      expect(reading.points.single.z, greaterThanOrEqualTo(-2));
      expect(reading.zone, RoadToHealthZone.green);
    });

    test('below −3 SD is the red band', () {
      final reading = RoadToHealth.read(
        sex: Sex.male,
        dateOfBirth: dob,
        measurements: [_weighing(id: 'g1', at: _at(dob, 24), weightKg: 8.6)],
      );
      expect(reading.points.single.z, lessThan(-3));
      expect(reading.zone, RoadToHealthZone.red);
    });

    test(
      'the boy and girl standards differ, and the chart follows the child',
      () {
        // 6.8 kg at 12 months: the WHO prints 6.9 kg as the boys' −3 line, so a
        // boy at 6.8 kg is below it (−3.2 SD, red). The girls' −3 line sits at
        // 6.3 kg, so the same child-weight pair reads −2.3 SD, yellow. Same
        // number on the scale, two different readings — which is why the sex has
        // to reach the reference table.
        final girl = RoadToHealth.read(
          sex: Sex.female,
          dateOfBirth: dob,
          measurements: [_weighing(id: 'g1', at: _at(dob, 12), weightKg: 6.8)],
        );
        final boy = RoadToHealth.read(
          sex: Sex.male,
          dateOfBirth: dob,
          measurements: [_weighing(id: 'g1', at: _at(dob, 12), weightKg: 6.8)],
        );

        expect(girl.zone, RoadToHealthZone.yellow);
        expect(boy.zone, RoadToHealthZone.red);
        expect(girl.points.single.z, greaterThan(boy.points.single.z));
      },
    );

    test('crossing down into a worse band is reported', () {
      final falling = RoadToHealth.read(
        sex: Sex.male,
        dateOfBirth: dob,
        measurements: [
          _weighing(id: 'g1', at: _at(dob, 14), weightKg: 10.0),
          _weighing(id: 'g2', at: _at(dob, 20), weightKg: 8.0),
        ],
      );
      expect(falling.zone, RoadToHealthZone.red);
      expect(falling.movedDown, isTrue);
      expect(falling.explanation, contains('crossed down'));

      final climbing = RoadToHealth.read(
        sex: Sex.male,
        dateOfBirth: dob,
        measurements: [
          _weighing(id: 'g1', at: _at(dob, 14), weightKg: 8.0),
          _weighing(id: 'g2', at: _at(dob, 20), weightKg: 10.0),
        ],
      );
      expect(climbing.zone, RoadToHealthZone.green);
      expect(climbing.movedDown, isFalse);

      final steady = RoadToHealth.read(
        sex: Sex.male,
        dateOfBirth: dob,
        measurements: [
          _weighing(id: 'g1', at: _at(dob, 14), weightKg: 10.0),
          _weighing(id: 'g2', at: _at(dob, 20), weightKg: 10.2),
        ],
      );
      expect(steady.zone, RoadToHealthZone.green);
      expect(
        steady.movedDown,
        isFalse,
        reason: 'same band twice is not a fall',
      );
    });

    test('a visit with no weight is named, not silently dropped', () {
      // A MUAC-only contact is the common case in a CHPS session. If it simply
      // vanished from the series, the line would read as a child who was not
      // growing between the two weighings.
      final reading = RoadToHealth.read(
        sex: Sex.female,
        dateOfBirth: dob,
        measurements: [
          _weighing(id: 'g1', at: _at(dob, 10), weightKg: 8.4),
          _weighing(id: 'g2', at: _at(dob, 13), muacMm: 132),
          _weighing(id: 'g3', at: _at(dob, 16), weightKg: 8.6),
        ],
      );

      expect(reading.points, hasLength(2));
      expect(reading.unweighedVisits, 1);
      expect(reading.explanation, contains('1 visit had no weight recorded'));
    });

    test('no date of birth declines, and says why', () {
      final reading = RoadToHealth.read(
        sex: Sex.male,
        dateOfBirth: null,
        measurements: [_weighing(id: 'g1', at: dob, weightKg: 9.0)],
      );
      expect(reading.canPlot, isFalse);
      expect(reading.gap, RoadToHealthGap.noDateOfBirth);
      expect(reading.gap!.detail, contains('date of birth'));
      expect(reading.points, isEmpty);
    });

    test('no weights at all declines as no weighings', () {
      final reading = RoadToHealth.read(
        sex: Sex.male,
        dateOfBirth: dob,
        measurements: [_weighing(id: 'g1', at: _at(dob, 8), muacMm: 140)],
      );
      expect(reading.gap, RoadToHealthGap.noWeighings);
      expect(reading.unweighedVisits, 1);
    });

    test('past the end of the standard declines rather than extrapolating', () {
      final reading = RoadToHealth.read(
        sex: Sex.male,
        dateOfBirth: dob,
        measurements: [_weighing(id: 'g1', at: _at(dob, 74), weightKg: 21.0)],
      );
      expect(reading.canPlot, isFalse);
      expect(reading.gap, RoadToHealthGap.pastTheStandard);
      expect(reading.offStandardVisits, 1);
      expect(reading.gap!.detail, contains('60 months'));
    });

    test('with nothing recorded there is nothing to invent', () {
      final reading = RoadToHealth.read(
        sex: Sex.female,
        dateOfBirth: dob,
        measurements: const [],
      );
      expect(reading.gap, RoadToHealthGap.nothingRecorded);
      expect(reading.explanation, isEmpty);
    });

    test('input order cannot change the track', () {
      final measurements = [
        _weighing(id: 'g1', at: _at(dob, 20), weightKg: 10.0),
        _weighing(id: 'g2', at: _at(dob, 8), weightKg: 7.6),
        _weighing(id: 'g3', at: _at(dob, 14), weightKg: 8.0),
      ];
      final forwards = RoadToHealth.read(
        sex: Sex.male,
        dateOfBirth: dob,
        measurements: measurements,
      );
      final backwards = RoadToHealth.read(
        sex: Sex.male,
        dateOfBirth: dob,
        measurements: measurements.reversed.toList(),
      );

      final oldestFirst = measurements.map((m) => m.takenAt).toList()..sort();

      expect(
        backwards.points.map((p) => p.takenAt).toList(),
        forwards.points.map((p) => p.takenAt).toList(),
      );
      expect(
        forwards.points.map((p) => p.takenAt).toList(),
        oldestFirst,
        reason: 'the track runs oldest to newest whatever order it arrived in',
      );
      expect(
        forwards.points.map((p) => p.weightKg).toList(),
        const [7.6, 8.0, 10.0],
        reason: 'a line drawn out of order would slope the wrong way',
      );
      expect(forwards.movedDown, isFalse);
    });

    test('one weighing gives a position, never a direction', () {
      final reading = RoadToHealth.read(
        sex: Sex.male,
        dateOfBirth: dob,
        measurements: [_weighing(id: 'g1', at: _at(dob, 20), weightKg: 11.0)],
      );
      expect(reading.movedDown, isFalse);
      expect(reading.explanation, contains('never a direction'));
    });
  });
}
