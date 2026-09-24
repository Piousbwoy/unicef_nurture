"""Local engineering tests; no training promotion, network, or source-data writes."""
import ast
import json
import copy
import ctypes
import sys
import shutil
import tempfile
from pathlib import Path
import unittest
from unittest.mock import patch

import numpy as np
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import brier_score_loss

import evaluate_research_models as research
import verify_release_assets as release


class ResearchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.schemas = research.legacy_schemas()
        cls.run_dir = research.ROOT / 'tool/research_runs/evidence_v1'

    def test_generated_contract_preserves_experimental_training_policy(self):
        contracts = research.build_contract(self.schemas)['models']
        c = contracts['neonatal_sepsis']
        self.assertTrue(c['patient_output_allowed'])
        self.assertFalse(c['clinical_use_allowed'])
        self.assertEqual(c['output_scope'], 'clinician_experimental')
        observed = [f for f in c['features'] if f['input_policy'] == 'observed']
        fixed = [f for f in c['features'] if f['input_policy'] == 'constant_normalized']
        self.assertEqual(len(observed), 5)
        self.assertEqual(len(fixed), 15)
        self.assertTrue(all(f['constant_normalized'] == 0 and not f['supported'] for f in fixed))
        self.assertEqual(observed[-1]['input_source'], 'current_weight_kg')
        self.assertTrue(all(f['required'] and f['imputation'] is None for f in observed))
        self.assertFalse(c['calibration']['validated_for_artifact'])
        for name in contracts.keys() - {'neonatal_sepsis'}:
            self.assertFalse(contracts[name]['patient_output_allowed'])

    def test_release_accepts_only_pinned_experimental_policy(self):
        original = json.loads((research.ASSETS / 'research_contracts.json').read_text())
        with tempfile.TemporaryDirectory(dir=research.ROOT / '.dart_tool') as temp:
            root = Path(temp)
            build = root / 'build'
            for name in release.MODELS:
                for suffix in ['.tflite', '_metrics.json']:
                    relative = Path(f'assets/models/{name}_int8_v1{suffix}')
                    for target in [root / relative, build / 'assets' / relative]:
                        target.parent.mkdir(parents=True, exist_ok=True)
                        shutil.copyfile(research.ROOT / relative, target)
            for i in range(123):
                relative = Path(f'assets/audio/test_{i}.wav')
                for target in [root / relative, build / 'assets' / relative]:
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(b'RIFF\x00\x00\x00\x00WAVE')
            for name in ['index.html', 'main.dart.js', 'flutter_bootstrap.js',
                         'sqlite3.wasm', 'canvaskit/canvaskit.wasm']:
                target = build / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text('test runtime placeholder')

            def check(contracts):
                for target in [root / 'assets/models/research_contracts.json',
                               build / 'assets/assets/models/research_contracts.json']:
                    target.write_text(json.dumps(contracts), encoding='utf-8')
                with patch.object(release, 'ROOT', root):
                    return release.verify(build)

            self.assertTrue(check(original)['passed'])
            mutations = [
                ('clinical authority', lambda c: c.update(clinical_use_allowed=True)),
                ('scope', lambda c: c.update(output_scope='clinical')),
                ('policy', lambda c: c.update(input_policy_version='unknown')),
                ('age support', lambda c: c.update(age_days_support=[0, 59])),
                ('evidence', lambda c: c.update(evidence='synthetic')),
                ('fixed value', lambda c: c['features'][4].update(constant_normalized=.1)),
                ('fixed reason', lambda c: c['features'][12].update(fixed_reason='unavailable_training_feature')),
                ('weight source', lambda c: c['features'][5].update(input_source='birth_weight_kg')),
                ('required input', lambda c: c['features'][1].update(required=False)),
                ('bounds', lambda c: c['features'][1].update(max=45)),
                ('baseline', lambda c: c['sensitivity_baseline']['means'].update(age_days=.5)),
                ('postprocessing', lambda c: c['calibration'].update(validated_for_artifact=True)),
                ('quantization', lambda c: c.update(input_quantization=[1., 0])),
            ]
            for name, mutate in mutations:
                with self.subTest(name=name):
                    changed = copy.deepcopy(original)
                    mutate(changed['models']['neonatal_sepsis'])
                    with self.assertRaises(ValueError):
                        check(changed)
            for name in release.MODELS - {'neonatal_sepsis'}:
                changed = copy.deepcopy(original)
                changed['models'][name]['patient_output_allowed'] = True
                with self.assertRaises(ValueError):
                    check(changed)

    def test_experimental_golden_vectors_use_five_observations(self):
        fixture = research.experimental_neonatal_fixture()
        self.assertEqual(fixture['artifact_sha256'], 'b40ce5c43958b16bf6508887f49d79e7de7c0e6b8c4fd68ffabefb8a8d2b0fff')
        self.assertEqual(fixture['input_policy_version'], 'neonatal-five-observed-v1')
        self.assertEqual(len(fixture['cases']), 8)
        first = fixture['cases'][0]
        self.assertEqual(first['quantized'], [-119, -19, -57, -1, -128, 6] + [-128] * 14)
        for case in fixture['cases']:
            self.assertTrue(all(case['normalized'][i] == 0 for i in [4] + list(range(6, 20))))
            self.assertTrue(0 <= case['raw_output'] <= 1)
            self.assertTrue(0 <= case['adjusted_output'] <= 1)
        for i, slot in enumerate([0, 1, 2, 3, 5]):
            replacement = fixture['cases'][i + 3]['normalized']
            self.assertAlmostEqual(replacement[slot], [.0296, .6548, .4019, .5754, .5274][i], places=7)
            self.assertTrue(all(replacement[j] == first['normalized'][j] for j in range(20) if j != slot))

    @unittest.skipUnless(sys.platform == 'win32', 'Windows native-library parity')
    def test_windows_native_library_matches_experimental_vectors(self):
        """Native C API parity, not Flutter host or physical-device acceptance."""
        library = research.ROOT / 'blobs/libtensorflowlite_c-win.dll'
        if not library.is_file():
            self.skipTest('Bundled Windows TFLite library is unavailable')
        api = ctypes.CDLL(str(library))

        def bind(name, result, *arguments):
            function = getattr(api, name)
            function.restype = result
            function.argtypes = arguments
            return function

        pointer = ctypes.c_void_p
        integer = ctypes.c_int
        size = ctypes.c_size_t
        model_create = bind('TfLiteModelCreateFromFile', pointer, ctypes.c_char_p)
        model_delete = bind('TfLiteModelDelete', None, pointer)
        options_create = bind('TfLiteInterpreterOptionsCreate', pointer)
        options_delete = bind('TfLiteInterpreterOptionsDelete', None, pointer)
        set_threads = bind('TfLiteInterpreterOptionsSetNumThreads', None, pointer, integer)
        create = bind('TfLiteInterpreterCreate', pointer, pointer, pointer)
        destroy = bind('TfLiteInterpreterDelete', None, pointer)
        allocate = bind('TfLiteInterpreterAllocateTensors', integer, pointer)
        input_tensor = bind('TfLiteInterpreterGetInputTensor', pointer, pointer, integer)
        output_tensor = bind('TfLiteInterpreterGetOutputTensor', pointer, pointer, integer)
        tensor_type = bind('TfLiteTensorType', integer, pointer)
        tensor_size = bind('TfLiteTensorByteSize', size, pointer)
        copy_input = bind('TfLiteTensorCopyFromBuffer', integer, pointer, pointer, size)
        copy_output = bind('TfLiteTensorCopyToBuffer', integer, pointer, pointer, size)
        invoke = bind('TfLiteInterpreterInvoke', integer, pointer)
        fixture = json.loads((self.run_dir / 'neonatal_experimental_parity.json').read_text())
        artifact = research.ASSETS / 'neonatal_sepsis_int8_v1.tflite'
        self.assertEqual(release.sha256(artifact), fixture['artifact_sha256'])
        model = model_create(str(artifact).encode())
        self.assertTrue(model)
        options = options_create()
        interpreter = None
        try:
            self.assertTrue(options)
            set_threads(options, 1)
            interpreter = create(model, options)
            self.assertTrue(interpreter)
            self.assertEqual(allocate(interpreter), 0)
            source = input_tensor(interpreter, 0)
            target = output_tensor(interpreter, 0)
            self.assertEqual((tensor_type(source), tensor_size(source)), (9, 20))
            self.assertEqual((tensor_type(target), tensor_size(target)), (1, 4))
            for case in fixture['cases']:
                with self.subTest(case=case['name']):
                    tensor = (ctypes.c_int8 * 20)(*case['quantized'])
                    self.assertEqual(copy_input(source, tensor, ctypes.sizeof(tensor)), 0)
                    self.assertEqual(invoke(interpreter), 0)
                    result = ctypes.c_float()
                    self.assertEqual(copy_output(target, ctypes.byref(result), ctypes.sizeof(result)), 0)
                    self.assertAlmostEqual(result.value, case['raw_output'], delta=1e-5)
        finally:
            if interpreter:
                destroy(interpreter)
            if options:
                options_delete(options)
            model_delete(model)

    def test_semantic_boolean_mapping_and_excluded_features(self):
        self.assertEqual(research.boolean('Yes'), 1)
        self.assertEqual(research.boolean('No'), 0)
        self.assertTrue(np.isnan(research.boolean('not collected')))
        _, _, _, features, audit = research.audit_dataset('neonatal_sepsis', self.schemas)
        self.assertIn('feeding_difficulty', features)
        self.assertNotIn('birth_weight_kg', features)
        self.assertFalse(audit['outcome_semantics_verified'])
        self.assertIn('weight', audit['excluded'])
        self.assertTrue(audit['local_provenance'])
        self.assertEqual(list(research.DATASETS['lbw_sga']['mapping']), ['maternal_age'])
        self.assertNotIn('haemoglobin', research.DATASETS['lbw_sga']['mapping'])

    def test_reproducible_grouped_splits_and_label_conflicts(self):
        for name in research.DATASETS:
            X, y, groups, _, audit = research.audit_dataset(name, self.schemas)
            parts = research.split_groups(X, y, groups)
            repeated = research.split_groups(X, y, groups)
            self.assertEqual(set(np.concatenate(list(parts.values()))), set(range(len(y))))
            for key in parts:
                np.testing.assert_array_equal(parts[key], repeated[key])
                self.assertEqual(set(y[parts[key]]), {0, 1})
            for a, b in [('training', 'calibration'), ('training', 'evaluation'), ('calibration', 'evaluation')]:
                self.assertFalse(set(groups[parts[a]]) & set(groups[parts[b]]))
            if name == 'preeclampsia_risk':
                self.assertGreater(audit['groups_with_conflicting_labels'], 0)

    def test_imputation_fits_only_training_folds(self):
        X = np.column_stack([np.arange(100, dtype=float), np.tile([0., 1.], 50)])
        X[::7, 1] = np.nan
        y = np.tile([0, 1], 50)
        groups = np.arange(100)
        seen = []

        class TrackedImputer(SimpleImputer):
            def fit(self, X, y=None):
                seen.append(np.asarray(X).copy())
                return super().fit(X, y)

        with patch.object(research, 'SimpleImputer', TrackedImputer), patch.object(
            research, 'candidates', lambda: iter([('logistic_C0.1', LogisticRegression(C=.1))])
        ):
            pipe, _, _ = research.select_candidate(X[:60], y[:60], groups[:60])
        self.assertGreaterEqual(len(seen), 3)
        self.assertTrue(all(np.max(v[:, 0]) < 60 for v in seen))
        np.testing.assert_allclose(pipe[0].statistics_, np.nanmedian(X[:60], axis=0))
        self.assertTrue(all(len(v) < 60 for v in seen[:-1]))

    def test_insufficient_groups_block_selection(self):
        with self.assertRaisesRegex(ValueError, 'Insufficient'):
            research.select_candidate(np.zeros((2, 1)), np.array([0, 1]), np.array([1, 1]))

    def test_model_specific_normalization_and_missingness(self):
        for name, schema in self.schemas.items():
            features = list(schema)
            raw = np.array([[schema[f][0] for f in features], [schema[f][1] for f in features]], dtype=float)
            expected = np.array([np.zeros(len(features)), np.ones(len(features))], dtype=np.float32)
            np.testing.assert_array_equal(research.normalize(raw, features, schema), expected)
        self.assertTrue(np.isnan(research.normalize([[np.nan]], ['age_days'], self.schemas['neonatal_sepsis'])[0, 0]))

    def test_platt_logit_formula_and_legacy_helpers(self):
        p = np.array([.1, .5, .8])
        np.testing.assert_allclose(research.apply_calibration(p, 1, 0), p)
        self.assertAlmostEqual(research.apply_calibration(np.array([.8]), 2, 0)[0], 16 / 17)
        for filename, function in [('train_model_pack.py', '_platt_calibrate_with_residuals'),
                                   ('fix_normalization_skew.py', '_platt_with_ci')]:
            tree = ast.parse((research.ROOT / 'tool' / filename).read_text(encoding='utf-8'))
            node = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == function)
            # Execute only this pure helper, not the archival trainer/import side effects.
            scope = {'np': np, 'LogisticRegression': LogisticRegression, 'brier_score_loss': brier_score_loss}
            exec(compile(ast.Module(body=[node], type_ignores=[]), filename, 'exec'), scope)
            y = np.array([0, 0, 1, 1, 1, 0])
            raw = np.array([.1, .3, .6, .8, .9, .2])
            result = scope[function](y, raw)
            a, b, brier = result[0], result[1], result[-2]
            self.assertAlmostEqual(brier, brier_score_loss(y, research.apply_calibration(raw, a, b)), places=7)

    def test_calibration_threshold_ties_favor_sensitivity(self):
        self.assertEqual(research.select_threshold(np.array([0, 1]), np.array([.5, .5])), .5)
        for name in research.DATASETS:
            report = json.loads((self.run_dir / f'{name}_evaluation.json').read_text())
            threshold = report['evaluation']['threshold']
            self.assertTrue(np.isfinite(threshold))
            before = research.digest((self.run_dir / f'{name}_evaluation.json').read_bytes())
            with patch.object(research, 'write_json'):
                research.verify_completed_run(name, self.schemas, self.run_dir)
            self.assertEqual(before, research.digest((self.run_dir / f'{name}_evaluation.json').read_bytes()))

    def test_exported_metrics_and_reliability_counts(self):
        y = np.array([0, 0, 1, 1])
        p = np.array([.1, .7, .4, .9])
        result = research.metrics(y, p, .5)
        self.assertEqual(result['confusion'], {'tn': 1, 'fp': 1, 'fn': 1, 'tp': 1})
        self.assertEqual(sum(b['n'] for b in result['reliability_bins']), 4)
        self.assertEqual(result['sensitivity'], .5)
        self.assertEqual(result['specificity'], .5)
        self.assertAlmostEqual(result['brier'], float(np.mean((p-y)**2)))

    def test_group_bootstrap_is_reproducible_and_rejects_singleton(self):
        y = np.array([0, 1, 0, 1])
        p = np.array([.2, .7, .1, .9])
        groups = np.array([0, 0, 1, 1])
        a = research.bootstrap(y, p, groups, .5, repeats=20)
        self.assertEqual(a, research.bootstrap(y, p, groups, .5, repeats=20))
        self.assertEqual(research.bootstrap(y, p, np.zeros(4), .5), {})

    def test_engineering_gates_never_override_semantics_or_parity(self):
        metrics = {'average_precision': .9, 'prevalence': .5, 'brier': .1}
        intervals = {'auroc': {'low': .8}}
        self.assertFalse(research.packaging_gate({'packaging_allowed': False}, metrics, intervals, .25, True))
        self.assertFalse(research.packaging_gate({'packaging_allowed': True}, metrics, intervals, .25, False))
        self.assertFalse(research.packaging_gate({'packaging_allowed': True}, metrics, {}, .25, True))
        for name in research.DATASETS:
            report = json.loads((self.run_dir / f'{name}_evaluation.json').read_text())
            self.assertFalse(report['packaged'])
            self.assertFalse(report['clinical_use_allowed'])

    def test_legacy_commands_redirect_before_archival_side_effects(self):
        for filename in ['train_model_pack.py', 'train_real_models.py', 'fix_normalization_skew.py']:
            tree = ast.parse((research.ROOT / 'tool' / filename).read_text(encoding='utf-8'))
            guard = next(n for n in tree.body if isinstance(n, ast.If))
            self.assertIn('evaluate_research_models', ast.unparse(guard))
            self.assertIn('raise SystemExit(0)', ast.unparse(guard))
            archived = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == '_archived_main')
            self.assertIsInstance(archived.body[0], ast.Raise)


if __name__ == '__main__':
    unittest.main()
