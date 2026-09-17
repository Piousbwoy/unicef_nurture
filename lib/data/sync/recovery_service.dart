/// Cloud recovery service for our Hybrid Architecture.
///
/// When an existing user loses their handset or switches to a replacement device,
/// their local SQLite database is completely empty upon installation. Rather than
/// forcing a duplicate account creation (which creates data fragmentation in the
/// CHPS zone), this service reaches out to the Main MariaDB Server via our REST API.
///
/// **The Two-Step Hybrid Recovery Flow:**
/// 1. Profile & Credential Verification (`POST /api/restore/lookup`):
///    Retrieves the user profile metadata along with their `pin_salt` and `pin_hash`
///    from MariaDB. The local device executes `Credentials.verify` to confirm identity.
/// 2. Downstream Caseload Ingest (`GET /api/restore/caseload`):
///    Once identity is verified locally, the service requests all households,
///    persons (mothers & children), visits, assessments, and referrals assigned to
///    this worker or family from MariaDB and performs atomic batch upserts into SQLite.
///
/// **Demo & Field Trial Mode:**
/// The automated simulation of cloud restoration runs ONLY when the app is
/// compiled with `--dart-define=DEMO_MODE=true`. In every other build this
/// service is strictly honest: with no server configured, an unknown phone is
/// told to register (or configure sync); with a server configured, the real
/// network outcome — success, wrong PIN, or failure — is shown verbatim. No
/// fabricated accounts, ever: a fabricated "restored" user shows a name that
/// is not the worker's and its records never sync back to MariaDB.
library;

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../domain/entities/core.dart';
import '../../domain/enums.dart';
import '../local/app_database.dart';
import '../local/preferences_store.dart';
import '../local/user_dao.dart';
import 'http_client.dart';
import 'server_auth_client.dart';

/// When `true`, a transient network error during cloud recovery falls back to a
/// realistic simulation of profile + caseload restoration. Used exclusively for
/// Northern Region field demos, web pitches, and integration environments where
/// a real district VM is not reachable. In production builds this MUST be
/// `false` — a user on a replacement device who gets a network error must see
/// the error, not be silently signed into a fabricated "restored" account whose
/// records will never sync back to the real MariaDB.
///
/// Enable from the command line:
/// `flutter run --dart-define=DEMO_MODE=true`
const bool kDemoMode = bool.fromEnvironment(
  'DEMO_MODE',
  defaultValue: false,
);

enum RecoveryStatus {
  success,
  notFound,
  wrongPin,
  networkError,
}

class RecoveryResult {
  const RecoveryResult({
    required this.status,
    this.user,
    this.restoredRecordsCount = 0,
    this.message,
  });

  final RecoveryStatus status;
  final AppUser? user;
  final int restoredRecordsCount;
  final String? message;

  bool get isSuccess => status == RecoveryStatus.success && user != null;
}

abstract final class CloudRecoveryService {
  static Future<RecoveryResult> restoreAccount({
    required String phone,
    required String pin,
  }) async {
    final cleanPhone = phone.trim();
    final baseUrl = await PreferencesStore.effectiveSyncApiUrl();

    // If a live Main MariaDB Server URL is configured, attempt actual network
    // recovery. Every outcome is returned to the caller verbatim: the user
    // must see the real failure reason on a blank replacement device, because
    // silently substituting fake records would produce phantom caseloads that
    // never sync to MariaDB and are lost on the next sign-out.
    if (baseUrl.isNotEmpty) {
      final outcome = await _restoreFromLiveServer(cleanPhone, pin, baseUrl);
      if (!kDemoMode) return outcome;
      // In DEMO MODE only: a transient networkError falls through to
      // _simulateCloudRecovery so pitch environments without a district VM
      // can still demonstrate the full recovery flow.
      if (outcome.status == RecoveryStatus.networkError) {
        return _simulateCloudRecovery(cleanPhone, pin);
      }
      return outcome;
    }

    // No server URL is configured. Production builds tell the truth: there is
    // no account on this device and nowhere to recover one from. Only an
    // explicit `--dart-define=DEMO_MODE=true` build opts in to the simulation
    // — a silently fabricated "restored" identity used to leave the FHW home
    // screen showing a name that was never theirs.
    if (kDemoMode) return _simulateCloudRecovery(cleanPhone, pin);
    return const RecoveryResult(
      status: RecoveryStatus.notFound,
      message: 'No account exists on this device, and no sync server is '
          'configured for cloud recovery. Register a new account, or set up '
          'sync in Me → Sync settings to restore from the district server.',
    );
  }

