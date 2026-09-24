"""Local-only, leakage-controlled research benchmark. Never overwrites model binaries.

Run: python tool/evaluate_research_models.py [--audit-only] [--write-contract]
All outcomes are dataset-defined; unresolved clinical definitions block packaging.
"""
from __future__ import annotations

import argparse
import ast
import csv
import hashlib
import importlib.metadata
import json
import os
import subprocess
from pathlib import Path

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")
os.environ.setdefault("TF_ENABLE_ONEDNN_OPTS", "0")
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import (average_precision_score, brier_score_loss,
                             confusion_matrix, log_loss, roc_auc_score, roc_curve)
from sklearn.model_selection import StratifiedGroupKFold
from sklearn.pipeline import make_pipeline

ROOT = Path(__file__).resolve().parents[1]
REAL = ROOT / "tool/datasets/real"
ASSETS = ROOT / "assets/models"
SEED = 20260915
INPUT_ARITHMETIC = "float32_divide_add_round_ties_away_from_zero"


def run_configuration(schemas):
    return {
        "seed": SEED,
        "trainer_sha256": digest(Path(__file__).read_bytes()),
        "schema_sha256": digest(json.dumps(schemas, sort_keys=True).encode()),
        "versions": {p: importlib.metadata.version(p) for p in ["numpy", "scikit-learn", "tensorflow"]},
        "grouped_partitions": [0.6, 0.2, 0.2],
        "selection": {"metric": "training_fold_average_precision", "tie_tolerance": 0.01,
                      "logistic_C": [0.1, 1, 10], "forest_trees": 300,
                      "forest_depth": [4, 8], "forest_min_leaf": [20, 10]},
        "distillation": {"layers": [32, 16, 1], "epochs": 100, "batch_size": 32,
                         "learning_rate": 0.003, "training_validation_fraction": 0.2,
                         "early_stopping_patience": 10, "representative_training_rows": 256},
        "imputation": "training_fold_median",
        "input_quantization_arithmetic": INPUT_ARITHMETIC,
        "calibration": "calibration_only_Platt_logit_C1",
        "threshold": "calibration_only_Youden_J_ties_favor_sensitivity",
        "bootstrap": {"unit": "predictor_or_patient_group", "repeats": 1000},
    }


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def write_json(path: Path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, allow_nan=False) + "\n", encoding="utf-8")


def legacy_schemas():
    # Parse constants without importing the legacy trainer's download/TF side effects.
    tree = ast.parse((ROOT / "tool/train_model_pack.py").read_text(encoding="utf-8"))
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(
                isinstance(t, ast.Name) and t.id == "SCHEMA_NORM" for t in node.targets):
            return ast.literal_eval(node.value)
    raise ValueError("Missing legacy schema")


def boolean(value):
    v = str(value).strip().lower()
    if v in {"yes", "true", "1"}:
        return 1.0
    if v in {"no", "false", "0"}:
        return 0.0
    return np.nan


def numeric(value):
    try:
        n = float(value)
        return n if np.isfinite(n) else np.nan
    except (ValueError, TypeError):
        return np.nan


DATASETS = {
    "neonatal_sepsis": {
        "files": ["mbarara_neonatal_sepsis_cases.csv", "mbarara_neonatal_sepsis_controls.csv"],
        "label": "neonatal_sepsis", "id": None,
        "mapping": {"age_days": "age_days", "temperature_celsius": "temperature",
                    "respiratory_rate_per_min": "respiratory_rate", "heart_rate_per_min": "heart_rate",
                    "feeding_difficulty": "poor_feeding", "lethargic_unconscious": "lethargy"},
        "excluded": {"weight": "Admission weight is not verified birth weight",
                     "blood_culture": "Potential outcome information, not an intake predictor"},
        "limitations": ["Clinical reference standard and measurement timing not documented locally",
                        "No patient identifiers; duplicate-predictor grouping is not proof of patient independence",
                        "Hospital admission cohort, not community screening"],
    },
    "preeclampsia_risk": {
        "files": ["preeclampsia_cfarkas.csv"], "label": "preeclampsia_onset", "id": "id",
        "mapping": {"maternal_age": "maternal_age", "gravida": "n_pregnancies",
                    "previous_losses": "n_abortions"},
        "excluded": {"bmi": "Measurement time relative to pregnancy/outcome is not established",
                     "parity": "Not an observed source column; do not derive from primigravidity",
                     "newborn_weight": "Post-delivery outcome information"},
        "limitations": ["Outcome coding/reference standard and pregnancy observation times lack a local data dictionary",
                        "No blood pressure predictors; cannot validate blood-pressure decision rules",
                        "No dataset-specific license statement located locally"],
    },
    "lbw_sga": {
        "files": ["lbw_classic.csv"], "label": "reslt", "id": None,
        "mapping": {"maternal_age": "age"},
        "excluded": {"Hb": "Measurement units/timing not established in local documentation",
                     "BP": "Ratio-like column is neither systolic nor diastolic pressure"},
        "limitations": ["Meaning and polarity of reslt are not documented locally",
                        "No gestational-age-specific outcome: LBW does not establish SGA",
                        "No patient identifiers or dataset-specific license statement located locally"],
    },
}


