/// Visits, assessments, referrals, barriers and scheduled contacts — the
/// clinical event log.
///
/// Three things here are load-bearing:
///
/// **A visit is a container, not a form.** One encounter under a tree can hold a
/// mother's PNC check, two newborn assessments and a sick three-year-old. The
/// [VisitDao] roll call records who was *present*, separately from who was
/// assessed, because "the second twin was not brought today" is precisely the
/// signal that finds a child before it becomes a death.
///
/// **Assessments and referrals are written together.** An urgent verdict that
/// saved without its referral would be a triage decision nobody acts on, so
/// [AssessmentDao.saveWithReferral] commits both plus both outbox rows in one
/// transaction.
///
/// **Referrals are queried by what has gone wrong.** Open, overdue,
/// needing-escalation: these are indexed queries rather than something a CHO has
/// to leaf through a register to notice.
library;

import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';

import '../../domain/entities/visit.dart';
import '../../domain/enums.dart';
import '../../domain/services/follow_up_policy.dart';
import 'app_database.dart';
import 'outbox_dao.dart';
import 'upsert.dart';

/// One row of the roll call: who the CHO expected, and who actually turned up.
class VisitParticipant {
  const VisitParticipant({
    required this.visitId,
    required this.personId,
    this.wasPresent = true,
    this.absenceNote,
    this.queueOrder = 0,
    this.assessed = false,
  });

  final String visitId;
  final String personId;
  final bool wasPresent;

  /// Why they were not here. Free text, because the real answers are things no
  /// dropdown anticipates — "gone to the market in Yendi", "with the
  /// grandmother in another compound".
  final String? absenceNote;

  final int queueOrder;
  final bool assessed;

  Map<String, Object?> toMap() => {
    'visit_id': visitId,
    'person_id': personId,
    'was_present': wasPresent ? 1 : 0,
    'absence_note': absenceNote,
    'queue_order': queueOrder,
    'assessed': assessed ? 1 : 0,
  };

  factory VisitParticipant.fromMap(Map<String, Object?> m) => VisitParticipant(
    visitId: m['visit_id'] as String,
    personId: m['person_id'] as String,
    wasPresent: (m['was_present'] as num?) != 0,
    absenceNote: m['absence_note'] as String?,
    queueOrder: (m['queue_order'] as num?)?.toInt() ?? 0,
    assessed: (m['assessed'] as num?) == 1,
  );

  VisitParticipant copyWith({
    bool? wasPresent,
    String? absenceNote,
    bool? assessed,
  }) => VisitParticipant(
    visitId: visitId,
    personId: personId,
    wasPresent: wasPresent ?? this.wasPresent,
    absenceNote: absenceNote ?? this.absenceNote,
    queueOrder: queueOrder,
    assessed: assessed ?? this.assessed,
  );
}

/// The half-open local-day window `[midnight, next midnight)` as the ISO text
/// the date columns actually store. Timestamps are written with
/// `toIso8601String()`, which sorts lexicographically, so a string range is a
/// correct day filter — and the upper bound is exclusive, which keeps a record
/// saved at exactly midnight tonight in tomorrow's tally.
({String start, String end}) _dayWindow(DateTime day) => (
  start: DateTime(day.year, day.month, day.day).toIso8601String(),
  end: DateTime(
    day.year,
    day.month,
    day.day,
  ).add(const Duration(days: 1)).toIso8601String(),
);

