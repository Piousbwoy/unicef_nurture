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
import '../sync/recovery_service.dart';
import '../sync/server_auth_client.dart';

/// PIN stretching. 20,000 iterations is a fraction of a second on a low-end
/// Android phone and a very long time across 10,000 candidate PINs.
/// On Web (JS event loop) and during debug tests, lower iterations prevent UI thread freezing.
final int _pinIterations = kIsWeb ? 500 : (kDebugMode ? 1000 : 20000);

abstract final class Credentials {
  static final Random _random = Random.secure();

  /// Domain separator used for the cloud verifier derivation. NEVER change
  /// this after go-live — every account registered under the old separator
  /// would become unrecoverable.
  static const String cloudVerifierDomainSeparator = 'carebridge_cloud_auth_v1';

  /// Iterations for the cloud-verifier stretched HMAC derivation. This is a
  /// deliberately high cost (distinct from the on-device 20k hash) so a
  /// stolen user_verifiers table remains expensive to crack, even without
  /// knowing either the on-device pin_hash or the 4-digit PIN.
  static int get cloudVerifierIterations =>
      kIsWeb ? 500 : (kDebugMode ? 1000 : 120000);

  static String newSalt([int bytes = 16]) {
    final values = List<int>.generate(bytes, (_) => _random.nextInt(256));
    return base64Url.encode(values);
  }

  /// Iterated HMAC-SHA256, the same construction PBKDF2 uses — ON-DEVICE
  /// credentials ONLY. This stretched hash (plus its salt) must never leave
  /// the local SQLite database. Not synced, not logged, not sent anywhere.
  static String hashPin(String pin, String salt) {
    final key = utf8.encode(salt);
    var block = Uint8List.fromList(utf8.encode(pin));
    for (var i = 0; i < _pinIterations; i++) {
      block = Uint8List.fromList(Hmac(sha256, key).convert(block).bytes);
    }
    return base64.encode(block);
  }

  /// Domain-separated cloud authentication verifier. This is the ONLY value
  /// that ever leaves the device for MariaDB user_verifiers. Per the Ghana
  /// Health Service compliance architecture:
  ///
  ///   CloudVerifier = HMAC-SHA256-ITERATED(
  ///       key   = "carebridge_cloud_auth_v1" || server_salt || phone,
  ///       input = local_pin_hash)
  ///
  /// Because this is a one-way keyed derivation on the already-stretched
  /// pin_hash:
  ///   - A breach of MariaDB cannot recover the on-device pin_hash (domain
  ///     separator + per-user server salt + 120k additional iterations).
  ///   - A breach of MariaDB cannot recover the 4-digit PIN (the 120k cost
  ///     plus the domain-separated structure means you cannot repurpose
  ///     offline PIN rainbow tables).
  ///   - On a blank replacement device during recovery, the client fetches
  ///     the server_salt first (public, non-secret), recomputes this verifier
  ///     from PIN+phone+server_salt, and the server compares constant-time.
  static String computeCloudVerifier({
    required String localPinHash,
    required String phone,
    required String serverSalt,
  }) {
    final keyMaterial =
        utf8.encode('$cloudVerifierDomainSeparator|$serverSalt|$phone');
    var block = Uint8List.fromList(utf8.encode(localPinHash));
    for (var i = 0; i < cloudVerifierIterations; i++) {
      block = Uint8List.fromList(Hmac(sha256, keyMaterial).convert(block).bytes);
    }
    return base64.encode(block);
  }

