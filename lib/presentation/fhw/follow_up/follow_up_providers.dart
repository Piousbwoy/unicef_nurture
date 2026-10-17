/// The reads behind the follow-up desk, kept out of `app/providers.dart`.
///
/// Three sources become one board: the referrals this device issued and the
/// answers they collected ([CareRepository.followUpDesk]), and the day plan's
/// walk ([DayPlan]) — because a referral only becomes answerable when a
/// household is on a route. The joining rule lives in [buildFollowUpDesk] so
/// the ordering can be read and tested without a screen.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../data/repositories/care_repository.dart';
import '../../../domain/entities/core.dart';
import '../../../domain/services/follow_up_policy.dart';

/// Everything the desk draws, already sorted.
class FollowUpBoard {
  const FollowUpBoard({
    required this.desk,
    required this.people,
    required this.routeHouseholds,
    required this.chaseDueAt,
    required this.generatedAt,
  });

  final FollowUpDesk desk;

  /// Person behind each case, by person id. Absent when the record is no
  /// longer on file — the case stays, unnamed, rather than vanishing.
  final Map<String, Person> people;

  /// Households with a visit due or overdue today. The only honest meaning of
  /// "on your route": the worker is walking there anyway.
  final Set<String> routeHouseholds;

  /// When a chase visit is already booked for a referral, by referral id. This
  /// is what keeps "put this household on a route" from booking the family a
  /// second visit the second time a worker taps it.
  final Map<String, DateTime> chaseDueAt;

  final DateTime generatedAt;

  Person? personOf(FollowUpCase item) => people[item.referral.personId];

  DateTime? chaseDue(FollowUpCase item) => chaseDueAt[item.referral.id];
}

/// The follow-up desk for the signed-in worker.
///
/// Reads the day plan's value rather than awaiting it: the Route tab already
/// asked for that zone-wide ranking, and the desk must not block on a second
/// pass — nor become unrenderable because the plan itself failed.
final followUpDeskProvider = FutureProvider<FollowUpBoard>((ref) async {
  await ref.watch(bootstrapProvider.future);
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    throw const AccessDenied('view the follow-up desk', null);
  }
  final raw = await ref.read(careRepositoryProvider).followUpDesk(user);
  final plan = ref.watch(dayPlanProvider).valueOrNull;
  final route = {
    for (final contact in [...?plan?.dueContacts, ...?plan?.overdueContacts])
      contact.householdId,
  };
  final now = DateTime.now();
  return FollowUpBoard(
    desk: buildFollowUpDesk(
      referrals: raw.referrals,
      ledger: raw.ledger,
      householdOf: {
        for (final entry in raw.people.entries)
          entry.key: entry.value.householdId,
      },
      routeHouseholds: route,
      now: now,
    ),
    people: raw.people,
    routeHouseholds: route,
    // `due` is already ascending, so the first chase per referral wins.
    chaseDueAt: {
      for (final chase in raw.chases) chase.referralId!: chase.dueDate,
    },
    generatedAt: now,
  );
});

/// The one refresh every write on this desk performs.
///
/// A follow-up touches the referrals table, the schedule, the barrier history
/// and the route ranking at once, so those reads are re-invalidated together —
/// an out-of-date Route tab is how a worker visits a family twice.
void refreshFollowUpDesk(WidgetRef ref) {
  ref.invalidate(followUpDeskProvider);
  ref.invalidate(openReferralsProvider);
  ref.invalidate(dayPlanProvider);
  ref.invalidate(referralCompletionProvider);
}