def audit_dataset(name, schemas):
    spec = DATASETS[name]
    rows, files = [], []
    provenance = json.loads((REAL / "DATASETS_SHA256.json").read_text(encoding="utf-8"))
    for filename in spec["files"]:
        path = REAL / filename
        with path.open(newline="", encoding="utf-8-sig") as f:
            rows.extend(csv.DictReader(f))
        files.append({"file": filename, "sha256": digest(path.read_bytes())})
    features = list(spec["mapping"])
    X = np.full((len(rows), len(features)), np.nan)
    for j, feature in enumerate(features):
        source = spec["mapping"][feature]
        lo, hi, kind = schemas[name][feature]
        values = np.array([(boolean(r.get(source)) if kind == "bool" else numeric(r.get(source))) for r in rows])
        values[(values < lo) | (values > hi)] = np.nan
        X[:, j] = values
    y = np.array([numeric(r.get(spec["label"])) for r in rows])
    if not set(y).issubset({0.0, 1.0}):
        raise ValueError(f"{name}: unknown/nonbinary labels; refusing to infer their meaning")
    y = y.astype(int)
    # Union groups by patient ID OR exact predictor record, including missingness.
    parents = list(range(len(rows)))
    def root(i):
        while parents[i] != i:
            parents[i] = parents[parents[i]]
            i = parents[i]
        return i
    seen = {}
    signatures = []
    for i, row in enumerate(rows):
        signature = digest(json.dumps([None if np.isnan(v) else float(v) for v in X[i]]).encode())
        signatures.append(signature)
        keys = ["x:" + signature]
        if spec["id"] and row.get(spec["id"]):
            keys.append("id:" + row[spec["id"]])
        for key in keys:
            if key in seen:
                parents[root(i)] = root(seen[key])
            else:
                seen[key] = i
    groups = np.array([root(i) for i in range(len(rows))])
    conflicts = sum(len(set(y[groups == g])) > 1 for g in set(groups))
    audit = {
        "model": name, "files": files, "n": len(y), "positive": int(y.sum()),
        "dataset_defined_label": spec["label"], "outcome_semantics_verified": False,
        "feature_mapping": spec["mapping"], "excluded": spec["excluded"],
        "local_provenance": {f: provenance.get(f, {}) for f in spec["files"]},
        "measurement_timing": "Not established locally; exploratory associations only",
        "license_status": "Local attribution is not an independently verified data-use license",
        "raw_missing": {f: sum(not str(r.get(source, "")).strip() for r in rows)
                        for f, source in spec["mapping"].items()},
        "missing_or_outside_transform_support": {f: int(np.isnan(X[:, j]).sum()) for j, f in enumerate(features)},
        "unique_groups": len(set(groups)), "duplicate_predictor_rows": len(y) - len(set(signatures)),
        "groups_with_conflicting_labels": conflicts,
        "limitations": spec["limitations"],
        "license_file": "mbarara_LICENSE.txt (Apache-2.0 text; dataset applicability not independently verified)" if name == "neonatal_sepsis" else None,
        "packaging_allowed": False,
        "packaging_blocker": "Clinical outcome definition/measurement timing requires source documentation",
    }
    return X, y, groups, features, audit


def normalize(X, features, schema):
    out = np.array(X, dtype=np.float64, copy=True)
    for j, feature in enumerate(features):
        lo, hi, _ = schema[feature]
        values = out[:, j]
        if not np.isfinite([lo, hi]).all() or hi <= lo or np.isinf(values).any() or ((values < lo) | (values > hi)).any():
            raise ValueError("Value outside normalization contract")
        out[:, j] = (values - lo) / (hi - lo)
    return out.astype(np.float32)


def split_groups(X, y, groups):
    folds = list(StratifiedGroupKFold(5, shuffle=True, random_state=SEED).split(X, y, groups))
    evaluation, calibration = folds[0][1], folds[1][1]
    training = np.setdiff1d(np.arange(len(y)), np.r_[evaluation, calibration])
    parts = {"training": training, "calibration": calibration, "evaluation": evaluation}
    for name, indices in parts.items():
        if len(set(y[indices])) != 2:
            raise ValueError(f"{name}: insufficient class/group coverage")
    for a, b in [("training", "calibration"), ("training", "evaluation"), ("calibration", "evaluation")]:
        assert not set(groups[parts[a]]) & set(groups[parts[b]])
    return parts


def candidates():
    for c in (0.1, 1.0, 10.0):
        yield f"logistic_C{c:g}", LogisticRegression(C=c, max_iter=1000, random_state=SEED)
    for depth in (4, 8):
        for leaf in (20, 10):
            yield f"forest_d{depth}_leaf{leaf}", RandomForestClassifier(
                n_estimators=300, max_depth=depth, min_samples_leaf=leaf,
                random_state=SEED, n_jobs=2)


