// Push a handful of realistic sample records through the SAME HTTP path the
// phone app uses (POST /api/sync), so you can confirm your MariaDB is being
// populated WITHOUT touching the phone.
//
//   1. Start the server:            npm start
//   2. Run this:                    node scripts/seed-demo.js
//   3. Open a mysql terminal and:   SELECT * FROM carebridge.households;
//
// The payload shape below is byte-for-byte the contract the app sends
// (lib/data/sync/http_transport.dart), so if these rows land, the app's rows
// will land too.
'use strict';

require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });

const BASE = process.env.SEED_URL || `http://localhost:${process.env.PORT || 3000}`;
const TOKEN = process.env.SYNC_API_TOKEN;

if (!TOKEN || TOKEN === 'change-me-to-a-long-random-token') {
  console.error('Set SYNC_API_TOKEN in server/.env first (same value the server uses).');
  process.exit(1);
}

const now = new Date().toISOString();

// A representative slice of what a community health worker's morning produces.
const records = [
  {
    entity_table: 'households',
    entity_id: 'hh-demo-001',
    operation: 'insert',
    payload: {
      id: 'hh-demo-001', name: 'Alhassan family', region: 'Northern',
      district: 'Karaga', community: 'Gushegu', created_by: 'fhw-demo',
      head_name: 'Sule Alhassan', contact_phone: '0201112223',
      family_size: 6, has_valid_nhis: 1, walking_minutes_to_facility: 25,
      landmark: 'Near the old shea tree', created_at: now, updated_at: now,
    },
  },
  {
    entity_table: 'persons',
    entity_id: 'person-mother-001',
    operation: 'insert',
    payload: {
      id: 'person-mother-001', household_id: 'hh-demo-001', full_name: 'Ayishetu Alhassan',
      client_type: 'mother', sex: 'female', date_of_birth: '1998-03-14',
      is_dob_estimated: 1, nhis_number: 'GH-4421-9987', created_at: now,
      updated_at: now, is_active: 1,
    },
  },
  {
    entity_table: 'persons',
    entity_id: 'person-child-001',
    operation: 'insert',
    payload: {
      id: 'person-child-001', household_id: 'hh-demo-001', full_name: 'Samira Alhassan',
      client_type: 'child', sex: 'female', date_of_birth: '2024-06-02',
      mother_id: 'person-mother-001', is_dob_estimated: 0, created_at: now,
      updated_at: now, is_active: 1,
    },
  },
  {
    entity_table: 'growth_measurements',
    entity_id: 'growth-001',
    operation: 'insert',
    payload: {
      id: 'growth-001', person_id: 'person-child-001', taken_at: now,
      muac_cm: 12.9, weight_kg: 8.4, height_cm: 71.5,
      has_bilateral_oedema: 0, recorded_by: 'fhw-demo',
    },
  },
  {
    entity_table: 'assessments',
    entity_id: 'assess-001',
    operation: 'insert',
    payload: {
      id: 'assess-001', visit_id: 'visit-demo-001', person_id: 'person-child-001',
      client_type: 'child', performed_by: 'fhw-demo', performed_at: now,
      inputs_json: JSON.stringify({ cough: true, fever: true, muac_cm: 12.9 }),
      result_json: JSON.stringify({ triage: 'priority', danger_signs: [] }),
      care_plan_json: JSON.stringify({ overallTriage: 'priority', actions: ['Refer to CHPS compound'] }),
      sync_state: 'pending',
    },
  },
  {
    entity_table: 'referrals',
    entity_id: 'ref-001',
    operation: 'insert',
    payload: {
      id: 'ref-001', reference_code: 'KRG-2417', person_id: 'person-child-001',
      assessment_id: 'assess-001', facility_name: 'Gushegu CHPS Compound',
      reason: 'Falling MUAC with cough and fever — assess for pneumonia and malnutrition',
      urgency: 'priority', issued_by: 'fhw-demo', issued_at: now,
      status: 'issued', sync_state: 'pending',
    },
  },
];

async function main() {
  console.log(`Sending ${records.length} sample records to ${BASE}/api/sync ...\n`);
  let failed = 0;
  for (const rec of records) {
    const body = { ...rec, queued_at: now, client_version: 'seed-demo' };
    const res = await fetch(`${BASE}/api/sync`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${TOKEN}`,
      },
      body: JSON.stringify(body),
    });
    const text = await res.text();
    if (res.ok) {
      console.log(`  ok   ${rec.entity_table.padEnd(20)} ${rec.entity_id}`);
    } else {
      failed += 1;
      console.error(`  FAIL ${rec.entity_table.padEnd(20)} ${rec.entity_id} -> HTTP ${res.status} ${text}`);
    }
  }

  console.log('\nNow verify in your mysql terminal:');
  console.log('  SELECT id, name, community FROM carebridge.households;');
  console.log('  SELECT full_name, client_type FROM carebridge.persons;');
  console.log('  SELECT reference_code, urgency, status FROM carebridge.referrals;');
  console.log('  SELECT entity_table, entity_id, operation FROM carebridge.sync_log ORDER BY id DESC LIMIT 6;');

  if (failed > 0) {
    console.error(`\n${failed} record(s) failed.`);
    process.exit(1);
  }
  console.log('\nAll records accepted. They are in MariaDB.');
}

main().catch((err) => {
  console.error('Could not reach the sync server:', err.message);
  console.error('Is it running? Start it with: npm start');
  process.exit(1);
});
