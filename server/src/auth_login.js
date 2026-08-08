// Per-user JWT authentication (v1.1 — compliance with GHS data-privacy policy).
//
// Architecture: On-Device Credentials vs Cloud Verifiers, completely separated:
//
//   * device-local pin_hash / pin_salt:
//       - NEVER cross the network (stripped from users outbox via tables.js whitelist)
//       - never reach the MariaDB users table (post-v1.1 clients always NULL them)
//
//   * user_verifiers table (isolated, separate from synced patient records):
//       - server_salt (24-byte random, per-user, non-secret)
//       - verifier = DOMAIN-SEPARATED ITERATED HMAC-SHA256(
//             key   = "carebridge_cloud_auth_v1" || server_salt || phone,
//             input = either (device_local_pin_hash) [during registration]
//                     OR first_pass_stretch(pin, server_salt) [during blank-device login])
//
// Challenge-response login on a replacement device (no local SQLite):
//   GET  /api/auth/challenge?phone=X  → 200 { user_id, server_salt } (public, unauth)
//   POST /api/auth/login
//          { phone, verifier_response, device_id }
//        → 200 { access_token, refresh_token, user, expires_in }
//
// The client computes the response locally using
// Credentials.computeCloudVerifierFromPin(pin, phone, server_salt). The
// server compares stored verifier constant-time against the response. The
// actual PIN and the device-local pin_hash never traverse the network: the
// client hashes them before sending, and the server never returns a verifier.
//
// Legacy migration path (existing users who have users.pin_hash / pin_salt
// from the old pre-v1.1 sync whitelist):
//   If no user_verifiers row exists AND users.pin_hash / pin_salt are set,
//   we accept a direct verifier submission computed either from the on-device
//   hash (new client, during first sync after upgrade) OR recompute the
//   expected cloud verifier on the fly from the legacy users.pin_hash and a
//   newly-generated server_salt stored into user_verifiers, then NULL the
//   legacy columns. One-time work: user is migrated silently on first login.
//
// POST /api/auth/refresh — exchange a refresh_token for a fresh access_token.
// POST /api/auth/logout — revoke a specific refresh token (or all, for lost device).
'use strict';

const crypto = require('crypto');
const { pool } = require('./db');
const config = require('./config');
const {
  signAccessToken,
  signRefreshToken,
  hashRefreshToken,
  rateLimiter,
} = require('./auth');

const CLOUD_VERIFIER_DOMAIN_SEPARATOR = 'carebridge_cloud_auth_v1';
const CLOUD_VERIFIER_ITERATIONS = 120000;
const DEVICE_PIN_ITERATIONS_RELEASE = 20000;
const DEVICE_PIN_ITERATIONS_DEBUG = 1000;
const DEVICE_PIN_ITERATIONS_WEB = 500;

// Matches the client-side `const _pinIterations` heuristic for the first-pass
// stretch used on blank-device recovery logins (where we do not hold the
// original device pin_hash, we must rebuild from PIN + server_salt).
function devicePinIterations() {
  if (process.env.WEB_BUILD === 'true') return DEVICE_PIN_ITERATIONS_WEB;
  if (process.env.NODE_ENV !== 'production') return DEVICE_PIN_ITERATIONS_DEBUG;
  return DEVICE_PIN_ITERATIONS_RELEASE;
}

// Compute the expected cloud verifier exactly as the client's
// Credentials.computeCloudVerifier() does it — when we already hold the raw
// device local_pin_hash (e.g. legacy migration, or registration sync-in).
function expectedVerifierFromLocalHash(localPinHash, phone, serverSalt) {
  const keyMaterial = `${CLOUD_VERIFIER_DOMAIN_SEPARATOR}|${serverSalt}|${phone}`;
  let block = Buffer.from(localPinHash, 'utf8');
  for (let i = 0; i < CLOUD_VERIFIER_ITERATIONS; i++) {
    block = crypto.createHmac('sha256', keyMaterial).update(block).digest();
  }
  return block.toString('base64');
}

