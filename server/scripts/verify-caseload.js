// Proves the cross-worker caseload, over HTTP only.
//
// The claim the judges asked for, in one sentence: Nurse A registers a family on
// her handset in Savelugu, and Nurse B — a DIFFERENT nurse on a DIFFERENT handset,
// working a DIFFERENT district the next day — can pull that family and find the
// child by name. A third nurse in another region must never receive it at all.
//
// This used to fail silently. The server scoped a pull to the exact
// (region, district, community) tuple while the app's own register is region-wide,
// so a colleague's rows simply never crossed the wire: the search was empty and
// no error was raised. The fix lives in pull.js householdScope() and its twin in
// recovery.js; this script is the proof, not a comment claiming it.
//
// Every step goes through the public API — nothing is written into MariaDB by
// hand — so it exercises exactly what two phones do.
//
//   node scripts/verify-caseload.js
//
'use strict';

require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const crypto = require('crypto');
const { auditAnchors } = require('../src/anchors');

const BASE = process.env.BASE || `http://localhost:${process.env.PORT || 3000}`;
const DOMAIN = 'carebridge_cloud_auth_v1';
// Web build cost (lib/data/local/user_dao.dart: kIsWeb -> 500/500).
const PIN_ITERS = parseInt(process.env.PIN_ITERS || '500', 10);
const CLOUD_ITERS = parseInt(process.env.CLOUD_ITERS || '500', 10);

let activeBase = BASE;

function hmac(key, msg) {
  return crypto.createHmac('sha256', key).update(msg).digest();
}

/// Byte-for-byte Credentials.computeCloudVerifierFromPin — the only derivation a
/// handset can produce without the on-device pin_hash.
function verifierFromPin(pin, phone, serverSalt) {
  const fpKey = Buffer.from(`first_pass|${serverSalt}|${phone}`, 'utf8');
  let fp = Buffer.from(pin, 'utf8');
  for (let i = 0; i < PIN_ITERS; i++) fp = hmac(fpKey, fp);
  const km = Buffer.from(`${DOMAIN}|${serverSalt}|${phone}`, 'utf8');
  let b = fp;
  for (let i = 0; i < CLOUD_ITERS; i++) b = hmac(km, b);
  return b.toString('base64');
}

async function call(method, path, body, token) {
  const headers = {};
  if (body) headers['Content-Type'] = 'application/json; charset=utf-8';
  if (token) headers.Authorization = `Bearer ${token}`;
  const res = await fetch(`${activeBase}${path}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });
  let json = {};
  try {
    json = await res.json();
  } catch (_) {
    /* status is what matters */
  }
  return { status: res.status, json };
}

const results = [];
function check(name, ok, detail) {
  results.push({ name, ok });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? `  — ${detail}` : ''}`);
}

// Node resolves `localhost` to ::1 first while Express binds IPv4, so a bare
// "fetch failed" can mean nothing worse than an address-family mismatch.
async function resolveBase() {
  const candidates = [BASE];
  if (/localhost/.test(BASE)) {
    candidates.push(BASE.replace('localhost', '127.0.0.1'));
    candidates.push(BASE.replace('localhost', '[::1]'));
  }
  for (const url of candidates) {
    try {
      if ((await fetch(`${url}/health`, { method: 'GET' })).status === 200) return url;
    } catch (_) {
      /* next family */
    }
  }
  return null;
}

/**
 * Create a worker's account through the bootstrap route and sign in on her own
 * handset, returning the JWT every later call is authenticated with.
 */
