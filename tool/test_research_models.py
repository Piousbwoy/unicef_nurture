"""Local engineering tests; no training promotion, network, or source-data writes."""
import ast
import json
from pathlib import Path
import unittest
from unittest.mock import patch

import numpy as np
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import brier_score_loss

import evaluate_research_models as research


class ResearchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.schemas = research.legacy_schemas()
        cls.run_dir = research.ROOT / 'tool/research_runs/evidence_v1'

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
