-- ============================================================================
-- 007_ledger_no_seq_collision.sql — an audit row must never overwrite another.
--
-- 006 added access_ledger with TWO conflict keys: the globally unique `id`, and
-- a UNIQUE (device_id, seq). The second one looked like good instinct — it makes a
-- re-pushed entry after a dropped connection update in place instead of
-- duplicating. It does exactly that. It also does something much worse.
--
-- `seq` is only meaningful inside one device's own hash chain: every handset's
-- first trail entry is seq 1. So if the same handset ever writes a *different*
-- entry at a seq it has used before — after a database rebuild, a restored
-- backup, a rolled-forward chain, or simply the next test run — the upsert
-- matches on (device_id, seq) instead of on `id`, keeps the OLD row's primary
-- key, and overwrites the OLD row's contents. One access record silently
-- replaces another, and nothing anywhere reports it.
--
-- That was caught by scripts/verify-caseload.js, not by reading the DDL: the probe
-- asserted that two devices' seq-1 entries coexist, and it found one row where
-- two were expected — with the second run's contents and the first run's id.
--
-- So `id` is the only conflict key. Retry idempotency is preserved (the same entry
-- id updates in place, which is all a retry needs), and no entry can ever land on
-- top of a different one. `idx_ledger_device` stays for walking a device's chain
-- and re-verifying its hashes; it is now plain, not unique.
--
-- An audit store that can lose a line without erroring is worse than no audit
-- store, because it looks complete.
--
-- Idempotent. Run with:
--   node scripts/apply-migration.js migrations/007_ledger_no_seq_collision.sql
-- ============================================================================

USE carebridge;

ALTER TABLE access_ledger DROP INDEX IF EXISTS uq_ledger_device_seq;

-- Plain index for chain traversal and per-device re-verification, with or without
-- the unique version above: IF NOT EXISTS makes this safe either way.
CREATE INDEX IF NOT EXISTS idx_ledger_device ON access_ledger(device_id, seq);
