-- ============================================================================
-- 006_accountability.sql — the consent ledger and the access trail.
--
-- Health data is "special personal data" under Ghana's Data Protection Act 2012
-- (Act 843). The obligation is not to make records hard to reach — a nurse
-- blocked from a patient is a harm the Act does not ask for — it is to be able to
-- justify every access afterwards, and to prove that the record of those accesses
-- was not rewritten by the person being asked about it.
--
-- So this migration adds two append-only tables:
--
--   consent_events   — what each family agreed to, as a history rather than a
--                      flag. A withdrawal is a new row, because the grant that
--                      came before it is the defence for anything done while it
--                      stood.
--   access_ledger    — one row per record access, carrying the purpose and the
--                      lawful basis, plus a hash chain so editing or deleting any
--                      row invalidates every row after it.
--
-- Both are PUSH-ONLY by design: neither is registered in src/pull.js, because an
-- audit trail about who read a patient is itself patient data and must not be
-- downloaded onto every handset in the region to answer a question only a
-- supervisor asks. The district reads it here.
--
-- `access_ledger` is keyed on its globally unique id ONLY. `seq` is meaningful
-- just within one device's own chain — every handset starts at 1 — so it is
-- indexed for walking the chain but never used as a conflict key. See
-- migrations/007, which corrects this file's first revision.
--
-- Idempotent: safe to run more than once, and matching the fresh-install DDL in
-- schema.sql exactly. Run with:
--   node scripts/apply-migration.js migrations/006_accountability.sql
--   node scripts/apply-migration.js migrations/007_ledger_no_seq_collision.sql
-- ============================================================================

USE carebridge;

-- ---------------------------------------------------------------------------
-- 1. What each family decided, and when.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS consent_events (
  id                VARCHAR(64)  NOT NULL,
  subject_person_id VARCHAR(64)  NOT NULL,
  scope             VARCHAR(40)  NOT NULL,
  decision          VARCHAR(24)  NOT NULL,
  notice_version    VARCHAR(32)  NOT NULL,
  language          VARCHAR(24)  NOT NULL DEFAULT 'English',
  voice_artifact    VARCHAR(120) NULL,
  captured_by       VARCHAR(64)  NOT NULL,
  device_id         VARCHAR(64)  NULL,
  witness_name      VARCHAR(160) NULL,
  note              TEXT         NULL,
  occurred_at       VARCHAR(40)  NOT NULL,
  PRIMARY KEY (id),
  KEY idx_consent_subject (subject_person_id, scope, occurred_at)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------------
-- 2. The access trail, verifiable by construction.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS access_ledger (
  id                VARCHAR(64)  NOT NULL,
  seq               BIGINT       NOT NULL,
  actor_id          VARCHAR(64)  NOT NULL,
  actor_role        VARCHAR(32)  NOT NULL,
  device_id         VARCHAR(64)  NULL,
  action            VARCHAR(64)  NOT NULL,
  entity_table      VARCHAR(64)  NOT NULL,
  entity_id         VARCHAR(64)  NOT NULL,
  subject_person_id VARCHAR(64)  NOT NULL,
  purpose           VARCHAR(32)  NOT NULL,
  basis             VARCHAR(32)  NOT NULL,
  note              TEXT         NULL,
  flagged           TINYINT(1)   NOT NULL DEFAULT 0,
  occurred_at       VARCHAR(40)  NOT NULL,
  previous_hash     VARCHAR(64)  NOT NULL,
  entry_hash        VARCHAR(64)  NOT NULL,
  hash_format       VARCHAR(8)   NOT NULL DEFAULT 'v1',
  received_at       DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_ledger_subject (subject_person_id, occurred_at),
  KEY idx_ledger_flagged (flagged, occurred_at),
  KEY idx_ledger_device (device_id, seq)
) ENGINE=InnoDB;
