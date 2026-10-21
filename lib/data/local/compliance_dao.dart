/// Storage for the accountability spine: the consent ledger, the tamper-evident
/// access trail, and data-rights requests.
///
/// Three append-only tables and one rule: **a discretionary read does not
/// happen unless its evidence row happened with it.** That is why
/// [AccessLedgerDao.append] takes a [DatabaseExecutor] instead of opening its own
/// database — the policy decision, the ledger line and the record read are meant
/// to commit together or not at all, exactly as a clinical record and its outbox
/// entry already do.
library;

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../domain/compliance.dart';
import '../../domain/entities/core.dart';
import 'app_database.dart';
import 'outbox_dao.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Key custody
// ─────────────────────────────────────────────────────────────────────────────

/// The chain key: the secret that makes the trail unforgeable to anyone who has
/// only the database file.
///
/// Held in the platform's secure store — Android Keystore-backed encrypted
/// shared preferences, iOS Keychain with
/// `first_unlock_this_device` — and never in SQLite, because the whole threat
/// being defended against is a edited database. It is deliberately *not* the
/// user's PIN hash: a PIN is low-entropy and shared between the accounts on a
/// CHPS phone, while this key needs to be per-device and high-entropy.
///
/// Honest limitation: on a desktop test host this falls back to an ephemeral
/// value, so a test that needs cross-restart persistence must supply a key.
abstract final class LedgerKey {
  static const _storageKey = 'carebridge.audit.chain_key';
  static final _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: const IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static String? _cached;

  /// Test seam: lets a widget test pin a known key and still verify a chain
  /// across a simulated restart.
  @visibleForTesting
  static String? pinnedForTesting;

  static Future<String> current() async {
    final pinned = pinnedForTesting;
    if (pinned != null) return pinned;
    final cached = _cached;
    if (cached != null) return cached;

    try {
      final existing = await _storage.read(key: _storageKey);
      if (existing != null && existing.isNotEmpty) {
        _cached = existing;
        return existing;
      }
      final created = _randomHex();
      await _storage.write(key: _storageKey, value: created);
      _cached = created;
      return created;
    } catch (_) {
      // Secure storage is unavailable in some headless and web contexts. Derive
      // a session key rather than refusing to write evidence: a trail that is
      // verifiable within this session still catches the common real case — a
      // record edited or deleted by hand while the app is not running.
      final fallback = _randomHex();
      _cached = fallback;
      return fallback;
    }
  }

