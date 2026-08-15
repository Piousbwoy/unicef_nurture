/// Application wiring.
///
/// One file, deliberately. Riverpod's failure mode on a project this size is
/// providers scattered across forty files until nobody can answer "what depends
/// on the database?". Keeping the graph in one place means the answer is
/// visible.
///
/// The rule the whole app rests on: **no widget ever sees a DAO.** Screens get
/// [CareRepository] or [InsightRepository], both of which take the acting
/// [AppUser] and check permissions before touching storage. A widget that wants
/// to bypass RBAC has to import a DAO directly, which is the kind of change a
/// reviewer notices.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/session.dart';
import '../data/local/app_database.dart';
import '../data/local/outbox_dao.dart';
import '../data/local/preferences_store.dart';
import '../data/local/user_dao.dart';
import '../data/repositories/care_repository.dart';
import '../data/repositories/insight_repository.dart';
import '../data/sync/sync_service.dart';
import '../data/sync/http_transport.dart';
import '../domain/engines/barrier_engine.dart';
import '../domain/engines/trajectory_engine.dart';
import '../domain/engines/vulnerability_engine.dart';
import '../domain/entities/core.dart';
import '../domain/entities/visit.dart';
import '../domain/enums.dart';

// ---------------------------------------------------------------- Bootstrapping

/// Opens the database and starts the sync service.
///
/// Everything else waits on this. No demo data is seeded automatically: every
/// account and every record on this device is created by a real user during
/// real use.
final bootstrapProvider = FutureProvider<void>((ref) async {
  await AppDatabase.instance.database;
  // The sync service starts itself inside [syncServiceProvider], so awaiting
  // it here is enough — and a later invalidation (e.g. the sync-settings
  // screen swapping in a real server) re-creates an already-running service.
  await ref.read(syncServiceProvider.future);
});

// ------------------------------------------------------------------- Repositories

final careRepositoryProvider = Provider<CareRepository>((_) => CareRepository());

final insightRepositoryProvider = Provider<InsightRepository>(
  (_) => InsightRepository(),
);

final syncServiceProvider = FutureProvider<SyncService>((ref) async {
  // Try to create a real HTTP transport from configured preferences.
  // If no sync URL has been set, fall back to LoopbackTransport so the
  // outbox lifecycle still works for demonstration and testing.
  final transport = await HttpSyncTransport.fromPreferences();
  final service = SyncService(transport: transport);
  ref.onDispose(service.dispose);
  // Start here, not only in [bootstrapProvider]: when the sync-settings
  // screen invalidates this provider to pick up a newly configured server,
  // the replacement service must also begin listening for connectivity and
  // running its timer. [SyncService.start] is idempotent, so the bootstrap
  // path starting it again is harmless.
  await service.start();
  return service;
});

/// Drives the offline banner. Seeded with the current summary so the banner is
/// correct on first paint rather than blank until the first sync tick.
final syncStatusProvider = StreamProvider<SyncStatusSummary>((ref) async* {
  final service = await ref.watch(syncServiceProvider.future);
  await service.publishStatus();
  yield* service.status;
});

/// Whether the device currently has internet connectivity.
/// Drives the [ConnectivityPill] and any other widget that needs to know
/// in real time.
final connectivityProvider = StreamProvider<bool>((ref) async* {
  final service = await ref.watch(syncServiceProvider.future);
  // Broadcast streams do not buffer, so a subscriber that arrives after
  // start() already emitted its seed would otherwise sit blank (or show
  // "offline") until the next genuine connectivity change — an online phone
  // reading "offline" for a whole visit. Yield the live state first so the
  // pill is correct on first paint, then stream subsequent changes.
  yield await service.isOnline;
  yield* service.connectivity;
});

// ----------------------------------------------------------------------- Session

final sessionControllerProvider = Provider<SessionController>(
  (_) => SessionController(),
);

/// The single source of truth for who is signed in.
final sessionProvider = NotifierProvider<SessionNotifier, SessionState>(
  SessionNotifier.new,
);

class SessionNotifier extends Notifier<SessionState> {
  @override
  SessionState build() {
    // Restoration is async but the shell needs a state synchronously, so the
    // notifier starts in [SessionLoading] and the splash screen holds until this
    // resolves.
    Future.microtask(restore);
    return const SessionLoading();
  }

  SessionController get _controller => ref.read(sessionControllerProvider);

