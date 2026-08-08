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
