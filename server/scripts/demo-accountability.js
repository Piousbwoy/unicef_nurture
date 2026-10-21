// ============================================================================
// demo-accountability.js — put a district on stage in one command.
//
//   node scripts/demo-accountability.js            seed (idempotent)
//   node scripts/demo-accountability.js --audit    read back what the district holds
//   node scripts/demo-accountability.js --reset    delete only the demo-% rows
//
// WHY THIS EXISTS
// The accountability spine is the part of this app that cannot be demoed by
// seeding data, and that is the point. Consent decisions, access-trail entries
// and data-rights requests are produced by a handset *while a worker works*, and
// the trail's hashes are keyed with a secret that lives in the phone's secure
// storage and is never sent anywhere. A server that could recompute them is a
// server that could forge the trail. So this script seeds only what a district
// would legitimately already hold — the register, the people, and the accounts
// that sign in — and then hands you the ninety seconds that generate the rest.
//
// WHAT IT DELIBERATELY DOES NOT DO
// It does not insert consent_events, access_ledger or data_rights_requests rows.
// Fake hashes in an evidence table would make the demonstration a fiction, and a
// judge who asks "how was that hash produced?" deserves an answer that does not
// require a footnote. The real entries are produced live, by the app, in front of
// them; `--audit` then shows you the district's copy of them.
//
// REGION STRINGS ARE THE WHOLE DEMO
// Households are visible to a worker by region/district scope, and this repo has
// already been burned once by a register that looked empty because one flow wrote
// "Northern" while another wrote "Northern Region". Every row below uses the same
// strings the sign-up wizard writes, and the numbers each family carries are
// derived from those constants so the two can never drift apart silently here.
'use strict';

require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const crypto = require('crypto');

const { pool } = require('../src/db');

// The web build stretches at 500/500 (lib/data/local/user_dao.dart). A native
// debug build uses 1000/1000 and release 20000/120000 — pass the flag to match
// whichever build is on stage, or the PIN will derive a different verifier and
// every login will fail with no useful message.
function arg(name, fallback) {
  const hit = process.argv.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.split('=').slice(1).join('=') : fallback;
}
const RESET = process.argv.includes('--reset');
const AUDIT = process.argv.includes('--audit');
const PIN_ITERS = parseInt(arg('pin-iters', process.env.AUTH_PIN_ITERS || '500'), 10);
const CLOUD_ITERS = parseInt(arg('cloud-iters', process.env.AUTH_CLOUD_ITERS || '500'), 10);

const DOMAIN = 'carebridge_cloud_auth_v1';

function hmac(key, msg) {
  return crypto.createHmac('sha256', key).update(msg).digest();
}

/// Byte-for-byte Credentials.computeCloudVerifierFromPin — the derivation a
/// blank device sends on recovery login, and the only one a script can produce
/// without the phone's on-device pin_hash.
function verifierFromPin(pin, phone, serverSalt) {
  const fpKey = Buffer.from(`first_pass|${serverSalt}|${phone}`, 'utf8');
  let fp = Buffer.from(pin, 'utf8');
  for (let i = 0; i < PIN_ITERS; i++) fp = hmac(fpKey, fp);
  const km = Buffer.from(`${DOMAIN}|${serverSalt}|${phone}`, 'utf8');
  let b = fp;
  for (let i = 0; i < CLOUD_ITERS; i++) b = hmac(km, b);
  return b.toString('base64');
}

const NOW = new Date().toISOString();

// ── The district ────────────────────────────────────────────────────────────
const workers = [
  {
    id: 'demo-worker-amina',
    fullName: 'Amina Fusea',
    phone: '0244000101',
    pin: '1122',
    role: 'frontlineHealthWorker',
    region: 'Northern Region',
    district: 'Tamale Metropolitan',
    community: 'Vittin',
  },
  {
    // A second zone, so that "a worker opened a family she has no recorded
    // relationship with" is a real click in the demo rather than a hypothetical.
    id: 'demo-worker-ibrahim',
    fullName: 'Ibrahim Saddique',
    phone: '0244000102',
    pin: '2233',
    role: 'frontlineHealthWorker',
    region: 'North East Region',
    district: 'East Mamprusi',
    community: 'Walewale',
  },
];

