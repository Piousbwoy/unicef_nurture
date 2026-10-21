/// Governance as code: the record of processing activities, the access matrix and
/// the control map, written in the same language as the system they describe.
///
/// ### Why this file exists instead of a PDF
///
/// A privacy register written as a document is a snapshot of what somebody believed
/// on the day they wrote it. In a codebase that gains a table every few weeks, a
/// document becomes wrong quietly — and a *wrong* register is worse than an absent
/// one, because a district that relies on it has been misled in writing. Act 843
/// s.27 makes the organisation responsible for what it processes; nothing in a text
/// file checks that the organisation is honest about its own database.
///
/// So the register below is data, and `test/governance_test.dart` reconciles it
/// against four artefacts that are not opinions:
///
///  * the local schema built by [AppDatabase] — every table created on a handset;
///  * `server/schema.sql` — every table the district keeps;
///  * `server/src/tables.js` — the sync whitelist, i.e. what may leave a handset;
///  * `server/src/pull.js` — the pull list, i.e. what may arrive on another one.
///
/// Add a table and the build fails until it has a declared purpose, a lawful basis,
/// a retention rule and a place in the matrix. Remove one and the build fails until
/// the register stops claiming it. That is the only form of compliance document an
/// engineer can actually trust.
///
/// ### What this file deliberately does not do
///
/// It does not rate the app "compliant". Section [SecurityControl] records what is
/// implemented, where, and which test proves it — and says out loud, in
/// [SecurityControl.boundary], what it does not cover. Controls that belong to the
/// district, not to software, are listed with [ControlOwnership.notOurs] rather than
/// quietly dropped from the map.
library;

import 'compliance.dart';
import 'enums.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Where a piece of data physically lives
// ─────────────────────────────────────────────────────────────────────────────

/// How far a table's contents travel. Derived from the artefacts named above, and
/// checked against them in CI — this enum is a claim, not an assertion.
enum StorageScope {
  /// On the handset only. Never admitted by the sync whitelist.
  deviceOnly('On this device only'),

  /// Written here, kept by the district, and handed out again on pull.
  deviceAndDistrict('This device and the district'),

  /// Sent from the device but never stored in local SQLite — the row goes straight
  /// into the outbox. A credential verifier lives here on purpose: the derivation
  /// that lets the cloud authenticate a PIN must not sit beside the record it
  /// unlocks.
  pushedNotStored('Sent from the device, kept only at the district'),

  /// Exists only on the server. No handset can create or change these rows.
  districtOnly('District only');

  const StorageScope(this.label);
  final String label;
}

/// One table, its scope, and the activity that justifies it.
class StoredData {
  const StoredData({
    required this.table,
    required this.scope,
    required this.activity,
    required this.contains,
  });

  final String table;
  final StorageScope scope;

  /// Id of the [ProcessingActivity] that declares why this data exists.
  final String activity;

  /// Plain words on what the rows hold, because "persons" says nothing to a
  /// supervisor or a family reading the register.
  final String contains;

  bool get travelsToDistrict =>
      scope == StorageScope.deviceAndDistrict ||
      scope == StorageScope.pushedNotStored;
}

// ─────────────────────────────────────────────────────────────────────────────
// The record of processing activities
// ─────────────────────────────────────────────────────────────────────────────

/// The Act 843 basis this build relies on, stated per activity rather than once for
/// the whole app, because "we process HIV results" and "we log that a supervisor
/// opened a queue" are not the same justification.
enum LawfulBasis {
  /// The family was told, in their language, and agreed — recorded as an append-only
  /// consent event, not a checkbox.
  consent('Consent of the data subject'),

  /// Needed to give the care itself. Written where a contract or a statutory duty
  /// would say the same thing: the visit cannot happen without the row.
  careProvided('Necessary to provide the health care recorded'),

  /// A legal obligation the district carries and this app helps discharge.
  legalObligation('Legal obligation of the data controller'),

  /// Keeping the accountability evidence — the trail, the anchors, the read log —
  /// so a dispute can be settled with facts.
  accountability('Necessary for the accountability record'),

  /// Rows that hold no patient content at all.
  operation('System operation, no personal data processed');

  const LawfulBasis(this.label);
  final String label;
}

/// A purpose of processing, with the questions a supervisory authority asks about
/// it: whose data, what for, on what basis, for how long, and who may see it.
class ProcessingActivity {
  const ProcessingActivity({
    required this.id,
    required this.title,
    required this.purpose,
    required this.basis,
    required this.subjects,
    required this.retention,
    required this.guard,
    this.readBy = const {},
    this.writeBy = const {},
    this.specialPersonalData = false,
    this.nonTableStorage = '',
  });

  final String id;
  final String title;

  /// What the processing is *for*, in the words of the person doing it.
  final String purpose;
  final LawfulBasis basis;

  /// Whose data this is.
  final String subjects;

  /// The rule this build applies, plus who owns the decision if it is not the app's.
  final String retention;

  /// The code that actually enforces access — named, so a claim in the register can
  /// be gone and read. A matrix with no enforcement point is a wish.
  final String guard;

  /// Capabilities that let a role read rows in this activity. Empty for
  /// server-managed rows no app role opens directly.
  final Set<Permission> readBy;
  final Set<Permission> writeBy;

  /// Act 843 s.37 special personal data — health, and the beliefs and genetics that
  /// come with it. Higher duty of care, and the reason these rows are the ones the
  /// protection class exists for.
  final bool specialPersonalData;

  /// Where the data sits when it is not a SQLite table — stated rather than left
  /// implicit, because "the register covers the database" is exactly how a file
  /// full of de-identified patient records ends up undeclared. An activity with no
  /// table must fill this in; CI checks it.
  final String nonTableStorage;

  bool get hasAppVisibleRules => readBy.isNotEmpty || writeBy.isNotEmpty;
}

// ─────────────────────────────────────────────────────────────────────────────
// The control map
// ─────────────────────────────────────────────────────────────────────────────

/// How far a control is really implemented. `liveWithBoundary` is the honest
/// majority: a control that cannot reach every platform is still a control, as long
/// as the screen says where it stops.
enum ControlMaturity {
  live('In place'),
  liveWithBoundary('In place, with a stated limit'),
  planned('Not built yet'),
  notOurs('Not this software’s to implement');

  const ControlMaturity(this.label);
  final String label;
}

/// Who owns the residual risk a control does not cover.
enum ControlOwnership {
  /// The app team, in this repository.
  appTeam,

  /// The CHPS compound or district that deploys it: rosters, training, retention
  /// periods, breach notification to the Secretariat.
  controller,

  /// Shared: the software provides the mechanism, the deployment must use it.
  both,
}

/// One safeguard, where it lives, and what proves it works.
class SecurityControl {
  const SecurityControl({
    required this.id,
    required this.problem,
    required this.answer,
    required this.maturity,
    required this.frameworks,
    required this.implementations,
    this.proofTests = const [],
    this.boundary = '',
    this.owner = ControlOwnership.appTeam,
  });

  final String id;

  /// The failure being prevented, in operational terms — not the control's name.
  final String problem;
  final String answer;
  final ControlMaturity maturity;

  /// External references, quoted as they are usually cited: OWASP MASVS groups,
  /// HIPAA Security Rule paragraphs, Act 843 sections.
  final List<String> frameworks;

  /// Repository-relative paths. CI checks they exist, so a control map cannot cite
  /// a file that was never written or has since been renamed.
  final List<String> implementations;

  /// Repository-relative test files. A `live` claim needs one, or a
  /// [boundary] sentence explaining what stands in for it.
  final List<String> proofTests;

  /// What this control does not do. Left blank only when there is nothing to
  /// concede, which is rare.
  final String boundary;
  final ControlOwnership owner;

  bool get needsProof =>
      maturity == ControlMaturity.live ||
      maturity == ControlMaturity.liveWithBoundary;
}

// ─────────────────────────────────────────────────────────────────────────────
// The register
// ─────────────────────────────────────────────────────────────────────────────

