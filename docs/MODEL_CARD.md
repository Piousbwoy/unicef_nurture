# CareBridge AI — Model Cards

Generated from `assets/models/*_metrics.json` and
`assets/models/research_contracts.json` by `tool/build_model_cards.py`.
Generated: 2026-10-22 05:45 UTC

**These cards describe research artefacts.** No model in this repository
is validated for clinical use in Northern Ghana. The deterministic
WHO/GHS protocol engines make every clinical decision; models may supply
an experimental, clearly-labelled signal and never change treatment or
referral.

## Summary

| model | evidence | patient output | clinical use | evaluated |
| --- | --- | --- | --- | --- |
| neonatal_sepsis | legacy_real_data | yes | no | legacy_teacher_only |
| preeclampsia_risk | synthetic | no | no | legacy_teacher_only |
| child_pneumonia | synthetic | no | no | legacy_teacher_only |
| lbw_sga | synthetic | no | no | legacy_teacher_only |

## neonatal_sepsis

- **Version:** v2.0-real-data-neonatal_sepsis
- **Training data:** REAL: Mbarara RRH neonatal sepsis EMR, Uganda (964 rows [756 positive, 208 negative]; age 0-3 days; vitals + feeding/lethargy signs)
- **Cohort:** young_infant
- **Permitted use:** experimental display only (clinician_experimental); clinical use not permitted
- **Artifact SHA-256:** `b40ce5c43958b16bf6508887f49d79e7de7c0e6b8c4fd68ffabefb8a8d2b0fff`
- **Calibration validated for this artifact:** False

### Internal validation

| metric | value |
| --- | --- |
| `method` | 5-fold stratified cross-validation (pooled OOF) |
| `holdout_auc` | 0.9 |
| `fold_auc_mean` | 0.9039 |
| `fold_auc_std` | 0.0326 |
| `sensitivity` | 0.7778 |
| `specificity` | 0.9327 |
| `youden_j` | 0.7105 |
| `best_threshold` | 0.0158 |
| `n_pool` | 964 |
| `n_folds` | 5 |
| `fold_size` | 193 |
| `oof_n` | 964 |
| `calibration.method` | platt_scaling |
| `calibration.A` | 2.013769 |
| `calibration.B` | -5.826344 |
| `calibration.brier_score` | 0.4108 |
| `calibration.conformal_q95` | 0.9955 |
| `calibration.conformal_note` | 95th percentile of |p_cal - y| on out-of-fold predictions; [p - q, p + q] covers the true label for >= 95% of patients like the fold pool (exchangeability assumed). |
| `calibration.ci_table` | 10 entries (see model_cards.json) |
| `calibration.prior_adjustment.cohort_prior` | 0.7842 |
| `calibration.prior_adjustment.target_prior` | 0.02 |
| `calibration.prior_adjustment.logit_shift` | -5.1823 |
| `calibration.prior_adjustment.note` | Platt intercept re-anchored so calibrated probabilities express P(sepsis) at the Ghana CHPS prior used by the deterministic fallback. Discrimination (AUC) unchanged. |
| `calibration.prior_adjustment.cohort_scale_brier` | 0.1021 |
| `calibration.prior_adjustment.target_prior_baseline_brier` | 0.0196 |
| `calibration.brier_score_cohort_scale` | 0.1021 |

### External / out-of-domain checks

| metric | value |
| --- | --- |
| `dataset` | PhysioNet 2019 adult ICU (n=4000) - out-of-domain transfer check |
| `n` | 4000 |
| `holdout_auc` | 0.5112 |
| `sensitivity` | 0.2689 |
| `specificity` | 0.8155 |
| `youden_j` | 0.0844 |
| `best_threshold` | 0.68 |
| `calibrated_brier` | 0.0293 |

### Inputs

