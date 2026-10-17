-- ============================================================================
-- 005_verifier_iterations.sql — advertise the stretching cost per credential.
--
-- The CareBridge client picks its PIN-stretching cost from compile-time flags
-- (lib/data/local/user_dao.dart): web 500/500, native debug 1000/1000, native
-- release 20000/120000. The cloud verifier is an iterated HMAC at exactly that
-- cost, so a replacement handset that assumes its OWN cost derives a different
-- verifier and is rejected — with a bare "Invalid credentials" and no hint why.
--
-- In practice: register in the browser demo, then try to recover the same
-- account on the Android build. Locked out. The whole "register once, recover
-- from any handset" promise depended on this.
--
-- Fix: store the cost the verifier was made at, and hand it back from
-- /api/auth/challenge next to server_salt. Both are non-secret. The client then
-- derives at the advertised cost instead of guessing.
--
-- NULL means "row written before this column existed" and is deliberately not
-- backfilled. We cannot recover the cost after the fact — it is not derivable
-- from the verifier — so the client falls back to its own platform cost, which
-- is exactly the pre-migration behaviour. No existing account is made worse off,
-- and none is silently given a wrong assumption.
--
-- Idempotent: safe to run more than once. For FRESH installs the equivalent DDL
-- is already in schema.sql. The push whitelist lives in src/tables.js, the
-- response in src/auth_login.js (handleChallenge and handleProvisionRegistration)
-- and the client side in lib/data/sync/server_auth_client.dart.
--
-- Run with (the runtime sync user is least-privilege and cannot ALTER, so use an
-- admin account):
--   mysql -u <admin> -p carebridge < migrations/005_verifier_iterations.sql
-- ============================================================================

ALTER TABLE user_verifiers
  ADD COLUMN IF NOT EXISTS pin_iterations   INT NULL AFTER verifier,
  ADD COLUMN IF NOT EXISTS cloud_iterations INT NULL AFTER pin_iterations;
