import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../../domain/engines/recommendation_engine.dart';

import '../../domain/entities/caregiver.dart';
import '../../domain/entities/visit.dart';
import '../../domain/entities/core.dart';
import '../../domain/services/caregiver_check_policy.dart';
import '../../domain/services/caregiver_milestone_policy.dart';
import 'app_database.dart';

/// Internal persistence boundary. Widgets access this only via CareRepository.
/// All operations recheck persisted linkage inside the same transaction.
abstract final class CaregiverDao {
  static final Map<CaregiverScope, Future<void>> _tails = {};
  static const _scopeWhere = 'user_id = ? AND household_id = ?';
  static List<Object?> _args(CaregiverScope scope) => [
    scope.userId,
    scope.householdId,
  ];

  static Future<T> _run<T>(
    CaregiverScope scope,
    String? personId,
    Future<T> Function(Transaction txn) action,
  ) {
    final previous = _tails[scope] ?? Future<void>.value();
    final result = previous.then((_) async {
      final db = await AppDatabase.instance.database;
      return db.transaction((txn) async {
        await _guard(txn, scope, personId);
        return action(txn);
      });
    });
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _tails[scope] = tail;
    tail.then((_) {
      if (identical(_tails[scope], tail)) _tails.remove(scope);
    });
    return result;
  }

  static Future<void> _guard(
    DatabaseExecutor db,
    CaregiverScope scope,
    String? personId,
  ) async {
    final users = await db.query(
      Tables.users,
      columns: ['role', 'linked_household_id'],
      where: 'id = ?',
      whereArgs: [scope.userId],
    );
    if (users.length != 1 ||
        users.single['role'] != 'caregiver' ||
        users.single['linked_household_id'] != scope.householdId) {
      throw const CaregiverDataException(
        'Your family link changed. Reopen your family before saving.',
      );
    }
    if (personId != null) {
      final people = await db.query(
        Tables.persons,
        columns: ['id'],
        where: 'id = ? AND household_id = ? AND is_active = 1',
        whereArgs: [personId, scope.householdId],
      );
      if (people.length != 1) {
        throw const CaregiverDataException(
          'This person is not in your current family.',
        );
      }
    }
  }

  static Future<CaregiverSettings?> settings(CaregiverScope scope) =>
      _run(scope, null, (txn) async {
        final rows = await txn.query(
          Tables.caregiverSettings,
          where: _scopeWhere,
          whereArgs: _args(scope),
        );
        return rows.isEmpty ? null : CaregiverSettings.fromMap(rows.single);
      });

