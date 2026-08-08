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
    //
    // IMPORTANT — Ghana Health Service data-privacy compliance (HOW_IT_WORKS.md):
    // On-device PIN credentials NEVER cross the network. pin_hash and pin_salt
    // live strictly inside local device SQLite and are deliberately excluded
    // from the server-side users table. Cloud authentication is performed
    // against the isolated user_verifiers table using a domain-separated
    // HMAC verifier (see user_verifiers below), which is a one-way derivation
    // that cannot be reversed to yield the on-device pin_hash or the PIN.
    //
    columns: [
      'id', 'full_name', 'phone', 'role', 'region', 'district', 'community',
      'chps_zone', 'facility_name', 'staff_id', 'preferred_language',
      'linked_household_id', 'created_at',
    ],
  },
  //
  // Isolated cloud-authentication table — lives physically separate from the
  // synced clinical records. Nothing in here can be reversed to recover the
  // user's on-device pin_hash or their 4-digit PIN.
  //
  // Scope guard (see sync.js handleSync): a caller may only upsert rows where
  // payload.user_id === their authenticated JWT sub claim (or, for a brand
  // new self-registering device that hasn't obtained a JWT yet, the phone
  // number of the just-created user matches the phone in the legacy token's
  // authenticated context where applicable).
  //
  user_verifiers: {
    pk: ['user_id'],
    columns: [
      'user_id', 'server_salt', 'verifier', 'device_id',
      'created_at', 'updated_at',
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
      'rhesus_positive', 'sickling_status', 'sickle_genotype',
      'hiv_tested', 'hiv_test_date',
      'syphilis_tested', 'syphilis_test_date',
      'hbsag_tested', 'hbsag_test_date',
      'delivery_date', 'delivery_place', 'delivery_mode', 'plurality',
      'family_planning_method',
      'urine_protein', 'urine_glucose', 'urine_ketones', 'urine_blood',
      'oedema_hands_or_face', 'epigastric_pain', 'headache_severe',
      'blurred_vision', 'brisk_reflexes', 'oliguria',
      'weight_gain_over_1kg_per_week',
      'prev_hypertension', 'prev_diabetes', 'prev_anaemia', 'prev_tb',
      'prev_asthma', 'prev_heart_disease', 'prev_kidney_disease',
      'prev_hepatitis',
      'involution_cm_below_umbilicus',
      'lochia_colour', 'lochia_odour', 'lochia_amount',
      'wound_redness', 'wound_oedema', 'wound_discharge',
      'wound_approximated', 'episiotomy_or_laceration',
      'nipples_cracked', 'nipples_inverted', 'breast_mastitis_signs',
      'breast_attachment_ok', 'breast_let_down_ok',
      'edinburgh_laugh', 'edinburgh_enjoy', 'edinburgh_blame',
      'edinburgh_anxious', 'edinburgh_scared', 'edinburgh_overwhelm',
      'edinburgh_sleep', 'edinburgh_sad', 'edinburgh_cry',
      'edinburgh_self_harm',
      'updated_at',
    ],
  },
  birth_records: {
    pk: ['person_id'],
    columns: [
      'person_id', 'birth_weight_kg', 'birth_length_cm',
      'gestation_weeks_at_birth', 'delivery_place', 'delivery_mode',
      'plurality', 'birth_order',
      'resuscitation_needed', 'apgar_1_minute', 'apgar_5_minute',
      'cord_care_given', 'cord_chlorhexidine_applied',
      'vitamin_k_given', 'vitamin_k_dose_mg',
      'breastfed_within_one_hour', 'breastfeeding_ok_on_day1',
      'temperature_celsius', 'respiratory_rate_per_min',
      'heart_rate_per_min', 'oxygen_saturation_per_cent',
      'history_of_convulsions', 'severe_chest_indrawing',
      'nasal_flaring', 'grunting', 'bulging_fontanelle',
      'jaundice_before_24h', 'jaundice_on_day3_or_later',
      'feeding_difficulty', 'abdominal_distension',
      'cord_redness_beyond_base', 'cord_pus', 'cord_oedema_beyond_base',
      'skin_pustules', 'lethargic_or_unconscious', 'bleeding_from_any_site',
      'kmc_eligible', 'kmc_initiated', 'kmc_site', 'kmc_hours_per_day',
      'sickle_screen_sample_collected', 'sickle_screen_sample_date',
      'hearing_screen_done', 'hearing_screen_result',
      'updated_at',
    ],
  },
  growth_measurements: {
    pk: ['id'],
    columns: [
      'id', 'person_id', 'taken_at',
      'muac_mm', 'muac_cm', 'weight_kg', 'height_cm',
      'has_bilateral_oedema', 'palmar_pallor_severity', 'recorded_by',
    ],
  },
  child_assessment_snapshots: {
    pk: ['id'],
    columns: [
      'id', 'person_id', 'assessed_at', 'visit_type', 'age_days_completed',
      'able_to_drink_or_breastfeed', 'vomits_everything',
      'has_convulsions_this_visit', 'is_lethargic_or_unconscious',
      'cough_present', 'cough_duration_days', 'respiratory_rate_per_min',
      'chest_indrawing', 'stridor_calm', 'nasal_flaring',
      'oxygen_saturation_per_cent',
      'diarrhoea_present', 'diarrhoea_duration_days', 'blood_in_stool',
      'restless_or_irritable', 'sunken_eyes', 'drinks_eagerly',
      'skin_pinch_result',
      'fever_reported', 'fever_duration_days', 'temperature_celsius',
      'stiff_neck', 'runny_nose',
      'measles_rash_present', 'measles_cough', 'measles_coryza',
      'measles_conjunctivitis', 'mouth_ulcers', 'eye_discharge',
      'corneal_clouding', 'measles_within_past_3_months',
      'malaria_rdt_done', 'malaria_rdt_result',
      'tourniquet_test_done', 'tourniquet_test_positive',
      'skin_petechiae', 'capillary_refill_seconds',
      'ear_problem_present', 'ear_pain_duration_days',
      'ear_pus_draining', 'ear_pus_duration_days',
      'tender_swelling_behind_ear',
      'weight_for_height_or_length_zscore',
      'hiv_exposed_or_infected_status', 'able_to_finish_rutf',
      'breastfed_today', 'night_feeds_per_24h',
      'complementary_foods_given_today',
      'minimum_dietary_diversity', 'minimum_meal_frequency',
      'minimum_acceptable_diet',
      'immunizations_due_today', 'immunizations_given_today',
      'assessed_by_user_id', 'recorded_by_user_id',
      'updated_at',
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