abstract final class GovernanceRegister {
  /// Every table in the system, and why it is there.
  static const List<StoredData> data = [
    // ── Identity and access ────────────────────────────────────────────
    StoredData(
      table: 'users',
      scope: StorageScope.deviceAndDistrict,
      activity: 'identity',
      contains:
          'A health worker’s name, phone number, role and the CHPS zone they '
          'are assigned to; or a caregiver’s name, phone number and the one '
          'household their account is bound to. On the district copy the PIN '
          'columns do not exist.',
    ),
    StoredData(
      table: 'user_verifiers',
      scope: StorageScope.pushedNotStored,
      activity: 'identity',
      contains:
          'The salted, domain-separated derivation the cloud authenticates '
          'against. Never stored in local SQLite, because a verifier kept '
          'beside the records it unlocks is a second key in the same pocket.',
    ),
    StoredData(
      table: 'refresh_tokens',
      scope: StorageScope.districtOnly,
      activity: 'sessions',
      contains:
          'Server-issued session material, hashed, with its expiry. A handset '
          'cannot write this table even if it is compromised.',
    ),

    // ── The register of families ───────────────────────────────────────
    StoredData(
      table: 'households',
      scope: StorageScope.deviceAndDistrict,
      activity: 'household',
      contains:
          'Household name, head of household, contact phone, GPS point, walking '
          'time to the facility, NHIS validity and household size.',
    ),
    StoredData(
      table: 'persons',
      scope: StorageScope.deviceAndDistrict,
      activity: 'person',
      contains:
          'Full name, client type, sex, date of birth (sometimes estimated), '
          'phone, NHIS number, the mother a newborn links to, and the protection '
          'class marking.',
    ),
    StoredData(
      table: 'home_checks',
      scope: StorageScope.deviceOnly,
      activity: 'household',
      contains:
          'The environmental checks a worker performs at the dwelling: water, '
          'sanitation, sleeping arrangement, insecticide-treated net use.',
    ),
    StoredData(
      table: 'milestone_checks',
      scope: StorageScope.deviceOnly,
      activity: 'child',
      contains:
          'Which developmental milestones a child was observed to reach, and when.',
    ),

    // ── Health, by life stage ──────────────────────────────────────────
    StoredData(
      table: 'maternal_records',
      scope: StorageScope.deviceAndDistrict,
      activity: 'maternal',
      contains:
          'Pregnancy and postnatal history, antenatal interventions, laboratory '
          'results including HIV, syphilis and hepatitis B testing, pre-eclampsia '
          'signs, birth-outcome data, breastfeeding findings and the full '
          'Edinburgh postnatal depression scale — including the self-harm item.',
    ),
    StoredData(
      table: 'birth_records',
      scope: StorageScope.deviceAndDistrict,
      activity: 'newborn',
      contains:
          'Birth measurements, delivery circumstances, Apgar scores, newborn '
          'danger signs,Kangaroo Mother Care details, sickle cell screening and '
          'hearing screening.',
    ),
    StoredData(
      table: 'growth_measurements',
      scope: StorageScope.deviceAndDistrict,
      activity: 'child',
      contains:
          'Weight, length or height, MUAC, bilateral oedema and palmar pallor, '
          'each tied to the child and the time it was taken.',
    ),
    StoredData(
      table: 'child_assessment_snapshots',
      scope: StorageScope.deviceAndDistrict,
      activity: 'child',
      contains:
          'The IMCI assessment as performed: symptom history, vital signs, '
          'classification inputs, immunisation and feeding detail, malaria RDT '
          'result, and the HIV exposure status of the child.',
    ),

    // ── The visit, and what came of it ─────────────────────────────────
    StoredData(
      table: 'visits',
      scope: StorageScope.deviceAndDistrict,
      activity: 'encounter',
      contains:
          'Which household was walked to, by whom, when, the GPS point, the '
          'reasons recorded and free-text notes.',
    ),
    StoredData(
      table: 'visit_participants',
      scope: StorageScope.deviceAndDistrict,
      activity: 'encounter',
      contains:
          'The roll call: who in the household was present, who was absent and '
          'the note explaining the absence.',
    ),
    StoredData(
      table: 'assessments',
      scope: StorageScope.deviceAndDistrict,
      activity: 'encounter',
      contains:
          'The stored verdict of an assessment — inputs, result and care plan as '
          'JSON — plus any override of the AI recommendation, the reason for it '
          'and who made it.',
    ),
    StoredData(
      table: 'referrals',
      scope: StorageScope.deviceAndDistrict,
      activity: 'referral',
      contains:
          'The referral letter itself: reference code, the person referred, the '
          'facility, urgency, clinical summary, and who confirmed arrival or '
          'escalated it.',
    ),
    StoredData(
      table: 'follow_up_contacts',
      scope: StorageScope.deviceAndDistrict,
      activity: 'referral',
      contains:
          'Each check-in after a referral: whether the family was reached, what '
          'care they actually received, their condition, and the barriers named.',
    ),
    StoredData(
      table: 'scheduled_contacts',
      scope: StorageScope.deviceAndDistrict,
      activity: 'referral',
      contains: 'The next contact a family is due, its purpose and priority.',
    ),

    // ── What the family says and asks ──────────────────────────────────
    StoredData(
      table: 'barrier_reports',
      scope: StorageScope.deviceAndDistrict,
      activity: 'barrier',
      contains:
          'The obstacles a family reports in their own terms — money, distance, '
          'an elder who must agree, a closed post — with notes and whether the '
          'barrier was later resolved.',
    ),
    StoredData(
      table: 'care_requests',
      scope: StorageScope.deviceAndDistrict,
      activity: 'familyRequest',
      contains:
          'A family asking a health worker to come, at what urgency, and the '
          'answer the worker gave on another handset.',
    ),
    StoredData(
      table: 'caregiver_drafts',
      scope: StorageScope.deviceOnly,
      activity: 'familyRequest',
      contains:
          'A caregiver’s unfinished entry, held on this handset until it is sent '
          'or discarded. It is not a record of anything the district holds.',
    ),
    StoredData(
      table: 'caregiver_activity',
      scope: StorageScope.deviceOnly,
      activity: 'familyVoice',
      contains:
          'What the family did in the app themselves: which guidance they opened, '
          'which questions they asked. Deliberately not whitelisted for sync — a '
          'family’s own reading is not data the service gets to collect about them.',
    ),
    StoredData(
      table: 'caregiver_settings',
      scope: StorageScope.deviceOnly,
      activity: 'familyVoice',
      contains:
          'This handset’s preferences for a caregiver account: language, reminder '
          'times, notice acknowledgement.',
    ),

    // ── The accountability spine ───────────────────────────────────────
    StoredData(
      table: 'consent_events',
      scope: StorageScope.deviceAndDistrict,
      activity: 'consent',
      contains:
          'Every consent decision ever made, as its own row: the scope, the '
          'decision, which version of the notice was read out, the language, an '
          'optional voice artefact and the witness. Withdrawal is a new row, never '
          'an edit.',
    ),
    StoredData(
      table: 'access_ledger',
      scope: StorageScope.deviceAndDistrict,
      activity: 'accessTrail',
      contains:
          'One row per opening of a record: who, in what role, on which device, '
          'doing what to whom, for which purpose, on what basis, with the hash '
          'that chains it to the row before it.',
    ),
    StoredData(
      table: 'ledger_anchors',
      scope: StorageScope.pushedNotStored,
      activity: 'accessTrail',
      contains:
          'Every tenth entry, the device’s commitment to its own chain position — '
          'the hash and the count. Immutable on the server by trigger, which is '
          'what makes a shortened trail detectable rather than merely possible.',
    ),
    StoredData(
      table: 'data_rights_requests',
      scope: StorageScope.deviceAndDistrict,
      activity: 'dataRights',
      contains:
          'A family’s request to see, correct, object, erase or carry away their '
          'data, the 30-day clock it started, and the answer given.',
    ),
    StoredData(
      table: 'server_read_log',
      scope: StorageScope.districtOnly,
      activity: 'districtReads',
      contains:
          'What the district handed out: which account pulled which scope, how '
          'many rows, and every recovery download. Written only by the server — a '
          'read log a handset could write to is a read log that can be emptied.',
    ),

    // ── Machine rows, no patient content ───────────────────────────────
    StoredData(
      table: 'sync_outbox',
      scope: StorageScope.deviceOnly,
      activity: 'machinery',
      contains:
          'The queue of writes waiting for a network. It carries copies of '
          'patient payloads until they are admitted, which is why it lives inside '
          'the encrypted database rather than in a plain text file.',
    ),
    StoredData(
      table: 'sync_state',
      scope: StorageScope.deviceOnly,
      activity: 'machinery',
      contains:
          'This device’s watermarks and last admitted sequence. Nothing about a '
          'family is in this table.',
    ),
    StoredData(
      table: 'audit_log',
      scope: StorageScope.deviceOnly,
      activity: 'machinery',
      contains:
          'The device’s own operational log of authentication and synchronisation '
          'events. Distinct from the access ledger: this records that a session '
          'opened, not that a record was read.',
    ),
    StoredData(
      table: 'sync_log',
      scope: StorageScope.districtOnly,
      activity: 'districtIngest',
      contains:
          'The server’s receipt for every admitted change: who sent it, which '
          'entity, whether it was accepted or refused. Never delivered to a '
          'handset — the receipt for somebody else’s sync is not data to sync.',
    ),
  ];

