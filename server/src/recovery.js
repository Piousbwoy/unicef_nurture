// Account recovery and downstream data restoration for CareBridge Hybrid Architecture.
//
// SECURITY MODEL (post-P0-auth rewrite):
//
// Both endpoints are protected by requireJwtUser — the caller MUST present a
// valid per-user JWT (legacy global tokens are rejected). The PIN-verification
// step happens in the /api/auth/login endpoint; these endpoints do not touch
// the verifier or PIN material at all.
//
// P0-SEC-B SCOPE RULES (ENFORCED HERE, NOT NEGOTIABLE):
//
//   * handleProfileLookup — return only the profile of the authenticated user.
//     The server ignores any body.phone parameter; it replies with the phone +
//     profile the JWT claims describe. A caregiver JWT can fetch ONLY its own
//     profile; a FHW JWT can fetch ONLY its own profile. No enumeration.
//
//   * handleCaseloadRestore — server IGNORES query/body user_id, role,
//     household_id. It derives them ALL from the JWT claims instead:
//        - caregiver: restore households/persons linked to JWT.linked_household
//          (never any other id passed by a caller who happens to know a UUID)
//        - frontlineHealthWorker: restore (region, district, community) from
//          JWT claims, plus households.created_by === JWT.sub
//     NEVER return a different district/community than the caller is cleared
//     for. This closes the caseload-exfiltration cross-district bug.
//
// PIN hash and salt are NEVER returned by any endpoint here. The user object
// is scrubbed before responding.
'use strict';

const { pool } = require('./db');

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

async function handleProfileLookup(req, res) {
  const claims = req.auth && req.auth.claims;
  if (!claims) {
    return res.status(401).json({ ok: false, error: 'Authentication required.' });
  }
  try {
    const [rows] = await pool.query(
      'SELECT * FROM users WHERE id = ? LIMIT 1',
      [claims.userId]
    );
    if (rows.length === 0) {
      return res.status(404).json({ ok: false, error: 'Account not found.' });
    }
    return res.status(200).json({ ok: true, user: scrubUser(rows[0]) });
  } catch (err) {
    console.error('Error during profile lookup:', err.message);
    return res.status(500).json({ ok: false, error: 'Server error during profile lookup.' });
  }
}

async function handleCaseloadRestore(req, res) {
  const claims = req.auth && req.auth.claims;
  if (!claims) {
    return res.status(401).json({ ok: false, error: 'Authentication required.' });
  }
  const userId = claims.userId;
  const role = claims.role; // 'frontlineHealthWorker' | 'caregiver' | 'supervisor'

  // Explicitly IGNORE any user-provided user_id, role, or household_id.
  // Scope is derived entirely from the verified JWT.

  try {
    // Resolve the full user row first (we need linked_household_id for
    // caregivers, which isn't baked into the JWT claims currently).
    const [uRows] = await pool.query(
      'SELECT linked_household_id, role, region, district, community FROM users WHERE id = ? LIMIT 1',
      [userId]
    );
    if (uRows.length === 0) {
      return res.status(404).json({ ok: false, error: 'Account not found.' });
    }
    const user = uRows[0];

    let households = [];
    let persons = [];
    let assessments = [];
    let visits = [];
    let referrals = [];

    const isCaregiver = role === 'caregiver' || user.role === 'caregiver';
    if (isCaregiver && user.linked_household_id) {
      const householdId = user.linked_household_id;
      const [hRows] = await pool.query('SELECT * FROM households WHERE id = ?', [householdId]);
      households = hRows;

      const [pRows] = await pool.query('SELECT * FROM persons WHERE household_id = ?', [householdId]);
      persons = pRows;

      if (persons.length > 0) {
        const pIds = persons.map((p) => p.id);
        const placeholders = pIds.map(() => '?').join(',');
        const [aRows] = await pool.query(
          `SELECT * FROM assessments WHERE person_id IN (${placeholders})`,
          pIds
        );
        assessments = aRows;
        const [rRows] = await pool.query(
          `SELECT * FROM referrals WHERE person_id IN (${placeholders})`,
          pIds
        );
        referrals = rRows;
      }
    } else {
      // Frontline worker — restore households in their JWT (region, district,
      // community) tuple OR created_by === their user_id. Source of truth is
      // the JWT claims (claims.region etc.), NOT user input.
      const region = claims.region || user.region;
      const district = claims.district || user.district;
      const community = claims.community || user.community;
      const [hRows] = await pool.query(
        'SELECT * FROM households WHERE (region = ? AND district = ? AND community = ?) OR created_by = ?',
        [region, district, community, userId]
      );
      households = hRows;

      if (households.length > 0) {
        const hIds = households.map((h) => h.id);
        const placeholders = hIds.map(() => '?').join(',');
        const [pRows] = await pool.query(
          `SELECT * FROM persons WHERE household_id IN (${placeholders})`,
          hIds
        );
        persons = pRows;

        if (persons.length > 0) {
          const pIds = persons.map((p) => p.id);
          const pPlaceholders = pIds.map(() => '?').join(',');
          const [aRows] = await pool.query(
            `SELECT * FROM assessments WHERE person_id IN (${pPlaceholders})`,
            pIds
          );
          assessments = aRows;
          const [rRows] = await pool.query(
            `SELECT * FROM referrals WHERE person_id IN (${pPlaceholders})`,
            pIds
          );
          referrals = rRows;
        }

        const [vRows] = await pool.query(
          `SELECT * FROM visits WHERE household_id IN (${placeholders})`,
          hIds
        );
        visits = vRows;
      }
    }

    return res.status(200).json({
      ok: true,
      scoped_to: {
        user_id: userId,
        role,
        region: claims.region || null,
        district: claims.district || null,
        community: claims.community || null,
        linked_household_id: user.linked_household_id || null,
      },
      data: {
        households,
        persons,
        assessments,
        visits,
        referrals,
      },
    });
  } catch (err) {
    console.error('Error during caseload restoration:', err.message);
    return res.status(500).json({ ok: false, error: 'Server error during caseload restoration.' });
  }
}

module.exports = { handleProfileLookup, handleCaseloadRestore };