def select_candidate(X, y, groups):
    n_splits = min(5, *(len(set(groups[y == c])) for c in (0, 1)))
    if n_splits < 2:
        raise ValueError("Insufficient minority-class groups for selection")
    folds = list(StratifiedGroupKFold(n_splits, shuffle=True, random_state=SEED).split(X, y, groups))
    ranked = []
    for order, (name, estimator) in enumerate(candidates()):
        scores = []
        for tr, va in folds:
            if len(set(y[tr])) != 2 or len(set(y[va])) != 2:
                raise ValueError("Inner fold lacks class coverage")
            pipe = make_pipeline(SimpleImputer(strategy="median", keep_empty_features=True), estimator)
            pipe.fit(X[tr], y[tr])
            scores.append(float(average_precision_score(y[va], pipe.predict_proba(X[va])[:, 1])))
        ranked.append({"name": name, "mean_average_precision": float(np.mean(scores)), "folds": scores, "order": order})
    best = max(r["mean_average_precision"] for r in ranked)
    winner = min((r for r in ranked if r["mean_average_precision"] >= best - 0.01), key=lambda r: r["order"])
    estimator = dict(candidates())[winner["name"]]
    pipe = make_pipeline(SimpleImputer(strategy="median", keep_empty_features=True), estimator)
    pipe.fit(X, y)
    return pipe, winner["name"], ranked


def export_int8(pipe, X, output):
    import tensorflow as tf
    tf.keras.utils.set_random_seed(SEED)
    tf.config.experimental.enable_op_determinism()
    clean = pipe[0].transform(X).astype(np.float32)
    estimator = pipe[-1]
    if isinstance(estimator, LogisticRegression):
        network = tf.keras.Sequential([tf.keras.Input(shape=(clean.shape[1],)), tf.keras.layers.Dense(1, activation="sigmoid")])
        network.layers[0].set_weights([estimator.coef_.T.astype(np.float32), estimator.intercept_.astype(np.float32)])
    else:
        network = tf.keras.Sequential([tf.keras.Input(shape=(clean.shape[1],)),
                                      tf.keras.layers.Dense(32, activation="relu"),
                                      tf.keras.layers.Dense(16, activation="relu"),
                                      tf.keras.layers.Dense(1, activation="sigmoid")])
        network.compile(optimizer=tf.keras.optimizers.Adam(0.003), loss="binary_crossentropy")
        soft = estimator.predict_proba(clean)[:, 1].astype(np.float32)
        # Training-only distillation validation; no calibration/evaluation inputs.
        network.fit(clean, soft, epochs=100, batch_size=32, validation_split=0.2, verbose=0,
                    callbacks=[tf.keras.callbacks.EarlyStopping(patience=10, restore_best_weights=True)])
    converter = tf.lite.TFLiteConverter.from_keras_model(network)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.representative_dataset = lambda: ([row.reshape(1, -1)] for row in clean[:256])
    converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
    converter.inference_input_type = tf.int8
    converter.inference_output_type = tf.int8
    model = converter.convert()
    output.write_bytes(model)
    interpreter = tf.lite.Interpreter(model_content=model, num_threads=1)
    interpreter.allocate_tensors()
    return interpreter


def infer(interpreter, X):
    i, o = interpreter.get_input_details()[0], interpreter.get_output_details()[0]
    scale, zp = i["quantization"]
    oscale, ozp = o["quantization"]
    if scale <= 0 or oscale <= 0 or i["dtype"] != np.int8 or o["dtype"] != np.int8:
        raise ValueError("Unexpected INT8 signature")
    out = []
    for row in X:
        # Ties away from zero agrees with Dart round().
        v = row / scale + zp
        q = (np.sign(v) * np.floor(np.abs(v) + 0.5)).clip(-128, 127).astype(np.int8)
        interpreter.set_tensor(i["index"], q.reshape(1, -1))
        interpreter.invoke()
        p = float((interpreter.get_tensor(o["index"]).ravel()[0].astype(float) - ozp) * oscale)
        if not np.isfinite(p) or not 0 <= p <= 1:
            raise ValueError("Invalid exported-model output")
        out.append(p)
    return np.array(out)


def apply_calibration(p, a, b):
    p = np.clip(p, 1e-7, 1 - 1e-7)
    z = a * np.log(p / (1 - p)) + b
    return 1 / (1 + np.exp(-np.clip(z, -700, 700)))


def calibrate(y, p):
    p = np.clip(p, 1e-7, 1 - 1e-7)
    lr = LogisticRegression(C=1.0, max_iter=1000).fit(np.log(p / (1 - p)).reshape(-1, 1), y)
    return float(lr.coef_[0, 0]), float(lr.intercept_[0])


def select_threshold(y, p):
    fpr, tpr, thresholds = roc_curve(y, p, drop_intermediate=False)
    valid = np.isfinite(thresholds)
    choices = np.flatnonzero(valid)
    return float(thresholds[max(choices, key=lambda i: (round(tpr[i] - fpr[i], 12), tpr[i]))])


