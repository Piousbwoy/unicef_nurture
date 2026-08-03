-- ============================================================================
-- CareBridge AI — district sync schema (MariaDB)
--
-- This is the CENTRAL aggregate that field phones eventually sync into. It
-- mirrors the on-device SQLite schema (lib/data/local/app_database.dart) so a
-- record looks identical on both sides.
--
-- TWO DELIBERATE DIFFERENCES from the device schema:
--
-- 1. NO FOREIGN KEY constraints. The phone's outbox sends records by
--    *priority*, not by parent-child order: an urgent referral (priority 0)
--    can arrive before the routine household registration (priority 5) it
--    belongs to. A sink that rejected rows on FK violation would make the app
--    permanently abandon a valid record (the app treats 4xx as "never retry").
--    Referential integrity is already enforced at the SOURCE — the phone's
--    SQLite database runs with `PRAGMA foreign_keys = ON`. This database is an
--    eventually-consistent aggregate for reporting, so we keep the indexes
--    (fast queries) and drop the constraints (tolerant ingest).
--
-- 2. NO pin_hash / pin_salt columns. Device credentials never leave the phone
--    (the app strips them from the sync payload), so the server has nowhere to
--    put them and nothing to leak.
--
-- Dates are stored as the exact ISO-8601 TEXT the phone sends, so nothing is
-- lost to timezone or format conversion. Booleans are 0/1 integers, exactly as
-- the device serialises them.
-- ============================================================================

CREATE DATABASE IF NOT EXISTS carebridge
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE carebridge;

