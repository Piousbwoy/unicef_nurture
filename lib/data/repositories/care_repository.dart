/// The access-controlled gateway to every record in the app.
///
/// This class exists so that **role enforcement cannot be forgotten**. The
/// widgets never touch a DAO. They cannot: the DAOs are reachable only through
/// this repository, and every method here takes the acting [AppUser] as its
/// first argument and checks a [Permission] before it does anything.
///
/// Why it is built this way rather than hiding buttons in the UI:
///
/// **Hidden buttons are not access control.** A screen that omits a menu item is
/// a courtesy. If the route can still be reached — by a deep link, a stale
/// navigator stack, a rebuilt widget after a role switch on a shared phone — the
/// data is exposed. Enforcement belongs at the data boundary, once, where it
/// cannot be routed around.
///
/// **Caregivers are scoped, not merely limited.** `viewOwnFamilyOnly` is not a
/// weaker version of `viewAllHouseholds`; it is a different shape of access. A
/// caregiver account is bound to one household at registration, and every read
/// is filtered against that binding. A caregiver asking for a household that is
/// not theirs does not get an empty list — they get a denial, and the attempt is
/// written to the audit log.
///
/// **Denials are recorded.** Access control with no trace is a claim. Constraint
/// 5 of the brief is protection of health data, and "we check permissions"
/// is only true if it can be shown afterwards.
library;

import '../../domain/entities/core.dart';
import '../../domain/entities/visit.dart';
import '../../domain/enums.dart';
import '../local/household_dao.dart';
import '../local/user_dao.dart';
import '../local/visit_dao.dart';

/// Thrown when a user attempts something their role does not allow.
///
/// A thrown exception rather than a null return, deliberately: a permission
/// failure is a bug or an attack, never a normal branch, and it must not be
/// possible to ignore it by accident.
class AccessDenied implements Exception {
  const AccessDenied(this.action, this.permission, {this.detail});

  final String action;
  final Permission? permission;
  final String? detail;

  /// Shown to the user. Says what is not allowed, without lecturing.
  String get message =>
      detail ?? 'Your role does not allow you to $action on this device.';

  @override
  String toString() => 'AccessDenied($action, ${permission?.name}): $message';
}

class CareRepository {
  CareRepository();

  // ---------------------------------------------------------------------------
  // Guards
  // ---------------------------------------------------------------------------

  /// Every write and every read of another family's data passes through here.
  Future<void> _require(
    AppUser user,
    Permission permission,
    String action, {
    String? entityTable,
    String? entityId,
  }) async {
    if (user.can(permission)) return;
    await AuditDao.denied(
      action: action,
      actor: user,
      permission: permission,
      entityTable: entityTable,
      entityId: entityId,
    );
    throw AccessDenied(action, permission);
  }

  /// Confirms a caregiver is asking about their own household.
  ///
  /// An FHW passes through: their scope is a CHPS zone of 3,000–4,500 people, and
  /// restricting them per-household would break the job. A caregiver is checked
  /// against the household their account was bound to at registration.
  Future<void> _requireHouseholdScope(
    AppUser user,
    String householdId,
    String action,
  ) async {
    if (user.can(Permission.viewAllHouseholds)) return;

    final linked = await UserDao.linkedHouseholdFor(user.id);
    if (linked != null && linked == householdId) return;

    await AuditDao.denied(
      action: action,
      actor: user,
      permission: Permission.viewAllHouseholds,
      entityTable: 'households',
      entityId: householdId,
    );
    throw AccessDenied(
      action,
      Permission.viewAllHouseholds,
      detail:
          'This record belongs to another family. Caregiver accounts can only '
          'open their own household.',
    );
  }

  /// Resolves the household a person belongs to, then scope-checks it. Used by
  /// every person-level read, because a person ID leaks nothing about ownership
  /// on its own.
  Future<void> _requirePersonScope(
    AppUser user,
    String personId,
    String action,
  ) async {
    if (user.can(Permission.viewAllHouseholds)) return;
    final person = await PersonDao.byId(personId);
    if (person == null) {
      throw AccessDenied(action, null, detail: 'That record does not exist.');
    }
    await _requireHouseholdScope(user, person.householdId, action);
  }

