// MariaDB connection pool.
//
// Every query the server runs goes through this pool with parameterised
// placeholders — identifiers (table/column names) only ever come from the
// whitelist in tables.js, never from the request, and values are always bound
// as parameters. That combination is what makes SQL injection structurally
// impossible here, not a filter we have to remember to apply.
'use strict';

const mysql = require('mysql2/promise');
const config = require('./config');

const pool = mysql.createPool({
  host: config.db.host,
  port: config.db.port,
  user: config.db.user,
  password: config.db.password,
  database: config.db.name,
  waitForConnections: true,
  connectionLimit: 10,
  charset: 'utf8mb4_unicode_ci',
  dateStrings: true, // keep dates as the exact strings the phone sent
  namedPlaceholders: false,
});

// Cheap liveness probe used by GET /health and at startup.
async function ping() {
  const conn = await pool.getConnection();
  try {
    await conn.ping();
  } finally {
    conn.release();
  }
}

module.exports = { pool, ping };
