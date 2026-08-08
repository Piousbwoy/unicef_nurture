// POST /api/sync — receives one outbox entry from a phone and persists it.
//
// Contract with the app (lib/data/sync/http_transport.dart):
//   2xx -> record accepted, phone marks it synced.
//   4xx -> record is invalid and retrying is pointless; phone shows a human.
//   5xx -> server/network problem; phone backs off and retries later.
//
// Everything that can be fixed by the client arriving differently is a 4xx;
// everything that is the server's fault is a 5xx. Getting this split wrong is
// how records get lost (a 4xx is never retried), so transient problems must
// always surface as 5xx.
'use strict';

const { pool } = require('./db');
const { TABLES, OPERATIONS } = require('./tables');

// A problem caused by the shape of the request -> 400, do not retry.
class ClientError extends Error {}

// Coerce a JSON value into something safe to bind to a column. Booleans become
// 0/1 (matching how the device stores them); stray objects are serialised
// rather than allowed to crash the write.
function normalize(v) {
  if (v === undefined || v === null) return null;
  if (typeof v === 'boolean') return v ? 1 : 0;
  if (typeof v === 'number' || typeof v === 'string') return v;
  return JSON.stringify(v);
}

// Keep only whitelisted columns from a payload object.
function filterRow(tableDef, payload) {
  const row = {};
  for (const col of tableDef.columns) {
    if (Object.prototype.hasOwnProperty.call(payload, col)) {
      row[col] = normalize(payload[col]);
    }
  }
  return row;
}

// --- Pure SQL builders (exported for testing) -------------------------------
// Identifiers (table/column names) only ever come from the whitelist in
// tables.js; values are always bound as `?` parameters. A request can therefore
// never influence the shape of the SQL, only the bound values.
function buildUpsertSql(tableName, pkCols, row) {
  const cols = Object.keys(row);
  const colSql = cols.map((c) => `\`${c}\``).join(', ');
  const placeholders = cols.map(() => '?').join(', ');
  const values = cols.map((c) => row[c]);
  const updateCols = cols.filter((c) => !pkCols.includes(c));
  if (updateCols.length === 0) {
    // Only the key was sent — ensure the row exists, change nothing.
    return {
      sql: `INSERT IGNORE INTO \`${tableName}\` (${colSql}) VALUES (${placeholders})`,
      values,
    };
  }
  const updateSql = updateCols.map((c) => `\`${c}\` = VALUES(\`${c}\`)`).join(', ');
  return {
    sql:
      `INSERT INTO \`${tableName}\` (${colSql}) VALUES (${placeholders}) ` +
      `ON DUPLICATE KEY UPDATE ${updateSql}`,
    values,
  };
}

function buildDeleteSql(tableName, pkCols, row) {
  const where = pkCols.map((c) => `\`${c}\` = ?`);
  const values = pkCols.map((c) => row[c]);
  return { sql: `DELETE FROM \`${tableName}\` WHERE ${where.join(' AND ')}`, values };
}

// Idempotent write. INSERT ... ON DUPLICATE KEY UPDATE means a record that is
// sent twice (the phone retrying after a lost acknowledgement) lands once.
// Only the columns present in the payload are written, so the partial updates
// the app sends (e.g. {id, is_active: 0}) touch only what they mean to touch.
async function upsertRow(conn, tableName, payload) {
  const tableDef = TABLES[tableName];
  if (!tableDef) throw new ClientError(`Unknown table "${tableName}".`);

  const row = filterRow(tableDef, payload);

  // Without the primary key we cannot be idempotent, so refuse loudly.
  for (const pk of tableDef.pk) {
    if (row[pk] === undefined || row[pk] === null || row[pk] === '') {
      throw new ClientError(
        `payload for "${tableName}" is missing primary key column "${pk}".`
      );
    }
  }

  const { sql, values } = buildUpsertSql(tableName, tableDef.pk, row);
  const [result] = await conn.execute(sql, values);
  return result.affectedRows || 0;
}

async function deleteRow(conn, tableName, payload) {
  const tableDef = TABLES[tableName];
  if (!tableDef) throw new ClientError(`Unknown table "${tableName}".`);
  const row = filterRow(tableDef, payload);
  for (const pk of tableDef.pk) {
    if (row[pk] === undefined || row[pk] === null || row[pk] === '') {
      throw new ClientError(
        `delete for "${tableName}" is missing primary key column "${pk}".`
      );
    }
  }
  const { sql, values } = buildDeleteSql(tableName, tableDef.pk, row);
  const [result] = await conn.execute(sql, values);
  return result.affectedRows || 0;
}

