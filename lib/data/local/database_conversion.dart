/// Turning a register that predates encryption into an encrypted one, without the
/// app ever holding only one copy.
///
/// ## Why a plan comes before the work
///
/// The database being converted is the one thing on this handset that cannot be
/// recreated. A CHPS register holds children's immunisation dates and a mother's
/// HIV result; if a migration goes wrong there is no server copy to fall back to,
/// because the whole premise of this app is that the network was not there when
/// the data was written. So the sequence is: count first, convert into a **new
/// file**, reopen that file with the new key and count again, and only swap the
/// names once the two agree. Anything short of that is a bet that a native copy
/// function cannot fail.
///
/// ## Why the plaintext backup survives exactly one launch
///
/// Keeping it forever would mean the point of the migration — no plaintext
/// register on a device that can be lost — is quietly undone. Deleting it
/// immediately means a problem discovered tomorrow has no way back. So the backup
/// is removed by [AppDatabase] the first time it successfully opens the encrypted
/// file, which is one clean launch of proof and no longer. The reasoning is in
/// `app_database.dart` next to the deletion, where someone will find it.
///
/// ## What is verified here and what is not
///
/// Counting, comparison and the swap (including its rollback) run on any platform
/// and are covered by `test/database_conversion_test.dart`. The SQLCipher copy
/// itself lives behind the engine split and can only be exercised on a real
/// Android or iOS device — a desktop test host has no SQLCipher to call. That
/// boundary is stated rather than smoothed over: this file is correct about
/// everything it can check, and refuses to pretend about the rest.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'app_database.dart';
import 'database_secret.dart';
import 'db_engine_stub.dart' if (dart.library.io) 'db_engine_io.dart';

@immutable
class ConversionOutcome {
  const ConversionOutcome.converted(this.message) : converted = true;
  const ConversionOutcome.refused(this.message) : converted = false;

  final bool converted;

  /// Written to be shown to a person: what happened, or what stopped it.
  final String message;
}

abstract final class DatabaseConversion {
  /// Whether this build can convert at all, and why not — so a screen can offer
  /// or withhold the action without importing the platform engine itself.
  static bool get supportedByThisBuild => supportsInPlaceConversion;

  static String get unsupportedReason => conversionUnavailableReason;

  /// Rowids and bookkeeping, not data worth comparing.
  static const _skip = {'android_metadata'};

  /// Every user table in the register and how many rows it holds.
  static Future<Map<String, int>> tableCounts(Database db) async {
    final named = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      'AND name NOT LIKE \'sqlite_%\' ORDER BY name',
    );
    final counts = <String, int>{};
    for (final row in named) {
      final name = row['name'] as String;
      if (_skip.contains(name.toLowerCase())) continue;
      // A table name is an identifier and cannot be bound as a parameter, so it
      // is quoted. Every name here comes from this app's own sqlite_master rather
      // than from user input.
      final counted = await db.rawQuery('SELECT COUNT(*) AS c FROM "$name"');
      counts[name] = (counted.first['c'] as int?) ?? 0;
    }
    return counts;
  }

  /// Where the copy and the original disagree, as sentences.
  ///
  /// Both directions are checked. A table missing from the converted file is
  /// obvious; a table that appears only there means the two files are not the
  /// same register at all, which is worse and easier to miss.
  static List<String> mismatches({
    required Map<String, int> original,
    required Map<String, int> converted,
  }) {
    final problems = <String>[];
    for (final entry in original.entries) {
      final actual = converted[entry.key];
      if (actual == null) {
        problems.add(
          '${entry.key}: ${entry.value} row(s) in the register, '
          'absent from the converted database',
        );
        continue;
      }
      if (actual != entry.value) {
        problems.add(
          '${entry.key}: expected ${entry.value} row(s), found $actual',
        );
      }
    }
    for (final name in converted.keys) {
      if (!original.containsKey(name)) {
        problems.add('$name: present in the converted database only');
      }
    }
    return problems;
  }

  /// Converts the live register, verifying before anything is renamed.
  ///
  /// Refuses rather than improvises at every step: this build unable to convert,
  /// the device unwilling to keep a key, a register that is already encrypted, or
  /// a copy that does not match. A refusal leaves the original file exactly where
  /// it was.
  static Future<ConversionOutcome> runGuarded() async {
    if (!supportsInPlaceConversion) {
      return ConversionOutcome.refused(conversionUnavailableReason);
    }

    final database = await AppDatabase.instance.database;
    final posture = await AppDatabase.instance.posture;
    if (posture.encrypted) {
      return const ConversionOutcome.refused(
        'This register is already encrypted, so there is nothing to convert.',
      );
    }
    final expected = await tableCounts(database);
    final path = await AppDatabase.instance.resolvedPath;

    final passphrase = await DatabaseSecret.passphraseForNewDatabase();
    if (passphrase == null) {
      return const ConversionOutcome.refused(
        'This device would not keep a database key, so the register cannot be '
        'encrypted. Nothing was changed.',
      );
    }

    final target = '$path.converting';
    final backup = '$path.plaintext-backup';
    if (await fileExists(target) || await fileExists(backup)) {
      return const ConversionOutcome.refused(
        'An earlier conversion left a working or backup file behind. Nothing was '
        'changed, because overwriting it could destroy the only remaining copy.',
      );
    }

    // The singleton handle must be released: a file open under the old name
    // cannot be renamed, and SQLCipher must not see the same database twice.
    await AppDatabase.instance.close();

    try {
      await convertPlaintextToEncrypted(
        plainPath: path,
        targetPath: target,
        passphrase: passphrase,
      );
    } catch (e) {
      await deleteFile(target);
      return ConversionOutcome.refused(
        'The copy could not be made (${e.runtimeType}). The existing register is '
        'untouched and still unencrypted.',
      );
    }

    // Verify by opening the copy the way the app will, not by trusting that the
    // copy function reported the truth.
    Database? check;
    var problems = <String>[];
    try {
      check = await openAppDatabase(
        path: target,
        version: kDatabaseVersion,
        passphrase: passphrase,
      );
      problems = mismatches(
        original: expected,
        converted: await tableCounts(check),
      );
    } catch (e) {
      problems = ['the converted file could not be opened: ${e.runtimeType}'];
    } finally {
      await check?.close();
    }

    if (problems.isNotEmpty) {
      await deleteFile(target);
      return ConversionOutcome.refused(
        'Verification failed, so the register was left as it was: '
        '${problems.take(3).join('; ')}.',
      );
    }

    try {
      await swapEncryptedIntoPlace(
        plainPath: path,
        targetPath: target,
        backupPath: backup,
      );
    } catch (e) {
      await deleteFile(target);
      return ConversionOutcome.refused(
        'The converted file was ready but could not be put in place '
        '(${e.runtimeType}). The unencrypted register is still in use.',
      );
    }

    final moved = expected.values.fold<int>(0, (a, b) => a + b);
    return ConversionOutcome.converted(
      'Encrypted the register: $moved row(s) across ${expected.length} table(s) '
      'copied and checked. The unencrypted file is kept until the app has opened '
      'the encrypted one successfully once, then removed.',
    );
  }
}
