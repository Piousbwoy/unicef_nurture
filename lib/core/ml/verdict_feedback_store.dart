/// The human-in-the-loop ledger: every time a CHO says the verdict held up
/// (or didn't), one de-identified line lands here.
///
/// This is the flywheel, stated plainly: the more the staff uses the app,
/// the more labelled ground truth the next model review receives. The
/// privacy contract follows the recalibration pathway's lead — no names,
/// no ids, no dates finer than the month, nothing that could point at a
/// family. Unlike the recalibration batch, capture is NOT gated on the GHS
/// salt: the record carries no linkage key at all, so there is nothing to
/// arm. It leaves the phone only the way the district officer collects it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class VerdictFeedbackStore {
  const VerdictFeedbackStore({required this.file});

  /// Name of the JSONL ledger in the app's documents directory.
  static const String fileName = 'verdict_feedback.jsonl';

  /// Bumped whenever the record shape changes, so the pipeline can route.
  static const int currentSchemaVersion = 1;

  /// Injected by [forDevice] in production; tests pass a temp file.
  final File file;

  /// Production factory: documents-directory ledger. Returns null where the
  /// platform has no usable storage (web, plugin-less test VM) — callers
  /// treat null as "unavailable, carry on quietly". The feedback strip must
  /// never cost a CHO a saved assessment, so every failure is swallowed.
  static Future<VerdictFeedbackStore?> forDevice() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return VerdictFeedbackStore(
        file: File('${dir.path}${Platform.pathSeparator}$fileName'),
      );
    } catch (_) {
      return null;
    }
  }

  /// Appends one confirmation as a JSONL line. [correct] is the CHO's
  /// verdict on the verdict; [note] is their optional correction in their
  /// own words. Engine and final triage travel together — the gap between
  /// them is the most valuable signal in the ledger.
  Future<void> append({
    required String clientType,
    required String engineTriage,
    required String finalTriage,
    required bool correct,
    String? note,
  }) async {
    final now = DateTime.now();
    final record = <String, Object?>{
      'schemaVersion': currentSchemaVersion,
      // Month granularity — a feedback line must never be able to point at
      // one visit, the way the recalibration contract demands.
      'recordedMonth': '${now.year}-${now.month.toString().padLeft(2, '0')}',
      'clientType': clientType,
      'engineTriage': engineTriage,
      'finalTriage': finalTriage,
      'verdictCorrect': correct,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    };
    await file.writeAsString(
      '${jsonEncode(record)}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  /// Number of confirmations currently held on the device.
  Future<int> count() async {
    if (!await file.exists()) return 0;
    final lines = await file.readAsLines();
    return lines.where((l) => l.trim().isNotEmpty).length;
  }
}
