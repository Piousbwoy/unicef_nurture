// GET /api/pull — delta pull: the read half of the hybrid sync engine.
//
// Push (POST /api/sync) moves local writes up; pull (GET /api/pull) moves
// everything a given caller is allowed to see back down. Together they give
// two devices a converging view of the district database:
//
//   * Nurse A registers a household on her phone; it pushes to MariaDB.
//   * Nurse B (same region/community) pulls with her watermark (`since`) and
//     receives Nurse A's row — searchable in her app immediately, because the
//     local caseload query is already region-scoped.
//
// WATERMARK / CURSOR CONTRACT (second-precision UTC):
//
//   Every row of the six pullable clinical tables carries a server-managed
//   `pull_updated_at` marker (UTC, second precision) maintained by triggers —
//   see migrations/002_delta_pull.sql. The client stores the `server_time`
//   returned with the FIRST page of a pull session and sends it back (minus a
//   1-second overlap) as `since` on the next pull. Rows stream ordered by
//   (pull_updated_at, pk) across a fixed table order and are paged with an
//   offset-style `cursor`. The overlap plus last-writer-wins merging makes
//   re-delivery harmless, and any row written mid-pagination sorts after the
//   session's watermark so it is always caught by the next pull.
//
// SCOPE (identity with recovery.js — NOT NEGOTIABLE):
//
//   * caregiver: rows of the household bound to the JWT user
//     (linked_household_id). No binding → an honest, empty page.
//   * frontlineHealthWorker / supervisor: every household in the JWT's REGION
//     (plus anything created_by === JWT sub). Not the exact
//     (region, district, community) tuple — that predicate made a nurse's pull
//     return only her own community while the app's register on her phone is
//     region-wide, so a family registered by a colleague two districts over,
//     or in the same district under a different community spelling, simply
//     never arrived. The child would still walk in and be a stranger.
//
//   The region arm is matched by mutual prefix for the same reason the local
//   caseload query is: record sources disagree on 'Northern' vs 'Northern
//   Region' (cloud recovery writes the short form, the setup wizard the long
//   one), and an exact equality silently hides every colleague household from an
//   account created through recovery. A prefix never crosses into a
//   differently-named region: neither 'Northern Region' nor 'North East Region'
//   is a prefix of the other.
//
// The client's querystring is never trusted for scope — same rule as
// recovery.js. pull_updated_at is now DELIVERED, not stripped: the client
// persists it into a local `pull_updated_at` column (households, persons,
// referrals) so it can merge on the server's trusted clock instead of
// device-written time. It is never on the write whitelist, so no client can
// push it back.
'use strict';

const { pool } = require('./db');
const { recordRead } = require('./read_audit');

const PAGE_LIMIT_DEFAULT = 200;
const PAGE_LIMIT_MAX = 500;

// Fixed table order defines the concatenated stream the offset cursor pages
// through (parents before children, so a client can apply rows in one pass).
const PULL_TABLES = [
  { name: 'households', pk: 'id' },
  { name: 'persons', pk: 'id' },
  { name: 'visits', pk: 'id' },
  { name: 'assessments', pk: 'id' },
  { name: 'referrals', pk: 'id' },
  // After households, whose row a family's request points at: a device that
  // lost its household must receive the parent first or the child is an
  // FK failure mid-page.
  { name: 'care_requests', pk: 'id' },
];

// Accepts the exact ISO string this API issued earlier (server_time), with or
// without milliseconds/timezone. Anything else is a client bug worth a 400.
const WATERMARK_RE =
  /^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:?\d{2})?$/;

function parseWatermark(raw) {
  if (raw == null || String(raw).trim() === '') return null; // full pull
  const s = String(raw).trim();
  if (!WATERMARK_RE.test(s)) return undefined; // malformed
  return s.replace(' ', 'T');
}

// Same scope resolution as recovery.js handleCaseloadRestore.
async function resolveScope(claims) {
  const [rows] = await pool.query(
    'SELECT linked_household_id, role, region, district, community ' +
      'FROM users WHERE id = ? LIMIT 1',
    [claims.userId]
  );
  if (rows.length === 0) return null;
  const user = rows[0];
  const isCaregiver = claims.role === 'caregiver' || user.role === 'caregiver';
  if (isCaregiver) {
    // A caregiver with no bound household legitimately sees nothing — the
    // null region/user fields make every scope predicate compare against
    // NULL, an honest empty page rather than an error.
    return {
      caregiverHouseholdId: user.linked_household_id || null,
      region: null,
      district: null,
      community: null,
      userId: null,
    };
  }
  return {
    caregiverHouseholdId: null,
    region: claims.region || user.region,
    district: claims.district || user.district,
    community: claims.community || user.community,
    userId: claims.userId,
  };
}

function householdScope(scope) {
  if (scope.caregiverHouseholdId) {
    return { sql: 'id = ?', params: [scope.caregiverHouseholdId] };
  }
  // A worker with no region on her account still gets her own rows — an honest
  // narrow page beats an unbounded one.
  if (!scope.region) {
    return { sql: '(created_by = ?)', params: [scope.userId] };
  }
  return {
    sql:
      '(created_by = ? OR (region IS NOT NULL AND '
      + '(region LIKE ? OR ? LIKE CONCAT(region, \'%\'))))',
    params: [scope.userId, `${scope.region}%`, scope.region],
  };
}

