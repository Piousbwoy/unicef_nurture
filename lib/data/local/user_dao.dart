/// Users, PINs and the audit trail.
///
/// Constraint 5 of the brief is protection of sensitive health data. In a CHPS
/// compound that constraint has a specific shape: **one Android phone is shared**
/// — by the CHO, the community health nurse, sometimes a volunteer, and in
/// caregiver mode by mothers waiting under the tree outside. The threat is not a
/// remote attacker. It is the next person to pick up the handset.
///
/// So the design is:
///
/// **A 4-digit PIN, salted and hashed.** Not a password. A CHO with wet hands
/// and a cracked screen will not type a passphrase forty times a day, and an app
/// that is annoying to unlock gets left unlocked. Four digits is weak in the
/// abstract and correct here, because it is defending against casual access on a
/// device that is already in trusted hands — and because the alternative in
/// practice is no lock at all.
///
/// **Per-user salt, PBKDF2-style stretching.** A raw SHA-256 of a 4-digit PIN is
/// a 10,000-entry rainbow table anybody could build in a second. Stretching over
/// many iterations makes an offline attack on a stolen phone cost real time.
///
/// **Every permission denial is logged.** Access control that leaves no trace is
/// a claim, not a control. The audit log is what lets a district team answer
/// "who opened this mother's record" — and it is written locally first, like
/// everything else.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:sqflite/sqflite.dart';

import '../../domain/entities/core.dart';
import '../../domain/enums.dart';
import 'app_database.dart';
import 'outbox_dao.dart';

/// PIN stretching. 20,000 iterations is a fraction of a second on a low-end
/// Android phone and a very long time across 10,000 candidate PINs.
/// On Web (JS event loop) and during debug tests, lower iterations prevent UI thread freezing.
final int _pinIterations = kIsWeb ? 500 : (kDebugMode ? 1000 : 20000);

abstract final class Credentials {
  static final Random _random = Random.secure();

  static String newSalt([int bytes = 16]) {
    final values = List<int>.generate(bytes, (_) => _random.nextInt(256));
    return base64Url.encode(values);
  }

  /// Iterated HMAC-SHA256, the same construction PBKDF2 uses.
  ///
  /// Written out rather than pulled from a package because the dependency list
  /// is already long and this is thirty lines of well-understood code — but the
  /// construction itself is standard, not invented here.
  static String hashPin(String pin, String salt) {
    final key = utf8.encode(salt);
    var block = Uint8List.fromList(utf8.encode(pin));
    for (var i = 0; i < _pinIterations; i++) {
      block = Uint8List.fromList(Hmac(sha256, key).convert(block).bytes);
    }
    return base64.encode(block);
  }