  Future<void> restore() async {
    await ref.read(bootstrapProvider.future);
    state = await _controller.restore();
  }

  Future<bool> signIn({required String phone, required String pin}) async {
    state = await _controller.signIn(phone: phone, pin: pin);
    return state is SessionActive;
  }

  Future<bool> register({
    required AppUser user,
    required String pin,
    String? linkedHouseholdId,
  }) async {
    state = await _controller.registerAndSignIn(
      user: user,
      pin: pin,
      linkedHouseholdId: linkedHouseholdId,
    );
    return state is SessionActive;
  }

  Future<void> signOut() async {
    final current = state;
    state = await _controller.signOut(
      current is SessionActive ? current.user : null,
    );
  }

  Future<bool> resetPin({required String phone, required String newPin}) async {
    state = await _controller.resetPin(phone: phone, newPin: newPin);
    return state is SessionSignedOut;
  }

  /// Moves a device back to the setup screen. Used by the "reset this device"
  /// action in settings, which clears data and lets a new user start fresh.
  void markNeedsSetup() => state = const SessionNeedsSetup();

  /// Persists a new guidance language in the one place every audio call site
  /// reads it — the signed-in user — then mirrors it into the preferences
  /// store and the live session state so every screen re-renders at once.
  /// The DAO enqueues the MariaDB outbox entry, so the choice also travels on
  /// the next sync window.
  Future<void> updateLanguage(String language) async {
    final current = state;
    if (current is! SessionActive) return;
    final updated = current.user.copyWith(preferredLanguage: language);
    await UserDao.updateLanguage(updated.id, language);
    await PreferencesStore.setPreferredLanguage(language);
    state = SessionActive(updated, linkedHouseholdId: current.linkedHouseholdId);
  }
}

/// The signed-in user, or null. Almost every screen wants this and nothing else.
final currentUserProvider = Provider<AppUser?>((ref) {
  final session = ref.watch(sessionProvider);
  return session is SessionActive ? session.user : null;
});

/// The household a caregiver is bound to. Null for an FHW, whose scope is a
/// whole zone rather than one household.
final linkedHouseholdProvider = Provider<String?>((ref) {
  final session = ref.watch(sessionProvider);
  return session is SessionActive ? session.linkedHouseholdId : null;
});

/// The role a user just picked on the "Who are you?" screen, carried through
/// the sign-in detour so "Create a new account" lands on the correct
/// registration form.
///
/// Set by [SetupScreen] when a role card is tapped. Read by [SignInScreen]
/// when "Create a new account" is pressed, then by [SetupScreen] again on the
/// next build to skip the role choice. Cleared by [SetupScreen] when the
/// registration form is dismissed so the choice does not leak across sessions.
final pendingRoleProvider = StateProvider<UserRole?>((ref) => null);

// -------------------------------------------------------------------- Feature reads

/// The ranked day plan for the signed-in worker's zone.
///
/// Kept as a provider rather than screen state so the dashboard, the household
/// list and the referral chase list all read the same ranking. Two screens
/// disagreeing about which compound is most at risk would cost more trust than
/// either screen earns.
final dayPlanProvider = FutureProvider<DayPlan>((ref) async {
  await ref.watch(bootstrapProvider.future);
  final user = ref.watch(currentUserProvider);
  if (user == null || !user.can(Permission.planVisitRoute)) {
    throw const AccessDenied('plan the day', Permission.planVisitRoute);
  }
  return ref.read(insightRepositoryProvider).planDay(
    workerId: user.id,
    region: user.region,
    district: user.district,
  );
});

/// Households the signed-in user may see. Different query per role — see
/// [CareRepository.visibleHouseholds].
final visibleHouseholdsProvider = FutureProvider<List<Household>>((ref) async {
  await ref.watch(bootstrapProvider.future);
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];
  return ref.read(careRepositoryProvider).visibleHouseholds(user);
});

/// Everyone in one household, ordered the way care is delivered: mother, then
/// newborns, then under-fives by age.
final householdMembersProvider =
    FutureProvider.family<List<Person>, String>((ref, householdId) async {
      final user = ref.watch(currentUserProvider);
      if (user == null) return const [];
      return ref
          .read(careRepositoryProvider)
          .visitQueue(user, householdId);
    });

