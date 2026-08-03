/// Where the database meets the AI engines.
///
/// The engines are pure functions over an input object — deliberately, so they
/// can be unit-tested against published protocol tables without a database in
/// sight. This repository is the other half: it *assembles* those inputs from
/// whatever the records actually contain, which in Northern Ghana is never
/// everything.
///
/// The hard part is not the scoring. It is doing this for 245 households on a
/// low-end Android phone, in under a second, before a CHO loses patience and
/// goes back to the paper register. So the reads are batched — five queries for
/// the whole zone, not five per household — and the ranking happens in Dart over
/// data already in memory.
library;

import 'package:collection/collection.dart';

import '../../domain/engines/barrier_engine.dart';
import '../../domain/engines/trajectory_engine.dart';
import '../../domain/engines/vulnerability_engine.dart';
import '../../domain/entities/core.dart';
import '../../domain/entities/visit.dart';
import '../../domain/enums.dart';
import '../local/household_dao.dart';
import '../local/visit_dao.dart';

/// One household, scored, with everything the dashboard card needs already
/// resolved. Assembling this eagerly is what keeps the list scrolling smoothly
/// instead of firing queries as the CHO's thumb moves.
class HouseholdPriority {
  const HouseholdPriority({
    required this.household,
    required this.score,
    required this.members,
    this.mother,
    this.daysSinceLastVisit,
    this.openReferral,
    this.nextContactDue,
  });

  final Household household;
  final VulnerabilityScore score;
  final List<Person> members;
  final Person? mother;
  final int? daysSinceLastVisit;
  final Referral? openReferral;
  final ScheduledContact? nextContactDue;

  VulnerabilityBand get band => score.band;

  /// The one-line reason this household is where it is in the queue. A CHO who
  /// cannot see why will not trust the order, and will go back to visiting by
  /// proximity.
  String get reason => score.whyThisRanking;

  int get childCount => members
      .where(
        (m) =>
            m.effectiveClientType == ClientType.childUnderFive ||
            m.effectiveClientType == ClientType.newborn,
      )
      .length;
}

/// The day's plan: a ranked, explained list plus the counts a CHO needs before
/// they set off.
class DayPlan {
  const DayPlan({
    required this.priorities,
    required this.dueContacts,
    required this.overdueContacts,
    required this.chaseReferrals,
    required this.generatedAt,
  });

  final List<HouseholdPriority> priorities;
  final List<ScheduledContact> dueContacts;
  final List<ScheduledContact> overdueContacts;

  /// Urgent referrals with no confirmed arrival. These come before everything
  /// else, always: each one is a family who was told to go somewhere and, as far
  /// as anybody knows, did not.
  final List<Referral> chaseReferrals;

  final DateTime generatedAt;

  List<HouseholdPriority> get critical =>
      priorities.where((p) => p.band == VulnerabilityBand.critical).toList();

  List<HouseholdPriority> get high =>
      priorities.where((p) => p.band == VulnerabilityBand.high).toList();

  bool get isEmpty =>
      priorities.isEmpty && dueContacts.isEmpty && chaseReferrals.isEmpty;

  /// The headline. Written as a sentence rather than a number, because "12" on
  /// its own does not tell a CHO whether to hurry.
  String get headline {
    if (chaseReferrals.isNotEmpty) {
      return '${chaseReferrals.length} referral'
          '${chaseReferrals.length == 1 ? '' : 's'} not confirmed — trace first';
    }
    final c = critical.length;
    if (c > 0) {
      return '$c household${c == 1 ? '' : 's'} need${c == 1 ? 's' : ''} '
          'seeing today';
    }
    if (overdueContacts.isNotEmpty) {
      return '${overdueContacts.length} contact'
          '${overdueContacts.length == 1 ? '' : 's'} overdue';
    }
    if (dueContacts.isNotEmpty) {
      return '${dueContacts.length} scheduled contact'
          '${dueContacts.length == 1 ? '' : 's'} due';
    }
    return 'Nothing urgent. Use today for routine follow-up.';
  }
}

class InsightRepository {
  InsightRepository();

