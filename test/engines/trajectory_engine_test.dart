/// Trajectory engine: the slope is the finding, not the last point.
///
/// This is the "predict risk before crisis" challenge — a child whose MUAC is
/// 12.4, 12.1, 11.8 is green on every single reading and still heading for
/// SAM. These tests pin that the engine sees it.
library;

import 'package:carebridge_ai/domain/engines/trajectory_engine.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:flutter_test/flutter_test.dart';

GrowthMeasurement _m(int day, double muac, {double? weight}) => GrowthMeasurement(
  id: 'g$day',
  personId: 'child-1',
  takenAt: DateTime(2026, 1, 1).add(Duration(days: day)),
  muacCm: muac,
  weightKg: weight,
);

void main() {
  group('TrajectoryEngine', () {
    test('no measurements means insufficient data, not "fine"', () {
      final result = TrajectoryEngine.analyse(const []);

      expect(result.trend, GrowthTrend.insufficientData);
      expect(result.findings, isNotEmpty);
    });

    test('a single reading cannot show a direction', () {
      final result = TrajectoryEngine.analyse([_m(0, 12.5)]);

      expect(result.trend, GrowthTrend.insufficientData);
      expect(result.pointsUsed, 1);
    });

    test('a falling MUAC is detected even while every reading looks acceptable', () {
      final result = TrajectoryEngine.analyse([
        _m(0, 12.6),
        _m(30, 12.2),
        _m(60, 11.9),
      ]);

      expect(result.trend, GrowthTrend.falling);
      expect(result.muacChangePerMonth, isNotNull);
      expect(result.muacChangePerMonth!, lessThan(0));
      expect(result.daysToSamThreshold, isNotNull);
      expect(result.daysToSamThreshold!, greaterThan(0));
    });

    test('a rising MUAC is growing', () {
      final result = TrajectoryEngine.analyse([
        _m(0, 11.8),
        _m(35, 12.3),
        _m(70, 12.7),
      ]);

      expect(result.trend, GrowthTrend.rising);
      expect(result.muacChangePerMonth!, greaterThan(0));
      expect(result.daysToSamThreshold, isNull);
    });

    test('measurements given out of order are still read chronologically', () {
      final result = TrajectoryEngine.analyse([
        _m(60, 11.9),
        _m(0, 12.6),
        _m(30, 12.2),
      ]);

      expect(result.trend, GrowthTrend.falling);
      expect(result.pointsUsed, 3);
    });

    test('the explanation shows the arithmetic in words', () {
      final result = TrajectoryEngine.analyse([
        _m(0, 12.6),
        _m(30, 12.2),
        _m(60, 11.9),
      ]);

      expect(result.explanation, isNotEmpty);
    });

    test('a child already below the SAM line is flagged immediately', () {
      final result = TrajectoryEngine.analyse([
        _m(0, 11.6),
        _m(30, 11.2),
      ]);

      expect(result.trend, GrowthTrend.falling);
      // Already below 11.5: the projection is "now", not a future date.
      expect(
        result.findings.any((f) => f.severity.isAtLeastPriority),
        isTrue,
      );
    });
  });
}
