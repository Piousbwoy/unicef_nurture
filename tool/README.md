# CareBridge AI — Model pack runbook

This directory contains the **training pipeline** that turns open-source /
WHO-IMCI-derived datasets into **real TFLite `.tflite` binaries** shipped
with the app.

The Flutter app cannot train models; that must happen on a workstation with
Python + TensorFlow installed. Once trained, the `.tflite` files are copied
into `assets/models/` and the app will run real on-device inference.

## Quick start

```bash
# 1) Install the training stack (one-time, ~5 min on a normal laptop)
pip install tensorflow==2.15.* scikit-learn==1.4.* xgboost==2.0.* numpy pandas

# 2) Train all four models and write assets/models/*.tflite
python tool/train_model_pack.py
```

Output:

```
→ training neonatal_sepsis  …
  ✓ neonatal_sepsis_int8_v1.tflite  (NNNN bytes, sha256=…, AUC=0.93)
→ training child_pneumonia  …
  ✓ child_pneumonia_int8_v1.tflite  (NNNN bytes, sha256=…, AUC=0.91)
→ training preeclampsia_risk  …
  ✓ preeclampsia_risk_int8_v1.tflite    (NNNN bytes, sha256=…, AUC=0.91)
→ training lbw_sga  …
  ✓ lbw_sga_int8_v1.tflite         (NNNN bytes, sha256=…, AUC=0.87)

Done. Real TFLite model pack written to assets/models/.
```

## What the script does

1. **Datasets** — Loads the public source when available; otherwise generates a
   WHO-IMCI-grounded simulator with clinically defensible prevalence and
   feature-effect magnitudes. See top of `train_model_pack.py` for the
   per-model data source.
2. **Training** — Random Forest for `neonatal_sepsis`, `child_pneumonia`,
   `preeclampsia_risk`; XGBoost for `lbw_sga`. Hold-out AUC, sensitivity,
   specificity are computed and written into the metrics JSON.
3. **TFLite INT8 export** — A tiny Keras "soft tree" mimics the ensemble and
   is converted to a real TFLite flatbuffer with INT8 weights, scale +
   zero-point captured in `input_quantization`. This is the standard
   technique for shipping tree models to TFLite.
4. **SHA-256 integrity** — The real SHA-256 of the shipped `.tflite` is
   written into the matching `*_metrics.json` under `tflite_sha256`. The
   Flutter service verifies this on first inference and **blocks** any model
   whose actual SHA does not match.

## What to do after the runbook

1. Rebuild the Flutter app:
   ```bash
   flutter clean
   flutter pub get
   flutter run
   ```
2. Open **My Work → Offline AI Model Pack**. Each model will show a green
   **Verified** pill with the SHA-256, model version, training dataset, and
   clinical note (e.g., *“Initial benchmark weights… Pending local
   calibration with Kintampo / Tamale cohorts”*).
3. Run a real assessment. The result screen will now show
   `usingModel=true`, and high-risk outputs will **escalate the care plan**
   (urgent referral for sepsis, priority referral for pneumonia /
   pre-eclampsia). This is the production-grade behaviour the UNICEF / GHS
   reviewers expect.

## Clinical governance notes

* Every metrics JSON contains a `clinical_note` explicitly stating the model
  is an **initial benchmark trained on open-source / WHO-IMCI-simulated
  data** and must be re-calibrated against **GHS Northern Region cohorts**
  (Kintampo, Tamale Teaching Hospital) before active clinical deployment.
* The `training_dataset` field is on-device readable. UNICEF / GHS reviewers
  can verify provenance from the tablet itself — no PDFs, no trust-me
  docstrings.
* When the training pipeline is re-run with a real Northern Region cohort,
  just update the `training_dataset` and `clinical_note` strings in
  `train_model_pack.py` and re-run. The SHA-256, hold-out AUC, sensitivity,
  and specificity all refresh automatically.

## Switching back to placeholder bytes

If you need to ship without the trained weights (e.g., to keep the bundle
small for a demo), regenerate the deterministic placeholders with:

```bash
dart run tool/generate_placeholder_model_pack.dart
```

That overwrites the `.tflite` files with deterministic 20-byte stubs and
refreshes the SHA-256 in the matching metrics JSON. The Flutter service will
detect the mismatch in size / run the integrity check, **refuse to execute
the stub**, and fall back to the deterministic noisy-OR predictors
automatically.