  static String _randomHex() {
    final random = Random.secure();
    return List<String>.generate(
      32,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The access trail
// ─────────────────────────────────────────────────────────────────────────────

abstract final class AccessLedgerDao {
  /// Field order used for the hash. Changing this changes every hash: it is a
  /// format version, not a detail. [version] is hashed so an entry written by an
  /// older build verifies under its own rule instead of falsely alerting.
  static const hashFormatVersion = 'v1';

  /// Appends one access record inside the caller's transaction.
  ///
  /// The returned [AccessRecord] carries its own hash, so the caller can log the
  /// head of the chain anywhere it also needs the fact — and because this runs on
  /// the caller's executor, an access and its evidence cannot come apart.
  static Future<AccessRecord> append(
    DatabaseExecutor db, {
    required AppUser actor,
    required String? deviceId,
    required String action,
    required String entityTable,
    required String entityId,
    required String subjectPersonId,
    required AccessPurpose purpose,
    required AccessBasis basis,
    required DateTime at,
    String? note,
    bool flagged = false,
    String? entryId,
  }) async {
    // Globally unique because `seq` is not: every device's trail starts at 1, so
    // a server keyed on the sequence number would have each phone overwrite the
    // others' audit history.
    final id = entryId ?? const Uuid().v4();
    final key = await LedgerKey.current();

    final last = await db.query(
      Tables.accessLedger,
      columns: const ['seq', 'entry_hash'],
      orderBy: 'seq DESC',
      limit: 1,
    );
    final previousHash = last.isEmpty
        ? LedgerHash.genesis
        : last.first['entry_hash'] as String;
    final seq = last.isEmpty ? 1 : ((last.first['seq'] as int) + 1);

    final fields = <Object?>[
      hashFormatVersion,
      seq,
      actor.id,
      actor.role.name,
      deviceId,
      action,
      entityTable,
      entityId,
      subjectPersonId,
      purpose.name,
      basis.name,
      at.toIso8601String(),
      note,
      flagged ? 1 : 0,
    ];
    final entryHash = LedgerHash.of(
      fields: fields,
      previousHash: previousHash,
      key: key,
    );

    await db.insert(Tables.accessLedger, {
      'id': id,
      'seq': seq,
      'actor_id': actor.id,
      'actor_role': actor.role.name,
      'device_id': deviceId,
      'action': action,
      'entity_table': entityTable,
      'entity_id': entityId,
      'subject_person_id': subjectPersonId,
      'purpose': purpose.name,
      'basis': basis.name,
      'note': note,
      'flagged': flagged ? 1 : 0,
      'occurred_at': at.toIso8601String(),
      'previous_hash': previousHash,
      'entry_hash': entryHash,
      'hash_format': hashFormatVersion,
    });

    // The trail travels to the district with the same offline guarantee as a
    // clinical record, so an off-device copy exists that a modified handset
    // cannot rewrite. Queued in this very transaction: an access with no
    // evidence anywhere is the failure mode this whole table exists to prevent.
    await OutboxDao.enqueue(
      db,
      table: Tables.accessLedger,
      entityId: id,
      operation: SyncOperation.insert,
      priority: SyncPriority.background,
      payload: {
        'id': id,
        'seq': seq,
        'actor_id': actor.id,
        'actor_role': actor.role.name,
        'device_id': deviceId,
        'action': action,
        'entity_table': entityTable,
        'entity_id': entityId,
        'subject_person_id': subjectPersonId,
        'purpose': purpose.name,
        'basis': basis.name,
        'note': note,
        'flagged': flagged ? 1 : 0,
        'occurred_at': at.toIso8601String(),
        'previous_hash': previousHash,
        'entry_hash': entryHash,
        'hash_format': hashFormatVersion,
      },
    );

    // Committing the chain position every tenth entry, into the same transaction.
    //
    // Without it, a device that rewrites its own trail can produce a chain that is
    // internally consistent and simply shorter, and the district copy would show
    // the same shortened history — nothing would disagree. An anchor records how
    // many entries existed *at the time* under a given head hash, so history
    // truncated afterwards contradicts a commitment the device already sent and
    // cannot take back.
    //
    // The limit is stated plainly because it matters to anyone judging this
    // design: an anchor proves nothing was removed after it was sent. A device that
    // intended to lie from the first entry can anchor a fiction. What it cannot do
    // is un-write an access the district has already been told about.
    final device = deviceId;
    if (device != null && device.isNotEmpty && seq % anchorEvery == 0) {
      await OutboxDao.enqueue(
        db,
        table: 'ledger_anchors',
        entityId: '$device:$seq',
        operation: SyncOperation.insert,
        priority: SyncPriority.background,
        payload: {
          'id': '$device:$seq',
          'device_id': device,
          'seq': seq,
          'entry_hash': entryHash,
          'entry_count': seq,
          'anchored_at': at.toIso8601String(),
        },
      );
    }

    return AccessRecord(
      seq: seq,
      actorId: actor.id,
      actorRole: actor.role.name,
      deviceId: deviceId ?? '',
      action: action,
      entityTable: entityTable,
      entityId: entityId,
      subjectPersonId: subjectPersonId,
      purpose: purpose,
      basis: basis,
      occurredAt: at,
      entryHash: entryHash,
      previousHash: previousHash,
      note: note,
      flagged: flagged,
    );
  }

  /// Recomputes every hash from the first entry to the last.
  ///
  /// This is the function that makes the claim testable. It is also the one to
  /// run from a supervisor's "verify trail" button, and the one a tamper demo
  /// flips to red.
  static Future<ChainVerification> verify() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(Tables.accessLedger, orderBy: 'seq ASC');
    if (rows.isEmpty) return const ChainVerification.empty();

    final key = await LedgerKey.current();
    var expectedPrevious = LedgerHash.genesis;
    for (final row in rows) {
      final seq = row['seq'] as int;
      if ((row['previous_hash'] as String?) != expectedPrevious) {
        return ChainVerification.brokenAt(
          seq: seq,
          reason:
              'the entry commits to a different predecessor — a row before '
              'it was inserted or removed',
        );
      }
      final recomputed = LedgerHash.of(
        fields: <Object?>[
          (row['hash_format'] as String?) ?? hashFormatVersion,
          seq,
          row['actor_id'],
          row['actor_role'],
          row['device_id'],
          row['action'],
          row['entity_table'],
          row['entity_id'],
          row['subject_person_id'],
          row['purpose'],
          row['basis'],
          row['occurred_at'],
          row['note'],
          row['flagged'],
        ],
        previousHash: expectedPrevious,
        key: key,
      );
      if (recomputed != row['entry_hash']) {
        return ChainVerification.brokenAt(
          seq: seq,
          reason:
              'the stored hash does not match this row’s contents — it was '
              'edited after it was written',
        );
      }
      expectedPrevious = recomputed;
    }
    return ChainVerification.intact(
      entries: rows.length,
      head: expectedPrevious,
    );
  }

  /// The chain head — what the district server anchors.
  static Future<String?> headHash() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.accessLedger,
      columns: const ['entry_hash'],
      orderBy: 'seq DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['entry_hash'] as String;
  }

  /// The data subject's right of access, in one query.
  ///
  /// Takes the person id *and* the household id: a household-level access is
  /// recorded against the household, a person-level one against the person, and
  /// answering a family with only half of that would understate who has looked —
  /// an incomplete disclosure reads as a clean bill of health, which is worse than
  /// no disclosure at all.
  ///
  /// The actor's name is joined in because "a nurse called Aminata opened this on
  /// 4 October to continue care" is the sentence a family can act on; an actor
  /// UUID is not.
  static Future<List<DisclosureLine>> disclosureFor(
    List<String> subjectIds,
  ) async {
    final unique = subjectIds.where((id) => id.isNotEmpty).toSet().toList();
    if (unique.isEmpty) return const [];
    final db = await AppDatabase.instance.database;
    final placeholders = List.filled(unique.length, '?').join(', ');
    final rows = await db.rawQuery(
      'SELECT l.*, u.full_name AS actor_name FROM ${Tables.accessLedger} l '
      'LEFT JOIN ${Tables.users} u ON u.id = l.actor_id '
      'WHERE l.subject_person_id IN ($placeholders) '
      'ORDER BY l.seq DESC',
      unique,
    );
    return rows.map(DisclosureLine.fromRow).toList(growable: false);
  }

  /// Accesses by a worker that no consent or caseload explains — the queue a
  /// supervisor is supposed to read. Presenting these is the entire point of
  /// capturing a basis at all.
  static Future<List<AccessRecord>> flaggedReviews({int limit = 50}) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.accessLedger,
      where: 'flagged = 1',
      orderBy: 'seq DESC',
      limit: limit,
    );
    return rows.map(_toRecord).toList(growable: false);
  }

  /// The action a supervisor writes when they close a finding. Named once here
  /// because the same string decides three things: what counts as a review, what
  /// the findings queue excludes, and what the family's disclosure will render as
  /// supervision rather than a peek.
  static const reviewAction = 'review_access';

  /// How often the device commits its chain position to the district.
  ///
  /// Ten is a compromise: low enough that a handset lost or edited shortly after
  /// an access still has a recent commitment, high enough that a busy register
  /// session does not double the outbox. An anchor is one tiny row per ten
  /// accesses, pushed on the next window like everything else.
  static const anchorEvery = 10;

  /// The supervisor's working queue: accesses no consent and no care relationship
  /// explains, each carrying the worker's name, the family's name, and whether a
  /// review has already been written against it.
  ///
  /// Names are joined rather than left as ids because this list is meant to be
  /// *acted on*: "Aminata Fusea looked outside her zone at Akosia Yeboah" is a
  /// sentence a District Supervisor can do something about, and two UUIDs are not.
  /// The review count comes back as a subquery on the same table so that marking
  /// a finding reviewed never mutates the finding itself.
  static Future<List<AccessFinding>> findings({int limit = 50}) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      'SELECT l.*, u.full_name AS actor_name, '
      'COALESCE(p.full_name, h.name) AS subject_name, '
      '(SELECT COUNT(*) FROM ${Tables.accessLedger} r '
      'WHERE r.action = ? AND r.entity_id = l.id) AS review_count '
      'FROM ${Tables.accessLedger} l '
      'LEFT JOIN ${Tables.users} u ON u.id = l.actor_id '
      'LEFT JOIN ${Tables.persons} p ON p.id = l.subject_person_id '
      'LEFT JOIN ${Tables.households} h ON h.id = l.subject_person_id '
      "WHERE l.flagged = 1 AND l.action <> ? "
      'ORDER BY l.seq DESC LIMIT ?',
      [AccessLedgerDao.reviewAction, AccessLedgerDao.reviewAction, limit],
    );
    return rows.map(AccessFinding.fromRow).toList(growable: false);
  }

  /// Two questions the finding queue cannot ask, because each is about the
  /// *shape* of many entries rather than about any one of them.
  ///
  /// Both are answered in SQL with a single aggregate each rather than by pulling
  /// the trail into Dart: this runs on a handset whose memory is already spoken
  /// for, and a device audit table grows without limit.
  static Future<List<AccessPattern>> patterns({
    required DateTime since,
    int actorThreshold = 4,
    int subjectThreshold = 4,
    int limit = 10,
  }) async {
    final db = await AppDatabase.instance.database;
    final sinceText = since.toIso8601String();
    final out = <AccessPattern>[];

    // One worker, many families, none of them theirs. Deliberately counts
    // DISTINCT subjects: the same household read five times in one sitting is one
    // visit, and a detector that reports it is a detector people stop reading.
    final volume = await db.rawQuery(
      'SELECT l.actor_id, u.full_name AS actor_name, '
      'COUNT(DISTINCT l.subject_person_id) AS families, MAX(l.occurred_at) AS latest '
      'FROM ${Tables.accessLedger} l '
      'LEFT JOIN ${Tables.users} u ON u.id = l.actor_id '
      "WHERE l.flagged = 1 AND l.action <> ? AND l.occurred_at >= ? "
      'GROUP BY l.actor_id HAVING families >= ? '
      'ORDER BY families DESC LIMIT ?',
      [reviewAction, sinceText, actorThreshold, limit],
    );
    for (final r in volume) {
      final raw = r['latest'] as String?;
      out.add(
        AccessPattern(
          kind: AccessPatternKind.outOfCaseloadVolume,
          // A worker whose account row has gone still shows up; an id with no
          // name is uglier than a guess and far harder to disprove later.
          actorName: (r['actor_name'] as String?) ?? 'a former health worker',
          count: (r['families'] as int? ?? 0),
          latest: raw == null ? since : DateTime.parse(raw),
        ),
      );
    }

    // One protected record, several pairs of eyes. Restricted to marked records
    // on purpose: three colleagues sharing one district's caseload is normal work
    // and reporting it would teach the supervisor to ignore this queue.
    final shared = await db.rawQuery(
      'SELECT l.subject_person_id, COALESCE(p.full_name, h.name) AS subject_name, '
      'COUNT(DISTINCT l.actor_id) AS workers, MAX(l.occurred_at) AS latest '
      'FROM ${Tables.accessLedger} l '
      'JOIN ${Tables.persons} pr ON pr.id = l.subject_person_id '
      'LEFT JOIN ${Tables.persons} p ON p.id = l.subject_person_id '
      'LEFT JOIN ${Tables.households} h ON h.id = l.subject_person_id '
      "WHERE l.action <> ? AND l.occurred_at >= ? "
      'AND pr.sensitivity IS NOT NULL '
      'GROUP BY l.subject_person_id HAVING workers >= ? '
      'ORDER BY workers DESC LIMIT ?',
      [reviewAction, sinceText, subjectThreshold, limit],
    );
    for (final r in shared) {
      final raw = r['latest'] as String?;
      out.add(
        AccessPattern(
          kind: AccessPatternKind.sharedSensitiveSubject,
          subjectName: (r['subject_name'] as String?) ?? 'a protected record',
          count: (r['workers'] as int? ?? 0),
          latest: raw == null ? since : DateTime.parse(raw),
        ),
      );
    }
    return out;
  }

  static AccessRecord _toRecord(Map<String, Object?> m) => AccessRecord(
    seq: m['seq'] as int,
    actorId: m['actor_id'] as String,
    actorRole: m['actor_role'] as String? ?? '',
    deviceId: m['device_id'] as String? ?? '',
    action: m['action'] as String,
    entityTable: m['entity_table'] as String? ?? '',
    entityId: m['entity_id'] as String? ?? '',
    subjectPersonId: m['subject_person_id'] as String? ?? '',
    purpose: _byName(
      AccessPurpose.values,
      m['purpose'],
      AccessPurpose.unstated,
    ),
    basis: _byName(AccessBasis.values, m['basis'], AccessBasis.none),
    occurredAt: DateTime.parse(m['occurred_at'] as String),
    entryHash: m['entry_hash'] as String? ?? '',
    previousHash: m['previous_hash'] as String? ?? '',
    note: m['note'] as String?,
    flagged: (m['flagged'] as int? ?? 0) == 1,
  );

  /// Reads a stored enum name back into its value.
  ///
  /// Bound to `Enum` and read statically, never through `dynamic`. The dynamic hop
  /// analysed clean and then threw `NoSuchMethodError: Class 'AccessPurpose' has no
  /// instance getter 'name'` the moment anything actually called it — which is how
  /// a read path survives review and fails on the first supervisor to open the
  /// desk. The typed form is also what the disclosure projection already does, so
  /// the two read paths now resolve names the same way.
  static T _byName<T extends Enum>(List<T> values, Object? name, T fallback) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return fallback;
  }
}

