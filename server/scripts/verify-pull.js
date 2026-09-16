// End-to-end verification of GET /api/pull against a REAL MariaDB.
//
//   node scripts/verify-pull.js        (from the server/ directory)
//
// What it does, in order:
//   1. Skips honestly (exit 0) when .env is missing/incomplete, MariaDB is
//      unreachable, or the configured user may not create the scratch
//      database — CI must not fail because the environment happens to be off.
//      To run fully on a machine whose .env user lacks CREATE privileges,
//      provide elevated credentials via PULL_VERIFY_ADMIN_USER and (optional)
//      PULL_VERIFY_ADMIN_PASSWORD. The admin connection is built directly
//      (bypassing config.js) precisely so a no-password local root account
//      works; it creates the scratch database, grants the normal .env user
//      scratch-scoped access, and drops the database afterwards.
//   2. Creates a scratch database (carebridge_verify_pull), applies
//      schema.sql into it, and seeds two nurses, one caregiver and a few
//      households/persons — including sentinel pin_hash/pin_salt values that
//      must NEVER appear in any response.
//   3. Boots a minimal express app mounting the REAL middleware chain
//      (requireJwtUser) and the REAL handlePull — no product code is mocked.
//   4. Asserts the pull contract: JWT-only access, per-nurse scope
//      ((region, district, community) OR created_by), caregiver household
//      binding, scrubbing of pull_updated_at / pin_hash / pin_salt, the
//      cursor-0 self-profile rider, and delta behaviour driven by the
//      server-side pull_updated_at triggers.
//   5. Drops the scratch database. Nothing outside it is touched.
//
// Exit codes: 0 = PASS or honest SKIP, 1 = FAIL (a real contract break).
'use strict';

const http = require('http');
const path = require('path');

// dotenv with a pinned path so the script works from any working directory.
// Must run BEFORE config.js is required; later dotenv calls do not override
// variables that are already set, so this is the authoritative load.
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

const NEEDED_ENV = [
  'DB_HOST',
  'DB_USER',
  'DB_PASSWORD',
  'JWT_ACCESS_SECRET',
  'JWT_REFRESH_SECRET',
];

function missingEnv() {
  return NEEDED_ENV.filter(
    (k) => !process.env[k] || process.env[k].trim() === ''
  );
}

// The scratch database name is fixed and identifier-safe.
const VERIFY_DB = process.env.PULL_VERIFY_DB || 'carebridge_verify_pull';
if (!/^[A-Za-z0-9_]+$/.test(VERIFY_DB)) {
  console.error(`Refusing to use unsafe scratch database name: ${VERIFY_DB}`);
  process.exit(1);
}

// --------------------------------------------------------------- check ledger
let passed = 0;
let failed = 0;

function check(name, cond, extra) {
  if (cond) {
    passed += 1;
    console.log(`  PASS  ${name}`);
  } else {
    failed += 1;
    const suffix = extra === undefined ? '' : ` -> ${JSON.stringify(extra)}`;
    console.log(`  FAIL  ${name}${suffix}`);
  }
}

