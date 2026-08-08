// CareBridge district sync server — entry point.
//
// A deliberately small surface: one health probe and one authenticated write
// endpoint. The phone POSTs one outbox entry at a time to /api/sync; see
// sync.js for the status-code contract the app relies on.
'use strict';

const express = require('express');
const config = require('./config');
const { ping } = require('./db');
const { requireAuth, requireJwtUser } = require('./auth');
const { handleSync } = require('./sync');
const { handleProfileLookup, handleCaseloadRestore } = require('./recovery');
const { handleChallenge, handleLogin, handleRefresh, handleLogout } = require('./auth_login');

const app = express();

// Assessment payloads embed full care plans as JSON; give them room.
app.use(express.json({ limit: '10mb' }));

// Refuse anything but JSON on write requests (POST/PUT).
app.use((req, res, next) => {
  if (req.path.startsWith('/api/') && (req.method === 'POST' || req.method === 'PUT') && !req.is('application/json')) {
    return res.status(415).json({ ok: false, error: 'Content-Type must be application/json.' });
  }
  next();
});

// The phone's "Test connection" button does a plain GET on the base URL, so
// answer it honestly and without auth (it reveals nothing but "I am alive").
app.get('/', (req, res) => {
  res.status(200).json({ ok: true, service: 'carebridge-sync', version: '1.1.0', auth: 'jwt-per-user + legacy-token-window' });
});

app.get('/health', async (req, res) => {
  try {
    await ping();
    res.status(200).json({ ok: true, database: 'reachable' });
  } catch (err) {
    res.status(503).json({ ok: false, database: 'unreachable', error: err.message });
  }
});

// -------- Auth endpoints (challenge is unauth; login/refresh unauth; logout requires auth) --------
app.get('/api/auth/challenge', handleChallenge);
app.post('/api/auth/challenge', handleChallenge);
app.post('/api/auth/login', handleLogin);
app.post('/api/auth/refresh', handleRefresh);
app.post('/api/auth/logout', requireAuth, handleLogout);

// -------- Authenticated write endpoints --------
// Legacy devices still get through via the global token (if configured); new
// devices use a per-user JWT. Either way the sync_log carries attribution.
app.post('/api/sync', requireAuth, handleSync);

// -------- Recovery endpoints (STRICT: JWT-only, legacy tokens rejected) ---
// Profile & caseload restoration leak patient data; they MUST be attributable.
app.post('/api/restore/lookup', requireJwtUser, handleProfileLookup);
app.get('/api/restore/caseload', requireJwtUser, handleCaseloadRestore);
app.post('/api/restore/caseload', requireJwtUser, handleCaseloadRestore);

// Nothing else exists.
app.use((req, res) => {
  res.status(404).json({ ok: false, error: 'Not found.' });
});

// Last-resort error handler — never leak stack traces to a client.
// eslint-disable-next-line no-unused-vars
app.use((err, req, res, next) => {
  // eslint-disable-next-line no-console
  console.error('unhandled error:', err.message);
  res.status(500).json({ ok: false, error: 'Internal server error.' });
});

async function main() {
  // Fail fast if the database is not reachable, so a misconfigured server never
  // silently accepts-then-loses records.
  try {
    await ping();
    // eslint-disable-next-line no-console
    console.log(`MariaDB at ${config.db.host}:${config.db.port} is reachable.`);
  } catch (err) {
    // eslint-disable-next-line no-console
    console.error(
      `Cannot reach MariaDB at ${config.db.host}:${config.db.port} ` +
        `(${err.message}). Check .env and that the database is running.`
    );
    process.exit(1);
  }

  app.listen(config.port, () => {
    // eslint-disable-next-line no-console
    console.log(`CareBridge sync server listening on port ${config.port}.`);
    // eslint-disable-next-line no-console
    console.log(`Point the phone's Sync settings at http://<this-machine-ip>:${config.port}`);
  });
}

main();