  /// Why each of the above exists.
  static const List<ProcessingActivity> activities = [
    ProcessingActivity(
      id: 'identity',
      title: 'Account identity and cloud authentication',
      purpose:
          'To know whose hands the handset is in, to scope every query to the '
          'caseload that account is responsible for, and to let the same worker '
          'sign in on a replacement device after a loss.',
      basis: LawfulBasis.legalObligation,
      subjects: 'Health workers and enrolled caregivers, not patients.',
      retention:
          'For as long as the account is in use. The district copy holds no PIN '
          'material, so there is nothing there to compromise when an account ends.',
      guard:
          'AuthenticationService, and the per-role capability set in '
          'Permission.forRole.',
      readBy: {Permission.viewCommunityInsights},
      writeBy: {Permission.registerHousehold},
    ),
    ProcessingActivity(
      id: 'sessions',
      title: 'Server-issued session material',
      purpose:
          'To end a stolen bearer token without waiting for it to expire, and to '
          'revoke every session on a device reported lost.',
      basis: LawfulBasis.operation,
      subjects: 'Health workers and enrolled caregivers.',
      retention:
          'Until expiry or revocation. No app role reads this table; the server '
          'does, on its own authority.',
      guard: 'server/src/auth.js, which stores hashes and honours revocation.',
    ),
    ProcessingActivity(
      id: 'household',
      title: 'Household registration and the visit to the dwelling',
      purpose:
          'To find the family at all, to reach them in an emergency, and to record '
          'the shared risks — water, sanitation, sleeping arrangement, net use — '
          'that belong to the dwelling rather than to one person.',
      basis: LawfulBasis.consent,
      subjects:
          'Every person resident in the household, including those not '
          'otherwise enrolled.',
      retention:
          'While the household is under the CHPS zone’s care. Environmental check '
          'history stays on the device that recorded it; the district keeps the '
          'household itself.',
      guard:
          'CareRepository._requireHouseholdScope, which refuses a household '
          'outside the account’s own scope.',
      readBy: {Permission.viewAllHouseholds, Permission.viewOwnFamilyOnly},
      writeBy: {Permission.registerHousehold, Permission.manageOwnFamily},
    ),
    ProcessingActivity(
      id: 'person',
      title: 'The person register',
      purpose:
          'To name the individual care is being given to, to link a newborn to its '
          'mother, and to check NHIS cover before a referral is sent.',
      basis: LawfulBasis.consent,
      subjects: 'Enrolled individuals.',
      retention:
          'While the person is in the programme. A erasure request removes the '
          'name, phone and NHIS number and leaves the clinical history without '
          'identifiers.',
      guard:
          'RecordAccessPolicy, which is where the protection class and the '
          'caseload relationship are actually decided.',
      readBy: {Permission.viewAllHouseholds, Permission.viewOwnFamilyOnly},
      writeBy: {Permission.registerHousehold, Permission.manageOwnFamily},
    ),
    ProcessingActivity(
      id: 'maternal',
      title: 'Pregnancy, birth and postnatal health',
      purpose:
          'To run the antenatal and postnatal schedule, to detect pre-eclampsia '
          'and postpartum danger signs while they are still actionable, and to '
          'screen for PMTCT and the mother’s mental health.',
      basis: LawfulBasis.consent,
      subjects: 'Pregnant and postpartum women.',
      retention:
          'Per Ghana Health Service health-records retention, which this build '
          'does not decide. Deletion on request is handled by erasing identifiers '
          'and keeping the de-identified history.',
      guard:
          'RecordAccessPolicy plus the HIV, syphilis, hepatitis B, sickling and '
          'Edinburgh self-harm columns, which are the reason the protection class '
          'exists.',
      readBy: {Permission.viewAllHouseholds, Permission.viewOwnFamilyOnly},
      writeBy: {
        Permission.recordClinicalVitals,
        Permission.runClinicalAssessment,
      },
      specialPersonalData: true,
    ),
    ProcessingActivity(
      id: 'newborn',
      title: 'Newborn health at and after birth',
      purpose:
          'To resuscitate and thermal-care the newborn on evidence, to run the '
          'day-by-day danger-sign checks, and to complete birth screening '
          'including sickle cell and hearing.',
      basis: LawfulBasis.consent,
      subjects: 'Newborns.',
      retention: 'As for maternal health records.',
      guard: 'RecordAccessPolicy.',
      readBy: {Permission.viewAllHouseholds, Permission.viewOwnFamilyOnly},
      writeBy: {
        Permission.recordClinicalVitals,
        Permission.runClinicalAssessment,
      },
      specialPersonalData: true,
    ),
    ProcessingActivity(
      id: 'child',
      title: 'Child growth, development and illness classification',
      purpose:
          'To plot growth against WHOs standards and catch faltering early, to '
          'record developmental milestones, and to classify a sick child into '
          'the right IMCI category at the point of care.',
      basis: LawfulBasis.consent,
      subjects: 'Newborns and children under five.',
      retention: 'As for maternal health records.',
      guard: 'RecordAccessPolicy.',
      readBy: {Permission.viewAllHouseholds, Permission.viewOwnFamilyOnly},
      writeBy: {
        Permission.recordClinicalVitals,
        Permission.runClinicalAssessment,
        Permission.runCaregiverTriage,
      },
      specialPersonalData: true,
    ),
    ProcessingActivity(
      id: 'encounter',
      title: 'The visit, the roll call and the assessment verdict',
      purpose:
          'To evidence that a visit happened and whom it reached, to carry the '
          'classification and care plan forward, and to keep an AI recommendation '
          'overridable by a named human with a stated reason.',
      basis: LawfulBasis.careProvided,
      subjects: 'Everyone present at the visit.',
      retention: 'As for health records.',
      guard:
          'VisitDao and the override columns on assessments, which refuse an '
          'override without a reason and a person.',
      readBy: {Permission.viewAllHouseholds, Permission.viewOwnFamilyOnly},
      writeBy: {
        Permission.runClinicalAssessment,
        Permission.overrideAiRecommendation,
        Permission.planVisitRoute,
      },
      specialPersonalData: true,
    ),
    ProcessingActivity(
      id: 'referral',
      title: 'Referral, arrival and follow-up',
      purpose:
          'To get a mother to a facility that knows she is coming, and then to '
          'answer the question the paper system never closes: did she arrive, and '
          'what care did she actually receive?',
      basis: LawfulBasis.careProvided,
      subjects: 'The referred person and the household that followed up.',
      retention:
          'Until the episode is closed and reported, then as a health record.',
      guard:
          'RecordAccessPolicy and the referral scope checks in CareRepository.',
      readBy: {Permission.viewAllHouseholds},
      writeBy: {
        Permission.issueReferral,
        Permission.confirmReferralArrival,
      },
      specialPersonalData: true,
    ),
    ProcessingActivity(
      id: 'barrier',
      title: 'Barriers the family reports',
      purpose:
          'To record in the family’s own words why care did not happen, so the '
          'compound plans around it rather than logging a default.',
      basis: LawfulBasis.consent,
      subjects: 'The household or person reporting.',
      retention: 'Until resolved, then kept as history of the obstacle.',
      guard: 'CareRepository scope checks; no clinical field is writable here.',
      readBy: {Permission.viewAllHouseholds, Permission.viewOwnFamilyOnly},
      writeBy: {Permission.recordBarrier},
    ),
    ProcessingActivity(
      id: 'familyRequest',
      title: 'A family asking for care',
      purpose:
          'To let a household call a worker to the door, and to make sure the '
          'answer — not silence — reaches the handset the question came from.',
      basis: LawfulBasis.consent,
      subjects: 'The requesting household.',
      retention: 'Until answered, plus the record of the answer.',
      guard:
          'CareRepository, which binds a caregiver account to exactly one '
          'household; drafts stay on this device until sent.',
      readBy: {Permission.viewAllHouseholds, Permission.viewOwnFamilyOnly},
      writeBy: {Permission.requestCare, Permission.manageOwnFamily},
    ),
    ProcessingActivity(
      id: 'familyVoice',
      title: 'What the family read and asked on their own handset',
      purpose:
          'To resume the guidance where the family left off, on this handset, in '
          'their language.',
      basis: LawfulBasis.consent,
      subjects: 'The caregiver account and the household it is bound to.',
      retention: 'Until the family clears it, on this device only.',
      guard:
          'Storage scope: these rows are deliberately absent from the sync '
          'whitelist, so reading about infant feeding does not create a file at '
          'the district.',
      readBy: {Permission.viewOwnFamilyOnly},
      writeBy: {Permission.manageOwnFamily},
    ),
    ProcessingActivity(
      id: 'consent',
      title: 'The consent history',
      purpose:
          'To be able to say, months later, which notice was read out, in what '
          'language, on what date, and what was agreed to — including what was '
          'later withdrawn.',
      basis: LawfulBasis.accountability,
      subjects: 'The consenting individual and the household.',
      retention:
          'Longer than the record it authorises. A withdrawal is a new row, so the '
          'fact that care was lawful between two dates survives.',
      guard: 'ConsentDao, which exposes no update and no delete.',
      readBy: {Permission.viewAllHouseholds},
      writeBy: {Permission.registerHousehold},
    ),
    ProcessingActivity(
      id: 'accessTrail',
      title: 'The tamper-evident access ledger and its anchors',
      purpose:
          'To answer a family’s question “who looked at my record”, and to let the '
          'district notice a trail that was rewritten after the fact.',
      basis: LawfulBasis.accountability,
      subjects: 'The worker who looked, and the person looked at.',
      retention:
          'Retained after erasure of the record it describes: destroying the '
          'evidence of an access would destroy the account of whether it was '
          'lawful.',
      guard:
          'AccessLedgerDao, which appends only; the HMAC chain key lives in '
          'secure storage and is never transmitted; ledger_anchors is immutable by '
          'server trigger.',
      readBy: {Permission.viewCommunityInsights},
      writeBy: {Permission.viewAllHouseholds},
    ),
    ProcessingActivity(
      id: 'dataRights',
      title: 'Data-rights requests and the answers to them',
      purpose:
          'To turn a family’s statutory request into visible work with a deadline, '
          'rather than a message nobody is accountable for answering.',
      basis: LawfulBasis.legalObligation,
      subjects: 'The requesting individual.',
      retention: 'Kept after fulfilment — the answer is the evidence.',
      guard: 'DataRightsDao and the supervisor desk queue.',
      readBy: {Permission.viewCommunityInsights},
      writeBy: {Permission.viewOwnFamilyOnly, Permission.viewAllHouseholds},
    ),
    ProcessingActivity(
      id: 'districtReads',
      title: 'What the district handed out',
      purpose:
          'To cover the half of the trail a handset cannot see: the device that '
          'downloaded a caseload is not the device that read a record, and a '
          'recovery restore moves thousands of rows at once.',
      basis: LawfulBasis.accountability,
      subjects: 'The account that pulled, and the scope it was served.',
      retention: 'District retention policy, which this build does not set.',
      guard: 'server/src/read_audit.js — the only writer.',
    ),
    ProcessingActivity(
      id: 'machinery',
      title: 'Synchronisation and operational state',
      purpose:
          'To get work done offline and admit it exactly once when a signal '
          'arrives.',
      basis: LawfulBasis.operation,
      subjects: 'No data subject — these rows describe the device.',
      retention: 'Until admitted, then cleared.',
      guard:
          'SyncService and the outbox, which is inside the encrypted database '
          'because it temporarily holds patient payloads.',
    ),
    ProcessingActivity(
      id: 'districtIngest',
      title: 'The district’s own admission log',
      purpose:
          'To keep the server’s receipt for what it accepted and refused, which is '
          'where a dispute about a lost change is settled.',
      basis: LawfulBasis.accountability,
      subjects: 'The account that sent the change.',
      retention: 'District retention policy.',
      guard: 'server/src/sync.js — not on the pull list, so it cannot spread.',
    ),
    ProcessingActivity(
      id: 'modelRecalibration',
      title: 'De-identified export for model recalibration',
      purpose:
          'To let the risk checks be retrained on real Northern Ghana data under a '
          'signed Kintampo HRC / Navrongo HDSS agreement, without the research '
          'dataset ever containing a name, a phone number, a community, a household '
          'id, a GPS point or a birthday.',
      basis: LawfulBasis.consent,
      subjects:
          'Children and mothers whose completed assessment contributed a model '
          'prediction. Re-identification is prevented by construction, not by '
          'redaction.',
      retention:
          'On the handset until the district officer exports the monthly batch and '
          'clears it in front of the worker. Revoking the salt stops collection at '
          'once.',
      guard:
          'RecalibrationStore.append, which is a no-op until the GHS-issued salt is '
          'provisioned — an unarmed device collects nothing — plus '
          'RecalibrationRecord, which holds only a salted SHA-256 person key, a '
          'month, an age band and numeric model inputs.',
      writeBy: {Permission.exportRecords},
      nonTableStorage:
          'A JSONL batch file in the app documents directory, and the linkage salt '
          'in secure storage. Not a SQLite table, and never on the sync whitelist.',
      specialPersonalData: true,
    ),
  ];