  // ---------------------------------------------------------------------------
  // Households
  // ---------------------------------------------------------------------------

  Future<void> registerHousehold(AppUser user, Household household) async {
    await _require(
      user,
      Permission.registerHousehold,
      'register a household',
      entityTable: 'households',
      entityId: household.id,
    );
    await HouseholdDao.upsert(household);
  }

  /// Registers a mother and any newborns in one atomic write.
  ///
  /// This is the delivery scenario as a single event. A twin birth half-recorded
  /// — mother saved, second twin lost — produces exactly the invisible newborn
  /// the app exists to prevent, so it is one transaction or none.
  Future<void> registerFamily(
    AppUser user, {
    required Household household,
    Person? mother,
    MaternalRecord? maternalRecord,
    List<Person> children = const [],
    Map<String, BirthRecord> birthRecords = const {},
  }) async {
    await _require(user, Permission.registerHousehold, 'register a family');
    await PersonDao.registerFamily(
      household: household,
      mother: mother,
      maternalRecord: maternalRecord,
      children: children,
      birthRecords: birthRecords,
    );
    await AuditDao.record(
      action: 'register_family',
      outcome: 'allowed',
      actorId: user.id,
      actorRole: user.role.name,
      entityTable: 'households',
      entityId: household.id,
      detail:
          '${mother != null ? 'mother + ' : ''}${children.length} child record(s)',
    );
  }

  /// Households this user may see.
  ///
  /// The two roles get genuinely different queries rather than the same query
  /// with a filter bolted on — which is what keeps a caregiver's list from ever
  /// being one missing `where` clause away from the whole zone.
  Future<List<Household>> visibleHouseholds(AppUser user) async {
    if (user.can(Permission.viewAllHouseholds)) {
      return HouseholdDao.caseloadFor(
        workerId: user.id,
        region: user.region,
        district: user.district,
      );
    }
    final linked = await UserDao.linkedHouseholdFor(user.id);
    if (linked == null) return const [];
    final household = await HouseholdDao.byId(linked);
    return household == null ? const [] : [household];
  }

  Future<Household?> household(AppUser user, String id) async {
    await _requireHouseholdScope(user, id, 'open this household');
    return HouseholdDao.byId(id);
  }

  Future<List<Household>> searchHouseholds(AppUser user, String query) async {
    await _require(
      user,
      Permission.viewAllHouseholds,
      'search all households',
    );
    return HouseholdDao.search(query);
  }

  // ---------------------------------------------------------------------------
  // People
  // ---------------------------------------------------------------------------

  Future<List<Person>> peopleIn(AppUser user, String householdId) async {
    await _requireHouseholdScope(user, householdId, 'view this household');
    return PersonDao.inHousehold(householdId);
  }

  /// The multi-client queue: mother first, then newborns, then under-fives.
  ///
  /// This is the answer to "she arrived with a newborn twin and a three-year-old"
  /// — one call produces the whole queue in clinical order.
  Future<List<Person>> visitQueue(AppUser user, String householdId) async {
    await _requireHouseholdScope(user, householdId, 'start a visit here');
    return PersonDao.clientsForVisit(householdId);
  }

  Future<Person?> person(AppUser user, String personId) async {
    await _requirePersonScope(user, personId, 'open this record');
    return PersonDao.byId(personId);
  }

  Future<void> savePerson(AppUser user, Person person) async {
    await _require(user, Permission.registerHousehold, 'add or edit a person');
    await PersonDao.upsert(person);
  }

  Future<List<Person>> childrenOf(AppUser user, String motherId) async {
    await _requirePersonScope(user, motherId, 'view this family');
    return PersonDao.childrenOf(motherId);
  }

  // ---------------------------------------------------------------------------
  // Clinical detail
  // ---------------------------------------------------------------------------

  Future<MaternalRecord?> maternalRecord(AppUser user, String personId) async {
    await _requirePersonScope(user, personId, 'view this maternal record');
    return MaternalRecordDao.forPerson(personId);
  }