def metrics(y, p, threshold):
    tn, fp, fn, tp = confusion_matrix(y, p >= threshold, labels=[0, 1]).ravel()
    ratio = lambda a, b: float(a / b) if b else None
    bins = []
    for j in range(10):
        mask = (p >= j / 10) & (p < (j + 1) / 10 if j < 9 else p <= 1)
        bins.append({"lower": j / 10, "upper": (j + 1) / 10, "n": int(mask.sum()),
                     "mean_output": float(p[mask].mean()) if mask.any() else None,
                     "observed_fraction": float(y[mask].mean()) if mask.any() else None})
    return {"n": len(y), "prevalence": float(y.mean()), "auroc": float(roc_auc_score(y, p)),
            "average_precision": float(average_precision_score(y, p)), "brier": float(brier_score_loss(y, p)),
            "log_loss": float(log_loss(y, p, labels=[0, 1])), "threshold": threshold,
            "sensitivity": ratio(tp, tp + fn), "specificity": ratio(tn, tn + fp),
            "ppv": ratio(tp, tp + fp), "npv": ratio(tn, tn + fn),
            "confusion": dict(zip(["tn", "fp", "fn", "tp"], map(int, [tn, fp, fn, tp]))), "reliability_bins": bins}


def bootstrap(y, p, groups, threshold, repeats=1000):
    if len(np.unique(groups)) < 2:
        return {}  # One evaluation cluster cannot estimate sampling uncertainty.
    rng = np.random.default_rng(SEED)
    unique = np.unique(groups)
    by_group = {g: np.flatnonzero(groups == g) for g in unique}
    samples = {k: [] for k in ["auroc", "average_precision", "brier", "log_loss", "sensitivity", "specificity", "ppv", "npv"]}
    for _ in range(repeats):
        idx = np.concatenate([by_group[g] for g in rng.choice(unique, len(unique), replace=True)])
        if len(set(y[idx])) < 2:
            continue
        result = metrics(y[idx], p[idx], threshold)
        for key in samples:
            if result[key] is not None:
                samples[key].append(result[key])
    return {key: {"low": float(np.quantile(v, 0.025)), "high": float(np.quantile(v, 0.975)), "replicates": len(v)}
            for key, v in samples.items() if v}


def packaging_gate(audit, result, intervals, baseline_brier, parity_passed=False):
    return bool(audit["packaging_allowed"] and parity_passed
                and intervals.get("auroc", {}).get("low", 0) > 0.5
                and result["average_precision"] > result["prevalence"]
                and result["brier"] < baseline_brier)


def build_contract(schemas):
    import tensorflow as tf
    models = {}
    for name, schema in schemas.items():
        metrics_path = ASSETS / f"{name}_int8_v1_metrics.json"
        old = json.loads(metrics_path.read_text(encoding="utf-8"))
        real = name == "neonatal_sepsis"
        learned = {"age_days", "temperature_celsius", "respiratory_rate_per_min", "heart_rate_per_min"} if real else set()
        interpreter = tf.lite.Interpreter(model_path=str(ASSETS / f"{name}_int8_v1.tflite"))
        interpreter.allocate_tensors()
        inp, op = interpreter.get_input_details()[0], interpreter.get_output_details()[0]
        models[name] = {
            "model_type": "dense_network", "output_type": "binary_probability",
            "input_dtype": np.dtype(inp["dtype"]).name, "input_shape": inp["shape"].tolist(),
            "output_dtype": np.dtype(op["dtype"]).name, "output_shape": op["shape"].tolist(),
            "input_quantization": list(inp["quantization"]), "output_quantization": list(op["quantization"]),
            "input_quantization_arithmetic": INPUT_ARITHMETIC,
            "schema_version": 1, "model_name": name, "model_version": old["model_version"],
            "artifact_sha256": digest((ASSETS / f"{name}_int8_v1.tflite").read_bytes()),
            "evidence": "legacy_real_data" if real else "synthetic",
            "patient_output_allowed": False, "clinical_use_allowed": False,
            "cohort": "young_infant" if real else "child" if name == "child_pneumonia" else "maternal",
            "age_days_support": [0, 3] if real else None,
            "dataset": old.get("training_dataset"),
            "outcome": "Dataset-defined neonatal_sepsis; reference standard unverified" if real else "Simulated outcome",
            "limitations": (["Legacy feeding/lethargy encoding discarded Yes/No observations",
                              "Weight meaning differs from the app's birth-weight field",
                              "Published metrics describe the teacher, not an independently evaluated exported model"] if real else
                             ["Synthetic training does not establish patient-level predictive performance"])
                            + ["Not clinically validated for Northern Ghana", "No individual probability confidence interval"],
            "evaluation_kind": "legacy_teacher_only", "evaluation": {},
            "features": [{"name": f, "meaning": f.replace("_", " "), "kind": kind,
                          "unit": "boolean" if kind == "bool" else "days" if f == "age_days" else
                                  "C" if "temperature" in f else "per_min" if "per_min" in f else
                                  "mmHg" if f.endswith("_bp") else "source_schema_unit",
                          "min": lo, "max": hi, "transform": "min_max", "imputation": None,
                          "required": f in learned, "supported": f in learned}
                         for f, (lo, hi, kind) in schema.items()],
        }
    c = models['neonatal_sepsis']
    policy = 'neonatal-five-observed-v1'
    means = {'age_days': .0296, 'temperature_celsius': .6548,
             'respiratory_rate_per_min': .4019, 'heart_rate_per_min': .5754,
             'birth_weight_kg': .5274}
    c.update(patient_output_allowed=True, output_scope='clinician_experimental',
             input_policy_version=policy,
             calibration={'A': 2.013769, 'B': -5.826344,
                          'formula': 'sigmoid(A * logit(p) + B)',
                          'provenance': 'Unvalidated legacy Random Forest teacher OOF transform; includes assumed prior shift',
                          'validated_for_artifact': False},
             sensitivity_baseline={'artifact_sha256': c['artifact_sha256'],
                                   'input_policy_version': policy,
                                   'provenance': 'Normalized training means from legacy artifact metrics',
                                   'means': means})
    c['limitations'].append('Current measured weight is an experimental proxy for source admission weight; measurement timing unverified')
    for f in c['features']:
        key = f['name']
        observed = key in means
        f.update(input_policy='observed' if observed else 'constant_normalized',
                 required=observed, supported=observed)
        if observed:
            f['input_source'] = 'current_weight_kg' if key == 'birth_weight_kg' else key
        else:
            f.update(constant_normalized=0.0,
                     fixed_reason='legacy_encoding_defect' if key in ('feeding_difficulty', 'lethargic_unconscious')
                     else 'unavailable_training_feature')
        if key == 'birth_weight_kg':
            f.update(unit='kg', meaning='Current measured weight: experimental proxy for source admission weight; measurement timing unverified')
    return {"schema_version": 1, "models": models}