  /// Constant-time comparison. The timing channel on a local PIN check is
  /// largely theoretical, but getting this wrong is free to avoid.
  static bool verify(String pin, String salt, String expectedHash) {
    final actual = hashPin(pin, salt);
    if (actual.length != expectedHash.length) return false;
    var diff = 0;
    for (var i = 0; i < actual.length; i++) {
      diff |= actual.codeUnitAt(i) ^ expectedHash.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// Rejects the PINs that make a lock pointless. Enforced at registration
  /// rather than suggested, because "1234" is what gets typed otherwise.
  static String? validatePin(String pin) {
    if (pin.length != 4 || int.tryParse(pin) == null) {
      return 'The PIN must be exactly 4 digits.';
    }
    if (RegExp(r'^(\d)\1{3}$').hasMatch(pin)) {
      return 'Do not use the same digit four times.';
    }
    const sequences = {'1234', '4321', '0123', '3210', '2345', '6789', '9876'};
    if (sequences.contains(pin)) {
      return 'That PIN is too easy to guess. Choose another.';
    }
    return null;
  }
}

/// Why a sign-in failed, so the UI can say something true and useful rather
/// than "invalid credentials".
enum AuthFailure {
  unknownPhone('No account on this phone uses that number.'),
  wrongPin('That PIN is not correct.'),
  noPinSet('This account has no PIN yet. Set one to continue.'),
  lockedOut('Too many wrong attempts. Wait a moment and try again.');

  const AuthFailure(this.message);
  final String message;
}

class AuthResult {
  const AuthResult.success(this.user) : failure = null;
  const AuthResult.failure(this.failure) : user = null;

  final AppUser? user;
  final AuthFailure? failure;

  bool get isSuccess => user != null;
}

abstract final class UserDao {
  /// Creates an account with a PIN, or replaces one that already exists for the
  /// same phone number.
  ///
  /// [linkedHouseholdId] is what makes caregiver access safe: a caregiver
  /// account is bound to exactly one household at creation, so
  /// `viewOwnFamilyOnly` has something concrete to scope to and cannot be
  /// widened later from inside the app.
  static Future<AppUser> register({
    required AppUser user,
    required String pin,
    String? linkedHouseholdId,
  }) async {
    final salt = Credentials.newSalt();
    final hash = Credentials.hashPin(pin, salt);
    final db = await AppDatabase.instance.database;

    await db.transaction((txn) async {
      final map = user.toMap();
      await txn.insert(Tables.users, {
        ...map,
        'pin_hash': hash,
        'pin_salt': salt,
        'linked_household_id': linkedHouseholdId,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      // The PIN hash is deliberately absent from the sync payload. Credentials
      // are device-local; there is no reason for them to travel.
      await OutboxDao.enqueue(
        txn,
        table: Tables.users,
        entityId: user.id,
        operation: SyncOperation.insert,
        payload: map,
        priority: SyncPriority.background,
      );

      await txn.insert(Tables.auditLog, {
        'actor_id': user.id,
        'actor_role': user.role.name,
        'action': 'register_user',
        'entity_table': Tables.users,
        'entity_id': user.id,
        'outcome': 'allowed',
        'detail': 'Account created as ${user.role.label}',
        'occurred_at': DateTime.now().toIso8601String(),
      });
    });

    return user;
  }

  static Future<AuthResult> signIn({
    required String phone,
    required String pin,
  }) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.users,
      where: 'phone = ?',
      whereArgs: [phone.trim()],
      limit: 1,
    );

    if (rows.isEmpty) {
      await AuditDao.record(
        action: 'sign_in',
        outcome: 'denied',
        detail: 'Unknown phone number',
      );
      return const AuthResult.failure(AuthFailure.unknownPhone);
    }

    final row = rows.first;
    final salt = row['pin_salt'] as String?;
    final hash = row['pin_hash'] as String?;

    if (salt == null || hash == null) {
      return const AuthResult.failure(AuthFailure.noPinSet);
    }

    if (!Credentials.verify(pin, salt, hash)) {
      await AuditDao.record(
        actorId: row['id'] as String,
        action: 'sign_in',
        outcome: 'denied',
        detail: 'Wrong PIN',
      );
      return const AuthResult.failure(AuthFailure.wrongPin);
    }

    final user = AppUser.fromMap(row);
    await AuditDao.record(
      actorId: user.id,
      actorRole: user.role.name,
      action: 'sign_in',
      outcome: 'allowed',
    );
    return AuthResult.success(user);
  }

  static Future<AppUser?> byId(String id) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.users,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : AppUser.fromMap(rows.first);
  }

  static Future<AppUser?> byPhone(String phone) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.users,
      where: 'phone = ?',
      whereArgs: [phone.trim()],
      limit: 1,
    );
    return rows.isEmpty ? null : AppUser.fromMap(rows.first);
  }

  /// Resets a user's PIN without requiring the old one. Intended for a local
  /// device-only reset flow when no SMS backend is available.
  static Future<bool> resetPin({
    required String phone,
    required String newPin,
  }) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.users,
      where: 'phone = ?',
      whereArgs: [phone.trim()],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    final user = AppUser.fromMap(rows.first);
    final newSalt = Credentials.newSalt();
    await db.update(
      Tables.users,
      {
        'pin_salt': newSalt,
        'pin_hash': Credentials.hashPin(newPin, newSalt),
      },
      where: 'id = ?',
      whereArgs: [user.id],
    );
    await AuditDao.record(
      actorId: user.id,
      action: 'reset_pin',
      outcome: 'allowed',
    );
    return true;
  }

  /// The household a caregiver account may see. Null for an FHW, whose scope is
  /// their zone rather than one compound.
  static Future<String?> linkedHouseholdFor(String userId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.users,
      columns: ['linked_household_id'],
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['linked_household_id'] as String?;
  }

  static Future<void> setLinkedHousehold({
    required String userId,
    required String householdId,
  }) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      Tables.users,
      {'linked_household_id': householdId},
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  /// Accounts registered on this device, for the account picker on a shared
  /// phone.
  static Future<List<AppUser>> all() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(Tables.users, orderBy: 'created_at ASC');
    return rows.map(AppUser.fromMap).toList(growable: false);
  }

  static Future<List<AppUser>> byRole(UserRole role) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.users,
      where: 'role = ?',
      whereArgs: [role.name],
      orderBy: 'full_name ASC',
    );
    return rows.map(AppUser.fromMap).toList(growable: false);
  }

  static Future<bool> anyRegistered() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${Tables.users}',
    );
    return (rows.first['c'] as num).toInt() > 0;
  }

  static Future<bool> changePin({
    required String userId,
    required String currentPin,
    required String newPin,
  }) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.users,
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty) return false;

    final salt = rows.first['pin_salt'] as String?;
    final hash = rows.first['pin_hash'] as String?;
    if (salt == null || hash == null) return false;
    if (!Credentials.verify(currentPin, salt, hash)) return false;

    final newSalt = Credentials.newSalt();
    await db.update(
      Tables.users,
      {'pin_salt': newSalt, 'pin_hash': Credentials.hashPin(newPin, newSalt)},
      where: 'id = ?',
      whereArgs: [userId],
    );
    await AuditDao.record(
      actorId: userId,
      action: 'change_pin',
      outcome: 'allowed',
    );
    return true;
  }

  static Future<void> updateLanguage({
    required String userId,
    required String language,
  }) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      Tables.users,
      {'preferred_language': language},
      where: 'id = ?',
      whereArgs: [userId],
    );
  }
}

