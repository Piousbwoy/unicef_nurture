"""Verify the offline release payload; does not certify browser caching or clinical use."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODELS = {"neonatal_sepsis", "child_pneumonia", "preeclampsia_risk", "lbw_sga"}


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify_output_policy(name, contract):
    if contract.get('clinical_use_allowed') is not False:
        raise ValueError(f'Clinical authorization is forbidden: {name}')
    if name != 'neonatal_sepsis':
        if contract.get('patient_output_allowed') is not False:
            raise ValueError(f'Unapproved patient output in release: {name}')
        return
    artifact = 'b40ce5c43958b16bf6508887f49d79e7de7c0e6b8c4fd68ffabefb8a8d2b0fff'
    policy = 'neonatal-five-observed-v1'
    expected = {
        'model_name': name, 'model_version': 'v2.0-real-data-neonatal_sepsis',
        'artifact_sha256': artifact, 'input_policy_version': policy,
        'evidence': 'legacy_real_data', 'output_scope': 'clinician_experimental',
        'cohort': 'young_infant', 'age_days_support': [0, 3],
        'model_type': 'dense_network', 'output_type': 'binary_probability',
        'input_dtype': 'int8', 'input_shape': [1, 20],
        'output_dtype': 'float32', 'output_shape': [1, 1],
        'input_quantization': [0.003921568859368563, -128],
        'output_quantization': [0., 0],
        'input_quantization_arithmetic': 'float32_divide_add_round_ties_away_from_zero',
    }
    if (contract.get('patient_output_allowed') is not True or
            any(contract.get(k) != v for k, v in expected.items())):
        raise ValueError('Invalid neonatal experimental identity or tensor contract')
    order = ['age_days', 'temperature_celsius', 'respiratory_rate_per_min',
             'heart_rate_per_min', 'oxygen_saturation_per_cent', 'birth_weight_kg',
             'apgar_5_minute', 'history_of_convulsions', 'severe_chest_indrawing',
             'nasal_flaring_grunting', 'bulging_fontanelle', 'jaundice_before_24h',
             'feeding_difficulty', 'abdominal_distension', 'cord_infection',
             'skin_pustules', 'lethargic_unconscious', 'bleeding', 'hiv_exposed', 'multiple_birth']
    observed = {
        'age_days': (0, 59, .0296), 'temperature_celsius': (34, 41, .6548),
        'respiratory_rate_per_min': (20, 120, .4019),
        'heart_rate_per_min': (60, 220, .5754), 'birth_weight_kg': (.8, 5, .5274),
    }
    features = contract.get('features', [])
    if not isinstance(features, list) or [f.get('name') for f in features] != order:
        raise ValueError('Invalid neonatal tensor order')
    for feature in features:
        key = feature['name']
        if key in observed:
            lo, hi, _ = observed[key]
            valid = (feature.get('input_policy') == 'observed' and
                     feature.get('required') is True and feature.get('supported') is True and
                     feature.get('min') == lo and feature.get('max') == hi and
                     feature.get('transform') == 'min_max' and
                     feature.get('input_source') == ('current_weight_kg' if key == 'birth_weight_kg' else key))
        else:
            reason = ('legacy_encoding_defect' if key in ['feeding_difficulty', 'lethargic_unconscious']
                      else 'unavailable_training_feature')
            valid = (feature.get('input_policy') == 'constant_normalized' and
                     feature.get('constant_normalized') == 0 and
                     feature.get('required') is False and feature.get('supported') is False and
                     feature.get('fixed_reason') == reason)
        if not valid or feature.get('imputation') is not None:
            raise ValueError(f'Invalid neonatal feature policy: {key}')
    baseline = contract.get('sensitivity_baseline', {})
    calibration = contract.get('calibration', {})
    if (baseline.get('artifact_sha256') != artifact or
            baseline.get('input_policy_version') != policy or
            baseline.get('means') != {k: v[2] for k, v in observed.items()} or
            calibration.get('A') != 2.013769 or calibration.get('B') != -5.826344 or
            calibration.get('formula') != 'sigmoid(A * logit(p) + B)' or
            calibration.get('validated_for_artifact') is not False or
            not isinstance(calibration.get('provenance'), str) or not calibration['provenance']):
        raise ValueError('Invalid neonatal sensitivity or legacy postprocessing policy')


def verify(build):
    copied = []

    def identical(source):
        relative = source.relative_to(ROOT)
        released = build / "assets" / relative
        if not released.is_file() or sha256(source) != sha256(released):
            raise ValueError(f"Release asset missing or different: {relative}")
        copied.append(relative.as_posix())
        return released

    contracts_path = ROOT / "assets/models/research_contracts.json"
    contracts = json.loads(identical(contracts_path).read_text(encoding="utf-8"))
    if contracts.get("schema_version") != 1 or set(contracts["models"]) != MODELS:
        raise ValueError("Unexpected research contract/model set")
    artifacts = {}
    for name in sorted(MODELS):
        model = identical(ROOT / f"assets/models/{name}_int8_v1.tflite")
        metadata = identical(ROOT / f"assets/models/{name}_int8_v1_metrics.json")
        metrics = json.loads(metadata.read_text(encoding="utf-8"))
        contract = contracts["models"][name]
        digest = sha256(model)
        if digest != metrics["tflite_sha256"] or digest != contract["artifact_sha256"]:
            raise ValueError(f"Model/metadata hash mismatch: {name}")
        if contract["model_version"] != metrics["model_version"]:
            raise ValueError(f"Model version mismatch: {name}")
        verify_output_policy(name, contract)
        artifacts[name] = digest

    audio = sorted((ROOT / "assets/audio").rglob("*.wav"))
    if len(audio) != 123:
        raise ValueError(f"Expected 123 preserved WAV assets, found {len(audio)}")
    for source in audio:
        released = identical(source)
        header = released.read_bytes()[:12]
        if header[:4] != b"RIFF" or header[8:12] != b"WAVE":
            raise ValueError(f"Invalid WAV header: {source.name}")
    for font in sorted((ROOT / "assets/fonts").glob("*.ttf")):
        identical(font)
    for required in ["index.html", "main.dart.js", "flutter_bootstrap.js",
                     "sqlite3.wasm", "canvaskit/canvaskit.wasm"]:
        path = build / required
        if not path.is_file() or path.stat().st_size == 0:
            raise ValueError(f"Missing local runtime: {required}")
    html = (build / "index.html").read_text(encoding="utf-8")
    if "fonts.googleapis.com" in html or "fonts.gstatic.com" in html:
        raise ValueError("Release HTML still loads external fonts")
    return {"passed": True, "model_sha256": artifacts, "wav_count": len(audio),
            "identical_source_assets": len(copied), "clinical_use_allowed": False,
            "scope": "Release payload integrity only; browser offline save/reload requires a separate test"}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", type=Path, default=ROOT / "build/web")
    args = parser.parse_args()
    print(json.dumps(verify(args.build.resolve()), indent=2))