abstract final class VisitDao {
  static Future<void> upsert(Visit visit) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      final map = visit.toMap();
      // A visit parents its roll call and its assessments. Replacing the row would
      // cascade them both away, so completing a visit twice would erase the
      // clinical work done inside it.
      await upsertWithoutCascade(
        txn,
        table: Tables.visits,
        primaryKey: const ['id'],
        row: map,
      );
      await OutboxDao.enqueue(
        txn,
        table: Tables.visits,
        entityId: visit.id,
        operation: SyncOperation.update,
        payload: map,
      );
    });
  }

  /// Opens a visit and its roll call in one transaction.
  static Future<void> start(
    Visit visit,
    List<VisitParticipant> participants,
  ) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      final map = visit.toMap();
      await upsertWithoutCascade(
        txn,
        table: Tables.visits,
        primaryKey: const ['id'],
        row: map,
      );
      for (final p in participants) {
        await txn.insert(
          Tables.visitParticipants,
          p.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await OutboxDao.enqueue(
        txn,
        table: Tables.visits,
        entityId: visit.id,
        operation: SyncOperation.insert,
        payload: {
          ...map,
          'participants': participants.map((p) => p.toMap()).toList(),
        },
      );
    });
  }

  static Future<Visit?> byId(String id) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.visits,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Visit.fromMap(rows.first);
  }

  /// A visit left open — the app crashed, the battery died, the CHO was called
  /// away mid-encounter. Offered for resumption on next launch, because asking
  /// a mother the same forty questions twice is how an app gets abandoned.
  static Future<Visit?> openVisitFor(String workerId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.visits,
      where: 'conducted_by = ? AND completed_at IS NULL',
      whereArgs: [workerId],
      orderBy: 'started_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : Visit.fromMap(rows.first);
  }

  /// Every session this worker has left open, newest first. The real CHPS
  /// workload is a queue, not a single thread: several households received
  /// today, a routine consult paused while an urgent arrival is pulled forward.
  /// The schema already allows many `completed_at IS NULL` rows per worker —
  /// only the single-resume UI used to pretend otherwise.
  static Future<List<Visit>> openVisitsFor(String workerId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.visits,
      where: 'conducted_by = ? AND completed_at IS NULL',
      whereArgs: [workerId],
      orderBy: 'started_at DESC',
    );
    return rows.map(Visit.fromMap).toList(growable: false);
  }

  /// The one open session for a specific household, if any. Intake uses this to
  /// join an existing ticket instead of starting a duplicate for the same
  /// family, while still allowing a second household its own open visit.
  static Future<Visit?> openVisitForHousehold(
    String workerId,
    String householdId,
  ) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.visits,
      where: 'conducted_by = ? AND household_id = ? AND completed_at IS NULL',
      whereArgs: [workerId, householdId],
      orderBy: 'started_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : Visit.fromMap(rows.first);
  }

  static Future<List<Visit>> forHousehold(String householdId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.visits,
      where: 'household_id = ?',
      whereArgs: [householdId],
      orderBy: 'started_at DESC',
    );
    return rows.map(Visit.fromMap).toList(growable: false);
  }

  static Future<List<Visit>> completedOn(DateTime day, String workerId) async {
    final db = await AppDatabase.instance.database;
    final window = _dayWindow(day);
    final rows = await db.query(
      Tables.visits,
      where: 'conducted_by = ? AND started_at >= ? AND started_at < ?',
      whereArgs: [workerId, window.start, window.end],
      orderBy: 'started_at DESC',
    );
    return rows.map(Visit.fromMap).toList(growable: false);
  }

  /// The front-door pace for one clinic day. One pass over the day's visits
  /// left-joined to their assessments: received count, still-open count, and
  /// the mean minutes from receiving a session to its first saved assessment.
  static Future<ClinicDayStats> clinicDayStats(
    String workerId,
    DateTime day,
  ) async {
    final db = await AppDatabase.instance.database;
    final window = _dayWindow(day);
    final rows = await db.rawQuery(
      'SELECT v.started_at AS started_at, v.completed_at AS completed_at, '
      'MIN(a.performed_at) AS first_assessed_at '
      'FROM ${Tables.visits} v '
      'LEFT JOIN ${Tables.assessments} a ON a.visit_id = v.id '
      'WHERE v.conducted_by = ? AND v.started_at >= ? AND v.started_at < ? '
      'GROUP BY v.id',
      [workerId, window.start, window.end],
    );
    var open = 0;
    var assessed = 0;
    var totalMinutes = 0;
    for (final row in rows) {
      if (row['completed_at'] == null) open++;
      final first = row['first_assessed_at'] as String?;
      if (first != null) {
        assessed++;
        totalMinutes += DateTime.parse(
          first,
        ).difference(DateTime.parse(row['started_at'] as String)).inMinutes;
      }
    }
    return ClinicDayStats(
      received: rows.length,
      openNow: open,
      avgMinutesToFirstAssessment: assessed == 0
          ? null
          : totalMinutes / assessed,
    );
  }

  static Future<void> complete(String visitId, {String? notes}) async {
    final db = await AppDatabase.instance.database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      await txn.update(
        Tables.visits,
        {
          'completed_at': now,
          // Omitted entirely when null, so a completion without notes does not
          // wipe notes the CHO typed earlier in the encounter.
          'notes': ?notes,
          'sync_state': SyncState.pending.name,
        },
        where: 'id = ?',
        whereArgs: [visitId],
      );
      await OutboxDao.enqueue(
        txn,
        table: Tables.visits,
        entityId: visitId,
        operation: SyncOperation.update,
        payload: {'id': visitId, 'completed_at': now, 'notes': notes},
      );
    });
  }

  static Future<List<VisitParticipant>> participants(String visitId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.visitParticipants,
      where: 'visit_id = ?',
      whereArgs: [visitId],
      orderBy: 'queue_order ASC',
    );
    return rows.map(VisitParticipant.fromMap).toList(growable: false);
  }

  static Future<void> updateParticipant(VisitParticipant p) async {
    final db = await AppDatabase.instance.database;
    await db.insert(
      Tables.visitParticipants,
      p.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Everyone expected at recent visits who was not there. The defaulter list,
  /// derived rather than maintained by hand.
  static Future<List<VisitParticipant>> recentAbsentees({
    int withinDays = 30,
  }) async {
    final db = await AppDatabase.instance.database;
    final cutoff = DateTime.now()
        .subtract(Duration(days: withinDays))
        .toIso8601String();
    final rows = await db.rawQuery(
      '''
      SELECT vp.* FROM ${Tables.visitParticipants} vp
      JOIN ${Tables.visits} v ON v.id = vp.visit_id
      WHERE vp.was_present = 0 AND v.started_at >= ?
      ORDER BY v.started_at DESC
      ''',
      [cutoff],
    );
    return rows.map(VisitParticipant.fromMap).toList(growable: false);
  }

  /// How many days since anyone from this household was seen. Feeds the
  /// vulnerability score, where silence counts as risk rather than as safety.
  static Future<int?> daysSinceLastVisit(String householdId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      'SELECT MAX(started_at) AS last FROM ${Tables.visits} WHERE household_id = ?',
      [householdId],
    );
    final last = DateTime.tryParse((rows.first['last'] as String?) ?? '');
    return last == null ? null : DateTime.now().difference(last).inDays;
  }
}