def evaluate(name, schemas, out):
    configuration = run_configuration(schemas)
    write_json(out / f"{name}_configuration.json", configuration)
    X, y, groups, features, audit = audit_dataset(name, schemas)
    X = normalize(X, features, schemas[name])
    parts = split_groups(X, y, groups)
    manifest = {k: list(map(int, v)) for k, v in parts.items()}
    manifest["groups"] = list(map(int, groups))
    manifest["dataset_hashes"] = audit["files"]
    write_json(out / f"{name}_split.json", manifest)
    tr, ca, te = (parts[k] for k in ["training", "calibration", "evaluation"])
    baseline_cv = []
    # Explicit prevalence-only comparison, fit inside each training fold.
    n_folds = min(5, *(len(set(groups[tr][y[tr] == c])) for c in (0, 1)))
    if n_folds < 2:
        raise ValueError("Insufficient groups for baseline comparison")
    for bt, bv in StratifiedGroupKFold(n_folds, shuffle=True, random_state=SEED).split(X[tr], y[tr], groups[tr]):
        baseline_cv.append(float(average_precision_score(y[tr][bv], np.full(len(bv), y[tr][bt].mean()))))
    pipe, selected, cv = select_candidate(X[tr], y[tr], groups[tr])
    interpreter = export_int8(pipe, X[tr], out / f"{name}.tflite")
    clean = pipe[0].transform(X).astype(np.float32)
    raw_cal, raw_eval = infer(interpreter, clean[ca]), infer(interpreter, clean[te])
    a, b = calibrate(y[ca], raw_cal)
    threshold = select_threshold(y[ca], apply_calibration(raw_cal, a, b))
    p = apply_calibration(raw_eval, a, b)
    result = metrics(y[te], p, threshold)
    intervals = bootstrap(y[te], p, groups[te], threshold)
    baseline_brier = float(brier_score_loss(y[te], np.full(len(te), y[tr].mean())))
    teacher = pipe.predict_proba(X[te])[:, 1]
    inp, op = interpreter.get_input_details()[0], interpreter.get_output_details()[0]
    # No source rows are emitted into public Flutter assets. These fixtures stay local.
    probes = np.vstack([clean[te[:24]], np.zeros(len(features)), np.ones(len(features)),
                        np.full(len(features), 0.5)]).astype(np.float32)
    write_json(out / f"{name}_parity.json", {
        "model_path": str((out / f"{name}.tflite").relative_to(ROOT)),
        "input_quantization": list(inp["quantization"]), "output_quantization": list(op["quantization"]),
        "cases": [{"input": row.tolist(), "expected": float(p)} for row, p in zip(probes, infer(interpreter, probes))]})
    report = {"configuration_sha256": digest(json.dumps(configuration, sort_keys=True).encode()),
              "audit": audit, "selected": selected, "training_cv": cv, "evaluation": result,
              "prevalence_baseline_cv_ap": baseline_cv,
              "baseline_evaluation": metrics(y[te], np.full(len(te), y[tr].mean()), threshold),
              "aggregate_bootstrap_95": intervals, "baseline_brier": baseline_brier,
              "training_prevalence": float(y[tr].mean()), "split_sha256": digest(json.dumps(manifest, sort_keys=True).encode()),
              "features": features, "training_imputation_normalized": pipe[0].statistics_.tolist(),
              "calibration": {"A": a, "B": b, "formula": "sigmoid(A * logit(p) + B)"},
              "teacher_diagnostic_auroc": float(roc_auc_score(y[te], teacher)),
              "teacher_student_mean_absolute_difference": float(np.mean(np.abs(teacher - raw_eval))),
              "candidate_sha256": digest((out / f"{name}.tflite").read_bytes()),
              "packaged": packaging_gate(audit, result, intervals, baseline_brier),
              "parity": "pending Dart verification", "evaluation_scope": "Exploratory reuse of historically examined repository data",
              "clinical_use_allowed": False}
    write_json(out / f"{name}_evaluation.json", report)
    print(f"{name}: {selected}, exported AUROC={result['auroc']:.4f}, AP={result['average_precision']:.4f}, Brier={result['brier']:.4f}; packaged=False", flush=True)
    return report


