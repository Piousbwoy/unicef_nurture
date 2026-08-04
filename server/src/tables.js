// The sync whitelist — the single most important security control on the
// server.
//
// The phone sends `entity_table` and a `payload` object. We NEVER trust either
// to name a table or a column directly. Instead every table and column that may
// be written is declared here, and anything not on the list is rejected (or, for
// stray payload keys, silently dropped). Combined with parameterised values in
// db.js, this means a compromised or malicious client can only ever write to
// the exact columns the app itself writes to — it cannot touch sync_log, cannot
// add columns, cannot inject SQL.
//
// `pk` lists the primary-key column(s) used for idempotent upserts and deletes.
// `children` maps a nested payload key to the table it should be written to
// (a visit carries its roll-call participants inline).
'use strict';

const TABLES = {
  users: {
    pk: ['id'],
    // In our Hybrid Architecture with MariaDB as the Main Server, we sync pin_hash
    // and pin_salt so accounts can be cleanly restored when logging in on a fresh device.
    columns: [
      'id', 'full_name', 'phone', 'role', 'region', 'district', 'community',
      'chps_zone', 'facility_name', 'staff_id', 'preferred_language',
      'linked_household_id', 'pin_hash', 'pin_salt', 'created_at',
    ],
  },
  households: {
    pk: ['id'],
    columns: [
      'id', 'name', 'region', 'district', 'community', 'created_by',
      'head_name', 'contact_phone', 'latitude', 'longitude', 'family_size',
      'has_valid_nhis', 'walking_minutes_to_facility', 'landmark',
      'created_at', 'updated_at',
    ],
  },
  persons: {
    pk: ['id'],
    columns: [
      'id', 'household_id', 'full_name', 'client_type', 'sex', 'date_of_birth',
      'age_years_approx', 'phone', 'mother_id', 'is_dob_estimated',
      'nhis_number', 'created_at', 'updated_at', 'is_active',
    ],
  },
  maternal_records: {
    pk: ['person_id'],
    columns: [
      'person_id', 'gravida', 'parity', 'previous_losses',
      'previous_caesarean', 'last_menstrual_period', 'expected_delivery_date',
      'anc_contacts_completed', 'iptp_doses', 'td_doses',
      'iron_folate_supplied', 'llin_supplied', 'haemoglobin', 'blood_group',
      'sickling_status', 'hiv_tested', 'delivery_date', 'delivery_place',
      'delivery_mode', 'plurality', 'family_planning_method', 'updated_at',
    ],
  },
  birth_records: {
    pk: ['person_id'],
    columns: [
      'person_id', 'birth_weight_kg', 'gestation_weeks_at_birth',
      'delivery_place', 'delivery_mode', 'plurality', 'birth_order',
      'resuscitation_needed', 'cord_care_given', 'vitamin_k_given',
      'breastfed_within_one_hour', 'updated_at',
    ],
  },
  growth_measurements: {
    pk: ['id'],
    columns: [
      'id', 'person_id', 'taken_at', 'muac_cm', 'weight_kg', 'height_cm',
      'has_bilateral_oedema', 'recorded_by',
    ],
  },
  visits: {
    pk: ['id'],
    columns: [
      'id', 'household_id', 'conducted_by', 'started_at', 'completed_at',
      'reasons', 'latitude', 'longitude', 'notes', 'sync_state',
    ],
    // A visit's payload carries its roll call inline; write it to its own table.
    children: { participants: 'visit_participants' },
  },
  visit_participants: {
    pk: ['visit_id', 'person_id'],
    columns: [
      'visit_id', 'person_id', 'was_present', 'absence_note', 'queue_order',
      'assessed',
    ],
  },
  assessments: {
    pk: ['id'],
    columns: [
      'id', 'visit_id', 'person_id', 'client_type', 'performed_by',
      'performed_at', 'inputs_json', 'result_json', 'care_plan_json',
      'overridden_triage', 'override_reason', 'override_by', 'sync_state',
    ],
  },
  referrals: {
    pk: ['id'],
    columns: [
      'id', 'reference_code', 'person_id', 'assessment_id', 'facility_name',
      'reason', 'urgency', 'issued_by', 'issued_at', 'status',
      'status_updated_at', 'clinical_summary', 'arrival_confirmed_by',
      'outcome_notes', 'escalated_at', 'sync_state',
    ],
  },
  barrier_reports: {
    pk: ['id'],
    columns: [
      'id', 'household_id', 'person_id', 'referral_id', 'barriers',
      'recorded_by', 'recorded_at', 'notes', 'resolved', 'sync_state',
    ],
  },
  scheduled_contacts: {
    pk: ['id'],
    columns: [
      'id', 'person_id', 'household_id', 'due_date', 'purpose', 'created_by',
      'completed_at', 'assessment_id', 'priority', 'sync_state',
    ],
  },
};

// The operations the app can legitimately send.
const OPERATIONS = new Set(['insert', 'update', 'delete']);

module.exports = { TABLES, OPERATIONS };
