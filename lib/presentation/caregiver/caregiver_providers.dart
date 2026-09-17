import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../data/repositories/care_repository.dart';
import '../../domain/entities/caregiver.dart';
import '../../domain/entities/core.dart';
import '../../domain/entities/visit.dart';
import '../../domain/enums.dart';
import '../../domain/services/caregiver_today_planner.dart';

final caregiverClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);
final caregiverScopeProvider = Provider<CaregiverScope?>((ref) {
  final user = ref.watch(currentUserProvider);
  final household = ref.watch(linkedHouseholdProvider);
  if (user == null || user.role != UserRole.caregiver || household == null) {
    return null;
  }
  return CaregiverScope(userId: user.id, householdId: household);
});

AppUser _owner(Ref ref, CaregiverScope scope) {
  final active = ref.watch(caregiverScopeProvider);
  final user = ref.watch(currentUserProvider);
  if (active != scope || user == null) {
    throw const CaregiverDataException(
      'Your account or family changed. Reopen your family.',
    );
  }
  return user;
}

/// Same watches as [_owner] but returns null instead of throwing. Used by the
/// writer, which the home shell keeps alive across the sign-out transition:
/// re-evaluating it during that flush must not throw: writes are still refused
/// by [CaregiverWriter.isCurrent] once the account is gone.
AppUser? _ownerOrNull(Ref ref, CaregiverScope scope) {
  final active = ref.watch(caregiverScopeProvider);
  final user = ref.watch(currentUserProvider);
  return active == scope ? user : null;
}

final caregiverSettingsProvider = FutureProvider.autoDispose
    .family<CaregiverSettings, CaregiverScope>((ref, scope) async {
      final user = _owner(ref, scope);
      final now = ref.watch(caregiverClockProvider);
      return await ref
              .watch(careRepositoryProvider)
              .caregiverSettings(user, scope) ??
          CaregiverSettings(scope: scope, updatedAt: now());
    });
final caregiverActivityProvider = FutureProvider.autoDispose
    .family<List<CaregiverActivity>, CaregiverScope>((ref, scope) {
      final user = _owner(ref, scope);
      return ref.watch(careRepositoryProvider).caregiverActivity(user, scope);
    });

class CaregiverClinicalData {
  const CaregiverClinicalData({
    required this.members,
    required this.checks,
    required this.milestones,
    required this.assessments,
    required this.contacts,
    required this.referrals,
  });
  final List<Person> members;
  final List<HomeCheck> checks;
  final List<MilestoneCheck> milestones;
  final List<Assessment> assessments;
  final List<ScheduledContact> contacts;
  final List<Referral> referrals;
}

final caregiverClinicalProvider = FutureProvider.autoDispose
    .family<CaregiverClinicalData, CaregiverScope>((ref, scope) async {
      final user = _owner(ref, scope);
      final repo = ref.watch(careRepositoryProvider);
      // Register all dependencies before awaiting, including the existing refresh paths.
      final membersFuture = ref.watch(
        householdMembersProvider(scope.householdId).future,
      );
      final checksFuture = ref.watch(
        householdHomeChecksProvider(scope.householdId).future,
      );
      final milestonesFuture = ref.watch(
        householdMilestoneChecksProvider(scope.householdId).future,
      );
      final referralsFuture = ref.watch(openReferralsProvider.future);
      final (members, checks, milestones, referrals) = await (
        membersFuture,
        checksFuture,
        milestonesFuture,
        referralsFuture,
      ).wait;
      final histories = await Future.wait(
        members.map((p) => repo.assessmentHistory(user, p.id)),
      );
      final contacts = await Future.wait(
        members.map((p) => repo.scheduledContactsForPerson(user, p.id)),
      );
      return CaregiverClinicalData(
        members: members,
        checks: checks,
        milestones: milestones,
        assessments: histories.expand((a) => a).toList(),
        contacts: contacts
            .expand((a) => a)
            .where((c) => c.householdId == scope.householdId)
            .toList(),
        referrals: referrals,
      );
    });

final caregiverCalendarProvider =
    StateNotifierProvider.autoDispose<CaregiverCalendar, DateTime>((ref) {
      return CaregiverCalendar(
        ref.watch(caregiverClockProvider),
        onResume: () {
          ref.invalidate(caregiverClinicalProvider);
          ref.invalidate(caregiverActivityProvider);
        },
      );
    });

