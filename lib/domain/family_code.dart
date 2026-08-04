/// The family code.
///
/// A caregiver account has to be tied to exactly one household, and the tying
/// has to happen on a phone with no network, in a compound, in front of the
/// family. That rules out an email invite or a server-issued token.
///
/// So the code is *derived* from the household id: six characters a CHO can read
/// aloud and a mother can type. Nothing is stored, nothing has to sync, and the
/// same household always produces the same code on any device that holds its
/// record.
///
/// It is deliberately not a secret. Knowing a code is not enough to see a
/// household's records — the account still needs a PIN, and every read is still
/// checked against the binding at the repository. The code's job is to stop the
/// wrong household being linked by accident, not to resist an attacker.
///
/// The alphabet excludes the characters that get misheard or mistyped when a code
/// is read out in a noisy compound: I/1, O/0, U/V, and S/5.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'entities/core.dart';

abstract final class FamilyCode {
  static const _alphabet = 'ABCDEFGHJKLMNPQRTWXYZ2346789';
  static const int length = 6;

  /// The code for a household id. Deterministic.
  static String of(String householdId) {
    final digest = sha256.convert(utf8.encode('carebridge:$householdId')).bytes;
    final chars = <String>[];
    for (var i = 0; i < length; i++) {
      chars.add(_alphabet[digest[i] % _alphabet.length]);
    }
    return chars.join();
  }

  /// Formats for reading aloud: `ABC-D24`.
  static String pretty(String householdId) {
    final code = of(householdId);
    return '${code.substring(0, 3)}-${code.substring(3)}';
  }

  /// Accepts what a person actually types: lower case, spaces, hyphens, and the
  /// confusable characters mapped to what the speaker almost certainly said.
  static String normalise(String input) {
    final upper = input.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return upper
        .replaceAll('I', 'J')
        .replaceAll('1', 'J')
        .replaceAll('O', 'Q')
        .replaceAll('0', 'Q')
        .replaceAll('U', 'W')
        .replaceAll('V', 'W')
        .replaceAll('S', '9')
        .replaceAll('5', '9');
  }

  static bool matches(String householdId, String typed) =>
      normalise(typed) == normalise(of(householdId));

  static bool looksValid(String typed) => normalise(typed).length == length;

  /// Encodes a Household record into a high-density, offline-verifiable QR payload string.
  /// This enables zero-network optical database synchronization from tablet to smartphone.
  static String encodeQrPayload(Household h) {
    final payload = {
      'p': 'CB_FAMILY',
      'id': h.id,
      'nm': h.name,
      'rg': h.region,
      'ds': h.district,
      'cm': h.community,
      'cb': h.createdBy,
      'lm': h.landmark ?? '',
    };
    return 'CAREBRIDGE_QR|${base64Encode(utf8.encode(jsonEncode(payload)))}';
  }

  /// Decodes a compressed QR payload string back into a valid Household entity.
  /// Returns null if the string is not a valid CareBridge family payload.
  static Household? decodeQrPayload(String data) {
    try {
      if (!data.startsWith('CAREBRIDGE_QR|')) return null;
      final encoded = data.substring('CAREBRIDGE_QR|'.length);
      final jsonStr = utf8.decode(base64Decode(encoded));
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      if (map['p'] != 'CB_FAMILY') return null;
      return Household(
        id: map['id'] as String,
        name: map['nm'] as String,
        region: map['rg'] as String,
        district: map['ds'] as String,
        community: map['cm'] as String,
        createdBy: (map['cb'] as String?) ?? 'FHW-QR-SYNC',
        landmark: map['lm'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}
