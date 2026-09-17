import 'dart:convert';

import '../engines/nurturing_care_engine.dart';
import '../engines/recommendation_engine.dart';
import '../entities/caregiver.dart';
import '../entities/core.dart';
import '../entities/visit.dart';
import '../enums.dart';
import 'caregiver_food_planner.dart';
import 'caregiver_milestone_policy.dart';

enum CaregiverFocusSource {
  clinic('From your clinic'),
  homeCheck('Your home check'),
  everyday('Everyday guidance');

  const CaregiverFocusSource(this.label);
  final String label;
}

enum CaregiverFocusRoute { check, carePlan, food, play, help }

class CaregiverFocus {
  const CaregiverFocus({
    required this.personId,
    required this.sourceId,
    required this.itemKey,
    required this.source,
    required this.title,
    required this.detail,
    required this.route,
    required this.priority,
    required this.sourceTime,
    this.dueDate,
    this.canComplete = false,
    this.done = false,
  });
  final String personId;
  final String sourceId;
  final String itemKey;
  final CaregiverFocusSource source;
  final String title;
  final String detail;
  final CaregiverFocusRoute route;
  final int priority;
  final DateTime sourceTime;
  final DateTime? dueDate;
  final bool canComplete;
  final bool done;
  String get identity => jsonEncode([personId, sourceId, itemKey]);
}

class CaregiverDay {
  CaregiverDay({
    required this.dateKey,
    required List<CaregiverFocus> attention,
    required List<CaregiverFocus> routine,
  }) : attention = List.unmodifiable(attention),
       routine = List.unmodifiable(routine);
  final String dateKey;
  final List<CaregiverFocus> attention;
  final List<CaregiverFocus> routine;
  List<CaregiverFocus> get focus => routine.take(3).toList(growable: false);
}

