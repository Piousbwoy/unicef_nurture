// Guards the de-identification contract of the recalibration export.
//
// The Kintampo/Navrongo pathway only works if a record carried off a phone
// can never identify a family. These tests pin the two failure modes that
// would break that promise: an identifier key leaking into the JSON, and a
// personKey that stops being a one-way, salt-held pseudonym.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:carebridge_ai/core/ml/recalibration_export.dart';

/// Keys that must never appear anywhere in an export record. Any addition
/// to the schema must be checked against this list.
const _bannedKeys = {
  'name',
  'fullName',
  'phone',
  'phoneNumber',
  'personId',
  'householdId',
  'community',
  'gps',
  'latitude',
  'longitude',
  'dateOfBirth',
  'createdAt',
  'userId',
};

RecalibrationRecord _sample() => RecalibrationRecord.build(
      modelName: 'neonatal_sepsis',
      modelVersion: 'v1.0-ghana-baseline',
      district: 'Savelugu',
      clientType: 'newborn',
      ageDays: 12,
      createdAt: DateTime(2026, 8, 3, 14, 22),
      features: const {
        'age_days': 0.19,
        'temperature_celsius': 0.55,
        'history_of_convulsions': 0,
        'feeding_difficulty': 1,
      },
      predictedProbability: 0.031,
      predictedTier: 'moderate',
      engineTriage: 'urgent',
      finalTriage: 'urgent',
      referralIssued: true,
      referralUrgency: 'today',
      personId: 'person-7f3a9c-REAL-ID',
      salt: 'ghs-held-salt',
    );

void _collectKeys(Object? node, Set<String> out) {
  if (node is Map) {
    for (final entry in node.entries) {
      out.add(entry.key.toString());
      _collectKeys(entry.value, out);
    }
  } else if (node is List) {
    for (final item in node) {
      _collectKeys(item, out);
    }
  }
}

void main() {
  test('export record contains no identifier keys, nested or otherwise', () {
    final keys = <String>{};
    _collectKeys(_sample().toJson(), keys);
    for (final banned in _bannedKeys) {
      expect(keys.contains(banned), isFalse,
          reason: 'identifier key "$banned" leaked into the export');
    }
  });

  test('export record never contains the raw person id as a value', () {
    final line = _sample().toJsonLine();
    expect(line.contains('person-7f3a9c-REAL-ID'), isFalse);
  });

  test('personKey is deterministic, salt-held and one-way', () {
    final a = RecalibrationRecord.personKeyFor('p-1', 'salt-A');
    final b = RecalibrationRecord.personKeyFor('p-1', 'salt-A');
    final c = RecalibrationRecord.personKeyFor('p-1', 'salt-B');
    expect(a, b, reason: 'same id + same salt must link repeat visits');
    expect(a, isNot(c), reason: 'without the GHS salt the key cannot be computed');
    expect(a, isNot(contains('p-1')));
    expect(a.length, 64, reason: 'hex-encoded SHA-256');
  });

  test('month and age are always coarsened', () {
    expect(RecalibrationRecord.monthOf(DateTime(2026, 8, 3, 23, 59)),
        '2026-08');
    expect(RecalibrationRecord.monthOf(DateTime(2027, 1, 1)), '2027-01');

    expect(RecalibrationRecord.ageBandForDays(null), 'unknown');
    expect(RecalibrationRecord.ageBandForDays(0), '0-6');
    expect(RecalibrationRecord.ageBandForDays(12), '7-27');
    expect(RecalibrationRecord.ageBandForDays(45), '28-59');
    expect(RecalibrationRecord.ageBandForDays(200), '60-364');
    expect(RecalibrationRecord.ageBandForDays(900), '365-1825');
    expect(RecalibrationRecord.ageBandForDays(8000), '1826+');

    // The record never carries the exact age or timestamp it was built from:
    // the only time/place fields are the coarsened ones asserted above.
    final json = _sample().toJson();
    expect(json['ageBand'], '7-27');
    expect(json['createdMonth'], '2026-08');
  });

  test('JSONL round-trips and stays numeric-only in features', () {
    final record = _sample();
    final decoded = jsonDecode(record.toJsonLine()) as Map<String, Object?>;
    expect(decoded['schemaVersion'], 1);
    expect(decoded['modelName'], 'neonatal_sepsis');
    expect(decoded['predictedProbability'], 0.031);
    expect(decoded['referralIssued'], isTrue);
    final features = decoded['features'] as Map<String, Object?>;
    for (final value in features.values) {
      expect(value, isA<num>(),
          reason: 'features must replay the exact numeric inference input');
    }
  });

  test('a drift-suppressed probability exports as null, not a fake zero', () {
    final record = RecalibrationRecord.build(
      modelName: 'preeclampsia_risk',
      modelVersion: null,
      district: 'Yendi',
      clientType: 'mother',
      ageDays: null,
      createdAt: DateTime(2026, 8, 14),
      features: const {'systolic_bp': 0.4},
      predictedProbability: null,
      predictedTier: 'high',
      engineTriage: 'urgent',
      finalTriage: 'routine',
      referralIssued: false,
      referralUrgency: null,
      personId: 'p-2',
      salt: 's',
    );
    final decoded = jsonDecode(record.toJsonLine()) as Map<String, Object?>;
    expect(decoded.containsKey('predictedProbability'), isTrue);
    expect(decoded['predictedProbability'], isNull);
    expect(decoded['modelVersion'], 'unknown');
    expect(decoded['ageBand'], 'unknown');
    // The override gap (engine urgent -> final routine) must survive; it is
    // the most valuable recalibration signal in the cohort.
    expect(decoded['engineTriage'], 'urgent');
    expect(decoded['finalTriage'], 'routine');
  });
}