abstract final class AssessmentDao {
  static Future<void> save(Assessment a) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      await _insertAssessment(txn, a);
    });
  }

  /// Saves an assessment and the referral it produced atomically.
  ///
  /// These two must not be separable. An urgent verdict persisted without its
  /// referral is a decision nobody acts on; a referral without the assessment
  /// behind it cannot be justified to the receiving facility.
  static Future<void> saveWithReferral(Assessment a, Referral r) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      await _insertAssessment(txn, a);

      final rm = r.toMap();
      await upsertWithoutCascade(
        txn,
        table: Tables.referrals,
        primaryKey: const ['id'],
        row: rm,
      );
      await OutboxDao.enqueue(
        txn,
        table: Tables.referrals,
        entityId: r.id,
        operation: SyncOperation.insert,
        payload: rm,
        // A referral for a child in danger is the one thing that must leave the
        // device the instant a bar of signal appears.
        priority: r.urgency == ReferralUrgency.immediate
            ? SyncPriority.critical
            : SyncPriority.clinical,
      );
    });
  }

  /// Saves an assessment plus the follow-up contacts the engine generated, so
  /// no scheduled review depends on a CHO remembering to add it.
  static Future<void> saveWithSchedule(
    Assessment a,
    List<ScheduledContact> contacts,
  ) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      await _insertAssessment(txn, a);
      for (final c in contacts) {
        final cm = c.toMap();
        await txn.insert(
          Tables.scheduledContacts,
          cm,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await OutboxDao.enqueue(
          txn,
          table: Tables.scheduledContacts,
          entityId: c.id,
          operation: SyncOperation.insert,
          payload: cm,
        );
      }
    });
  }

  static Future<void> _insertAssessment(
    DatabaseExecutor txn,
    Assessment a,
  ) async {
    final map = a.toMap();
    await txn.insert(
      Tables.assessments,
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    // Mark the person as assessed within this visit, so the roll call shows
    // progress without a second write path.
    await txn.update(
      Tables.visitParticipants,
      {'assessed': 1},
      where: 'visit_id = ? AND person_id = ?',
      whereArgs: [a.visitId, a.personId],
    );
    await OutboxDao.enqueue(
      txn,
      table: Tables.assessments,
      entityId: a.id,
      operation: SyncOperation.insert,
      payload: map,
      priority: a.effectiveTriage == TriageLevel.urgent
          ? SyncPriority.critical
          : SyncPriority.clinical,
    );
  }

  static Future<Assessment?> byId(String id) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.assessments,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Assessment.fromMap(rows.first);
  }

  static Future<List<Assessment>> forPerson(String personId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.assessments,
      where: 'person_id = ?',
      whereArgs: [personId],
      orderBy: 'performed_at DESC',
    );
    return rows.map(Assessment.fromMap).toList(growable: false);
  }

  static Future<Assessment?> latestForPerson(String personId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.assessments,
      where: 'person_id = ?',
      whereArgs: [personId],
      orderBy: 'performed_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : Assessment.fromMap(rows.first);
  }

  static Future<List<Assessment>> forVisit(String visitId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.assessments,
      where: 'visit_id = ?',
      whereArgs: [visitId],
      orderBy: 'performed_at ASC',
    );
    return rows.map(Assessment.fromMap).toList(growable: false);
  }

  /// Records a clinician overruling the engine.
  ///
  /// The human is accountable for care, so they must be able to. The app records
  /// that they did and why — both for audit, and because a corpus of overrides
  /// is the only honest training signal this system will ever get for improving
  /// its own thresholds.
  static Future<void> recordOverride({
    required String assessmentId,
    required TriageLevel newTriage,
    required String reason,
    required String byUserId,
  }) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      await txn.update(
        Tables.assessments,
        {
          'overridden_triage': newTriage.name,
          'override_reason': reason,
          'override_by': byUserId,
          'sync_state': SyncState.pending.name,
        },
        where: 'id = ?',
        whereArgs: [assessmentId],
      );
      await OutboxDao.enqueue(
        txn,
        table: Tables.assessments,
        entityId: assessmentId,
        operation: SyncOperation.update,
        payload: {
          'id': assessmentId,
          'overridden_triage': newTriage.name,
          'override_reason': reason,
          'override_by': byUserId,
        },
        priority: SyncPriority.clinical,
      );
      await txn.insert(Tables.auditLog, {
        'actor_id': byUserId,
        'action': 'override_recommendation',
        'entity_table': Tables.assessments,
        'entity_id': assessmentId,
        'outcome': 'allowed',
        'detail': 'Changed triage to ${newTriage.name}: $reason',
        'occurred_at': DateTime.now().toIso8601String(),
      });
    });
  }

  /// Every override, for the model-improvement view. Small on purpose: this is
  /// evidence to read, not a table to page through.
  static Future<List<Assessment>> overrides({int limit = 100}) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.assessments,
      where: 'overridden_triage IS NOT NULL',
      orderBy: 'performed_at DESC',
      limit: limit,
    );
    return rows.map(Assessment.fromMap).toList(growable: false);
  }

  static Future<int> countToday(String workerId) async {
    final db = await AppDatabase.instance.database;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).toIso8601String();
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${Tables.assessments} '
      'WHERE performed_by = ? AND performed_at >= ?',
      [workerId, start],
    );
    return (rows.first['c'] as num).toInt();
  }

  /// Everything this worker saved on [day], whole.
  ///
  /// Deliberately not a SQL aggregate: the daily register tally reads the
  /// `inputs_json` and `result_json` payloads for the RDT result, the vaccine
  /// list and the nutrition band, none of which belong in a `LIKE` pattern.
  /// One clinic day is tens of rows, so the parse is free — see
  /// [DailyRegisterTally.of].
  static Future<List<Assessment>> forWorkerOn(
    String workerId,
    DateTime day,
  ) async {
    final db = await AppDatabase.instance.database;
    final window = _dayWindow(day);
    final rows = await db.query(
      Tables.assessments,
      where: 'performed_by = ? AND performed_at >= ? AND performed_at < ?',
      whereArgs: [workerId, window.start, window.end],
      orderBy: 'performed_at ASC',
    );
    return rows.map(Assessment.fromMap).toList(growable: false);
  }

  /// Assessments this worker recorded within the window — the personal
  /// workload figure behind "register time handed back".
  static Future<int> countWithin(String workerId, {int withinDays = 30}) async {
    final db = await AppDatabase.instance.database;
    final since = DateTime.now()
        .subtract(Duration(days: withinDays))
        .toIso8601String();
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${Tables.assessments} '
      'WHERE performed_by = ? AND performed_at >= ?',
      [workerId, since],
    );
    return (rows.first['c'] as num).toInt();
  }

  /// How many times this worker overruled the engine within the window.
  /// Every one carries a written clinical reason, so the honest framing is
  /// "times your judgement is on record", never "times the AI was wrong".
  static Future<int> countOverridesWithin(
    String workerId, {
    int withinDays = 30,
  }) async {
    final db = await AppDatabase.instance.database;
    final since = DateTime.now()
        .subtract(Duration(days: withinDays))
        .toIso8601String();
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${Tables.assessments} '
      'WHERE performed_by = ? AND performed_at >= ? '
      'AND overridden_triage IS NOT NULL',
      [workerId, since],
    );
    return (rows.first['c'] as num).toInt();
  }
}