  static List<StoredData> tablesFor(String activityId) => [
    for (final d in data)
      if (d.activity == activityId) d,
  ];

  static ProcessingActivity? activityById(String id) {
    for (final a in activities) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// The tables that leave a handset at all.
  static List<String> get whitelistedForSync => [
    for (final d in data)
      if (d.travelsToDistrict) d.table,
  ];

  /// The tables the district will hand to a *different* handset on pull. Stated in
  /// the register so the absence of the accountability spine here is a documented
  /// decision rather than an omission somebody has to notice.
  static const List<String> pulledOntoOtherDevices = [
    'households',
    'persons',
    'visits',
    'assessments',
    'referrals',
    'care_requests',
  ];

  /// Tables that must never appear on the pull list.
  static const List<String> mustNotSpread = [
    'user_verifiers',
    'refresh_tokens',
    'consent_events',
    'access_ledger',
    'ledger_anchors',
    'data_rights_requests',
    'server_read_log',
    'sync_log',
  ];

  /// The safeguards, where they live, and what proves them. Anything here that
  /// claims to be in place names a file CI can open.
  static const List<SecurityControl> controls = [
    SecurityControl(
      id: 'at-rest-encryption',
      problem:
          'A handset left in a taxi, or sold on, carries every family in a CHPS '
          'zone on its storage.',
      answer:
          'The whole database is a SQLCipher file with a per-installation 256-bit '
          'key, read back from secure storage before it is used: an install '
          'refuses to encrypt with a key it could not retrieve, because that is '
          'how records get destroyed by well-meaning software.',
      maturity: ControlMaturity.liveWithBoundary,
      frameworks: [
        'OWASP MASVS-STORAGE-1 (sensitive data at rest)',
        'HIPAA 45 CFR 164.312(a)(2)(iv) encryption',
        'Act 843 s.26 — security of processed data',
      ],
      implementations: [
        'lib/data/local/db_engine_io.dart',
        'lib/data/local/database_secret.dart',
        'lib/data/local/app_database.dart',
      ],
      proofTests: ['test/encryption_posture_test.dart'],
      boundary:
          'Web and desktop builds have no SQLCipher engine, so the posture card '
          'says "not encrypted at rest" on those platforms instead of the app '
          'claiming protection it does not have.',
    ),
    SecurityControl(
      id: 'conversion-of-existing-data',
      problem:
          'Installs that existed before encryption keep their plaintext file, and '
          'the honest word for that is a breach still sitting on disk.',
      answer:
          'A copy-verify-swap migration: the plaintext is copied into an encrypted '
          'file at a side path, every table is counted on both sides, and only a '
          'match renames over the original. A refusal or a mismatch leaves the '
          'original untouched with its rows intact.',
      maturity: ControlMaturity.live,
      frameworks: ['OWASP MASVS-STORAGE-1', 'Act 843 s.26'],
      implementations: ['lib/data/local/database_conversion.dart'],
      proofTests: ['test/database_conversion_test.dart'],
    ),
    SecurityControl(
      id: 'secure-delete',
      problem:
          'SQLite leaves deleted rows and freed pages readable in the file until '
          'they are overwritten, so "the record was deleted" is a claim about '
          'bytes, not a fact.',
      answer:
          '`PRAGMA secure_delete = ON` at every open, on every engine, read with '
          'rawQuery because the pragma returns a row and the Android engine '
          'rejects row-returning statements through execute.',
      maturity: ControlMaturity.liveWithBoundary,
      frameworks: [
        'OWASP MASVS-STORAGE-2 (data must not be inadvertently exposed)',
        'HIPAA 45 CFR 164.310(d)(2)(i) disposal',
      ],
      implementations: ['lib/data/local/app_database.dart'],
      proofTests: ['test/hardening_test.dart'],
      boundary:
          'It overwrites within the database file. It cannot reach blocks the '
          'filesystem has already relocated, and it does nothing about blocks that '
          'were freed before this build — which is why the conversion exists.',
    ),
    SecurityControl(
      id: 'transport-security',
      problem:
          'A health record sent over plain HTTP, or to a server a synthetic '
          'credential points at, leaves the compound permanently.',
      answer:
          'One rule enforced at the single HTTP door: https required, with a '
          'loopback exception that must be switched on deliberately by a test or a '
          'developer build. Android additionally refuses cleartext in its '
          'platform configuration.',
      maturity: ControlMaturity.liveWithBoundary,
      frameworks: [
        'OWASP MASVS-NETWORK-1 (data in transit)',
        'HIPAA 45 CFR 164.312(e)(1) transmission security',
      ],
      implementations: [
        'lib/data/sync/transport_policy.dart',
        'lib/data/sync/http_client.dart',
        'android/app/src/main/res/xml/network_security_config.xml',
        'android/app/src/main/AndroidManifest.xml',
      ],
      proofTests: ['test/transport_policy_test.dart'],
      boundary:
          'The manifest only governs Android. The code rule is what protects the '
          'web, iOS and desktop builds, which is why the check lives in the client '
          'rather than only in configuration.',
    ),
    SecurityControl(
      id: 'credential-separation',
      problem:
          'A PIN database sitting beside the records it unlocks turns one leaked '
          'file into both a key and a vault.',
      answer:
          'The device holds a stretched local verifier; the cloud authenticates '
          'against a domain-separated derivation of it, stored in its own table '
          'and never in the synced user row, whose server-side copy has no PIN '
          'columns at all.',
      maturity: ControlMaturity.live,
      frameworks: [
        'OWASP MASVS-AUTH-1 / MASVS-CRYPTO-2 (key management)',
        'HIPAA 45 CFR 164.312(d) person or entity authentication',
      ],
      implementations: ['lib/data/local/user_dao.dart', 'server/src/auth.js'],
      proofTests: ['test/recovery_and_registration_test.dart'],
    ),
    SecurityControl(
      id: 'inactivity-lock',
      problem:
          'One Android phone is shared between a CHO, a nurse and a caregiver in a '
          'waiting area. A screen left on a bench is an open file on a family.',
      answer:
          'A watchdog per role: a field worker\'s session locks after an idle '
          'window and after the app has been backgrounded long enough, evaluated '
          'on resume rather than by timer because Android suspends Dart timers.',
      maturity: ControlMaturity.liveWithBoundary,
      frameworks: [
        'OWASP MASVS-AUTH-1',
        'HIPAA 45 CFR 164.312(a)(2)(iii)',
        'Act 843 s.26',
      ],
      implementations: [
        'lib/core/auth/idle_lock.dart',
        'lib/app/session_guard.dart',
        'lib/core/auth/session.dart',
      ],
      proofTests: ['test/idle_lock_test.dart'],
      boundary:
          'A caregiver\'s own handset is deliberately not locked on idle: the '
          'person holding it is the data subject, and a lock that stops a mother '
          'reaching infant-feeding advice at 3am is a worse outcome than the risk '
          'it prevents.',
    ),
    SecurityControl(
      id: 'screen-capture',
      problem:
          'A record on screen is a record in somebody\'s camera roll, a screenshot '
          'in a chat, and a thumbnail in the recent-apps switcher.',
      answer:
          'FLAG_SECURE is set on the activity in every build that is not '
          'debuggable, so capture is refused by the platform rather than asked '
          'nicely of the user.',
      maturity: ControlMaturity.liveWithBoundary,
      frameworks: ['OWASP MASVS-STORAGE-2', 'OWASP MASVS-PRIVACY'],
      implementations: [
        'android/app/src/main/kotlin/gh/carebridge/carebridge_ai/MainActivity.kt',
      ],
      boundary:
          'Android only, and it stops the operating system, not a second phone '
          'photographing the screen. Debug builds leave capture working so the '
          'screenshot is still possible when the app is being reviewed.',
    ),
    SecurityControl(
      id: 'access-enforcement',
      problem:
          'A role list on a screen proves that a widget was hidden. It does not '
          'prove the data was never read by an account that should not have seen '
          'it.',
      answer:
          'Every read goes through a policy decision point that returns a basis — '
          'care relationship, consent, emergency, official authority — and every '
          'repository method asks it before it touches a DAO. The decision, not '
          'the button, is the control.',
      maturity: ControlMaturity.live,
      frameworks: [
        'OWASP MASVS-AUTH-1',
        'HIPAA 45 CFR 164.312(a)(1) access control',
        'GDPR Art 25 (protection by design)',
      ],
      implementations: ['lib/data/repositories/record_access.dart'],
      proofTests: ['test/accountability_test.dart', 'test/rbac_test.dart'],
    ),
    SecurityControl(
      id: 'sensitive-record-class',
      problem:
          'A worker with a legitimate caseload is still a worker with a caseload: '
          'for a record carrying HIV status, or a mother\'s self-harm answer, being '
          'entitled to look is not the same as needing to.',
      answer:
          'A protection class on the person row. A marked record opens without a '
          'reason only for the worker responsible for it; anyone else must state '
          'why, and the stated reason is written into the trail the family can '
          'read.',
      maturity: ControlMaturity.live,
      frameworks: [
        'Act 843 s.37 (special personal data)',
        'HIPAA 45 CFR 164.312(b) audit controls',
        'GDPR Art 9 (data revealing health or beliefs)',
      ],
      implementations: [
        'lib/domain/entities/core.dart',
        'lib/data/local/app_database.dart',
        'lib/presentation/fhw/household_screen.dart',
      ],
      proofTests: ['test/hardening_test.dart'],
    ),
    SecurityControl(
      id: 'break-glass',
      problem:
          'A refusal that cannot be overridden is a refusal that gets worked '
          'around with somebody else\'s login — and in a convulsing child, the '
          'answer must not be a argument.',
      answer:
          'Care is never blocked by a record. Where the policy would refuse, the '
          'screen asks for a reason in words, grants it for the length of the '
          'sitting, and files the reason as the basis. Refusals are recorded too, '
          'so the trail shows the attempt as well as the access.',
      maturity: ControlMaturity.live,
      frameworks: ['HIPAA 45 CFR 164.312(b)', 'GDPR Art 32(p)'],
      implementations: ['lib/data/repositories/record_access.dart'],
      proofTests: ['test/hardening_test.dart'],
      boundary:
          'A reason is a deterrent and a record, not a verification. Nothing here '
          'can prove a stated reason was true; the supervision queue is where a '
          'human decides whether it looked plausible.',
    ),
    SecurityControl(
      id: 'tamper-evident-trail',
      problem:
          'An audit log that the account it describes can edit is a story told '
          'afterwards by the person with the least to lose.',
      answer:
          'Each entry carries the hash of the one before it, keyed with an HMAC '
          'secret held in secure storage and never transmitted. The DAOs expose no '
          'update and no delete, and the trail is never cascaded from a patient '
          'row.',
      maturity: ControlMaturity.live,
      frameworks: [
        'HIPAA 45 CFR 164.312(c)(1) integrity',
        'HIPAA 45 CFR 164.308(a)(1)(ii)(D) system activity review',
      ],
      implementations: [
        'lib/domain/compliance.dart',
        'lib/data/local/compliance_dao.dart',
      ],
      proofTests: ['test/accountability_test.dart'],
      boundary:
          'Verification of a chain an adversary controlled end to end is not '
          'possible from the device alone — which is what the anchors are for.',
    ),
    SecurityControl(
      id: 'chain-anchoring',
      problem:
          'A device that rewrites its own history can also re-sign it, and the '
          'forgery is invisible from inside the chain.',
      answer:
          'Every tenth entry, the device commits its chain position to the '
          'district. The rows are append-only by database trigger, so the server '
          'cannot be talked into changing them, and a comparison finds an entry '
          'whose hash no longer matches or a history that got shorter.',
      maturity: ControlMaturity.liveWithBoundary,
      frameworks: [
        'HIPAA 45 CFR 164.312(c)(1)',
        'GDPR Art 5(2) accountability',
      ],
      implementations: [
        'lib/data/local/compliance_dao.dart',
        'server/src/anchors.js',
        'server/migrations/009_hardening.sql',
      ],
      boundary:
          'The device sends its own anchors, so an anchor defeats rewriting '
          'history after it was admitted and does not defeat a device that lied '
          'from the first entry. Recorded in the migration and said on the desk.',
    ),
    SecurityControl(
      id: 'read-audit-at-the-district',
      problem:
          'A device-side trail records what was read on that handset. It cannot '
          'see the day a caseload was downloaded, or a recovery that moved every '
          'row in a district onto a new phone.',
      answer:
          'The server writes what it handed out — scope, counts, watermark — into '
          'a table no client may write to, because a read log a device can edit is '
          'a read log that can be emptied.',
      maturity: ControlMaturity.live,
      frameworks: ['HIPAA 45 CFR 164.312(b)', 'GDPR Art 30'],
      implementations: [
        'server/src/read_audit.js',
        'server/src/pull.js',
        'server/src/recovery.js',
      ],
      boundary:
          'It records volumes and scope, not individual row ids: a pull page of '
          'five hundred records does not become five hundred log rows on a '
          'connectivity-limited server.',
    ),
    SecurityControl(
      id: 'pattern-monitoring',
      problem:
          'One flagged read is a story about one worker. Forty flagged reads across '
          'forty unrelated families is a story about a habit, and no single entry '
          'in the trail shows it.',
      answer:
          'Two aggregate questions asked of the trail: who opened an unusual number '
          'of unrelated families in a day, and which protected record was opened by '
          'several workers. Reported as counts on the supervision desk, phrased as '
          'shapes worth a conversation rather than as accusations.',
      maturity: ControlMaturity.live,
      frameworks: [
        'HIPAA 45 CFR 164.308(a)(1)(ii)(D)',
        'GDPR Art 5(2) accountability',
      ],
      implementations: ['lib/data/local/compliance_dao.dart'],
      proofTests: ['test/hardening_test.dart'],
      boundary:
          'Both detectors have ordinary explanations — a shared caseload, a campaign '
          'day, a family that moved. The count is the prompt; the decision belongs to '
          'the supervisor reading it.',
    ),
    SecurityControl(
      id: 'right-to-erase',
      problem:
          'A family asks for their record to be deleted, and the software has to '
          'answer with something other than a checkbox.',
      answer:
          'The request is honoured by erasing every direct identifier — name, phone, '
          'NHIS number — from the register, keeping the clinical history without '
          'names, writing the act itself into the access trail, and closing the '
          'request only when those have happened. A request that cannot be honoured '
          'throws a refusal that says what must happen first.',
      maturity: ControlMaturity.liveWithBoundary,
      frameworks: ['GDPR Art 17 erasure', 'Act 843 — correction and deletion'],
      implementations: ['lib/data/repositories/care_repository.dart'],
      proofTests: ['test/hardening_test.dart'],
      boundary:
          'Statutory retention periods for health records are not this software to '
          'decide, so clinical rows are kept de-identified rather than destroyed, and '
          'the screen says so to the family in those words.',
    ),
    SecurityControl(
      id: 'consent-as-history',
      problem:
          'If withdrawal overwrites the consent row, the record no longer shows that '
          'the care given in between was authorised — and the family looks like they '
          'were treated unlawfully.',
      answer:
          'A consent decision is its own append-only row: scope, decision, which '
          'version of the notice was read out, the language, and an optional voice '
          'artefact for a family who cannot read.',
      maturity: ControlMaturity.live,
      frameworks: ['Act 843 s.26', 'GDPR Art 7'],
      implementations: [
        'lib/domain/compliance.dart',
        'lib/data/local/compliance_dao.dart',
      ],
      proofTests: ['test/accountability_test.dart'],
    ),
    SecurityControl(
      id: 'rights-with-a-deadline',
      problem:
          'A request that reaches only the handset it was typed on is a request '
          'nobody is accountable for answering, and a lost phone is a lost '
          'obligation.',
      answer:
          'The request and its answer are queued out of the device in the same '
          'transaction that records them, the desk counts the days against the same '
          'constant the notice promised, and an overdue item is marked late in words '
          'as well as in colour.',
      maturity: ControlMaturity.liveWithBoundary,
      frameworks: ['Act 843 — data subject rights', 'GDPR Art 12(3)'],
      implementations: [
        'lib/data/local/compliance_dao.dart',
        'server/migrations/008_data_rights_requests.sql',
      ],
      proofTests: ['test/accountability_test.dart'],
      boundary:
          'There is no supervisory role in this build, so the queue a worker sees is '
          'this device\'s, not the district\'s. The desk states that limit on screen '
          'rather than implying coverage it does not have.',
    ),
    SecurityControl(
      id: 'sync-whitelist',
      problem:
          'A client names the table and columns it wants written. Trusting that is '
          'an invitation for a compromised handset to rewrite the audit log or add a '
          'column to a health record.',
      answer:
          'Every writable table and column is declared in one file and anything not '
          'on the list is rejected, with identifiers backtick-quoted and values '
          'parameterised. A malicious client can write only what the app itself '
          'writes.',
      maturity: ControlMaturity.live,
      frameworks: ['OWASP MASVS-PLATFORM', 'HIPAA 45 CFR 164.312(c)(1)'],
      implementations: [
        'server/src/tables.js',
        'server/src/db.js',
        'server/src/sync.js',
      ],
      proofTests: ['test/sync_no_server_test.dart'],
    ),
    SecurityControl(
      id: 'minimisation-at-the-edge',
      problem:
          'Syncing everything to everybody means a family\'s HIV status exists on '
          'every handset in the region, each one a copy that can be lost.',
      answer:
          'Push and pull are separate lists. The consent record, the access trail, '
          'the anchors and the rights queue go to the district and never come back '
          'down onto another handset; the server\'s own logs are not on the whitelist '
          'at all. The register reconciles these lists against the code in CI, so an '
          'undocumented widening of the pull stream fails the build.',
      maturity: ControlMaturity.live,
      frameworks: ['GDPR Art 5(1)(c) minimisation', 'Act 843 s.26'],
      implementations: ['server/src/pull.js', 'server/src/tables.js'],
      proofTests: ['test/governance_test.dart', 'test/pull_service_test.dart'],
    ),
    SecurityControl(
      id: 'no-telemetry',
      problem:
          'Analytics is how a health app quietly becomes a data broker: a crash '
          'report carrying a mother\'s name, an event stream describing which '
          'families have epilepsy.',
      answer:
          'No analytics, crash-reporting or advertising dependency is permitted in '
          'the manifest, and CI fails if one appears. The only outbound traffic is '
          'to the district the account is configured for.',
      maturity: ControlMaturity.live,
      frameworks: ['GDPR Art 25', 'OWASP MASVS-PRIVACY'],
      implementations: ['pubspec.yaml', 'lib/data/sync/transport_policy.dart'],
      proofTests: ['test/governance_test.dart'],
    ),
    SecurityControl(
      id: 'posture-said-out-loud',
      problem:
          'The most common compliance failure in software is a shield icon that '
          'claims encryption the build does not have.',
      answer:
          'The security posture is computed at runtime from the engine that '
          'actually opened the file, and printed on the profile tab and the '
          'supervision desk with its reason. There is no constant in the app that '
          'says "secure".',
      maturity: ControlMaturity.live,
      frameworks: ['GDPR Art 30', 'OWASP MASVS-STORAGE-1'],
      implementations: [
        'lib/data/local/app_database.dart',
        'lib/presentation/fhw/profile_tab.dart',
      ],
      proofTests: [
        'test/encryption_posture_test.dart',
        'test/hardening_test.dart',
      ],
    ),
    SecurityControl(
      id: 'research-export-minimisation',
      problem:
          'An app that improves its models needs real data, and the fastest route '
          'is an export of the records. That route turns a health worker into a '
          'data collector without a receipt.',
      answer:
          'The export carries no direct identifier at all — a salted SHA-256 for '
          'linkage, district instead of community, month instead of date, age band '
          'instead of birthday, and only the numeric inputs the model consumed. The '
          'device is armed with a salt GHS issues and never ships with the app, an '
          'unarmed device collects nothing, and the batch leaves the handset only by '
          'a handover the worker performs and can see the count of.',
      maturity: ControlMaturity.live,
      frameworks: [
        'GDPR Art 5(1)(e) pseudonymisation',
        'GDPR Art 89 (research processing)',
        'Act 843 s.37',
      ],
      implementations: [
        'lib/core/ml/recalibration_export.dart',
        'lib/core/ml/recalibration_store.dart',
      ],
      proofTests: [
        'test/recalibration_export_test.dart',
        'test/recalibration_store_test.dart',
      ],
      boundary:
          'Linkage is the residual risk: whoever holds the salt can join two '
          'batches of the same child. The salt stays with GHS, which is why the app '
          'cannot do that join and why revoking it stops collection immediately.',
    ),
    SecurityControl(
      id: 'cascade-safe-parent-writes',
      problem:
          'A record can be destroyed by an edit. `INSERT OR REPLACE` deletes the '
          'conflicting row before re-inserting it, and the register turns foreign '
          'keys on deliberately, so that implicit delete cascades: correcting a '
          "household's name would delete its members, and with them the growth "
          'curves, the assessments and the referrals. No error was raised and '
          'nothing was written to the trail.',
      answer:
          'Every write of a row that other rows cascade from goes through '
          'upsertWithoutCascade — look for the row, update it, insert only if '
          'absent — so no deletion is on the path. CI reads the DDL for the '
          'cascade parents and fails if any of them is written with '
          'ConflictAlgorithm.replace again, on any table, in any file.',
      maturity: ControlMaturity.live,
      frameworks: [
        'HIPAA 45 CFR 164.312(c)(1) integrity',
        'Act 843 s.26 — accuracy of processed data',
        'OWASP MASVS-RESILIENCE (a failure that cannot be seen cannot be fixed)',
      ],
      implementations: [
        'lib/data/local/upsert.dart',
        'lib/data/local/household_dao.dart',
        'lib/data/local/visit_dao.dart',
        'lib/data/sync/recovery_service.dart',
      ],
      proofTests: ['test/cascade_safety_test.dart'],
      boundary:
          'It protects against this specific mechanism. Deleting a row on purpose '
          'still cascades — which is correct, and is why the deletion paths name '
          'their deletes.',
    ),
    SecurityControl(
      id: 'retention-periods',
      problem:
          'Someone must decide how long a maternal record is kept, and when it stops '
          'being needed.',
      answer:
          'Not this software. Ghana Health Service records policy sets it, the '
          'district data protection supervisor applies it, and this build\'s job is to '
          'make the row findable and erasable when they do.',
      maturity: ControlMaturity.notOurs,
      frameworks: ['Act 843 s.26', 'GDPR Art 5(1)(e)'],
      implementations: ['lib/domain/governance.dart'],
      owner: ControlOwnership.controller,
    ),
    SecurityControl(
      id: 'controller-registration',
      problem:
          'Processing personal data without registering with the Data Protection '
          'Commission is an offence in itself, whatever the software does.',
      answer:
          'A filing the District Directorate makes as data controller, with this '
          'register as the input it has to describe. The Secretariat\'s enforcement is '
          'outside this repository.',
      maturity: ControlMaturity.notOurs,
      frameworks: ['Act 843 s.24 (registration of data controllers)'],
      implementations: ['lib/domain/governance.dart'],
      owner: ControlOwnership.controller,
    ),
    SecurityControl(
      id: 'breach-notification',
      problem:
          'A lost handset is a reportable event, and the clock starts when it is '
          'noticed, not when it is investigated.',
      answer:
          'A process, not a feature. What the software contributes is the trail and '
          'the anchors, so the report can say which records that device had opened '
          'rather than guess.',
      maturity: ControlMaturity.notOurs,
      frameworks: ['Act 843 — disclosure', 'GDPR Art 33'],
      implementations: ['lib/data/local/compliance_dao.dart'],
      owner: ControlOwnership.both,
    ),
    SecurityControl(
      id: 'impact-assessment',
      problem:
          'Processing special personal data at scale is exactly the case in which a '
          'data protection impact assessment is required before the deployment, not '
          'after the pilot.',
      answer:
          'Owned by the controller. This register, the matrix and the control map are '
          'written to be the evidence base an assessment cites, which is why the '
          'boundaries are recorded rather than smoothed over.',
      maturity: ControlMaturity.notOurs,
      frameworks: ['GDPR Art 35'],
      implementations: ['lib/domain/governance.dart'],
      owner: ControlOwnership.controller,
    ),
  ];
  static List<AccessMatrixRow> accessMatrix(UserRole role) {
    final granted = Permission.forRole(role);
    return [
      for (final a in activities)
        if (a.hasAppVisibleRules)
          AccessMatrixRow(
            activity: a,
            readable: granted.intersection(a.readBy).isNotEmpty,
            writable: granted.intersection(a.writeBy).isNotEmpty,
            why: a.guard,
          ),
    ];
  }
}

/// One line of the matrix, as it applies to one role.
class AccessMatrixRow {
  const AccessMatrixRow({
    required this.activity,
    required this.readable,
    required this.writable,
    required this.why,
  });

