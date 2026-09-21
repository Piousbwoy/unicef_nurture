// Idempotently apply server/schema.sql to the configured MariaDB database.
// schema.sql is entirely CREATE TABLE IF NOT EXISTS, so this only adds tables
// that are missing (e.g. user_verifiers + refresh_tokens on a pre-v1.1 DB) and
// never touches existing data.
//
//   node scripts/apply-schema.js
'use strict';

require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const fs = require('fs');
const path = require('path');
const mysql = require('mysql2/promise');
const config = require('../src/config');

async function main() {
  const sql = fs.readFileSync(path.join(__dirname, '..', 'schema.sql'), 'utf8');
  // The runtime sync user is least-privilege (no CREATE). Applying schema needs
  // an admin account; pass it via DB_ADMIN_USER / DB_ADMIN_PASSWORD, else fall
  // back to the normal DB_USER (works if that user already owns the schema).
  const conn = await mysql.createConnection({
    host: config.db.host,
    port: config.db.port,
    user: process.env.DB_ADMIN_USER || config.db.user,
    password: process.env.DB_ADMIN_PASSWORD !== undefined
      ? process.env.DB_ADMIN_PASSWORD
      : config.db.password,
    database: config.db.name,
    multipleStatements: true,
    charset: 'utf8mb4_unicode_ci',
  });
  try {
    await conn.query(sql);
    const [rows] = await conn.query('SHOW TABLES');
    console.log('Applied schema.sql. Tables now present:');
    console.log('  ' + rows.map((r) => Object.values(r)[0]).join('\n  '));
  } finally {
    await conn.end();
  }
}

main().catch((err) => {
  console.error('apply-schema failed:', err.message);
  process.exit(1);
});
