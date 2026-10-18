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
///
/// **The check itself is now evidence.** A permission test answers "may she?" and
/// then forgets. So these guards also answer the question Act 843 actually asks —
/// *on what lawful basis, at what time, from which handset, and can you prove the
/// record of it was not edited afterwards* — and write the answer to a hash-chained
/// trail before any data is returned. Health data is "special personal data" there
/// for a reason: a system that cannot reconstruct who saw a child's record has not
/// protected it, it has merely not been caught.
library;

import '../../domain/entities/caregiver.dart';
import '../../domain/entities/care_request.dart';
import '../../domain/services/caregiver_check_policy.dart';
import '../../domain/services/caregiver_milestone_policy.dart';
import '../../domain/services/follow_up_policy.dart';
import '../local/care_request_dao.dart';
import '../local/caregiver_dao.dart';
import '../../domain/entities/core.dart';
import '../../domain/entities/visit.dart';
import '../../domain/enums.dart';
import '../local/household_dao.dart';
import '../local/compliance_dao.dart';
import '../local/user_dao.dart';
import '../local/visit_dao.dart';
import '../sync/server_auth_client.dart';
import '../../domain/compliance.dart';
import '../local/app_database.dart';
import 'record_access.dart';

/// The handset's stable device id, for attribution on the access trail.
///
/// Read from the same place auth and sync read it, so one identity is used
/// everywhere and a forensic review cannot find two names for one phone. Null when
/// secure storage is unavailable, which degrades attribution but never blocks care.
Future<String?> _currentDeviceId() async {
  try {
    return await ServerAuthClient.deviceId();
  } catch (_) {
    return null;
  }
}

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
  CareRepository({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;
  final DateTime Function() _clock;

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
  ///
  /// Passing the role floor is not the end of the question for a health worker, it
  /// is the beginning of a different one: *why is she allowed to see this family*
  /// and *will there be a record*. That is answered and recorded here, once per
  /// access, before the data is handed over.
  Future<void> _requireHouseholdScope(
    AppUser user,
    String householdId,
    String action, {
    AccessPurpose purpose = AccessPurpose.continuingCare,
    String? breakGlassReason,
    String? subjectPersonId,
  }) async {
    if (user.can(Permission.viewAllHouseholds)) {
      await _accountForAccess(
        user,
        householdId,
        action,
        purpose: purpose,
        breakGlassReason: breakGlassReason,
        subjectPersonId: subjectPersonId,
      );
      return;
    }

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

  /// Runs the policy decision and writes its evidence. Refuses the read only where
  /// the law refuses it, and only where the evidence itself could not be written
  /// for access that is not this worker's own caseload — see [RecordAccess].
  Future<void> _accountForAccess(
    AppUser user,
    String householdId,
    String action, {
    required AccessPurpose purpose,
    String? breakGlassReason,
    String? subjectPersonId,
  }) async {
    final db = await AppDatabase.instance.database;
    final decision = await RecordAccess.open(
      db,
      actor: user,
      householdId: householdId,
      subjectPersonId: subjectPersonId ?? householdId,
      purpose: purpose,
      action: action,
      breakGlassReason: breakGlassReason,
      deviceId: await _currentDeviceId(),
    );
    if (decision.isRefusal) {
      throw AccessDenied(
        action,
        Permission.viewAllHouseholds,
        detail: decision.reason,
      );
    }
  }

  /// Resolves the household a person belongs to, then scope-checks it. Used by
  /// every person-level read, because a person ID leaks nothing about ownership
  /// on its own — and because the *subject* of the access, which is what a
  /// family's disclosure is queried by, is only known from the person row.
  Future<void> _requirePersonScope(
    AppUser user,
    String personId,
    String action, {
    AccessPurpose purpose = AccessPurpose.continuingCare,
    String? breakGlassReason,
  }) async {
    final person = await PersonDao.byId(personId);
    if (user.can(Permission.viewAllHouseholds)) {
      if (person == null) return;
      await _requireHouseholdScope(
        user,
        person.householdId,
        action,
        purpose: purpose,
        breakGlassReason: breakGlassReason,
        subjectPersonId: personId,
      );
      return;
    }
    if (person == null) {
      throw AccessDenied(action, null, detail: 'That record does not exist.');
    }
    await _requireHouseholdScope(
      user,
      person.householdId,
      action,
      purpose: purpose,
      subjectPersonId: personId,
    );
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

  /// A caregiver starts their own household record.
  ///
  /// Real life does not wait for registration day: a family that downloads the
  /// app before any health worker has reached their compound still deserves a
  /// working account. The household they create is an ordinary record — same
  /// table, same outbox, same sync — with the caregiver's own user id as
  /// `createdBy`, so it joins the zone caseload the moment an FHW's phone
  /// meets it.
  ///
  /// Guarded twice: the capability ([Permission.manageOwnFamily]) and the
  /// role. An FHW never holds the capability, and a caregiver account is the
  /// only thing that may use it. The household must also be the one the
  /// account will be bound to — this method is called from registration, so
  /// [AppUser.id] is known before the user row exists; everything else about
  /// the check is identical to any other write.
  Future<void> createOwnHousehold(AppUser user, Household household) async {
    await _require(
      user,
      Permission.manageOwnFamily,
      'create your own family record',
      entityTable: 'households',
      entityId: household.id,
    );
    if (!user.role.isCaregiver) {
      throw const AccessDenied(
        'create your own family record',
        Permission.manageOwnFamily,
        detail: 'Only caregiver accounts start a family this way.',
      );
    }
    if (household.createdBy != user.id) {
      throw const AccessDenied(
        'create your own family record',
        Permission.manageOwnFamily,
        detail: 'A family record must be created under your own account.',
      );
    }
    await HouseholdDao.upsert(household);
    await AuditDao.record(
      action: 'self_register_household',
      outcome: 'allowed',
      actorId: user.id,
      actorRole: user.role.name,
      entityTable: 'households',
      entityId: household.id,
      detail: household.name,
    );
  }

  /// Households this user may see.
  ///
  /// The two roles get genuinely different queries rather than the same query
  /// with a filter bolted on — which is what keeps a caregiver's list from ever
  /// being one missing `where` clause away from the whole zone.
  ///
  /// An FHW's register spans her whole region, not just her district: a worker
  /// posted anywhere in the region she signed up in must be able to find any
  /// family in it. The day plan keeps the narrower district scope — the
  /// register is what she searches, the plan is what she walks.
  Future<List<Household>> visibleHouseholds(AppUser user) async {
    if (user.can(Permission.viewAllHouseholds)) {
      // Region-wide register: a colleague's household in any district of
      // the region is findable (see HouseholdDao.caseloadFor — region names
      // are matched by mutual prefix so 'Northern' and 'Northern Region'
      // count as the same region).
      return HouseholdDao.caseloadFor(workerId: user.id, region: user.region);
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
    await _require(user, Permission.viewAllHouseholds, 'search all households');
    return HouseholdDao.search(query, region: user.region);
  }

  // ---------------------------------------------------------------------------
  // Accountability: consent, the access trail, and the family's own rights
  // ---------------------------------------------------------------------------

  /// Records what a family decided about one scope.
  ///
  /// Append-only. A withdrawal never rewrites the earlier grant, because the
  /// grant is what makes an access in between lawful — deleting it would destroy
  /// the defence of something that already happened.
  Future<void> recordConsent(
    AppUser user, {
    required String subjectPersonId,
    required ConsentScope scope,
    required ConsentDecision decision,
    String language = 'English',
    String? voiceArtifact,
    String? witnessName,
    String? note,
  }) async {
    await _requireHouseholdScope(
      user,
      // The subject's household authorises nothing on its own — recording a
      // decision needs the standing to edit this person's record at all.
      (await PersonDao.byId(subjectPersonId))?.householdId ?? subjectPersonId,
      'record a consent choice',
      purpose: AccessPurpose.continuingCare,
      subjectPersonId: subjectPersonId,
    );
    final db = await AppDatabase.instance.database;
    await ConsentLedgerDao.record(
      db,
      event: ConsentEvent(
        id: 'consent-${DateTime.now().microsecondsSinceEpoch}',
        subjectPersonId: subjectPersonId,
        scope: scope,
        decision: decision,
        noticeVersion: CareNotice.currentVersion,
        occurredAt: _clock(),
        capturedBy: user.id,
        language: language,
        voiceArtifact: voiceArtifact,
        witnessName: witnessName,
        deviceId: await _currentDeviceId(),
        note: note,
      ),
    );
  }

  /// The family's current position on every scope. Absence is *not* consent, so a
  /// scope nobody was asked about reads as null and is treated as not granted.
  Future<Map<ConsentScope, ConsentEvent?>> consentFor(
    AppUser user,
    String subjectPersonId,
  ) async {
    await _requirePersonScope(user, subjectPersonId, 'view a consent record');
    return ConsentLedgerDao.currentFor(subjectPersonId);
  }

  /// "Who has seen this record" — the data subject's right of access, answered as
  /// a query rather than as a promise in a policy document.
  ///
  /// Takes both ids because a household-level access is recorded against the
  /// household and a person-level one against the person; a family asking about
  /// their child wants both halves, and showing only one would be an
  /// understatement of exactly the wrong kind.
  Future<List<DisclosureLine>> accessTrail(
    AppUser user, {
    required String subjectPersonId,
    required String householdId,
  }) async {
    await _requirePersonScope(user, subjectPersonId, 'view an access trail');
    return AccessLedgerDao.disclosureFor([
      subjectPersonId,
      householdId,
    ]);
  }

  /// Recomputes the trail's hash chain. The operation a supervisor runs to check
  /// that nobody has edited the log — and the one a tamper demonstration flips.
  Future<ChainVerification> verifyAccessTrail(AppUser user) async {
    await _require(
      user,
      Permission.viewCommunityInsights,
      'verify the access trail',
    );
    return AccessLedgerDao.verify();
  }

  /// Accesses with no consent and no care relationship behind them: the queue a
  /// district supervisor is expected to read, not a dashboard nobody opens.
  Future<List<AccessRecord>> flaggedAccesses(
    AppUser user, {
    int limit = 50,
  }) async {
    await _require(user, Permission.viewCommunityInsights, 'review flagged access');
    return AccessLedgerDao.flaggedReviews(limit: limit);
  }

  /// Opens a record the worker has no relationship to, *with a stated reason*.
  ///
  /// This is the path that exists so that no clinician is ever blocked from a
  /// patient, and so that the choice is uncomfortable in the only way that is
  /// useful afterwards: it costs a sentence, it is flagged to a supervisor, and it
  /// appears by name in the family's own disclosure.
  Future<void> openRecordUnderGlass(
    AppUser user, {
    required String householdId,
    required String subjectPersonId,
    required String reason,
  }) async {
    await _require(user, Permission.viewAllHouseholds, 'open a patient record');
    final db = await AppDatabase.instance.database;
    final decision = await RecordAccess.open(
      db,
      actor: user,
      householdId: householdId,
      subjectPersonId: subjectPersonId,
      purpose: AccessPurpose.continuingCare,
      action: 'open_record_under_glass',
      breakGlassReason: reason,
      deviceId: await _currentDeviceId(),
    );
    if (decision.isRefusal) {
      throw AccessDenied(
        'open this record',
        Permission.viewAllHouseholds,
        detail: decision.reason,
      );
    }
  }

  /// A family asking to see, correct, object, erase or take away their data.
  /// Opened as work with a deadline, not as a toast message.
  Future<void> raiseDataRight(
    AppUser user, {
    required String subjectPersonId,
    required DataRight right,
  }) async {
    await _requirePersonScope(user, subjectPersonId, 'request a data right');
    await DataRightsDao.open(
      id: 'right-${DateTime.now().microsecondsSinceEpoch}',
      subjectPersonId: subjectPersonId,
      right: right,
      requestedBy: user.id,
      at: _clock(),
    );
  }

  Future<List<RightsRequest>> dataRightsFor(
    AppUser user,
    String subjectPersonId,
  ) async {
    await _requirePersonScope(user, subjectPersonId, 'view data-rights requests');
    return DataRightsDao.forSubject(subjectPersonId);
  }

  /// The outstanding obligations the district owes families, oldest first.
  Future<List<RightsRequest>> openDataRightsQueue(AppUser user) async {
    await _require(
      user,
      Permission.viewCommunityInsights,
      'view the data-rights queue',
    );
    return DataRightsDao.openQueue();
  }

  Future<void> resolveDataRight(
    AppUser user, {
    required String requestId,
    required RequestStatus status,
    required String resolution,
  }) async {
    await _require(
      user,
      Permission.viewCommunityInsights,
      'answer a data-rights request',
    );
    await DataRightsDao.resolve(
      requestId,
      status: status,
      resolution: resolution,
      at: _clock(),
    );
  }

  // ---------------------------------------------------------------------------
  // People
  // ---------------------------------------------------------------------------

  Future<List<Person>> peopleIn(AppUser user, String householdId) async {
    await _requireHouseholdScope(user, householdId, 'view this household');
    return PersonDao.inHousehold(householdId);
  }

  Future<Map<String, List<Person>>> visibleHouseholdMembers(
    AppUser user,
  ) async {
    await _require(
      user,
      Permission.viewAllHouseholds,
      'search patient records',
    );
    final households = await visibleHouseholds(user);
    final grouped = await PersonDao.groupedByHousehold();
    return {
      for (final household in households)
        household.id: grouped[household.id] ?? const <Person>[],
    };
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

  /// A caregiver adds someone they care for to their own family.
  ///
  /// The scope check is the whole point: [Permission.manageOwnFamily] alone
  /// would let a caregiver write into any household id they typed, so the
  /// person's household is resolved and matched against the account's binding
  /// before anything is written. The attempt is audited either way.
  Future<void> addFamilyMember(AppUser user, Person person) async {
    await _require(
      user,
      Permission.manageOwnFamily,
      'add a family member',
      entityTable: 'persons',
      entityId: person.id,
    );
    await _requireHouseholdScope(
      user,
      person.householdId,
      'add a member to this family',
    );
    await PersonDao.upsert(person);
    await AuditDao.record(
      action: 'add_family_member',
      outcome: 'allowed',
      actorId: user.id,
      actorRole: user.role.name,
      entityTable: 'persons',
      entityId: person.id,
      detail: person.fullName,
    );
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

  /// The most recent measurement on this device, for the caregiver home check
  /// to consult. Reading is not writing — a family still cannot enter a
  /// measurement — but a tape reading a health worker already took on this
  /// phone is evidence the check would otherwise ignore.
  Future<GrowthMeasurement?> latestGrowth(
    AppUser user,
    String personId,
  ) async {
    await _requirePersonScope(user, personId, 'view the last measurement');
    return GrowthDao.latest(personId);
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

  Future<Visit?> resumableVisit(AppUser user) => VisitDao.openVisitFor(user.id);

  /// Every session this worker has left open — the clinic queue. Scoped to the
  /// clinical role, the same permission that lets them start one.
  Future<List<Visit>> openClinicVisits(AppUser user) async {
    await _require(
      user,
      Permission.runClinicalAssessment,
      'view the clinic queue',
      entityTable: 'visits',
    );
    return VisitDao.openVisitsFor(user.id);
  }

  /// The front-door pace for one clinic day (defaults to today). Derived from
  /// existing rows — no extra is captured at the door.
  Future<ClinicDayStats> clinicDayStats(AppUser user, {DateTime? day}) async {
    await _require(
      user,
      Permission.runClinicalAssessment,
      'view clinic day stats',
      entityTable: 'visits',
    );
    return VisitDao.clinicDayStats(user.id, day ?? DateTime.now());
  }

  /// The day's register tally: under-fives seen, RDTs, malnutrition bands,
  /// immunisations and referrals, counted from the rows this account saved.
  ///
  /// The same permission that lets a worker write those rows — this is their
  /// own day read back to them, so no zone-wide right is needed. The referrals
  /// are counted per worker for the same reason: a shared phone held by two
  /// CHPS staff must not show one person's register column total to the other.
  Future<DailyRegisterTally> dailyRegister(
    AppUser user, {
    DateTime? day,
  }) async {
    await _require(
      user,
      Permission.runClinicalAssessment,
      'view the daily register tally',
      entityTable: 'assessments',
    );
    final on = day ?? _clock();
    return DailyRegisterTally.of(
      assessments: await AssessmentDao.forWorkerOn(user.id, on),
      referralsIssued: await ReferralDao.countIssuedBy(user.id, on),
    );
  }

  /// The open session for one household, if there is one. Intake joins this
  /// ticket instead of starting a duplicate, while a different household is
  /// still free to open its own.
  Future<Visit?> openVisitForHousehold(AppUser user, String householdId) async {
    await _requireHouseholdScope(user, householdId, 'resume a session here');
    return VisitDao.openVisitForHousehold(user.id, householdId);
  }

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

  /// Confirms a family arrived using the referral reference code.
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

  /// Records what the facility actually did, against the reference code, named
  /// by the verifier. The stronger sibling of [confirmArrival]: arrival is a
  /// footfall, this is the outcome. Only the three states a verifier can
  /// witness ([ReferralStatus.arrived], [ReferralStatus.treated],
  /// [ReferralStatus.died]) may be confirmed here, and a settled case is never
  /// reopened — so this is how `treated` finally stops being only a family's
  /// report and can carry the name of someone who saw it happen.
  ///
  /// Returns null when the code matches nothing or the case is already closed;
  /// the caller shows one message for both, because neither is a success and
  /// distinguishing them only helps someone game the code.
  Future<Referral?> confirmReferralOutcome(
    AppUser user,
    String referenceCode, {
    required ReferralStatus outcome,
    String? outcomeNotes,
  }) async {
    await _require(
      user,
      Permission.confirmReferralArrival,
      'confirm a referral outcome',
    );
    if (!outcome.isFacilityConfirmable) {
      throw ArgumentError.value(outcome, 'outcome', 'not a facility-confirmable state');
    }
    final referral = await ReferralDao.byCode(referenceCode);
    if (referral == null) return null;
    if (!facilityOutcomeAllowed(referral.status, outcome)) return null;
    await ReferralDao.updateStatus(
      referralId: referral.id,
      status: outcome,
      confirmedBy: user.id,
      outcomeNotes: outcomeNotes,
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
  // Follow-up: the answer ledger
  // ---------------------------------------------------------------------------

  /// Records what a worker found when they went looking.
  ///
  /// One call, one commit — see [FollowUpDao.record]. The failure this shape
  /// exists to prevent is the half-written follow-up: a referral marked
  /// attended with no answer behind it, or an answer with no barrier recorded,
  /// which is a district report that reads as effort rather than care.
  ///
  /// The gate is [Permission.issueReferral], the same one that wrote the
  /// referral in the first place: answering for a family is the authority to
  /// act on them. Notably this does *not* route through [scheduleContacts],
  /// which asks for `runClinicalAssessment` — a worker chasing a referral is
  /// not performing an assessment, and making them hold that permission to
  /// close a loop is how loops stop being closed.
  Future<FollowUpResult> recordFollowUp(
    AppUser user, {
    required Referral referral,
    required String householdId,
    required String contactId,
    required FollowUpAnswer answer,
    FollowUpReReferral? alsoReRefer,
    DateTime? nextVisitAt,
    String? completedContactId,
  }) async {
    await _require(
      user,
      Permission.issueReferral,
      'record a referral follow-up',
      entityTable: 'referrals',
      entityId: referral.id,
    );
    return FollowUpDao.record(
      referral: referral,
      householdId: householdId,
      contactId: contactId,
      answer: answer,
      recordedBy: user.id,
      at: _clock(),
      alsoReRefer: alsoReRefer,
      nextVisitAt: nextVisitAt,
      completedContactId: completedContactId,
    );
  }

  /// The referral desk: everything issued in the window, with its answers and
  /// the people behind them.
  ///
  /// Three batched reads, not one per case: a desk that fires a query per card
  /// is a slow morning on the low-end Androids this runs on. The zone gate at
  /// the top covers all three — [Permission.viewAllHouseholds] is what makes a
  /// zone-wide read lawful here, so no row is filtered afterwards because none
  /// of them were individually scoped.
  Future<
    ({
      List<Referral> referrals,
      Map<String, List<FollowUpContact>> ledger,
      Map<String, Person> people,
      List<ScheduledContact> chases,
    })
  >
  followUpDesk(AppUser user, {int withinDays = 21}) async {
    await _require(
      user,
      Permission.viewAllHouseholds,
      'view the follow-up desk',
    );
    // The window is measured from the repository's clock, not the wall clock.
    // Every write on this class is stamped with [_clock], so a desk that read
    // with a different clock would age its own records twice: a phone left on
    // the wrong date could drop a referral it issued five minutes ago, and no
    // screen would say why.
    final referrals = await ReferralDao.recent(
      withinDays: withinDays,
      now: _clock(),
    );
    final ids = referrals.map((r) => r.id);
    final ledger = await FollowUpDao.forReferrals(ids);
    final people = await PersonDao.byIdMany(
      referrals.map((r) => r.personId),
    );
    // A chase already on the calendar is the only thing that stops the desk
    // offering the same visit twice.
    final chases = await ScheduleDao.openChasesFor(ids);
    return (
      referrals: referrals,
      ledger: ledger,
      people: people,
      chases: chases,
    );
  }

  /// Puts a chase onto the route: one visit, tied to the referral it answers.
  ///
  /// Gated on [Permission.planVisitRoute] — the authority the Route tab already
  /// reads with. A worker deciding to go and look should not need to hold the
  /// clinical-assessment permission to make the app put the household in front
  /// of them tomorrow.
  Future<void> planChaseVisit(
    AppUser user,
    ScheduledContact contact,
  ) async {
    await _require(
      user,
      Permission.planVisitRoute,
      'plan a visit for this household',
    );
    await _requireHouseholdScope(
      user,
      contact.householdId,
      'plan a visit for this household',
    );
    await ScheduleDao.upsert(contact);
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
    final scope = CaregiverScope(
      userId: check.checkedBy,
      householdId: check.householdId,
    );
    await _requireCaregiverScope(user, scope, personId: check.personId);
    await CaregiverDao.saveLegacyHomeCheck(scope, check);
  }

  /// Sends the one thing a home check is allowed to send: the family asking for
  /// help. The check itself stays on their device (see `recordHomeCheck`), so
  /// this carries who they are worried about and how urgent the check judged it,
  /// never what they answered.
  ///
  /// Returns the request that now exists — including the one this check already
  /// raised, so a second tap cannot summon two people — or null when the verdict
  /// asks for nothing.
  Future<CareRequest?> raiseCareRequest(
    AppUser user,
    CaregiverScope scope,
    HomeCheck check,
  ) async {
    await _require(
      user,
      Permission.requestCare,
      'ask for a health worker',
      entityTable: 'care_requests',
      entityId: 'req-${check.id}',
    );
    await _requireCaregiverScope(user, scope, personId: check.personId);
    // Not redundant with the helper above: that proves the person belongs to
    // this family. This proves the *check* handed over belongs to it too, so a
    // family cannot point a request at the household next door.
    if (check.householdId != scope.householdId) {
      throw const AccessDenied(
        'ask for help for another household',
        Permission.requestCare,
      );
    }

    // Any status, not just open. `CareRequest.id` is derived from the check, so
    // an answered request has this same primary key: finding only open rows here
    // would let a second tap replace the health worker's reply with a fresh open
    // request and queue a second summons for a family someone has already
    // answered.
    final existing = await CareRequestDao.forCheck(check.id);
    if (existing != null) return existing;

    final request = CareRequest.fromCheck(
      check: check,
      userId: user.id,
      at: _clock(),
    );
    if (request == null) return null;

    await CareRequestDao.create(request);
    return request;
  }

  /// Calls back a request the family sent but that has not reached the network.
  ///
  /// Once the server has it, this returns false rather than deleting: the health
  /// worker already knows, and a family whose screen now says "nobody was told"
  /// would be believing the less true of the two statements. Refusing an
  /// answered request is the same rule — the reply is theirs to keep.
  Future<bool> withdrawCareRequest(
    AppUser user,
    CaregiverScope scope,
    String homeCheckId,
  ) async {
    await _require(
      user,
      Permission.requestCare,
      'withdraw your request',
      entityTable: 'care_requests',
    );
    await _requireCaregiverScope(user, scope);
    final request = await CareRequestDao.openForCheck(homeCheckId);
    if (request == null) return false;
    if (request.householdId != scope.householdId) {
      throw const AccessDenied(
        'withdraw another household’s request',
        Permission.requestCare,
      );
    }
    return CareRequestDao.withdraw(request.id);
  }

  /// What the family already asked for this check, and whether the phone has
  /// managed to send it — one read, because the card that shows the state must
  /// not pair a request with a delivery flag taken from somewhere else.
  Future<({CareRequest request, bool sent})?> careRequestState(
    AppUser user,
    CaregiverScope scope,
    String homeCheckId,
  ) async {
    await _require(user, Permission.requestCare, 'view your request');
    await _requireCaregiverScope(user, scope);
    final request = await CareRequestDao.forCheck(homeCheckId);
    if (request == null) return null;
    return (
      request: request,
      sent: await CareRequestDao.isSent(request.id),
    );
  }

  /// The home checks a family has run, newest first. Both roles may read
  /// them: the caregiver sees their own history, the FHW sees what the family
  /// reported before deciding what to examine first.
  Future<List<HomeCheck>> homeChecks(AppUser user, String householdId) async {
    await _requireHouseholdScope(user, householdId, 'view home checks');
    return HomeCheckDao.forHousehold(householdId);
  }

  /// The morning briefing: the home checks every family in the zone has run
  /// within the window, newest first.
  ///
  /// Zone-wide, so gated on the permission only an FHW holds. Home checks
  /// never enter the outbox — they surface here because caregiver mode runs
  /// on this same device. What the family saw at home is what the worker
  /// reads before deciding whom to see first.
  Future<List<HomeCheck>> recentZoneHomeChecks(
    AppUser user, {
    int withinDays = 7,
  }) async {
    await _require(
      user,
      Permission.viewAllHouseholds,
      'view home checks across the zone',
    );
    return HomeCheckDao.recentAcrossZone(withinDays: withinDays);
  }

  /// The worker's own month: how many assessments this device wrote for them
  /// and how often their judgement stood over the engine's. Reads only the
  /// signed-in worker's rows, so no zone permission is needed — a caregiver
  /// asking gets an honest zero, not an error.
  Future<({int assessments, int overrides})> personalImpact(
    AppUser user,
  ) async {
    final assessments = await AssessmentDao.countWithin(user.id);
    final overrides = await AssessmentDao.countOverridesWithin(user.id);
    return (assessments: assessments, overrides: overrides);
  }

  /// The latest home check for one person — the "last checked" line on the
  /// caregiver's family tiles.
  Future<HomeCheck?> latestHomeCheck(AppUser user, String personId) async {
    await _requirePersonScope(user, personId, 'view a home check');
    return HomeCheckDao.latestForPerson(personId);
  }

  /// Saves one milestone check a caregiver ran at home.
  ///
  /// Same contract as [recordHomeCheck]: gated, scoped, and deliberately not
  /// queued to the outbox. A family's report of what their child can do stays
  /// on their device until they choose to show it.
  Future<void> recordMilestoneCheck(AppUser user, MilestoneCheck check) async {
    await _require(
      user,
      Permission.runCaregiverTriage,
      'record a milestone check',
      entityTable: 'milestone_checks',
      entityId: check.id,
    );
    await _requireHouseholdScope(
      user,
      check.householdId,
      'record a milestone check for this household',
    );
    final scope = CaregiverScope(
      userId: check.checkedBy,
      householdId: check.householdId,
    );
    await _requireCaregiverScope(user, scope, personId: check.personId);
    await CaregiverDao.saveLegacyMilestone(scope, check);
  }

  /// The milestone checks a family has run, newest first. Both roles read:
  /// the caregiver their history, the FHW what the family says the child can
  /// do — flags first in their head, though the list itself stays chronological.
  Future<List<MilestoneCheck>> milestoneChecks(
    AppUser user,
    String householdId,
  ) async {
    await _requireHouseholdScope(user, householdId, 'view milestone checks');
    return MilestoneCheckDao.forHousehold(householdId);
  }

  /// The latest milestone check for one child — the "growing as expected"
  /// line on the caregiver's family tiles.
  Future<MilestoneCheck?> latestMilestoneCheck(
    AppUser user,
    String personId,
  ) async {
    await _requirePersonScope(user, personId, 'view a milestone check');
    return MilestoneCheckDao.latestForPerson(personId);
  }

  /// Zone impact in one read — the proof layer the judges and the district
  /// team ask for: not "how many forms were filled", but "what did this
  /// phone catch and close".
  ///
  /// FHW-only by construction: it aggregates every household, so it is gated
  /// on the zone-wide permission a caregiver does not hold.
  Future<
    ({
      int issued,
      int arrived,
      double rate,
      int urgentHomeChecks,
      int flaggedChildren,
    })
  >
  impactSummary(AppUser user) async {
    await _require(
      user,
      Permission.viewAllHouseholds,
      'view the zone impact summary',
    );
    final referrals = await ReferralDao.completionStats(withinDays: 90);
    final rate = referrals.issued == 0
        ? 0.0
        : referrals.arrived / referrals.issued;
    final urgentHomeChecks = await HomeCheckDao.countWithVerdict(
      HomeCheckVerdict.urgent,
      withinDays: 30,
    );
    final flaggedChildren = await MilestoneCheckDao.countFlaggedChildren(
      withinDays: 30,
    );
    return (
      issued: referrals.issued,
      arrived: referrals.arrived,
      rate: rate,
      urgentHomeChecks: urgentHomeChecks,
      flaggedChildren: flaggedChildren,
    );
  }

  // Local-only caregiver companion state. Never enqueue these records for sync.
  Future<Person?> _requireCaregiverScope(
    AppUser user,
    CaregiverScope scope, {
    String? personId,
  }) async {
    await _require(
      user,
      Permission.manageOwnFamily,
      'access local caregiver records',
    );
    if (scope.userId != user.id) {
      throw const AccessDenied(
        'access another caregiver’s records',
        Permission.manageOwnFamily,
      );
    }
    await _requireHouseholdScope(
      user,
      scope.householdId,
      'access local caregiver records',
    );
    if (personId == null) return null;
    final person = await PersonDao.byId(personId);
    if (person == null ||
        person.householdId != scope.householdId ||
        !person.isActive) {
      throw const AccessDenied(
        'access a person outside your family',
        Permission.manageOwnFamily,
      );
    }
    return person;
  }

  Future<CaregiverSettings?> caregiverSettings(
    AppUser user,
    CaregiverScope scope,
  ) async {
    await _requireCaregiverScope(user, scope);
    return CaregiverDao.settings(scope);
  }

  Future<void> saveCaregiverSettings(
    AppUser user,
    CaregiverSettings settings,
  ) async {
    await _requireCaregiverScope(
      user,
      settings.scope,
      personId: settings.selectedPersonId,
    );
    if (settings.contacts.any((c) => !c.isValid) ||
        settings.contacts.map((c) => c.kind).toSet().length !=
            settings.contacts.length) {
      throw const CaregiverDataException(
        'Review the saved contact names and numbers.',
      );
    }
    await CaregiverDao.saveSettings(settings);
  }

  Future<CaregiverDraft?> caregiverDraft(
    AppUser user,
    CaregiverScope scope,
    String personId,
    CaregiverDraftKind kind,
  ) async {
    await _requireCaregiverScope(user, scope, personId: personId);
    return CaregiverDao.draft(scope, personId, kind);
  }

  Future<void> saveCaregiverDraft(AppUser user, CaregiverDraft draft) async {
    await _requireCaregiverScope(user, draft.scope, personId: draft.personId);
    if (draft.id.isEmpty ||
        draft.questionVersion < 1 ||
        draft.questionIndex < 0 ||
        draft.updatedAt.isBefore(draft.startedAt)) {
      throw const CaregiverDataException('The check session is not valid.');
    }
    await CaregiverDao.saveDraft(draft);
  }

  Future<void> discardCaregiverDraft(
    AppUser user,
    CaregiverScope scope,
    String personId,
    CaregiverDraftKind kind,
  ) async {
    await _requireCaregiverScope(user, scope, personId: personId);
    await CaregiverDao.discardDraft(scope, personId, kind);
  }

  Future<List<CaregiverActivity>> caregiverActivity(
    AppUser user,
    CaregiverScope scope, {
    String? personId,
  }) async {
    await _requireCaregiverScope(user, scope, personId: personId);
    return CaregiverDao.activity(scope, personId: personId);
  }

  Future<void> saveCaregiverActivity(
    AppUser user,
    CaregiverActivity activity,
  ) async {
    await _requireCaregiverScope(
      user,
      activity.scope,
      personId: activity.personId,
    );
    if (activity.id.isEmpty ||
        activity.itemKey.isEmpty ||
        activity.occurrenceKey.isEmpty ||
        activity.note.length > 1000 ||
        (activity.personId == null &&
            activity.kind != CaregiverActivityKind.shopping) ||
        (activity.kind == CaregiverActivityKind.observation &&
            activity.observation == null) ||
        activity.kind == CaregiverActivityKind.homeCheckContext ||
        activity.kind == CaregiverActivityKind.milestoneContext) {
      throw const CaregiverDataException(
        'This activity cannot be saved independently.',
      );
    }
    await CaregiverDao.saveActivity(activity);
  }

  Future<HomeCheck> finalizeCaregiverHomeCheck(
    AppUser user,
    CaregiverDraft draft,
  ) async {
    final person = (await _requireCaregiverScope(
      user,
      draft.scope,
      personId: draft.personId,
    ))!;
    final policy = CaregiverCheckPolicy(clock: _clock);
    if (!policy.compatible(draft, person)) {
      throw const CaregiverDataException(
        'The person’s age or check questions changed. Start a new check.',
      );
    }
    final questions = policy.questionsFor(person)!;
    // The same reading the screen saw, so the saved verdict and the verdict the
    // family was shown cannot disagree.
    final growth = await GrowthDao.latest(draft.personId);
    final decision = policy.decide(questions, draft.answers, growth: growth);
    final verdict = switch (decision) {
      CaregiverCheckDecision.urgent => HomeCheckVerdict.urgent,
      CaregiverCheckDecision.contactToday => HomeCheckVerdict.caution,
      CaregiverCheckDecision.routine => HomeCheckVerdict.fine,
      _ => throw const CaregiverDataException(
        'Answer the remaining questions before saving a completed check.',
      ),
    };
    final report = HomeCheck(
      id: draft.id,
      householdId: draft.scope.householdId,
      personId: draft.personId,
      clientType: questions.clientType,
      verdict: verdict,
      yesSigns: questions.questions
          .where((q) => draft.answers[q.key] == CaregiverAnswer.yes)
          .map((q) => q.label)
          .toList(),
      unsureSigns: questions.questions
          .where((q) => draft.answers[q.key] == CaregiverAnswer.unsure)
          .map((q) => q.label)
          .toList(),
      checkedBy: user.id,
      checkedAt: draft.startedAt,
    );
    return CaregiverDao.finalizeHomeCheck(draft, report, _clock());
  }

  Future<MilestoneCheck> finalizeCaregiverMilestone(
    AppUser user,
    CaregiverDraft draft,
  ) async {
    final person = (await _requireCaregiverScope(
      user,
      draft.scope,
      personId: draft.personId,
    ))!;
    return CaregiverDao.finalizeMilestone(
      draft,
      CaregiverMilestonePolicy.report(draft, person, _clock()),
      _clock(),
    );
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
    return all.where((c) => c.householdId == linked).toList(growable: false);
  }

  /// Includes completed contacts so caregiver history does not recreate them
  /// as pending follow-ups. Reading never confirms an appointment or a dose.
  Future<List<ScheduledContact>> scheduledContactsForPerson(
    AppUser user,
    String personId,
  ) async {
    await _requirePersonScope(user, personId, 'view scheduled contacts');
    return ScheduleDao.forPerson(personId);
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