function tableFilter(tableName, scope) {
  const hh = householdScope(scope);
  switch (tableName) {
    case 'households':
      return hh;
    // Household-scoped, and deliberately one case for all three: a worker who
    // covers the zone receives the family's ask, a worker two districts over
    // never learns it exists, and a bound caregiver receives exactly their own.
    case 'persons':
    case 'visits':
    case 'care_requests':
      return {
        sql: `household_id IN (SELECT id FROM households WHERE ${hh.sql})`,
        params: hh.params,
      };
    case 'assessments':
    case 'referrals':
      return {
        sql:
          'person_id IN (SELECT id FROM persons WHERE household_id IN ' +
          `(SELECT id FROM households WHERE ${hh.sql}))`,
        params: hh.params,
      };
    default:
      throw new Error(`pull: unknown table ${tableName}`);
  }
}

// Same scrub contract as recovery.js: never pin_hash, never pin_salt.
function scrubUser(u) {
  return {
    id: u.id,
    full_name: u.full_name,
    phone: u.phone,
    role: u.role,
    region: u.region,
    district: u.district,
    community: u.community,
    chps_zone: u.chps_zone,
    facility_name: u.facility_name,
    staff_id: u.staff_id,
    preferred_language: u.preferred_language,
    linked_household_id: u.linked_household_id,
    created_at: u.created_at,
  };
}

async function handlePull(req, res) {
  const claims = req.auth && req.auth.claims;
  if (!claims) {
    return res.status(401).json({ ok: false, error: 'Authentication required.' });
  }

  const since = parseWatermark(req.query.since);
  if (since === undefined) {
    return res.status(400).json({
      ok: false,
      error:
        'Invalid since watermark. Send an ISO-8601 timestamp (the server_time ' +
        'of a previous page) or omit it for a full pull.',
    });
  }
  let cursor = Number.parseInt(String(req.query.cursor ?? '0'), 10);
  if (!Number.isFinite(cursor) || cursor < 0) cursor = 0;
  let limit = Number.parseInt(String(req.query.limit ?? ''), 10);
  if (!Number.isFinite(limit) || limit <= 0) limit = PAGE_LIMIT_DEFAULT;
  limit = Math.min(limit, PAGE_LIMIT_MAX);

  try {
    const scope = await resolveScope(claims);
    if (!scope) {
      return res.status(404).json({ ok: false, error: 'Account not found.' });
    }

    const data = {
      households: [],
      persons: [],
      visits: [],
      assessments: [],
      referrals: [],
      care_requests: [],
    };

    let users = null;
    let delivered = 0;
    let hasMore = false;

    if (cursor === 0) {
      // The caller's own profile rides along on the first page of every pull
      // session: it is how a second device learns a name or language edited
      // on the first, at the cost of a single row.
      const [uRows] = await pool.query(
        'SELECT * FROM users WHERE id = ? LIMIT 1',
        [claims.userId]
      );
      users = uRows.length > 0 ? scrubUser(uRows[0]) : null;
    }

    // Every scope runs the same paged loop: householdScope() narrows each
    // table by the FHW tuple/created_by OR by the caregiver's bound
    // household. (A former `if (!scope.caregiverHouseholdId)` guard here
    // skipped the loop entirely for bound caregivers, delivering them an
    // always-empty page — the one thing the contract promises them.)
    let offset = cursor;
    for (const t of PULL_TABLES) {
      const remaining = limit - delivered;
      if (remaining <= 0) {
        // The previous table filled the page exactly — assume more data
        // may remain there; the next page call re-checks it cheaply.
        hasMore = true;
        break;
      }
      const f = tableFilter(t.name, scope);
      const where =
        `(${f.sql}) AND pull_updated_at IS NOT NULL` +
        (since ? ' AND pull_updated_at > ?' : '');
      const [rows] = await pool.query(
        `SELECT * FROM \`${t.name}\` WHERE ${where} ` +
          `ORDER BY pull_updated_at ASC, \`${t.pk}\` ASC LIMIT ? OFFSET ?`,
        [...f.params, ...(since ? [since] : []), remaining, offset]
      );
      // Phase 1 (sync correctness): deliver the marker. The client intersects
      // each row with its own local columns, so it is stored where the schema
      // has a `pull_updated_at` column and harmlessly dropped elsewhere.
      data[t.name] = rows;
      delivered += rows.length;
      if (rows.length < remaining) {
        // This table is exhausted within the watermark; subsequent tables
        // page from their own offset 0.
        offset = 0;
      } else {
        // The page ended exactly at this table's boundary — optimistically
        // assume more rows remain here. If it was actually the end, the
        // next page call returns zero rows for this table and continues.
        hasMore = true;
        break;
      }
    }

    // Read audit, before the response: this is the one data flow in the system
    // that moves a whole district's register onto a handset that then walks out of
    // the compound, and until now it left no trace at all. It can never fail the
    // read — see src/read_audit.js for why that trade-off is deliberate.
    await recordRead({
      claims,
      scope,
      route: 'pull',
      counts: {
        households: data.households.length,
        persons: data.persons.length,
        total: delivered,
      },
      watermark: since,
      cursor,
    });

    return res.status(200).json({
      ok: true,
      scoped_to: {
        user_id: claims.userId,
        role: claims.role,
        region: scope.caregiverHouseholdId ? null : scope.region || null,
        district: scope.caregiverHouseholdId ? null : scope.district || null,
        community: scope.caregiverHouseholdId ? null : scope.community || null,
        linked_household_id: scope.caregiverHouseholdId,
      },
      server_time: new Date().toISOString(),
      since,
      cursor,
      next_cursor: hasMore ? cursor + delivered : null,
      has_more: hasMore,
      page_size: limit,
      delivered,
      data: { ...data, users },
    });
  } catch (err) {
    console.error('Error during delta pull:', err.message);
    return res
      .status(500)
      .json({ ok: false, error: 'Server error during delta pull.' });
  }
}

module.exports = { handlePull };