def verify_completed_run(name, schemas, out):
    """Verify frozen results and add diagnostics without fitting or retuning anything."""
    report = json.loads((out / f"{name}_evaluation.json").read_text(encoding="utf-8"))
    if "error" in report:
        return report
    manifest = json.loads((out / f"{name}_split.json").read_text(encoding="utf-8"))
    _, y, groups, features, audit = audit_dataset(name, schemas)
    if report["candidate_sha256"] != digest((out / f"{name}.tflite").read_bytes()):
        raise ValueError("Completed candidate hash mismatch; refusing reuse or retraining")
    if manifest["dataset_hashes"] != audit["files"] or report["features"] != features:
        raise ValueError("Completed dataset/feature mismatch; refusing reuse or retraining")
    if report["split_sha256"] != digest(json.dumps(manifest, sort_keys=True).encode()):
        raise ValueError("Completed split hash mismatch; refusing reuse or retraining")
    if manifest["groups"] != groups.tolist():
        raise ValueError("Completed grouping mismatch; refusing reuse or retraining")
    parts = {k: np.array(manifest[k], dtype=int) for k in ["training", "calibration", "evaluation"]}
    indices = np.concatenate(list(parts.values()))
    if sorted(indices.tolist()) != list(range(len(y))):
        raise ValueError("Frozen partitions overlap or omit rows")
    for a, b in [("training", "calibration"), ("training", "evaluation"), ("calibration", "evaluation")]:
        if set(groups[parts[a]]) & set(groups[parts[b]]):
            raise ValueError("Frozen partitions overlap groups")
    if any(set(y[idx]) != {0, 1} for idx in parts.values()):
        raise ValueError("Frozen partitions lack class coverage")
    te, tr = parts["evaluation"], parts["training"]
    if report.get("configuration_sha256"):
        configuration = json.loads((out / f"{name}_configuration.json").read_text(encoding="utf-8"))
        if digest(json.dumps(configuration, sort_keys=True).encode()) != report["configuration_sha256"]:
            raise ValueError("Frozen configuration hash mismatch")
    n_groups = len(np.unique(groups[te]))
    addendum = {
        "candidate_sha256": report["candidate_sha256"],
        "evaluation_groups": n_groups,
        "baseline_evaluation": metrics(y[te], np.full(len(te), y[tr].mean()), report["evaluation"]["threshold"]),
        "no_refitting_or_threshold_changes": True,
        "configuration_limit": None if report.get("configuration_sha256") else "Historical run records seed, dependencies and candidate grid, but lacks a contemporaneous trainer-code hash",
        "bootstrap_correction": "Singleton evaluation group: original degenerate intervals are invalid and withdrawn" if n_groups < 2 else None,
        "clinical_use_allowed": False,
    }
    reproduced_path = out / f"{name}_metric_verification.json"
    if reproduced_path.exists():
        reproduced = json.loads(reproduced_path.read_text(encoding="utf-8"))
        if (reproduced.get("candidate_sha256") == report["candidate_sha256"] and
                reproduced.get("evaluation_report_sha256") == digest((out / f"{name}_evaluation.json").read_bytes())):
            addendum["exported_metrics_reproduced"] = reproduced.get("passed") is True
    parity_path = out / "parity_verification.json"
    if parity_path.exists():
        parity = json.loads(parity_path.read_text(encoding="utf-8"))
        if parity.get("hashes") == parity_hashes(out) and parity.get("passed") is True:
            addendum["dart_parity"] = "Passed exact INT8 input and official output tolerance checks"
    write_json(out / f"{name}_verification.json", addendum)
    result = dict(report, verification_addendum=addendum)
    result["baseline_evaluation"] = addendum["baseline_evaluation"]
    if "dart_parity" in addendum:
        result["parity"] = addendum["dart_parity"]
    if n_groups < 2:
        result["aggregate_bootstrap_95"] = {}
    return result


