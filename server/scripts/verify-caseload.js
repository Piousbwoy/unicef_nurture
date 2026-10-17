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

  // Three nurses, one region. B deliberately spells the region the SHORT way
  // ('Northern'), which is exactly what a recovery-created account writes, so the
  // tolerant match is exercised rather than assumed. C is a different region.
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
    fullName: 'Nurse C — North East',
    region: 'North East Region',
    district: 'Nalerigu Guarlja',
    community: 'Walewale',
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
      `  C ${nurseC.userId} (${nurseC.region} / ${nurseC.district})\n`
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
  const pullB = await call('GET', '/api/pull', null, nurseB.token);
  const dataB = (pullB.json && pullB.json.data) || {};
  const householdsB = dataB.households || [];
  const personsB = dataB.persons || [];
  const referralsB = dataB.referrals || [];

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
  const pullC = await call('GET', '/api/pull', null, nurseC.token);
  const dataC = (pullC.json && pullC.json.data) || {};
  const householdsC = dataC.households || [];
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

  const watermarkMs = Date.parse(pullB.json.server_time) - 1000;
  const watermark = new Date(watermarkMs).toISOString();
  const deltaB = await call(
    'GET',
    `/api/pull?since=${encodeURIComponent(watermark)}`,
    null,
    nurseB.token
  );
  const deltaRows = ((deltaB.json && deltaB.json.data) || {}).referrals || [];
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