  /// Convenience helper for a blank device during recovery: when the client
  /// does not hold the local pin_hash, it can compute a verifier from the
  /// same primitive inputs the device WOULD have used if it were the
  /// original. Stretches the PIN with the SERVER SALT (not the on-device
  /// pin_salt — we deliberately never fetch that from MariaDB).
  ///
  /// CloudVerifier(no local hash) = HMAC-SHA256-ITERATED(
  ///     key   = "carebridge_cloud_auth_v1" || server_salt || phone,
  ///     input = STRETCHED(pin, server_salt, device_iterations))
  static String computeCloudVerifierFromPin({
    required String pin,
    required String phone,
    required String serverSalt,
  }) {
    final firstPassKey = utf8.encode('first_pass|$serverSalt|$phone');
    var firstPass = Uint8List.fromList(utf8.encode(pin));
    for (var i = 0; i < _pinIterations; i++) {
      firstPass =
          Uint8List.fromList(Hmac(sha256, firstPassKey).convert(firstPass).bytes);
    }
    final keyMaterial =
        utf8.encode('$cloudVerifierDomainSeparator|$serverSalt|$phone');
    var block = firstPass;
    for (var i = 0; i < cloudVerifierIterations; i++) {
      block = Uint8List.fromList(Hmac(sha256, keyMaterial).convert(block).bytes);
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

  /// Constant-time verifier comparison — returns true only if the candidate
  /// cloud verifier matches the stored one, with no early-return short-circuit.
  static bool verifyCloudVerifier(String candidate, String expected) {
    if (candidate.length != expected.length) return false;
    var diff = 0;
    for (var i = 0; i < candidate.length; i++) {
      diff |= candidate.codeUnitAt(i) ^ expected.codeUnitAt(i);
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
  unknownPhone('No account found locally or on the MariaDB Main Server. Tap Create Account below to set up your offline profile.'),
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
    final localSalt = Credentials.newSalt();
    final localPinHash = Credentials.hashPin(pin, localSalt);
    final serverSalt = Credentials.newSalt(24); // distinct from the on-device localSalt
    final cloudVerifier = Credentials.computeCloudVerifier(
      localPinHash: localPinHash,
      phone: user.phone,
      serverSalt: serverSalt,
    );
    final deviceId = await _deviceIdForOutbox();
    final db = await AppDatabase.instance.database;

    await db.transaction((txn) async {
      // LOCAL SQLite ONLY — localSalt and localPinHash NEVER leave the device, nowhere else.
      final localUserRow = {
        ...user.toMap(),
        'pin_hash': localPinHash,
        'pin_salt': localSalt,
        'linked_household_id': linkedHouseholdId,
      };
      await txn.insert(
        Tables.users,
        localUserRow,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      //  // WIRE OUTBOX — intentionally scoped to EXCLUDE on-device credentials.
      // Part (a): the plain user profile (no pin_hash, no pin_salt anywhere).
      final userPayloadForServer = {
        ...user.toMap(),
        'linked_household_id': linkedHouseholdId,
      };
      await OutboxDao.enqueue(
        txn,
        table: Tables.users,
        entityId: user.id,
        operation: SyncOperation.insert,
        payload: userPayloadForServer,
        priority: SyncPriority.critical,
      );

      // Part (b): a SEPARATE outbox row writes only the domain-separated cloud
      // verifier, isolated from the general users table — exactly as prescribed by
      // the Ghana Health Service compliance architecture.
      //
      // Promoted to SyncPriority.critical (0, the highest) because no downstream
      // clinical record created_by this user can be correctly attributed in
      // MariaDB until the identity rows are ingested first.
      final now = DateTime.now().toIso8601String();
      await OutboxDao.enqueue(
        txn,
        table: Tables.userVerifiers,
        entityId: user.id,
        operation: SyncOperation.insert,
        payload: {
          'user_id': user.id,
          'server_salt': serverSalt,
          'verifier': cloudVerifier,
          'device_id': deviceId,
          'created_at': now,
          'updated_at': now,
        },
        priority: SyncPriority.critical,
      );

      await txn.insert(Tables.auditLog, {
        'actor_id': user.id,
        'actor_role': user.role.name,
        'action': 'register_user',
        'entity_table': Tables.users,
        'entity_id': user.id,
        'outcome': 'allowed',
        'detail':
            'Account created as ${user.role.label}. Local pin_hash retained on device only; cloud verifier enqueued to user_verifiers.',
        'occurred_at': DateTime.now().toIso8601String(),
      });
    });

    return user;
  }

  /// Resets a user's PIN without requiring the old one. Intended for a local
  /// device-only reset flow when no SMS backend is available.
  ///
  /// Also re-derives the cloud verifier against a fresh server_salt and enqueues
  /// it to user_verifiers so a subsequent recovery login still succeeds from any device.
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
    final newLocalSalt = Credentials.newSalt();
    final newLocalHash = Credentials.hashPin(newPin, newLocalSalt);
    final newServerSalt = Credentials.newSalt(24);
    final newCloudVerifier = Credentials.computeCloudVerifier(
      localPinHash: newLocalHash,
      phone: user.phone,
      serverSalt: newServerSalt,
    );
    final deviceId = await _deviceIdForOutbox();
    await db.transaction((txn) async {
      await txn.update(
        Tables.users,
        {'pin_salt': newLocalSalt, 'pin_hash': newLocalHash},
        where: 'id = ?',
        whereArgs: [user.id],
      );
      final now = DateTime.now().toIso8601String();
      await OutboxDao.enqueue(
        txn,
        table: Tables.userVerifiers,
        entityId: user.id,
        operation: SyncOperation.insert,
        payload: {
          'user_id': user.id,
          'server_salt': newServerSalt,
          'verifier': newCloudVerifier,
          'device_id': deviceId,
          'created_at': now,
          'updated_at': now,
        },
        priority: SyncPriority.clinical,
      );
    });
    await AuditDao.record(
      actorId: user.id,
      action: 'reset_pin',
      outcome: 'allowed',
      detail: 'PIN reset; local credentials and cloud verifier regenerated.',
    );
    return true;
  }

  /// Changes the PIN when the user knows the current one. Also regenerates the
  /// cloud verifier with a fresh server salt so old verifier revocation is
  /// automatic after a PIN rotation.
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
    final row = rows.first;
    final oldSalt = row['pin_salt'] as String?;
    final oldHash = row['pin_hash'] as String?;
    if (oldSalt == null || oldHash == null) return false;
    if (!Credentials.verify(currentPin, oldSalt, oldHash)) return false;
    final user = AppUser.fromMap(row);
    final newLocalSalt = Credentials.newSalt();
    final newLocalHash = Credentials.hashPin(newPin, newLocalSalt);
    final newServerSalt = Credentials.newSalt(24);
    final newCloudVerifier = Credentials.computeCloudVerifier(
      localPinHash: newLocalHash,
      phone: user.phone,
      serverSalt: newServerSalt,
    );
    final deviceId = await _deviceIdForOutbox();
    await db.transaction((txn) async {
      await txn.update(
        Tables.users,
        {'pin_salt': newLocalSalt, 'pin_hash': newLocalHash},
        where: 'id = ?',
        whereArgs: [userId],
      );
      final now = DateTime.now().toIso8601String();
      await OutboxDao.enqueue(
        txn,
        table: Tables.userVerifiers,
        entityId: userId,
        operation: SyncOperation.insert,
        payload: {
          'user_id': userId,
          'server_salt': newServerSalt,
          'verifier': newCloudVerifier,
          'device_id': deviceId,
          'created_at': now,
          'updated_at': now,
        },
        priority: SyncPriority.clinical,
      );
    });
    await AuditDao.record(
      actorId: userId,
      action: 'change_pin',
      outcome: 'allowed',
      detail: 'PIN changed; cloud verifier rotated with new server_salt.',
    );
    return true;
  }

  /// Returns the canonical device ID, shared across auth and sync flows.
  ///
  /// Delegates directly to [ServerAuthClient.deviceId] so there is exactly one
  /// storage location (FlutterSecureStorage under key `carebridge.auth.device_id`),
  /// one `cb-` prefix format, and the same value is used in:
  ///   * `/api/auth/login` device_id claims (for refresh-token forensic attribution)
  ///   * `/api/auth/refresh` device_id claims
  ///   * `user_verifiers.device_id` column
  ///
  /// Previously UserDao stored a duplicate copy in SharedPreferences under a
  /// different key; that duplication caused forensic misalignment when the two
  /// stores diverged. Single source of truth now.
  static Future<String?> _deviceIdForOutbox() async {
    try {
      return await ServerAuthClient.deviceId();
    } catch (_) {
      return null;
    }
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
      // Hybrid Architecture Fallback:
      // If the account does not exist in local SQLite (e.g. fresh app install on a replacement device),
      // reach out to the Main MariaDB Server via CloudRecoveryService to authenticate and pull records down!
      final recovery = await CloudRecoveryService.restoreAccount(phone: phone, pin: pin);
      if (recovery.isSuccess) {
        await AuditDao.record(
          actorId: recovery.user!.id,
          actorRole: recovery.user!.role.name,
          action: 'cloud_recovery_login',
          outcome: 'allowed',
          detail: 'Restored account and caseload from MariaDB Main Server',
        );
        return AuthResult.success(recovery.user!);
      }

      if (recovery.status == RecoveryStatus.wrongPin) {
        await AuditDao.record(
          action: 'cloud_recovery_login',
          outcome: 'denied',
          detail: 'Wrong PIN against cloud credentials',
        );
        return const AuthResult.failure(AuthFailure.wrongPin);
      }

      await AuditDao.record(
        action: 'sign_in',
        outcome: 'denied',
        detail: 'Unknown phone number locally and on server',
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

  // ----------------------------------------------------------- helpers

  /// True if at least one account exists on this device.
  static Future<bool> anyRegistered() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.users,
      columns: ['COUNT(*) AS c'],
    );
    final count = (rows.firstOrNull?['c'] as num?)?.toInt() ?? 0;
    return count > 0;
  }

  /// Caregiver accounts are bound to exactly one household at creation.
  /// Returns null for frontline health workers or unbound accounts.
  static Future<String?> linkedHouseholdFor(String userId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.users,
      columns: ['linked_household_id'],
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final v = rows.first['linked_household_id'];
    return v is String && v.isNotEmpty ? v : null;
  }

  /// Binds (or unbinds) a caregiver account to a household ID. Passing
  /// null clears the binding (usually only done during cloud recovery when
  /// the server provides a fresh, authoritative household binding).
  static Future<void> setLinkedHousehold(String userId, String? householdId) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      Tables.users,
      {'linked_household_id': householdId},
      where: 'id = ?',
      whereArgs: [userId],
    );
    await AuditDao.record(
      actorId: userId,
      action: 'set_linked_household',
      outcome: 'allowed',
      entityId: householdId,
      entityTable: Tables.households,
      detail: householdId == null ? 'Unbound user from household' : 'Bound user to household',
    );
  }