def experimental_neonatal_fixture():
    """Official TFLite execution vectors; no fitting or clinical validation."""
    import tensorflow as tf
    path = ASSETS / 'neonatal_sepsis_int8_v1.tflite'
    artifact = digest(path.read_bytes())
    if artifact != 'b40ce5c43958b16bf6508887f49d79e7de7c0e6b8c4fd68ffabefb8a8d2b0fff':
        raise ValueError('Experimental fixture requires the unchanged shipped artifact')
    interpreter = tf.lite.Interpreter(model_path=str(path), num_threads=1)
    interpreter.allocate_tensors()
    inp, out = interpreter.get_input_details()[0], interpreter.get_output_details()[0]
    slots = [0, 1, 2, 3, 5]
    raw = [[2, 37, 48, 140, 3], [0, 34, 20, 60, .8], [3, 41, 120, 220, 5]]
    rows = []
    for values in raw:
        row = np.zeros(20, dtype=np.float32)
        for slot, value, lo, hi in zip(slots, values, [0, 34, 20, 60, .8], [59, 41, 120, 220, 5]):
            row[slot] = (value - lo) / (hi - lo)
        rows.append(row)
    for slot, mean in zip(slots, [.0296, .6548, .4019, .5754, .5274]):
        row = rows[0].copy()
        row[slot] = mean
        rows.append(row)
    cases = []
    for index, row in enumerate(rows):
        v = np.float32(row / np.float32(inp['quantization'][0])) + np.float32(inp['quantization'][1])
        q = (np.sign(v) * np.floor(np.abs(v) + np.float32(.5))).clip(-128, 127).astype(np.int8)
        interpreter.set_tensor(inp['index'], q.reshape(1, -1))
        interpreter.invoke()
        output = float(interpreter.get_tensor(out['index']).ravel()[0])
        adjusted = float(apply_calibration(np.array([output]), 2.013769, -5.826344)[0])
        cases.append({'name': ['measured', 'lower_bounds', 'upper_bounds'][index] if index < 3 else f'replace_slot_{slots[index-3]}',
                      'raw': raw[index] if index < 3 else raw[0],
                      'normalized': row.tolist(), 'quantized': q.tolist(),
                      'raw_output': output, 'adjusted_output': adjusted})
    return {'artifact_sha256': artifact, 'input_policy_version': 'neonatal-five-observed-v1',
            'model_path': path.relative_to(ROOT).as_posix(), 'tolerance': 1e-5,
            'scope': 'Execution parity only; not predictive accuracy or clinical validation', 'cases': cases}


def verification_fixtures(schemas, out):
    """Boundary and missing-input fixtures from frozen artifacts, not new training."""
    import tensorflow as tf
    fixtures = []
    write_json(out / 'neonatal_experimental_parity.json', experimental_neonatal_fixture())
    for name in DATASETS:
        report = verify_completed_run(name, schemas, out)
        features = report["features"]
        schema = schemas[name]
        columns = [{"name": f, "min": schema[f][0], "max": schema[f][1],
                    "kind": schema[f][2], "transform": "min_max",
                    "imputation_normalized": report["training_imputation_normalized"][j]}
                   for j, f in enumerate(features)]
        path = out / f"{name}.tflite"
        interpreter = tf.lite.Interpreter(model_path=str(path), num_threads=1)
        interpreter.allocate_tensors()
        i, o = interpreter.get_input_details()[0], interpreter.get_output_details()[0]
        X, y, _, _, _ = audit_dataset(name, schemas)
        normal_data = normalize(X, features, schema)
        split = json.loads((out / f"{name}_split.json").read_text(encoding="utf-8"))
        imputation = np.array(report["training_imputation_normalized"], dtype=np.float32)
        np.testing.assert_allclose(imputation, np.nanmedian(normal_data[split["training"]], axis=0), atol=1e-7)
        te = split["evaluation"]
        clean = np.where(np.isnan(normal_data[te]), imputation, normal_data[te])
        p = apply_calibration(infer(interpreter, clean), report["calibration"]["A"], report["calibration"]["B"])
        measured = metrics(y[te], p, report["evaluation"]["threshold"])
        for key in ["auroc", "average_precision", "brier", "log_loss", "sensitivity", "specificity", "ppv", "npv"]:
            if measured[key] is None or report["evaluation"][key] is None:
                assert measured[key] == report["evaluation"][key], key
            else:
                np.testing.assert_allclose(measured[key], report["evaluation"][key], atol=1e-10, rtol=1e-10)
        assert measured["confusion"] == report["evaluation"]["confusion"]
        assert [b["n"] for b in measured["reliability_bins"]] == [b["n"] for b in report["evaluation"]["reliability_bins"]]
        write_json(out / f"{name}_metric_verification.json", {
            "passed": True, "candidate_sha256": report["candidate_sha256"],
            "evaluation_report_sha256": digest((out / f"{name}_evaluation.json").read_bytes()),
            "scope": "Frozen exported INT8 evaluation, recorded imputation/calibration/threshold; no fitting",
            "clinical_use_allowed": False,
        })
        raw = np.array([[s["min"] for s in columns], [s["max"] for s in columns],
                        [(s["min"] + s["max"]) / 2 for s in columns],
                        [np.nan] * len(columns)])
        normal = normalize(raw, features, schema)
        normal = np.where(np.isnan(normal), np.array(report["training_imputation_normalized"], dtype=np.float32), normal)
        cases = []
        for values, tensor, output in zip(raw, normal, infer(interpreter, normal)):
            v = tensor / i["quantization"][0] + i["quantization"][1]
            quantized = (np.sign(v) * np.floor(np.abs(v) + 0.5)).clip(-128, 127).astype(int)
            cases.append({"raw": [None if np.isnan(v) else float(v) for v in values],
                          "normalized": tensor.tolist(), "quantized": quantized.tolist(), "expected": float(output)})
        fixtures.append({"name": name, "model_path": str(path.relative_to(ROOT)),
                         "features": columns, "cases": cases, "tolerance": float(o["quantization"][0])})
    for name, schema in schemas.items():
        path = ASSETS / f"{name}_int8_v1.tflite"
        interpreter = tf.lite.Interpreter(model_path=str(path), num_threads=1)
        interpreter.allocate_tensors()
        i, o = interpreter.get_input_details()[0], interpreter.get_output_details()[0]
        cases = []
        for row in [np.zeros(len(schema)), np.ones(len(schema)), np.full(len(schema), 0.5)]:
            v = row / i["quantization"][0] + i["quantization"][1]
            q = (np.sign(v) * np.floor(np.abs(v) + 0.5)).clip(-128, 127).astype(np.int8)
            interpreter.set_tensor(i["index"], q.reshape(1, -1))
            interpreter.invoke()
            cases.append({"normalized": row.tolist(), "quantized": q.tolist(),
                          "expected": float(interpreter.get_tensor(o["index"]).ravel()[0])})
        fixtures.append({"name": "legacy_" + name, "model_path": str(path.relative_to(ROOT)),
                         "features": [], "cases": cases, "tolerance": 1e-5})
    write_json(out / "runtime_fixtures.json", {"cases": fixtures,
               "input_quantization_arithmetic": INPUT_ARITHMETIC,
               "missing_input_scope": "Technical imputation parity only; missing required observations block patient output"})