  /// Builds the ranked plan for a CHPS zone.
  ///
  /// Five batched reads, then all the scoring in memory. The alternative —
  /// querying per household — is roughly 1,200 SQLite round trips for a zone of
  /// 245 compounds, which on a shared Tecno phone is the difference between
  /// instant and unusable.
  Future<DayPlan> planDay({
    required String workerId,
    required String region,
    required String district,
    String? community,
    int? month,
  }) async {
    final households = await HouseholdDao.caseloadFor(
      workerId: workerId,
      region: region,
      district: district,
      community: community,
    );
    if (households.isEmpty) {
      return DayPlan(
        priorities: const [],
        dueContacts: const [],
        overdueContacts: const [],
        chaseReferrals: const [],
        generatedAt: DateTime.now(),
      );
    }

    final peopleByHousehold = await PersonDao.groupedByHousehold();
    final latestGrowth = await GrowthDao.latestForAll();
    final missedCounts = await ScheduleDao.missedCountsForAll();
    final openReferrals = await ReferralDao.open();
    final dueContacts = await ScheduleDao.due(horizonDays: 0);
    final overdue = await ScheduleDao.overdue();

    final referralsByPerson = <String, Referral>{};
    for (final r in openReferrals) {
      // Keep the most urgent open referral per person, since that is the one
      // that decides how hard to chase.
      final existing = referralsByPerson[r.personId];
      if (existing == null ||
          r.urgency.index < existing.urgency.index) {
        referralsByPerson[r.personId] = r;
      }
    }

    final contactsByHousehold = <String, ScheduledContact>{};
    for (final c in [...overdue, ...dueContacts]) {
      contactsByHousehold.putIfAbsent(c.householdId, () => c);
    }

    final priorities = <HouseholdPriority>[];
    final now = month ?? DateTime.now().month;

    for (final household in households) {
      final members = peopleByHousehold[household.id] ?? const <Person>[];

      final mother = members.firstWhereOrNull(
        (p) =>
            p.effectiveClientType == ClientType.pregnantWoman ||
            p.effectiveClientType == ClientType.postpartumWoman,
      );

      final children = members
          .where(
            (p) =>
                p.effectiveClientType == ClientType.newborn ||
                p.effectiveClientType == ClientType.childUnderFive,
          )
          .toList(growable: false);

      final maternal = mother == null
          ? null
          : await MaternalRecordDao.forPerson(mother.id);
      final births = await BirthRecordDao.forPeople(
        children.map((c) => c.id),
      );

      final openReferral = members
          .map((m) => referralsByPerson[m.id])
          .whereType<Referral>()
          .firstOrNull;

      final barriers = await BarrierDao.historyFor(household.id);
      final daysSince = await VisitDao.daysSinceLastVisit(household.id);

      var missed = 0;
      for (final m in members) {
        missed += missedCounts[m.id] ?? 0;
      }

      final score = VulnerabilityEngine.score(
        VulnerabilityInput(
          mother: mother,
          maternalRecord: maternal,
          children: children,
          birthRecords: births.values.toList(growable: false),
          latestGrowth: {
            for (final child in children)
              if (latestGrowth[child.id] != null)
                child.id: latestGrowth[child.id]!,
          },
          household: household,
          openUrgentReferralHours: openReferral?.hoursOpen,
          hasUnconfirmedReferral: openReferral != null,
          missedContactsCount: missed,
          reportedBarriers: barriers,
          daysSinceLastContact: daysSince,
          motherHaemoglobin: maternal?.haemoglobin,
          deliveryPlace: maternal?.deliveryPlace,
          month: now,
        ),
      );

      priorities.add(
        HouseholdPriority(
          household: household,
          score: score,
          members: members,
          mother: mother,
          daysSinceLastVisit: daysSince,
          openReferral: openReferral,
          nextContactDue: contactsByHousehold[household.id],
        ),
      );
    }

    priorities.sort((a, b) {
      final byScore = b.score.score.compareTo(a.score.score);
      if (byScore != 0) return byScore;
      // Tie-break on ignorance: the household we know least about is seen first.
      // A compound nobody has measured is not a safe compound.
      return a.score.dataCompleteness.compareTo(b.score.dataCompleteness);
    });

    return DayPlan(
      priorities: priorities,
      dueContacts: dueContacts,
      overdueContacts: overdue,
      chaseReferrals: openReferrals
          .where((r) => r.needsEscalation)
          .toList(growable: false),
      generatedAt: DateTime.now(),
    );
  }