  final ProcessingActivity activity;
  final bool readable;
  final bool writable;
  final String why;

  String get verdict {
    // Four states, not two. An activity a role can put rows into but never read
    // back is a different thing from one it can do both, and collapsing them would
    // overstate what the role sees.
    if (writable && readable) return 'Read and write';
    if (writable) return 'Write only';
    if (readable) return 'Read only';
    return 'Not reachable';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The document, as a build artefact
// ─────────────────────────────────────────────────────────────────────────────

/// Renders the register into the markdown a district reads.
///
/// `docs/GOVERNANCE.md` is the output of [render], and `test/governance_test.dart`
/// fails when the checked-in file differs from a fresh render. So the document
/// cannot be edited into a lie: to change what it says you change the register, and
/// to change the register you change the code the register describes. The test also
/// writes the file, on request only, because this register reaches into domain code
/// that needs the Flutter VM, so no plain `dart run` script can generate it.
///
/// Deliberately absent: a generation date. A timestamp would make the file differ
/// from itself every day, which turns a check into noise and the check back into a
/// document nobody reads.
abstract final class GovernanceDocs {
  /// The provenance line at the top of the rendered file. Named here so the test
  /// compares against the same string the generator writes.
  static const provenance =
      '<!-- Generated from lib/domain/governance.dart. Do not hand-edit: '
      'test/governance_test.dart fails if this file stops matching the register. '
      'Regenerate with WRITE_GOVERNANCE_DOC=1 flutter test '
      'test/governance_test.dart -->';

  static String _backticks(Iterable<String> values) =>
      values.map((v) => '`$v`').join(', ');

  static String render() {
    final b = StringBuffer()
      ..writeln(provenance)
      ..writeln()
      ..writeln('# Record of processing, access matrix and control map')
      ..writeln()
      ..writeln(
        "CareBridge AI — community maternal and newborn care for Ghana CHPS "
        'compounds. This is the privacy register in the form Act 843 and Article 30 '
        'both ask for: what is processed, on what basis, for how long, who may see '
        'it, and which safeguard covers it.',
      )
      ..writeln()
      ..writeln(
        'It is generated from code and reconciled against four artefacts that are '
        'not opinions — the local schema, `server/schema.sql`, the sync whitelist '
        'in `server/src/tables.js` and the pull list in `server/src/pull.js`. A '
        'table with no declared purpose fails the build, and so does a purpose whose '
        'table has disappeared.',
      )
      ..writeln()
      ..writeln('## 1. Processing activities')
      ..writeln();

    for (final a in GovernanceRegister.activities) {
      final rows = GovernanceRegister.tablesFor(a.id);
      b
        ..writeln('### ${a.title}')
        ..writeln();
      final tags = <String>['`${a.id}`'];
      if (a.specialPersonalData) tags.add('**special personal data**');
      b.writeln(tags.join(' · '));
      b.writeln();
      if (rows.isNotEmpty) {
        b.writeln('Tables: ${_backticks(rows.map((r) => r.table))}.');
        b.writeln();
      }
      if (a.nonTableStorage.isNotEmpty) {
        b.writeln('- **Held outside SQLite** — ${a.nonTableStorage}');
      }
      b
        ..writeln('- **Purpose** — ${a.purpose}')
        ..writeln('- **Lawful basis** — ${a.basis.label}')
        ..writeln('- **Whose data** — ${a.subjects}')
        ..writeln('- **Retention** — ${a.retention}')
        ..writeln('- **Enforced by** — ${a.guard}');
      // The turnaround a family was promised is printed from the constant the
      // notice itself uses, so this document cannot quote a different number from
      // the one the queue counts against.
      if (a.id == 'dataRights') {
        b.writeln('- **Answered within** — ${CareNotice.serviceDeadlineLabel}');
      }
      if (a.readBy.isNotEmpty) {
        b.writeln(
          '- **Readable with** — ${a.readBy.map((p) => p.name).join(', ')}',
        );
      }
      if (a.writeBy.isNotEmpty) {
        b.writeln(
          '- **Writable with** — ${a.writeBy.map((p) => p.name).join(', ')}',
        );
      }
      b.writeln();
    }

    b
      ..writeln('## 2. Where the data is allowed to go')
      ..writeln()
      ..writeln(
        'Scope is the difference between a register and a leak. Push and pull are '
        'separate decisions here, and the accountability evidence is deliberately '
        'one-way.',
      )
      ..writeln();

    for (final scope in StorageScope.values) {
      final rows = [
        for (final d in GovernanceRegister.data)
          if (d.scope == scope) d,
      ];
      b.writeln('### ${scope.label}');
      b.writeln();
      if (rows.isEmpty) {
        b.writeln('_None._');
      } else {
        for (final d in rows) {
          b.writeln('- `${d.table}` — ${d.contains}');
        }
      }
      b.writeln();
    }

    b
      ..writeln(
        'Returned to a *different* handset on pull: '
        '${_backticks(GovernanceRegister.pulledOntoOtherDevices)}.',
      )
      ..writeln()
      ..writeln(
        'Never allowed onto the pull list, because a consent history, the trail of '
        'who read a family, an open rights request and the district\'s own logs are '
        'no business of any other handset: '
        '${_backticks(GovernanceRegister.mustNotSpread)}.',
      )
      ..writeln()
      ..writeln('## 3. Access matrix by role')
      ..writeln()
      ..writeln(
        'Generated by asking the capability set the app actually enforces '
        '(`Permission.forRole`), so this table cannot drift from the code that hides '
        'a button or refuses a query. The verdict is a ceiling: the caseload scope '
        'and the protection class narrow it further, per row, at the enforcement '
        'point named in section 1.',
      )
      ..writeln();

    for (final role in UserRole.values) {
      b.writeln('### ${role.label}');
      b.writeln();
      for (final row in GovernanceRegister.accessMatrix(role)) {
        b.writeln('- **${row.activity.title}** — ${row.verdict}');
      }
      b.writeln();
    }

    b
      ..writeln('## 4. Control map')
      ..writeln()
      ..writeln(
        'Each safeguard names the failure it prevents, the files that implement it '
        'and the test that proves it. What it does **not** cover is printed in the '
        'same entry, because a control map that only lists successes is marketing.',
      )
      ..writeln();

    for (final c in GovernanceRegister.controls) {
      b
        ..writeln('### `${c.id}`')
        ..writeln()
        ..writeln('${c.maturity.label} — owned by ${_owner(c.owner)}')
        ..writeln()
        ..writeln('- **Failure prevented** — ${c.problem}')
        ..writeln('- **What the software does** — ${c.answer}')
        ..writeln('- **Cited against** — ${c.frameworks.join('; ')}')
        ..writeln('- **In** — ${_backticks(c.implementations)}');
      if (c.proofTests.isNotEmpty) {
        b.writeln('- **Proved by** — ${_backticks(c.proofTests)}');
      }
      if (c.boundary.isNotEmpty) {
        b.writeln('- **Does not cover** — ${c.boundary}');
      }
      b.writeln();
    }

    b
      ..writeln('## 5. What this register does not claim')
      ..writeln()
      ..writeln(
        'It does not say the deployment is compliant. Compliance is a state a data '
        'controller achieves with an organisation around the software: registering '
        'with the Commission, setting retention periods, training the workers who '
        'hold the handsets, reporting a breach. Those rows appear above with an '
        'owner and the words "not this software\'s to implement", because quietly '
        'dropping them is the one edit that would make this document false.',
      )
      ..writeln()
      ..writeln(
        '${GovernanceRegister.data.length} tables are registered, of which '
        '${GovernanceRegister.whitelistedForSync.length} may leave a handset and '
        '${GovernanceRegister.pulledOntoOtherDevices.length} are handed to another '
        'one. Those two numbers are the whole minimisation argument, and they are '
        'computed rather than asserted.',
      )
      ..writeln();
    return b.toString();
  }

  static String _owner(ControlOwnership o) => switch (o) {
    ControlOwnership.appTeam => 'this software',
    ControlOwnership.controller => 'the deploying health authority',
    ControlOwnership.both =>
      'the deployment, with the software providing the evidence',
  };
}
