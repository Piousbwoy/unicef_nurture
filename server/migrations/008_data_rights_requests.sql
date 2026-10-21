-- ============================================================================
-- 008_data_rights_requests.sql — the family's request, held by the district.
--
-- Under Ghana's Data Protection Act 2012 (Act 843) a data subject can ask for
-- their record to be seen, corrected, objected to, erased, or carried away. What
-- makes that a right rather than a polite feature is a deadline the controller
-- can be held to. A deadline is only auditable if the request exists somewhere
-- other than the handset that raised it — because the phone a family used to ask
-- is also the thing they might lose, factory-reset, or (in the worst case) be
-- told had never recorded anything.
--
-- So this is the third accountability table, and it answers the question the
-- other two do not:
--
--   consent_events       — what the family agreed to
--   access_ledger        — who looked, why, and under what law
--   data_rights_requests — what the family asked us to do, and whether we did it
--
-- PUSH-ONLY, like the others. The server is the district's system of record for
-- the obligation; the app's supervision desk reads the copy on its own handset
-- and says so on screen rather than implying district-wide coverage it does not
-- yet have. Extending the delta pull to this table is the follow-up, and it is a
-- real decision, not an oversight: an unanswered request names a family, so
-- downloading the whole district's queue onto every CHPS handset would spread
-- exactly the data the request is trying to protect. The honest shape is a
-- supervisor-scoped pull, and it needs the same thinking the access ledger got.
--
-- UNLIKE the other two, this row is MUTABLE: a request moves from open to
-- answered or refused. Sync upserts on the primary key with last-write-wins and
-- no clock comparison, so if two handsets ever answer the same request, whoever
-- pushes last wins. That is acceptable here and worth stating plainly: only a
-- supervisor with viewCommunityInsights resolves requests, the resolution text is
-- stored on the row, and the access ledger independently records who did what and
-- when. If requests ever become answerable from more than one device at once, this
-- needs a compare-and-set on status rather than a blind overwrite.
--
-- Idempotent: safe to run more than once, and matching the fresh-install DDL in
-- schema.sql exactly. Run with:
--   node scripts/apply-migration.js migrations/008_data_rights_requests.sql
-- ============================================================================

USE carebridge;

CREATE TABLE IF NOT EXISTS data_rights_requests (
  id                VARCHAR(64)  NOT NULL,
  -- Whose right is being exercised. A child's request is raised by the person
  -- holding the phone, so this is the patient, not the account.
  subject_person_id VARCHAR(64)  NOT NULL,
  -- access | rectification | objection | erasure | portability, as the app's
  -- DataRight enum names them.
  request_kind      VARCHAR(32)  NOT NULL,
  -- open | fulfilled | refused. The promise the privacy notice makes is measured
  -- against this column, which is why it is NOT NULL rather than implied by
  -- resolved_at being set.
  status            VARCHAR(24)  NOT NULL,
  requested_at      VARCHAR(40)  NOT NULL,
  -- The account that raised it — which for a family is the caregiver's own user
  -- id, and matters when a request is disputed.
  requested_by      VARCHAR(64)  NOT NULL,
  resolved_at       VARCHAR(40)  NULL,
  -- The answer, in words the family will be given. A refusal with an empty reason
  -- is not an answer, and the desk will not submit one.
  resolution        TEXT         NULL,
  received_at       DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  -- The queue a supervisor reads: open work, oldest first, so the 30-day promise
  -- can be measured by anyone who asks.
  KEY idx_rights_open (status, requested_at),
  KEY idx_rights_subject (subject_person_id, requested_at)
) ENGINE=InnoDB;
