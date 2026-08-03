// Standalone verification of the sync server's security-critical logic.
// Runs with plain Node (no test framework, no database):
//
//     node test/verify.js
//
// It proves the three things a reviewer most needs to know:
//   1. The SQL builders produce correct, idempotent, parameterised statements.
//   2. The whitelist drops anything that is not a known column (including
//      credentials and injection attempts) before it ever nears the database.
//   3. The bearer-token gate rejects missing/wrong tokens and admits the right
//      one.
'use strict';

// config.js validates the environment at require time, so provide it before
// importing anything that touches it. These values are never used to connect.
process.env.DB_HOST = process.env.DB_HOST || '127.0.0.1';
process.env.DB_USER = process.env.DB_USER || 'verify';
process.env.DB_PASSWORD = process.env.DB_PASSWORD || 'verify';
process.env.DB_NAME = process.env.DB_NAME || 'carebridge';
process.env.SYNC_API_TOKEN = 'test-secret-token';

const assert = require('assert');
const { buildUpsertSql, buildDeleteSql, filterRow, normalize } = require('../src/sync');
const { TABLES } = require('../src/tables');
const { requireToken } = require('../src/auth');

let passed = 0;
function test(name, fn) {
  try {
    fn();
    passed += 1;
    console.log(`  ok   ${name}`);
  } catch (err) {
    console.error(`  FAIL ${name}`);
    console.error(`       ${err.message}`);
    process.exitCode = 1;
  }
}

console.log('SQL builders');

test('full insert builds an idempotent upsert', () => {
  const row = { id: 'h1', name: 'Household', region: 'Northern' };
  const { sql, values } = buildUpsertSql('households', TABLES.households.pk, row);
  assert.strictEqual(
    sql,
    'INSERT INTO `households` (`id`, `name`, `region`) VALUES (?, ?, ?) ' +
      'ON DUPLICATE KEY UPDATE `name` = VALUES(`name`), `region` = VALUES(`region`)'
  );
  assert.deepStrictEqual(values, ['h1', 'Household', 'Northern']);
});

test('partial update only touches the provided columns', () => {
  const row = { id: 'p1', is_active: 0 };
  const { sql, values } = buildUpsertSql('persons', TABLES.persons.pk, row);
  assert.strictEqual(
    sql,
    'INSERT INTO `persons` (`id`, `is_active`) VALUES (?, ?) ' +
      'ON DUPLICATE KEY UPDATE `is_active` = VALUES(`is_active`)'
  );
  assert.deepStrictEqual(values, ['p1', 0]);
});

test('key-only payload uses INSERT IGNORE (no update clause)', () => {
  const row = { person_id: 'm1' };
  const { sql } = buildUpsertSql('maternal_records', TABLES.maternal_records.pk, row);
  assert.strictEqual(sql, 'INSERT IGNORE INTO `maternal_records` (`person_id`) VALUES (?)');
});

test('composite primary key delete binds both parts', () => {
  const row = { visit_id: 'v1', person_id: 'p1', was_present: 1 };
  const { sql, values } = buildDeleteSql(
    'visit_participants',
    TABLES.visit_participants.pk,
    row
  );
  assert.strictEqual(sql, 'DELETE FROM `visit_participants` WHERE `visit_id` = ? AND `person_id` = ?');
  assert.deepStrictEqual(values, ['v1', 'p1']);
});

console.log('Whitelist filtering');

test('unknown and credential columns are dropped', () => {
  const payload = {
    id: 'u1',
    full_name: 'Ama',
    phone: '0200000000',
    role: 'fhw',
    region: 'Northern', district: 'Karaga', community: 'Gushegu',
    preferred_language: 'English',
    created_at: '2026-08-01T00:00:00.000',
    // None of these may ever reach the database:
    pin_hash: 'evil', pin_salt: 'evil', is_admin: 1,
    "id`; DROP TABLE users;--": 'x',
  };
  const row = filterRow(TABLES.users, payload);
  assert.strictEqual(row.id, 'u1');
  assert.strictEqual(row.full_name, 'Ama');
  assert.ok(!('pin_hash' in row), 'pin_hash must be dropped');
  assert.ok(!('pin_salt' in row), 'pin_salt must be dropped');
  assert.ok(!('is_admin' in row), 'unknown column must be dropped');
  assert.strictEqual(Object.keys(row).length, 9, 'only whitelisted columns survive');
});

test('booleans normalise to 0/1 and objects are serialised', () => {
  assert.strictEqual(normalize(true), 1);
  assert.strictEqual(normalize(false), 0);
  assert.strictEqual(normalize(null), null);
  assert.strictEqual(normalize({ a: 1 }), '{"a":1}');
  assert.strictEqual(normalize('text'), 'text');
});

console.log('Bearer-token gate');

function mockRes() {
  const res = { statusCode: null, body: null };
  res.status = (code) => { res.statusCode = code; return res; };
  res.json = (body) => { res.body = body; return res; };
  return res;
}

test('missing token -> 401', () => {
  const res = mockRes();
  let nextCalled = false;
  requireToken({ headers: {} }, res, () => { nextCalled = true; });
  assert.strictEqual(res.statusCode, 401);
  assert.strictEqual(nextCalled, false);
});

test('wrong token -> 401', () => {
  const res = mockRes();
  let nextCalled = false;
  requireToken({ headers: { authorization: 'Bearer wrong' } }, res, () => { nextCalled = true; });
  assert.strictEqual(res.statusCode, 401);
  assert.strictEqual(nextCalled, false);
});

test('correct token -> passes through', () => {
  const res = mockRes();
  let nextCalled = false;
  requireToken(
    { headers: { authorization: 'Bearer test-secret-token' } },
    res,
    () => { nextCalled = true; }
  );
  assert.strictEqual(nextCalled, true);
  assert.strictEqual(res.statusCode, null);
});

console.log(`\n${passed} checks passed${process.exitCode ? ' (with failures)' : ''}.`);
