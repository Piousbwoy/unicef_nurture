/// Delta pull — the read half of the hybrid engine.
///
/// Push (the outbox) moves local writes up; pull moves everything the
/// signed-in caller is allowed to see back down. Nurse A registers a household
/// and it pushes; Nurse B pulls and it is searchable in her app immediately,
/// because the local caseload query is already region-scoped. This file is the
/// client half of `GET /api/pull` (see server/src/pull.js).
///
/// The contract, in one paragraph: pages are fetched until the server says
/// `has_more: false`; each page is merged in one transaction — households and
/// persons last-writer-wins on their client-written `updated_at`, visits,
/// assessments and referrals insert-if-absent (clinical history is
/// append-only, and a row that already exists locally was itself pushed, so
/// the server can only be re-offering it) — and the `server_time` of the FIRST
/// page becomes the next watermark, stored per-user in `sync_state`. The next
/// pull sends that watermark (minus a one-second overlap) as `since`; the
/// overlap plus the merge rules make re-delivery harmless, and the server owns
/// the change markers, so device clocks are only ever used for display.
///
/// Failure behaviour is deliberately boring: a pull that fails at page 3 of 5
/// has committed its earlier pages but advances nothing, so the next pull
/// re-reads the same window and the merge rules make the repeat invisible. A
/// watermark is only ever written after a pull completes end to end.
library;

import 'package:sqflite/sqflite.dart' show DatabaseExecutor;

import '../local/app_database.dart';
import '../local/preferences_store.dart';
import '../local/sync_state_dao.dart';
import '../local/user_dao.dart' show AuditDao;
import 'http_client.dart';
import 'server_auth_client.dart';

/// How a pull ended.
enum PullStatus {
  /// Every page fetched and merged; the watermark advanced.
  success,

  /// No sync server is configured. Pulling is not applicable — not an error.
  /// This device is, by choice, running standalone.
  notConfigured,

  /// The server rejected the credentials and a refresh did not help.
  unauthorized,

  /// The network failed, the answer timed out, or the reply was not a pull
  /// page. Nothing was persisted; the next trigger retries.
  unavailable,
}

/// What one pull did, for the banner, the audit log and the sync settings.
class PullReport {
  const PullReport({
    required this.status,
    this.rowsApplied = 0,
    this.rowsSkipped = 0,
    this.pages = 0,
    this.detail,
  });

  final PullStatus status;

  /// Rows inserted or refreshed locally (the merge rules decide which).
  final int rowsApplied;

  /// Rows the server offered that were already present and up to date here —
  /// the watermark overlap and the merge rules at work, not waste.
  final int rowsSkipped;

  final int pages;

  /// Human-readable context for a failure, or null on success.
  final String? detail;

  bool get isSuccess => status == PullStatus.success;

  /// Did this pull change what the user can see? Drives provider invalidation.
  bool get changedLocalData => rowsApplied > 0;

  @override
  String toString() =>
      'pull($status): $rowsApplied applied, $rowsSkipped skipped, '
      '$pages page(s)${detail == null ? '' : ' — $detail'}';
}

class PullService {
  PullService({this.minGap = const Duration(seconds: 30)});

  /// Hard ceiling on pages per session. The server caps pages at 500 rows, so
  /// this allows ~100k rows before declaring the session divergent — a
  /// runaway guard, never a realistic limit.
  static const int _maxPages = 500;

  /// Pulls are triggered eagerly — after every accepted push batch, on every
  /// connectivity flap, on sign-in. [minGap] collapses that enthusiasm: a pull
  /// requested within the gap of the last *successful* one is skipped unless
  /// [pull] is called with force. Use Duration.zero in tests.
  final Duration minGap;

  DateTime? _lastSuccessAt;
  PullReport? _lastReport;
  Future<PullReport>? _inFlight;

  /// Runs one pull session to completion.
  ///
  /// Re-entrant callers share the in-flight session rather than racing the
  /// server: the timer, a connectivity flap and a push drain landing together
  /// produce one network conversation and one report.
  Future<PullReport> pull({String? userId, bool force = false}) {
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;
    final last = _lastReport;
    if (!force &&
        last != null &&
        last.isSuccess &&
        _lastSuccessAt != null &&
        DateTime.now().difference(_lastSuccessAt!) < minGap) {
      return Future.value(last);
    }
    final run = _pull(userId: userId).whenComplete(() => _inFlight = null);
    _inFlight = run;
    return run;
  }