-- ----------------------------------------------------------------------------
-- Health workers / caregivers / accounts.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
  id                  VARCHAR(64)  NOT NULL,
  full_name           VARCHAR(191) NOT NULL,
  phone               VARCHAR(40)  NOT NULL,
  role                VARCHAR(32)  NOT NULL,
  region              VARCHAR(96)  NOT NULL,
  district            VARCHAR(96)  NOT NULL,
  community           VARCHAR(96)  NOT NULL,
  chps_zone           VARCHAR(96)  NULL,
  facility_name       VARCHAR(160) NULL,
  staff_id            VARCHAR(64)  NULL,
  preferred_language  VARCHAR(40)  NOT NULL DEFAULT 'English',
  linked_household_id VARCHAR(64)  NULL,
  created_at          VARCHAR(40)  NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_users_phone (phone),
  KEY idx_users_district (region, district, community)
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
-- Households — the unit a community health worker actually walks to.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS households (
  id                          VARCHAR(64)  NOT NULL,
  name                        VARCHAR(191) NOT NULL,
  region                      VARCHAR(96)  NOT NULL,
  district                    VARCHAR(96)  NOT NULL,
  community                   VARCHAR(96)  NOT NULL,
  created_by                  VARCHAR(64)  NOT NULL,
  head_name                   VARCHAR(191) NULL,
  contact_phone               VARCHAR(40)  NULL,
  latitude                    DOUBLE       NULL,
  longitude                   DOUBLE       NULL,
  family_size                 INT          NULL,
  has_valid_nhis              TINYINT(1)   NULL,
  walking_minutes_to_facility INT          NULL,
  landmark                    VARCHAR(255) NULL,
  created_at                  VARCHAR(40)  NOT NULL,
  updated_at                  VARCHAR(40)  NOT NULL,
  PRIMARY KEY (id),
  KEY idx_households_community (region, district, community),
  KEY idx_households_created_by (created_by)
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
-- Persons — one flat table for women, newborns and under-fives.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS persons (
  id               VARCHAR(64)  NOT NULL,
  household_id     VARCHAR(64)  NOT NULL,
  full_name        VARCHAR(191) NOT NULL,
  client_type      VARCHAR(32)  NOT NULL,
  sex              VARCHAR(16)  NULL,
  date_of_birth    VARCHAR(40)  NULL,
  age_years_approx INT          NULL,
  phone            VARCHAR(40)  NULL,
  mother_id        VARCHAR(64)  NULL,
  is_dob_estimated TINYINT(1)   NOT NULL DEFAULT 0,
  nhis_number      VARCHAR(64)  NULL,
  created_at       VARCHAR(40)  NOT NULL,
  updated_at       VARCHAR(40)  NOT NULL,
  is_active        TINYINT(1)   NOT NULL DEFAULT 1,
  PRIMARY KEY (id),
  KEY idx_persons_household (household_id, is_active),
  KEY idx_persons_mother (mother_id),
  KEY idx_persons_type (client_type, is_active)
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
-- Maternal record — mirrors Ghana's Maternal Health Record Book.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS maternal_records (
  person_id              VARCHAR(64) NOT NULL,
  gravida                INT         NULL,
  parity                 INT         NULL,
  previous_losses        INT         NULL,
  previous_caesarean     INT         NULL,
  last_menstrual_period  VARCHAR(40) NULL,
  expected_delivery_date VARCHAR(40) NULL,
  anc_contacts_completed INT         NOT NULL DEFAULT 0,
  iptp_doses             INT         NOT NULL DEFAULT 0,
  td_doses               INT         NOT NULL DEFAULT 0,
  iron_folate_supplied   TINYINT(1)  NOT NULL DEFAULT 0,
  llin_supplied          TINYINT(1)  NOT NULL DEFAULT 0,
  haemoglobin            DOUBLE      NULL,
  blood_group            VARCHAR(16) NULL,
  sickling_status        VARCHAR(32) NULL,
  hiv_tested             TINYINT(1)  NOT NULL DEFAULT 0,
  delivery_date          VARCHAR(40) NULL,
  delivery_place         VARCHAR(96) NULL,
  delivery_mode          VARCHAR(64) NULL,
  plurality              VARCHAR(32) NOT NULL DEFAULT 'singleton',
  family_planning_method VARCHAR(96) NULL,
  updated_at             VARCHAR(40) NOT NULL,
  PRIMARY KEY (person_id)
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
-- Birth record — fixed at birth; drives the young-infant risk model.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS birth_records (
  person_id                 VARCHAR(64) NOT NULL,
  birth_weight_kg           DOUBLE      NULL,
  gestation_weeks_at_birth  INT         NULL,
  delivery_place            VARCHAR(96) NULL,
  delivery_mode             VARCHAR(64) NULL,
  plurality                 VARCHAR(32) NOT NULL DEFAULT 'singleton',
  birth_order               INT         NOT NULL DEFAULT 1,
  resuscitation_needed      TINYINT(1)  NULL,
  cord_care_given           TINYINT(1)  NULL,
  vitamin_k_given           TINYINT(1)  NULL,
  breastfed_within_one_hour TINYINT(1)  NULL,
  updated_at                VARCHAR(40) NOT NULL,
  PRIMARY KEY (person_id)
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
-- Growth measurements — append-only series for the trajectory engine.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS growth_measurements (
  id                   VARCHAR(64) NOT NULL,
  person_id            VARCHAR(64) NOT NULL,
  taken_at             VARCHAR(40) NOT NULL,
  muac_cm              DOUBLE      NULL,
  weight_kg            DOUBLE      NULL,
  height_cm            DOUBLE      NULL,
  has_bilateral_oedema TINYINT(1)  NOT NULL DEFAULT 0,
  recorded_by          VARCHAR(64) NULL,
  PRIMARY KEY (id),
  KEY idx_growth_person_date (person_id, taken_at)
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
-- Visits — one encounter can carry several assessments.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS visits (
  id           VARCHAR(64)  NOT NULL,
  household_id VARCHAR(64)  NOT NULL,
  conducted_by VARCHAR(64)  NOT NULL,
  started_at   VARCHAR(40)  NOT NULL,
  completed_at VARCHAR(40)  NULL,
  reasons      TEXT         NULL,
  latitude     DOUBLE       NULL,
  longitude    DOUBLE       NULL,
  notes        TEXT         NULL,
  sync_state   VARCHAR(24)  NOT NULL DEFAULT 'pending',
  PRIMARY KEY (id),
  KEY idx_visits_household (household_id, started_at),
  KEY idx_visits_worker_date (conducted_by, started_at)
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
-- Visit participants — the roll call ("who was actually present").
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS visit_participants (
  visit_id     VARCHAR(64) NOT NULL,
  person_id    VARCHAR(64) NOT NULL,
  was_present  TINYINT(1)  NOT NULL DEFAULT 1,
  absence_note VARCHAR(255) NULL,
  queue_order  INT         NOT NULL DEFAULT 0,
  assessed     TINYINT(1)  NOT NULL DEFAULT 0,
  PRIMARY KEY (visit_id, person_id),
  KEY idx_participants_person (person_id)
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
-- Assessments — raw answers AND the verdict, so decisions can be re-derived.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS assessments (
  id                VARCHAR(64) NOT NULL,
  visit_id          VARCHAR(64) NOT NULL,
  person_id         VARCHAR(64) NOT NULL,
  client_type       VARCHAR(32) NOT NULL,
  performed_by      VARCHAR(64) NOT NULL,
  performed_at      VARCHAR(40) NOT NULL,
  inputs_json       MEDIUMTEXT  NOT NULL,
  result_json       MEDIUMTEXT  NOT NULL,
  care_plan_json    MEDIUMTEXT  NULL,
  overridden_triage VARCHAR(24) NULL,
  override_reason   TEXT        NULL,
  override_by       VARCHAR(64) NULL,
  sync_state        VARCHAR(24) NOT NULL DEFAULT 'pending',
  PRIMARY KEY (id),
  KEY idx_assessments_person (person_id, performed_at),
  KEY idx_assessments_visit (visit_id),
  KEY idx_assessments_overrides (overridden_triage)
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
-- Referrals — the last-mile loop; status is a first-class column.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS referrals (
  id                   VARCHAR(64)  NOT NULL,
  reference_code       VARCHAR(40)  NOT NULL,
  person_id            VARCHAR(64)  NOT NULL,
  assessment_id        VARCHAR(64)  NOT NULL,
  facility_name        VARCHAR(160) NOT NULL,
  reason               TEXT         NOT NULL,
  urgency              VARCHAR(24)  NOT NULL,
  issued_by            VARCHAR(64)  NOT NULL,
  issued_at            VARCHAR(40)  NOT NULL,
  status               VARCHAR(24)  NOT NULL DEFAULT 'issued',
  status_updated_at    VARCHAR(40)  NULL,
  clinical_summary     MEDIUMTEXT   NULL,
  arrival_confirmed_by VARCHAR(64)  NULL,
  outcome_notes        TEXT         NULL,
  escalated_at         VARCHAR(40)  NULL,
  sync_state           VARCHAR(24)  NOT NULL DEFAULT 'pending',
  PRIMARY KEY (id),
  UNIQUE KEY uq_referrals_code (reference_code),
  KEY idx_referrals_status (status, issued_at),
  KEY idx_referrals_person (person_id, issued_at)
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
-- Barrier reports — why care did not happen.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS barrier_reports (
  id           VARCHAR(64) NOT NULL,
  household_id VARCHAR(64) NOT NULL,
  person_id    VARCHAR(64) NULL,
  referral_id  VARCHAR(64) NULL,
  barriers     TEXT        NULL,
  recorded_by  VARCHAR(64) NOT NULL,
  recorded_at  VARCHAR(40) NOT NULL,
  notes        TEXT        NULL,
  resolved     TINYINT(1)  NOT NULL DEFAULT 0,
  sync_state   VARCHAR(24) NOT NULL DEFAULT 'pending',
  PRIMARY KEY (id),
  KEY idx_barriers_household (household_id, recorded_at),
  KEY idx_barriers_date (recorded_at)
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
-- Scheduled contacts — engine-generated follow-up ("Plan My Day").
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS scheduled_contacts (
  id            VARCHAR(64) NOT NULL,
  person_id     VARCHAR(64) NOT NULL,
  household_id  VARCHAR(64) NOT NULL,
  due_date      VARCHAR(40) NOT NULL,
  purpose       TEXT        NOT NULL,
  created_by    VARCHAR(64) NOT NULL,
  completed_at  VARCHAR(40) NULL,
  assessment_id VARCHAR(64) NULL,
  priority      VARCHAR(24) NOT NULL DEFAULT 'routine',
  sync_state    VARCHAR(24) NOT NULL DEFAULT 'pending',
  PRIMARY KEY (id),
  KEY idx_contacts_due (completed_at, due_date),
  KEY idx_contacts_person (person_id, due_date)
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
-- Sync log — a server-side audit trail of EVERY write the sync endpoint makes.
-- It records *what* changed (table, id, operation, when) but never the payload
-- itself, so the audit trail carries no PHI. This is the control that makes
-- "who changed this child's record, and when" answerable at the district.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sync_log (
  id             BIGINT      NOT NULL AUTO_INCREMENT,
  entity_table   VARCHAR(64) NOT NULL,
  entity_id      VARCHAR(64) NOT NULL,
  operation      VARCHAR(16) NOT NULL,
  rows_affected  INT         NOT NULL DEFAULT 0,
  client_version VARCHAR(32) NULL,
  received_at    DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_sync_log_entity (entity_table, entity_id),
  KEY idx_sync_log_time (received_at)
) ENGINE=InnoDB;
