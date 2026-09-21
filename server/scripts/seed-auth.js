// Seed a single authentication credential directly into MariaDB so the
// district sync server can authenticate a phone that is NOT resident in any
// device's local SQLite — i.e. to prove the cloud-recovery login path works.
//
//   node scripts/seed-auth.js --phone=0242940527 --pin=4572
//
// WHY THIS EXISTS
// The app's registration flow enqueues user_verifiers.verifier computed as
//   computeCloudVerifier(localPinHash, phone, serverSalt)   [input = on-device pin_hash]
// but a BLANK-device recovery login posts
//   computeCloudVerifierFromPin(pin, phone, serverSalt)     [input = first_pass stretch of PIN]
// Those two derivations are NOT equal, so a synced registration row can never
// satisfy a blank-device challenge/response (Path A constant-time compare in
// src/auth_login.js). To test server-backed auth we therefore store the value
// the LOGIN path actually sends: computeCloudVerifierFromPin(...).
//
// ITERATION COST MUST MATCH THE CLIENT BUILD. The client picks its stretch cost
// from compile-time flags (lib/data/local/user_dao.dart):
//   kIsWeb          -> first_pass 500,  cloud 500
//   native debug    -> first_pass 1000, cloud 1000
//   native release  -> first_pass 20000, cloud 120000
// CareBridge is launched via the web launch configs, so the default here is the
// WEB cost (500/500). Override with --pin-iters / --cloud-iters for a native build.
'use strict';

require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const crypto = require('crypto');

// --- args -------------------------------------------------------------------
function arg(name, fallback) {
  const hit = process.argv.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.split('=').slice(1).join('=') : fallback;
}

const PHONE = arg('phone', '0242940527').trim();
const PIN = arg('pin', '4572').trim();
const FULL_NAME = arg('name', 'Server Auth Test');
const ROLE = arg('role', 'frontlineHealthWorker');
const REGION = arg('region', 'Northern Region');
const DISTRICT = arg('district', 'Savelugu Municipal');
const COMMUNITY = arg('community', 'Tamale Central');
const PIN_ITERS = parseInt(arg('pin-iters', process.env.AUTH_PIN_ITERS || '500'), 10);
const CLOUD_ITERS = parseInt(arg('cloud-iters', process.env.AUTH_CLOUD_ITERS || '500'), 10);

const DOMAIN = 'carebridge_cloud_auth_v1';

// --- verifier, byte-for-byte the client's computeCloudVerifierFromPin --------
function hmac(keyBuf, msgBuf) {
  return crypto.createHmac('sha256', keyBuf).update(msgBuf).digest();
}
function computeVerifierFromPin(pin, phone, serverSalt) {
  const firstPassKey = Buffer.from(`first_pass|${serverSalt}|${phone}`, 'utf8');
  let firstPass = Buffer.from(pin, 'utf8');
  for (let i = 0; i < PIN_ITERS; i++) firstPass = hmac(firstPassKey, firstPass);
  const keyMaterial = Buffer.from(`${DOMAIN}|${serverSalt}|${phone}`, 'utf8');
  let block = firstPass;
  for (let i = 0; i < CLOUD_ITERS; i++) block = hmac(keyMaterial, block);
  return block.toString('base64'); // standard base64, matches Dart base64.encode
}

async function main() {
  if (!/^\d{4,8}$/.test(PIN)) {
    console.error(`PIN must be 4-8 digits, got "${PIN}".`);
    process.exit(1);
  }
  // 24 random bytes, base64url — same shape the client generates at registration.
  const serverSalt = crypto.randomBytes(24).toString('base64url');
  const verifier = computeVerifierFromPin(PIN, PHONE, serverSalt);
  const now = new Date().toISOString();

  const { pool } = require('../src/db');
  const conn = await pool.getConnection();
  try {
    const [existing] = await conn.execute('SELECT id FROM users WHERE phone = ? LIMIT 1', [PHONE]);
    const userId = existing.length > 0 ? existing[0].id : crypto.randomUUID();

    // Upsert the users row. pin_hash / pin_salt stay NULL by design — the new
    // auth path never uses them.
    await conn.execute(
      `INSERT INTO users
         (id, full_name, phone, role, region, district, community,
          preferred_language, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, 'English', ?)
       ON DUPLICATE KEY UPDATE
         full_name = VALUES(full_name), role = VALUES(role),
         region = VALUES(region), district = VALUES(district),
         community = VALUES(community)`,
      [userId, FULL_NAME, PHONE, ROLE, REGION, DISTRICT, COMMUNITY, now]
    );

    await conn.execute(
      `INSERT INTO user_verifiers
         (user_id, server_salt, verifier, device_id, created_at, updated_at)
       VALUES (?, ?, ?, 'seed-auth', ?, ?)
       ON DUPLICATE KEY UPDATE
         server_salt = VALUES(server_salt), verifier = VALUES(verifier),
         updated_at = VALUES(updated_at)`,
      [userId, serverSalt, verifier, now, now]
    );

    console.log('Seeded credential into MariaDB:');
    console.log('  phone       :', PHONE);
    console.log('  user_id     :', userId);
    console.log('  role        :', ROLE, `(${REGION} / ${DISTRICT} / ${COMMUNITY})`);
    console.log('  server_salt :', serverSalt);
    console.log('  verifier    :', verifier);
    console.log(`  iterations  : first_pass=${PIN_ITERS}, cloud=${CLOUD_ITERS} (web build default = 500/500)`);
    console.log('\nNow start the server (npm start) and sign in with this phone + PIN.');
  } finally {
    conn.release();
    await pool.end();
  }
}

main().catch((err) => {
  console.error('Seed failed:', err.message);
  console.error('Is MariaDB running and server/.env correct? (DB reachable on 127.0.0.1:3306)');
  process.exit(1);
});
