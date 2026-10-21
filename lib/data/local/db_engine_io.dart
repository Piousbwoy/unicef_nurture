/// The native database engine: SQLCipher on Android and iOS, plain SQLite
/// everywhere else this file can be reached from.
///
/// Chosen by `app_database.dart` via `if (dart.library.io)`, so this is compiled
/// for mobile and desktop but not for the web build — the package itself imports
/// `dart:io`, which is exactly why the split exists.
///
/// ## Desktop is not silently pretending to be mobile
///
/// Windows, macOS and Linux take the plain path here rather than being handed a
/// password the engine would ignore. That keeps the reported posture honest:
/// `supportsEncryptionAtRest` is the single answer every surface reads, so a
/// district IT officer looking at the settings screen is told the truth about the
/// build in front of them.
library;

import 'dart:io';

// Types come from `package:sqflite` rather than `sqflite_common` directly:
// sqflite re-exports them, and importing the transitive package would trip
// `depend_on_referenced_packages`. SQLCipher's own signatures are aliases of the
// same sqflite_common typedefs, so the two engines accept the same callbacks.
import 'package:sqflite/sqflite.dart' as plain;
import 'package:sqflite_sqlcipher/sqflite.dart' as cipher;

/// SQLCipher is linked into the Android and iOS builds only.
bool get supportsEncryptionAtRest => Platform.isAndroid || Platform.isIOS;

String get encryptionUnavailableReason =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS
    ? 'The desktop build uses the plain SQLite engine, so the register on this '
          'computer is not encrypted at rest. Desktop is a development and '
          'demonstration target here, not the build a district installs.'
    : 'This platform has no encrypted SQLite engine linked into this build.';

Future<bool> localDatabaseExists(String path) => plain.databaseExists(path);

Future<plain.Database> openAppDatabase({
  required String path,
  required int version,
  plain.OnDatabaseConfigureFn? onConfigure,
  plain.OnDatabaseCreateFn? onCreate,
  plain.OnDatabaseVersionChangeFn? onUpgrade,
  String? passphrase,
}) {
  if (!supportsEncryptionAtRest || passphrase == null) {
    return plain.openDatabase(
      path,
      version: version,
      onConfigure: onConfigure,
      onCreate: onCreate,
      onUpgrade: onUpgrade,
    );
  }
  return cipher.openDatabase(
    path,
    version: version,
    password: passphrase,
    onConfigure: onConfigure,
    onCreate: onCreate,
    onUpgrade: onUpgrade,
  );
}

/// Whether an existing plaintext register can be converted by this build.
bool get supportsInPlaceConversion => Platform.isAndroid || Platform.isIOS;

String get conversionUnavailableReason =>
    'Conversion needs the SQLCipher engine, which is linked into the Android and '
    'iOS builds only. This build cannot turn an existing register into an '
    'encrypted one.';

/// SQLite has no parameter slot for an ATTACH key — it is a token in the
/// grammar, not an expression — so the value is interpolated. That is only safe
/// if it is checked first rather than escaped optimistically: a real passphrase
/// is base64url and can never contain a quote, and anything that does is refused
/// outright instead of being concatenated into DDL.
final RegExp _passphraseShape = RegExp(r'^[A-Za-z0-9_\-]{32,}$');

/// Copies an unencrypted register into a new keyed database file using
/// SQLCipher's own export, leaving the source untouched.
///
/// The caller owns verification and the file swap. This function deliberately
/// does not rename or delete anything: if it did, a failure halfway through would
/// be indistinguishable from a lost register, and the only recovery would be a
/// backup the caller never got to check.
Future<void> convertPlaintextToEncrypted({
  required String plainPath,
  required String targetPath,
  required String passphrase,
}) async {
  if (!supportsInPlaceConversion) {
    throw UnsupportedError(conversionUnavailableReason);
  }
  if (!_passphraseShape.hasMatch(passphrase)) {
    throw ArgumentError(
      'The stored database key is not in the expected form, so it cannot be used '
      'to convert the register.',
    );
  }
  for (final path in [plainPath, targetPath]) {
    if (path.contains("'")) {
      throw ArgumentError('Refusing to convert from an unexpected file path.');
    }
  }

  // SQLCipher opens a plaintext database with an empty key, which is what makes
  // this direction possible: `main` is the old register and the keyed file is
  // attached beside it. Foreign keys are off for the copy because
  // sqlcipher_export moves tables in whatever order the schema happens to be in.
  final db = await cipher.openDatabase(plainPath, password: '');
  try {
    await db.execute('PRAGMA foreign_keys = OFF');
    await db.execute(
      "ATTACH DATABASE '$targetPath' AS keyed KEY '$passphrase'",
    );
    await db.execute("SELECT sqlcipher_export('keyed')");
    await db.execute('DETACH DATABASE keyed');
  } finally {
    // Closing is what checkpoints the journal. The swap that follows must not run
    // while a sidecar file still holds committed rows.
    await db.close();
  }
}

Future<bool> fileExists(String path) => File(path).exists();

Future<void> deleteFile(String path) async {
  final file = File(path);
  if (await file.exists()) await file.delete();
}

/// Moves the converted file into place, keeping the original as a backup.
///
/// Two renames cannot be atomic, and the gap between them is the only moment this
/// device holds no complete register. So the order is deliberate — original to
/// backup first, new into place second — and a failure in between puts the
/// original back before anything is reported. A migration that leaves a register
/// half-named is the one outcome a storage control is not allowed to produce.
Future<void> swapEncryptedIntoPlace({
  required String plainPath,
  required String targetPath,
  required String backupPath,
}) async {
  final plain = File(plainPath);
  final target = File(targetPath);
  if (!await target.exists()) {
    throw StateError('The converted database is missing; nothing was swapped.');
  }
  if (await File(backupPath).exists()) {
    throw StateError(
      'A previous conversion backup is still present. Resolve it before running '
      'again, so a register is never overwritten twice.',
    );
  }

  final hadPlain = await plain.exists();
  if (hadPlain) await plain.rename(backupPath);
  try {
    await target.rename(plainPath);
  } catch (e) {
    if (hadPlain) await File(backupPath).rename(plainPath);
    rethrow;
  }
}