  static Future<void> saveSettings(CaregiverSettings settings) =>
      _run(settings.scope, settings.selectedPersonId, (txn) async {
        await txn.insert(
          Tables.caregiverSettings,
          settings.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });

  static Future<CaregiverDraft?> draft(
    CaregiverScope scope,
    String personId,
    CaregiverDraftKind kind,
  ) => _run(scope, personId, (txn) async {
    final rows = await txn.query(
      Tables.caregiverDrafts,
      where: '$_scopeWhere AND person_id = ? AND kind = ?',
      whereArgs: [..._args(scope), personId, kind.name],
    );
    return rows.isEmpty ? null : CaregiverDraft.fromMap(rows.single);
  });

  static Future<void> saveDraft(CaregiverDraft draft) =>
      _run(draft.scope, draft.personId, (txn) async {
        final table = draft.kind == CaregiverDraftKind.homeCheck
            ? Tables.homeChecks
            : Tables.milestoneChecks;
        final completed = await txn.query(
          table,
          columns: ['id'],
          where: 'id = ?',
          whereArgs: [draft.id],
        );
        if (completed.isNotEmpty) {
          throw const CaregiverDataException(
            'This check is already complete. Start a new check.',
          );
        }
        final rows = await txn.query(
          Tables.caregiverDrafts,
          where: 'id = ?',
          whereArgs: [draft.id],
        );
        if (rows.isNotEmpty) {
          final saved = CaregiverDraft.fromMap(rows.single);
          if (saved.scope != draft.scope ||
              saved.personId != draft.personId ||
              saved.kind != draft.kind ||
              saved.startedAt != draft.startedAt ||
              saved.cohortKey != draft.cohortKey ||
              saved.questionVersion != draft.questionVersion) {
            throw const CaregiverDataException(
              'The saved check belongs to a different session.',
            );
          }
          if (draft.updatedAt.isBefore(saved.updatedAt)) return;
          await txn.update(
            Tables.caregiverDrafts,
            draft.toMap(),
            where: 'id = ?',
            whereArgs: [draft.id],
          );
        } else {
          // A second active session is rejected, not silently substituted.
          await txn.insert(Tables.caregiverDrafts, draft.toMap());
        }
      });

  static Future<void> discardDraft(
    CaregiverScope scope,
    String personId,
    CaregiverDraftKind kind,
  ) => _run(scope, personId, (txn) async {
    await txn.delete(
      Tables.caregiverDrafts,
      where: '$_scopeWhere AND person_id = ? AND kind = ?',
      whereArgs: [..._args(scope), personId, kind.name],
    );
  });

  static Future<List<CaregiverActivity>> activity(
    CaregiverScope scope, {
    String? personId,
  }) => _run(scope, personId, (txn) async {
    final rows = await txn.query(
      Tables.caregiverActivity,
      where: '$_scopeWhere${personId == null ? '' : ' AND person_id = ?'}',
      whereArgs: [..._args(scope), if (personId != null) personId],
      orderBy: 'occurred_at DESC, id',
    );
    return rows.map(CaregiverActivity.fromMap).toList(growable: false);
  });

  static Future<void> saveActivity(
    CaregiverActivity activity,
  ) => _run(activity.scope, activity.personId, (txn) async {
    if (activity.kind == CaregiverActivityKind.planAction) {
      final rows = await txn.query(
        Tables.assessments,
        where: 'id = ? AND person_id = ?',
        whereArgs: [activity.sourceId, activity.personId],
      );
      bool allowed = false;
      try {
        if (rows.length == 1 && activity.occurrenceKey == activity.sourceId) {
          final raw = Assessment.fromMap(rows.single).carePlanJson;
          final plan = CarePlan.fromJson(
            Map<String, Object?>.from(jsonDecode(raw!) as Map),
          );
          allowed = plan.actions.any(
            (a) =>
                CaregiverActivity.mayComplete(a) &&
                jsonEncode(a.toJson()) == activity.itemKey,
          );
        }
      } catch (_) {
        allowed = false;
      }
      if (!allowed) {
        throw const CaregiverDataException(
          'Only counseling steps from this person’s saved plan can be checked.',
        );
      }
    }
    if (activity.kind == CaregiverActivityKind.observation ||
        activity.kind == CaregiverActivityKind.arrival) {
      final rows = await txn.query(
        Tables.homeChecks,
        columns: ['id'],
        where: 'id = ? AND household_id = ? AND person_id = ?',
        whereArgs: [
          activity.sourceId,
          activity.scope.householdId,
          activity.personId,
        ],
      );
      if (rows.length != 1) {
        throw const CaregiverDataException(
          'The original check could not be found for this person.',
        );
      }
    }
    await _saveActivity(txn, activity);
  });

  static Future<void> _saveActivity(
    Transaction txn,
    CaregiverActivity activity,
  ) async {
    final sameId = await txn.query(
      Tables.caregiverActivity,
      where: 'id = ?',
      whereArgs: [activity.id],
    );
    final rows = await txn.query(
      Tables.caregiverActivity,
      where:
          '$_scopeWhere AND person_id IS ? AND kind = ? AND source_id = ? AND item_key = ? AND occurrence_key = ?',
      whereArgs: [
        ..._args(activity.scope),
        activity.personId,
        activity.kind.name,
        activity.sourceId,
        activity.itemKey,
        activity.occurrenceKey,
      ],
    );
    if (sameId.isNotEmpty &&
        (rows.isEmpty || rows.single['id'] != activity.id)) {
      throw const CaregiverDataException('This activity ID is already in use.');
    }
    if (rows.isEmpty) {
      await txn.insert(Tables.caregiverActivity, activity.toMap());
      return;
    }
    final saved = CaregiverActivity.fromMap(rows.single);
    if (activity.isImmutable) {
      if (saved.toMap()['content_json'] != activity.toMap()['content_json']) {
        throw const CaregiverDataException(
          'Saved observations cannot be rewritten. Add a new note.',
        );
      }
      return;
    }
    if (activity.updatedAt.isBefore(saved.updatedAt)) return;
    final values = activity.toMap()
      ..['id'] = saved.id
      ..['occurred_at'] = saved.occurredAt.toIso8601String();
    await txn.update(
      Tables.caregiverActivity,
      values,
      where: 'id = ?',
      whereArgs: [saved.id],
    );
  }

  static Future<void> saveLegacyHomeCheck(
    CaregiverScope scope,
    HomeCheck report,
  ) => _run(
    scope,
    report.personId,
    (txn) => _saveLegacy(txn, scope, Tables.homeChecks, report.toMap()),
  );

  static Future<void> saveLegacyMilestone(
    CaregiverScope scope,
    MilestoneCheck report,
  ) => _run(
    scope,
    report.personId,
    (txn) => _saveLegacy(txn, scope, Tables.milestoneChecks, report.toMap()),
  );

  static Future<void> _saveLegacy(
    Transaction txn,
    CaregiverScope scope,
    String table,
    Map<String, Object?> report,
  ) async {
    if (report['checked_by'] != scope.userId ||
        report['household_id'] != scope.householdId) {
      throw const CaregiverDataException(
        'This report belongs to another caregiver.',
      );
    }
    final existing = await txn.query(
      table,
      where: 'id = ?',
      whereArgs: [report['id']],
    );
    if (existing.isNotEmpty) {
      if (report.entries.any((e) => existing.single[e.key] != e.value)) {
        throw const CaregiverDataException(
          'A completed check cannot be changed. Start a new check.',
        );
      }
      return;
    }
    await txn.insert(table, report);
  }

  static Future<HomeCheck> finalizeHomeCheck(
    CaregiverDraft draft,
    HomeCheck report,
    DateTime now,
  ) => _run(draft.scope, draft.personId, (txn) async {
    final rowsBefore = await txn.query(
      Tables.persons,
      where: 'id = ?',
      whereArgs: [draft.personId],
    );
    final person = Person.fromMap(rowsBefore.single);
    final policy = CaregiverCheckPolicy(clock: () => now);
    if (!policy.compatible(draft, person)) {
      throw const CaregiverDataException(
        'The person or question group changed. Start a new check.',
      );
    }
    await _finalize(
      txn,
      draft,
      Tables.homeChecks,
      report.toMap(),
      CaregiverActivityKind.homeCheckContext,
    );
    final rows = await txn.query(
      Tables.homeChecks,
      where: 'id = ?',
      whereArgs: [draft.id],
    );
    return HomeCheck.fromMap(rows.single);
  });

  static Future<MilestoneCheck> finalizeMilestone(
    CaregiverDraft draft,
    MilestoneCheck report,
    DateTime now,
  ) => _run(draft.scope, draft.personId, (txn) async {
    final rowsBefore = await txn.query(
      Tables.persons,
      where: 'id = ?',
      whereArgs: [draft.personId],
    );
    CaregiverMilestonePolicy.report(
      draft,
      Person.fromMap(rowsBefore.single),
      now,
    );
    await _finalize(
      txn,
      draft,
      Tables.milestoneChecks,
      report.toMap(),
      CaregiverActivityKind.milestoneContext,
    );
    final rows = await txn.query(
      Tables.milestoneChecks,
      where: 'id = ?',
      whereArgs: [draft.id],
    );
    return MilestoneCheck.fromMap(rows.single);
  });

  static Future<void> _finalize(
    Transaction txn,
    CaregiverDraft draft,
    String table,
    Map<String, Object?> report,
    CaregiverActivityKind kind,
  ) async {
    if (report['id'] != draft.id ||
        report['checked_by'] != draft.scope.userId ||
        report['person_id'] != draft.personId ||
        report['household_id'] != draft.scope.householdId ||
        report['checked_at'] != draft.startedAt.toIso8601String()) {
      throw const CaregiverDataException(
        'The report does not match its check session.',
      );
    }
    final context = CaregiverActivity(
      id: '${draft.id}:context',
      scope: draft.scope,
      personId: draft.personId,
      kind: kind,
      sourceId: draft.id,
      itemKey: 'report',
      occurrenceKey: draft.id,
      occurredAt: draft.startedAt,
      updatedAt: draft.updatedAt,
      note: draft.onsetNote,
      detail: {
        'questionVersion': draft.questionVersion,
        'cohort': draft.cohortKey,
        'answers': {
          for (final key in draft.answers.keys.toList()..sort())
            key: draft.answers[key]!.name,
        },
        // Worry, duration and pre-care context travel with the report so the
        // nurse summary can show them for older checks too. Absent on rows
        // finalized before these screens existed — readers tolerate null.
        if (draft.concerns != null)
          'concerns': draft.concerns,
        if (draft.durationKey != null) 'duration': draft.durationKey,
        if (draft.givenCare.isNotEmpty)
          'given': draft.givenCare.toList()..sort(),
      },
    );
    final existing = await txn.query(
      table,
      where: 'id = ?',
      whereArgs: [draft.id],
    );
    if (existing.isNotEmpty) {
      if (report.entries.any((e) => existing.single[e.key] != e.value)) {
        throw const CaregiverDataException(
          'A completed check cannot be changed. Start a new check.',
        );
      }
      final savedContext = await txn.query(
        Tables.caregiverActivity,
        where: 'id = ?',
        whereArgs: [context.id],
      );
      if (savedContext.isEmpty ||
          savedContext.single['content_json'] !=
              context.toMap()['content_json']) {
        throw const CaregiverDataException(
          'A completed check context cannot be changed. Start a new check.',
        );
      }
      return;
    }
    final drafts = await txn.query(
      Tables.caregiverDrafts,
      where: '$_scopeWhere AND person_id = ? AND kind = ?',
      whereArgs: [..._args(draft.scope), draft.personId, draft.kind.name],
    );
    if (drafts.isNotEmpty && drafts.single['id'] != draft.id) {
      throw const CaregiverDataException(
        'Another check is in progress. Review it before continuing.',
      );
    }
    final idCollision = await txn.query(
      Tables.caregiverDrafts,
      where: 'id = ?',
      whereArgs: [draft.id],
    );
    if (idCollision.isNotEmpty &&
        (idCollision.single['user_id'] != draft.scope.userId ||
            idCollision.single['household_id'] != draft.scope.householdId ||
            idCollision.single['person_id'] != draft.personId)) {
      throw const CaregiverDataException('This check ID is already in use.');
    }
    if (drafts.isNotEmpty) {
      final saved = CaregiverDraft.fromMap(drafts.single);
      if (saved.startedAt != draft.startedAt ||
          saved.cohortKey != draft.cohortKey ||
          saved.questionVersion != draft.questionVersion ||
          draft.updatedAt.isBefore(saved.updatedAt)) {
        throw const CaregiverDataException(
          'The saved draft changed. Review it before continuing.',
        );
      }
    }
    await txn.insert(table, report);
    await _saveActivity(txn, context);
    await txn.delete(
      Tables.caregiverDrafts,
      where: 'id = ? AND $_scopeWhere',
      whereArgs: [draft.id, ..._args(draft.scope)],
    );
  }
}