  Future<PullReport> _pull({String? userId}) async {
    final base = await PreferencesStore.effectiveSyncApiUrl();
    if (base.trim().isEmpty) {
      return const PullReport(status: PullStatus.notConfigured);
    }
    final baseUrl = base.trim().replaceAll(RegExp(r'/+$'), '');

    final picked = await ServerAuthClient.pickAuthorization();
    if (picked == null) {
      return const PullReport(
        status: PullStatus.unauthorized,
        detail: 'Not signed in to the sync server.',
      );
    }
    String auth = picked;

    final watermarkKey =
        SyncStateKeys.scoped(SyncStateKeys.pullWatermark, userId);
    final since = _overlapped(await SyncStateDao.read(watermarkKey));

    // Terminal states funnel through [done] so every completed attempt — and
    // only a completed attempt — lands in the audit log exactly once.
    String? actorId;
    Future<PullReport> done(PullReport report) async {
      if (report.status != PullStatus.notConfigured) {
        await AuditDao.record(
          action: 'delta pull',
          outcome: switch (report.status) {
            PullStatus.success => 'allowed',
            PullStatus.unauthorized => 'denied',
            _ => 'failed',
          },
          actorId: actorId,
          detail:
              '${report.rowsApplied} applied, ${report.rowsSkipped} skipped, '
              '${report.pages} page(s)'
              '${report.detail == null ? '' : ' — ${report.detail}'}',
        );
      }
      if (report.isSuccess) {
        _lastReport = report;
        _lastSuccessAt = DateTime.now();
      }
      return report;
    }

    try {
      var cursor = 0;
      var pages = 0;
      var applied = 0;
      var skipped = 0;
      var refreshedAuth = false;
      String? sessionWatermark;
      final columns = <String, Set<String>>{};

      while (true) {
        if (pages > _maxPages) {
          return done(PullReport(
            status: PullStatus.unavailable,
            pages: pages,
            detail: 'Pull did not converge after $_maxPages pages.',
          ));
        }

        final query = <String, String>{'cursor': '$cursor'};
        if (since != null) query['since'] = since;
        final uri =
            Uri.parse('$baseUrl/api/pull').replace(queryParameters: query);
        var reply = await PlatformHttpClient.get(
          uri,
          headers: {'Authorization': auth},
          timeout: const Duration(seconds: 25),
        );

        // An expired access token is one refresh away from working — tried
        // exactly once, so a genuinely revoked session cannot loop here.
        if (reply.statusCode == 401 && !refreshedAuth) {
          refreshedAuth = true;
          final ok = await ServerAuthClient
              .refreshAccessToken()
              .then((r) => r.isOk);
          if (ok) {
            final fresh = await ServerAuthClient.pickAuthorization();
            if (fresh != null) {
              auth = fresh;
              reply = await PlatformHttpClient.get(
                uri,
                headers: {'Authorization': auth},
                timeout: const Duration(seconds: 25),
              );
            }
          }
        }

        if (reply.statusCode == 401 || reply.statusCode == 403) {
          return done(PullReport(
            status: PullStatus.unauthorized,
            pages: pages,
            detail:
                'The server rejected this device\u2019s credentials '
                '(HTTP ${reply.statusCode}). Sign in again.',
          ));
        }

        final body = reply.jsonBody;
        if (body == null) {
          return done(PullReport(
            status: PullStatus.unavailable,
            pages: pages,
            detail:
                'The server answer was not JSON (HTTP ${reply.statusCode}).',
          ));
        }
        if (reply.statusCode != 200 || body['ok'] != true) {
          return done(PullReport(
            status: PullStatus.unavailable,
            pages: pages,
            detail: body['error'] is String
                ? body['error'] as String
                : 'The server answered HTTP ${reply.statusCode}.',
          ));
        }

        // The first page anchors the session: its server_time is the only
        // clock reading this pull will trust, however long paging takes.
        final serverTime = body['server_time'];
        if (serverTime is! String || serverTime.isEmpty) {
          return done(PullReport(
            status: PullStatus.unavailable,
            pages: pages,
            detail: 'The server did not include server_time; the watermark '
                'cannot be advanced safely.',
          ));
        }
        sessionWatermark ??= serverTime;
        final scopedTo = body['scoped_to'];
        if (actorId == null && scopedTo is Map) {
          final uid = scopedTo['user_id'];
          if (uid is String && uid.isNotEmpty) actorId = uid;
        }

        final data = body['data'];
        if (data is! Map<String, dynamic>) {
          return done(PullReport(
            status: PullStatus.unavailable,
            pages: pages,
            detail: 'Malformed pull page: data is not an object.',
          ));
        }

        final db = await AppDatabase.instance.database;
        final merged =
            await db.transaction((txn) => _applyPage(txn, data, columns));
        applied += merged.applied;
        skipped += merged.skipped;
        pages++;

        if (body['has_more'] != true) break;
        final next = body['next_cursor'];
        if (next is! int || next <= cursor) {
          return done(PullReport(
            status: PullStatus.unavailable,
            pages: pages,
            detail: 'Server pagination did not advance.',
          ));
        }
        cursor = next;
      }

      // The watermark moves only now — after every page is safely merged. A
      // pull that died mid-way left the old watermark standing, so the next
      // pull re-reads the same window and the merge rules make the repeat
      // invisible.
      await SyncStateDao.write(watermarkKey, sessionWatermark);
      await SyncStateDao.write(
        SyncStateKeys.scoped(SyncStateKeys.lastPullAt, userId),
        DateTime.now().toUtc().toIso8601String(),
      );
      await SyncStateDao.write(
        SyncStateKeys.scoped(SyncStateKeys.lastPullRows, userId),
        '$applied',
      );

      return done(PullReport(
        status: PullStatus.success,
        rowsApplied: applied,
        rowsSkipped: skipped,
        pages: pages,
      ));
    } on HttpFailure catch (e) {
      return done(PullReport(status: PullStatus.unavailable, detail: e.message));
    } catch (e) {
      return done(PullReport(status: PullStatus.unavailable, detail: '$e'));
    }
  }

