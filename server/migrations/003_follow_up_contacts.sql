-- ============================================================================
-- 003_follow_up_contacts.sql — the v8 answer-led referral follow-up ledger.
--
-- The client (visit_dao.dart) enqueues one follow_up_contacts row per referral
-- check-in to the sync outbox. Before this change the table did not exist on the
-- server and was absent from the src/tables.js sync whitelist, so POST /api/sync
-- answered 400 "Unknown entity_table" and the client classified the 4xx as a
-- permanent SendRejected — every contact became a poisoned outbox row that never
-- retried and never landed on any device with a configured sync URL.
--
-- This creates the table. The matching whitelist entry lives in src/tables.js and
-- the fresh-install DDL in schema.sql; all three must agree.
--
-- Idempotent: safe to run more than once (CREATE TABLE IF NOT EXISTS). For FRESH
-- installs the equivalent DDL is already baked into schema.sql.
--
-- Run with (the runtime sync user is least-privilege and cannot CREATE, so use
-- an admin account):
--   mysql -u <admin> -p carebridge < migrations/003_follow_up_contacts.sql
-- ============================================================================

USE carebridge;

-- `at` and `condition` are MySQL reserved words; they are backtick-quoted here
-- and by sync.js when it builds the parameterised upsert. Push-only for now (not
-- in src/pull.js PULL_TABLES), matching barrier_reports and scheduled_contacts;
-- adding it to the pull stream is separate reporting/cross-device work.
CREATE TABLE IF NOT EXISTS follow_up_contacts (
  id                 VARCHAR(64) NOT NULL,
  referral_id        VARCHAR(64) NOT NULL,
  person_id          VARCHAR(64) NULL,
  household_id       VARCHAR(64) NOT NULL,
  `at`               VARCHAR(40) NOT NULL,
  channel            VARCHAR(24) NOT NULL,
  reached            VARCHAR(24) NOT NULL,
  care               VARCHAR(24) NOT NULL,
  `condition`        VARCHAR(24) NOT NULL,
  barriers           TEXT        NULL,
  note               TEXT        NULL,
  linked_referral_id VARCHAR(64) NULL,
  recorded_by        VARCHAR(64) NOT NULL,
  sync_state         VARCHAR(24) NOT NULL DEFAULT 'pending',
  PRIMARY KEY (id),
  KEY idx_follow_up_referral (referral_id, `at`),
  KEY idx_follow_up_household (household_id, `at`)
) ENGINE=InnoDB;
