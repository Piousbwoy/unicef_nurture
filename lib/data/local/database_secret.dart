/// The database passphrase, and an honest statement of what it protects.
///
/// ## Why "no key" is a permitted outcome
///
/// `flutter_secure_storage` fails on real devices — a corrupted keystore, an
/// Android OEM that kills it after an app update, a browser with no platform
/// storage at all. The tempting response is a fallback: derive something from the
/// app name and carry on as if the file were protected. That is the one option
/// that must not be taken. A database encrypted with a key anyone can recompute
/// is not encrypted, and the app would still report that it is — which is worse
/// for a district than an unencrypted file plus a settings screen that says so.
/// So a device that cannot hold a key gets an unencrypted register and a visible,
/// specific reason.
///
/// ## Why the key is written once and never derived
///
/// A passphrase derived from the user's PIN would have to change every time she
/// changes it, and every health worker on a shared CHPS handset would need one of
/// their own — which would put the register out of reach after a lost device
/// recovery. A random per-installation key stored in the hardware-backed store is
/// the arrangement that survives both. It is also the primitive that makes
/// crypto-shredding possible later: destroying this value is what erases a record
/// for real, which is the property the Data Protection Act's erasure right needs
/// and a `DELETE FROM` does not provide.
///
/// ## The data-loss hazard, handled
///
/// A key that is written but not actually persisted is the worst failure mode
/// available: the database is created with a passphrase nobody kept, and on the
/// next launch it cannot be opened at all. So [passphraseForNewDatabase] reads the
/// value back and refuses to proceed unless the stored copy matches — falling back
/// to an unencrypted register rather than to an unreadable one.
library;

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Whether the register on this device is encrypted at rest, stated in the words
/// a settings screen shows. Never inferred from a build flag by the UI.
@immutable
class AtRestPosture {
  const AtRestPosture.encrypted()
    : encrypted = true,
      summary =
          'Encrypted at rest. Patient records on this phone are unreadable '
          'without the device key, which lives in the hardware-backed store and '
          'never leaves it.';

  const AtRestPosture.plaintext(this.summary) : encrypted = false;

  final bool encrypted;
  final String summary;
}

abstract final class DatabaseSecret {
  /// Versioned so a future key rotation can introduce `v2` and tell the two
  /// apart, rather than discovering it when a database will not open.
  static const _keyName = 'carebridge.db.passphrase.v1';

  /// Deliberately the same plain construction the session store uses: this app
  /// already relies on flutter_secure_storage being keystore- and
  /// keychain-backed by default, and quietly diverging here would be a second,
  /// undocumented security decision.
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static final Random _random = Random.secure();

  /// A passphrase for a database that does not exist yet, or null when this
  /// device cannot hold one.
  static Future<String?> passphraseForNewDatabase() async {
    try {
      final existing = await _storage.read(key: _keyName);
      // 32 base64url characters is well short of 32 bytes; anything thinner is a
      // truncated or half-written value from an older release, and reusing it
      // would mean accepting a weak key forever because it is already stored.
      if (existing != null && _looksLikeAKey(existing)) return existing;

      final fresh = base64Url.encode(
        List<int>.generate(32, (_) => _random.nextInt(256)),
      );
      await _storage.write(key: _keyName, value: fresh);

      final readBack = await _storage.read(key: _keyName);
      if (readBack != fresh) {
        debugPrint(
          'Database key did not persist; this register will not be encrypted.',
        );
        return null;
      }
      return fresh;
    } catch (e) {
      debugPrint('Database key store unavailable: $e');
      return null;
    }
  }

  static bool _looksLikeAKey(String value) {
    if (value.length < 43) return false; // 32 bytes in base64 is 43+ characters
    return true;
  }
}