async function handleSync(req, res) {
  const body = req.body || {};
  const entityTable = body.entity_table;
  const entityId = body.entity_id;
  const operation = body.operation;
  const payload = body.payload;
  const clientVersion = body.client_version || null;

  const auth = req.auth || {};
  const claims = auth.claims || null;
  const authMethod = auth.authMethod || 'unauthenticated';

  // --- Validate the envelope (all 4xx: the phone should not retry these) ----
  if (typeof entityTable !== 'string' || !TABLES[entityTable]) {
    return res
      .status(400)
      .json({ ok: false, error: `Unknown entity_table "${entityTable}".` });
  }
  if (typeof operation !== 'string' || !OPERATIONS.has(operation)) {
    return res
      .status(400)
      .json({ ok: false, error: `Unknown operation "${operation}".` });
  }
  if (payload === null || typeof payload !== 'object' || Array.isArray(payload)) {
    return res
      .status(400)
      .json({ ok: false, error: 'payload must be a JSON object.' });
  }

  // --- Scope: a JWT-authenticated write of a user-row can only change the
  // caller's own account (not someone else's). Prevent a compromised JWT
  // from overwriting other users' metadata.
  if (claims && entityTable === 'users' && payload.id) {
    if (String(payload.id) !== String(claims.userId)) {
      return res.status(403).json({
        ok: false,
        error: 'A user token cannot write another user\'s account record.',
      });
    }
  }

  // --- Scope: credential material lives in an isolated table. Only the
  // authenticated user themselves (or a fresh outbox from the SAME phone
  // number on a device that has not yet obtained a JWT via the legacy window)
  // may upsert a user_verifiers row. No bulk overwrite, no cross-user writes.
  // This constraint is what keeps pin_hash / pin_salt off the general server:
  // only the domain-separated HMAC verifier may reach user_verifiers, and
  // only on behalf of the owning account.
  if (entityTable === 'user_verifiers') {
    const payloadUserId = typeof payload.user_id === 'string' ? payload.user_id : null;
    if (!payloadUserId) {
      return res.status(400).json({
        ok: false,
        error: 'user_verifiers writes must include payload.user_id.',
      });
    }
    if (claims && String(payloadUserId) !== String(claims.userId)) {
      return res.status(403).json({
        ok: false,
        error: 'A user token cannot write another user\'s isolated credentials.',
      });
    }
    if (Array.isArray(payload.verifier) || typeof payload.verifier !== 'string' || payload.verifier.length < 16) {
      return res.status(400).json({
        ok: false,
        error: 'user_verifiers verifier must be a well-formed base64 HMAC.',
      });
    }
    if (Array.isArray(payload.server_salt) || typeof payload.server_salt !== 'string' || payload.server_salt.length < 12) {
      return res.status(400).json({
        ok: false,
        error: 'user_verifiers server_salt must be a non-trivial random salt.',
      });
    }
  }

  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();

    let affected;
    if (operation === 'delete') {
      affected = await deleteRow(conn, entityTable, payload);
    } else {
      // Write any nested children first (a visit carries its roll call), then
      // the record itself. Both ride the same transaction.
      const tableDef = TABLES[entityTable];
      if (tableDef.children) {
        for (const [key, childTable] of Object.entries(tableDef.children)) {
          const children = payload[key];
          if (Array.isArray(children)) {
            for (const child of children) {
              if (child && typeof child === 'object') {
                await upsertRow(conn, childTable, child);
              }
            }
          }
        }
      }
      affected = await upsertRow(conn, entityTable, payload);
    }

    // Audit trail: what changed, never the PHI itself. Attribution comes from
    // JWT claims (or legacy_token marker) so the district can know WHO wrote
    // what and WHEN, and which devices still need upgrading.
    await conn.execute(
      'INSERT INTO sync_log ' +
        '(user_id, facility_name, device_id, entity_table, entity_id, ' +
        ' operation, rows_affected, client_version, auth_method) ' +
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        claims ? claims.userId : null,
        claims ? (claims.facilityName || null) : null,
        claims ? (claims.deviceId || null) : null,
        entityTable,
        String(entityId ?? ''),
        operation,
        affected,
        clientVersion,
        authMethod,
      ]
    );

    await conn.commit();
    return res.status(200).json({
      ok: true,
      entity_table: entityTable,
      entity_id: entityId,
      affected,
    });
  } catch (err) {
    await conn.rollback().catch(() => {});
    if (err instanceof ClientError) {
      return res.status(400).json({ ok: false, error: err.message });
    }
    // Server-side failure -> 5xx so the phone keeps the record and retries.
    // eslint-disable-next-line no-console
    console.error(`sync failed for ${entityTable}/${entityId}:`, err.message);
    return res
      .status(500)
      .json({ ok: false, error: 'Internal error; record will be retried.' });
  } finally {
    conn.release();
  }
}

module.exports = {
  handleSync,
  // Exported for the verification script (test/verify.js).
  buildUpsertSql,
  buildDeleteSql,
  filterRow,
  normalize,
};
