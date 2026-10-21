/// The non-encrypting database engine — the default for web and any platform
/// whose build cannot carry SQLCipher.
///
/// Selected by `app_database.dart` through a conditional import, following the
/// repo's existing pattern (`piper_tts_runner.dart`, `translation_runner.dart`).
/// This file must not import `dart:io`, which is what keeps the web build
/// compiling: the SQLCipher package pulls `dart:io` in on the native side.
///
/// ## Why this file is allowed to say "not encrypted" out loud
///
/// The alternative — a hardcoded fallback key so every platform looks encrypted —
/// is worse than doing nothing, because it produces a system that reports a
/// security property it does not have. A control that cannot be declined honestly
/// is not a control, it is a claim. The posture reported here is surfaced in the
/// app and in the compliance mapping, so a browser demo reads as a demo rather
/// than as a district deployment.
library;

import 'package:sqflite/sqflite.dart';

/// Whether this build can encrypt the local register at rest.
bool get supportsEncryptionAtRest => false;

/// Why not, in the words a settings screen shows.
///
/// Deliberately specific: "encryption is not available" reads like a bug, while
/// naming the platforms tells a district IT officer what to install to get it.
String get encryptionUnavailableReason =>
    'This build keeps the register in an unencrypted SQLite file. Encryption at '
    'rest is in the Android and iOS builds; the browser and desktop builds are '
    'demonstration targets, not the thing a district installs on a field phone.';

/// Always reports an existing database, so no key is ever requested on a
/// platform that could not use it. Only consulted when
/// [supportsEncryptionAtRest] is true.
Future<bool> localDatabaseExists(String path) async => true;

/// This engine cannot produce an encrypted file, so it certainly cannot convert
/// one. Reported rather than thrown, because the caller has to tell a district
/// why nothing happened.
bool get supportsInPlaceConversion => false;

String get conversionUnavailableReason =>
    'This build has no encrypted database engine, so an existing register cannot '
    'be converted here. The Android and iOS builds can.';

Future<void> convertPlaintextToEncrypted({
  required String plainPath,
  required String targetPath,
  required String passphrase,
}) async {
  throw UnsupportedError(conversionUnavailableReason);
}

/// The browser has no file to inspect — the register lives inside IndexedDB, so
/// every question about "the database file" is answered the safe way: it does not
/// exist here, and nothing may be renamed.
Future<bool> fileExists(String path) async => false;

Future<void> deleteFile(String path) async {}

Future<void> swapEncryptedIntoPlace({
  required String plainPath,
  required String targetPath,
  required String backupPath,
}) async {
  throw UnsupportedError(conversionUnavailableReason);
}

Future<Database> openAppDatabase({
  required String path,
  required int version,
  OnDatabaseConfigureFn? onConfigure,
  OnDatabaseCreateFn? onCreate,
  OnDatabaseVersionChangeFn? onUpgrade,
  String? passphrase,
}) => openDatabase(
  path,
  version: version,
  onConfigure: onConfigure,
  onCreate: onCreate,
  onUpgrade: onUpgrade,
);
