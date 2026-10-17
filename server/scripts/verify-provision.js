// Proves the credential-bootstrap path end to end, over HTTP only.
//
// The claim under test: a device that has NEVER spoken to this server can POST its
// own cloud verifier, and a DIFFERENT handset holding only the phone number and PIN
// can then authenticate against it. That is the "register once, recover anywhere"
// promise. It used to be impossible — /api/sync needs a JWT, a JWT needs a
// challenge, and a challenge needs the user_verifiers row that only the first sync
// could deliver. POST /api/auth/register breaks that loop.
//
// Unlike scripts/seed-auth.js, this writes nothing directly into MariaDB. Every
// step goes through the public API, so it exercises exactly what a handset does.
//
//   node scripts/verify-provision.js
//
'use strict';

require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const crypto = require('crypto');

const BASE = process.env.BASE || `http://localhost:${process.env.PORT || 3000}`;
const DOMAIN = 'carebridge_cloud_auth_v1';
// Web build cost (lib/data/local/user_dao.dart: kIsWeb -> 500/500). A native
// debug build uses 1000/1000 and release 20000/120000.
const PIN_ITERS = parseInt(process.env.PIN_ITERS || '500', 10);
const CLOUD_ITERS = parseInt(process.env.CLOUD_ITERS || '500', 10);

const PHONE = process.env.PHONE || `05${Date.now().toString().slice(-8)}`;
const PIN = process.env.PIN || '7391';

// Set once /health is reachable, from whichever address family answered.
let activeBase = BASE;

function hmac(key, msg) {
  return crypto.createHmac('sha256', key).update(msg).digest();
}

// Byte-for-byte the client's Credentials.computeCloudVerifierFromPin — the only
// derivation a blank device can produce, since it holds no on-device pin_hash.
// Iteration cost is a parameter because that is the whole point: a native build
// would use 1000/1000 where a web build used 500/500, and the two results differ.
function verifierFromPin(pin, phone, serverSalt, pinIters, cloudIters) {
  const pIters = pinIters === undefined ? PIN_ITERS : pinIters;
  const cIters = cloudIters === undefined ? CLOUD_ITERS : cloudIters;
  const fpKey = Buffer.from(`first_pass|${serverSalt}|${phone}`, 'utf8');
  let fp = Buffer.from(pin, 'utf8');
  for (let i = 0; i < pIters; i++) fp = hmac(fpKey, fp);

  const km = Buffer.from(`${DOMAIN}|${serverSalt}|${phone}`, 'utf8');
  let b = fp;
  for (let i = 0; i < cIters; i++) b = hmac(km, b);
  return b.toString('base64');
}

async function call(method, path, body) {
  const res = await fetch(`${activeBase}${path}`, {
    method,
    headers: body ? { 'Content-Type': 'application/json; charset=utf-8' } : {},
    body: body ? JSON.stringify(body) : undefined,
  });
  let json = {};
  try {
    json = await res.json();
  } catch (_) {
    /* non-JSON body — status is what matters here */
  }
  return { status: res.status, json };
}