const households = [
  {
    id: 'demo-hh-yeboah',
    name: 'The Yeboah family',
    region: 'Northern Region',
    district: 'Savelugu Municipal',
    community: 'Gushegu',
    landmark: 'Behind the Savelugu market, past the water point',
    createdBy: 'demo-worker-amina',
    headName: 'Kwame Yeboah',
    contactPhone: '0244000103',
    walkingMinutesToFacility: 18,
    familySize: 5,
    hasValidNhis: 1,
    members: [
      {
        id: 'demo-person-abena',
        fullName: 'Abena Yeboah',
        clientType: 'postpartumWoman',
        sex: 'female',
        dateOfBirth: '1999-07-11',
      },
      {
        id: 'demo-person-akwa',
        fullName: 'Akwa Yeboah',
        clientType: 'childUnderFive',
        sex: 'female',
        dateOfBirth: '2025-02-18',
        motherId: 'demo-person-abena',
      },
    ],
  },
  {
    id: 'demo-hh-wumbei',
    name: 'The Wumbei family',
    region: 'North East Region',
    district: 'East Mamprusi',
    community: 'Bbilong',
    landmark: 'Opposite the chief palace',
    createdBy: 'demo-worker-ibrahim',
    headName: 'Abdulai Wumbei',
    contactPhone: '0244000104',
    walkingMinutesToFacility: 42,
    familySize: 7,
    hasValidNhis: 0,
    members: [
      {
        id: 'demo-person-mariama',
        fullName: 'Mariama Wumbei',
        clientType: 'postpartumWoman',
        sex: 'female',
        dateOfBirth: '1998-03-04',
      },
      {
        id: 'demo-person-fuseina',
        fullName: 'Fuseina Abdulai Wumbei',
        clientType: 'childUnderFive',
        sex: 'female',
        dateOfBirth: '2025-01-20',
        motherId: 'demo-person-mariama',
      },
    ],
  },
];

// The family's own account, bound to exactly one household — which is what the
// repository checks before it will hand a family their disclosure.
const caregivers = [
  {
    id: 'demo-caregiver-abena',
    fullName: 'Abena Yeboah',
    phone: '0244000103',
    pin: '3344',
    role: 'caregiver',
    region: 'Northern Region',
    district: 'Savelugu Municipal',
    community: 'Gushegu',
    linkedHouseholdId: 'demo-hh-yeboah',
  },
];

async function upsertAccount(conn, account) {
  const serverSalt = crypto.randomBytes(24).toString('base64url');
  const verifier = verifierFromPin(account.pin, account.phone, serverSalt);
  await conn.execute(
    `INSERT INTO users
       (id, full_name, phone, role, region, district, community,
        preferred_language, linked_household_id, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, 'English', ?, ?)
     ON DUPLICATE KEY UPDATE
       full_name = VALUES(full_name), role = VALUES(role),
       region = VALUES(region), district = VALUES(district),
       community = VALUES(community),
       linked_household_id = VALUES(linked_household_id)`,
    [
      account.id,
      account.fullName,
      account.phone,
      account.role,
      account.region,
      account.district,
      account.community,
      account.linkedHouseholdId || null,
      NOW,
    ]
  );
  await conn.execute(
    `INSERT INTO user_verifiers
       (user_id, server_salt, verifier, device_id, pin_iterations,
        cloud_iterations, created_at, updated_at)
     VALUES (?, ?, ?, 'demo-seed', ?, ?, ?, ?)
     ON DUPLICATE KEY UPDATE
       server_salt = VALUES(server_salt), verifier = VALUES(verifier),
       pin_iterations = VALUES(pin_iterations),
       cloud_iterations = VALUES(cloud_iterations),
       updated_at = VALUES(updated_at)`,
    [account.id, serverSalt, verifier, PIN_ITERS, CLOUD_ITERS, NOW, NOW]
  );
}

async function seed(conn) {
  for (const account of [...workers, ...caregivers]) {
    await upsertAccount(conn, account);
    console.log(`  account  ${account.fullName.padEnd(18)} ${account.phone}  PIN ${account.pin}`);
  }
  for (const hh of households) {
    await conn.execute(
      `INSERT INTO households
         (id, name, region, district, community, created_by, head_name,
          contact_phone, family_size, has_valid_nhis,
          walking_minutes_to_facility, landmark, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE
         name = VALUES(name), region = VALUES(region),
         district = VALUES(district), community = VALUES(community),
         landmark = VALUES(landmark), updated_at = VALUES(updated_at)`,
      [
        hh.id, hh.name, hh.region, hh.district, hh.community, hh.createdBy,
        hh.headName, hh.contactPhone, hh.familySize, hh.hasValidNhis,
        hh.walkingMinutesToFacility, hh.landmark, NOW, NOW,
      ]
    );
    for (const p of hh.members) {
      await conn.execute(
        `INSERT INTO persons
           (id, household_id, full_name, client_type, sex, date_of_birth,
            mother_id, created_at, updated_at, is_active)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1)
         ON DUPLICATE KEY UPDATE
           full_name = VALUES(full_name), client_type = VALUES(client_type),
           sex = VALUES(sex), date_of_birth = VALUES(date_of_birth),
           updated_at = VALUES(updated_at)`,
        [
          p.id, hh.id, p.fullName, p.clientType, p.sex, p.dateOfBirth,
          p.motherId || null, NOW, NOW,
        ]
      );
    }
    console.log(`  register ${hh.name.padEnd(20)} ${hh.region} / ${hh.district}  (${hh.members.length} people)`);
  }
}

