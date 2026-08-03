// Bearer-token authentication for the sync endpoint.
//
// The comparison is constant-time so the server does not leak, through response
// timing, how many leading characters of a guessed token were correct. For a
// health-data endpoint this is cheap insurance and there is no reason not to.
'use strict';

const crypto = require('crypto');
const config = require('./config');

function timingSafeEqual(a, b) {
  const bufA = Buffer.from(String(a), 'utf8');
  const bufB = Buffer.from(String(b), 'utf8');
  if (bufA.length !== bufB.length) {
    // Compare against self to burn a constant amount of time, then fail.
    crypto.timingSafeEqual(bufA, bufA);
    return false;
  }
  return crypto.timingSafeEqual(bufA, bufB);
}

function requireToken(req, res, next) {
  const header = req.headers['authorization'] || '';
  const match = /^Bearer\s+(.+)$/i.exec(header);
  if (!match) {
    return res
      .status(401)
      .json({ ok: false, error: 'Missing Bearer token.' });
  }
  if (!timingSafeEqual(match[1], config.syncApiToken)) {
    return res
      .status(401)
      .json({ ok: false, error: 'Invalid sync token.' });
  }
  return next();
}

module.exports = { requireToken };
