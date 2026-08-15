/// On-device store for the Kintampo/Navrongo recalibration pathway.
///
/// The data agreement is signed; this is the machinery that honours it.
/// Every saved assessment can append one [RecalibrationRecord] per model to
/// a JSONL batch file on the device — but only when the district officer has
/// **armed** the device with the GHS-issued linkage salt. No salt, no
/// records: the pathway fails safe, closed.
///
/// The batch file leaves the phone the way the agreement says it does: the
/// district officer exports a monthly-stamped copy during a supervisory
/// visit and clears the device batch. Nothing syncs silently.
library;

import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'recalibration_export.dart';

class RecalibrationStore {
  const RecalibrationStore({required this.file, required this.salt});

  /// Secure-storage key for the GHS-issued linkage salt. The salt is
  /// provisioned by the district officer (see `provisionSalt`) — it is
  /// never compiled into the app.
  static const String saltKey = 'kintampo_recalibration_salt';

  /// Name of the JSONL batch file in the app's documents directory.
  static const String batchFileName = 'recalibration_export.jsonl';

  /// Where the batch lives and the salt that arms it. Injected by
  /// [forDevice] in production; tests pass a temp file and a literal salt.
  final File file;
  final String? salt;

  /// True only when a GHS salt is provisioned. [append] is a no-op
  /// otherwise — an unarmed device collects nothing.
  bool get isArmed => salt != null && salt!.isNotEmpty;

  /// Production factory: documents-directory batch file + salt from secure
  /// storage. Returns null where the platform has no usable storage (web,
  /// unit-test VM without plugins) — callers treat null as "unavailable,
  /// carry on quietly".
  static Future<RecalibrationStore?> forDevice() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final salt = await const FlutterSecureStorage().read(key: saltKey);
      return RecalibrationStore(
        file: File('${dir.path}${Platform.pathSeparator}$batchFileName'),
        salt: salt,
      );
    } catch (_) {
      return null;
    }
  }

  /// Arms the device: stores the GHS-issued salt in secure storage. Called
  /// from the district officer's flow in My Work → Recalibration export.
  static Future<void> provisionSalt(String salt) async {
    await const FlutterSecureStorage().write(key: saltKey, value: salt);
  }

  /// Disarms the device and stops all further capture (e.g. agreement
  /// suspension or device reassignment).
  static Future<void> revokeSalt() async {
    await const FlutterSecureStorage().delete(key: saltKey);
  }

  /// Appends one record as a JSONL line. No-op when unarmed.
  Future<void> append(RecalibrationRecord record) async {
    if (!isArmed) return;
    await file.writeAsString(
      '${record.toJsonLine()}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  /// Number of records currently held on the device.
  Future<int> count() async {
    if (!await file.exists()) return 0;
    final lines = await file.readAsLines();
    return lines.where((l) => l.trim().isNotEmpty).length;
  }

  /// The raw JSONL lines, oldest first.
  Future<List<String>> lines() async {
    if (!await file.exists()) return const <String>[];
    final lines = await file.readAsLines();
    return lines.where((l) => l.trim().isNotEmpty).toList(growable: false);
  }

  /// Copies the batch to a monthly-stamped export file the district officer
  /// can pull during a supervisory visit. Prefers the USB-visible external
  /// app directory (Android); falls back to the documents directory, and in
  /// a plugin-less environment to the batch file's own directory.
  Future<File> exportBatch({DateTime? now}) async {
    final stamp = RecalibrationRecord.monthOf(now ?? DateTime.now());
    Directory targetDir;
    try {
      targetDir =
          await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
    } catch (_) {
      targetDir = file.parent;
    }
    final out = File(
      '${targetDir.path}${Platform.pathSeparator}'
      'recalibration_export_$stamp.jsonl',
    );
    if (await file.exists()) {
      await file.copy(out.path);
    } else {
      await out.writeAsString('', flush: true);
    }
    return out;
  }

  /// Deletes the on-device batch — only after an export has been signed
  /// over to the officer.
  Future<void> clear() async {
    if (await file.exists()) await file.delete();
  }
}
