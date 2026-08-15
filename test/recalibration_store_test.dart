// Guards the on-device half of the Kintampo/Navrongo pathway.
//
// The agreement only holds if two properties never regress: an unarmed
// device (no GHS salt) collects absolutely nothing, and the batch that
// leaves the phone is exactly the JSONL the records were written as.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:carebridge_ai/core/ml/recalibration_export.dart';
import 'package:carebridge_ai/core/ml/recalibration_store.dart';

RecalibrationRecord _record(String personId) => RecalibrationRecord.build(
      modelName: 'neonatal_sepsis',
      modelVersion: 'v1.0-ghana-priors',
      district: 'Savelugu',
      clientType: 'newborn',
      ageDays: 14,
      createdAt: DateTime(2026, 8, 3, 10, 30),
      features: const {'temperature_celsius': 38.2, 'feeding_difficulty': 1},
      predictedProbability: 0.21,
      predictedTier: 'moderate',
      engineTriage: 'priority',
      finalTriage: 'urgent',
      referralIssued: true,
      referralUrgency: 'immediate',
      personId: personId,
      salt: 'test-salt',
    );

Future<Directory> _tempDir() =>
    Directory.systemTemp.createTemp('recalibration_store_test');

void main() {
  group('RecalibrationStore', () {
    test('an unarmed device collects nothing', () async {
      final dir = await _tempDir();
      addTearDown(() => dir.delete(recursive: true));
      final store = RecalibrationStore(
        file: File('${dir.path}/batch.jsonl'),
        salt: null,
      );

      expect(store.isArmed, isFalse);
      await store.append(_record('person-1'));

      expect(await store.count(), 0);
      expect(await store.file.exists(), isFalse,
          reason: 'an unarmed append must not even create the file');
    });

    test('an armed device appends one JSONL line per record', () async {
      final dir = await _tempDir();
      addTearDown(() => dir.delete(recursive: true));
      final store = RecalibrationStore(
        file: File('${dir.path}/batch.jsonl'),
        salt: 'test-salt',
      );

      await store.append(_record('person-1'));
      await store.append(_record('person-2'));

      expect(await store.count(), 2);
      final lines = await store.lines();
      final first = jsonDecode(lines.first) as Map<String, Object?>;
      expect(first['modelName'], 'neonatal_sepsis');
      expect(first['personKey'],
          RecalibrationRecord.personKeyFor('person-1', 'test-salt'));
      expect(lines.first.contains('person-1'), isFalse,
          reason: 'the raw person id must never touch the batch file');
    });

    test('exportBatch writes a month-stamped copy and keeps the batch',
        () async {
      final dir = await _tempDir();
      addTearDown(() => dir.delete(recursive: true));
      final store = RecalibrationStore(
        file: File('${dir.path}/batch.jsonl'),
        salt: 'test-salt',
      );
      await store.append(_record('person-1'));

      final out = await store.exportBatch(now: DateTime(2026, 8, 31));

      // In a plugin-less test VM the export falls back to the batch's own
      // directory; on a device it prefers the USB-visible external storage.
      expect(out.path, contains('recalibration_export_2026-08.jsonl'));
      expect(await out.exists(), isTrue);
      expect((await out.readAsLines()).length, 1);
      expect(await store.count(), 1,
          reason: 'export is a copy — clearing is a separate, sworn step');
    });

    test('clear deletes the on-device batch', () async {
      final dir = await _tempDir();
      addTearDown(() => dir.delete(recursive: true));
      final store = RecalibrationStore(
        file: File('${dir.path}/batch.jsonl'),
        salt: 'test-salt',
      );
      await store.append(_record('person-1'));
      expect(await store.count(), 1);

      await store.clear();

      expect(await store.count(), 0);
      expect(await store.file.exists(), isFalse);
    });
  });
}