function section(title) {
  console.log(`\n${title}`);
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// errno 1044 = ER_DBACCESS_DENIED_ERROR (no privilege on that database),
// 1045 = ER_ACCESS_DENIED_ERROR (bad credentials), 1042 = host not allowed.
function isAccessDenied(err) {
  return (
    err &&
    (err.errno === 1042 ||
      err.errno === 1044 ||
      err.errno === 1045 ||
      err.code === 'ER_DBACCESS_DENIED_ERROR' ||
      err.code === 'ER_ACCESS_DENIED_ERROR' ||
      err.code === 'ER_HOST_NOT_PRIVILEGED')
  );
}

function skipPrivilegeMessage(user) {
  return (
    `SKIP: database user '${user}' may not create or use the scratch ` +
    `database ${VERIFY_DB}. Re-run with elevated credentials, e.g. ` +
    'PULL_VERIFY_ADMIN_USER=root (plus PULL_VERIFY_ADMIN_PASSWORD if root ' +
    'has one); the run then touches only the scratch database.'
  );
}

// Grant the .env product user ALL on the scratch database only. Account
// parts are validated identifiers — never interpolated request input.
async function grantProductUserOnScratch(adminPool, productUser) {
  if (!/^[A-Za-z0-9._%+-]+$/.test(productUser)) {
    throw new Error(`refusing to grant to unusual account name: ${productUser}`);
  }
  let hosts = null;
  try {
    const [rows] = await adminPool.query(
      'SELECT host FROM mysql.user WHERE user = ?',
      [productUser]
    );
    // MariaDB reports the column as `Host` regardless of the case written in
    // the SELECT — pick the key case-insensitively, or a literal `undefined`
    // host would slip through the regex guard below as a valid identifier.
    hosts = rows
      .map((r) => r.Host ?? r.host ?? r.HOST)
      .filter((h) => typeof h === 'string');
  } catch (_) {
    hosts = null; // no visibility into mysql.user — try the common hosts
  }
  if (!hosts || hosts.length === 0) hosts = ['localhost', '%'];
  let lastErr = null;
  for (const host of hosts) {
    if (!/^[A-Za-z0-9._%:-]+$/.test(host)) continue;
    try {
      await adminPool.query(
        `GRANT ALL PRIVILEGES ON \`${VERIFY_DB}\`.* TO '${productUser}'@'${host}'`
      );
      return;
    } catch (err) {
      lastErr = err;
    }
  }
  if (lastErr) throw lastErr;
}

// ------------------------------------------------------------------- fixtures
const T0 = new Date().toISOString();

// pin_hash/pin_salt sentinels: if ANY response contains these strings, the
// scrub contract (never deliver credential material) is broken.
const SENTINEL_HASH = 'legacy-hash-never-delivered';
const SENTINEL_SALT = 'legacy-salt-never-delivered';

function seedUser(over) {
  return {
    id: 'u-verify-x',
    full_name: 'Verify User',
    phone: '+233200000000',
    role: 'fhw',
    region: 'Northern',
    district: 'Savelugu',
    community: 'Diare',
    chps_zone: null,
    facility_name: 'Verify CHPS',
    staff_id: null,
    preferred_language: 'English',
    linked_household_id: null,
    pin_hash: SENTINEL_HASH,
    pin_salt: SENTINEL_SALT,
    created_at: T0,
    ...over,
  };
}

const NURSE_A = seedUser({ id: 'u-nurse-a', full_name: 'Nurse Ama Adjei', phone: '+233201000001' });
const NURSE_B = seedUser({
  id: 'u-nurse-b',
  full_name: 'Nurse Kwame Boateng',
  phone: '+233201000002',
  region: 'Northern',
  district: 'Tamale',
  community: 'Central',
});
const NURSE_C = seedUser({
  id: 'u-nurse-c',
  full_name: 'Nurse Akosua Mensah',
  phone: '+233201000003',
  region: 'Ashanti',
  district: 'Obuasi',
  community: 'Wawase',
});
const MAMA = seedUser({
  id: 'u-mama',
  full_name: 'Fatima Alhassan',
  phone: '+233209000001',
  role: 'caregiver',
  linked_household_id: 'hh-a',
  facility_name: null,
});

function seedHousehold(over) {
  return {
    id: 'hh-x',
    name: 'Verify family',
    region: 'Northern',
    district: 'Savelugu',
    community: 'Diare',
    created_by: 'u-nurse-a',
    head_name: 'Verify Head',
    contact_phone: null,
    latitude: null,
    longitude: null,
    family_size: 4,
    has_valid_nhis: 1,
    walking_minutes_to_facility: 20,
    landmark: null,
    created_at: T0,
    updated_at: T0,
    ...over,
  };
}

// hh-a and hh-b are inside nurses' tuples; hh-c belongs to nurse C only;
// hh-d sits OUTSIDE every tuple here but was created by nurse A, so only the
// `OR created_by = ?` half of the scope predicate may surface it.
const HOUSEHOLDS = [
  seedHousehold({ id: 'hh-a', name: 'Adjei family' }),
  seedHousehold({
    id: 'hh-b',
    name: 'Boateng family',
    district: 'Tamale',
    community: 'Central',
  }),
  seedHousehold({
    id: 'hh-c',
    name: 'Mensah family',
    region: 'Ashanti',
    district: 'Obuasi',
    community: 'Wawase',
    created_by: 'u-nurse-c',
  }),
  seedHousehold({
    id: 'hh-d',
    name: 'Owusu family',
    region: 'Ashanti',
    district: 'Obuasi',
    community: 'Wawase',
    created_by: 'u-nurse-a',
  }),
];

const PERSONS = [
  {
    id: 'p-b1',
    household_id: 'hh-b',
    full_name: 'Kwame Boateng Jr',
    client_type: 'child',
    sex: 'male',
    date_of_birth: '2024-06-02',
    age_years_approx: null,
    phone: null,
    mother_id: null,
    is_dob_estimated: 0,
    nhis_number: null,
    created_at: T0,
    updated_at: T0,
    is_active: 1,
  },
  {
    id: 'p-c1',
    household_id: 'hh-c',
    full_name: 'Mensah relative',
    client_type: 'mother',
    sex: 'female',
    date_of_birth: '1996-01-20',
    age_years_approx: null,
    phone: null,
    mother_id: null,
    is_dob_estimated: 0,
    nhis_number: null,
    created_at: T0,
    updated_at: T0,
    is_active: 1,
  },
];

// ------------------------------------------------------------------ HTTP stub
function requestJson(port, requestPath, token) {
  return new Promise((resolve, reject) => {
    const req = http.request(
      {
        host: '127.0.0.1',
        port,
        path: requestPath,
        method: 'GET',
        headers: token ? { authorization: `Bearer ${token}` } : {},
        timeout: 10000,
      },
      (res) => {
        let raw = '';
        res.setEncoding('utf8');
        res.on('data', (chunk) => {
          raw += chunk;
        });
        res.on('end', () => {
          let body = null;
          try {
            body = JSON.parse(raw);
          } catch (_) {
            /* non-JSON body keeps raw inspectable */
          }
          resolve({ status: res.statusCode, body, raw });
        });
      }
    );
    req.on('timeout', () => req.destroy(new Error('request timed out')));
    req.on('error', reject);
    req.end();
  });
}

function idsOf(rows) {
  return rows.map((r) => r.id).sort();
}

// Scan a whole parsed payload (recursively) for a key that must not exist.
function payloadContainsKey(value, key) {
  if (Array.isArray(value)) return value.some((v) => payloadContainsKey(v, key));
  if (value && typeof value === 'object') {
    return (
      Object.prototype.hasOwnProperty.call(value, key) ||
      Object.values(value).some((v) => payloadContainsKey(v, key))
    );
  }
  return false;
}

// schema.sql creates/uses the production database by name; rewrite those two
// statements to the scratch database before applying.
function schemaStatementsFor(dbName) {
  const fs = require('fs');
  // Normalize CRLF (this repo checks out with \r\n on Windows): JS `.` and `$`
  // both stop at \r, which would silently defeat the per-line comment strip
  // below and let comment text flow into the executed statements.
  const rawSql = fs
    .readFileSync(path.join(__dirname, '..', 'schema.sql'), 'utf8')
    .replace(/^\uFEFF/, '')
    .replace(/\r\n/g, '\n');
  const noComments = rawSql
    .split('\n')
    .map((line) => line.replace(/(^|\s)--.*$/, '$1'))
    .join('\n')
    .replace(/CREATE DATABASE IF NOT EXISTS\s+`?\w+`?/i, `CREATE DATABASE IF NOT EXISTS \`${dbName}\``)
    .replace(/USE\s+`?\w+`?\s*;/i, `USE \`${dbName}\`;`);
  return noComments
    .split(';')
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
}

// ----------------------------------------------------------------------- main
async function main() {
  const missing = missingEnv();
  if (missing.length > 0) {
    console.log(
      'SKIP: server/.env is missing required variables ' +
        `(${missing.join(', ')}). Copy .env.example to .env to enable ` +
        'the live pull verification.'
    );
    process.exit(0);
  }

  // The pull check must never write into the production database: DB_NAME is
  // redirected to the scratch database before the server modules load, and a
  // scratch-scoped GRANT lets the normal .env user work inside it. Elevated
  // PULL_VERIFY_ADMIN_USER/PASSWORD (when given) are used directly for the
  // admin connection — bypassing config.js, whose required() cannot express
  // a no-password account (the common local MariaDB root setup).
  process.env.DB_NAME = VERIFY_DB;
  const config = require('../src/config');
  const mysql = require('mysql2/promise');

  const adminCreds = {
    host: config.db.host,
    port: config.db.port,
    user: (process.env.PULL_VERIFY_ADMIN_USER || '').trim() || config.db.user,
    password:
      process.env.PULL_VERIFY_ADMIN_PASSWORD !== undefined
        ? process.env.PULL_VERIFY_ADMIN_PASSWORD
        : config.db.password,
  };

  // Admin pool WITHOUT a database: reachability probe + CREATE/DROP database.
  const admin = mysql.createPool({
    ...adminCreds,
    connectionLimit: 2,
    connectTimeout: 4000,
  });

  try {
    await Promise.race([
      admin.query('SELECT 1'),
      sleep(5000).then(() => {
        throw new Error('MariaDB probe timed out after 5s');
      }),
    ]);
  } catch (err) {
    console.log(
      `SKIP: MariaDB probe failed (${err.message}). The server is not ` +
        'reachable, or the credentials were rejected.'
    );
    await admin.end().catch(() => {});
    process.exit(0);
  }

  // From here on, failures are real FAILs: the database is up, the product
  // under test must behave. The two exceptions below stay SKIPs: both are
  // environment privilege gaps (the sync user is usually granted ALL on
  // carebridge.* only), not defects in the code under test.
  let server = null;
  let serverPort = 0;
  try {
    try {
      await admin.query(
        `CREATE DATABASE IF NOT EXISTS \`${VERIFY_DB}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci`
      );
    } catch (err) {
      if (isAccessDenied(err)) {
        console.log(skipPrivilegeMessage(config.db.user));
        await admin.end().catch(() => {});
        process.exit(0);
      }
      throw err;
    }

    // The scratch database exists but the .env product user has no rights on
    // it (it is usually granted ALL on carebridge.* only). Grant it
    // scratch-scoped access so the REAL product pool can run the test; the
    // grant is scoped to this database and vanishes with it on DROP.
    if (adminCreds.user !== config.db.user) {
      try {
        await grantProductUserOnScratch(admin, config.db.user);
      } catch (err) {
        console.log(
          skipPrivilegeMessage(config.db.user) + ` (grant failed: ${err.message})`
        );
        await admin.end().catch(() => {});
        process.exit(0);
      }
    }

    // Probe with the REAL product credentials — a creator without usable
    // grants ON the new database would otherwise fail mid-run.
    const probe = mysql.createPool({
      host: config.db.host,
      port: config.db.port,
      user: config.db.user,
      password: config.db.password,
      database: VERIFY_DB,
      connectionLimit: 1,
      connectTimeout: 4000,
    });
    try {
      await probe.query('SELECT 1');
    } catch (err) {
      if (isAccessDenied(err)) {
        console.log(skipPrivilegeMessage(config.db.user));
        await probe.end().catch(() => {});
        await admin.end().catch(() => {});
        process.exit(0);
      }
      throw err;
    }
    await probe.end().catch(() => {});

    // Load the real product modules — the scratch DB now exists and the
    // configured user may use it, so the lazily-connecting db.js pool is
    // safe to use.
    const { pool } = require('../src/db');
    const { signAccessToken, requireJwtUser } = require('../src/auth');
    const { handlePull } = require('../src/pull');
    const express = require('express');

    section(`Applying schema.sql into ${VERIFY_DB}`);
    for (const stmt of schemaStatementsFor(VERIFY_DB)) {
      await pool.query(stmt);
    }
    console.log('  ok    schema applied');

    section('Seeding scratch data');
    for (const u of [NURSE_A, NURSE_B, NURSE_C, MAMA]) {
      await pool.query('INSERT INTO users SET ?', u);
    }
    for (const h of HOUSEHOLDS) {
      await pool.query('INSERT INTO households SET ?', h);
    }
    for (const p of PERSONS) {
      await pool.query('INSERT INTO persons SET ?', p);
    }
    console.log('  ok    4 users, 4 households, 2 persons inserted');

    const [markerRows] = await pool.query(
      'SELECT id, pull_updated_at FROM households ORDER BY id'
    );
    const stampedList = markerRows.map((r) => r.id).join(',');
    const allStamped = markerRows.every((r) => r.pull_updated_at != null);
    check(
      'BEFORE INSERT triggers stamp pull_updated_at on every seeded household',
      allStamped && markerRows.length === HOUSEHOLDS.length,
      stampedList
    );

    section('Booting minimal express app with the REAL pull chain');
    const app = express();
    app.get('/api/pull', requireJwtUser, handlePull);
    await new Promise((resolve) => {
      server = app.listen(0, () => resolve());
    });
    serverPort = server.address().port;
    console.log(`  ok    listening on 127.0.0.1:${serverPort}`);

    const tokenFor = (user) => signAccessToken(user, { deviceId: 'verify-device' });
    const tokenA = tokenFor(NURSE_A);
    const tokenB = tokenFor(NURSE_B);
    const tokenMama = tokenFor(MAMA);

    // ---- 1. JWT-only gate
    section('Contract: authentication');
    const anon = await requestJson(serverPort, '/api/pull');
    check('pull without a bearer token is rejected with 401', anon.status === 401, anon.status);

    // Watermark determinism: the seed markers were stamped at t0; give the
    // clock >1s of separation so since = server_time - 1s lands strictly
    // after every seeded marker's second. (An equal-second marker is the
    // shorter string, so it sorts before the millisecond `since` and stays
    // out of the delta pulls — but only once the seconds differ at all.)
    await sleep(1200);

    // ---- 2. Full pull as nurse A
    section('Contract: FHW scope ((region, district, community) OR created_by)');
    const pullA = await requestJson(serverPort, '/api/pull', tokenA);
    check('full pull returns 200', pullA.status === 200, pullA.status);
    check('response body has ok=true', pullA.body && pullA.body.ok === true);
    check(
      'server_time is millisecond-precision ISO-8601 UTC',
      !!pullA.body &&
        /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(pullA.body.server_time || ''),
      pullA.body && pullA.body.server_time
    );
    check(
      'scoped_to names the caller (user_id, role)',
      !!pullA.body &&
        pullA.body.scoped_to &&
        pullA.body.scoped_to.user_id === 'u-nurse-a' &&
        pullA.body.scoped_to.role === 'fhw',
      pullA.body && pullA.body.scoped_to
    );
    check(
      'nurse A sees hh-a and hh-b (tuple) and hh-d (created_by)',
      !!pullA.body && JSON.stringify(idsOf(pullA.body.data.households)) === JSON.stringify(['hh-a', 'hh-b', 'hh-d']),
      pullA.body && idsOf(pullA.body.data.households)
    );
    check(
      'nurse A never sees hh-c (other nurse, other tuple)',
      !!pullA.body && !idsOf(pullA.body.data.households).includes('hh-c')
    );
    check(
      'persons arrive through the household subquery (p-b1 only)',
      !!pullA.body && JSON.stringify(idsOf(pullA.body.data.persons)) === JSON.stringify(['p-b1']),
      pullA.body && idsOf(pullA.body.data.persons)
    );
    check(
      'cursor 0 rides the caller profile (users self-row)',
      !!pullA.body && pullA.body.data.users && pullA.body.data.users.id === 'u-nurse-a',
      pullA.body && pullA.body.data.users
    );
    check(
      'self-row carries the profile but never credential columns',
      !!pullA.body &&
        pullA.body.data.users &&
        pullA.body.data.users.full_name === NURSE_A.full_name &&
        !('pin_hash' in pullA.body.data.users) &&
        !('pin_salt' in pullA.body.data.users)
    );
    check(
      'no row anywhere in the payload carries pull_updated_at',
      !!pullA.body && !payloadContainsKey(pullA.body, 'pull_updated_at')
    );
    check(
      'sentinel pin material never crosses the wire',
      !!pullA.raw &&
        !pullA.raw.includes(SENTINEL_HASH) &&
        !pullA.raw.includes(SENTINEL_SALT)
    );

    // ---- 3. Full pull as nurse B (narrower tuple)
    const pullB = await requestJson(serverPort, '/api/pull', tokenB);
    check(
      'nurse B (Northern/Tamale/Central) sees exactly hh-b',
      pullB.status === 200 &&
        pullB.body &&
        JSON.stringify(idsOf(pullB.body.data.households)) === JSON.stringify(['hh-b']),
      pullB.body && idsOf(pullB.body.data.households || [])
    );
    check(
      'nurse B does NOT inherit nurse A rows outside her tuple',
      !!pullB.body &&
        !idsOf(pullB.body.data.households).includes('hh-a') &&
        !idsOf(pullB.body.data.households).includes('hh-d') &&
        !idsOf(pullB.body.data.households).includes('hh-c')
    );

    // ---- 4. Caregiver scope
    section('Contract: caregiver household binding');
    const pullMama = await requestJson(serverPort, '/api/pull', tokenMama);
    check(
      'caregiver sees exactly her bound household',
      pullMama.status === 200 &&
        pullMama.body &&
        JSON.stringify(idsOf(pullMama.body.data.households)) === JSON.stringify(['hh-a']),
      pullMama.body && idsOf(pullMama.body.data.households || [])
    );
    check(
      'caregiver scoped_to exposes linked_household_id and no region tuple',
      !!pullMama.body &&
        pullMama.body.scoped_to &&
        pullMama.body.scoped_to.linked_household_id === 'hh-a' &&
        pullMama.body.scoped_to.region === null,
      pullMama.body && pullMama.body.scoped_to
    );

    // ---- 5. Delta pull
    section('Contract: delta pull via server-side triggers');
    // Seed markers landed at t0; the full pull above happened >= 1.2s later,
    // so (server_time - 1s) is strictly after every seeded marker's second.
    const st1 = pullA.body.server_time;
    const since1 = new Date(Date.parse(st1) - 1000).toISOString();
    const deltaEmpty = await requestJson(
      serverPort,
      `/api/pull?since=${encodeURIComponent(since1)}`,
      tokenA
    );
    check(
      'delta pull with since=server_time-1s delivers zero clinical rows',
      deltaEmpty.status === 200 &&
        deltaEmpty.body &&
        ['households', 'persons', 'visits', 'assessments', 'referrals'].every(
          (t) => Array.isArray(deltaEmpty.body.data[t]) && deltaEmpty.body.data[t].length === 0
        ),
      deltaEmpty.body &&
        JSON.stringify(
          Object.fromEntries(
            ['households', 'persons', 'visits', 'assessments', 'referrals'].map((t) => [
              t,
              (deltaEmpty.body.data[t] || []).length,
            ])
          )
        )
    );
    check(
      'self-profile still rides the first delta page',
      !!deltaEmpty.body && deltaEmpty.body.data.users && deltaEmpty.body.data.users.id === 'u-nurse-a'
    );

    await sleep(1100); // guarantee hh-new stamps strictly after since1
    const hhNew = seedHousehold({ id: 'hh-new', name: 'Delta family' });
    await pool.query('INSERT INTO households SET ?', hhNew);
    const deltaNew = await requestJson(
      serverPort,
      `/api/pull?since=${encodeURIComponent(since1)}`,
      tokenA
    );
    check(
      'a row inserted after the watermark arrives on the next delta pull',
      deltaNew.status === 200 &&
        deltaNew.body &&
        JSON.stringify(idsOf(deltaNew.body.data.households)) === JSON.stringify(['hh-new']),
      deltaNew.body && idsOf(deltaNew.body.data.households || [])
    );
    check(
      'single-row delta reports has_more=false and next_cursor=null',
      !!deltaNew.body && deltaNew.body.has_more === false && deltaNew.body.next_cursor === null,
      deltaNew.body && { has_more: deltaNew.body.has_more, next_cursor: deltaNew.body.next_cursor }
    );
    check(
      'delta rows are scrubbed of pull_updated_at too',
      !!deltaNew.body && !payloadContainsKey(deltaNew.body, 'pull_updated_at')
    );
  } catch (err) {
    failed += 1;
    console.error(`\nFAIL  unexpected error: ${err.message}`);
    if (err.stack) console.error(err.stack.split('\n').slice(0, 4).join('\n'));
  } finally {
    if (server) {
      await new Promise((resolve) => server.close(resolve)).catch(() => {});
    }
    try {
      // End the product pool first so it releases its connections, then drop.
      const dbMod = require.cache[require.resolve('../src/db')];
      if (dbMod) await dbMod.exports.pool.end().catch(() => {});
      await admin
        .query(`DROP DATABASE IF EXISTS \`${VERIFY_DB}\``)
        .catch((e) => console.warn(`warning: could not drop ${VERIFY_DB}: ${e.message}`));
    } catch (_) {
      /* best-effort cleanup; never masks the run result */
    }
    await admin.end().catch(() => {});
  }

  section('Result');
  console.log(`${passed} passed, ${failed} failed.`);
  if (failed > 0) {
    console.log('The pull contract is BROKEN — do not ship.');
    process.exit(1);
  }
  console.log('The pull contract holds against a live MariaDB.');
  process.exit(0);
}

main().catch((err) => {
  console.error('verify-pull crashed:', err.message);
  process.exit(1);
});