  /// The vulnerability score for one household, with the same inputs the day
  /// plan uses — so the number on the household screen always matches the number
  /// that put it in the queue. A ranking that disagrees with the detail view is
  /// a ranking a CHO will stop believing.
  Future<VulnerabilityScore> scoreHousehold(String householdId) async {
    final household = await HouseholdDao.byId(householdId);
    final members = await PersonDao.inHousehold(householdId);

    final mother = members.firstWhereOrNull(
      (p) =>
          p.effectiveClientType == ClientType.pregnantWoman ||
          p.effectiveClientType == ClientType.postpartumWoman,
    );
    final children = members
        .where(
          (p) =>
              p.effectiveClientType == ClientType.newborn ||
              p.effectiveClientType == ClientType.childUnderFive,
        )
        .toList(growable: false);

    final maternal = mother == null
        ? null
        : await MaternalRecordDao.forPerson(mother.id);
    final births = await BirthRecordDao.forPeople(children.map((c) => c.id));

    final growth = <String, GrowthMeasurement>{};
    for (final child in children) {
      final latest = await GrowthDao.latest(child.id);
      if (latest != null) growth[child.id] = latest;
    }

    final referrals = <Referral>[];
    for (final m in members) {
      referrals.addAll(await ReferralDao.forPerson(m.id));
    }
    final open = referrals.where((r) => r.status.isOpen).toList();

    var missed = 0;
    for (final m in members) {
      missed += await ScheduleDao.missedCountFor(m.id);
    }

    return VulnerabilityEngine.score(
      VulnerabilityInput(
        mother: mother,
        maternalRecord: maternal,
        children: children,
        birthRecords: births.values.toList(growable: false),
        latestGrowth: growth,
        household: household,
        openUrgentReferralHours: open.isEmpty ? null : open.first.hoursOpen,
        hasUnconfirmedReferral: open.isNotEmpty,
        missedContactsCount: missed,
        reportedBarriers: await BarrierDao.historyFor(householdId),
        daysSinceLastContact: await VisitDao.daysSinceLastVisit(householdId),
        motherHaemoglobin: maternal?.haemoglobin,
        deliveryPlace: maternal?.deliveryPlace,
        month: DateTime.now().month,
      ),
    );
  }

  /// Growth trajectory for one child, from the stored series.
  ///
  /// This is the query that catches the child whose every individual reading is
  /// still "green" while the slope has been falling for three months.
  Future<TrajectoryResult> trajectory(String personId) async {
    final series = await GrowthDao.series(personId);
    return TrajectoryEngine.analyse(series);
  }

  /// Every child in the zone whose growth is heading the wrong way.
  ///
  /// Ordered by how little time is left before the SAM threshold, which is the
  /// only ordering that reflects urgency. A child 40 days out matters more today
  /// than one 200 days out with a steeper-looking curve.
  Future<List<({Person child, TrajectoryResult trajectory})>>
  decliningChildren() async {
    final children = await PersonDao.byClientType(ClientType.childUnderFive);
    final results = <({Person child, TrajectoryResult trajectory})>[];

    for (final child in children) {
      final series = await GrowthDao.series(child.id);
      if (series.length < 2) continue;
      final t = TrajectoryEngine.analyse(series);
      if (t.isDeteriorating) results.add((child: child, trajectory: t));
    }

    results.sort((a, b) {
      final aDays = a.trajectory.daysToSamThreshold ?? 9999;
      final bDays = b.trajectory.daysToSamThreshold ?? 9999;
      return aDays.compareTo(bDays);
    });
    return results;
  }

  /// Predicts what will stop this referral before it is issued.
  ///
  /// Called *while the family is still present*, which is the whole point. A
  /// transport problem discovered now can be solved; the same problem discovered
  /// two days later is a defaulter report.
  Future<BarrierForecast> forecastBarriers({
    required String householdId,
    String? personId,
    ReferralUrgency urgency = ReferralUrgency.sameDay,
    bool? decisionMakerPresent,
    bool? isNightTime,
  }) async {
    final household = await HouseholdDao.byId(householdId);
    final client = personId == null ? null : await PersonDao.byId(personId);
    final members = await PersonDao.inHousehold(householdId);
    final barriers = await BarrierDao.historyFor(householdId);

    var missed = 0;
    for (final m in members) {
      missed += await ScheduleDao.missedCountFor(m.id);
    }

    final underFives = members
        .where(
          (m) =>
              m.effectiveClientType == ClientType.childUnderFive ||
              m.effectiveClientType == ClientType.newborn,
        )
        .length;

    return BarrierEngine.forecast(
      household: household,
      client: client,
      previouslyReported: barriers,
      missedContactsCount: missed,
      urgency: urgency,
      month: DateTime.now().month,
      isNightTime: isNightTime ?? _isNight(),
      childrenUnderFiveInHousehold: underFives,
      decisionMakerPresent: decisionMakerPresent,
    );
  }

  /// Barrier patterns across the zone. Turns individual excuses into evidence:
  /// nine families reporting a closed facility in one month is a staffing
  /// problem with numbers attached, not nine family problems.
  Future<List<BarrierPattern>> zonePatterns({int withinDays = 90}) async {
    final reports = await BarrierDao.withinDays(withinDays);
    return BarrierEngine.detectPatterns(reports);
  }

  /// Referral completion over a window — the single number that says whether the
  /// last mile is being closed, rather than whether notes are being written.
  Future<({int issued, int arrived, double rate})> referralCompletion({
    int withinDays = 90,
  }) async {
    final stats = await ReferralDao.completionStats(withinDays: withinDays);
    final rate = stats.issued == 0 ? 0.0 : stats.arrived / stats.issued;
    return (issued: stats.issued, arrived: stats.arrived, rate: rate);
  }

  static bool _isNight() {
    final hour = DateTime.now().hour;
    return hour >= 19 || hour < 6;
  }
}
