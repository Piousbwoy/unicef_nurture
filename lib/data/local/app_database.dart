/// The offline database — the foundation the whole app stands on.
///
/// The first hackathon constraint is *works offline in low-connectivity
/// settings*, and in a CHPS compound in Karaga that is not a nice-to-have: the
/// network is absent for most of the working day, and a form that fails to save
/// is a child who was never assessed. So the design here is deliberate:
///
/// **SQLite is the source of truth, not a cache.** Nothing in the app ever waits
/// for a server. Every write commits locally and immediately, and an outbox row
/// is queued in the *same transaction*. A record cannot exist without its sync
/// intent, and sync intent cannot exist without a record.
///
/// **Hand-written SQL, no code generation.** Drift would be prettier. It would
/// also put `build_runner` between this team and a working build, and a codegen
/// failure at 2am before a pitch is not a risk worth taking for syntactic
/// sugar. The schema is 14 tables; it fits in one file a judge can read.
///
/// **Soft deletes and append-only clinical history.** Growth measurements and
/// assessments are never updated in place. A CHO who mis-measures adds a new
/// reading; the trajectory engine needs the series, and a clinical record that
/// can be silently rewritten is not a clinical record.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
// The analyzer flags this as redundant because sqflite_common_ffi re-exports the
// same symbols. It is not: importing the sqflite plugin is what registers the
// native database factory on Android and iOS. Remove it and the app opens no
// database on a real phone.
// ignore: unnecessary_import
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// Bumping this runs [AppDatabase._upgrade]. Every increment needs a matching
/// case, because a field device may be several versions behind.
const int kDatabaseVersion = 4;

