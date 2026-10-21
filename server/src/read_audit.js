// Server-side read auditing: who took how much of the register, and to where.
//
// ### The gap this closes
//
// `sync_log` records every write a device makes. Until now, the one data flow with
// no record at all was a *read*: `GET /api/pull` and the cloud-recovery caseload
// route could each hand a whole district's register to a handset, and the server
// would keep no note of who did it, when, or how many rows left.
//
// That is not a lesser exposure than a write. A CHPS handset is shared, it leaves
// the compound in a pocket, and it is the artefact most likely to be lost. The
// question a district will be asked after one goes missing is not "what changed" —
// it is "what did that phone take, and when".
//
// ### Why it can never break a request
//
// Every write here is wrapped so that a logging failure cannot fail a clinical
// read. That is a deliberate, stated trade-off and it has a cost: an audit log with
// holes is weaker than one that cannot have them, and a log that broke care would be
// switched off inside a week by the first administrator with the password. The
// balance is the one the app already draws everywhere else — care is never blocked
// by a record, and a logging failure is therefore recorded loudly on the console,
// with the failure count reported by `--audit` rather than hidden.
//
// ### Why devices cannot write here
//
// There is no entry for this table in `src/tables.js`, which is the list of tables
// a device is allowed to push. A read log a device could write to is a read log it
// could forge or empty, so the server is its only writer.
'use strict';

const { pool } = require('./db');

// Bumped if a logging fault needs to be noticed by something other than a human
// reading stdout in a district office that has no console open.
let failures = 0;

async function recordRead({ claims, scope, route, counts, watermark, cursor }) {
  try {
    await pool.query(
      `INSERT INTO server_read_log
         (user_id, role, route, region, district, community,
          household_count, person_count, row_count, watermark, cursor_position)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        claims && claims.userId ? claims.userId : 'unknown',
        (claims && claims.role) || null,
        route,
        (scope && scope.region) || null,
        (scope && scope.district) || null,
        (scope && scope.community) || null,
        (counts && counts.households) || 0,
        (counts && counts.persons) || 0,
        (counts && counts.total) || 0,
        watermark || null,
        typeof cursor === 'number' ? cursor : null,
      ]
    );
  } catch (err) {
    failures += 1;
    console.error(
      `READ AUDIT FAILED (${failures}) for ${route}: ${err.message}`
    );
  }
}

module.exports = { recordRead, readAuditFailures: () => failures };
