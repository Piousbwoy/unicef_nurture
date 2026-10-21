-- ============================================================================
-- 009_hardening.sql — a protection class, chain anchors, and a read log.
--
-- Three additions to the district's copy, all of them answering a question the
-- accountability spine could not answer on its own.
--
-- 1. persons.sensitivity
--    A record can now be marked as held to a narrower rule than the rest of the
--    register — an HIV result, an adolescent's visit, a disclosure of violence. In
--    a small community the colleague at the next compound may be a neighbour, so
--    "in the same district" is too wide a care relationship for those. The marking
--    lives on the person rather than in a side table so it travels with the row:
--    pull and cloud recovery both intersect server rows against local columns, so
--    a handset that never saw the marking still enforces it. That is the whole
--    point — a protection that only exists on the device that set it protects
--    nothing from the devices that matter.
--
-- 2. ledger_anchors
--    The device's access trail is a hash chain, verified on the handset. What it
--    could not prove to anybody else was the absence of a rewrite: a device that
--    edited its own history could produce a chain that was internally consistent
--    and simply shorter, and the district copy would show the same shortened
--    history, because the rows arrive from that device.
--
--    So every tenth entry, the device commits its position — sequence number, head
--    hash, entry count — to the district, out of band from the entries themselves.
--    History truncated after that contradicts a commitment the device already sent
--    and cannot take back.
--
--    The limit is recorded here as plainly as it should be stated to an auditor:
--    an anchor proves nothing was removed AFTER it was sent. A device determined to
--    lie from its very first entry can anchor a fiction. What it cannot do is
--    un-write an access the district has already been told about. Closing that
--    last gap needs a key the device does not hold alone, which is a design
--    decision for the district's PKI, not something to invent in a migration.
--
-- 3. server_read_log
--    Until now the server recorded only writes (sync_log). But the sharper
--    exposure in a district system is not who changed a record — it is who
--    *downloaded* how many records to a handset that leaves the compound in a
--    pocket. Delta pull and cloud recovery were completely unlogged.
--
--    Deliberately NOT in src/tables.js. That file is the whitelist of tables a
--    device may write; a log a device could write into is a log that can be
--    forged or emptied, so this table has exactly one writer — the server itself.
--
-- Idempotent: safe to run more than once, and matching schema.sql for fresh
-- installs. Run with:
--   node scripts/apply-migration.js migrations/009_hardening.sql
-- ============================================================================

USE carebridge;

-- ---------------------------------------------------------------------------
-- 1. The protection class. NULL means ordinary, and must never be inferred
--    from a missing value on a client that predates this column.
-- ---------------------------------------------------------------------------
ALTER TABLE persons
  ADD COLUMN IF NOT EXISTS sensitivity VARCHAR(32) NULL;

-- ---------------------------------------------------------------------------
-- 2. Chain anchors: one tiny commitment per ten entries, per device.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ledger_anchors (
  id           VARCHAR(96) NOT NULL,
  device_id    VARCHAR(64) NOT NULL,
  seq          BIGINT      NOT NULL,
  entry_hash   VARCHAR(64) NOT NULL,
  entry_count  BIGINT      NOT NULL,
  anchored_at  VARCHAR(40) NOT NULL,
  received_at  DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  -- The checker walks one device's anchors in chain order to see whether the
  -- trail it holds still agrees with what that device admitted at the time.
  KEY idx_anchor_device (device_id, seq)
) ENGINE=InnoDB;

-- Anchors are worthless if the device that sent one can take it back. Sync upserts
-- on the primary key, so a re-push of `device:10` with a different hash would
-- overwrite the original commitment and a rewritten history would anchor cleanly
-- — the exact attack the table exists to detect. A device cannot be trusted to
-- leave its own past alone, so the database refuses it: the anchor table is
-- append-only with no privilege granted to the connection to change that.
DROP TRIGGER IF EXISTS trg_anchor_rows_are_immutable;
CREATE TRIGGER trg_anchor_rows_are_immutable BEFORE UPDATE ON ledger_anchors
FOR EACH ROW
  SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'ledger_anchors is append-only: an anchor cannot be revised';

DROP TRIGGER IF EXISTS trg_anchor_rows_cannot_be_deleted;
CREATE TRIGGER trg_anchor_rows_cannot_be_deleted BEFORE DELETE ON ledger_anchors
FOR EACH ROW
  SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'ledger_anchors is append-only: an anchor cannot be withdrawn';

-- ---------------------------------------------------------------------------
-- 3. Read audit: who took how much of the register, and where they took it to.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS server_read_log (
  id               BIGINT       NOT NULL AUTO_INCREMENT,
  user_id          VARCHAR(64)  NOT NULL,
  role             VARCHAR(32)  NULL,
  route            VARCHAR(32)  NOT NULL,
  region           VARCHAR(96)  NULL,
  district         VARCHAR(96)  NULL,
  community        VARCHAR(96)  NULL,
  household_count  INT          NOT NULL DEFAULT 0,
  person_count     INT          NOT NULL DEFAULT 0,
  row_count        INT          NOT NULL DEFAULT 0,
  watermark        VARCHAR(40)  NULL,
  cursor_position  INT          NULL,
  answered_at      DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_read_user_time (user_id, answered_at),
  KEY idx_read_time (answered_at)
) ENGINE=InnoDB;