/// Deterministic local guidance, not predictions or booked appointments.
class CaregiverTodayPlanner {
  CaregiverTodayPlanner({required this.clock});
  final DateTime Function() clock;
  CaregiverDay build({
    required CaregiverScope scope,
    required List<Person> members,
    List<HomeCheck> checks = const [],
    List<Referral> referrals = const [],
    List<ScheduledContact> contacts = const [],
    List<Assessment> assessments = const [],
    List<CaregiverActivity> activity = const [],
    String? selectedPersonId,
  }) {
    final now = clock().toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final dateKey = caregiverDateKey(now);
    final people = {
      for (final p in members)
        if (p.householdId == scope.householdId && p.isActive) p.id: p,
    };
    final attention = <String, CaregiverFocus>{};
    final routine = <String, CaregiverFocus>{};
    void add(CaregiverFocus item, {bool urgent = false}) {
      if (!people.containsKey(item.personId)) return;
      // Emergency information remains visible even when another person is selected.
      if (!urgent &&
          selectedPersonId != null &&
          item.personId != selectedPersonId)
        return;
      (urgent ? attention : routine).putIfAbsent(item.identity, () => item);
    }

    bool done(String personId, String key) => activity.any(
      (a) =>
          a.scope == scope &&
          a.personId == personId &&
          a.kind == CaregiverActivityKind.dailyTask &&
          a.sourceId == 'everyday' &&
          a.itemKey == key &&
          a.occurrenceKey == dateKey &&
          a.done,
    );

    for (final referral in referrals) {
      if (!referral.status.isOpen) continue;
      final urgent =
          referral.urgency == ReferralUrgency.immediate ||
          referral.urgency == ReferralUrgency.sameDay;
      add(
        CaregiverFocus(
          personId: referral.personId,
          sourceId: referral.id,
          itemKey: 'referral',
          source: CaregiverFocusSource.clinic,
          title: urgent
              ? 'Follow the clinic’s urgent referral'
              : 'Your clinic referral',
          detail:
              '${referral.facilityName} · ${referral.urgency.label}. Arrival has not been confirmed by the clinic.',
          route: CaregiverFocusRoute.carePlan,
          priority: urgent ? 0 : 3,
          sourceTime: referral.issuedAt,
        ),
        urgent: urgent,
      );
    }
    final concerning =
        checks
            .where(
              (c) =>
                  c.householdId == scope.householdId &&
                  c.verdict != HomeCheckVerdict.fine,
            )
            .toList()
          ..sort((a, b) => b.checkedAt.compareTo(a.checkedAt));
    final seen = <String>{};
    for (final check in concerning) {
      if (!seen.add(check.personId)) continue;
      add(
        CaregiverFocus(
          personId: check.personId,
          sourceId: check.id,
          itemKey: 'concerning-check',
          source: CaregiverFocusSource.homeCheck,
          title: check.verdict == HomeCheckVerdict.urgent
              ? 'Danger signs were reported at home'
              : 'Some home-check answers were uncertain',
          detail:
              'Saved caregiver report. If care has not been received, ${check.verdict == HomeCheckVerdict.urgent ? 'seek urgent help now' : 'contact a health worker today'}. '
              'A later “better” note does not medically clear this report.',
          route: CaregiverFocusRoute.check,
          priority: check.verdict == HomeCheckVerdict.urgent ? 1 : 2,
          sourceTime: check.checkedAt,
        ),
        urgent: true,
      );
    }
    // The recheck promise: a caregiver who ticked "I will check again
    // tomorrow" sees that promise today, whatever else is selected, until
    // a new check for the same person discharges it.
    for (final person in people.values) {
      final promised = activity.any(
        (a) =>
            a.scope == scope &&
            a.personId == person.id &&
            a.kind == CaregiverActivityKind.dailyTask &&
            a.sourceId != 'everyday' &&
            a.itemKey == 'recheck' &&
            a.occurrenceKey == dateKey,
      );
      if (!promised) continue;
      final checkedToday = checks.any(
        (c) =>
            c.householdId == scope.householdId &&
            c.personId == person.id &&
            caregiverDateKey(c.checkedAt) == dateKey,
      );
      if (checkedToday) continue;
      add(
        CaregiverFocus(
          personId: person.id,
          sourceId: 'recheck',
          itemKey: 'recheck-promised',
          source: CaregiverFocusSource.homeCheck,
          title:
              'You promised to check '
              '${person.fullName.split(' ').first} again today',
          detail:
              'A check asked to be repeated today. If anything worries you, '
              'run the danger-sign check now.',
          route: CaregiverFocusRoute.check,
          priority: 2,
          sourceTime: today,
        ),
        urgent: true,
      );
    }
    final orderedContacts =
        contacts.where((c) => c.householdId == scope.householdId).toList()
          ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    for (final contact in orderedContacts) {
      if (contact.isDone) continue;
      final due = contact.dueDate.toLocal();
      add(
        CaregiverFocus(
          personId: contact.personId,
          sourceId: contact.assessmentId ?? contact.id,
          itemKey: 'contact:${contact.purpose.trim().toLowerCase()}',
          source: CaregiverFocusSource.clinic,
          title: contact.purpose,
          detail:
              'Scheduled contact recorded by your clinic. Check arrangements with your health worker.',
          route: CaregiverFocusRoute.carePlan,
          priority: DateTime(due.year, due.month, due.day).isAfter(today)
              ? 5
              : 3,
          sourceTime: contact.dueDate,
          dueDate: contact.dueDate,
        ),
      );
    }
    final latest = <String, Assessment>{};
    for (final assessment in assessments) {
      final previous = latest[assessment.personId];
      if (previous == null ||
          previous.performedAt.isBefore(assessment.performedAt))
        latest[assessment.personId] = assessment;
    }
    for (final assessment in latest.values) {
      int? days = assessment.result.followUpInDays;
      final raw = assessment.carePlanJson;
      if (raw != null) {
        try {
          days = CarePlan.fromJson(
            Map<String, Object?>.from(jsonDecode(raw) as Map),
          ).followUpInDays;
        } catch (_) {
          add(
            CaregiverFocus(
              personId: assessment.personId,
              sourceId: assessment.id,
              itemKey: 'unreadable-plan',
              source: CaregiverFocusSource.clinic,
              title: 'Saved clinic advice could not be read',
              detail:
                  'Ask your health worker to review the original plan. No completed progress was assumed.',
              route: CaregiverFocusRoute.carePlan,
              priority: 4,
              sourceTime: assessment.performedAt,
            ),
          );
          continue;
        }
      }
      if (days == null || days < 0) continue;
      // The clinical result screen persists “<classification> — review”. A
      // matching explicit record (including completed ones) replaces this derivation.
      final purpose = '${assessment.result.classification} — review'
          .trim()
          .toLowerCase();
      if (orderedContacts.any(
        (c) =>
            c.personId == assessment.personId &&
            c.assessmentId == assessment.id &&
            c.purpose.trim().toLowerCase() == purpose,
      ))
        continue;
      final origin = assessment.performedAt.toLocal();
      final due = DateTime(origin.year, origin.month, origin.day + days);
      add(
        CaregiverFocus(
          personId: assessment.personId,
          sourceId: assessment.id,
          itemKey: 'follow-up',
          source: CaregiverFocusSource.clinic,
          title: 'Review the health worker’s advice',
          detail:
              'Follow-up date calculated from the saved assessment. This is not a booked appointment.',
          route: CaregiverFocusRoute.carePlan,
          priority: due.isAfter(today) ? 5 : 4,
          sourceTime: assessment.performedAt,
          dueDate: due,
        ),
      );
    }
    for (final person in people.values) {
      final child =
          person.clientType == ClientType.newborn ||
          person.clientType == ClientType.childUnderFive;
      final age = CaregiverFoodPlanner.ageMonths(person, now);
      if (!child || age != null) {
        add(
          CaregiverFocus(
            personId: person.id,
            sourceId: 'everyday',
            itemKey: 'feeding',
            source: CaregiverFocusSource.everyday,
            title: child && age! < 6
                ? 'Feeding support today'
                : 'Food for today',
            detail:
                'Practical household ideas, separate from any prescribed feeding plan.',
            route: CaregiverFocusRoute.food,
            priority: 6,
            sourceTime: today,
            canComplete: true,
            done: done(person.id, 'feeding'),
          ),
        );
      }
      final band = CaregiverMilestonePolicy.bandFor(person, now);
      if (band != null) {
        add(
          CaregiverFocus(
            personId: person.id,
            sourceId: 'everyday',
            itemKey: 'play',
            source: CaregiverFocusSource.everyday,
            title: 'Play together today',
            detail: NurturingCareEngine.activityToday(band, now),
            route: CaregiverFocusRoute.play,
            priority: 6,
            sourceTime: today,
            canComplete: true,
            done: done(person.id, 'play'),
          ),
        );
      }
    }
    int compare(CaregiverFocus a, CaregiverFocus b) {
      final priority = a.priority.compareTo(b.priority);
      if (priority != 0) return priority;
      if (a.done != b.done) return a.done ? 1 : -1;
      final due = (a.dueDate ?? a.sourceTime).compareTo(
        b.dueDate ?? b.sourceTime,
      );
      return due != 0 ? due : a.identity.compareTo(b.identity);
    }

    return CaregiverDay(
      dateKey: dateKey,
      attention: attention.values.toList()..sort(compare),
      routine: routine.values.toList()..sort(compare),
    );
  }
}