- Observed at inference: age_days, temperature_celsius, respiratory_rate_per_min, heart_rate_per_min, birth_weight_kg, feeding_difficulty, lethargic_unconscious
- Fixed / zero-imputed: 13 (oxygen_saturation_per_cent, apgar_5_minute, history_of_convulsions, severe_chest_indrawing, nasal_flaring_grunting, bulging_fontanelle, jaundice_before_24h, abdominal_distension, cord_infection, skin_pustules, bleeding, hiv_exposed, multiple_birth)

### Limitations

- Legacy feeding/lethargy encoding discarded Yes/No observations
- Weight meaning differs from the app's birth-weight field
- Published metrics describe the teacher, not an independently evaluated exported model
- Not clinically validated for Northern Ghana
- No individual probability confidence interval
- Current measured weight is an experimental proxy for source admission weight; measurement timing unverified

### Notes

Trained on REAL clinical data (Mbarara Regional Referral Hospital (Uganda), neonatal admissions; n=964, 756 cases). Features absent from the source cohort (13 zero-filled) are learned as constants by the model; the deterministic WHO/GHS rules in the app cover those red lines at runtime (the selector ORs AI risk with clinical danger signs). Calibration: logit-correct Platt scaling fitted on 5-fold out-of-fold predictions; 95% CI from per-bin residual std. Training features are the SAME [0,1]-normalized representation the app feeds at inference (v1.0 had a raw-scale train/serve skew - fixed). Cohort: Mbarara Regional Referral Hospital (Uganda), neonatal admissions; population transfer to the Northern Ghana CHPS context is unvalidated. Decision-support, not diagnosis.

## preeclampsia_risk

- **Version:** v1.1-ghana-baseline-normalized-serving
- **Training data:** [M1] Adokiya 2022 (Hb); [M7] Charadan 2025 (PIH); [M8] Bugri 2023 (HTN); [M9] Boafo 2025 (PE meta)
- **Cohort:** maternal
- **Permitted use:** no patient-facing output permitted
- **Artifact SHA-256:** `90c6a8d25de4d0fd88deda045b41ca7da3271a71e9fac0f4ad110adbb70698bf`
- **Calibration validated for this artifact:** not recorded

### Internal validation

| metric | value |
| --- | --- |
| `holdout_auc` | 1.0 |
| `sensitivity` | 1.0 |
| `specificity` | 0.9994 |
| `youden_j` | 0.9994 |
| `best_threshold` | 0.5 |
| `n_train` | 8000 |
| `n_test` | 2000 |
| `calibration.method` | platt_scaling |
| `calibration.A` | 3.173835 |
| `calibration.B` | -0.467574 |
| `calibration.brier_score` | 0.1357 |
| `calibration.ci_table` | 10 entries (see model_cards.json) |

### External / out-of-domain checks

| metric | value |
| --- | --- |
| `dataset` | UCI Machine Learning Repository: Maternal Health Risk Data Set (Ahmed M., 2018; Bangladesh-origin). Held out; scored through the same SCHEMA_NORM normalization the app applies at inference. |
| `n` | 1006 |
| `holdout_auc` | 0.7365 |
| `sensitivity` | 0.5279 |
| `specificity` | 0.9607 |
| `youden_j` | 0.4885 |
| `best_threshold` | 0.18 |
| `calibrated_brier` | 0.1846 |

### Limitations

- Synthetic training does not establish patient-level predictive performance
- Not clinically validated for Northern Ghana
- No individual probability confidence interval

### Notes

v1.1 normalization-skew fix. Same Ghana-priors simulator cohort as v1.0 (5 citation groups), but the distilled MLP is trained and served on the [0,1] SCHEMA_NORM representation - the exact tensor the app feeds at inference. v1.0 distilled from RAW feature scales, so its input quantization clamped every app input to ~0 (train/serve skew); v1.1's flatbuffer input quantization covers [0,1] (scale=0.003922, zero_point=-128). Calibration via Platt scaling on the internal 20% hold-out; 95% CI from per-bin Platt-residual std; drift detection via per-feature z-score against the normalized training distribution.