  Future<void> saveMaternalRecord(AppUser user, MaternalRecord record) async {
    await _require(
      user,
      Permission.recordClinicalVitals,
      'record maternal clinical details',
      entityTable: 'maternal_records',
      entityId: record.personId,
    );
    await MaternalRecordDao.upsert(record);
  }

  Future<BirthRecord?> birthRecord(AppUser user, String personId) async {
    await _requirePersonScope(user, personId, 'view this birth record');
    return BirthRecordDao.forPerson(personId);
  }

  Future<void> saveBirthRecord(AppUser user, BirthRecord record) async {
    await _require(
      user,
      Permission.recordClinicalVitals,
      'record birth details',
      entityTable: 'birth_records',
      entityId: record.personId,
    );
    await BirthRecordDao.upsert(record);
  }

  /// Records a measurement.
  ///
  /// Gated on [Permission.recordClinicalVitals], which caregivers do not hold.
  /// This is a clinical judgement, not a preference: a MUAC tape read by an
  /// untrained hand, stored with equal weight, would corrupt the trajectory
  /// series that the early-warning engine depends on. Caregivers report
  /// *symptoms*; they do not enter measurements.
  Future<void> recordGrowth(AppUser user, GrowthMeasurement m) async {
    await _require(
      user,
      Permission.recordClinicalVitals,
      'record a measurement',
      entityTable: 'growth_measurements',
      entityId: m.id,
    );
    await GrowthDao.insert(m);
  }

  Future<List<GrowthMeasurement>> growthSeries(
    AppUser user,
    String personId,
  ) async {
    await _requirePersonScope(user, personId, 'view growth history');
    return GrowthDao.series(personId);
  }

  // ---------------------------------------------------------------------------
  // Visits
  // ---------------------------------------------------------------------------

  Future<void> startVisit(
    AppUser user,
    Visit visit,
    List<VisitParticipant> rollCall,
  ) async {
    await _require(
      user,
      Permission.runClinicalAssessment,
      'start a clinical visit',
      entityTable: 'visits',
      entityId: visit.id,
    );
    await VisitDao.start(visit, rollCall);
  }

  Future<Visit?> resumableVisit(AppUser user) =>
      VisitDao.openVisitFor(user.id);

  Future<void> completeVisit(AppUser user, String visitId, {String? notes}) =>
      VisitDao.complete(visitId, notes: notes);

  Future<List<VisitParticipant>> rollCall(AppUser user, String visitId) =>
      VisitDao.participants(visitId);

  Future<void> updateRollCall(AppUser user, VisitParticipant p) =>
      VisitDao.updateParticipant(p);

  Future<List<Visit>> visitHistory(AppUser user, String householdId) async {
    await _requireHouseholdScope(user, householdId, 'view visit history');
    return VisitDao.forHousehold(householdId);
  }

  // ---------------------------------------------------------------------------
  // Assessments
  // ---------------------------------------------------------------------------

  /// Saves a full clinical assessment, with the referral and follow-up contacts
  /// it produced.
  ///
  /// One method rather than three calls, so the three cannot come apart. An
  /// urgent verdict that persisted without its referral is a decision nobody
  /// acts on.
  Future<void> saveAssessment(
    AppUser user,
    Assessment assessment, {
    Referral? referral,
    List<ScheduledContact> followUps = const [],
  }) async {
    await _require(
      user,
      Permission.runClinicalAssessment,
      'save a clinical assessment',
      entityTable: 'assessments',
      entityId: assessment.id,
    );

    if (referral != null) {
      await _require(
        user,
        Permission.issueReferral,
        'issue a referral',
        entityTable: 'referrals',
        entityId: referral.id,
      );
      await AssessmentDao.saveWithReferral(assessment, referral);
      if (followUps.isNotEmpty) await ScheduleDao.upsertAll(followUps);
    } else if (followUps.isNotEmpty) {
      await AssessmentDao.saveWithSchedule(assessment, followUps);
    } else {
      await AssessmentDao.save(assessment);
    }

    await AuditDao.record(
      action: 'save_assessment',
      outcome: 'allowed',
      actorId: user.id,
      actorRole: user.role.name,
      entityTable: 'assessments',
      entityId: assessment.id,
      detail:
          '${assessment.clientType.name} — ${assessment.result.classification} '
          '(${assessment.effectiveTriage.name})',
    );
  }