const String kDatabaseName = 'carebridge.db';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  Database? _db;
  Completer<Database>? _opening;

  /// Set once at startup. On web the WASM-backed factory is used; on desktop
  /// (Windows / macOS / Linux) the FFI factory; on Android and iOS the native
  /// sqflite plugin is the default and needs no override.
  static bool _ffiInitialised = false;

  static void initialiseForPlatform() {
    if (_ffiInitialised) return;
    if (kIsWeb) {
      databaseFactory = databaseFactoryFfiWeb;
    } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    // On Android/iOS the sqflite plugin's native factory is already wired by
    // the import above — nothing to do.
    _ffiInitialised = true;
  }

  /// Kept for tests, which always run on a desktop host where FFI is the
  /// right choice regardless of the app's platform.
  static void initialiseForDesktopAndTests() {
    if (_ffiInitialised) return;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    _ffiInitialised = true;
  }

  /// Opens the database, or returns the already-open handle.
  ///
  /// Guarded by a [Completer] rather than a plain null check: several providers
  /// initialise in parallel on first launch, and two concurrent `openDatabase`
  /// calls on the same file is a real crash on Android.
  Future<Database> get database async {
    final existing = _db;
    if (existing != null && existing.isOpen) return existing;

    final inFlight = _opening;
    if (inFlight != null) return inFlight.future;

    final completer = Completer<Database>();
    _opening = completer;
    try {
      final db = await _open();
      _db = db;
      completer.complete(db);
      return db;
    } catch (e, st) {
      completer.completeError(e, st);
      _opening = null;
      rethrow;
    } finally {
      _opening = null;
    }
  }

  Future<Database> _open() async {
    final path = await _resolvePath();
    return openDatabase(
      path,
      version: kDatabaseVersion,
      onConfigure: (db) async {
        // Off by default in SQLite. Without this, orphaned children of a
        // deleted household would linger and quietly skew every zone count.
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async => _createAll(db),
      onUpgrade: _upgrade,
    );
  }

  Future<String> _resolvePath() async {
    // Web: the "path" is just a database name. The web factory (sqflite_common_ffi_web)
    // backs the database with the browser's IndexedDB, so data persists across
    // page reloads within the same browser origin. There is no flat file to open
    // with an external tool — inspect it via Chrome DevTools →
    // Application → IndexedDB.
    if (kIsWeb) return kDatabaseName;
    // All other platforms (Android, iOS, Windows, macOS, Linux) store the
    // database in the application documents directory so data survives restarts.
    // Previously desktop used Directory.systemTemp, which was a hackathon
    // shortcut that made the database ephemeral on Windows/macOS/Linux. That
    // has been removed: the app now behaves consistently across all platforms.
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, kDatabaseName);
  }

  /// For tests: an isolated in-memory database with the full schema.
  static Future<Database> openInMemory() async {
    initialiseForDesktopAndTests();
    // ignore: avoid_redundant_argument_values
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: kDatabaseVersion,
        onConfigure: (d) async => d.execute('PRAGMA foreign_keys = ON'),
        onCreate: (d, _) async => _createAll(d),
      ),
    );
    return db;
  }

  Future<void> close() async {
    final db = _db;
    _db = null;
    if (db != null && db.isOpen) await db.close();
  }

  /// Wipes every row but keeps the schema. Used by "reset this device" in
  /// settings so a fresh user can start without reinstalling.
  Future<void> clearAll() async {
    final db = await database;
    await db.transaction((txn) async {
      // Children before parents.
      for (final table in const [
        Tables.outbox,
        Tables.auditLog,
        Tables.scheduledContacts,
        Tables.milestoneChecks,
        Tables.homeChecks,
        Tables.barrierReports,
        Tables.referrals,
        Tables.assessments,
        Tables.visitParticipants,
        Tables.visits,
        Tables.growthMeasurements,
        Tables.birthRecords,
        Tables.maternalRecords,
        Tables.persons,
        Tables.households,
        Tables.users,
      ]) {
        await txn.delete(table);
      }
    });
  }

  Future<void> _upgrade(Database db, int from, int to) async {
    // Version 1 is the initial schema. Future versions add their statements
    // here, never editing an earlier case.
    if (from < 2) {
      // Version 2: the synthesized care plan joins the assessment so the audit
      // trail shows the decision that actually governed care. Nullable — rows
      // that predate the column simply have no stored plan.
      await db.execute(
        'ALTER TABLE ${Tables.assessments} ADD COLUMN care_plan_json TEXT',
      );
    }
    if (from < 3) {
      // Version 3: the caregiver's home checks. A new table, never an added
      // column on assessments — a family's report is a different kind of
      // evidence from a clinical assessment and must not share its rows.
      await db.execute(_homeChecksTable);
      await db.execute(
        'CREATE INDEX idx_home_checks_household ON ${Tables.homeChecks}'
        '(household_id, checked_at DESC)',
      );
      await db.execute(
        'CREATE INDEX idx_home_checks_person ON ${Tables.homeChecks}'
        '(person_id, checked_at DESC)',
      );
    }
    if (from < 4) {
      // Version 4: the family's milestone checks. Own table for the same
      // reason home checks have one — a mother's report of what her child
      // can do is screening evidence, not a clinical finding, and the two
      // must never share rows.
      await db.execute(_milestoneChecksTable);
      await db.execute(
        'CREATE INDEX idx_milestone_checks_household ON '
        '${Tables.milestoneChecks}(household_id, checked_at DESC)',
      );
      await db.execute(
        'CREATE INDEX idx_milestone_checks_person ON '
        '${Tables.milestoneChecks}(person_id, checked_at DESC)',
      );
    }
  }

  static Future<void> _createAll(DatabaseExecutor db) async {
    for (final statement in _schema) {
      await db.execute(statement);
    }
  }
}

/// Table names as constants, so a typo in a DAO is a compile error rather than
/// a runtime "no such table" on a health worker's phone.
abstract final class Tables {
  static const users = 'users';
  static const households = 'households';
  static const persons = 'persons';
  static const maternalRecords = 'maternal_records';
  static const birthRecords = 'birth_records';
  static const growthMeasurements = 'growth_measurements';
  static const visits = 'visits';
  static const visitParticipants = 'visit_participants';
  static const assessments = 'assessments';
  static const referrals = 'referrals';
  static const barrierReports = 'barrier_reports';
  static const homeChecks = 'home_checks';
  static const milestoneChecks = 'milestone_checks';
  static const scheduledContacts = 'scheduled_contacts';
  static const outbox = 'sync_outbox';
  static const auditLog = 'audit_log';
}