// Compute the expected cloud verifier exactly as the client's
// Credentials.computeCloudVerifierFromPin() does it — used during challenge/
// response recovery login when the client is blank and has to stretch from
// scratch using the public server_salt (the on-device pin_salt is not known).
function expectedVerifierFromPinBlankDevice(pin, phone, serverSalt) {
  const iterFirstPass = devicePinIterations();
  const firstPassKey = `first_pass|${serverSalt}|${phone}`;
  let firstPass = Buffer.from(pin, 'utf8');
  for (let i = 0; i < iterFirstPass; i++) {
    firstPass = crypto.createHmac('sha256', firstPassKey).update(firstPass).digest();
  }
  const keyMaterial = `${CLOUD_VERIFIER_DOMAIN_SEPARATOR}|${serverSalt}|${phone}`;
  let block = firstPass;
  for (let i = 0; i < CLOUD_VERIFIER_ITERATIONS; i++) {
    block = crypto.createHmac('sha256', keyMaterial).update(block).digest();
  }
  return block.toString('base64');
}

function constantTimeEqual(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

function nowIso() { return new Date().toISOString(); }

function scrubUser(u) {
  return {
    id: u.id,
    full_name: u.full_name,
    phone: u.phone,
    role: u.role,
    region: u.region,
    district: u.district,
    community: u.community,
    chps_zone: u.chps_zone,
    facility_name: u.facility_name,
    staff_id: u.staff_id,
    preferred_language: u.preferred_language,
    linked_household_id: u.linked_household_id,
    created_at: u.created_at,
  };
}

async function upsertRefreshToken(conn, token, user, deviceId) {
  const hash = hashRefreshToken(token);
  const exp = new Date(Date.now() + config.jwt.refreshTtlDays * 86400000);
  await conn.execute(
    'INSERT INTO refresh_tokens (token_hash, user_id, device_id, issued_at, expires_at, revoked_at) ' +
      'VALUES (?, ?, ?, ?, ?, NULL) ' +
      'ON DUPLICATE KEY UPDATE user_id = VALUES(user_id), device_id = VALUES(device_id), ' +
      'issued_at = VALUES(issued_at), expires_at = VALUES(expires_at), revoked_at = NULL',
    [hash, user.id, deviceId || null, nowIso(), exp.toISOString()]
  );
  return hash;
}

// Unauthenticated. Returns the public server_salt + user_id so a blank
// replacement device can re-derive the cloud verifier locally. Pin_hash /
// pin_salt are NEVER in the response (we scrub them via the SELECT list).
async function handleChallenge(req, res) {
  const phoneRaw = (req.query && typeof req.query.phone === 'string') ? req.query.phone
    : (req.body && typeof req.body.phone === 'string' ? req.body.phone : '');
  const phone = phoneRaw.trim();
  if (!phone) {
    return res.status(400).json({ ok: false, error: 'Phone number is required.' });
  }
  let conn;
  try {
    conn = await pool.getConnection();
    const [users] = await conn.execute(
      'SELECT id, phone FROM users WHERE phone = ? LIMIT 1',
      [phone]
    );
    if (users.length === 0) {
      await new Promise((r) => setTimeout(r, 180));
      return res.status(404).json({
        ok: false,
        error: 'No account found for this phone number on the main server.',
      });
    }
    const user = users[0];
    const [verifiers] = await conn.execute(
      'SELECT server_salt FROM user_verifiers WHERE user_id = ? LIMIT 1',
      [user.id]
    );
    let serverSalt = verifiers.length > 0 ? verifiers[0].server_salt : null;

    // If the user was created by a legacy client (no user_verifiers row yet,
    // possibly because outbox hasn't synced) and they have users.pin_hash set,
    // generate a server_salt proactively so the first challenge/response can
    // still proceed (legacy migration path inside handleLogin will complete
    // the row insertion once verifier matches).
    if (!serverSalt) {
      const [legacyU] = await conn.execute(
        'SELECT pin_hash FROM users WHERE id = ? LIMIT 1',
        [user.id]
      );
      if (legacyU.length > 0 && legacyU[0].pin_hash) {
        serverSalt = crypto.randomBytes(24).toString('base64url');
        const now = nowIso();
        const stubVerifier = 'pending_' + crypto.randomBytes(16).toString('base64url');
        await conn.execute(
          'INSERT INTO user_verifiers (user_id, server_salt, verifier, created_at, updated_at) ' +
            'VALUES (?, ?, ?, ?, ?) ' +
            'ON DUPLICATE KEY UPDATE server_salt = VALUES(server_salt), updated_at = VALUES(updated_at)',
          [user.id, serverSalt, stubVerifier, now, now]
        );
      }
    }

    if (!serverSalt) {
      return res.status(404).json({
        ok: false,
        error: 'This account has no cloud verifier yet. Sign in once from the ' +
               'original registered device to enable cloud recovery.',
      });
    }

    return res.status(200).json({
      ok: true,
      user_id: user.id,
      phone: user.phone,
      server_salt: serverSalt,
    });
  } catch (err) {
    console.error('challenge failed for phone', phone, ':', err.message);
    return res.status(500).json({ ok: false, error: 'Server error during challenge.' });
  } finally {
    if (conn) conn.release();
  }
}

async function handleLogin(req, res) {
  const body = req.body || {};
  const phone = typeof body.phone === 'string' ? body.phone.trim() : '';
  // The new-compliance challenge/response response (cloud verifier hex/base64,
  // computed on the client from PIN + phone + server_salt using
  // computeCloudVerifierFromPin). Old clients pre-upgrade may still send raw
  // pin; we accept that during the transition window ONLY via the legacy
  // users.pin_hash / pin_salt path, and only if their legacy row actually
  // has those columns set still.
  const verifierResponse = typeof body.verifier_response === 'string'
    ? body.verifier_response
    : '';
  const rawPin = typeof body.pin === 'string' ? body.pin : '';
  const deviceId = typeof body.device_id === 'string' ? body.device_id.trim().slice(0, 64) : null;

  const ip = (req.headers['x-forwarded-for'] || req.socket.remoteAddress || 'unknown').toString().split(',')[0].trim();
  const rk = `${ip}:${phone || 'none'}`;

  const rl = rateLimiter.check(rk);
  if (!rl.ok) {
    rateLimiter.record(rk);
    return res.status(429).json({
      ok: false,
      error: 'Too many sign-in attempts.',
      retry_after_seconds: rl.retrySec,
    });
  }
  rateLimiter.record(rk);

  if (!phone) {
    return res.status(400).json({ ok: false, error: 'Phone number is required.' });
  }
  const hasVerifier = !!verifierResponse;
  const hasRawPin = !!rawPin;
  if (!hasVerifier && !hasRawPin) {
    return res.status(400).json({
      ok: false,
      error: 'Either verifier_response (challenge-response) or pin is required.',
    });
  }
  if (hasVerifier && (verifierResponse.length < 16 || verifierResponse.length > 512)) {
    return res.status(400).json({ ok: false, error: 'verifier_response is malformed.' });
  }
  if (hasRawPin && !/^\d{4,8}$/.test(rawPin)) {
    return res.status(400).json({ ok: false, error: 'PIN must be a 4- to 8-digit numeric code.' });
  }

  let conn;
  try {
    conn = await pool.getConnection();
    const [users] = await conn.execute(
      'SELECT * FROM users WHERE phone = ? LIMIT 1',
      [phone]
    );
    if (users.length === 0) {
      await new Promise((r) => setTimeout(r, 350));
      return res.status(401).json({ ok: false, error: 'Invalid credentials.' });
    }
    const user = users[0];
    const [vRows] = await conn.execute(
      'SELECT * FROM user_verifiers WHERE user_id = ? LIMIT 1',
      [user.id]
    );
    const verifierRow = vRows.length > 0 ? vRows[0] : null;
    let verified = false;
    let usedLegacyRawPinMigration = false;

    // Path A: Challenge-response — client sent a verifier_response (post-v1.1
    // clients on blank devices — this is the standard, compliant path).
    if (hasVerifier && verifierRow && !verifierRow.verifier.startsWith('pending_')) {
      verified = constantTimeEqual(verifierResponse, verifierRow.verifier);
    }

    // Path A2: Challenge-response — legacy row has a stub "pending_" verifier
    // because the original device has not yet synced its user_verifiers outbox,
    // but users.pin_hash / pin_salt are still present. Compute the EXPECTED
    // verifier from users.pin_hash + the server_salt we handed the client on
    // the /challenge step. On match, we persist the real verifier and NULL the
    // legacy pin_hash / pin_salt columns — user is migrated silently.
    if (!verified && hasVerifier && verifierRow && user.pin_hash && user.pin_salt) {
      const expected = expectedVerifierFromLocalHash(user.pin_hash, user.phone, verifierRow.server_salt);
      verified = constantTimeEqual(verifierResponse, expected);
      if (verified) {
        const now = nowIso();
        await conn.execute(
          'UPDATE user_verifiers SET verifier = ?, device_id = COALESCE(?, device_id), updated_at = ? WHERE user_id = ?',
          [expected, deviceId || null, now, user.id]
        );
        await conn.execute(
          'UPDATE users SET pin_hash = NULL, pin_salt = NULL WHERE id = ?',
          [user.id]
        );
        usedLegacyRawPinMigration = true;
      }
    }

    // Path B: legacy client that still sends raw PIN (pre-upgrade). Only
    // honoured if users.pin_hash / pin_salt are set; result is an immediate
    // migration to the user_verifiers row plus scrubbing legacy columns.
    if (!verified && hasRawPin && user.pin_hash && user.pin_salt) {
      const legacyOk = legacyVerifyPinDirect(rawPin, user.pin_salt, user.pin_hash);
      if (legacyOk) {
        const sSalt = (verifierRow && verifierRow.server_salt)
          ? verifierRow.server_salt
          : crypto.randomBytes(24).toString('base64url');
        const expected = expectedVerifierFromLocalHash(user.pin_hash, user.phone, sSalt);
        verified = true;
        usedLegacyRawPinMigration = true;
        const now = nowIso();
        if (verifierRow) {
          await conn.execute(
            'UPDATE user_verifiers SET server_salt = ?, verifier = ?, device_id = COALESCE(?, device_id), updated_at = ? WHERE user_id = ?',
            [sSalt, expected, deviceId || null, now, user.id]
          );
        } else {
          await conn.execute(
            'INSERT INTO user_verifiers (user_id, server_salt, verifier, device_id, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
            [user.id, sSalt, expected, deviceId || null, now, now]
          );
        }
        await conn.execute(
          'UPDATE users SET pin_hash = NULL, pin_salt = NULL WHERE id = ?',
          [user.id]
        );
      }
    }

    if (!verified) {
      await new Promise((r) => setTimeout(r, 300));
      return res.status(401).json({ ok: false, error: 'Invalid credentials.' });
    }

    rateLimiter.clear(rk);

    const access = signAccessToken(user, { deviceId });
    const refresh = signRefreshToken(user, { deviceId });
    await upsertRefreshToken(conn, refresh, user, deviceId);

    return res.status(200).json({
      ok: true,
      access_token: access,
      refresh_token: refresh,
      token_type: 'Bearer',
      expires_in: config.jwt.accessTtlMinutes * 60,
      refresh_expires_days: config.jwt.refreshTtlDays,
      migrated_legacy: usedLegacyRawPinMigration === true,
      user: scrubUser(user),
    });
  } catch (err) {
    console.error('login failed for phone', phone, ':', err.message);
    return res.status(500).json({ ok: false, error: 'Server error during sign-in.' });
  } finally {
    if (conn) conn.release();
  }
}

// Matches client Credentials.hashPin(pin, salt) exactly — only called on the
// legacy path for users that still have users.pin_hash / pin_salt populated
// from pre-v1.1 sync, so we can compute the expected cloud verifier from
// what's stored and migrate them.
function legacyVerifyPinDirect(pin, salt, expectedHash) {
  try {
    const iterations = devicePinIterations();
    let block = Buffer.from(pin, 'utf8');
    const key = Buffer.from(salt, 'utf8');
    for (let i = 0; i < iterations; i++) {
      block = crypto.createHmac('sha256', key).update(block).digest();
    }
    const got = block.toString('base64');
    return constantTimeEqual(got, expectedHash);
  } catch (_) {
    return false;
  }
}

async function handleRefresh(req, res) {
  const body = req.body || {};
  const token = typeof body.refresh_token === 'string' ? body.refresh_token.trim() : '';
  const deviceId = typeof body.device_id === 'string' ? body.device_id.trim().slice(0, 64) : null;
  if (!token) {
    return res.status(400).json({ ok: false, error: 'refresh_token is required.' });
  }
  let conn;
  try {
    conn = await pool.getConnection();
    const hash = hashRefreshToken(token);
    const [rows] = await conn.execute(
      'SELECT * FROM refresh_tokens WHERE token_hash = ? LIMIT 1',
      [hash]
    );
    if (rows.length === 0) {
      return res.status(401).json({ ok: false, error: 'Invalid refresh token.' });
    }
    const rt = rows[0];
    if (rt.revoked_at || new Date(rt.expires_at) < new Date()) {
      return res.status(401).json({ ok: false, error: 'Refresh token expired or revoked.' });
    }
    const [users] = await conn.execute('SELECT * FROM users WHERE id = ? LIMIT 1', [rt.user_id]);
    if (users.length === 0) {
      return res.status(401).json({ ok: false, error: 'Account no longer exists.' });
    }
    const user = users[0];
    const access = signAccessToken(user, { deviceId: deviceId || rt.device_id });
    return res.status(200).json({
      ok: true,
      access_token: access,
      token_type: 'Bearer',
      expires_in: config.jwt.accessTtlMinutes * 60,
    });
  } catch (err) {
    console.error('refresh failed:', err.message);
    return res.status(500).json({ ok: false, error: 'Server error during token refresh.' });
  } finally {
    if (conn) conn.release();
  }
}

async function handleLogout(req, res) {
  const body = req.body || {};
  const token = typeof body.refresh_token === 'string' ? body.refresh_token.trim() : '';
  if (!token) {
    return res.status(400).json({ ok: false, error: 'refresh_token is required.' });
  }
  let conn;
  try {
    conn = await pool.getConnection();
    const hash = hashRefreshToken(token);
    await conn.execute(
      'UPDATE refresh_tokens SET revoked_at = ? WHERE token_hash = ?',
      [nowIso(), hash]
    );
    const claims = req.auth && req.auth.claims;
    if (claims && body.all_devices === true) {
      await conn.execute(
        'UPDATE refresh_tokens SET revoked_at = ? WHERE user_id = ? AND revoked_at IS NULL',
        [nowIso(), claims.userId]
      );
    }
    return res.status(200).json({ ok: true });
  } catch (err) {
    console.error('logout failed:', err.message);
    return res.status(500).json({ ok: false, error: 'Server error during logout.' });
  } finally {
    if (conn) conn.release();
  }
}

module.exports = {
  handleChallenge,
  handleLogin,
  handleRefresh,
  handleLogout,
  expectedVerifierFromLocalHash,
  expectedVerifierFromPinBlankDevice,
  legacyVerifyPinDirect,
  constantTimeEqual,
  CLOUD_VERIFIER_DOMAIN_SEPARATOR,
  CLOUD_VERIFIER_ITERATIONS,
};
