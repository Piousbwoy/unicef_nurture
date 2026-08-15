# CareBridge AI — Offline TFLite Model Pack

This directory contains the on-device risk-prediction models that run **fully
offline** on Android/iOS tablets.

## Inference order (production)

1. **TFLite interpreter (PRIMARY)** — `Interpreter.fromAsset(...)` from
   `tflite_flutter`, with a real `run(input, output)` tensor pass and a
   calibrated probability extracted from the output. See
   `lib/core/ml/tflite_runner_io.dart`.
2. **Deterministic noisy-OR fallback (SECONDARY)** — only runs when the TFLite
   model is missing, the SHA-256 mismatch, the asset fails to load, or the
   interpreter throws. See the `_neonatalSepsisFallback` /
   `_childPneumoniaFallback` / `_preeclampsiaFallback` / `_lbwSgaFallback`
   routines in `lib/core/ml/offline_inference_service.dart`.

## Required files

| Model | `.tflite` asset | Metrics JSON |
| --- | --- | --- |
| Neonatal sepsis (0–59d PSBI) | `neonatal_sepsis_int8_v1.tflite` | `neonatal_sepsis_int8_v1_metrics.json` |
| Child pneumonia (2–59m) | `child_pneumonia_int8_v1.tflite` | `child_pneumonia_int8_v1_metrics.json` |
| Pre-eclampsia (ANC 20w+) | `preeclampsia_risk_int8_v1.tflite` | `preeclampsia_risk_int8_v1_metrics.json` |
| LBW / SGA | `lbw_sga_int8_v1.tflite` | `lbw_sga_int8_v1_metrics.json` |

## How to read these numbers

Not every AUC in the metrics JSONs means the same thing. The app UI frames
each block this way, and auditors should too:

| Model | Trained on | Headline number | The other number |
| --- | --- | --- | --- |
| Neonatal sepsis | **Real patient records** (Mbarara RRH EMR, Uganda, n=964 — `training_dataset` carries the `REAL:` prefix) | **Cross-validation AUC 0.90** — this is the evidence | PhysioNet adult-ICU check (AUC ≈ 0.51) is a deliberate out-of-domain transfer check; near-chance is *expected* |
| Pre-eclampsia | Simulator seeded from published Ghana studies | **External check on real patients: UCI Bangladesh AUC 0.74** (sens 0.53 / spec 0.96) | Internal hold-out (AUC 1.0) is the model predicting its own simulator — **sanity check only, not evidence** |
| Child pneumonia | Simulator seeded from WHO IMCI + Baiden 2011 | *No external check yet* — internal numbers are a simulator self-check | Same circularity caveat; treat as a screening aid |
| LBW / SGA | Simulator seeded from Savelugu (Northern Region) + MICS studies | *No external check yet* — internal numbers are a simulator self-check | Same circularity caveat; treat as a screening aid |

The rule the code enforces (`OfflineModelStatus.headlineValidation`): a model
trained on real patients leads with its cross-validation; a simulator-seeded
model leads with its external check, and its internal numbers are always
labelled a sanity check.

## Recalibration pathway (Northern Ghana)

The version ladders in the metrics JSONs name the way forward:
`v2.0-kintampo-cohort` → `v3.0-prospective-pilot`. This is how a
simulator-seeded model earns a real-data headline:

1. **Collect** — the app builds de-identified recalibration records on-device
   (see `lib/core/ml/recalibration_export.dart`). A record carries the model
   inputs (numeric/boolean only), the model's probability and tier, the
   engine and final triage, whether a referral was issued, the district, an
   age *band*, the month, and a salted SHA-256 `personKey` for linkage. No
   names, no phone numbers, no community, no exact dates, no raw person ids.
2. **Export** — records leave the device only with GHS approval, as JSONL,
   for the Kintampo Health Research Centre and Navrongo HDSS pipelines. The
   district health information officer signs the export; the salt is held by
   GHS, not shipped with the app.
3. **Recalibrate quarterly** — KHRC/Navrongo refit Platt scaling (A/B) and
   the CI table per district, and recompute the drift baselines. If a model's
   real-world calibration holds (Brier not worse than the shipped baseline),
   only the metrics JSON is re-issued; weights stay put.
4. **Promote** — when a cohort is large enough to retrain (KHRC guidance:
   ~5,000 records with outcome linkage), retrain, validate against the
   held-out district split, and ship `v2.0-kintampo-cohort` with a new
   SHA-256. Only then does the model's headline become Ghanaian patient data.

## Metrics JSON contract

Each `*_metrics.json` must contain:

```json
{
  "tflite_sha256": "<sha256 of the .tflite bytes>",
  "model_version": "v1.0",
  "trained_on": "YYYY-MM-DD",
  "validation": {
    "holdout_auc": 0.93,
    "sensitivity": 0.88,
    "specificity": 0.85
  },
  "input_feature_order": ["age_days", "temperature_celsius", "..."],
  "input_quantization": { "scale": 0.0078125, "zero_point": -128 }
}
```

The `input_feature_order` array **must match the schema** in
`OfflineInferenceService._inputSchemaFor(name)`. If a feature is missing or
out of order, the runner will block the model and the UI will report a
mismatch in **My Work → Offline AI Model Pack**.

## SHA-256 verification

The `OfflineInferenceService` computes the SHA-256 of each shipped `.tflite`
on first use and compares it to the `tflite_sha256` field in the metrics JSON.
If they do not match, the model is **blocked** (treated as unavailable) and
the deterministic fallback runs. This is the integrity guarantee auditors
require: tampered weights cannot produce a false “Verified” status.

## Training pipeline output

The `.tflite` binaries must come from your training pipeline (TensorFlow /
TFLite converter, or a sklearn→TFLite converter for tree models). The Flutter
app does not generate or fabricate weights.
