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

import 'package:sqflite/sqflite.dart';

import '../../domain/entities/visit.dart';
import '../../domain/enums.dart';
import 'app_database.dart';
import 'outbox_dao.dart';

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

abstract final class VisitDao {
  static Future<void> upsert(Visit visit) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      final map = visit.toMap();
      await txn.insert(
        Tables.visits,
        map,
        conflictAlgorithm: ConflictAlgorithm.replace,
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
      await txn.insert(
        Tables.visits,
        map,
        conflictAlgorithm: ConflictAlgorithm.replace,
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
    final start = DateTime(day.year, day.month, day.day).toIso8601String();
    final end = DateTime(
      day.year,
      day.month,
      day.day,
    ).add(const Duration(days: 1)).toIso8601String();
    final rows = await db.query(
      Tables.visits,
      where: 'conducted_by = ? AND started_at >= ? AND started_at < ?',
      whereArgs: [workerId, start, end],
      orderBy: 'started_at DESC',
    );
    return rows.map(Visit.fromMap).toList(growable: false);
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
      await txn.insert(
        Tables.referrals,
        rm,
        conflictAlgorithm: ConflictAlgorithm.replace,
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
}

abstract final class ReferralDao {
  static Future<void> upsert(Referral r) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      final map = r.toMap();
      await txn.insert(
        Tables.referrals,
        map,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await OutboxDao.enqueue(
        txn,
        table: Tables.referrals,
        entityId: r.id,
        operation: SyncOperation.update,
        payload: map,
        priority: r.urgency == ReferralUrgency.immediate
            ? SyncPriority.critical
            : SyncPriority.clinical,
      );
    });
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
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      await txn.update(
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
        txn,
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
    });
  }

  static Future<void> markEscalated(String referralId) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      Tables.referrals,
      {'escalated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [referralId],
    );
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

abstract final class BarrierDao {
  static Future<void> save(BarrierReport report) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      final map = report.toMap();
      await txn.insert(
        Tables.barrierReports,
        map,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await OutboxDao.enqueue(
        txn,
        table: Tables.barrierReports,
        entityId: report.id,
        operation: SyncOperation.insert,
        payload: map,
        priority: SyncPriority.clinical,
      );
    });
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
    await db.transaction((txn) async {
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
    });
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

  static Future<void> markDone(String id) async {
    final db = await AppDatabase.instance.database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      await txn.update(
        Tables.scheduledContacts,
        {'completed_at': now, 'sync_state': SyncState.pending.name},
        where: 'id = ?',
        whereArgs: [id],
      );
      await OutboxDao.enqueue(
        txn,
        table: Tables.scheduledContacts,
        entityId: id,
        operation: SyncOperation.update,
        payload: {'id': id, 'completed_at': now},
      );
    });
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
}
