"""
CareBridge AI - normalization-skew fix (v1.1-normalized-serving).

Fixes the v1.0 train/serve skew for the three simulator-seeded models
(child_pneumonia, preeclampsia_risk, lbw_sga).

The defect (documented in train_real_models.py, defect #2): v1.0 distilled
its MLPs from RAW feature scales (e.g. systolic BP 80-180, respiratory
rate 16-100), so the exported flatbuffer's int8 input quantization covers
a huge range (scale ~1.5-14). The Dart runtime feeds [0,1]-normalized
features, which quantize to ~0 for every feature -> the model saw a
near-constant input and produced near-constant outputs at runtime. The
neonatal_sepsis model was already retrained correctly by
train_real_models.py (v2.0-real-data) and is NOT touched here.

This script retrains the three simulators end-to-end on the NORMALIZED
representation (the exact SCHEMA_NORM the app applies at inference), so
the exported input quantization covers [0, 1] and train/serve agree.
Everything downstream is re-issued honestly from the new models:
internal validation, Platt A/B, per-bin CI table, drift baseline,
external UCI check for preeclampsia (normalized through the same
schema), input_quantization read back from the converted flatbuffer,
and the SHA-256 integrity pin.

Deterministic: fixed seeds + TF_ENABLE_ONEDNN_OPTS=0, no network access
(UCI csv is cached in tool/datasets/).
"""

from __future__ import annotations

import hashlib
import io
import json
import os
import sys
from datetime import date

import numpy as np

os.environ.setdefault("TF_ENABLE_ONEDNN_OPTS", "0")
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8",
                              errors="replace")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from sklearn.ensemble import RandomForestClassifier  # noqa: E402
from sklearn.linear_model import LogisticRegression  # noqa: E402
from sklearn.metrics import brier_score_loss, roc_auc_score  # noqa: E402
from sklearn.model_selection import train_test_split  # noqa: E402

import tensorflow as tf  # noqa: E402
import xgboost as xgb  # noqa: E402

from train_model_pack import (  # noqa: E402
    PNEUMONIA_FEATURES,
    PREECLAMPSIA_FEATURES,
    LBW_SGA_FEATURES,
    SCHEMA_NORM,
    ALL_SOURCES,
    _sim_pneumonia,
    _sim_preeclampsia,
    _sim_lbw_sga,
    _load_uci_maternal,
    _normalize_column,
    _youden,
)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS_DIR = os.path.join(ROOT, "assets", "models")

VERSION = "v1.1-ghana-baseline-normalized-serving"
VERSION_NEXT = "v2.0-kintampo-cohort"
TODAY = date.today().isoformat()

# The v1.0 runs that shipped the current (skewed) binaries: same simulator
# functions, same seeds, same cohort sizes. Regeneration is therefore
# bit-identical to the original cohorts; only the representation the
# models train/serve on changes.
SPECS = [
    ("child_pneumonia", _sim_pneumonia, PNEUMONIA_FEATURES,
     "[M14] WHO IMCI 2014 (pneumonia cutoffs); [M10] Baiden 2011 (CHO RR "
     "under-counting correction)",
     ["[M10]", "[M11]+[M14]"]),
    ("preeclampsia_risk", _sim_preeclampsia, PREECLAMPSIA_FEATURES,
     "[M1] Adokiya 2022 (Hb); [M7] Charadan 2025 (PIH); [M8] Bugri 2023 "
     "(HTN); [M9] Boafo 2025 (PE meta)",
     ["[M1]", "[M4]", "[M7]", "[M8]", "[M9]"]),
    ("lbw_sga", _sim_lbw_sga, LBW_SGA_FEATURES,
     "[M3] Adjei-Gyamfi 2023 Savelugu (LBW); [M5] Fosu 2013 (Northern "
     "MICS); [M1] Adokiya 2022 (Hb)",
     ["[M1]", "[M3]", "[M5]", "[M6]"]),
]


def _normalize_matrix(X_raw: np.ndarray, features: list) -> np.ndarray:
    cols = [_normalize_column(f, X_raw[:, j])
            for j, f in enumerate(features)]
    return np.stack(cols, axis=1).astype(np.float32)