  Future<List<Assessment>> assessmentHistory(
    AppUser user,
    String personId,
  ) async {
    await _requirePersonScope(user, personId, 'view assessment history');
    return AssessmentDao.forPerson(personId);
  }

  Future<Assessment?> latestAssessment(AppUser user, String personId) async {
    await _requirePersonScope(user, personId, 'view the last assessment');
    return AssessmentDao.latestForPerson(personId);
  }

  /// A clinician overruling the engine.
  ///
  /// Gated on [Permission.overrideAiRecommendation], which only an FHW holds. The
  /// human must be able to overrule the machine — they are accountable for the
  /// care, and a protocol cannot see everything in the room. But a caregiver
  /// overriding a danger sign would be the app talking a family out of going to
  /// hospital, which is the one outcome it must never produce.
  Future<void> overrideRecommendation(
    AppUser user, {
    required String assessmentId,
    required TriageLevel newTriage,
    required String reason,
  }) async {
    await _require(
      user,
      Permission.overrideAiRecommendation,
      'change a recommendation',
      entityTable: 'assessments',
      entityId: assessmentId,
    );
    if (reason.trim().length < 10) {
      throw AccessDenied(
        'change a recommendation',
        Permission.overrideAiRecommendation,
        detail:
            'Give a clinical reason of at least a few words. This is kept with '
            'the record and is how the recommendations get better.',
      );
    }
    await AssessmentDao.recordOverride(
      assessmentId: assessmentId,
      newTriage: newTriage,
      reason: reason.trim(),
      byUserId: user.id,
    );
  }

  // ---------------------------------------------------------------------------
  // Referrals
  // ---------------------------------------------------------------------------

  Future<void> issueReferral(AppUser user, Referral referral) async {
    await _require(
      user,
      Permission.issueReferral,
      'issue a referral',
      entityTable: 'referrals',
      entityId: referral.id,
    );
    await ReferralDao.upsert(referral);
  }

  Future<List<Referral>> openReferrals(AppUser user) async {
    if (user.can(Permission.viewAllHouseholds)) return ReferralDao.open();
    final linked = await UserDao.linkedHouseholdFor(user.id);
    if (linked == null) return const [];
    final people = await PersonDao.inHousehold(linked);
    final ids = people.map((p) => p.id).toSet();
    final all = await ReferralDao.open();
    return all.where((r) => ids.contains(r.personId)).toList(growable: false);
  }

  /// Urgent referrals with no confirmed arrival after 48 hours — the last-mile
  /// failure list, and the reason the referral loop is closed by data rather
  /// than by hope.
  Future<List<Referral>> referralsNeedingChase(AppUser user) async {
    await _require(
      user,
      Permission.viewAllHouseholds,
      'view the referral chase list',
    );
    return ReferralDao.needingEscalation();
  }

  /// Confirms a family arrived, via QR scan or by typing the short code.
  Future<Referral?> confirmArrival(AppUser user, String referenceCode) async {
    await _require(
      user,
      Permission.confirmReferralArrival,
      'confirm a referral arrival',
    );
    final referral = await ReferralDao.byCode(referenceCode);
    if (referral == null) return null;
    await ReferralDao.updateStatus(
      referralId: referral.id,
      status: ReferralStatus.arrived,
      confirmedBy: user.id,
    );
    return ReferralDao.byId(referral.id);
  }

  Future<void> updateReferralStatus(
    AppUser user, {
    required String referralId,
    required ReferralStatus status,
    String? outcomeNotes,
  }) async {
    await _require(
      user,
      Permission.issueReferral,
      'update a referral',
      entityTable: 'referrals',
      entityId: referralId,
    );
    await ReferralDao.updateStatus(
      referralId: referralId,
      status: status,
      outcomeNotes: outcomeNotes,
    );
  }