final householdProvider = FutureProvider.family<Household?, String>((
  ref,
  id,
) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  return ref.read(careRepositoryProvider).household(user, id);
});

/// The vulnerability score for one compound.
///
/// Goes through [CareRepository.household] first, and discards the result. That
/// looks wasteful and is not: the insight repository has no permission layer of
/// its own — it is pure assembly over DAOs — so the scope check has to happen
/// somewhere, and borrowing the repository's is better than writing a second
/// copy of the rule that could drift from the first.
final householdScoreProvider =
    FutureProvider.family<VulnerabilityScore, String>((ref, id) async {
      final user = ref.watch(currentUserProvider);
      if (user == null) {
        throw const AccessDenied('view this risk score', null);
      }
      await ref.read(careRepositoryProvider).household(user, id);
      return ref.read(insightRepositoryProvider).scoreHousehold(id);
    });

/// The last assessment recorded for one person, or null if never assessed.
/// Drives the badge on a member tile, so a CHO can see at a glance who was left
/// amber last time.
final latestAssessmentProvider =
    FutureProvider.family<Assessment?, String>((ref, personId) async {
      final user = ref.watch(currentUserProvider);
      if (user == null) return null;
      return ref.read(careRepositoryProvider).latestAssessment(user, personId);
    });

/// One person's record, scope-checked. The assessment shell uses this rather
/// than the household member list so the permission check happens per person.
final personProvider = FutureProvider.family<Person?, String>((
  ref,
  personId,
) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  return ref.read(careRepositoryProvider).person(user, personId);
});

/// The maternal record (LMP, delivery facts, history) for one mother.
final maternalRecordProvider =
    FutureProvider.family<MaternalRecord?, String>((ref, personId) async {
      final user = ref.watch(currentUserProvider);
      if (user == null) return null;
      return ref.read(careRepositoryProvider).maternalRecord(user, personId);
    });

/// The birth record (weight, gestation, resuscitation) for one newborn.
final birthRecordProvider = FutureProvider.family<BirthRecord?, String>((
  ref,
  personId,
) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  return ref.read(careRepositoryProvider).birthRecord(user, personId);
});

/// Growth series for one child, oldest first. The raw material behind the
/// trajectory sparkline.
final growthSeriesProvider =
    FutureProvider.family<List<GrowthMeasurement>, String>((
      ref,
      personId,
    ) async {
      final user = ref.watch(currentUserProvider);
      if (user == null) return const [];
      return ref.read(careRepositoryProvider).growthSeries(user, personId);
    });

/// Trajectory analysis for one child.
final trajectoryProvider =
    FutureProvider.family<TrajectoryResult, String>((ref, personId) async {
      final series = await ref.watch(growthSeriesProvider(personId).future);
      return TrajectoryEngine.analyse(series);
    });

/// Visit history for a compound, newest first.
final visitHistoryProvider =
    FutureProvider.family<List<Visit>, String>((ref, householdId) async {
      final user = ref.watch(currentUserProvider);
      if (user == null) return const [];
      return ref.read(careRepositoryProvider).visitHistory(user, householdId);
    });

/// Why care did not happen here before. Read on the household screen because a
/// barrier the family already reported should never have to be reported twice.
final barrierHistoryProvider =
    FutureProvider.family<List<CareBarrier>, String>((
      ref,
      householdId,
    ) async {
      final user = ref.watch(currentUserProvider);
      if (user == null) return const [];
      return ref.read(careRepositoryProvider).barrierHistory(user, householdId);
    });

/// The danger-sign checks this family ran at home, newest first. The caregiver
/// reads their own history; the FHW reads what the family reported before
/// deciding whom to examine first.
final householdHomeChecksProvider =
    FutureProvider.family<List<HomeCheck>, String>((ref, householdId) async {
      final user = ref.watch(currentUserProvider);
      if (user == null) return const [];
      return ref.read(careRepositoryProvider).homeChecks(user, householdId);
    });

/// The most recent home check for one person — the "last checked" line on the
/// caregiver's family tiles.
final latestHomeCheckProvider =
    FutureProvider.family<HomeCheck?, String>((ref, personId) async {
      final user = ref.watch(currentUserProvider);
      if (user == null) return null;
      return ref.read(careRepositoryProvider).latestHomeCheck(user, personId);
    });

