// End-to-end proof that MariaDB-backed authentication works: performs the SAME
// challenge/response a blank Flutter web device does, and asserts a JWT comes back.
//
//   node scripts/verify-auth.js --phone=0242940527 --pin=4572
//
// It mirrors lib/data/sync/server_auth_client.signIn + Credentials.
// computeCloudVerifierFromPin (web iteration cost 500/500 by default).
'use strict';

require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const crypto = require('crypto');

function arg(name, fallback) {
  const hit = process.argv.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.split('=').slice(1).join('=') : fallback;
}
const PHONE = arg('phone', '0242940527').trim();
const PIN = arg('pin', '4572').trim();
const PIN_ITERS = parseInt(arg('pin-iters', '500'), 10);
const CLOUD_ITERS = parseInt(arg('cloud-iters', '500'), 10);
const BASE = arg('base', `http://localhost:${process.env.PORT || 3000}`);
const DOMAIN = 'carebridge_cloud_auth_v1';

function hmac(k, m) { return crypto.createHmac('sha256', k).update(m).digest(); }
function verifierFromPin(pin, phone, salt) {
  const fpKey = Buffer.from(`first_pass|${salt}|${phone}`, 'utf8');
  let fp = Buffer.from(pin, 'utf8');
  for (let i = 0; i < PIN_ITERS; i++) fp = hmac(fpKey, fp);
  const km = Buffer.from(`${DOMAIN}|${salt}|${phone}`, 'utf8');
  let b = fp;
  for (let i = 0; i < CLOUD_ITERS; i++) b = hmac(km, b);
  return b.toString('base64');
}

(async () => {
  // Step 1: challenge (unauthenticated) -> server_salt
  const ch = await fetch(`${BASE}/api/auth/challenge?phone=${encodeURIComponent(PHONE)}`);
  const chJson = await ch.json();
  console.log('challenge ->', ch.status, JSON.stringify(chJson));
  if (!ch.ok || !chJson.server_salt) {
    console.error('CHALLENGE FAILED — is the account seeded? (run scripts/seed-auth.js)');
    process.exit(1);
  }

  // Step 2: derive the verifier locally, exactly like the client
  const verifier = verifierFromPin(PIN, PHONE, chJson.server_salt);

  // Step 3: login with the verifier (never the PIN)
  const lg = await fetch(`${BASE}/api/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=utf-8' },
    body: JSON.stringify({ phone: PHONE, verifier_response: verifier, device_id: 'verify-auth-cli' }),
  });
  const lgJson = await lg.json();
  console.log('login ->', lg.status, lgJson.ok ? `OK, access_token=${(lgJson.access_token||'').slice(0,24)}...` : JSON.stringify(lgJson));
  if (lg.ok && lgJson.access_token) {
    console.log('\nPASS: MariaDB authenticated the challenge/response and issued a JWT.');
    process.exit(0);
  } else {
    console.error('\nFAIL: login did not return a token.');
    process.exit(1);
  }
})().catch((e) => { console.error('verify failed:', e.message); process.exit(1); });
