-- ============================================================================
-- 002_delta_pull.sql — server-managed change markers for GET /api/pull.
--
-- The five pullable clinical tables did not all carry an updated_at column,
-- and device clocks are not trustworthy. Instead of trusting any of them, the
-- SERVER maintains its own second-precision UTC marker (pull_updated_at) on
-- every row via triggers, stamped on every INSERT and UPDATE — including the
-- INSERT ... ON DUPLICATE KEY UPDATE that POST /api/sync performs. GET
-- /api/pull streams rows whose marker is newer than the caller's watermark.
--
-- Idempotent: safe to run more than once (IF NOT EXISTS everywhere). For
-- FRESH installs the equivalent DDL is already baked into schema.sql.
--
-- Run with:
--   mysql -u carebridge_sync -p carebridge < migrations/002_delta_pull.sql
-- ============================================================================

USE carebridge;

-- ---------------------------------------------------------------------------
-- 1. The marker column itself.
-- ---------------------------------------------------------------------------
ALTER TABLE households  ADD COLUMN IF NOT EXISTS pull_updated_at VARCHAR(40) NULL;
ALTER TABLE persons     ADD COLUMN IF NOT EXISTS pull_updated_at VARCHAR(40) NULL;
ALTER TABLE visits      ADD COLUMN IF NOT EXISTS pull_updated_at VARCHAR(40) NULL;
ALTER TABLE assessments ADD COLUMN IF NOT EXISTS pull_updated_at VARCHAR(40) NULL;
ALTER TABLE referrals   ADD COLUMN IF NOT EXISTS pull_updated_at VARCHAR(40) NULL;

-- ---------------------------------------------------------------------------
-- 2. Backfill from the newest legacy timestamp each table has. Rows created
--    before this migration become "changed as of their last client edit",
--    which is the honest best estimate — the first pull after the migration
--    delivers them once, then never again until they actually change.
-- ---------------------------------------------------------------------------
UPDATE households  SET pull_updated_at = LEFT(COALESCE(updated_at, created_at), 19)
  WHERE pull_updated_at IS NULL;
UPDATE persons     SET pull_updated_at = LEFT(COALESCE(updated_at, created_at), 19)
  WHERE pull_updated_at IS NULL;
UPDATE visits      SET pull_updated_at = LEFT(COALESCE(completed_at, started_at), 19)
  WHERE pull_updated_at IS NULL;
UPDATE assessments SET pull_updated_at = LEFT(performed_at, 19)
  WHERE pull_updated_at IS NULL;
UPDATE referrals   SET pull_updated_at = LEFT(COALESCE(status_updated_at, issued_at), 19)
  WHERE pull_updated_at IS NULL;

-- ---------------------------------------------------------------------------
-- 3. Indexes: every pull query orders and range-scans on this column.
-- ---------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_households_pull  ON households  (pull_updated_at);
CREATE INDEX IF NOT EXISTS idx_persons_pull     ON persons     (pull_updated_at);
CREATE INDEX IF NOT EXISTS idx_visits_pull      ON visits      (pull_updated_at);
CREATE INDEX IF NOT EXISTS idx_assessments_pull ON assessments (pull_updated_at);
CREATE INDEX IF NOT EXISTS idx_referrals_pull   ON referrals   (pull_updated_at);

-- ---------------------------------------------------------------------------
-- 4. Triggers — single-statement bodies, so no DELIMITER gymnastics is needed
--    whether this file runs through the mysql CLI or through node mysql2.
-- ---------------------------------------------------------------------------
CREATE TRIGGER IF NOT EXISTS trg_households_pull_ins BEFORE INSERT ON households
  FOR EACH ROW SET NEW.pull_updated_at = DATE_FORMAT(UTC_TIMESTAMP(), '%Y-%m-%dT%H:%i:%s');
CREATE TRIGGER IF NOT EXISTS trg_households_pull_upd BEFORE UPDATE ON households
  FOR EACH ROW SET NEW.pull_updated_at = DATE_FORMAT(UTC_TIMESTAMP(), '%Y-%m-%dT%H:%i:%s');

CREATE TRIGGER IF NOT EXISTS trg_persons_pull_ins BEFORE INSERT ON persons
  FOR EACH ROW SET NEW.pull_updated_at = DATE_FORMAT(UTC_TIMESTAMP(), '%Y-%m-%dT%H:%i:%s');
CREATE TRIGGER IF NOT EXISTS trg_persons_pull_upd BEFORE UPDATE ON persons
  FOR EACH ROW SET NEW.pull_updated_at = DATE_FORMAT(UTC_TIMESTAMP(), '%Y-%m-%dT%H:%i:%s');

CREATE TRIGGER IF NOT EXISTS trg_visits_pull_ins BEFORE INSERT ON visits
  FOR EACH ROW SET NEW.pull_updated_at = DATE_FORMAT(UTC_TIMESTAMP(), '%Y-%m-%dT%H:%i:%s');
CREATE TRIGGER IF NOT EXISTS trg_visits_pull_upd BEFORE UPDATE ON visits
  FOR EACH ROW SET NEW.pull_updated_at = DATE_FORMAT(UTC_TIMESTAMP(), '%Y-%m-%dT%H:%i:%s');

CREATE TRIGGER IF NOT EXISTS trg_assessments_pull_ins BEFORE INSERT ON assessments
  FOR EACH ROW SET NEW.pull_updated_at = DATE_FORMAT(UTC_TIMESTAMP(), '%Y-%m-%dT%H:%i:%s');
CREATE TRIGGER IF NOT EXISTS trg_assessments_pull_upd BEFORE UPDATE ON assessments
  FOR EACH ROW SET NEW.pull_updated_at = DATE_FORMAT(UTC_TIMESTAMP(), '%Y-%m-%dT%H:%i:%s');

CREATE TRIGGER IF NOT EXISTS trg_referrals_pull_ins BEFORE INSERT ON referrals
  FOR EACH ROW SET NEW.pull_updated_at = DATE_FORMAT(UTC_TIMESTAMP(), '%Y-%m-%dT%H:%i:%s');
CREATE TRIGGER IF NOT EXISTS trg_referrals_pull_upd BEFORE UPDATE ON referrals
  FOR EACH ROW SET NEW.pull_updated_at = DATE_FORMAT(UTC_TIMESTAMP(), '%Y-%m-%dT%H:%i:%s');