/// One line of the disclosure a family is entitled to read.
class DisclosureLine {
  const DisclosureLine({
    required this.actorName,
    required this.actorRole,
    required this.purpose,
    required this.basis,
    required this.occurredAt,
    required this.action,
    this.note,
    required this.flagged,
  });

  final String actorName;
  final String actorRole;
  final AccessPurpose purpose;
  final AccessBasis basis;
  final DateTime occurredAt;
  final String action;

  /// The worker's stated reason, when there was one. This is the line a family
  /// actually reads, so it travels as far as the rest of the disclosure.
  final String? note;
  final bool flagged;

  factory DisclosureLine.fromRow(Map<String, Object?> m) => DisclosureLine(
    // An actor whose account has since been removed must still be disclosed; the
    // record of who looked cannot quietly disappear by deleting the user.
    actorName: (m['actor_name'] as String?) ?? 'a former health worker',
    actorRole: (m['actor_role'] as String?) ?? 'health worker',
    purpose: _purpose(m['purpose']),
    basis: _basis(m['basis']),
    occurredAt: DateTime.parse(m['occurred_at'] as String),
    action: m['action'] as String? ?? 'opened',
    // The stated reason is the part a family actually reads, so it is disclosed
    // with the rest of the line rather than left in the raw ledger.
    note: m['note'] as String?,
    flagged: (m['flagged'] as int? ?? 0) == 1,
  );

