// Per-user JWT authentication with rate-limited login and a legacy-token
// fallback window during device rollout.
//
// Two paths produce an authenticated request:
//
//  1. Per-user JWT (recommended). POST /api/auth/login with phone+PIN →
//     bcrypt.verify against user_verifiers → access_token (JWT, short-lived,
//     signed with accessSecret) + refresh_token (opaque, stored in DB, long-
//     lived). Access tokens are attached as "Authorization: Bearer <jwt>" on
//     every subsequent request.
//
//  2. Legacy SYNC_API_TOKEN (deprecation-only). If config.syncApiToken is
//     still set, the exact constant-time bearer comparison still works, but
//     every write gets marked as auth_method='legacy_token' with a NULL
//     user_id in sync_log so the district can identify un-upgraded devices.
//
// JWT tokens carry claims that downstream handlers read from req.auth:
//   { sub: user_id, role, region, district, community, facility_name,
//     jti, device_id, exp, iss, aud }
'use strict';

const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const config = require('./config');

function timingSafeEqual(a, b) {
  const bufA = Buffer.from(String(a ?? ''), 'utf8');
  const bufB = Buffer.from(String(b ?? ''), 'utf8');
  if (bufA.length !== bufB.length) {
    crypto.timingSafeEqual(bufA, bufA);
    return false;
  }
  return crypto.timingSafeEqual(bufA, bufB);
}

// --------------------------------------------------------------- Rate limiter
// In-memory sliding-window counter keyed by "ip:phone". Good enough for a
// district sync server behind a single ingress; swap for Redis if we ever
// scale horizontally.
class RateLimiter {
  constructor({ maxAttempts, windowSeconds, lockSeconds }) {
    this.max = maxAttempts;
    this.windowMs = windowSeconds * 1000;
    this.lockMs = lockSeconds * 1000;
    this.attempts = new Map(); // key -> [{ts}, ...]
    this.locks = new Map();    // key -> unlockAt
  }

  _now() { return Date.now(); }

  check(key) {
    const now = this._now();
    const lock = this.locks.get(key);
    if (lock && lock > now) {
      const retrySec = Math.ceil((lock - now) / 1000);
      return { ok: false, retrySec, reason: 'locked' };
    }
    const bucket = (this.attempts.get(key) || []).filter(
      (ts) => now - ts < this.windowMs
    );
    this.attempts.set(key, bucket);
    if (bucket.length >= this.max) {
      const unlock = now + this.lockMs;
      this.locks.set(key, unlock);
      return { ok: false, retrySec: Math.ceil(this.lockMs / 1000), reason: 'rate' };
    }
    return { ok: true };
  }

  record(key) {
    const bucket = this.attempts.get(key) || [];
    bucket.push(this._now());
    this.attempts.set(key, bucket);
  }

  clear(key) {
    this.attempts.delete(key);
    this.locks.delete(key);
  }
}

const rateLimiter = new RateLimiter({
  maxAttempts: config.rate.maxAttempts,
  windowSeconds: config.rate.windowSeconds,
  lockSeconds: config.rate.lockSeconds,
});

// ------------------------------------------------------------------ JWT sign
function signAccessToken(user, { deviceId, jti } = {}) {
  const now = Math.floor(Date.now() / 1000);
  const payload = {
    sub: user.id,
    role: user.role,
    region: user.region,
    district: user.district,
    community: user.community,
    facility_name: user.facility_name || null,
    phone: user.phone,
    device_id: deviceId || null,
  };
  return jwt.sign(payload, config.jwt.accessSecret, {
    issuer: config.jwt.issuer,
    audience: config.jwt.audience,
    jwtid: jti || crypto.randomBytes(12).toString('hex'),
    expiresIn: `${config.jwt.accessTtlMinutes * 60}s`,
    notBefore: now - 5,
  });
}

function signRefreshToken(user, { deviceId } = {}) {
  return crypto.randomBytes(32).toString('hex');
}

function hashRefreshToken(token) {
  return crypto.createHash('sha256').update(String(token)).digest('hex');
}

// ------------------------------------------------------------ Auth middleware
//
// Attaches req.auth = { claims | null, authMethod, legacy: boolean } or
// returns a 401 if no valid credential was presented.
function requireAuth(req, res, next) {
  const header = req.headers['authorization'] || '';
  const match = /^Bearer\s+(.+)$/i.exec(header);

  if (!match) {
    return res.status(401).json({ ok: false, error: 'Missing Bearer token.' });
  }

  const token = match[1];

  // 1. Try JWT decode + verify first
  try {
    const claims = jwt.verify(token, config.jwt.accessSecret, {
      issuer: config.jwt.issuer,
      audience: config.jwt.audience,
    });
    req.auth = {
      claims: {
        userId: claims.sub,
        role: claims.role,
        region: claims.region,
        district: claims.district,
        community: claims.community,
        facilityName: claims.facility_name || null,
        deviceId: claims.device_id || null,
        jti: claims.jti,
      },
      authMethod: 'jwt',
      legacy: false,
    };
    return next();
  } catch (jwtErr) {
    // Not a valid JWT. Fall through and try legacy token before rejecting.
  }

  // 2. Legacy global bearer token (transition-window only)
  if (config.syncApiToken && timingSafeEqual(token, config.syncApiToken)) {
    req.auth = {
      claims: null,
      authMethod: 'legacy_token',
      legacy: true,
    };
    return next();
  }

  return res.status(401).json({ ok: false, error: 'Invalid bearer token.' });
}

// Strict variant: require a real per-user JWT, reject legacy tokens.
// Used for recovery/caseload endpoints where we MUST know the caller.
function requireJwtUser(req, res, next) {
  requireAuth(req, res, () => {
    if (!req.auth || !req.auth.claims) {
      return res.status(401).json({
        ok: false,
        error: 'This endpoint requires per-user authentication. ' +
          'Sign in with your phone and PIN, or update your device.',
      });
    }
    next();
  });
}

module.exports = {
  requireAuth,
  requireToken: requireAuth,
  requireJwtUser,
  signAccessToken,
  signRefreshToken,
  hashRefreshToken,
  rateLimiter,
  timingSafeEqual,
};