const List<String> _schema = [
  // --------------------------------------------------------------------------
  // Users. A CHPS compound often shares one Android phone between the CHO, the
  // community health nurse, and caregivers using the app in the waiting area,
  // so several accounts coexist on one device.
  // --------------------------------------------------------------------------
  '''
  CREATE TABLE ${Tables.users} (
    id                 TEXT PRIMARY KEY,
    full_name          TEXT NOT NULL,
    phone              TEXT NOT NULL,
    role               TEXT NOT NULL,
    region             TEXT NOT NULL,
    district           TEXT NOT NULL,
    community          TEXT NOT NULL,
    chps_zone          TEXT,
    facility_name      TEXT,
    staff_id           TEXT,
    preferred_language TEXT NOT NULL DEFAULT 'English',
    pin_hash           TEXT,
    pin_salt           TEXT,
    linked_household_id TEXT,
    created_at         TEXT NOT NULL
  )
  ''',
  // Phone is the login identifier, so it must be unique per device.
  'CREATE UNIQUE INDEX idx_users_phone ON ${Tables.users}(phone)',

  // --------------------------------------------------------------------------
  // Households. The unit a CHO actually walks to, and the unit that carries
  // shared risk: one flooded road, one empty granary, one absent
  // decision-maker affects everybody inside it.
  // --------------------------------------------------------------------------
  '''
  CREATE TABLE ${Tables.households} (
    id                          TEXT PRIMARY KEY,
    name                        TEXT NOT NULL,
    region                      TEXT NOT NULL,
    district                    TEXT NOT NULL,
    community                   TEXT NOT NULL,
    created_by                  TEXT NOT NULL,
    head_name                   TEXT,
    contact_phone               TEXT,
    latitude                    REAL,
    longitude                   REAL,
    family_size                 INTEGER,
    has_valid_nhis              INTEGER,
    walking_minutes_to_facility INTEGER,
    landmark                    TEXT,
    created_at                  TEXT NOT NULL,
    updated_at                  TEXT NOT NULL
  )
  ''',
  // The zone list query: every household in one community, newest first.
  'CREATE INDEX idx_households_community ON ${Tables.households}(region, district, community)',
  'CREATE INDEX idx_households_created_by ON ${Tables.households}(created_by)',

  // --------------------------------------------------------------------------
  // Persons. One flat table for women, newborns and under-fives, because the
  // roll call has to let a CHO tick off whoever is actually in front of them
  // without first deciding which sub-table they belong in.
  // --------------------------------------------------------------------------
  '''
  CREATE TABLE ${Tables.persons} (
    id               TEXT PRIMARY KEY,
    household_id     TEXT NOT NULL,
    full_name        TEXT NOT NULL,
    client_type      TEXT NOT NULL,
    sex              TEXT,
    date_of_birth    TEXT,
    age_years_approx INTEGER,
    phone            TEXT,
    mother_id        TEXT,
    is_dob_estimated INTEGER NOT NULL DEFAULT 0,
    nhis_number      TEXT,
    created_at       TEXT NOT NULL,
    updated_at       TEXT NOT NULL,
    is_active        INTEGER NOT NULL DEFAULT 1,
    FOREIGN KEY (household_id) REFERENCES ${Tables.households}(id) ON DELETE CASCADE,
    FOREIGN KEY (mother_id) REFERENCES ${Tables.persons}(id) ON DELETE SET NULL
  )
  ''',
  'CREATE INDEX idx_persons_household ON ${Tables.persons}(household_id, is_active)',
  // Pulls a mother's children in one query, which is what a multi-client visit
  // needs the moment she arrives with three of them.
  'CREATE INDEX idx_persons_mother ON ${Tables.persons}(mother_id)',
  'CREATE INDEX idx_persons_type ON ${Tables.persons}(client_type, is_active)',

  // --------------------------------------------------------------------------
  // Maternal record. One row per woman, mirroring the fields in Ghana's
  // Maternal Health Record Book so a CHO transcribes rather than translates.
  // --------------------------------------------------------------------------
  '''
  CREATE TABLE ${Tables.maternalRecords} (
    person_id              TEXT PRIMARY KEY,
    gravida                INTEGER,
    parity                 INTEGER,
    previous_losses        INTEGER,
    previous_caesarean     INTEGER,
    last_menstrual_period  TEXT,
    expected_delivery_date TEXT,
    anc_contacts_completed INTEGER NOT NULL DEFAULT 0,
    iptp_doses             INTEGER NOT NULL DEFAULT 0,
    td_doses               INTEGER NOT NULL DEFAULT 0,
    iron_folate_supplied   INTEGER NOT NULL DEFAULT 0,
    llin_supplied          INTEGER NOT NULL DEFAULT 0,
    haemoglobin            REAL,
    blood_group            TEXT,
    sickling_status        TEXT,
    hiv_tested             INTEGER NOT NULL DEFAULT 0,
    delivery_date          TEXT,
    delivery_place         TEXT,
    delivery_mode          TEXT,
    plurality              TEXT NOT NULL DEFAULT 'singleton',
    family_planning_method TEXT,
    updated_at             TEXT NOT NULL,
    FOREIGN KEY (person_id) REFERENCES ${Tables.persons}(id) ON DELETE CASCADE
  )
  ''',

  // --------------------------------------------------------------------------
  // Birth record. Fixed at birth, and it drives the young-infant risk model
  // for the first 59 days — birth weight and asphyxia are the two facts that
  // most predict whether this newborn survives the month.
  // --------------------------------------------------------------------------
  '''
  CREATE TABLE ${Tables.birthRecords} (
    person_id                 TEXT PRIMARY KEY,
    birth_weight_kg           REAL,
    gestation_weeks_at_birth  INTEGER,
    delivery_place            TEXT,
    delivery_mode             TEXT,
    plurality                 TEXT NOT NULL DEFAULT 'singleton',
    birth_order               INTEGER NOT NULL DEFAULT 1,
    resuscitation_needed      INTEGER,
    cord_care_given           INTEGER,
    vitamin_k_given           INTEGER,
    breastfed_within_one_hour INTEGER,
    updated_at                TEXT NOT NULL,
    FOREIGN KEY (person_id) REFERENCES ${Tables.persons}(id) ON DELETE CASCADE
  )
  ''',

  // --------------------------------------------------------------------------
  // Growth measurements. Append-only, and that is the whole point: the
  // trajectory engine needs the series. A child whose MUAC reads 13.8, 13.1,
  // 12.7 is marked "green, green, yellow" on paper and sent home twice.
  // --------------------------------------------------------------------------
  '''
  CREATE TABLE ${Tables.growthMeasurements} (
    id                   TEXT PRIMARY KEY,
    person_id            TEXT NOT NULL,
    taken_at             TEXT NOT NULL,
    muac_cm              REAL,
    weight_kg            REAL,
    height_cm            REAL,
    has_bilateral_oedema INTEGER NOT NULL DEFAULT 0,
    recorded_by          TEXT,
    FOREIGN KEY (person_id) REFERENCES ${Tables.persons}(id) ON DELETE CASCADE
  )
  ''',
  'CREATE INDEX idx_growth_person_date ON ${Tables.growthMeasurements}(person_id, taken_at DESC)',

  // --------------------------------------------------------------------------
  // Visits. One encounter can carry several assessments — a mother, her
  // newborn twins and a three-year-old, all in one sitting under a tree.
  // --------------------------------------------------------------------------
  '''
  CREATE TABLE ${Tables.visits} (
    id           TEXT PRIMARY KEY,
    household_id TEXT NOT NULL,
    conducted_by TEXT NOT NULL,
    started_at   TEXT NOT NULL,
    completed_at TEXT,
    reasons      TEXT NOT NULL DEFAULT '',
    latitude     REAL,
    longitude    REAL,
    notes        TEXT,
    sync_state   TEXT NOT NULL DEFAULT 'pending',
    FOREIGN KEY (household_id) REFERENCES ${Tables.households}(id) ON DELETE CASCADE
  )
  ''',
  'CREATE INDEX idx_visits_household ON ${Tables.visits}(household_id, started_at DESC)',
  'CREATE INDEX idx_visits_worker_date ON ${Tables.visits}(conducted_by, started_at DESC)',

  // --------------------------------------------------------------------------
  // Visit participants — the roll call. Recorded separately from assessments
  // because *who was present* is a fact worth keeping even when the assessment
  // is skipped: "the twin was not brought" is exactly the signal that finds a
  // child before it is a death.
  // --------------------------------------------------------------------------
  '''
  CREATE TABLE ${Tables.visitParticipants} (
    visit_id     TEXT NOT NULL,
    person_id    TEXT NOT NULL,
    was_present  INTEGER NOT NULL DEFAULT 1,
    absence_note TEXT,
    queue_order  INTEGER NOT NULL DEFAULT 0,
    assessed     INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (visit_id, person_id),
    FOREIGN KEY (visit_id) REFERENCES ${Tables.visits}(id) ON DELETE CASCADE,
    FOREIGN KEY (person_id) REFERENCES ${Tables.persons}(id) ON DELETE CASCADE
  )
  ''',

  // --------------------------------------------------------------------------
  // Assessments. Raw answers *and* the verdict are both stored, so a decision
  // can be re-derived later and an improved model can be back-tested against
  // real history rather than guesses.
  // --------------------------------------------------------------------------
  '''
  CREATE TABLE ${Tables.assessments} (
    id                TEXT PRIMARY KEY,
    visit_id          TEXT NOT NULL,
    person_id         TEXT NOT NULL,
    client_type       TEXT NOT NULL,
    performed_by      TEXT NOT NULL,
    performed_at      TEXT NOT NULL,
    inputs_json       TEXT NOT NULL,
    result_json       TEXT NOT NULL,
    care_plan_json    TEXT,
    overridden_triage TEXT,
    override_reason   TEXT,
    override_by       TEXT,
    sync_state        TEXT NOT NULL DEFAULT 'pending',
    FOREIGN KEY (visit_id) REFERENCES ${Tables.visits}(id) ON DELETE CASCADE,
    FOREIGN KEY (person_id) REFERENCES ${Tables.persons}(id) ON DELETE CASCADE
  )
  ''',
  'CREATE INDEX idx_assessments_person ON ${Tables.assessments}(person_id, performed_at DESC)',
  'CREATE INDEX idx_assessments_visit ON ${Tables.assessments}(visit_id)',
  // Clinician overrides are the honest training signal for the risk model, so
  // they get their own index rather than being buried in a scan.
  'CREATE INDEX idx_assessments_overrides ON ${Tables.assessments}(overridden_triage)',

  // --------------------------------------------------------------------------
  // Referrals. The last-mile loop. A referral with no confirmed arrival is the
  // commonest place a child is lost, so status is a first-class column and
  // escalation is queryable, not something a CHO must remember.
  // --------------------------------------------------------------------------
  '''
  CREATE TABLE ${Tables.referrals} (
    id                   TEXT PRIMARY KEY,
    reference_code       TEXT NOT NULL,
    person_id            TEXT NOT NULL,
    assessment_id        TEXT NOT NULL,
    facility_name        TEXT NOT NULL,
    reason               TEXT NOT NULL,
    urgency              TEXT NOT NULL,
    issued_by            TEXT NOT NULL,
    issued_at            TEXT NOT NULL,
    status               TEXT NOT NULL DEFAULT 'issued',
    status_updated_at    TEXT,
    clinical_summary     TEXT,
    arrival_confirmed_by TEXT,
    outcome_notes        TEXT,
    escalated_at         TEXT,
    sync_state           TEXT NOT NULL DEFAULT 'pending',
    FOREIGN KEY (person_id) REFERENCES ${Tables.persons}(id) ON DELETE CASCADE
  )
  ''',
  // The code a facility reads off a paper slip or hears down a phone line.
  'CREATE UNIQUE INDEX idx_referrals_code ON ${Tables.referrals}(reference_code)',
  'CREATE INDEX idx_referrals_status ON ${Tables.referrals}(status, issued_at DESC)',
  'CREATE INDEX idx_referrals_person ON ${Tables.referrals}(person_id, issued_at DESC)',

  // --------------------------------------------------------------------------
  // Barrier reports. Why care did not happen — the sixth challenge area, and
  // the one paper registers throw away by writing "did not attend" and
  // stopping there.
  // --------------------------------------------------------------------------
  '''
  CREATE TABLE ${Tables.barrierReports} (
    id           TEXT PRIMARY KEY,
    household_id TEXT NOT NULL,
    person_id    TEXT,
    referral_id  TEXT,
    barriers     TEXT NOT NULL DEFAULT '',
    recorded_by  TEXT NOT NULL,
    recorded_at  TEXT NOT NULL,
    notes        TEXT,
    resolved     INTEGER NOT NULL DEFAULT 0,
    sync_state   TEXT NOT NULL DEFAULT 'pending',
    FOREIGN KEY (household_id) REFERENCES ${Tables.households}(id) ON DELETE CASCADE
  )
  ''',
  'CREATE INDEX idx_barriers_household ON ${Tables.barrierReports}(household_id, recorded_at DESC)',
  // Powers zone-wide pattern detection: nine families reporting "facility
  // closed" in one month is one staffing problem, not nine family problems.
  'CREATE INDEX idx_barriers_date ON ${Tables.barrierReports}(recorded_at DESC)',

  // --------------------------------------------------------------------------
  // Home checks. What the family saw and what the app advised, kept exactly
  // as the caregiver answered. Deliberately local-only — no sync_state, no
  // outbox row: checking danger signs at home must never feel like filing a
  // record, and the clinical conversation starts when the family tells the
  // health worker. Kept in its own table so it can never be mistaken for a
  // clinical assessment.
  // --------------------------------------------------------------------------
  _homeChecksTable,
  'CREATE INDEX idx_home_checks_household ON ${Tables.homeChecks}(household_id, checked_at DESC)',
  'CREATE INDEX idx_home_checks_person ON ${Tables.homeChecks}(person_id, checked_at DESC)',

  // --------------------------------------------------------------------------
  // Milestone checks. The nurturing-care twin of home checks: what the family
  // says their child can do, for the age band the child was in. Local-only by
  // the same reasoning — play is not a clinical record until the family
  // brings it to the health worker.
  // --------------------------------------------------------------------------
  _milestoneChecksTable,
  'CREATE INDEX idx_milestone_checks_household ON ${Tables.milestoneChecks}(household_id, checked_at DESC)',
  'CREATE INDEX idx_milestone_checks_person ON ${Tables.milestoneChecks}(person_id, checked_at DESC)',

  // --------------------------------------------------------------------------
  // Scheduled contacts. Generated by the engines, so follow-up is never left
  // to a CHO's memory or a note in a exercise book.
  // --------------------------------------------------------------------------
  '''
  CREATE TABLE ${Tables.scheduledContacts} (
    id            TEXT PRIMARY KEY,
    person_id     TEXT NOT NULL,
    household_id  TEXT NOT NULL,
    due_date      TEXT NOT NULL,
    purpose       TEXT NOT NULL,
    created_by    TEXT NOT NULL,
    completed_at  TEXT,
    assessment_id TEXT,
    priority      TEXT NOT NULL DEFAULT 'routine',
    sync_state    TEXT NOT NULL DEFAULT 'pending',
    FOREIGN KEY (person_id) REFERENCES ${Tables.persons}(id) ON DELETE CASCADE,
    FOREIGN KEY (household_id) REFERENCES ${Tables.households}(id) ON DELETE CASCADE
  )
  ''',
  // The "Plan My Day" query: what is due, soonest first, not yet done.
  'CREATE INDEX idx_contacts_due ON ${Tables.scheduledContacts}(completed_at, due_date)',
  'CREATE INDEX idx_contacts_person ON ${Tables.scheduledContacts}(person_id, due_date)',

  // --------------------------------------------------------------------------
  // Sync outbox. Written in the same transaction as the record it describes,
  // which is what makes offline-first safe rather than merely optimistic.
  //
  // `attempts` and `last_error` are kept so a row that will never succeed can
  // be shown to a human instead of retrying silently for a fortnight.
  // --------------------------------------------------------------------------
  '''
  CREATE TABLE ${Tables.outbox} (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    entity_table  TEXT NOT NULL,
    entity_id     TEXT NOT NULL,
    operation     TEXT NOT NULL,
    payload_json  TEXT NOT NULL,
    priority      INTEGER NOT NULL DEFAULT 5,
    queued_at     TEXT NOT NULL,
    attempts      INTEGER NOT NULL DEFAULT 0,
    last_attempt_at TEXT,
    last_error    TEXT,
    synced_at     TEXT
  )
  ''',
  // Urgent referrals must leave the device before routine registrations, so
  // priority leads the ordering.
  'CREATE INDEX idx_outbox_pending ON ${Tables.outbox}(synced_at, priority, queued_at)',
  'CREATE INDEX idx_outbox_entity ON ${Tables.outbox}(entity_table, entity_id)',

  // --------------------------------------------------------------------------
  // Audit log. Constraint 5 is protection of sensitive health data, and access
  // control that cannot be audited is a claim rather than a control. Every
  // permission denial and every clinical override lands here.
  // --------------------------------------------------------------------------
  '''
  CREATE TABLE ${Tables.auditLog} (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    actor_id    TEXT,
    actor_role  TEXT,
    action      TEXT NOT NULL,
    entity_table TEXT,
    entity_id   TEXT,
    outcome     TEXT NOT NULL,
    detail      TEXT,
    occurred_at TEXT NOT NULL
  )
  ''',
  'CREATE INDEX idx_audit_time ON ${Tables.auditLog}(occurred_at DESC)',
  'CREATE INDEX idx_audit_actor ON ${Tables.auditLog}(actor_id, occurred_at DESC)',
];