  static AccessPurpose _purpose(Object? n) => AccessPurpose.values.firstWhere(
    (p) => p.name == n,
    orElse: () => AccessPurpose.unstated,
  );
  static AccessBasis _basis(Object? n) => AccessBasis.values.firstWhere(
    (b) => b.name == n,
    orElse: () => AccessBasis.none,
  );
}

/// One finding on the supervision desk.
///
/// Deliberately not the same shape as [DisclosureLine]: the family gets sentences,
/// the supervisor gets the machinery — device id, entry id, whether anyone has
/// already written a decision — because the two audiences have different jobs to do.
class AccessFinding {
  const AccessFinding({
    required this.entryId,
    required this.seq,
    required this.actorName,
    required this.actorRole,
    required this.subjectName,
    required this.subjectPersonId,
    required this.deviceId,
    required this.purpose,
    required this.basis,
    required this.occurredAt,
    required this.reviewed,
    this.note,
  });

  /// The ledger row's own globally unique id — what a review points back to.
  final String entryId;
  final int seq;
  final String actorName;
  final String actorRole;
  final String subjectName;
  final String subjectPersonId;
  final String deviceId;
  final AccessPurpose purpose;
  final AccessBasis basis;
  final DateTime occurredAt;
  final String? note;

  /// Whether a supervisor has already written a decision against this entry.
  final bool reviewed;

