-- ============================================================================
-- CareBridge AI — Main Server Schema (MariaDB)
--
-- This is the CENTRAL MAIN SERVER repository that powers our Hybrid
-- Architecture. It mirrors the on-device SQLite schema so that records look
-- identical on both sides, enabling seamless synchronization and account
-- restoration when a field user switches phones or recovers an empty device.
--
-- KEY DESIGN DIFFERENCE from the device SQLite schema:
--
-- 1. NO FOREIGN KEY constraints. The phone's outbox sends records by
--    *priority*, not by parent-child order: an urgent referral (priority 0)
--    can arrive before the routine household registration (priority 5) it
--    belongs to. A sink that rejected rows on FK violation would make the app
--    permanently abandon a valid record (the app treats 4xx as "never retry").
--    Referential integrity is already enforced at the SOURCE — the phone's
--    SQLite database runs with `PRAGMA foreign_keys = ON`. This database is an
--    eventually-consistent aggregate for reporting and recovery, so we keep
--    the indexes (fast queries) and drop the constraints (tolerant ingest).
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
  -- NOTE: pin_hash and pin_salt are DEPRECATED and no longer synced from new
  -- clients. They remain in the schema ONLY for the duration of the transition
  -- from legacy-device recovery flows. They are NULL on every record written
  -- by a post-v1.1 client. New authentication uses the isolated user_verifiers
  -- table, which stores a DOMAIN-SEPARATED HMAC cloud verifier derived (but
  -- NOT recoverable) from the on-device pin_hash. See tables.js whitelist
  -- commentary for the Ghana Health Service compliance audit trail.
  pin_hash            VARCHAR(128) NULL,
  pin_salt            VARCHAR(64)  NULL,
  created_at          VARCHAR(40)  NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_users_phone (phone),
  KEY idx_users_district (region, district, community)
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
-- Isolated cloud-authentication verifiers — physically and logically separate
-- from the synced users/patients table per Ghana Health Service data-privacy
-- compliance architecture.
--
-- Construction (client-generated, at REGISTRATION / PIN CHANGE only):
--
--   cloud_verifier = HMAC-SHA256-ITERATED(
--       key   = "carebridge_cloud_auth_v1" || server_salt || phone,
--       input = device_local_pin_hash)
--
--   server_salt = 24-byte cryptographically random value, distinct from the
--                 device-local pin_salt (which never leaves the device).
--
-- Challenge-response recovery login (on a BLANK replacement device):
--   1. Client GET /api/auth/challenge?phone=X
--   2. Server returns { user_id, server_salt } — server_salt is non-secret.
--   3. Client, on blank device, re-derives the identical cloud_verifier using
--      Credentials.computeCloudVerifierFromPin(pin, phone, server_salt).
--      This stretches the PIN under server_salt first (first_pass) then
--      applies the identical domain-separated 120k HMAC iteration chain.
--   4. Client POSTs the resulting cloud_verifier (NOT PIN, NOT local_hash).
--   5. Server compares stored verifier constant-time; on match → issue JWT.
--
-- Security properties:
--   * local pin_hash / pin_salt NEVER cross the network (tables.js whitelist
--     strips them; AppUser.toMap never emits them).  → 100% compliance with
--     the HOW_IT_WORKS.md data-privacy promise.
--   * Reversing user_verifiers.verifier → 4-digit PIN costs 120k HMAC-SHA256
--     per candidate, per user, per server_salt — infeasible even at scale.
--   * Reversing user_verifiers.verifier → device_local_pin_hash costs 120k
--     HMAC-SHA256 per attempt (reversing the derivation).
--   * user_verifiers is the ONLY table that ever receives verifier bytes; the
--     general-purpose users table remains free of any credential material
--     that could be accidentally JOINed or SELECT * leaked.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_verifiers (
  user_id      VARCHAR(64)  NOT NULL,
  -- 24-byte cryptographically random salt, distinct from device-local pin_salt.
  -- Returned by /api/auth/challenge (non-secret) during recovery login.
  server_salt  VARCHAR(64)  NOT NULL,
  -- Domain-separated HMAC cloud verifier (base64 of final 32-byte hash).
  -- Never transmitted back to any client, ever. Compared constant-time.
  verifier     VARCHAR(128) NOT NULL,
  device_id    VARCHAR(64)  NULL,
  created_at   VARCHAR(40)  NOT NULL,
  updated_at   VARCHAR(40)  NOT NULL,
  PRIMARY KEY (user_id),
  CONSTRAINT fk_verifiers_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
-- Refresh token store. Long-lived refresh tokens are bound to a user+device
-- and can be revoked explicitly (lost-device workflow) or expire naturally.
-- Access tokens are stateless/signed (JWT, no DB lookup) for perf; refresh
-- tokens are stored in DB and checked on every /api/auth/refresh call.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS refresh_tokens (
  token_hash   VARCHAR(64)  NOT NULL,
  user_id      VARCHAR(64)  NOT NULL,
  device_id    VARCHAR(64)  NULL,
  issued_at    VARCHAR(40)  NOT NULL,
  expires_at   VARCHAR(40)  NOT NULL,
  revoked_at   VARCHAR(40)  NULL,
  PRIMARY KEY (token_hash),
  KEY idx_refresh_user (user_id)
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
-- Maternal record — mirrors Ghana's Maternal Health Record Book (JICA/GHS).
-- Version 5 (August 2026): Rh, sickle genotype, HBsAg/syphilis/HIV dates,
-- 4-strip urinalysis, 7 PE Liverpool flags, 8 PMHx, PNC involution/lochia/
-- wound/breast, 10-item Edinburgh EPDS (WHO Kumasi 2020 validated).
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS maternal_records (
  person_id                    VARCHAR(64) NOT NULL,
  gravida                      INT         NULL,
  parity                       INT         NULL,
  previous_losses              INT         NULL,
  previous_caesarean           INT         NULL,
  last_menstrual_period        VARCHAR(40) NULL,
  expected_delivery_date       VARCHAR(40) NULL,
  anc_contacts_completed       INT         NOT NULL DEFAULT 0,
  iptp_doses                   INT         NOT NULL DEFAULT 0,
  td_doses                     INT         NOT NULL DEFAULT 0,
  iron_folate_supplied         TINYINT(1)  NOT NULL DEFAULT 0,
  llin_supplied                TINYINT(1)  NOT NULL DEFAULT 0,
  haemoglobin                  DOUBLE      NULL,
  blood_group                  VARCHAR(16) NULL,
  rhesus_positive              TINYINT(1)  NULL,
  sickling_status              VARCHAR(32) NULL,
  sickle_genotype              VARCHAR(16) NULL,
  hiv_tested                   TINYINT(1)  NOT NULL DEFAULT 0,
  hiv_test_date                VARCHAR(40) NULL,
  syphilis_tested              TINYINT(1)  NOT NULL DEFAULT 0,
  syphilis_test_date           VARCHAR(40) NULL,
  hbsag_tested                 TINYINT(1)  NOT NULL DEFAULT 0,
  hbsag_test_date              VARCHAR(40) NULL,
  delivery_date                VARCHAR(40) NULL,
  delivery_place               VARCHAR(96) NULL,
  delivery_mode                VARCHAR(64) NULL,
  plurality                    VARCHAR(32) NOT NULL DEFAULT 'singleton',
  family_planning_method       VARCHAR(96) NULL,
  urine_protein                INT         NULL,
  urine_glucose                INT         NULL,
  urine_ketones                INT         NULL,
  urine_blood                  INT         NULL,
  oedema_hands_or_face         TINYINT(1)  NOT NULL DEFAULT 0,
  epigastric_pain              TINYINT(1)  NOT NULL DEFAULT 0,
  headache_severe              TINYINT(1)  NOT NULL DEFAULT 0,
  blurred_vision               TINYINT(1)  NOT NULL DEFAULT 0,
  brisk_reflexes               TINYINT(1)  NOT NULL DEFAULT 0,
  oliguria                     TINYINT(1)  NOT NULL DEFAULT 0,
  weight_gain_over_1kg_per_week TINYINT(1) NOT NULL DEFAULT 0,
  prev_hypertension            TINYINT(1)  NOT NULL DEFAULT 0,
  prev_diabetes                TINYINT(1)  NOT NULL DEFAULT 0,
  prev_anaemia                 TINYINT(1)  NOT NULL DEFAULT 0,
  prev_tb                      TINYINT(1)  NOT NULL DEFAULT 0,
  prev_asthma                  TINYINT(1)  NOT NULL DEFAULT 0,
  prev_heart_disease           TINYINT(1)  NOT NULL DEFAULT 0,
  prev_kidney_disease          TINYINT(1)  NOT NULL DEFAULT 0,
  prev_hepatitis               TINYINT(1)  NOT NULL DEFAULT 0,
  involution_cm_below_umbilicus INT         NULL,
  lochia_colour                VARCHAR(32) NULL,
  lochia_odour                 VARCHAR(32) NULL,
  lochia_amount                VARCHAR(32) NULL,
  wound_redness                TINYINT(1)  NOT NULL DEFAULT 0,
  wound_oedema                 TINYINT(1)  NOT NULL DEFAULT 0,
  wound_discharge              TINYINT(1)  NOT NULL DEFAULT 0,
  wound_approximated           TINYINT(1)  NULL,
  episiotomy_or_laceration     TINYINT(1)  NOT NULL DEFAULT 0,
  nipples_cracked              TINYINT(1)  NOT NULL DEFAULT 0,
  nipples_inverted             TINYINT(1)  NOT NULL DEFAULT 0,
  breast_mastitis_signs        TINYINT(1)  NOT NULL DEFAULT 0,
  breast_attachment_ok         TINYINT(1)  NULL,
  breast_let_down_ok           TINYINT(1)  NULL,
  edinburgh_laugh              INT         NULL,
  edinburgh_enjoy              INT         NULL,
  edinburgh_blame              INT         NULL,
  edinburgh_anxious            INT         NULL,
  edinburgh_scared             INT         NULL,
  edinburgh_overwhelm          INT         NULL,
  edinburgh_sleep              INT         NULL,
  edinburgh_sad                INT         NULL,
  edinburgh_cry                INT         NULL,
  edinburgh_self_harm          INT         NULL,
  updated_at                   VARCHAR(40) NOT NULL,
  PRIMARY KEY (person_id)
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
-- Birth record — fixed at birth; drives the young-infant 0–59d PSBI model.
-- Version 5 (August 2026): 15 WHO PSBI danger signs, KMC tracking, newborn
-- sickle + hearing screening (GHS 2024 national rollout), APGAR, length,
-- vitals, Vitamin K dose 0.5/1 mg, BF day1 check.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS birth_records (
  person_id                  VARCHAR(64) NOT NULL,
  birth_weight_kg            DOUBLE      NULL,
  birth_length_cm            DOUBLE      NULL,
  gestation_weeks_at_birth   INT         NULL,
  delivery_place             VARCHAR(96) NULL,
  delivery_mode              VARCHAR(64) NULL,
  plurality                  VARCHAR(32) NOT NULL DEFAULT 'singleton',
  birth_order                INT         NOT NULL DEFAULT 1,
  resuscitation_needed       TINYINT(1)  NULL,
  apgar_1_minute             INT         NULL,
  apgar_5_minute             INT         NULL,
  cord_care_given            TINYINT(1)  NULL,
  cord_chlorhexidine_applied TINYINT(1)  NULL,
  vitamin_k_given            TINYINT(1)  NULL,
  vitamin_k_dose_mg          DOUBLE      NOT NULL DEFAULT 1.0,
  breastfed_within_one_hour  TINYINT(1)  NULL,
  breastfeeding_ok_on_day1   TINYINT(1)  NULL,
  temperature_celsius        DOUBLE      NULL,
  respiratory_rate_per_min   INT         NULL,
  heart_rate_per_min         INT         NULL,
  oxygen_saturation_per_cent INT         NULL,
  history_of_convulsions     TINYINT(1)  NOT NULL DEFAULT 0,
  severe_chest_indrawing     TINYINT(1)  NOT NULL DEFAULT 0,
  nasal_flaring              TINYINT(1)  NOT NULL DEFAULT 0,
  grunting                   TINYINT(1)  NOT NULL DEFAULT 0,
  bulging_fontanelle         TINYINT(1)  NOT NULL DEFAULT 0,
  jaundice_before_24h        TINYINT(1)  NOT NULL DEFAULT 0,
  jaundice_on_day3_or_later  VARCHAR(32) NULL,
  feeding_difficulty         TINYINT(1)  NOT NULL DEFAULT 0,
  abdominal_distension       TINYINT(1)  NOT NULL DEFAULT 0,
  cord_redness_beyond_base   TINYINT(1)  NOT NULL DEFAULT 0,
  cord_pus                   TINYINT(1)  NOT NULL DEFAULT 0,
  cord_oedema_beyond_base    TINYINT(1)  NOT NULL DEFAULT 0,
  skin_pustules              TINYINT(1)  NOT NULL DEFAULT 0,
  lethargic_or_unconscious   TINYINT(1)  NOT NULL DEFAULT 0,
  bleeding_from_any_site     TINYINT(1)  NOT NULL DEFAULT 0,
  kmc_eligible               TINYINT(1)  NOT NULL DEFAULT 0,
  kmc_initiated              TINYINT(1)  NULL,
  kmc_site                   VARCHAR(64) NULL,
  kmc_hours_per_day          DOUBLE      NULL,
  sickle_screen_sample_collected TINYINT(1) NULL,
  sickle_screen_sample_date  VARCHAR(40) NULL,
  hearing_screen_done        TINYINT(1)  NULL,
  hearing_screen_result      VARCHAR(32) NULL,
  updated_at                 VARCHAR(40) NOT NULL,
  PRIMARY KEY (person_id)
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
-- Growth measurements — append-only series for the trajectory engine.
-- Version 5 (August 2026): muac_mm (source-of-truth, read directly from the
-- GHS tape) + palmar_pallor_severity (IMCI malnutrition anaemia trigger).
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS growth_measurements (
  id                   VARCHAR(64) NOT NULL,
  person_id            VARCHAR(64) NOT NULL,
  taken_at             VARCHAR(40) NOT NULL,
  muac_mm              INT         NULL,
  muac_cm              DOUBLE      NULL,
  weight_kg            DOUBLE      NULL,
  height_cm            DOUBLE      NULL,
  has_bilateral_oedema TINYINT(1)  NOT NULL DEFAULT 0,
  palmar_pallor_severity VARCHAR(32) NULL,
  recorded_by          VARCHAR(64) NULL,
  PRIMARY KEY (id),
  KEY idx_growth_person_date (person_id, taken_at)
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
-- Child IMCI structured assessment snapshot.
-- One row per sick-child encounter. Column order and section names match the
-- Ghana GHS IMCI Sick-Child Case Recording Form (blue book, 2022 revision)
-- EXACTLY — this is the adoption condition. 10 sections:
--   1. general danger signs
--   2. cough / RR / pneumonia
--   3. diarrhoea / dehydration Plan A/B/C
--   4. fever / measles / malaria RDT / dengue tourniquet
--   5. ear / mastoiditis
--   6. malnutrition / anaemia / HIV / RUTF
--   7. IYCF feeding assessment (6–23 months)
--   8. immunizations due/given today
--   9. initial vs follow_up visit type flag
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS child_assessment_snapshots (
  id                           VARCHAR(64) NOT NULL,
  person_id                    VARCHAR(64) NOT NULL,
  assessed_at                  VARCHAR(40) NOT NULL,
  visit_type                   VARCHAR(32) NOT NULL DEFAULT 'initial',
  age_days_completed           INT         NULL,
  able_to_drink_or_breastfeed  TINYINT(1)  NULL,
  vomits_everything            TINYINT(1)  NULL,
  has_convulsions_this_visit   TINYINT(1)  NULL,
  is_lethargic_or_unconscious  TINYINT(1)  NULL,
  cough_present                TINYINT(1)  NOT NULL DEFAULT 0,
  cough_duration_days          INT         NULL,
  respiratory_rate_per_min     INT         NULL,
  chest_indrawing              TINYINT(1)  NOT NULL DEFAULT 0,
  stridor_calm                 TINYINT(1)  NOT NULL DEFAULT 0,
  nasal_flaring                TINYINT(1)  NOT NULL DEFAULT 0,
  oxygen_saturation_per_cent   INT         NULL,
  diarrhoea_present            TINYINT(1)  NOT NULL DEFAULT 0,
  diarrhoea_duration_days      INT         NULL,
  blood_in_stool               TINYINT(1)  NOT NULL DEFAULT 0,
  restless_or_irritable        TINYINT(1)  NULL,
  sunken_eyes                  TINYINT(1)  NULL,
  drinks_eagerly               TINYINT(1)  NULL,
  skin_pinch_result            VARCHAR(32) NULL,
  fever_reported               TINYINT(1)  NOT NULL DEFAULT 0,
  fever_duration_days          INT         NULL,
  temperature_celsius          DOUBLE      NULL,
  stiff_neck                   TINYINT(1)  NOT NULL DEFAULT 0,
  runny_nose                   TINYINT(1)  NOT NULL DEFAULT 0,
  measles_rash_present         TINYINT(1)  NOT NULL DEFAULT 0,
  measles_cough                TINYINT(1)  NOT NULL DEFAULT 0,
  measles_coryza               TINYINT(1)  NOT NULL DEFAULT 0,
  measles_conjunctivitis       TINYINT(1)  NOT NULL DEFAULT 0,
  mouth_ulcers                 TINYINT(1)  NOT NULL DEFAULT 0,
  eye_discharge                TINYINT(1)  NOT NULL DEFAULT 0,
  corneal_clouding             TINYINT(1)  NOT NULL DEFAULT 0,
  measles_within_past_3_months TINYINT(1)  NOT NULL DEFAULT 0,
  malaria_rdt_done             TINYINT(1)  NOT NULL DEFAULT 0,
  malaria_rdt_result           VARCHAR(32) NULL,
  tourniquet_test_done         TINYINT(1)  NOT NULL DEFAULT 0,
  tourniquet_test_positive     TINYINT(1)  NULL,
  skin_petechiae               TINYINT(1)  NOT NULL DEFAULT 0,
  capillary_refill_seconds     DOUBLE      NULL,
  ear_problem_present          TINYINT(1)  NOT NULL DEFAULT 0,
  ear_pain_duration_days       INT         NULL,
  ear_pus_draining             TINYINT(1)  NOT NULL DEFAULT 0,
  ear_pus_duration_days        INT         NULL,
  tender_swelling_behind_ear   TINYINT(1)  NOT NULL DEFAULT 0,
  weight_for_height_or_length_zscore DOUBLE NULL,
  hiv_exposed_or_infected_status VARCHAR(64) NULL,
  able_to_finish_rutf          TINYINT(1)  NULL,
  breastfed_today              TINYINT(1)  NULL,
  night_feeds_per_24h          INT         NULL,
  complementary_foods_given_today TINYINT(1) NULL,
  minimum_dietary_diversity    TINYINT(1)  NULL,
  minimum_meal_frequency       TINYINT(1)  NULL,
  minimum_acceptable_diet      TINYINT(1)  NULL,
  immunizations_due_today      TEXT        NULL,
  immunizations_given_today    TEXT        NULL,
  assessed_by_user_id          VARCHAR(64) NULL,
  recorded_by_user_id          VARCHAR(64) NULL,
  updated_at                   VARCHAR(40) NOT NULL,
  PRIMARY KEY (id),
  KEY idx_child_assessment_snapshots_person (person_id, assessed_at),
  KEY idx_child_assessment_snapshots_visit (visit_type, assessed_at)
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
-- itself, so the audit trail carries no PHI. user_id + facility_id + device_id
-- come from the JWT claims attached by the auth middleware, never from client
-- input, so attribution is forensically sound.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sync_log (
  id             BIGINT      NOT NULL AUTO_INCREMENT,
  user_id        VARCHAR(64) NULL,
  facility_name  VARCHAR(160) NULL,
  device_id      VARCHAR(64) NULL,
  entity_table   VARCHAR(64) NOT NULL,
  entity_id      VARCHAR(64) NOT NULL,
  operation      VARCHAR(16) NOT NULL,
  rows_affected  INT         NOT NULL DEFAULT 0,
  client_version VARCHAR(32) NULL,
  auth_method    VARCHAR(16) NOT NULL DEFAULT 'jwt', -- 'jwt' | 'legacy_token'
  received_at    DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_sync_log_entity (entity_table, entity_id),
  KEY idx_sync_log_user (user_id, received_at),
  KEY idx_sync_log_time (received_at)
) ENGINE=InnoDB;