/// A local calendar boundary, not a background notification or alarm.
class CaregiverCalendar extends StateNotifier<DateTime>
    with WidgetsBindingObserver {
  CaregiverCalendar(this.clock, {required this.onResume}) : super(clock()) {
    WidgetsBinding.instance.addObserver(this);
    _schedule();
  }
  final DateTime Function() clock;
  final VoidCallback onResume;
  Timer? _timer;
  void _schedule() {
    _timer?.cancel();
    final now = clock().toLocal();
    final next = DateTime(now.year, now.month, now.day + 1);
    _timer = Timer(next.difference(now), refresh);
  }

  void refresh() {
    state = clock();
    _schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      refresh();
      onResume();
    } else {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

final caregiverTodayProvider = FutureProvider.autoDispose
    .family<CaregiverDay, CaregiverScope>((ref, scope) async {
      final now = ref.watch(caregiverCalendarProvider);
      final dataFuture = ref.watch(caregiverClinicalProvider(scope).future);
      final settingsFuture = ref.watch(caregiverSettingsProvider(scope).future);
      final activityFuture = ref.watch(caregiverActivityProvider(scope).future);
      final (data, settings, activity) = await (
        dataFuture,
        settingsFuture,
        activityFuture,
      ).wait;
      return CaregiverTodayPlanner(clock: () => now).build(
        scope: scope,
        members: data.members,
        checks: data.checks,
        referrals: data.referrals,
        contacts: data.contacts,
        assessments: data.assessments,
        activity: activity,
        selectedPersonId: settings.selectedPersonId,
      );
    });

/// One write queue per live account/family. Settings edits read the latest saved
/// value inside the queue, so a food edit cannot overwrite a contact edit.
final caregiverWriterProvider = Provider.autoDispose
    .family<CaregiverWriter, CaregiverScope>((ref, scope) {
      final user = _ownerOrNull(ref, scope);
      var alive = true;
      ref.onDispose(() => alive = false);
      return CaregiverWriter(
        scope: scope,
        user: user,
        repository: ref.watch(careRepositoryProvider),
        clock: ref.watch(caregiverClockProvider),
        isCurrent: () =>
            alive &&
            user != null &&
            ref.read(caregiverScopeProvider) == scope,
        changed: () {
          if (!alive) return;
          ref.invalidate(caregiverSettingsProvider(scope));
          ref.invalidate(caregiverActivityProvider(scope));
        },
      );
    });

class CaregiverWriter {
  CaregiverWriter({
    required this.scope,
    required this.user,
    required this.repository,
    required this.clock,
    required this.isCurrent,
    required this.changed,
  });
  final CaregiverScope scope;
  final AppUser? user;
  final CareRepository repository;
  final DateTime Function() clock;
  final bool Function() isCurrent;
  final VoidCallback changed;
  Future<void> _tail = Future.value();

  Future<void> _enqueue(Future<void> Function() action) {
    final result = _tail.then((_) async {
      if (!isCurrent()) {
        throw const CaregiverDataException(
          'Your account changed. Reopen your family.',
        );
      }
      await action();
      if (isCurrent()) changed();
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> settings(CaregiverSettings Function(CaregiverSettings) edit) =>
      _enqueue(() async {
        final current = user;
        if (current == null) {
          throw const CaregiverDataException(
            'Your account changed. Reopen your family.',
          );
        }
        final saved =
            await repository.caregiverSettings(current, scope) ??
            CaregiverSettings(scope: scope, updatedAt: clock());
        await repository.saveCaregiverSettings(
          current,
          edit(saved).copyWith(updatedAt: clock()),
        );
      });

  Future<void> activity(CaregiverActivity activity) =>
      _enqueue(() async {
        final current = user;
        if (current == null) {
          throw const CaregiverDataException(
            'Your account changed. Reopen your family.',
          );
        }
        await repository.saveCaregiverActivity(current, activity);
      });

  CaregiverActivity entry({
    required CaregiverActivityKind kind,
    String? personId,
    String sourceId = '',
    required String itemKey,
    String? occurrenceKey,
    bool done = true,
    String note = '',
    CaregiverObservation? observation,
    Map<String, Object?> detail = const {},
  }) {
    final now = clock();
    final id = const Uuid().v4();
    return CaregiverActivity(
      id: id,
      scope: scope,
      personId: personId,
      kind: kind,
      sourceId: sourceId,
      itemKey: itemKey,
      occurrenceKey: occurrenceKey ?? id,
      occurredAt: now,
      updatedAt: now,
      done: done,
      note: note,
      observation: observation,
      detail: detail,
    );
  }
}