def parity_hashes(out):
    paths = [ROOT / "test/research_parity_test.dart",
             ROOT / "lib/core/ml/tflite_dart_interpreter.dart",
             ROOT / "lib/core/ml/research_runtime.dart", out / "runtime_fixtures.json"]
    paths += [out / f"{n}{suffix}" for n in DATASETS for suffix in [".tflite", "_parity.json"]]
    paths += [ASSETS / f"{n}_int8_v1.tflite" for n in legacy_schemas()]
    return {str(p.relative_to(ROOT)): digest(p.read_bytes()) for p in paths}


def verify_dart(out, flutter):
    command = [flutter, "test", "test/research_parity_test.dart",
               f"--dart-define=RESEARCH_RUN={out.relative_to(ROOT).as_posix()}",
               "--reporter", "expanded"]
    completed = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
    write_json(out / "parity_verification.json", {
        "command": command, "passed": completed.returncode == 0,
        "hashes": parity_hashes(out), "stdout": completed.stdout, "stderr": completed.stderr,
        "scope": "Official Python TFLite versus pure-Dart; native Flutter runner not covered",
        "clinical_use_allowed": False,
    })
    print(completed.stdout)
    if completed.returncode:
        raise RuntimeError("Dart parity failed; no packaging allowed")


def verification_summary(schemas, out):
    results = {name: verify_completed_run(name, schemas, out) for name in DATASETS}
    path = out / "summary.json"
    summary = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {"seed": SEED}
    summary.update(results=results, clinical_use_allowed=False)
    write_json(path, summary)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--audit-only", action="store_true")
    parser.add_argument("--write-contract", action="store_true")
    parser.add_argument("--verify-existing", action="store_true", help="Verify frozen artifacts and emit runtime fixtures without training")
    parser.add_argument("--verify-dart", action="store_true", help="Run and record Dart parity; never train")
    parser.add_argument("--flutter", default="flutter", help="Flutter executable for parity checks")
    parser.add_argument("--output", type=Path, default=ROOT / "tool/research_runs/evidence_v1")
    args = parser.parse_args()
    out = args.output.resolve()
    if ROOT not in out.parents or ASSETS == out or ASSETS in out.parents:
        parser.error("Research outputs must stay in the workspace, outside shipped assets")
    schemas = legacy_schemas()
    audits = {name: audit_dataset(name, schemas)[4] for name in DATASETS}
    write_json(out / "dataset_audit.json", {"datasets": audits,
               "pneumonia": "No compatible real dataset in the current repository",
               "excluded_validation": ["Adult ICU sepsis", "UCI general maternal risk", "Fetal CTG"]})
    if args.write_contract:
        write_json(ASSETS / "research_contracts.json", build_contract(schemas))
    if args.verify_existing or args.verify_dart:
        verification_fixtures(schemas, out)
        if args.verify_dart:
            verify_dart(out, args.flutter)
        verification_summary(schemas, out)
        print("Frozen artifacts verified; no refitting or promotion")
        return
    if args.audit_only:
        print(json.dumps({n: {k: a[k] for k in ["n", "positive", "unique_groups", "duplicate_predictor_rows", "groups_with_conflicting_labels"]} for n, a in audits.items()}, indent=2))
        return
    results = {}
    for name in DATASETS:
        marker = out / f"{name}_evaluation.json"
        if marker.exists():
            results[name] = verify_completed_run(name, schemas, out)
            print(f"{name}: retained completed run; no retuning", flush=True)
            continue
        try:
            results[name] = evaluate(name, schemas, out)
        except Exception as e:
            results[name] = {"error": str(e), "packaged": False}
            write_json(marker, results[name])
            print(f"{name}: blocked: {e}", flush=True)
    write_json(out / "summary.json", {"seed": SEED,
               "versions": {p: importlib.metadata.version(p) for p in ["numpy", "scikit-learn", "tensorflow"]},
               "results": results, "clinical_use_allowed": False})


if __name__ == "__main__":
    main()