def _distill_tflite_int8(clf, X_raw, X_norm, name):
    """Distill tree -> MLP on the NORMALIZED representation and export
    TFLite INT8. Returns (bytes, input_scale, input_zero_point) with the
    quantization params read back from the converted flatbuffer."""
    tf.random.set_seed(42)
    np.random.seed(42)
    tf.keras.utils.set_random_seed(42)
    p = clf.predict_proba(X_raw)[:, 1].astype(np.float32)
    inputs = tf.keras.Input(shape=(X_norm.shape[1],), name="features")
    x = tf.keras.layers.Dense(32, activation="relu")(inputs)
    x = tf.keras.layers.Dense(16, activation="relu")(x)
    out = tf.keras.layers.Dense(1, activation="sigmoid", name="prob")(x)
    model = tf.keras.Model(inputs, out)
    model.compile(optimizer="adam", loss="binary_crossentropy",
                  metrics=["AUC"])
    model.fit(X_norm, p, epochs=40, batch_size=64, verbose=0)
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.target_spec.supported_ops = [
        tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
    converter.inference_input_type = tf.int8
    converter.inference_output_type = tf.float32

    def _rep():
        for i in range(0, min(200, len(X_norm)), 10):
            yield [X_norm[i:i + 10].astype(np.float32)]

    converter.representative_dataset = _rep
    tflite_bytes = converter.convert()

    interp = tf.lite.Interpreter(model_content=tflite_bytes)
    interp.allocate_tensors()
    quant = interp.get_input_details()[0].get("quantization", (0.0, 0))
    return tflite_bytes, float(quant[0]), int(quant[1])


def _platt_with_ci(y_true, p_in, n_bins=10):
    eps = 1e-7
    p_clip = np.clip(p_in, eps, 1 - eps)
    z = np.log(p_clip / (1 - p_clip)).reshape(-1, 1)
    lr = LogisticRegression(C=1.0, solver="lbfgs", max_iter=200)
    lr.fit(z, y_true)
    A = float(lr.coef_[0][0])
    B = float(lr.intercept_[0])
    p_cal = 1.0 / (1.0 + np.exp(-(A * p_clip + B)))
    brier = float(brier_score_loss(y_true, p_cal))
    residuals = p_cal - y_true
    edges = np.linspace(0.0, 1.0, n_bins + 1)
    ci_table = []
    for i in range(n_bins):
        lo, hi = float(edges[i]), float(edges[i + 1])
        if i == n_bins - 1:
            mask = (p_cal >= lo) & (p_cal <= hi)
        else:
            mask = (p_cal >= lo) & (p_cal < hi)
        n_in = int(mask.sum())
        if n_in >= 2:
            res_std = float(np.std(residuals[mask], ddof=1))
        elif n_in == 1:
            res_std = float(abs(residuals[mask][0]))
        else:
            res_std = None
        ci_table.append({
            "bin_lo": round(lo, 4), "bin_hi": round(hi, 4),
            "bin_mid": round((lo + hi) / 2, 4),
            "residual_std": None if res_std is None else round(res_std, 4),
            "n": n_in,
        })
    return A, B, brier, ci_table


def main():
    os.makedirs(ASSETS_DIR, exist_ok=True)
    print(f"CareBridge AI - normalization skew fix ({VERSION})")
    print(f"TF {tf.__version__} | seeds pinned | UCI external for "
          f"preeclampsia only\n")

    uci = _load_uci_maternal()
    uci_norm = None
    if uci is not None:
        uci_X, uci_y = uci
        uci_norm = (_normalize_matrix(uci_X, PREECLAMPSIA_FEATURES), uci_y)
        print(f"UCI Maternal loaded: {len(uci_X)} rows (normalized through "
              f"SCHEMA_NORM for the external check)")
    else:
        sys.exit("UCI maternal csv missing - cannot re-issue preeclampsia "
                 "external validation honestly")

    for name, sim_fn, feats, desc, priors_used in SPECS:
        print(f"\n=== {name} ===")
        X_raw, y = sim_fn()
        X = _normalize_matrix(X_raw, feats)
        stratify_ok = bool((y.sum() > 1) and (y.sum() < len(y) - 1))
        Xr_tr, Xr_te, X_tr, X_te, y_tr, y_te = train_test_split(
            X_raw, X, y, test_size=0.2, random_state=42,
            stratify=y if stratify_ok else None)

        if name == "lbw_sga":
            clf = xgb.XGBClassifier(n_estimators=200, max_depth=6,
                                    learning_rate=0.1,
                                    objective="binary:logistic",
                                    eval_metric="auc", n_jobs=2,
                                    tree_method="hist")
        else:
            clf = RandomForestClassifier(n_estimators=200, max_depth=12,
                                         min_samples_leaf=20, n_jobs=2,
                                         random_state=42)
        clf.fit(X_tr, y_tr)
        y_prob = clf.predict_proba(X_te)[:, 1]
        auc = float(roc_auc_score(y_te, y_prob))
        J, thr, sens, spec = _youden(y_te, y_prob)
        A, B, brier, ci_table = _platt_with_ci(y_te, y_prob)

        drift_baseline = []
        for j, fname in enumerate(feats):
            col = X_tr[:, j]
            drift_baseline.append({
                "feature": fname,
                "mean": round(float(np.mean(col)), 4),
                "std": round(float(np.std(col)), 4),
                "p_lo": round(float(np.percentile(col, 0.5)), 4),
                "p_hi": round(float(np.percentile(col, 99.5)), 4),
            })

        ext_block = None
        if name == "preeclampsia_risk" and uci_norm is not None:
            eX, ey = uci_norm
            y_prob_ext = clf.predict_proba(eX)[:, 1]
            ext_auc = float(roc_auc_score(ey, y_prob_ext))
            ext_J, ext_thr, ext_sens, ext_spec = _youden(ey, y_prob_ext)
            eps = 1e-7
            p_ext_cal = 1.0 / (1.0 + np.exp(
                -(A * np.clip(y_prob_ext, eps, 1 - eps) + B)))
            ext_block = {
                "dataset": "UCI Machine Learning Repository: Maternal Health "
                           "Risk Data Set (Ahmed M., 2018; Bangladesh-origin). "
                           "Held out; scored through the same SCHEMA_NORM "
                           "normalization the app applies at inference.",
                "n": int(len(eX)),
                "holdout_auc": round(ext_auc, 4),
                "sensitivity": round(ext_sens, 4),
                "specificity": round(ext_spec, 4),
                "youden_j": round(ext_J, 4),
                "best_threshold": round(ext_thr, 4),
                "calibrated_brier": round(
                    float(brier_score_loss(ey, p_ext_cal)), 4),
            }

        tflite_bytes, q_scale, q_zp = _distill_tflite_int8(
            clf, X_tr, X_tr, name)
        sha = hashlib.sha256(tflite_bytes).hexdigest()

        metrics = {
            "model_name": name,
            "model_version": VERSION,
            "version_ladder": {
                "this": VERSION,
                "next": VERSION_NEXT,
                "v3_prospective": "v3.0-prospective-pilot",
            },
            "training_dataset": desc,
            "ghana_calibration": {
                "priors_used": priors_used,
                "external_validation": ext_block,
            },
            "clinical_note": (
                f"v1.1 normalization-skew fix. Same Ghana-priors simulator "
                f"cohort as v1.0 ({len(priors_used)} citation groups), but "
                f"the distilled MLP is trained and served on the [0,1] "
                f"SCHEMA_NORM representation - the exact tensor the app "
                f"feeds at inference. v1.0 distilled from RAW feature "
                f"scales, so its input quantization clamped every app "
                f"input to ~0 (train/serve skew); v1.1's flatbuffer input "
                f"quantization covers [0,1] (scale={q_scale:.6f}, "
                f"zero_point={q_zp}). Calibration via Platt scaling on the "
                f"internal 20% hold-out; 95% CI from per-bin Platt-residual "
                f"std; drift detection via per-feature z-score against the "
                f"normalized training distribution."
            ),
            "validation": {
                "internal": {
                    "holdout_auc": round(auc, 4),
                    "sensitivity": round(sens, 4),
                    "specificity": round(spec, 4),
                    "youden_j": round(J, 4),
                    "best_threshold": round(thr, 4),
                    "n_train": int(len(X_tr)),
                    "n_test": int(len(X_te)),
                    "calibration": {
                        "method": "platt_scaling",
                        "A": round(A, 6),
                        "B": round(B, 6),
                        "brier_score": round(brier, 4),
                        "ci_table": ci_table,
                    },
                },
            },
            "drift_baseline": {
                "z_threshold": 3.5,
                "min_z_threshold": 2.5,
                "features": drift_baseline,
            },
            "input_feature_order": feats,
            "input_quantization": {
                "scale": round(q_scale, 9), "zero_point": q_zp},
            "tflite_sha256": sha,
            "trained_on": TODAY,
            "provenance": {
                ref_tag: {
                    "short": s.short,
                    "citation": s.citation,
                    "doi_or_url": s.doi_or_url,
                    "n": s.n,
                    "setting": s.setting,
                } for ref_tag, s in ALL_SOURCES.items()
            },
        }
        if ext_block is not None:
            metrics["validation"]["external"] = ext_block

        out_tflite = os.path.join(ASSETS_DIR, f"{name}_int8_v1.tflite")
        out_metrics = os.path.join(ASSETS_DIR,
                                   f"{name}_int8_v1_metrics.json")
        with open(out_tflite, "wb") as f:
            f.write(tflite_bytes)
        with open(out_metrics, "w") as f:
            json.dump(metrics, f, indent=2)
        v = metrics["validation"]["internal"]
        print(f"  .tflite {len(tflite_bytes)}B  input_quant: scale="
              f"{q_scale:.6f} zp={q_zp}")
        print(f"  INT AUC={v['holdout_auc']} sens={v['sensitivity']} "
              f"spec={v['specificity']} brier={v['calibration']['brier_score']}")
        if ext_block:
            print(f"  EXT(UCI) n={ext_block['n']} AUC={ext_block['holdout_auc']}")
        print(f"  SHA-256 {sha}")

    print("\nDone: 3 models re-issued with normalized serving. "
          "neonatal_sepsis (v2.0-real-data) untouched.")


if __name__ == "__main__":
    main()
