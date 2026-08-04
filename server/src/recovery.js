// Account recovery and downstream data restoration for CareBridge Hybrid Architecture.
//
// When a health worker or caregiver sets up the app on a fresh device with an empty
// SQLite database, the app reaches out to the Main MariaDB Server to lookup their
// profile and retrieve their associated clinical records.
'use strict';

const { pool } = require('./db');

async function handleProfileLookup(req, res) {
  const { phone } = req.body || {};
  if (!phone || typeof phone !== 'string' || !phone.trim()) {
    return res.status(400).json({ ok: false, error: 'Phone number is required for lookup.' });
  }

  try {
    const [rows] = await pool.query(
      'SELECT * FROM users WHERE phone = ? LIMIT 1',
      [phone.trim()]
    );

    if (rows.length === 0) {
      return res.status(404).json({ ok: false, error: 'No account found on the Main Server for this phone number.' });
    }

    const user = rows[0];
    return res.status(200).json({ ok: true, user });
  } catch (err) {
    // eslint-disable-next-line no-console
    console.error('Error during profile lookup:', err.message);
    return res.status(500).json({ ok: false, error: 'Server error during profile lookup.' });
  }
}

async function handleCaseloadRestore(req, res) {
  const userId = req.query.user_id || req.body.user_id;
  const role = req.query.role || req.body.role;
  const householdId = req.query.household_id || req.body.household_id;

  if (!userId) {
    return res.status(400).json({ ok: false, error: 'user_id is required for caseload restoration.' });
  }

  try {
    let households = [];
    let persons = [];
    let assessments = [];
    let visits = [];
    let referrals = [];

    if (role === 'caregiver' && householdId) {
      // For a caregiver, restore their linked household and family members
      const [hRows] = await pool.query('SELECT * FROM households WHERE id = ?', [householdId]);
      households = hRows;

      const [pRows] = await pool.query('SELECT * FROM persons WHERE household_id = ?', [householdId]);
      persons = pRows;

      if (persons.length > 0) {
        const pIds = persons.map(p => p.id);
        const placeholders = pIds.map(() => '?').join(',');
        const [aRows] = await pool.query(`SELECT * FROM assessments WHERE person_id IN (${placeholders})`, pIds);
        assessments = aRows;

        const [rRows] = await pool.query(`SELECT * FROM referrals WHERE person_id IN (${placeholders})`, pIds);
        referrals = rRows;
      }
    } else {
      // For frontline health workers (CHOs, nurses), restore households created in their community or by them
      const [uRows] = await pool.query('SELECT region, district, community FROM users WHERE id = ?', [userId]);
      if (uRows.length > 0) {
        const { region, district, community } = uRows[0];
        const [hRows] = await pool.query(
          'SELECT * FROM households WHERE (region = ? AND district = ? AND community = ?) OR created_by = ?',
          [region, district, community, userId]
        );
        households = hRows;
      }

      if (households.length > 0) {
        const hIds = households.map(h => h.id);
        const placeholders = hIds.map(() => '?').join(',');
        const [pRows] = await pool.query(`SELECT * FROM persons WHERE household_id IN (${placeholders})`, hIds);
        persons = pRows;

        if (persons.length > 0) {
          const pIds = persons.map(p => p.id);
          const pPlaceholders = pIds.map(() => '?').join(',');
          const [aRows] = await pool.query(`SELECT * FROM assessments WHERE person_id IN (${pPlaceholders})`, pIds);
          assessments = aRows;

          const [rRows] = await pool.query(`SELECT * FROM referrals WHERE person_id IN (${pPlaceholders})`, pIds);
          referrals = rRows;
        }

        const [vRows] = await pool.query(`SELECT * FROM visits WHERE household_id IN (${placeholders})`, hIds);
        visits = vRows;
      }
    }

    return res.status(200).json({
      ok: true,
      data: {
        households,
        persons,
        assessments,
        visits,
        referrals,
      },
    });
  } catch (err) {
    // eslint-disable-next-line no-console
    console.error('Error during caseload restoration:', err.message);
    return res.status(500).json({ ok: false, error: 'Server error during caseload restoration.' });
  }
}

module.exports = { handleProfileLookup, handleCaseloadRestore };