## child_pneumonia

- **Version:** v1.1-ghana-baseline-normalized-serving
- **Training data:** [M14] WHO IMCI 2014 (pneumonia cutoffs); [M10] Baiden 2011 (CHO RR under-counting correction)
- **Cohort:** child
- **Permitted use:** no patient-facing output permitted
- **Artifact SHA-256:** `a0479dc800c132f2d9f985cbc3117995725545bf8df65dce4b5091210384af5a`
- **Calibration validated for this artifact:** not recorded

### Internal validation

| metric | value |
| --- | --- |
| `holdout_auc` | 0.7424 |
| `sensitivity` | 0.8783 |
| `specificity` | 0.4826 |
| `youden_j` | 0.3609 |
| `best_threshold` | 0.23 |
| `n_train` | 6400 |
| `n_test` | 1600 |
| `calibration.method` | platt_scaling |
| `calibration.A` | 1.128274 |
| `calibration.B` | 0.100092 |
| `calibration.brier_score` | 0.2933 |
| `calibration.ci_table` | 10 entries (see model_cards.json) |

### External / out-of-domain checks

_None recorded._

### Limitations

- Synthetic training does not establish patient-level predictive performance
- Not clinically validated for Northern Ghana
- No individual probability confidence interval

### Notes

v1.1 normalization-skew fix. Same Ghana-priors simulator cohort as v1.0 (2 citation groups), but the distilled MLP is trained and served on the [0,1] SCHEMA_NORM representation - the exact tensor the app feeds at inference. v1.0 distilled from RAW feature scales, so its input quantization clamped every app input to ~0 (train/serve skew); v1.1's flatbuffer input quantization covers [0,1] (scale=0.003922, zero_point=-128). Calibration via Platt scaling on the internal 20% hold-out; 95% CI from per-bin Platt-residual std; drift detection via per-feature z-score against the normalized training distribution.

## lbw_sga

- **Version:** v1.1-ghana-baseline-normalized-serving
- **Training data:** [M3] Adjei-Gyamfi 2023 Savelugu (LBW); [M5] Fosu 2013 (Northern MICS); [M1] Adokiya 2022 (Hb)
- **Cohort:** maternal
- **Permitted use:** no patient-facing output permitted
- **Artifact SHA-256:** `096cbd93b0995b9e41d7c8eca6126a53297cdd753ea8fbc643db32b736ec2d87`
- **Calibration validated for this artifact:** not recorded

### Internal validation

| metric | value |
| --- | --- |
| `holdout_auc` | 0.9646 |
| `sensitivity` | 0.8976 |
| `specificity` | 0.9006 |
| `youden_j` | 0.7983 |
| `best_threshold` | 0.15 |
| `n_train` | 8000 |
| `n_test` | 2000 |
| `calibration.method` | platt_scaling |
| `calibration.A` | 0.737536 |
| `calibration.B` | 0.03138 |
| `calibration.brier_score` | 0.2407 |
| `calibration.ci_table` | 10 entries (see model_cards.json) |

### External / out-of-domain checks

_None recorded._

### Limitations

- Synthetic training does not establish patient-level predictive performance
- Not clinically validated for Northern Ghana
- No individual probability confidence interval

### Notes

v1.1 normalization-skew fix. Same Ghana-priors simulator cohort as v1.0 (4 citation groups), but the distilled MLP is trained and served on the [0,1] SCHEMA_NORM representation - the exact tensor the app feeds at inference. v1.0 distilled from RAW feature scales, so its input quantization clamped every app input to ~0 (train/serve skew); v1.1's flatbuffer input quantization covers [0,1] (scale=0.003922, zero_point=-128). Calibration via Platt scaling on the internal 20% hold-out; 95% CI from per-bin Platt-residual std; drift detection via per-feature z-score against the normalized training distribution.