async function reset(conn) {
  // Scoped to the demo- prefix on purpose. Nothing here touches records a real
  // handset has pushed, so a demo can be cleared without clearing a district.
  const tables = [
    'persons', 'households', 'data_rights_requests', 'consent_events',
    'access_ledger', 'user_verifiers', 'users',
  ];
  for (const t of tables) {
    // user_verifiers has no id column; its demo rows are the ones whose user_id
    // carries the prefix.
    const column = t === 'user_verifiers' ? 'user_id' : 'id';
    const [r] = await conn.execute(
      `DELETE FROM ${t} WHERE ${column} LIKE 'demo-%'`
    );
    console.log(`  cleared  ${t.padEnd(22)} ${r.affectedRows} row(s)`);
  }
}

async function audit(conn) {
  // The fixture counts answer "did the seed run, and did running it twice
  // duplicate anything?" — which is the question a demo day actually asks.
  const [fixtures] = await conn.execute(
    "SELECT (SELECT COUNT(*) FROM households WHERE id LIKE 'demo-%') AS households, " +
      "(SELECT COUNT(*) FROM persons WHERE id LIKE 'demo-%') AS people, " +
      "(SELECT COUNT(*) FROM users WHERE id LIKE 'demo-%') AS accounts"
  );
  const [ledger] = await conn.execute(
    'SELECT device_id, COUNT(*) AS entries, SUM(flagged = 1) AS flagged ' +
      'FROM access_ledger GROUP BY device_id ORDER BY device_id'
  );
  const [consents] = await conn.execute(
    'SELECT scope, decision, language, COUNT(*) AS events ' +
      'FROM consent_events GROUP BY scope, decision, language ORDER BY scope'
  );
  const [rights] = await conn.execute(
    'SELECT status, request_kind, COUNT(*) AS requests ' +
      'FROM data_rights_requests GROUP BY status, request_kind ORDER BY status'
  );
  const [late] = await conn.execute(
    "SELECT id, subject_person_id, requested_at FROM data_rights_requests " +
      "WHERE status = 'open' AND requested_at < DATE_SUB(NOW(), INTERVAL 30 DAY)"
  );
  console.log('\nWhat the district holds — the copy a lost handset cannot take with it:\n');
  console.log('demo fixture rows:');
  console.table(fixtures);
  console.log('access trail per device (flagged = needs an explanation):');
  console.table(ledger);
  console.log('consent decisions on file:');
  console.table(consents);
  console.log('data-rights requests:');
  console.table(rights);
  console.log(
    late.length
      ? `\n${late.length} request(s) past the 30-day promise:`
      : '\nno request is past the 30-day promise'
  );
  if (late.length) console.table(late);
  console.log(
    '\nNote on verification: the hashes above are recomputed on the HANDSET, with ' +
      'a key in its secure storage that is never transmitted. The server therefore ' +
      'holds an independent COPY, not an independently verifiable chain — which is ' +
      'the correct design and the honest answer if a judge asks.'
  );
}

(async () => {
  const conn = await pool.getConnection();
  try {
    if (RESET) {
      console.log('clearing demo rows only (LIKE \'demo-%\'):\n');
      await reset(conn);
      return;
    }
    if (AUDIT) {
      await audit(conn);
      return;
    }
    console.log(`seeding the district (stretches at ${PIN_ITERS}/${CLOUD_ITERS} — web build default):\n`);
    await seed(conn);
    console.log('\nNow, in the app, in this order — every step writes evidence as it goes:');
    console.log('  1. Sign in as Ibrahim (0244000102 / 2233) on device B. His register shows the Wumbei family.');
    console.log('  2. Search for "Yeboah" — Abena\'s family is in another region, so it is not offered. Ask why: the scope is the answer.');
    console.log('  3. Sign in as Amina (0244000101 / 1122). Open the Yeboah family, then open the Wumbei child through a referral or a walk-in.');
    console.log('     That read is outside her caseload: allowed, and flagged, with a reason she must type.');
    console.log('  4. Open that child\'s record → Chain of custody → the access is there, by name, with its basis.');
    console.log('  5. Sign in as Abena (0244000103 / 3344) → family → Akwa → Who has seen this record.');
    console.log('     She reads Amina\'s access as a sentence, and can hear it spoken.');
    console.log('  6. Ask for a correction from the family page. Then open the Supervision desk on Amina\'s phone: the finding and the request are both queued.');
    console.log('\nProve the tamper-evidence without a stage trick:');
    console.log('  flutter test test/accountability_test.dart --plain-name "access trail"');
    console.log('  (it edits one row and deletes another, and shows the chain breaking at exactly those entries)');
    console.log('\nRead back what the district kept:  node scripts/demo-accountability.js --audit');
    console.log('Clear the demo state again:         node scripts/demo-accountability.js --reset');
  } finally {
    conn.release();
    await pool.end();
  }
})().catch((err) => {
  console.error('demo-accountability failed:', err.message);
  console.error('Is MariaDB up and server/.env correct? (default 127.0.0.1:3306)');
  process.exit(1);
});