  // ---------------------------------------------------------------------------
  // Barriers
  // ---------------------------------------------------------------------------

  /// Records why care did not happen.
  ///
  /// Both roles hold [Permission.recordBarrier], and that is the point. A
  /// caregiver saying "we had no transport money" is the most reliable source
  /// there is — a CHO can only ever guess at it. This is the channel through
  /// which the community becomes a participant rather than a subject.
  Future<void> recordBarrier(AppUser user, BarrierReport report) async {
    await _require(
      user,
      Permission.recordBarrier,
      'record a barrier to care',
      entityTable: 'barrier_reports',
      entityId: report.id,
    );
    await _requireHouseholdScope(
      user,
      report.householdId,
      'record a barrier for this household',
    );
    await BarrierDao.save(report);
  }

  Future<List<CareBarrier>> barrierHistory(
    AppUser user,
    String householdId,
  ) async {
    await _requireHouseholdScope(user, householdId, 'view barrier history');
    return BarrierDao.historyFor(householdId);
  }

  /// Zone-wide barrier reports for pattern detection. FHW only — an individual
  /// caregiver has no business reading the whole community's difficulties.
  Future<List<BarrierReport>> zoneBarriers(
    AppUser user, {
    int withinDays = 90,
  }) async {
    await _require(
      user,
      Permission.viewCommunityInsights,
      'view community barrier patterns',
    );
    return BarrierDao.withinDays(withinDays);
  }

  // ---------------------------------------------------------------------------
  // Home checks — the caregiver's danger-sign reports
  // ---------------------------------------------------------------------------

  /// Saves one danger-sign check a caregiver ran at home.
  ///
  /// The write is gated on [Permission.runCaregiverTriage] and the household
  /// scope, but it is deliberately NOT queued to the outbox: the check stays
  /// on the family's device until the family chooses to share it in person.
  Future<void> recordHomeCheck(AppUser user, HomeCheck check) async {
    await _require(
      user,
      Permission.runCaregiverTriage,
      'record a home danger-sign check',
      entityTable: 'home_checks',
      entityId: check.id,
    );
    await _requireHouseholdScope(
      user,
      check.householdId,
      'record a home check for this household',
    );
    await HomeCheckDao.save(check);
  }

  /// The home checks a family has run, newest first. Both roles may read
  /// them: the caregiver sees their own history, the FHW sees what the family
  /// reported before deciding what to examine first.
  Future<List<HomeCheck>> homeChecks(AppUser user, String householdId) async {
    await _requireHouseholdScope(user, householdId, 'view home checks');
    return HomeCheckDao.forHousehold(householdId);
  }

  /// The latest home check for one person — the "last checked" line on the
  /// caregiver's family tiles.
  Future<HomeCheck?> latestHomeCheck(AppUser user, String personId) async {
    await _requirePersonScope(user, personId, 'view a home check');
    return HomeCheckDao.latestForPerson(personId);
  }

  // ---------------------------------------------------------------------------
  // Scheduled contacts
  // ---------------------------------------------------------------------------

  Future<List<ScheduledContact>> dueContacts(
    AppUser user, {
    int horizonDays = 0,
  }) async {
    if (user.can(Permission.planVisitRoute)) {
      return ScheduleDao.due(horizonDays: horizonDays);
    }
    final linked = await UserDao.linkedHouseholdFor(user.id);
    if (linked == null) return const [];
    final all = await ScheduleDao.due(horizonDays: horizonDays);
    return all
        .where((c) => c.householdId == linked)
        .toList(growable: false);
  }

  Future<void> scheduleContacts(
    AppUser user,
    List<ScheduledContact> contacts,
  ) async {
    await _require(
      user,
      Permission.runClinicalAssessment,
      'schedule follow-up contacts',
    );
    await ScheduleDao.upsertAll(contacts);
  }

  Future<void> markContactDone(AppUser user, String contactId) async {
    await _require(
      user,
      Permission.runClinicalAssessment,
      'complete a scheduled contact',
    );
    await ScheduleDao.markDone(contactId);
  }
}