/// The home-checks DDL stands alone so the version-3 migration can run the
/// exact same statement on devices that predate the table.
const String _homeChecksTable = '''
  CREATE TABLE ${Tables.homeChecks} (
    id            TEXT PRIMARY KEY,
    household_id  TEXT NOT NULL,
    person_id     TEXT NOT NULL,
    client_type   TEXT NOT NULL,
    verdict       TEXT NOT NULL,
    yes_signs     TEXT NOT NULL DEFAULT '',
    unsure_signs  TEXT NOT NULL DEFAULT '',
    checked_by    TEXT NOT NULL,
    checked_at    TEXT NOT NULL,
    FOREIGN KEY (household_id) REFERENCES ${Tables.households}(id) ON DELETE CASCADE,
    FOREIGN KEY (person_id) REFERENCES ${Tables.persons}(id) ON DELETE CASCADE
  )
  ''';

/// The milestone-checks DDL, standalone for the same reason: the version-4
/// migration must run the exact same statement on older devices.
const String _milestoneChecksTable = '''
  CREATE TABLE ${Tables.milestoneChecks} (
    id            TEXT PRIMARY KEY,
    household_id  TEXT NOT NULL,
    person_id     TEXT NOT NULL,
    age_months    INTEGER NOT NULL,
    band_label    TEXT NOT NULL,
    verdict       TEXT NOT NULL,
    can_do        TEXT NOT NULL DEFAULT '',
    not_yet       TEXT NOT NULL DEFAULT '',
    flags         TEXT NOT NULL DEFAULT '',
    checked_by    TEXT NOT NULL,
    checked_at    TEXT NOT NULL,
    FOREIGN KEY (household_id) REFERENCES ${Tables.households}(id) ON DELETE CASCADE,
    FOREIGN KEY (person_id) REFERENCES ${Tables.persons}(id) ON DELETE CASCADE
  )
  ''';
