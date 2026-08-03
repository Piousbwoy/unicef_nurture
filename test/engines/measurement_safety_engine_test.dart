/// Measurement-safety engine: implausible-value screening.
///
/// Pins the guarantee that a misrecorded number (wrong unit, transposed
/// decimal, device error) is caught and labelled as a data problem *before*
/// it can drive a confident-but-wrong clinical recommendation — and that a
/// true value is never flagged.
library;

import 'package:carebridge_ai/domain/engines/measurement_safety_engine.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MeasurementSafetyEngine', () {
    test('plausible values pass unflagged', () {
      expect(MeasurementSafetyEngine.check(MeasurementKind.weightKg, 12.5), isNull);
      expect(MeasurementSafetyEngine.check(MeasurementKind.heightCm, 85), isNull);
      expect(MeasurementSafetyEngine.check(MeasurementKind.muacCm, 13.2), isNull);
      expect(MeasurementSafetyEngine.check(MeasurementKind.temperatureC, 37.4), isNull);
      expect(MeasurementSafetyEngine.check(MeasurementKind.haemoglobin, 11.0), isNull);
    });

    test('absent values are skipped, not flagged', () {
      expect(MeasurementSafetyEngine.check(MeasurementKind.weightKg, null), isNull);
    });

    test('a Fahrenheit temperature is caught', () {
      final flag = MeasurementSafetyEngine.check(
        MeasurementKind.temperatureC,
        98.6,
      );

      expect(flag, isNotNull);
      expect(flag!.kind, MeasurementKind.temperatureC);
      expect(flag.advice, contains('°C'));
    });

    test('a MUAC recorded in millimetres is caught', () {
      final flag = MeasurementSafetyEngine.check(MeasurementKind.muacCm, 115);

      expect(flag, isNotNull);
      expect(flag!.advice, contains('millimetres'));
    });

    test('a height recorded in metres is caught', () {
      final flag = MeasurementSafetyEngine.check(MeasurementKind.heightCm, 0.85);

      expect(flag, isNotNull);
      expect(flag!.advice, contains('metres'));
    });

    test('a haemoglobin recorded in g/L is caught', () {
      final flag = MeasurementSafetyEngine.check(MeasurementKind.haemoglobin, 120);

      expect(flag, isNotNull);
      expect(flag!.advice, contains('g/dL'));
    });

    test('checkAll returns only the implausible values', () {
      final flags = MeasurementSafetyEngine.checkAll(const {
        MeasurementKind.weightKg: 12.5, // fine
        MeasurementKind.temperatureC: 98.6, // Fahrenheit
        MeasurementKind.muacCm: 115, // millimetres
        MeasurementKind.heightCm: 85, // fine
      });

      expect(flags, hasLength(2));
      expect(
        flags.map((f) => f.kind).toSet(),
        {MeasurementKind.temperatureC, MeasurementKind.muacCm},
      );
    });

    test('a normal blood pressure passes the relational check', () {
      expect(
        MeasurementSafetyEngine.checkBloodPressure(systolic: 110, diastolic: 70),
        isNull,
      );
    });

    test('a swapped blood pressure is caught', () {
      final flag = MeasurementSafetyEngine.checkBloodPressure(
        systolic: 70,
        diastolic: 110,
      );

      expect(flag, isNotNull);
      expect(flag!.problem, contains('swapped'));
    });

    test('flags surface as data-quality findings, never a diagnosis', () {
      final findings = MeasurementSafetyEngine.screenFindings(
        const {MeasurementKind.temperatureC: 98.6},
        systolic: 110,
        diastolic: 70,
      );

      expect(findings, hasLength(1));
      expect(findings.first.severity, TriageLevel.watch);
      expect(findings.first.label, contains('Check'));
      expect(findings.first.detail, contains('Do not act on this value'));
    });
  });
}
