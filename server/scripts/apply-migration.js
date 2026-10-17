// Apply a single .sql migration to the configured database.
//
// The runtime sync user is deliberately least-privilege and cannot ALTER, so
// migrations have to be applied with the admin credentials in .env — which is
// exactly what the server itself reads at startup. This runner uses those same
// settings so there is no second place to keep a password.
//
//   node scripts/apply-migration.js migrations/005_verifier_iterations.sql
//
// Multiple statements are allowed (the driver only executes one at a time
// here, so the file is split on semicolons at the end of a line). Statements
// that fail because the change is already present are reported and skipped, so
// re-running an idempotent migration is safe.
'use strict';

const fs = require('fs');
const path = require('path');
const mysql = require('mysql2/promise');

require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

const file = process.argv[2];
if (!file) {
  console.error('usage: node scripts/apply-migration.js <relative/path/to.sql>');
  process.exit(2);
}

const target = path.isAbsolute(file) ? file : path.join(__dirname, '..', file);
if (!fs.existsSync(target)) {
  console.error(`no such file: ${target}`);
  process.exit(2);
}

// Strip /* */ and -- comments before splitting, so a comment containing a
// semicolon cannot produce a half statement.
const sql = fs
  .readFileSync(target, 'utf8')
  .replace(/\/\*[\s\S]*?\*\//g, '')
  .split('\n')
  .filter((line) => !line.trim().startsWith('--'))
  .join('\n');

const statements = sql
  .split(/;\s*(?:\r?\n|$)/)
  .map((s) => s.trim())
  .filter(Boolean);

(async () => {
  const conn = await mysql.createConnection({
    host: process.env.DB_HOST || '127.0.0.1',
    port: parseInt(process.env.DB_PORT || '3306', 10),
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    database: process.env.DB_NAME,
    multipleStatements: false,
  });

  console.log(`applying ${path.basename(target)} — ${statements.length} statement(s)`);
  let applied = 0;
  let skipped = 0;

  for (const statement of statements) {
    const label = statement.replace(/\s+/g, ' ').slice(0, 72);
    try {
      await conn.query(statement);
      console.log(`  ok      ${label}`);
      applied++;
    } catch (err) {
      // 1060 duplicate column, 1061 duplicate index, 1050 table exists,
      // 1091 cannot drop (already gone) — all mean "already applied".
      const alreadyApplied = ['1060', '1061', '1050', '1091'].includes(
        String(err.code)
      );
      if (alreadyApplied) {
        console.log(`  skipped ${label}  (${err.sqlMessage})`);
        skipped++;
        continue;
      }
      console.error(`  FAILED  ${label}\n          ${err.code}: ${err.sqlMessage}`);
      await conn.end();
      process.exit(1);
    }
  }

  await conn.end();
  console.log(`done — ${applied} applied, ${skipped} already present`);
})().catch((e) => {
  console.error('migration failed:', e.message);
  process.exit(1);
});