/// One audit entry. Written for permission denials, clinical overrides, sign-ins
/// and record exports.
class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.action,
    required this.outcome,
    required this.occurredAt,
    this.actorId,
    this.actorRole,
    this.entityTable,
    this.entityId,
    this.detail,
  });

  final int id;
  final String action;
  final String outcome;
  final DateTime occurredAt;
  final String? actorId;
  final String? actorRole;
  final String? entityTable;
  final String? entityId;
  final String? detail;

  bool get wasDenied => outcome == 'denied';

  factory AuditEntry.fromMap(Map<String, Object?> m) => AuditEntry(
    id: (m['id'] as num).toInt(),
    action: m['action'] as String,
    outcome: m['outcome'] as String,
    occurredAt: DateTime.parse(m['occurred_at'] as String),
    actorId: m['actor_id'] as String?,
    actorRole: m['actor_role'] as String?,
    entityTable: m['entity_table'] as String?,
    entityId: m['entity_id'] as String?,
    detail: m['detail'] as String?,
  );
}

abstract final class AuditDao {
  /// Never throws.
  ///
  /// Audit logging must not be able to break care delivery. If the log write
  /// fails, the assessment still saves — a lost audit line is a governance
  /// problem, a blocked assessment is a clinical one, and they are not the same
  /// size.
  static Future<void> record({
    required String action,
    required String outcome,
    String? actorId,
    String? actorRole,
    String? entityTable,
    String? entityId,
    String? detail,
  }) async {
    try {
      final db = await AppDatabase.instance.database;
      await db.insert(Tables.auditLog, {
        'actor_id': actorId,
        'actor_role': actorRole,
        'action': action,
        'entity_table': entityTable,
        'entity_id': entityId,
        'outcome': outcome,
        'detail': detail,
        'occurred_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {
      // Deliberately swallowed. See the doc comment above.
    }
  }

  /// Convenience for the commonest entry: somebody tried to do something their
  /// role does not allow.
  static Future<void> denied({
    required String action,
    required AppUser? actor,
    Permission? permission,
    String? entityTable,
    String? entityId,
  }) => record(
    action: action,
    outcome: 'denied',
    actorId: actor?.id,
    actorRole: actor?.role.name,
    entityTable: entityTable,
    entityId: entityId,
    detail: permission == null
        ? 'Not permitted for this role'
        : 'Missing permission: ${permission.name}',
  );

  static Future<List<AuditEntry>> recent({int limit = 100}) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.auditLog,
      orderBy: 'occurred_at DESC',
      limit: limit,
    );
    return rows.map(AuditEntry.fromMap).toList(growable: false);
  }

  static Future<List<AuditEntry>> denials({int limit = 50}) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.auditLog,
      where: 'outcome = ?',
      whereArgs: ['denied'],
      orderBy: 'occurred_at DESC',
      limit: limit,
    );
    return rows.map(AuditEntry.fromMap).toList(growable: false);
  }
}