  /// The watermark is sent back with a one-second overlap: rows stamped in
  /// the watermark's own second are re-delivered, the merge rules shrug, and
  /// a second-precision marker can never strand a row written in the same
  /// second as the watermark itself.
  String? _overlapped(String? watermark) {
    if (watermark == null || watermark.isEmpty) return null;
    final t = DateTime.tryParse(watermark);
    if (t == null) return null; // unparsable → a full pull is the safe fallback
    return t.toUtc().subtract(const Duration(seconds: 1)).toIso8601String();
  }

  /// Merges one page inside the caller's transaction. Order matters: parents
  /// before children, exactly as the server streams them, so the foreign keys
  /// (left ON, unlike the server's tolerant ingest) do real work.
  Future<({int applied, int skipped})> _applyPage(
    DatabaseExecutor txn,
    Map<String, dynamic> data,
    Map<String, Set<String>> columns,
  ) async {
    await _warmColumns(txn, columns);
    var applied = 0;
    var skipped = 0;

    for (final row in _rows(data[Tables.households])) {
      if (await _mergeLww(txn, Tables.households, row, columns)) {
        applied++;
      } else {
        skipped++;
      }
    }
    for (final row in _rows(data[Tables.persons])) {
      if (await _mergeLww(txn, Tables.persons, row, columns)) {
        applied++;
      } else {
        skipped++;
      }
    }
    for (final table in const [
      Tables.visits,
      Tables.assessments,
      Tables.referrals,
    ]) {
      for (final row in _rows(data[table])) {
        if (await _mergeIfAbsent(txn, table, row, columns)) {
          applied++;
        } else {
          skipped++;
        }
      }
    }
    final self = data[Tables.users];
    if (self is Map<String, dynamic>) {
      if (await _mergeSelfUser(txn, self)) {
        applied++;
      } else {
        skipped++;
      }
    }
    return (applied: applied, skipped: skipped);
  }

  List<Map<String, dynamic>> _rows(Object? value) => value is List
      ? value.whereType<Map<String, dynamic>>().toList(growable: false)
      : const [];

  Future<void> _warmColumns(
    DatabaseExecutor txn,
    Map<String, Set<String>> cache,
  ) async {
    for (final table in const [
      Tables.households,
      Tables.persons,
      Tables.visits,
      Tables.assessments,
      Tables.referrals,
      Tables.users,
    ]) {
      if (cache.containsKey(table)) continue;
      try {
        final info = await txn.rawQuery('PRAGMA table_info($table)');
        cache[table] = info.map((r) => r['name'] as String).toSet();
      } catch (_) {
        cache[table] = const {}; // merges for this table become honest no-ops
      }
    }
  }

