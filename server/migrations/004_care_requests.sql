-- ============================================================================
-- 004_care_requests.sql — the family's request for help.
--
-- A caregiver's device enqueues one care_requests row when a family asks for a
-- health worker after an urgent or contact-today home check. The row must exist
-- server-side and be listed in src/tables.js: sync.js answers 400
-- "Unknown entity_table" for anything absent, the client classifies 4xx as a
-- permanent SendRejected, and the family's request would sit in their outbox
-- forever while their screen claimed help was coming.
--
-- There is deliberately no home_checks table. The check answers never leave the
-- phone; this table is the whole of what does.
--
-- Unlike barrier_reports and scheduled_contacts, which are push-only, this one
-- carries a server-managed pull_updated_at marker and the two triggers that
-- stamp it. A request is only real if the answer can travel home: a status
-- change made by a worker on their device has to reach the family's phone, or
-- they wait at home for a visitor who already came.
--
-- Idempotent: safe to run more than once. For FRESH installs the equivalent DDL
-- is already baked into schema.sql. The matching push whitelist lives in
-- src/tables.js and the pull registration in src/pull.js, and
-- test/care_request_contract_test.dart fails if the four drift apart.
--
-- Run with (the runtime sync user is least-privilege and cannot CREATE, so use
-- an admin account):
--   mysql -u <admin> -p carebridge < migrations/004_care_requests.sql
-- If that runtime user is granted per table rather than database-wide, add
-- SELECT, INSERT and UPDATE on care_requests to its grants before deploying.
-- ============================================================================

USE carebridge;

CREATE TABLE IF NOT EXISTS care_requests (
  id              VARCHAR(64)  NOT NULL,
  household_id    VARCHAR(64)  NOT NULL,
  person_id       VARCHAR(64)  NOT NULL,
  level           VARCHAR(24)  NOT NULL,
  home_check_id   VARCHAR(64)  NOT NULL,
  created_by      VARCHAR(64)  NOT NULL,
  created_at      VARCHAR(40)  NOT NULL,
  updated_at      VARCHAR(40)  NOT NULL,
  status          VARCHAR(24)  NOT NULL DEFAULT 'open',
  answered_at     VARCHAR(40)  NULL,
  sync_state      VARCHAR(24)  NOT NULL DEFAULT 'pending',
  pull_updated_at VARCHAR(40)  NULL,
  PRIMARY KEY (id),
  KEY idx_care_requests_household (household_id, created_at),
  KEY idx_care_requests_check (home_check_id),
  KEY idx_care_requests_pull (pull_updated_at)
) ENGINE=InnoDB;

-- Single-statement trigger bodies, so no DELIMITER gymnastics is required.
CREATE TRIGGER IF NOT EXISTS trg_care_requests_pull_ins BEFORE INSERT ON care_requests
  FOR EACH ROW SET NEW.pull_updated_at = DATE_FORMAT(UTC_TIMESTAMP(), '%Y-%m-%dT%H:%i:%s');
CREATE TRIGGER IF NOT EXISTS trg_care_requests_pull_upd BEFORE UPDATE ON care_requests
  FOR EACH ROW SET NEW.pull_updated_at = DATE_FORMAT(UTC_TIMESTAMP(), '%Y-%m-%dT%H:%i:%s');