async function provisionAndLogin(profile) {
  const userId = crypto.randomUUID();
  const serverSalt = crypto.randomBytes(24).toString('base64url');
  const pin = profile.pin;
  const reg = await call('POST', '/api/auth/register', {
    user_id: userId,
    phone: profile.phone,
    server_salt: serverSalt,
    verifier: verifierFromPin(pin, profile.phone, serverSalt),
    full_name: profile.fullName,
    role: 'frontlineHealthWorker',
    region: profile.region,
    district: profile.district,
    community: profile.community,
    preferred_language: 'English',
    device_id: 'verify-caseload-cli',
    pin_iterations: PIN_ITERS,
    cloud_iterations: CLOUD_ITERS,
  });
  if (reg.status !== 201) {
    throw new Error(`provision ${profile.phone} failed: ${reg.status} ${JSON.stringify(reg.json)}`);
  }
  const ch = await call('GET', `/api/auth/challenge?phone=${encodeURIComponent(profile.phone)}`);
  if (ch.status !== 200) {
    throw new Error(`challenge ${profile.phone} failed: ${ch.status} ${JSON.stringify(ch.json)}`);
  }
  const login = await call('POST', '/api/auth/login', {
    phone: profile.phone,
    verifier_response: verifierFromPin(pin, profile.phone, ch.json.server_salt),
    device_id: 'verify-caseload-cli',
  });
  if (login.status !== 200 || !login.json.access_token) {
    throw new Error(`login ${profile.phone} failed: ${login.status} ${JSON.stringify(login.json)}`);
  }
  return { userId, token: login.json.access_token, ...profile };
}

/** One record, pushed the way OutboxDao enqueues it: one entity per request. */
async function push(token, entityTable, entityId, payload, operation = 'insert') {
  return call(
    'POST',
    '/api/sync',
    {
      entity_table: entityTable,
      entity_id: entityId,
      operation,
      payload,
      client_version: 'verify-caseload',
    },
    token
  );
}

/**
 * A whole pull session, paged the way PullService pages it: follow next_cursor
 * until has_more is false. A single page is not enough — rows stream oldest
 * first in 200-row pages, so on a database that has seen real use the newest
 * record (the one under test) sits on the LAST page, and a one-page check would
 * report "missing" for a row the app would in fact receive.
 */
async function pullAll(token, since) {
  const data = {
    households: [],
    persons: [],
    visits: [],
    assessments: [],
    referrals: [],
    care_requests: [],
  };
  const seenKeys = new Set();
  let cursor = 0;
  let serverTime = null;
  for (let page = 0; page < 100; page++) {
    const qs = new URLSearchParams({ cursor: String(cursor) });
    if (since) qs.set('since', since);
    const res = await call('GET', `/api/pull?${qs}`, null, token);
    if (res.status !== 200 || !res.json.ok) {
      return { status: res.status, data, serverTime, pages: page };
    }
    if (page === 0) serverTime = res.json.server_time;
    for (const table of Object.keys(data)) {
      data[table].push(...((res.json.data && res.json.data[table]) || []));
    }
    // Record any table the server starts sending that this script does not model,
    // so a surprise addition shows up as a failed check rather than as data the
    // script quietly drops.
    for (const key of Object.keys((res.json.data || {}))) {
      seenKeys.add(key);
    }
    if (!res.json.has_more)
      return { status: 200, data, serverTime, pages: page + 1, seenKeys };
    cursor = res.json.next_cursor;
  }
  return { status: 200, data, serverTime, pages: 100, seenKeys };
}