const results = [];
function check(name, ok, detail) {
  results.push({ name, ok });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? `  — ${detail}` : ''}`);
}

// Node's fetch resolves `localhost` to ::1 first, while Express commonly binds the
// IPv4 stack; the request then dies as a bare "fetch failed" and looks like a dead
// server when it is only an address-family mismatch. Probe the candidates and use
// whichever actually answers, so this script behaves the same on every machine.
async function resolveBase() {
  const candidates = [BASE];
  if (/localhost/.test(BASE)) {
    candidates.push(BASE.replace('localhost', '127.0.0.1'));
    candidates.push(BASE.replace('localhost', '[::1]'));
  } else if (/127\.0\.0\.1/.test(BASE)) {
    candidates.push(BASE.replace('127.0.0.1', 'localhost'));
  }
  for (const url of candidates) {
    try {
      const res = await fetch(`${url}/health`, { method: 'GET' });
      if (res.status === 200) return url;
    } catch (_) {
      /* try the next address family */
    }
  }
  return null;
}

(async () => {
  const resolved = await resolveBase();
  if (!resolved) {
    console.error(`no server answered /health on ${BASE} (or its 127.0.0.1 / [::1] variants)`);
    console.error('start it with:  cd server; node src/index.js');
    process.exit(1);
  }
  activeBase = resolved;
  const userId = crypto.randomUUID();
  const serverSalt = crypto.randomBytes(24).toString('base64url');
  const verifier = verifierFromPin(PIN, PHONE, serverSalt);

  const payload = {
    user_id: userId,
    phone: PHONE,
    server_salt: serverSalt,
    verifier,
    full_name: 'Provision Test Worker',
    role: 'frontlineHealthWorker',
    region: 'Northern Region',
    district: 'Savelugu Municipal',
    community: 'Tamale Central',
    preferred_language: 'English',
    device_id: 'verify-provision-cli',
    // What the client now records: the cost this credential was stretched at.
    pin_iterations: PIN_ITERS,
    cloud_iterations: CLOUD_ITERS,
  };

  console.log(`target ${activeBase}  phone ${PHONE}  iters ${PIN_ITERS}/${CLOUD_ITERS}\n`);

  // 1. A brand-new device provisions its own credential. No JWT, no prior row.
  const first = await call('POST', '/api/auth/register', payload);
  check(
    'fresh device can provision its credential (201)',
    first.status === 201 && first.json.ok === true,
    `${first.status} ${JSON.stringify(first.json)}`
  );

  // 2. The phone is now challengeable — previously this returned 404.
  const ch = await call('GET', `/api/auth/challenge?phone=${encodeURIComponent(PHONE)}`);
  check(
    'the phone is now challengeable (200 + server_salt)',
    ch.status === 200 && !!ch.json.server_salt,
    `${ch.status} ${JSON.stringify(ch.json)}`
  );

  // 3. A DIFFERENT handset, knowing only phone + PIN, authenticates and gets a JWT.
  let recovered = { status: 0, json: {} };
  if (ch.json.server_salt) {
    recovered = await call('POST', '/api/auth/login', {
      phone: PHONE,
      verifier_response: verifierFromPin(PIN, PHONE, ch.json.server_salt),
      device_id: 'second-handset',
    });
  }
  check(
    'a second handset authenticates with phone + PIN (200 + JWT)',
    recovered.status === 200 && !!recovered.json.access_token,
    `${recovered.status} ${recovered.json.ok ? 'issued access_token' : JSON.stringify(recovered.json)}`
  );

  // 4. CREATE-ONLY guard: the route must never overwrite an existing credential.
  const again = await call('POST', '/api/auth/register', payload);
  check(
    're-provisioning the same account is refused (409, never overwrite)',
    again.status === 409,
    `${again.status} ${JSON.stringify(again.json)}`
  );

  // 5. HIJACK guard: the same phone under a different user_id must be refused,
  //    so guessing a colleague's number cannot displace their account.
  const hijack = await call('POST', '/api/auth/register', {
    ...payload,
    user_id: crypto.randomUUID(),
    server_salt: crypto.randomBytes(24).toString('base64url'),
    verifier: verifierFromPin('0000', PHONE, serverSalt),
  });
  check(
    'same phone under a different account is refused (409, no takeover)',
    hijack.status === 409,
    `${hijack.status} ${JSON.stringify(hijack.json)}`
  );

  // 6. A wrong PIN must not authenticate, even though the credential exists.
  const wrong = await call('POST', '/api/auth/login', {
    phone: PHONE,
    verifier_response: verifierFromPin('1234', PHONE, ch.json.server_salt || serverSalt),
    device_id: 'attacker',
  });
  check(
    'a wrong PIN is rejected (401)',
    wrong.status === 401,
    `${wrong.status} ${JSON.stringify(wrong.json)}`
  );

  const failed = results.filter((r) => !r.ok);
  console.log(
    `\n${results.length - failed.length}/${results.length} checks passed` +
      (failed.length ? ` — FAILED: ${failed.map((f) => f.name).join('; ')}` : '')
  );
  process.exit(failed.length ? 1 : 0);
  console.error('verify-provision crashed:', e.message);
  console.error('is the server running?  cd server; node src/index.js');
  process.exit(1);
});