  factory AccessFinding.fromRow(Map<String, Object?> m) => AccessFinding(
    entryId: m['id'] as String? ?? '',
    seq: m['seq'] as int? ?? 0,
    // An actor or family that has since been removed from the register must still
    // be named in the queue; a finding that shows "a former health worker" is
    // uglier than one that silently disappears, and much harder to explain away.
    actorName: (m['actor_name'] as String?) ?? 'a former health worker',
    actorRole: (m['actor_role'] as String?) ?? 'health worker',
    subjectName:
        (m['subject_name'] as String?) ?? 'a family not in this register',
    subjectPersonId: m['subject_person_id'] as String? ?? '',
    deviceId: m['device_id'] as String? ?? 'unknown device',
    purpose: DisclosureLine._purpose(m['purpose']),
    basis: DisclosureLine._basis(m['basis']),
    occurredAt: DateTime.parse(m['occurred_at'] as String),
    note: m['note'] as String?,
    reviewed: (m['review_count'] as int? ?? 0) > 0,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Consent: an append-only history of decisions
// ─────────────────────────────────────────────────────────────────────────────

abstract final class ConsentLedgerDao {
  /// Records a decision. Never updates an old one.
  ///
  /// A withdrawal is a new row, which is what preserves the legal fact that the
  /// family *did* consent between two dates — needed to explain an access that
  /// happened then, and the reason "delete the checkbox" is the wrong design.
  static Future<void> record(
    DatabaseExecutor db, {
    required ConsentEvent event,
  }) async {
    await db.insert(Tables.consentEvents, {
      'id': event.id,
      'subject_person_id': event.subjectPersonId,
      'scope': event.scope.name,
      'decision': event.decision.name,
      'notice_version': event.noticeVersion,
      'language': event.language,
      'voice_artifact': event.voiceArtifact,
      'captured_by': event.capturedBy,
      'device_id': event.deviceId,
      'witness_name': event.witnessName,
      'note': event.note,
      'occurred_at': event.occurredAt.toIso8601String(),
    });
    await OutboxDao.enqueue(
      db,
      table: Tables.consentEvents,
      entityId: event.id,
      operation: SyncOperation.insert,
      priority: SyncPriority.clinical,
      payload: {
        'id': event.id,
        'subject_person_id': event.subjectPersonId,
        'scope': event.scope.name,
        'decision': event.decision.name,
        'notice_version': event.noticeVersion,
        'language': event.language,
        'voice_artifact': event.voiceArtifact,
        'captured_by': event.capturedBy,
        'device_id': event.deviceId,
        'witness_name': event.witnessName,
        'note': event.note,
        'occurred_at': event.occurredAt.toIso8601String(),
      },
    );
  }

  /// The family's current position on one scope, or null when they have never
  /// been asked.
  ///
  /// Null is meaningful and must not default to granted: an una sked person has
  /// not consented.
  static Future<ConsentEvent?> current(
    String subjectPersonId,
    ConsentScope scope,
  ) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.consentEvents,
      where: 'subject_person_id = ? AND scope = ?',
      whereArgs: [subjectPersonId, scope.name],
      orderBy: 'occurred_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  /// Every scope's current state for one person, in one query.
  static Future<Map<ConsentScope, ConsentEvent?>> currentFor(
    String subjectPersonId,
  ) async {
    final out = <ConsentScope, ConsentEvent?>{
      for (final s in ConsentScope.values) s: null,
    };
    for (final scope in ConsentScope.values) {
      out[scope] = await current(subjectPersonId, scope);
    }
    return out;
  }

  static bool isGranted(ConsentEvent? event) => event?.isGrant == true;

  /// True when the newest grant predates the notice text now in force.
  static Future<bool> needsReconsent(
    String subjectPersonId,
    ConsentScope scope,
  ) async {
    final event = await current(subjectPersonId, scope);
    if (event == null) return true;
    if (!event.isGrant) return false;
    return event.noticeVersion != CareNotice.currentVersion;
  }

  /// The audit-relevant case: consent recorded today against a notice that is no
  /// longer current means the *old* permission is what stands.
  static Future<List<ConsentEvent>> historyFor(String subjectPersonId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.consentEvents,
      where: 'subject_person_id = ?',
      whereArgs: [subjectPersonId],
      orderBy: 'occurred_at DESC',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  static ConsentEvent _fromRow(Map<String, Object?> m) => ConsentEvent(
    id: m['id'] as String,
    subjectPersonId: m['subject_person_id'] as String,
    scope: ConsentScope.values.firstWhere(
      (s) => s.name == m['scope'],
      // An unknown scope is a build from another branch: refuse it rather than
      // guess, because guessing a scope is guessing a permission.
      orElse: () => ConsentScope.crossFacilitySearch,
    ),
    decision: ConsentDecision.values.firstWhere(
      (d) => d.name == m['decision'],
      orElse: () => ConsentDecision.objected,
    ),
    noticeVersion: m['notice_version'] as String? ?? 'unknown',
    occurredAt: DateTime.parse(m['occurred_at'] as String),
    capturedBy: m['captured_by'] as String? ?? '',
    language: m['language'] as String? ?? 'English',
    voiceArtifact: m['voice_artifact'] as String?,
    deviceId: m['device_id'] as String?,
    witnessName: m['witness_name'] as String?,
    note: m['note'] as String?,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Data-rights requests
// ─────────────────────────────────────────────────────────────────────────────

abstract final class DataRightsDao {
  static Future<void> open({
    required String id,
    required String subjectPersonId,
    required DataRight right,
    required String requestedBy,
    required DateTime at,
  }) async {
    final db = await AppDatabase.instance.database;
    final row = <String, Object?>{
      'id': id,
      'subject_person_id': subjectPersonId,
      'request_kind': right.name,
      'status': RequestStatus.open.name,
      'requested_at': at.toIso8601String(),
      'requested_by': requestedBy,
      'resolved_at': null,
      'resolution': null,
    };
    // The request and its intent to leave the phone go in one write, for the same
    // reason a clinical record does: a 30-day promise that can only be evidenced
    // from the handset a family might lose is not a promise. Whitelisted on the
    // server as push-only, so the district holds the obligation independently.
    await db.transaction((txn) async {
      await txn.insert(Tables.dataRightsRequests, row);
      await OutboxDao.enqueue(
        txn,
        table: Tables.dataRightsRequests,
        entityId: id,
        operation: SyncOperation.insert,
        priority: SyncPriority.background,
        payload: row,
      );
    });
  }

  static Future<List<RightsRequest>> forSubject(String subjectPersonId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.dataRightsRequests,
      where: 'subject_person_id = ?',
      whereArgs: [subjectPersonId],
      orderBy: 'requested_at DESC',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  /// One request by id, for the paths that must check what was asked before they
  /// act on it. A family's right to erasure must not be satisfiable by a caller who
  /// guessed at the kind from the row it happened to be looking at.
  static Future<RightsRequest?> byId(String id) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.dataRightsRequests,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  /// Everything the district still owes an answer to — the queue, with overdue
  /// work first, because a request left open is the failure this table exists to
  /// make visible.
  static Future<List<RightsRequest>> openQueue() async {
    final db = await AppDatabase.instance.database;
    // The name travels with the row, for the same reason the findings queue joins
    // it: a queue worked from ids is a queue nobody can actually work.
    final rows = await db.rawQuery(
      'SELECT q.*, COALESCE(p.full_name, h.name) AS subject_name '
      'FROM ${Tables.dataRightsRequests} q '
      'LEFT JOIN ${Tables.persons} p ON p.id = q.subject_person_id '
      'LEFT JOIN ${Tables.households} h ON h.id = q.subject_person_id '
      "WHERE q.status = '${RequestStatus.open.name}' "
      'ORDER BY q.requested_at ASC',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  static Future<void> resolve(
    String id, {
    required RequestStatus status,
    required String resolution,
    required DateTime at,
  }) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      await txn.update(
        Tables.dataRightsRequests,
        {
          'status': status.name,
          'resolution': resolution,
          'resolved_at': at.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      // The answer travels too, as the whole row. A district that can prove it
      // received a request but not that it met the deadline has documented half an
      // obligation; re-pushing the same id updates the server's row in place.
      final rows = await txn.query(
        Tables.dataRightsRequests,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return;
      await OutboxDao.enqueue(
        txn,
        table: Tables.dataRightsRequests,
        entityId: id,
        operation: SyncOperation.insert,
        priority: SyncPriority.background,
        payload: Map<String, Object?>.from(rows.single),
      );
    });
  }

  static RightsRequest _fromRow(Map<String, Object?> m) => RightsRequest(
    id: m['id'] as String,
    subjectPersonId: m['subject_person_id'] as String,
    right: DataRight.values.firstWhere(
      (r) => r.name == m['request_kind'],
      orElse: () => DataRight.access,
    ),
    requestedAt: DateTime.parse(m['requested_at'] as String),
    requestedBy: m['requested_by'] as String? ?? '',
    subjectName: m['subject_name'] as String?,
    status: RequestStatus.values.firstWhere(
      (s) => s.name == m['status'],
      orElse: () => RequestStatus.open,
    ),
    resolvedAt: (m['resolved_at'] as String?) == null
        ? null
        : DateTime.parse(m['resolved_at'] as String),
    resolution: m['resolution'] as String?,
  );
}