(async () => {
  const resolved = await resolveBase();
  if (!resolved) {
    console.error(`no server answered /health on ${BASE} (or its 127.0.0.1 variant)`);
    console.error('start it with:  cd server; node src/index.js');
    process.exit(1);
  }
  activeBase = resolved;

  const stamp = Date.now().toString().slice(-8);
  const now = new Date().toISOString();

  // Four nurses, two regions. B deliberately spells the region the SHORT way
  // ('Northern'), which is exactly what a recovery-created account writes, so the
  // tolerant match is exercised rather than assumed. C and D work two different
  // districts of North East, so the same promise is proven in a second region
  // and the privacy boundary is checked in both directions.
  const nurseA = await provisionAndLogin({
    phone: `05${stamp}01`,
    pin: '4417',
    fullName: 'Nurse A — Savelugu',
    region: 'Northern Region',
    district: 'Savelugu Municipal',
    community: 'Gushegu',
  });
  const nurseB = await provisionAndLogin({
    phone: `05${stamp}02`,
    pin: '5528',
    fullName: 'Nurse B — Tamale',
    region: 'Northern',
    district: 'Tamale Metropolitan',
    community: 'Vittin',
  });
  const nurseC = await provisionAndLogin({
    phone: `05${stamp}03`,
    pin: '6639',
    fullName: 'Nurse C — Walewale',
    region: 'North East Region',
    district: 'West Mamprusi Municipal',
    community: 'Walewale',
  });
  const nurseD = await provisionAndLogin({
    phone: `05${stamp}04`,
    pin: '7741',
    fullName: 'Nurse D — Nalerigu',
    region: 'North East Region',
    district: 'East Mamprusi Municipal',
    community: 'Nalerigu',
  });

  const householdId = `hh-case-${stamp}`;
  const personId = `p-case-${stamp}`;
  const referralId = `r-case-${stamp}`;
  // referrals.assessment_id is NOT NULL in the server schema (a referral always
  // comes out of an assessment), and there is no foreign key on it, so the
  // script names the assessment without replaying the whole clinical record.
  const assessmentId = `a-case-${stamp}`;
  const childName = `Abigail ${nurseA.district.split(' ')[0]} Kambilia`;

  console.log(
    `target ${activeBase}\n` +
      `  A ${nurseA.userId} (${nurseA.region} / ${nurseA.district})\n` +
      `  B ${nurseB.userId} (${nurseB.region} / ${nurseB.district})\n` +
      `  C ${nurseC.userId} (${nurseC.region} / ${nurseC.district})\n` +
      `  D ${nurseD.userId} (${nurseD.region} / ${nurseD.district})\n`
  );

  // ── 1. Nurse A registers a family and an ongoing referral, then pushes ──────
  const pushHh = await push(nurseA.token, 'households', householdId, {
    id: householdId,
    name: 'The Kambilia family',
    region: nurseA.region,
    district: nurseA.district,
    community: nurseA.community,
    head_name: 'Abanga Kambilia',
    contact_phone: '0244000000',
    landmark: 'behind the old clinic',
    created_by: nurseA.userId,
    created_at: now,
    updated_at: now,
  });
  const pushPerson = await push(nurseA.token, 'persons', personId, {
    id: personId,
    household_id: householdId,
    full_name: childName,
    client_type: 'childUnderFive',
    sex: 'F',
    date_of_birth: '2024-06-12',
    created_at: now,
    updated_at: now,
    is_active: 1,
  });
  check(
    "nurse A can push a family she registered (2xx both rows)",
    pushHh.status < 300 && pushPerson.status < 300,
    `household ${pushHh.status}, person ${pushPerson.status}`
  );

  const pushRef = await push(nurseA.token, 'referrals', referralId, {
    id: referralId,
    reference_code: `CB-${stamp.toUpperCase()}`,
    person_id: personId,
    assessment_id: assessmentId,
    facility_name: 'Tamale Teaching Hospital',
    reason: 'Fast breathing needing assessment',
    urgency: 'sameDay',
    issued_by: nurseA.userId,
    issued_at: now,
    status: 'issued',
    status_updated_at: now,
    sync_state: 'synced',
  });
  check(
    'nurse A can push an ongoing referral for that child (2xx)',
    pushRef.status < 300,
    `${pushRef.status} ${JSON.stringify(pushRef.json)}`
  );

  // ── 2. Nurse B, another district and another handset, pulls ─────────────────
  const pullB = await pullAll(nurseB.token);
  const dataB = pullB.data;
  const householdsB = dataB.households;
  const personsB = dataB.persons;
  const referralsB = dataB.referrals;

  check(
    "nurse B's pull carries the colleague household across districts",
    householdsB.some((h) => h.id === householdId),
    `got ${householdsB.length} household row(s)`
  );
  check(
    'nurse B receives the child, so a name search can find them',
    personsB.some((p) => p.id === personId && p.full_name === childName),
    `got ${personsB.length} person row(s)`
  );
  check(
    'nurse B receives the open referral too (the record is ongoing, not past)',
    referralsB.some((r) => r.id === referralId && r.status === 'issued'),
    `got ${referralsB.length} referral row(s)`
  );

  // ── 3. The privacy boundary: another region must not receive it ─────────────
  const pullC = await pullAll(nurseC.token);
  const householdsC = pullC.data.households;
  check(
    'a nurse in another region never receives the family',
    !householdsC.some((h) => h.id === householdId),
    `C got ${householdsC.length} household row(s)`
  );

  // ── 4. An in-place status change reaches the other device ──────────────────
  // The facility confirms arrival on Nurse B's handset; Nurse A's device must be
  // able to learn it. The server half of that is re-offering the SAME row id
  // with a newer revision marker — which a delta pull must do, because the
  // client's merge only ever saw insert-if-absent before.
  // Wait past the trigger's whole-second boundary. The server stamps
  // pull_updated_at at SECOND precision while its own server_time carries
  // milliseconds, so an update landing in the same second as the previous pull
  // is not strictly "newer" as a string. The client tolerates this by pulling
  // from one second before its watermark; doing the same here keeps the check
  // deterministic instead of racing the clock.
  await new Promise((r) => setTimeout(r, 1300));
  const later = new Date(Date.now() + 2000).toISOString();
  const pushArrived = await push(
    nurseA.token,
    'referrals',
    referralId,
    {
      id: referralId,
      reference_code: `CB-${stamp.toUpperCase()}`,
      person_id: personId,
      assessment_id: assessmentId,
      facility_name: 'Tamale Teaching Hospital',
      reason: 'Fast breathing needing assessment',
      urgency: 'sameDay',
      issued_by: nurseA.userId,
      issued_at: now,
      status: 'arrived',
      status_updated_at: later,
      arrival_confirmed_by: 'facility-desk',
      sync_state: 'synced',
    },
    'update'
  );
  check('an updated referral is accepted (2xx)', pushArrived.status < 300, `${pushArrived.status}`);

  const watermarkMs = Date.parse(pullB.serverTime) - 1000;
  const watermark = new Date(watermarkMs).toISOString();
  const deltaB = await pullAll(nurseB.token, watermark);
  const deltaRows = deltaB.data.referrals;
  const arrivedAgain = deltaRows.find((r) => r.id === referralId);
  check(
    'a delta pull re-offers the referral with the new status',
    !!arrivedAgain && arrivedAgain.status === 'arrived',
    `delta delivered ${deltaRows.length} referral row(s)` +
      (arrivedAgain ? `, status ${arrivedAgain.status}` : '')
  );
  check(
    'the re-offered row carries the server-owned revision marker',
    !!(arrivedAgain && arrivedAgain.pull_updated_at),
    arrivedAgain ? `pull_updated_at ${arrivedAgain.pull_updated_at}` : 'no row'
  );

  // ── 5. The same promise in North East, and the boundary the other way ──────
  // Nurse D registers a mother and her child in East Mamprusi. Nurse C, posted
  // in West Mamprusi, has never met them — the child walks into her clinic the
  // next day. She must receive both, so her search finds the child by name. A
  // Northern nurse must receive neither.
  const neHouseholdId = `hh-ne-${stamp}`;
  const neMotherId = `p-ne-mother-${stamp}`;
  const neChildId = `p-ne-child-${stamp}`;
  const neChildName = 'Fuseina Abdulai Wumbei';
  const neHh = await push(nurseD.token, 'households', neHouseholdId, {
    id: neHouseholdId,
    name: 'The Wumbei family',
    region: nurseD.region,
    district: nurseD.district,
    community: nurseD.community,
    head_name: 'Abdulai Wumbei',
    landmark: 'opposite the chief palace',
    created_by: nurseD.userId,
    created_at: now,
    updated_at: now,
  });
  const neMother = await push(nurseD.token, 'persons', neMotherId, {
    id: neMotherId,
    household_id: neHouseholdId,
    full_name: 'Mariama Wumbei',
    client_type: 'postpartumWoman',
    sex: 'F',
    date_of_birth: '1998-03-04',
    created_at: now,
    updated_at: now,
    is_active: 1,
  });
  const neChild = await push(nurseD.token, 'persons', neChildId, {
    id: neChildId,
    household_id: neHouseholdId,
    full_name: neChildName,
    client_type: 'childUnderFive',
    sex: 'F',
    date_of_birth: '2025-01-20',
    mother_id: neMotherId,
    created_at: now,
    updated_at: now,
    is_active: 1,
  });
  check(
    'nurse D (East Mamprusi) can push the family she registered (2xx)',
    neHh.status < 300 && neMother.status < 300 && neChild.status < 300,
    `household ${neHh.status}, mother ${neMother.status}, child ${neChild.status}`
  );

  const pullC2 = await pullAll(nurseC.token);
  check(
    "nurse C (West Mamprusi) receives nurse D's household — another North East district",
    pullC2.data.households.some((h) => h.id === neHouseholdId),
    `pull ${pullC2.status}, ${pullC2.pages} page(s), ${pullC2.data.households.length} household row(s)`
  );
  check(
    'nurse C receives the mother and the child by name',
    pullC2.data.persons.some((p) => p.id === neChildId && p.full_name === neChildName) &&
      pullC2.data.persons.some((p) => p.id === neMotherId),
    `${pullC2.data.persons.length} person row(s)`
  );

  const pullB2 = await pullAll(nurseB.token);
  check(
    'a Northern nurse never receives the North East family',
    !pullB2.data.households.some((h) => h.id === neHouseholdId) &&
      !pullB2.data.persons.some((p) => p.id === neChildId),
    `B got ${pullB2.data.households.length} household row(s)`
  );

  // ── 6. The accountability spine reaches the district, and does not collide ──
  // Consent decisions and access-trail entries are push-only: they must be
  // whitelisted (sync.js 400s anything absent, and the client treats 4xx as a
  // permanent rejection, so an unlisted table means evidence that never leaves
  // the phone) and they must never be pulled down to other handsets.
  const ledgerId = `al-${stamp}-d1-1`;
  const pushLedger = await push(nurseA.token, 'access_ledger', ledgerId, {
    id: ledgerId,
    seq: 1,
    actor_id: nurseA.userId,
    actor_role: 'frontlineHealthWorker',
    device_id: 'device-A',
    action: 'open_record',
    entity_table: 'households',
    entity_id: householdId,
    subject_person_id: personId,
    purpose: 'continuingCare',
    basis: 'careRelationship',
    note: 'own caseload',
    flagged: 0,
    occurred_at: now,
    previous_hash: 'carebridge-access-chain-v1',
    entry_hash: 'a'.repeat(64),
    hash_format: 'v1',
  });
  check(
    'the access trail is accepted by the server (whitelisted, not 400)',
    pushLedger.status < 300,
    `${pushLedger.status} ${JSON.stringify(pushLedger.json)}`
  );

  // A second device's FIRST trail entry has the same seq as the first device's
  // first entry. Every handset's chain starts at 1, so a server keyed on seq
  // would let one device erase another's audit history — the quietest possible
  // way to lose an accountability trail.
  const pushLedger2 = await push(nurseB.token, 'access_ledger', `al-${stamp}-d2-1`, {
    id: `al-${stamp}-d2-1`,
    seq: 1,
    actor_id: nurseB.userId,
    actor_role: 'frontlineHealthWorker',
    device_id: 'device-B',
    action: 'open_record',
    entity_table: 'households',
    entity_id: householdId,
    subject_person_id: personId,
    purpose: 'continuingCare',
    basis: 'consent',
    note: 'family opted in',
    flagged: 0,
    occurred_at: now,
    previous_hash: 'carebridge-access-chain-v1',
    entry_hash: 'b'.repeat(64),
    hash_format: 'v1',
  });
  check(
    'a second device’s seq 1 is accepted too',
    pushLedger2.status < 300,
    `${pushLedger2.status} ${JSON.stringify(pushLedger2.json)}`
  );

  const pushConsent = await push(
    nurseA.token,
    'consent_events',
    `ce-${stamp}`,
    {
      id: `ce-${stamp}`,
      subject_person_id: personId,
      scope: 'crossFacilitySearch',
      decision: 'granted',
      notice_version: '2026-10-v2',
      language: 'Hausa',
      voice_artifact: 'hausa_piper:consent-notice-2026-10',
      captured_by: nurseA.userId,
      device_id: 'device-A',
      witness_name: 'CHPS compound manager',
      occurred_at: now,
    }
  );
  check(
    'a recorded consent decision is accepted, spoken form included',
    pushConsent.status < 300,
    `${pushConsent.status} ${JSON.stringify(pushConsent.json)}`
  );

  // Read back from the district's own copy. Both rows must exist side by side.
  let dbProbe = null;
  try {
    const mysql = require('mysql2/promise');
    const conn = await mysql.createConnection({
      host: process.env.DB_HOST,
      port: parseInt(process.env.DB_PORT || '3306', 10),
      user: process.env.DB_USER,
      password: process.env.DB_PASSWORD,
      database: process.env.DB_NAME,
    });
    // Note the column is `id`, not `entity_id`: `entity_id` belongs to sync_log.
    // Querying the wrong one here returned zero rows and correctly failed the
    // check, which is the whole point of writing the assertion at all.
    const [rows] = await conn.execute(
      'SELECT device_id, seq, basis FROM access_ledger WHERE id LIKE ? ORDER BY device_id',
      [`al-${stamp}%`]
    );
    const [consents] = await conn.execute(
      'SELECT language, voice_artifact FROM consent_events WHERE id = ?',
      [`ce-${stamp}`]
    );
    dbProbe = { ledger: rows, consents };
    await conn.end();
  } catch (e) {
    dbProbe = { error: e.message };
  }
  check(
    'both devices’ seq 1 survive side by side — no overwrite of audit history',
    !!dbProbe &&
      Array.isArray(dbProbe.ledger) &&
      dbProbe.ledger.length === 2 &&
      dbProbe.ledger.filter((r) => r.seq === 1).length === 2,
    JSON.stringify(dbProbe)
  );
  check(
    'the consent row kept the language and the audio artefact that voiced it',
    !!dbProbe &&
      Array.isArray(dbProbe.consents) &&
      dbProbe.consents.length === 1 &&
      dbProbe.consents[0].language === 'Hausa' &&
      !!dbProbe.consents[0].voice_artifact,
    JSON.stringify(dbProbe && dbProbe.consents)
  );

  // And the trail stays off the download: pulling must not hand another device
  // someone else's access history.
  const pullForLedger = await pullAll(nurseC.token);
  check(
    'the access trail is never pulled down to another handset',
    !pullForLedger.seenKeys.has('access_ledger') &&
      !pullForLedger.seenKeys.has('consent_events'),
    `server offered keys: ${[...pullForLedger.seenKeys].join(', ')}`
  );

  // ── 7. A family's request reaches the district, and its answer replaces it ──
  // The privacy notice promises an answer within 30 days. A promise only the
  // family's own handset can evidence is not a promise — so this table is
  // whitelisted, and it is the one accountability row that is MUTABLE: a request
  // moves from open to fulfilled/refused. The client re-pushes the whole updated
  // row under the same id, which must land as an update and not a second request.
  const rightId = `dr-${stamp}`;
  const pushRight = await push(nurseA.token, 'data_rights_requests', rightId, {
    id: rightId,
    subject_person_id: personId,
    request_kind: 'rectification',
    status: 'open',
    requested_at: now,
    requested_by: nurseA.userId,
    resolved_at: null,
    resolution: null,
  });
  check(
    'a family’s data-rights request is accepted by the server (whitelisted, not 400)',
    pushRight.status < 300,
    `${pushRight.status} ${JSON.stringify(pushRight.json)}`
  );

  const answeredAt = new Date(Date.now() + 86400000).toISOString();
  const pushAnswer = await push(nurseA.token, 'data_rights_requests', rightId, {
    id: rightId,
    subject_person_id: personId,
    request_kind: 'rectification',
    status: 'fulfilled',
    requested_at: now,
    requested_by: nurseA.userId,
    resolved_at: answeredAt,
    resolution: 'Corrected the child’s date of birth against the birth card.',
  });
  check(
    'answering it is accepted as a re-push of the same id',
    pushAnswer.status < 300,
    `${pushAnswer.status} ${JSON.stringify(pushAnswer.json)}`
  );

  let rightsProbe = null;
  try {
    const mysql = require('mysql2/promise');
    const conn = await mysql.createConnection({
      host: process.env.DB_HOST,
      port: parseInt(process.env.DB_PORT || '3306', 10),
      user: process.env.DB_USER,
      password: process.env.DB_PASSWORD,
      database: process.env.DB_NAME,
    });
    const [rows] = await conn.execute(
      'SELECT status, request_kind, resolution, resolved_at FROM data_rights_requests WHERE id = ?',
      [rightId]
    );
    rightsProbe = rows;
    await conn.end();
  } catch (e) {
    rightsProbe = { error: e.message };
  }
  check(
    'the district holds ONE request row, answered in place — not duplicated, not lost',
    Array.isArray(rightsProbe) &&
      rightsProbe.length === 1 &&
      rightsProbe[0].status === 'fulfilled' &&
      !!rightsProbe[0].resolution &&
      !!rightsProbe[0].resolved_at,
    JSON.stringify(rightsProbe)
  );

  // Push-only, like the rest of the spine: an unanswered request names a family, so
  // the district's whole queue must not arrive on every handset that pulls.
  check(
    'a request is never downloaded to another handset',
    !pullForLedger.seenKeys.has('data_rights_requests'),
    `server offered keys: ${[...pullForLedger.seenKeys].join(', ')}`
  );

  // ── 8. Chain anchors: storable, irrevocable, and actually load-bearing ──────
  // The device commits its chain position every tenth entry so the district can
  // notice a trail that was shortened later. Three properties have to hold, and the
  // third is the only one that makes the other two worth having.
  const anchorDevice = `anchor-${stamp}`;
  const anchorId = `${anchorDevice}:10`;
  // A device with a complete trail of its own first, so the honest case really is
  // clean. A checker that cries wolf on its own test fixture is a checker nobody
  // reads — the same reason the detectors in the app count rather than accuse.
  for (let seq = 1; seq <= 9; seq++) {
    await push(nurseA.token, 'access_ledger', `al-${anchorDevice}-${seq}`, {
      id: `al-${anchorDevice}-${seq}`,
      seq,
      actor_id: nurseA.userId,
      actor_role: 'frontlineHealthWorker',
      device_id: anchorDevice,
      action: 'open_record',
      entity_table: 'households',
      entity_id: householdId,
      subject_person_id: personId,
      purpose: 'continuingCare',
      basis: 'careRelationship',
      note: 'anchor fixture',
      flagged: 0,
      occurred_at: now,
      previous_hash: 'carebridge-access-chain-v1',
      entry_hash: `f${String(seq).padStart(2, '0')}`.padEnd(64, '0'),
      hash_format: 'v1',
    });
  }
  await push(nurseA.token, 'access_ledger', `al-${anchorDevice}-10`, {
    id: `al-${anchorDevice}-10`,
    seq: 10,
    actor_id: nurseA.userId,
    actor_role: 'frontlineHealthWorker',
    device_id: anchorDevice,
    action: 'open_record',
    entity_table: 'households',
    entity_id: householdId,
    subject_person_id: personId,
    purpose: 'continuingCare',
    basis: 'careRelationship',
    note: 'anchor fixture',
    flagged: 0,
    occurred_at: now,
    previous_hash: 'carebridge-access-chain-v1',
    entry_hash: 'c'.repeat(64),
    hash_format: 'v1',
  });
  const anchorPush = await push(nurseA.token, 'ledger_anchors', anchorId, {
    id: anchorId,
    device_id: anchorDevice,
    seq: 10,
    entry_hash: 'c'.repeat(64),
    entry_count: 10,
    anchored_at: now,
  });
  check(
    'a chain anchor is accepted by the district',
    anchorPush.status < 300,
    `${anchorPush.status} ${JSON.stringify(anchorPush.json)}`
  );

  // The attack this closes: sync upserts on the primary key, so without a trigger a
  // device could re-push its own seq 10 with a new hash and re-sign its past.
  const reSigned = await push(nurseA.token, 'ledger_anchors', anchorId, {
    id: anchorId,
    device_id: anchorDevice,
    seq: 10,
    entry_hash: 'd'.repeat(64),
    entry_count: 10,
    anchored_at: now,
  });
  check(
    'a device cannot revise an anchor it already sent',
    reSigned.status >= 400,
    `${reSigned.status} ${JSON.stringify(reSigned.json)}`
  );

  // A synthetic shortened trail: the anchor declares five entries at seq 2, two
  // exist. Detection has to fire here or the anchor table is decoration.
  const fakeDevice = `shortened-${stamp}`;
  for (const seq of [1, 2]) {
    await push(nurseA.token, 'access_ledger', `al-${fakeDevice}-${seq}`, {
      id: `al-${fakeDevice}-${seq}`,
      seq,
      actor_id: nurseA.userId,
      actor_role: 'frontlineHealthWorker',
      device_id: fakeDevice,
      action: 'open_record',
      entity_table: 'households',
      entity_id: householdId,
      subject_person_id: personId,
      purpose: 'continuingCare',
      basis: 'careRelationship',
      note: 'shortened-trail probe',
      flagged: 0,
      occurred_at: now,
      previous_hash: 'carebridge-access-chain-v1',
      entry_hash: `e${seq}`.padEnd(64, '0'),
      hash_format: 'v1',
    });
  }
  await push(nurseA.token, 'ledger_anchors', `${fakeDevice}:2`, {
    id: `${fakeDevice}:2`,
    device_id: fakeDevice,
    seq: 2,
    entry_hash: `e2`.padEnd(64, '0'),
    entry_count: 5,
    anchored_at: now,
  });

  const audit = await auditAnchors();
  check(
    'a trail shortened after it was anchored is detected',
    audit.problems.some(
      (p) => p.device_id === fakeDevice && p.kind === 'history_shortened'
    ),
    `${audit.anchors} anchor(s), ${audit.problems.length} problem(s): ` +
      audit.problems.map((p) => `${p.device_id}/${p.kind}`).join(', ')
  );
  check(
    'and honest devices are not accused — a complete trail verifies clean',
    !audit.problems.some(
      (p) =>
        p.device_id === anchorDevice ||
        p.device_id === 'device-A' ||
        p.device_id === 'device-B'
    ),
    audit.problems.map((p) => `${p.device_id}:${p.kind}`).join(', ') || 'clean'
  );

  // ── 9. Read auditing: how much of the register left the server ───────────
  // Every pull above delivered rows to a handset. Until this existed, none of it was
  // recorded anywhere: the server logged writes and was silent on reads.
  let reads = null;
  try {
    const mysql = require('mysql2/promise');
    const conn = await mysql.createConnection({
      host: process.env.DB_HOST,
      port: parseInt(process.env.DB_PORT || '3306', 10),
      user: process.env.DB_USER,
      password: process.env.DB_PASSWORD,
      database: process.env.DB_NAME,
    });
    const [rows] = await conn.execute(
      "SELECT route, user_id, household_count, person_count FROM server_read_log " +
        'WHERE route = ? ORDER BY id DESC LIMIT 1',
      ['pull']
    );
    reads = rows;
    await conn.end();
  } catch (e) {
    reads = { error: e.message };
  }
  check(
    'every pull is recorded with the size of what it delivered',
    Array.isArray(reads) &&
      reads.length === 1 &&
      !!reads[0].user_id &&
      Number(reads[0].household_count) > 0,
    JSON.stringify(reads)
  );

  const failed = results.filter((r) => !r.ok);
  console.log(
    `\n${results.length - failed.length}/${results.length} checks passed` +
      (failed.length ? ` — FAILED: ${failed.map((f) => f.name).join('; ')}` : '')
  );
  process.exit(failed.length ? 1 : 0);
})().catch((e) => {
  console.error('verify-caseload crashed:', e.message);
  console.error('is the server running?  cd server; node src/index.js');
  process.exit(1);
});