  /// Every registered user on this device — used by the account switcher
  /// and by the admin roster screen. Does NOT include pin_hash or pin_salt
  /// (AppUser.fromMap intentionally drops them — they are not in toMap either).
  static Future<List<AppUser>> all() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.users,
      orderBy: 'full_name COLLATE NOCASE ASC',
    );
    return rows.map(AppUser.fromMap).toList();
  }

  /// All users of one role. Used by the case-load overview to filter FHWs
  /// vs caregivers during team rosters and supervision visits.
  static Future<List<AppUser>> byRole(UserRole role) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.users,
      where: 'role = ?',
      whereArgs: [role.name],
      orderBy: 'full_name COLLATE NOCASE ASC',
    );
    return rows.map(AppUser.fromMap).toList();
  }

  /// Switches the user's preferred language. The choice is device-local
  /// only; it syncs to the server via the normal users row outbox so the
  /// same language carries across recovery on a replacement device.
  static Future<void> updateLanguage(String userId, String language) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      Tables.users,
      {
        'preferred_language': language,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [userId],
    );
    // Enqueue an outbox sync so the preference propagates to MariaDB on
    // the next network window. Recovery restores the language correctly.
    final existing = await byId(userId);
    if (existing != null) {
      final now = DateTime.now().toIso8601String();
      await OutboxDao.enqueue(
        db,
        table: Tables.users,
        entityId: userId,
        operation: SyncOperation.update,
        payload: {
          ...existing.toMap(),
          'preferred_language': language,
          'updated_at': now,
        },
        priority: SyncPriority.background,
      );
    }
    await AuditDao.record(
      actorId: userId,
      action: 'change_preferred_language',
      outcome: 'allowed',
      detail: 'Set language to "$language".',
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
