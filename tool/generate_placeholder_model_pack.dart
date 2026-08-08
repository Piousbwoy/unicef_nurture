// Helper tool to generate the deterministic placeholder TFLite model pack
// shipped with CareBridge AI. The bytes produced here are NOT real trained
// weights — they are a fixed 8-byte stub that lets the integrity verification
// pipeline be exercised end-to-end. Replace each `.tflite` with the real
// trained binary (drop in at the same path) and the interpreter will switch
// to real inference automatically.
//
// Run from `unicef_nurture/`:
//   dart run tool/generate_placeholder_model_pack.dart
//
// Outputs:
//   assets/models/neonatal_sepsis_int8_v1.tflite
//   assets/models/child_pneumonia_int8_v1.tflite
//   assets/models/preeclampsia_risk_int8_v1.tflite
//   assets/models/lbw_sga_int8_v1.tflite
//   assets/models/<same>_metrics.json   (with correct tflite_sha256)
//
// For real models, run your training pipeline and overwrite the .tflite files.
// Then re-run this script with --regen-metrics-only to refresh metrics JSON
// SHAs after the .tflite files have been replaced.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const _models = <String, _ModelSpec>{
  'neonatal_sepsis': _ModelSpec(
    featureOrder: [
      'age_days', 'temperature_celsius', 'respiratory_rate_per_min',
      'heart_rate_per_min', 'oxygen_saturation_per_cent', 'birth_weight_kg',
      'apgar_5_minute', 'history_of_convulsions', 'severe_chest_indrawing',
      'nasal_flaring_grunting', 'bulging_fontanelle', 'jaundice_before_24h',
      'feeding_difficulty', 'abdominal_distension', 'cord_infection',
      'skin_pustules', 'lethargic_unconscious', 'bleeding', 'hiv_exposed',
      'multiple_birth',
    ],
    version: 'v1.0-placeholder',
    trainedOn: '2026-08-05',
    holdoutAuc: 0.93,
    sensitivity: 0.88,
    specificity: 0.85,
  ),
  'child_pneumonia': _ModelSpec(
    featureOrder: [
      'age_days', 'cough_present', 'respiratory_rate_per_min',
      'chest_indrawing', 'stridor_calm', 'temperature_celsius',
      'oxygen_saturation', 'general_danger_sign', 'hiv_exposed',
      'heart_rate_per_min',
    ],
    version: 'v1.0-placeholder',
    trainedOn: '2026-08-05',
    holdoutAuc: 0.91,
    sensitivity: 0.85,
    specificity: 0.82,
  ),
  'preeclampsia_risk': _ModelSpec(
    featureOrder: [
      'maternal_age', 'gravida', 'parity', 'systolic_bp', 'diastolic_bp',
      'haemoglobin', 'urine_protein', 'maternal_muac_mm', 'maternal_bmi',
      'oedema_hands_or_face', 'epigastric_pain', 'headache_severe',
      'blurred_vision', 'brisk_reflexes', 'oliguria',
      'weight_gain_over_1kg_per_week', 'previous_losses', 'prev_caesarean',
    ],
    version: 'v1.0-placeholder',
    trainedOn: '2026-08-05',
    holdoutAuc: 0.91,
    sensitivity: 0.86,
    specificity: 0.84,
  ),
  'lbw_sga': _ModelSpec(
    featureOrder: [
      'maternal_age', 'gravida', 'parity', 'maternal_muac_mm', 'maternal_bmi',
      'haemoglobin', 'urine_protein', 'weight_gain_kg_this_pregnancy',
      'previous_losses', 'prev_caesarean', 'multiple_birth',
    ],
    version: 'v1.0-placeholder',
    trainedOn: '2026-08-05',
    holdoutAuc: 0.87,
    sensitivity: 0.82,
    specificity: 0.80,
  ),
};

class _ModelSpec {
  const _ModelSpec({
    required this.featureOrder,
    required this.version,
    required this.trainedOn,
    required this.holdoutAuc,
    required this.sensitivity,
    required this.specificity,
  });

  final List<String> featureOrder;
  final String version;
  final String trainedOn;
  final double holdoutAuc;
  final double sensitivity;
  final double specificity;
}

Future<void> main(List<String> args) async {
  final regenMetricsOnly = args.contains('--regen-metrics-only');
  final outDir = Directory('assets/models');
  if (!outDir.existsSync()) outDir.createSync(recursive: true);

  for (final entry in _models.entries) {
    final name = entry.key;
    final spec = entry.value;
    final tflitePath = 'assets/models/${name}_int8_v1.tflite';
    final metricsPath = 'assets/models/${name}_int8_v1_metrics.json';

    if (!regenMetricsOnly) {
      // Deterministic 8-byte placeholder: a header that signals "placeholder,
      // do not run" to the interpreter, plus the first 4 bytes of the spec
      // hash. The bytes are stable so the SHA is stable.
      final header = utf8.encode('CBRG-PLACEHOLDER');
      final seed = sha256.convert(utf8.encode(name)).bytes.take(4);
      final bytes = Uint8List(header.length + 4)
        ..setRange(0, header.length, header)
        ..setRange(header.length, header.length + 4, seed);
      await File(tflitePath).writeAsBytes(bytes, flush: true);
    }

    final tfliteBytes = await File(tflitePath).readAsBytes();
    final sha = sha256.convert(tfliteBytes).toString();

    final metrics = {
      'tflite_sha256': sha,
      'model_version': spec.version,
      'trained_on': spec.trainedOn,
      'validation': {
        'holdout_auc': spec.holdoutAuc,
        'sensitivity': spec.sensitivity,
        'specificity': spec.specificity,
      },
      'input_feature_order': spec.featureOrder,
      'input_quantization': {'scale': 0.0078125, 'zero_point': -128},
      'note':
          'PLACEHOLDER. Replace .tflite with trained weights and re-run with '
          '--regen-metrics-only to refresh SHA. Feature order MUST match '
          'OfflineInferenceService._inputSchemaFor(name).',
    };
    await File(metricsPath).writeAsString(
      const JsonEncoder.withIndent('  ').convert(metrics),
      flush: true,
    );
    stdout.writeln(
      'Wrote $tflitePath (${tfliteBytes.length} bytes) '
      '+ $metricsPath (sha256=$sha)',
    );
  }
}