abstract final class ReferralDao {
  static Future<void> upsert(Referral r) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) => upsertIn(txn, r));
  }

  /// The transaction-scoped half of [upsert], so a follow-up answer can write
  /// its ledger row, advance the referral and raise a chained one in a single
  /// commit. Callers must already hold a [DatabaseExecutor].
  static Future<void> upsertIn(DatabaseExecutor db, Referral r) async {
    final map = r.toMap();
    // A referral parents every follow-up contact made against it — the answers
    // that say whether the mother actually reached the facility. Replacing the
    // referral would delete the evidence the follow-up desk exists to collect.
    await upsertWithoutCascade(
      db,
      table: Tables.referrals,
      primaryKey: const ['id'],
      row: map,
    );
    await OutboxDao.enqueue(
      db,
      table: Tables.referrals,
      entityId: r.id,
      operation: SyncOperation.update,
      payload: map,
      priority: r.urgency == ReferralUrgency.immediate
          ? SyncPriority.critical
          : SyncPriority.clinical,
    );
  }

  static Future<Referral?> byId(String id) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.referrals,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Referral.fromMap(rows.first);
  }

  /// Looks a referral up by the short code a facility reads off a paper slip or
  /// hears down a phone line. Case-insensitive, because it will be typed by
  /// someone in a hurry.
  static Future<Referral?> byCode(String code) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.referrals,
      where: 'UPPER(reference_code) = ?',
      whereArgs: [code.trim().toUpperCase()],
      limit: 1,
    );
    return rows.isEmpty ? null : Referral.fromMap(rows.first);
  }

  /// Whether any referral already carries [code]. Case-insensitive, matching
  /// [byCode].
  static Future<bool> codeExists(String code) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.referrals,
      columns: const ['id'],
      where: 'UPPER(reference_code) = ?',
      whereArgs: [code.trim().toUpperCase()],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Mints a short, human-speakable referral code that is not already in use.
  ///
  /// Ambiguous letters and digits are excluded so the code survives being read
  /// down a crackly phone line. `reference_code` has a UNIQUE index and the
  /// district resolves a family by this code, so two referrals must never share
  /// one — yet the space of a 4-character code is only ~810k, and by the
  /// birthday bound a device holding a few hundred referrals collides with real
  /// probability, which would throw at insert and fail the save. Candidates are
  /// drawn until one is unused; if 4-character draws somehow all collide the
  /// code is widened rather than returned dirty. Every mint site uses this so
  /// the check and the format cannot drift apart.
  static Future<String> mintReferenceCode() async {
    for (var attempt = 0; attempt < 40; attempt++) {
      final code = _randomReferenceCode(4);
      if (!await codeExists(code)) return code;
    }
    for (var attempt = 0; attempt < 40; attempt++) {
      final code = _randomReferenceCode(5);
      if (!await codeExists(code)) return code;
    }
    // Pathological — every 4- and 5-character draw hit an existing row.
    // Widen and let the UNIQUE index be the honest backstop rather than hand
    // the family a code we already know is taken.
    return _randomReferenceCode(6);
  }

  static final math.Random _referenceCodeRandom = math.Random.secure();

  /// A single random code with NO uniqueness check. Only for callers that cannot
  /// reach the database (a widget test with a mocked repository, or a transient
  /// DB error); prefer [mintReferenceCode], which guarantees the code is free.
  static String randomReferenceCode() => _randomReferenceCode(4);

  static String _randomReferenceCode(int length) {
    const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    return 'CB-${List.generate(length, (_) => alphabet[_referenceCodeRandom.nextInt(alphabet.length)]).join()}';
  }

  static Future<List<Referral>> open() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.referrals,
      where: 'status IN (?, ?)',
      whereArgs: [ReferralStatus.issued.name, ReferralStatus.travelling.name],
      orderBy: 'issued_at ASC',
    );
    return rows.map(Referral.fromMap).toList(growable: false);
  }

  static Future<List<Referral>> forPerson(String personId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.referrals,
      where: 'person_id = ?',
      whereArgs: [personId],
      orderBy: 'issued_at DESC',
    );
    return rows.map(Referral.fromMap).toList(growable: false);
  }

  /// Referrals issued inside the window, newest first, **whatever their
  /// status**.
  ///
  /// [open] answers "what is still unresolved". The desk needs a different
  /// question: "what did this week's work amount to" — which includes the
  /// settled cases, because a register that hides its outcomes cannot show a
  /// completion rate. The window exists because a field phone holds a growing
  /// history and the desk is a working list, not an archive.
  static Future<List<Referral>> recent({
    int withinDays = 21,
    DateTime? now,
  }) async {
    final db = await AppDatabase.instance.database;
    final cutoff = (now ?? DateTime.now()).subtract(Duration(days: withinDays));
    final rows = await db.query(
      Tables.referrals,
      where: 'issued_at >= ?',
      whereArgs: [cutoff.toIso8601String()],
      orderBy: 'issued_at DESC',
    );
    return rows.map(Referral.fromMap).toList(growable: false);
  }

  /// The referrals raised in answer to this one — the second visit of a trace
  /// that is still running. Read straight from `link_from_referral_id`, so a
  /// chain is a property of the data rather than something the UI remembers.
  static Future<List<Referral>> linkedChildren(String parentId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.referrals,
      where: 'link_from_referral_id = ?',
      whereArgs: [parentId],
      orderBy: 'issued_at ASC',
    );
    return rows.map(Referral.fromMap).toList(growable: false);
  }

  /// Urgent referrals with no confirmed arrival after 48 hours.
  ///
  /// This is the query the entire last-mile challenge reduces to. Every entry is
  /// a family who was told to go somewhere and, as far as anyone knows, did not.
  static Future<List<Referral>> needingEscalation() async {
    final all = await open();
    return all.where((r) => r.needsEscalation).toList(growable: false);
  }

  static Future<void> updateStatus({
    required String referralId,
    required ReferralStatus status,
    String? confirmedBy,
    String? outcomeNotes,
  }) async {
    final db = await AppDatabase.instance.database;
    await db.transaction(
      (txn) => updateStatusIn(
        txn,
        referralId: referralId,
        status: status,
        confirmedBy: confirmedBy,
        outcomeNotes: outcomeNotes,
      ),
    );
  }

  /// The transaction-scoped half of [updateStatus], so the follow-up answer,
  /// the status it implies and any referral it raises commit as one record.
  static Future<void> updateStatusIn(
    DatabaseExecutor db, {
    required String referralId,
    required ReferralStatus status,
    String? confirmedBy,
    String? outcomeNotes,
  }) async {
    final now = DateTime.now().toIso8601String();
    await db.update(
      Tables.referrals,
      {
        'status': status.name,
        'status_updated_at': now,
        'arrival_confirmed_by': ?confirmedBy,
        'outcome_notes': ?outcomeNotes,
        'sync_state': SyncState.pending.name,
      },
      where: 'id = ?',
      whereArgs: [referralId],
    );
    await OutboxDao.enqueue(
      db,
      table: Tables.referrals,
      entityId: referralId,
      operation: SyncOperation.update,
      payload: {
        'id': referralId,
        'status': status.name,
        'status_updated_at': now,
        'arrival_confirmed_by': confirmedBy,
        'outcome_notes': outcomeNotes,
      },
      priority: SyncPriority.clinical,
    );
  }

  static Future<void> markEscalated(String referralId) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) => markEscalatedIn(txn, referralId));
  }

  /// Stamps the escalation once and never moves it.
  ///
  /// The 48-hour banner is only honest if it fires the first time and then
  /// stops: `WHERE escalated_at IS NULL` means a second chase finds the date
  /// already set and changes nothing, so the trace keeps the day the case
  /// actually became overdue rather than the day someone last looked.
  static Future<void> markEscalatedIn(
    DatabaseExecutor db,
    String referralId, {
    DateTime? at,
  }) async {
    await db.rawUpdate(
      'UPDATE ${Tables.referrals} SET escalated_at = ? '
      'WHERE id = ? AND escalated_at IS NULL',
      [(at ?? DateTime.now()).toIso8601String(), referralId],
    );
  }

  /// Referrals this worker wrote out on [day], whatever happened to them since.
  ///
  /// Counted in SQL because the register asks only for the total, and a
  /// referral carries no JSON payload to unpick — unlike
  /// [AssessmentDao.forWorkerOn].
  static Future<int> countIssuedBy(String workerId, DateTime day) async {
    final db = await AppDatabase.instance.database;
    final window = _dayWindow(day);
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${Tables.referrals} '
      'WHERE issued_by = ? AND issued_at >= ? AND issued_at < ?',
      [workerId, window.start, window.end],
    );
    return (rows.first['c'] as num).toInt();
  }

  /// Completion rate over a window. The single number that says whether the
  /// last mile is actually being closed, rather than whether notes are being
  /// written.
  static Future<({int issued, int arrived})> completionStats({
    int withinDays = 90,
  }) async {
    final db = await AppDatabase.instance.database;
    final cutoff = DateTime.now()
        .subtract(Duration(days: withinDays))
        .toIso8601String();
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS issued,
             SUM(CASE WHEN status IN (?, ?) THEN 1 ELSE 0 END) AS arrived
      FROM ${Tables.referrals} WHERE issued_at >= ?
      ''',
      [ReferralStatus.arrived.name, ReferralStatus.treated.name, cutoff],
    );
    final r = rows.first;
    return (
      issued: (r['issued'] as num?)?.toInt() ?? 0,
      arrived: (r['arrived'] as num?)?.toInt() ?? 0,
    );
  }
}

/// The follow-up answer ledger.
///
/// Where the referral lifecycle records what the *worker decided*, this records
/// what the *family did* — which is the only half of the story the last mile
/// actually turns on. Reads here are deliberately referral-centred and
/// chronological: a case is reviewed as a trace ("referred Tuesday, visited
/// Thursday and nobody was home, went again Monday and he was still on the
/// bench"), never as a status field.
abstract final class FollowUpDao {
  static Future<void> insert(FollowUpContact c) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) => insertIn(txn, c));
  }

  /// Transaction-scoped write, used by the repository's single atomic
  /// follow-up commit. Replace-on-conflict is what makes a retry safe: the
  /// screen freezes the contact ID when it opens, so a second tap after a slow
  /// save rewrites the same row instead of logging an answer twice.
  static Future<void> insertIn(DatabaseExecutor db, FollowUpContact c) async {
    final map = c.toMap();
    await db.insert(
      Tables.followUpContacts,
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await OutboxDao.enqueue(
      db,
      table: Tables.followUpContacts,
      entityId: c.id,
      operation: SyncOperation.insert,
      payload: map,
      priority: SyncPriority.clinical,
    );
  }

  /// One follow-up answered, committed as one record.
  ///
  /// This is the whole write path for the follow-up desk: the ledger row, the
  /// referral status the answer implies, the barrier behind a failure, the
  /// visit that produced the answer, the next visit, and the chained referral
  /// a worsening child needs — in one transaction, so a phone dying mid-write
  /// leaves either a complete answer or none at all.
  ///
  /// Every row is keyed off [contactId], which the check-in screen mints once
  /// when it opens and keeps across retries. That is what makes a second tap
  /// safe: the writes collide with themselves instead of inventing a second
  /// answer, a second barrier or — worst of all — a second child in the
  /// register.
  ///
  /// [at] and [recordedBy] are passed in rather than read from the clock and
  /// the session, so the whole trace is stamped from the same instant the
  /// answer was accepted.
  static Future<FollowUpResult> record({
    required Referral referral,
    required String householdId,
    required String contactId,
    required FollowUpAnswer answer,
    required String recordedBy,
    required DateTime at,
    FollowUpReReferral? alsoReRefer,
    DateTime? nextVisitAt,
    String? completedContactId,
  }) async {
    final db = await AppDatabase.instance.database;
    return db.transaction<FollowUpResult>((txn) async {
      // The chained referral is built before the answer row because the answer
      // names it: a trace with a dangling end reads as a lost child.
      final raised = alsoReRefer == null
          ? null
          : Referral(
              id: alsoReRefer.id,
              referenceCode: alsoReRefer.referenceCode,
              personId: referral.personId,
              assessmentId: referral.assessmentId,
              facilityName: alsoReRefer.facilityName,
              reason: alsoReRefer.reason,
              urgency: alsoReRefer.urgency,
              issuedBy: recordedBy,
              issuedAt: at,
              // The receiving facility is handed the evidence from the first
              // visit, not a blank slip.
              clinicalSummary: referral.clinicalSummary,
              linkFromReferralId: referral.id,
            );

      final contact = FollowUpContact(
        id: contactId,
        referralId: referral.id,
        personId: referral.personId,
        householdId: householdId,
        at: at,
        channel: answer.channel,
        reached: answer.reached,
        care: answer.care,
        condition: answer.condition,
        barriers: answer.barriers,
        note: answer.note,
        linkedReferralId: raised?.id,
        recordedBy: recordedBy,
      );
      await insertIn(txn, contact);
      if (raised != null) await ReferralDao.upsertIn(txn, raised);

      final target = statusImpliedBy(answer, from: referral.status);
      if (target != null) {
        await ReferralDao.updateStatusIn(
          txn,
          referralId: referral.id,
          status: target,
          // The answer is given by a named worker, so the record can always
          // be asked who says so.
          confirmedBy: recordedBy,
        );
      }

      if (answer.barriers.isNotEmpty) {
        await BarrierDao.saveIn(
          txn,
          BarrierReport(
            id: 'bar-$contactId',
            householdId: householdId,
            personId: referral.personId,
            referralId: referral.id,
            barriers: answer.barriers.toList(growable: false),
            recordedBy: recordedBy,
            recordedAt: at,
            notes: answer.note,
          ),
        );
      }

      if (completedContactId != null) {
        await ScheduleDao.markDoneIn(txn, completedContactId);
      }
      if (nextVisitAt != null) {
        await ScheduleDao.upsertIn(
          txn,
          ScheduledContact(
            id: 'sc-$contactId',
            personId: referral.personId,
            householdId: householdId,
            dueDate: nextVisitAt,
            purpose: 'Re-check after referral ${referral.referenceCode}',
            createdBy: recordedBy,
            referralId: referral.id,
            priority: referral.urgency == ReferralUrgency.immediate
                ? TriageLevel.urgent
                : TriageLevel.priority,
          ),
        );
      }

      // Two visits that found nobody is a trace, not a forgetful afternoon.
      // Stamped inside this transaction and only where `escalated_at` is still
      // null, so the 48-hour banner fires once and keeps the date the case
      // actually became overdue.
      if (answer.isAttemptOnly &&
          await unansweredAttemptsIn(txn, referral.id) >=
              kUnansweredAttemptsBeforeTrace) {
        await ReferralDao.markEscalatedIn(txn, referral.id, at: at);
      }

      // Read the case back instead of rebuilding it in memory: the stored row
      // is the record, and the desk should show what the device holds.
      final rows = await txn.query(
        Tables.referrals,
        where: 'id = ?',
        whereArgs: [referral.id],
        limit: 1,
      );
      final updated = Referral.fromMap(rows.single);

      return (
        outcome: followUpOutcomeFor(
          answer: answer,
          referral: updated,
          raised: raised,
        ),
        contact: contact,
        referral: updated,
        raised: raised,
      );
    });
  }

  /// One referral's whole trace, oldest first.
  static Future<List<FollowUpContact>> forReferral(String referralId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.followUpContacts,
      where: 'referral_id = ?',
      whereArgs: [referralId],
      orderBy: 'at ASC',
    );
    return rows.map(FollowUpContact.fromMap).toList(growable: false);
  }

  /// Every referral's trace in one pass. The desk lists a dozen cases; loading
  /// them one query each would be a slow screen on a low-end phone, and the
  /// desk is read every morning.
  static Future<Map<String, List<FollowUpContact>>> forReferrals(
    Iterable<String> referralIds,
  ) async {
    final ids = referralIds.toSet();
    if (ids.isEmpty) return const {};
    final db = await AppDatabase.instance.database;
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await db.query(
      Tables.followUpContacts,
      where: 'referral_id IN ($placeholders)',
      whereArgs: ids.toList(growable: false),
      orderBy: 'referral_id, at ASC',
    );
    final out = <String, List<FollowUpContact>>{
      for (final id in ids) id: <FollowUpContact>[],
    };
    for (final row in rows) {
      final c = FollowUpContact.fromMap(row);
      out.putIfAbsent(c.referralId, () => <FollowUpContact>[]).add(c);
    }
    return out;
  }

  static Future<FollowUpContact?> latestFor(String referralId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.followUpContacts,
      where: 'referral_id = ?',
      whereArgs: [referralId],
      orderBy: 'at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : FollowUpContact.fromMap(rows.first);
  }

  /// Attempts that found nothing to report. Two of these is the trigger for a
  /// trace, because "we went twice and nobody was home" is a family avoiding
  /// care, not a worker forgetting one visit.
  static Future<int> unansweredAttempts(String referralId) async {
    final db = await AppDatabase.instance.database;
    return unansweredAttemptsIn(db, referralId);
  }

  /// Transaction-scoped half of [unansweredAttempts], so the escalation rule
  /// can count the attempt it has just written before the commit lands.
  static Future<int> unansweredAttemptsIn(
    DatabaseExecutor db,
    String referralId,
  ) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${Tables.followUpContacts} '
      'WHERE referral_id = ? AND reached = ?',
      [referralId, FollowUpReach.unknown.name],
    );
    return (rows.first['c'] as num).toInt();
  }
}

abstract final class BarrierDao {
  static Future<void> save(BarrierReport report) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) => saveIn(txn, report));
  }

  /// Transaction-scoped half of [save], so the barrier behind a "did not go"
  /// answer commits with the answer that surfaced it.
  static Future<void> saveIn(DatabaseExecutor db, BarrierReport report) async {
    final map = report.toMap();
    await db.insert(
      Tables.barrierReports,
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await OutboxDao.enqueue(
      db,
      table: Tables.barrierReports,
      entityId: report.id,
      operation: SyncOperation.insert,
      payload: map,
      priority: SyncPriority.clinical,
    );
  }

  static Future<List<BarrierReport>> forHousehold(String householdId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.barrierReports,
      where: 'household_id = ?',
      whereArgs: [householdId],
      orderBy: 'recorded_at DESC',
    );
    return rows.map(BarrierReport.fromMap).toList(growable: false);
  }

  /// Every barrier reported in a window, for zone-wide pattern detection. Nine
  /// families reporting "facility closed" in one month is one staffing problem
  /// with evidence attached, not nine family problems.
  static Future<List<BarrierReport>> withinDays(int days) async {
    final db = await AppDatabase.instance.database;
    final cutoff = DateTime.now()
        .subtract(Duration(days: days))
        .toIso8601String();
    final rows = await db.query(
      Tables.barrierReports,
      where: 'recorded_at >= ?',
      whereArgs: [cutoff],
      orderBy: 'recorded_at DESC',
    );
    return rows.map(BarrierReport.fromMap).toList(growable: false);
  }

  /// The distinct barriers a household has ever reported. Fed straight into the
  /// barrier engine, where having been told once is the strongest predictor of
  /// being told again.
  static Future<List<CareBarrier>> historyFor(String householdId) async {
    final reports = await forHousehold(householdId);
    return reports.expand((r) => r.barriers).toSet().toList(growable: false);
  }

  static Future<void> markResolved(String id) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      await txn.update(
        Tables.barrierReports,
        {'resolved': 1, 'sync_state': SyncState.pending.name},
        where: 'id = ?',
        whereArgs: [id],
      );
      await OutboxDao.enqueue(
        txn,
        table: Tables.barrierReports,
        entityId: id,
        operation: SyncOperation.update,
        payload: {'id': id, 'resolved': 1},
      );
    });
  }
}

abstract final class ScheduleDao {
  static Future<void> upsert(ScheduledContact c) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) => upsertIn(txn, c));
  }

  /// Transaction-scoped half of [upsert], so the visit that chases a referral
  /// can be written in the same commit as the referral itself.
  static Future<void> upsertIn(DatabaseExecutor db, ScheduledContact c) async {
    final map = c.toMap();
    await db.insert(
      Tables.scheduledContacts,
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await OutboxDao.enqueue(
      db,
      table: Tables.scheduledContacts,
      entityId: c.id,
      operation: SyncOperation.update,
      payload: map,
    );
  }

  static Future<void> upsertAll(List<ScheduledContact> contacts) async {
    if (contacts.isEmpty) return;
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      for (final c in contacts) {
        final map = c.toMap();
        await txn.insert(
          Tables.scheduledContacts,
          map,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await OutboxDao.enqueue(
          txn,
          table: Tables.scheduledContacts,
          entityId: c.id,
          operation: SyncOperation.update,
          payload: map,
        );
      }
    });
  }

  /// Everything due up to [horizonDays] from today, plus everything already
  /// overdue. The raw material for "Plan My Day".
  static Future<List<ScheduledContact>> due({int horizonDays = 0}) async {
    final db = await AppDatabase.instance.database;
    final horizon = DateTime.now()
        .add(Duration(days: horizonDays + 1))
        .toIso8601String();
    final rows = await db.query(
      Tables.scheduledContacts,
      where: 'completed_at IS NULL AND due_date < ?',
      whereArgs: [horizon],
      orderBy: 'due_date ASC',
    );
    return rows.map(ScheduledContact.fromMap).toList(growable: false);
  }

  static Future<List<ScheduledContact>> overdue() async {
    final db = await AppDatabase.instance.database;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final rows = await db.query(
      Tables.scheduledContacts,
      where: 'completed_at IS NULL AND due_date < ?',
      whereArgs: [today],
      orderBy: 'due_date ASC',
    );
    return rows.map(ScheduledContact.fromMap).toList(growable: false);
  }

  static Future<List<ScheduledContact>> forPerson(String personId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.scheduledContacts,
      where: 'person_id = ?',
      whereArgs: [personId],
      orderBy: 'due_date ASC',
    );
    return rows.map(ScheduledContact.fromMap).toList(growable: false);
  }

  static Future<ScheduledContact?> byId(String id) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.scheduledContacts,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : ScheduledContact.fromMap(rows.first);
  }

  /// The visits still scheduled to chase one referral.
  ///
  /// This is what stitches the desk to the day plan: a referral on "no visit
  /// soon" and a contact in "Plan My Day" used to be two clocks nobody could
  /// reconcile. Done contacts are excluded because the ledger, not the
  /// calendar, is what proves a family was seen.
  static Future<List<ScheduledContact>> forReferral(String referralId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.scheduledContacts,
      where: 'referral_id = ? AND completed_at IS NULL',
      whereArgs: [referralId],
      orderBy: 'due_date ASC',
    );
    return rows.map(ScheduledContact.fromMap).toList(growable: false);
  }

  /// Pending chases for a whole desk of referrals, in one pass.
  ///
  /// [forReferral] is the right call for one case; the desk has dozens, and
  /// looping it there turned a single screen into a query per card — audible on
  /// the low-end Androids this app is written for.
  static Future<List<ScheduledContact>> openChasesFor(
    Iterable<String> referralIds,
  ) async {
    final unique = referralIds.toSet();
    if (unique.isEmpty) return const [];
    final db = await AppDatabase.instance.database;
    final placeholders = List.filled(unique.length, '?').join(', ');
    final rows = await db.rawQuery(
      'SELECT * FROM ${Tables.scheduledContacts} '
      'WHERE completed_at IS NULL AND referral_id IN ($placeholders) '
      'ORDER BY due_date ASC',
      unique.toList(),
    );
    return rows.map(ScheduledContact.fromMap).toList(growable: false);
  }

  static Future<void> markDone(String id) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) => markDoneIn(txn, id));
  }

  /// Transaction-scoped half of [markDone], so recording an answer can close
  /// the visit that produced it in the same commit.
  static Future<void> markDoneIn(DatabaseExecutor db, String id) async {
    final now = DateTime.now().toIso8601String();
    await db.update(
      Tables.scheduledContacts,
      {'completed_at': now, 'sync_state': SyncState.pending.name},
      where: 'id = ? AND completed_at IS NULL',
      whereArgs: [id],
    );
    await OutboxDao.enqueue(
      db,
      table: Tables.scheduledContacts,
      entityId: id,
      operation: SyncOperation.update,
      payload: {'id': id, 'completed_at': now},
    );
  }

  /// How many contacts a person has missed. Feeds the vulnerability score,
  /// where a pattern of missed appointments is one of the few genuinely
  /// modifiable risks a CHO can act on this week.
  static Future<int> missedCountFor(String personId) async {
    final db = await AppDatabase.instance.database;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${Tables.scheduledContacts} '
      'WHERE person_id = ? AND completed_at IS NULL AND due_date < ?',
      [personId, today],
    );
    return (rows.first['c'] as num).toInt();
  }

  /// Missed-contact counts for every person at once, so the dashboard ranking
  /// stays one query rather than one per household.
  static Future<Map<String, int>> missedCountsForAll() async {
    final db = await AppDatabase.instance.database;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final rows = await db.rawQuery(
      'SELECT person_id, COUNT(*) AS c FROM ${Tables.scheduledContacts} '
      'WHERE completed_at IS NULL AND due_date < ? GROUP BY person_id',
      [today],
    );
    return {
      for (final r in rows) r['person_id'] as String: (r['c'] as num).toInt(),
    };
  }
}

/// The caregiver's danger-sign checks, kept on this device only.
///
/// No outbox row on purpose: a home check is the family's own working note.
/// It becomes part of the clinical conversation when the family says so —
/// by walking in, calling, or showing this screen — never silently in the
/// background.
abstract final class HomeCheckDao {
  static Future<void> save(HomeCheck check) async {
    final db = await AppDatabase.instance.database;
    await db.insert(
      Tables.homeChecks,
      check.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Newest first — the list both the caregiver and the FHW read.
  static Future<List<HomeCheck>> forHousehold(String householdId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.homeChecks,
      where: 'household_id = ?',
      whereArgs: [householdId],
      orderBy: 'checked_at DESC',
    );
    return rows.map(HomeCheck.fromMap).toList(growable: false);
  }

  /// The most recent check for one person, or null if never checked. Drives
  /// the "last checked" line on the caregiver's family tiles.
  static Future<HomeCheck?> latestForPerson(String personId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.homeChecks,
      where: 'person_id = ?',
      whereArgs: [personId],
      orderBy: 'checked_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return HomeCheck.fromMap(rows.first);
  }

  /// How many checks across every household landed on [verdict] within the
  /// window. Powers the zone impact card — families finding danger early is
  /// an outcome, not just a feature.
  static Future<int> countWithVerdict(
    HomeCheckVerdict verdict, {
    int withinDays = 30,
  }) async {
    final db = await AppDatabase.instance.database;
    final since = DateTime.now()
        .subtract(Duration(days: withinDays))
        .toIso8601String();
    final rows = await db.query(
      Tables.homeChecks,
      columns: ['COUNT(*) AS n'],
      where: 'verdict = ? AND checked_at >= ?',
      whereArgs: [verdict.name, since],
    );
    return (rows.first['n'] as num).toInt();
  }

  /// Every home check in the zone within the window, newest first. The
  /// morning briefing: what families saw at home since the worker last
  /// looked. Zone-wide on purpose — the Today tab must answer "who needs
  /// me" before any single household is opened.
  static Future<List<HomeCheck>> recentAcrossZone({int withinDays = 7}) async {
    final db = await AppDatabase.instance.database;
    final since = DateTime.now()
        .subtract(Duration(days: withinDays))
        .toIso8601String();
    final rows = await db.query(
      Tables.homeChecks,
      where: 'checked_at >= ?',
      whereArgs: [since],
      orderBy: 'checked_at DESC',
    );
    return rows.map(HomeCheck.fromMap).toList(growable: false);
  }
}

/// The family's milestone checks — nurturing care's twin of [HomeCheckDao],
/// and local-only for the identical reason: a mother's report of what her
/// child can do becomes clinical evidence when she shows it to the health
/// worker, never silently before.
abstract final class MilestoneCheckDao {
  static Future<void> save(MilestoneCheck check) async {
    final db = await AppDatabase.instance.database;
    await db.insert(
      Tables.milestoneChecks,
      check.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Newest first — the list both the caregiver and the FHW read.
  static Future<List<MilestoneCheck>> forHousehold(String householdId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.milestoneChecks,
      where: 'household_id = ?',
      whereArgs: [householdId],
      orderBy: 'checked_at DESC',
    );
    return rows.map(MilestoneCheck.fromMap).toList(growable: false);
  }

  /// The most recent milestone check for one child, or null. Drives the
  /// "growing as expected" line on the caregiver's family tiles.
  static Future<MilestoneCheck?> latestForPerson(String personId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      Tables.milestoneChecks,
      where: 'person_id = ?',
      whereArgs: [personId],
      orderBy: 'checked_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return MilestoneCheck.fromMap(rows.first);
  }

  /// Distinct children whose families raised a CCD flag within the window.
  /// A child counted once even if the family checked twice — the outcome is
  /// the child surfaced, not the number of taps.
  static Future<int> countFlaggedChildren({int withinDays = 30}) async {
    final db = await AppDatabase.instance.database;
    final since = DateTime.now()
        .subtract(Duration(days: withinDays))
        .toIso8601String();
    final rows = await db.rawQuery(
      'SELECT COUNT(DISTINCT person_id) AS n FROM '
      '${Tables.milestoneChecks} WHERE verdict = ? AND checked_at >= ?',
      [MilestoneVerdict.flag.name, since],
    );
    return (rows.first['n'] as num).toInt();
  }
}