  static Future<RecoveryResult> _restoreFromLiveServer(
    String phone,
    String pin,
    String baseUrl,
  ) async {
    try {
      // NEW Step 1: Authenticate to server first. This proves PIN correctness and
      // returns a per-user JWT used for all subsequent recovery endpoints.
      // PIN verification uses a zero-knowledge challenge-response flow: the
      // client first fetches a per-user server_salt, then locally computes a
      // domain-separated 120k-iter HMAC Cloud Verifier from pin+phone+salt,
      // and posts only the verifier_response (NEVER the raw PIN, on-device
      // pin_hash, or pin_salt) to /api/auth/login. Server constant-time
      // compares against the isolated user_verifiers table. Legacy accounts
      // are silently migrated on first successful auth; pin_hash/pin_salt
      // are NEVER sent back to the client in any response.
      final login = await ServerAuthClient.signIn(phone: phone, pin: pin);
      if (!login.isOk) {
        final err = (login.error ?? '').toLowerCase();
        if (err.contains('too many') || err.contains('locked')) {
          return RecoveryResult(
            status: RecoveryStatus.networkError,
            message: login.error,
          );
        }
        if (err.contains('credentials') || err.contains('wrong') || err.contains('invalid pin') || err.contains('pin incorrect')) {
          return RecoveryResult(
            status: RecoveryStatus.wrongPin,
            message: login.error ?? 'That PIN does not match your server credentials.',
          );
        }
        if (err.contains('network') || err.contains('timed out')) {
          return RecoveryResult(
            status: RecoveryStatus.networkError,
            message: login.error,
          );
        }
        // Anything else is probably "no profile" — treat as notFound so UI redirects
        // to register rather than a wrong-pin loop.
        return RecoveryResult(
          status: RecoveryStatus.notFound,
          message: login.error ?? 'No profile found for this phone on the server.',
        );
      }

      final accessToken = login.tokens!.accessToken;
      final fromLogin = login.user;

      // Step 2: Now hit /restore/lookup with the JWT. The server completely
      // ignores any phone in the POST body; it returns the scrubbed profile of
      // whoever owns the JWT sub claim. pin_hash/pin_salt will NOT be in the
      // response (they were stripped server-side).
      final lookupReply = await PlatformHttpClient.post(
        Uri.parse('$baseUrl/api/restore/lookup'),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode({'phone': phone}),
        timeout: const Duration(seconds: 15),
      );

      if (lookupReply.statusCode == 404) {
        return const RecoveryResult(
          status: RecoveryStatus.notFound,
          message: 'No profile found on the Main Server for this phone number.',
        );
      }
      if (lookupReply.statusCode != 200) {
        return RecoveryResult(
          status: RecoveryStatus.networkError,
          message: 'Server returned HTTP ${lookupReply.statusCode}: ${lookupReply.bodyText}',
        );
      }

      final userMap =
          (lookupReply.jsonBody?['user'] ?? fromLogin) as Map<String, dynamic>?;
      if (userMap == null) {
        return const RecoveryResult(
          status: RecoveryStatus.notFound,
          message: 'Invalid profile payload from server.',
        );
      }

      // Local PIN storage for offline-first sign-in after this recovery. We
      // regenerate credentials locally (new salt, HMAC hash) rather than ever
      // downloading them from the server. We know the PIN is correct because
      // the server /api/auth/login endpoint returned a JWT above — that is the
      // zero-knowledge proof of correctness.
      final localSalt = Credentials.newSalt();
      final localHash = Credentials.hashPin(pin, localSalt);

      final user = AppUser.fromMap(userMap);
      final db = await AppDatabase.instance.database;

      var restoredCount = 0;

      // Step 3: Fetch clinical caseload — server ignores querystring params; scope
      // derived entirely from the JWT (region/district/community/created_by for
      // FHWs, linked_household_id for caregivers). Response has scoped_to meta.
      // The reply body is fully read BEFORE the transaction opens so no network
      // work ever happens inside a SQLite transaction.
      final caseloadReply = await PlatformHttpClient.get(
        Uri.parse('$baseUrl/api/restore/caseload'),
        headers: {'Authorization': 'Bearer $accessToken'},
        timeout: const Duration(seconds: 20),
      );

      Map<String, dynamic>? caseloadData;
      if (caseloadReply.statusCode == 200) {
        final data = caseloadReply.jsonBody?['data'];
        if (data is Map<String, dynamic>) caseloadData = data;
      }

      // The caregiver household binding is THE thing that makes a recovered
      // caregiver account work: it is what scopes every caregiver query to
      // their family. AppUser.toMap() deliberately never carries it (it is a
      // device-local column), so it must be inserted explicitly here — without
      // this a recovered caregiver signs in with no family at all, and the app
      // looks dead.
      final rawBinding = userMap['linked_household_id'];
      final linkedHouseholdId =
          rawBinding is String && rawBinding.isNotEmpty ? rawBinding : null;

      // The server rows are `SELECT *`-shaped: they can carry server-owned
      // bookkeeping columns the local schema does not have — pull_updated_at
      // since the delta-pull work, and whatever the server grows next — plus
      // NULLs where the local schema promises defaults. Writing them verbatim
      // is how cloud recovery died in the field: "table households has no
      // column named pull_updated_at" the moment a caregiver with a caseload
      // tried to come back. Intersect every row with the local columns
      // first, exactly as the delta-pull path does. The PRAGMA reads happen
      // before the transaction opens, keeping the same no-DB-work-in-prepare
      // rule as the network read above. (The server also strips the marker
      // from caseload replies; the client does not have to trust that.)
      final localColumns = <String, Set<String>>{};
      if (caseloadData != null) {
        for (final table in [
          Tables.households,
          Tables.persons,
          Tables.assessments,
          Tables.visits,
          Tables.referrals,
        ]) {
          try {
            localColumns[table] = (await db.rawQuery('PRAGMA table_info($table)'))
                .map((r) => r['name'] as String)
                .toSet();
          } catch (_) {
            localColumns[table] = const {}; // that table merges as an honest no-op
          }
        }
      }

      await db.transaction((txn) async {
        await txn.insert(
          Tables.users,
          {
            ...user.toMap(),
            'pin_hash': localHash,
            'pin_salt': localSalt,
            'linked_household_id': linkedHouseholdId,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        restoredCount++;

        if (caseloadData != null) {
          for (final table in [
            Tables.households,
            Tables.persons,
            Tables.assessments,
            Tables.visits,
            Tables.referrals,
          ]) {
            final columns = localColumns[table];
            if (columns == null || columns.isEmpty) continue;
            final rows = caseloadData[table] as List<dynamic>? ?? [];
            for (final r in rows) {
              if (r is! Map<String, dynamic>) continue;
              final map = <String, dynamic>{
                for (final e in r.entries)
                  if (e.value != null && columns.contains(e.key))
                    e.key: e.value,
              };
              final id = map['id'];
              if (id is! String || id.isEmpty) {
                // Nothing to merge on — never guess an identity.
                continue;
              }
              await txn.insert(
                table,
                map,
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
              restoredCount++;
            }
          }
        }
      });

      // Belt and braces: re-assert the binding outside the insert so it also
      // survives INSERT OR REPLACE against the phone-unique index, and so the
      // binding is visible in the audit trail.
      await UserDao.setLinkedHousehold(user.id, linkedHouseholdId);

      return RecoveryResult(
        status: RecoveryStatus.success,
        user: user,
        restoredRecordsCount: restoredCount,
        message: 'Cloud restoration completed. Restored $restoredCount records from MariaDB.',
      );
    } catch (e) {
      return RecoveryResult(
        status: RecoveryStatus.networkError,
        message: 'Network error during cloud recovery: ${e.toString()}',
      );
    }
  }

  /// Interactive simulation for field trials and web demos where MariaDB is
  /// offline. Reachable ONLY under `--dart-define=DEMO_MODE=true` — see the
  /// gates in [restoreAccount]; production builds never fabricate an identity.
  static Future<RecoveryResult> _simulateCloudRecovery(String phone, String pin) async {
    await Future<void>.delayed(const Duration(milliseconds: 1400));

    // For demonstration, if user types PIN shorter than 4 digits, reject as invalid
    if (pin.length != 4 || int.tryParse(pin) == null) {
      return const RecoveryResult(
        status: RecoveryStatus.wrongPin,
        message: 'Please enter your authentic 4-digit security PIN.',
      );
    }

    final salt = Credentials.newSalt();
    final hash = Credentials.hashPin(pin, salt);
    final now = DateTime.now();

    // Reconstruct a realistic frontline health worker or caregiver profile
    final isWorker = phone.startsWith('02') || phone.startsWith('05');
    final user = AppUser(
      id: 'recovered-$phone-${now.millisecondsSinceEpoch}',
      fullName: isWorker ? 'Nurse Fatima (Cloud Restored)' : 'Aisha Ibrahim (Cloud Restored)',
      phone: phone,
      role: isWorker ? UserRole.frontlineHealthWorker : UserRole.caregiver,
      region: 'Northern',
      district: 'Savelugu Municipal',
      community: 'Diare CHPS',
      chpsZone: 'Diare Zone B',
      facilityName: 'Diare Health Centre',
      staffId: isWorker ? 'GHS-NOR-8821' : null,
      preferredLanguage: 'Dagbani',
      createdAt: now.subtract(const Duration(days: 90)),
    );

    final db = await AppDatabase.instance.database;
    var count = 1;
    final hhId = 'recovery-hh-$phone';

    await db.transaction((txn) async {
      // 1. Restore User Row
      await txn.insert(
        Tables.users,
        {
          ...user.toMap(),
          'pin_hash': hash,
          'pin_salt': salt,
          'linked_household_id': isWorker ? null : hhId,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // 2. Seed restored sample household to showcase downstream recovery
      await txn.insert(
        Tables.households,
        {
          'id': hhId,
          'name': isWorker ? 'Savelugu Recovered Caseload' : 'Ibrahim & Aisha Household',
          'region': 'Northern',
          'district': 'Savelugu Municipal',
          'community': 'Diare CHPS',
          'created_by': user.id,
          'head_name': isWorker ? 'Multiple Enrolled Families' : 'Ibrahim Yakutu',
          'contact_phone': phone,
          'latitude': 9.6241,
          'longitude': -0.8322,
          'family_size': 6,
          'has_valid_nhis': 1,
          'walking_minutes_to_facility': 18,
          'landmark': 'Near Diare Central Mosque',
          'created_at': now.subtract(const Duration(days: 45)).toIso8601String(),
          'updated_at': now.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      count++;

      // 3. Seed restored sample family members (Persons)
      await txn.insert(
        Tables.persons,
        {
          'id': 'person-mother-$phone',
          'household_id': hhId,
          'full_name': 'Aisha Ibrahim',
          // Must be a real ClientType name: the register reader maps stored
          // names back onto the enum, and a legacy alias used to crash the
          // AI Triage tab with "Bad state: No element".
          'client_type': 'pregnantWoman',
          'sex': 'female',
          'date_of_birth': '1998-04-12',
          'age_years_approx': 27,
          'phone': phone,
          'mother_id': null,
          'is_dob_estimated': 0,
          'nhis_number': 'NH-84920193-4',
          'created_at': now.subtract(const Duration(days: 45)).toIso8601String(),
          'updated_at': now.toIso8601String(),
          'is_active': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      count++;

      await txn.insert(
        Tables.persons,
        {
          'id': 'person-child-$phone',
          'household_id': hhId,
          'full_name': 'Zainab Ibrahim (Recovered)',
          'client_type': 'childUnderFive',
          'sex': 'female',
          'date_of_birth': now.subtract(const Duration(days: 120)).toIso8601String(),
          'age_years_approx': 0,
          'phone': null,
          'mother_id': 'person-mother-$phone',
          'is_dob_estimated': 0,
          'nhis_number': null,
          'created_at': now.subtract(const Duration(days: 45)).toIso8601String(),
          'updated_at': now.toIso8601String(),
          'is_active': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      count++;
    });

    return RecoveryResult(
      status: RecoveryStatus.success,
      user: user,
      restoredRecordsCount: count,
      message: 'Restored account and $count clinical records from MariaDB Main Server.',
    );
  }
}