/// The morning briefing on the FHW's Today tab: every family's home check
/// across the zone in the last week, newest first. FHW-only by permission —
/// a caregiver gets an empty list, so the card simply never renders for them.
final zoneHomeChecksProvider = FutureProvider<List<HomeCheck>>((ref) async {
  await ref.watch(bootstrapProvider.future);
  final user = ref.watch(currentUserProvider);
  if (user == null || !user.can(Permission.viewAllHouseholds)) {
    return const [];
  }
  return ref.read(careRepositoryProvider).recentZoneHomeChecks(user);
});

/// The signed-in worker's own month — assessments written and overrides
/// recorded. Powers the "your month with this phone" card: impact the worker
/// can feel, not just numbers the district consumes.
final workerImpactProvider =
    FutureProvider<({int assessments, int overrides})>((ref) async {
      await ref.watch(bootstrapProvider.future);
      final user = ref.watch(currentUserProvider);
      if (user == null) return (assessments: 0, overrides: 0);
      return ref.read(careRepositoryProvider).personalImpact(user);
    });

/// The milestone checks this family ran at home, newest first — the nurturing
/// care mirror of [householdHomeChecksProvider].
final householdMilestoneChecksProvider =
    FutureProvider.family<List<MilestoneCheck>, String>((
      ref,
      householdId,
    ) async {
      final user = ref.watch(currentUserProvider);
      if (user == null) return const [];
      return ref
          .read(careRepositoryProvider)
          .milestoneChecks(user, householdId);
    });

/// The most recent milestone check for one child — the "growing as expected"
/// line on the caregiver's family tiles.
final latestMilestoneCheckProvider =
    FutureProvider.family<MilestoneCheck?, String>((ref, personId) async {
      final user = ref.watch(currentUserProvider);
      if (user == null) return null;
      return ref
          .read(careRepositoryProvider)
          .latestMilestoneCheck(user, personId);
    });

/// Contacts scheduled for one household, due or overdue.
final householdContactsProvider =
    FutureProvider.family<List<ScheduledContact>, String>((
      ref,
      householdId,
    ) async {
      final user = ref.watch(currentUserProvider);
      if (user == null) return const [];
      final all = await ref
          .read(careRepositoryProvider)
          .dueContacts(user, horizonDays: 14);
      return all
          .where((c) => c.householdId == householdId)
          .toList(growable: false);
    });

/// Open referrals visible to this user. For a caregiver this is their own
/// family only — the repository decides, not the screen.
final openReferralsProvider = FutureProvider<List<Referral>>((ref) async {
  await ref.watch(bootstrapProvider.future);
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];
  return ref.read(careRepositoryProvider).openReferrals(user);
});

/// Children whose MUAC is falling, worst first. The single most
/// hackathon-relevant read in the app: every one of these is a child a paper
/// register would have marked green.
final decliningChildrenProvider =
    FutureProvider<List<({Person child, TrajectoryResult trajectory})>>((
      ref,
    ) async {
      await ref.watch(bootstrapProvider.future);
      final user = ref.watch(currentUserProvider);
      if (user == null || !user.can(Permission.viewCommunityInsights)) {
        return const [];
      }
      return ref.read(insightRepositoryProvider).decliningChildren();
    });

/// Zone-wide barrier patterns — the "hidden barriers" challenge, aggregated.
final barrierPatternsProvider = FutureProvider<List<BarrierPattern>>((
  ref,
) async {
  await ref.watch(bootstrapProvider.future);
  final user = ref.watch(currentUserProvider);
  if (user == null || !user.can(Permission.viewCommunityInsights)) {
    return const [];
  }
  return ref.read(insightRepositoryProvider).zonePatterns();
});

final referralCompletionProvider =
    FutureProvider<({int issued, int arrived, double rate})>((ref) async {
      await ref.watch(bootstrapProvider.future);
      return ref.read(insightRepositoryProvider).referralCompletion();
    });

/// The zone impact summary — what this phone has caught and closed. FHW-only;
/// a caregiver watching it gets an access-denied error, which is the point.
final impactSummaryProvider = FutureProvider<
  ({int issued, int arrived, double rate, int urgentHomeChecks,
    int flaggedChildren})
>((ref) async {
  await ref.watch(bootstrapProvider.future);
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    return (issued: 0, arrived: 0, rate: 0.0, urgentHomeChecks: 0,
      flaggedChildren: 0);
  }
  return ref.read(careRepositoryProvider).impactSummary(user);
});