  /// Intersects a server row with this device's actual columns. The two
  /// schemas mirror each other, but the server row is nullable where the
  /// local schema promises a NOT NULL default (visits.reasons) — dropping the
  /// null keys lets SQLite apply exactly the default the local schema
  /// declares, instead of trying to write NULL into it.
  Map<String, dynamic>? _localColumns(
    String table,
    Map<String, dynamic> row,
    Map<String, Set<String>> cache,
  ) {
    final cols = cache[table];
    if (cols == null) return null;
    final map = <String, dynamic>{};
    for (final entry in row.entries) {
      if (entry.value != null && cols.contains(entry.key)) {
        map[entry.key] = entry.value;
      }
    }
    return map;
  }

  /// Households and persons: last-writer-wins on the client-written
  /// `updated_at`. An incoming row replaces the local one only when it is not
  /// older — ties included, so a push-then-pull round trip converges instead
  /// of arguing about who wrote last.
  Future<bool> _mergeLww(
    DatabaseExecutor txn,
    String table,
    Map<String, dynamic> row,
    Map<String, Set<String>> columns,
  ) async {
    final id = row['id'];
    if (id is! String || id.isEmpty) return false;
    final map = _localColumns(table, row, columns);
    if (map == null || map.isEmpty) return false;

    final local =
        await txn.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
    if (local.isEmpty) {
      try {
        await txn.insert(table, map);
        return true;
      } catch (_) {
        // A parent this device has not yet received (outside its scope, or
        // unchanged since before its watermark). Skipped, not lost: the next
        // full pull heals it.
        return false;
      }
    }
    final incoming = (row['updated_at'] as String?) ?? '';
    final current = (local.first['updated_at'] as String?) ?? '';
    if (incoming.isEmpty || current.compareTo(incoming) >= 0) return false;
    try {
      await txn.update(table, map, where: 'id = ?', whereArgs: [id]);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Visits, assessments and referrals: insert-if-absent. A row that already
  /// exists locally was itself pushed from this ecosystem, and these tables
  /// are append-only by design — the server can only be re-offering what this
  /// device already has, which the watermark overlap makes routine.
  Future<bool> _mergeIfAbsent(
    DatabaseExecutor txn,
    String table,
    Map<String, dynamic> row,
    Map<String, Set<String>> columns,
  ) async {
    final id = row['id'];
    if (id is! String || id.isEmpty) return false;
    final existing = await txn.query(
      table,
      columns: const ['id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (existing.isNotEmpty) return false;
    final map = _localColumns(table, row, columns);
    if (map == null || map.isEmpty) return false;
    // Pulled rows are already on the server; they must never look locally
    // dirty, or the outbox would push them straight back.
    if (map.containsKey('sync_state')) map['sync_state'] = 'synced';
    try {
      await txn.insert(table, map);
      return true;
    } catch (_) {
      // FK parent missing on a delta window — the next full pull heals it.
      return false;
    }
  }

  /// The caller's own users row: a profile refresh, never a credential
  /// overwrite. pin_hash and pin_salt never leave the device, so the server
  /// row cannot carry them — and a locally fresh household binding must not
  /// be wiped by a server row that predates the push that would have carried
  /// it.
  Future<bool> _mergeSelfUser(
    DatabaseExecutor txn,
    Map<String, dynamic> user,
  ) async {
    final id = user['id'];
    if (id is! String || id.isEmpty) return false;
    final profile = <String, dynamic>{
      'full_name': user['full_name'],
      'phone': user['phone'],
      'role': user['role'],
      'region': user['region'],
      'district': user['district'],
      'community': user['community'],
      'chps_zone': user['chps_zone'],
      'facility_name': user['facility_name'],
      'staff_id': user['staff_id'],
      'preferred_language': user['preferred_language'],
      'created_at': user['created_at'],
    };
    final local = await txn.query(
      Tables.users,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (local.isEmpty) {
      final full = <String, dynamic>{'id': id, ...profile};
      final binding = user['linked_household_id'];
      if (binding is String && binding.isNotEmpty) {
        full['linked_household_id'] = binding;
      }
      try {
        await txn.insert(Tables.users, full);
        return true;
      } catch (_) {
        return false;
      }
    }
    final serverBinding = user['linked_household_id'];
    if (serverBinding is String && serverBinding.isNotEmpty) {
      profile['linked_household_id'] = serverBinding;
    } else if (local.first['linked_household_id'] == null) {
      profile['linked_household_id'] = null;
    }
    try {
      await txn.update(Tables.users, profile, where: 'id = ?', whereArgs: [id]);
      return true;
    } catch (_) {
      return false;
    }
  }
}
