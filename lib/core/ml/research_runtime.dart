part of 'offline_inference_service.dart';

abstract final class ResearchTransform {
  static double normalize(double value, double minimum, double maximum) {
    if (!value.isFinite ||
        !minimum.isFinite ||
        !maximum.isFinite ||
        maximum <= minimum ||
        value < minimum ||
        value > maximum) {
      throw const FormatException('Value outside normalization contract');
    }
    return (value - minimum) / (maximum - minimum);
  }
}

/// Offline research runtime. Clinical rules do not depend on this service.
class OfflineInferenceService {
  OfflineInferenceService({AssetBundle? bundle, TfliteRunner? runner})
    : _bundle = bundle ?? rootBundle,
      _runner = runner ?? getTfliteRunner();
  static final instance = OfflineInferenceService();
  static const neonatalArtifact =
      'b40ce5c43958b16bf6508887f49d79e7de7c0e6b8c4fd68ffabefb8a8d2b0fff';
  static const neonatalPolicy = 'neonatal-five-observed-v1';
  static const _neonatalMeans = {
    'age_days': .0296,
    'temperature_celsius': .6548,
    'respiratory_rate_per_min': .4019,
    'heart_rate_per_min': .5754,
    'birth_weight_kg': .5274,
  };
  static const _neonatalOrder = [
    'age_days',
    'temperature_celsius',
    'respiratory_rate_per_min',
    'heart_rate_per_min',
    'oxygen_saturation_per_cent',
    'birth_weight_kg',
    'apgar_5_minute',
    'history_of_convulsions',
    'severe_chest_indrawing',
    'nasal_flaring_grunting',
    'bulging_fontanelle',
    'jaundice_before_24h',
    'feeding_difficulty',
    'abdominal_distension',
    'cord_infection',
    'skin_pustules',
    'lethargic_unconscious',
    'bleeding',
    'hiv_exposed',
    'multiple_birth',
  ];

  static bool _validExperimentalPolicy(Map c, List<Map> features) {
    if (c['model_name'] != 'neonatal_sepsis' ||
        c['artifact_sha256'] != neonatalArtifact ||
        c['evidence'] != 'legacy_real_data' ||
        c['input_policy_version'] != neonatalPolicy ||
        c['output_scope'] != 'clinician_experimental' ||
        jsonEncode(c['age_days_support']) != '[0,3]' ||
        jsonEncode(features.map((f) => f['name']).toList()) !=
            jsonEncode(_neonatalOrder)) {
      return false;
    }
    final cal = c['calibration'];
    final baseline = c['sensitivity_baseline'];
    if (cal is! Map ||
        cal['A'] != 2.013769 ||
        cal['B'] != -5.826344 ||
        cal['validated_for_artifact'] != false ||
        cal['formula'] != 'sigmoid(A * logit(p) + B)' ||
        cal['provenance'] is! String ||
        baseline is! Map ||
        baseline['artifact_sha256'] != neonatalArtifact ||
        baseline['input_policy_version'] != neonatalPolicy ||
        baseline['means'] is! Map) {
      return false;
    }
    final means = baseline['means'] as Map;
    if (means.length != 5 ||
        !_neonatalMeans.entries.every((e) => means[e.key] == e.value)) {
      return false;
    }
    for (final f in features) {
      final key = f['name'];
      if (_neonatalMeans.containsKey(key)) {
        final bounds = switch (key) {
          'age_days' => (0, 59),
          'temperature_celsius' => (34, 41),
          'respiratory_rate_per_min' => (20, 120),
          'heart_rate_per_min' => (60, 220),
          _ => (.8, 5),
        };
        if (f['input_policy'] != 'observed' ||
            f['required'] != true ||
            f['supported'] != true ||
            f['imputation'] != null ||
            f['min'] != bounds.$1 ||
            f['max'] != bounds.$2 ||
            f['input_source'] !=
                (key == 'birth_weight_kg' ? 'current_weight_kg' : key)) {
          return false;
        }
      } else {
        final reason =
            key == 'feeding_difficulty' || key == 'lethargic_unconscious'
            ? 'legacy_encoding_defect'
            : 'unavailable_training_feature';
        if (f['input_policy'] != 'constant_normalized' ||
            f['constant_normalized'] != 0 ||
            f['supported'] != false ||
            f['required'] != false ||
            f['imputation'] != null ||
            f['fixed_reason'] != reason) {
          return false;
        }
      }
    }
    return true;
  }

  static bool _validInputPolicy(Map f, Set<String> rawKeys) =>
      switch (f['input_policy']) {
        null =>
          f['input_source'] == null || rawKeys.contains(f['input_source']),
        'observed' => rawKeys.contains(f['input_source'] ?? f['name']),
        'constant_normalized' =>
          f['constant_normalized'] is num &&
              (f['constant_normalized'] as num).isFinite &&
              (f['constant_normalized'] as num) >= 0 &&
              (f['constant_normalized'] as num) <= 1 &&
              f['required'] == false &&
              f['supported'] == false &&
              f['fixed_reason'] is String &&
              (f['fixed_reason'] as String).isNotEmpty,
        _ => false,
      };

  static double _adjust(double raw, Map cal) {
    if (!raw.isFinite || raw < 0 || raw > 1) {
      throw const FormatException('Invalid model output');
    }
    final clipped = raw.clamp(1e-7, 1 - 1e-7);
    return 1 /
        (1 +
            math.exp(
              -((cal['A'] as num) * math.log(clipped / (1 - clipped)) +
                  (cal['B'] as num)),
            ));
  }

  final AssetBundle _bundle;
  final TfliteRunner _runner;
  Future<void>? _initialization;
  final Map<String, OfflineModelStatus> _statuses = {};
  static const modelNames = [
    'neonatal_sepsis',
    'child_pneumonia',
    'preeclampsia_risk',
    'lbw_sga',
  ];

  Future<void> _initialize() => _initialization ??= _load();

  Future<void> _load() async {
    Map contracts = {};
    try {
      final root =
          jsonDecode(
                await _bundle.loadString(
                  'assets/models/research_contracts.json',
                ),
              )
              as Map;
      if (root['schema_version'] == 1) contracts = root['models'] as Map;
    } catch (_) {
      // Missing or invalid contracts fail closed, independently of file integrity.
    }
    for (final name in modelNames) {
      final path = 'assets/models/${name}_int8_v1.tflite';
      final metricsPath = path.replaceAll('.tflite', '_metrics.json');
      String? actual, expected;
      TfliteDartModel? graph;
      Map<String, Object?> metrics = {};
      Map<String, Object?> contract = {};
      Map<String, Object?> evaluation = {};
      try {
        final bytes = await _bundle.load(path);
        final data = bytes.buffer.asUint8List(
          bytes.offsetInBytes,
          bytes.lengthInBytes,
        );
        actual = sha256.convert(data).toString();
        graph = TfliteDartModel.fromBytes(data);
      } catch (_) {}
      try {
        metrics = Map<String, Object?>.from(
          jsonDecode(await _bundle.loadString(metricsPath)) as Map,
        );
        expected = metrics['tflite_sha256'] as String?;
      } catch (_) {}
      var valid = false;
      try {
        contract = Map<String, Object?>.from(contracts[name] as Map);
        final features = (contract['features'] as List).cast<Map>();
        evaluation = Map<String, Object?>.from(contract['evaluation'] as Map);
        final calibration = contract['calibration'];
        final calibrationValid =
            contract['patient_output_allowed'] != true ||
            (calibration is Map &&
                calibration['A'] is num &&
                calibration['B'] is num &&
                (calibration['A'] as num).isFinite &&
                (calibration['B'] as num).isFinite);
        final ageSupport = contract['age_days_support'];
        final supportValid =
            ageSupport == null ||
            (ageSupport is List &&
                ageSupport.length == 2 &&
                ageSupport.every((v) => v is num && v.isFinite) &&
                (ageSupport[0] as num) <= (ageSupport[1] as num));
        final rawKeys = const OfflineFeatureBag().rawFeatures.keys.toSet();
        valid =
            graph != null &&
            supportValid &&
            calibrationValid &&
            (contract['input_policy_version'] == null &&
                    contract['output_scope'] == null
                ? contract['evidence'] != 'legacy_real_data' ||
                      contract['patient_output_allowed'] != true
                : _validExperimentalPolicy(contract, features)) &&
            contract['patient_output_allowed'] is bool &&
            contract['clinical_use_allowed'] == false &&
            [
              'legacy_real_data',
              'synthetic',
              'retrospective_research',
            ].contains(contract['evidence']) &&
            contract['input_quantization_arithmetic'] ==
                'float32_divide_add_round_ties_away_from_zero' &&
            contract['model_type'] == 'dense_network' &&
            contract['output_type'] == 'binary_probability' &&
            contract['input_dtype'] == graph.inputDtype &&
            contract['output_dtype'] == graph.outputDtype &&
            jsonEncode(contract['input_shape']) ==
                jsonEncode(graph.inputShape) &&
            jsonEncode(contract['output_shape']) ==
                jsonEncode(graph.outputShape) &&
            _sameQuantization(
              contract['input_quantization'],
              graph.inputQuantization,
            ) &&
            _sameQuantization(
              contract['output_quantization'],
              graph.outputQuantization,
            ) &&
            graph.inputCount == features.length &&
            contract['schema_version'] == 1 &&
            contract['model_name'] == name &&
            contract['model_version'] is String &&
            contract['model_version'] == metrics['model_version'] &&
            features.isNotEmpty &&
            features.map((f) => f['name']).toSet().length == features.length &&
            features.every(
              (f) =>
                  f['name'] is String &&
                  rawKeys.contains(f['name']) &&
                  _validInputPolicy(f, rawKeys) &&
                  ['bool', 'int', 'double', 'float'].contains(f['kind']) &&
                  f['unit'] is String &&
                  f['min'] is num &&
                  f['max'] is num &&
                  (f['min'] as num).isFinite &&
                  (f['max'] as num).isFinite &&
                  (f['max'] as num) > (f['min'] as num) &&
                  f['transform'] == 'min_max' &&
                  f['required'] is bool &&
                  f['supported'] is bool &&
                  (f['imputation'] == null ||
                      (f['imputation'] is num &&
                          (f['imputation'] as num).isFinite &&
                          (f['imputation'] as num) >= (f['min'] as num) &&
                          (f['imputation'] as num) <= (f['max'] as num))),
            );
      } catch (_) {}
      final integrity =
          expected != null &&
          RegExp(r'^[a-f0-9]{64}$').hasMatch(expected) &&
          expected == actual;
      valid = valid && contract['artifact_sha256'] == actual;
      _statuses[name] = OfflineModelStatus(
        name: name,
        modelAssetPath: path,
        metricsAssetPath: metricsPath,
        isModelPresent: actual != null,
        isModelUsable: integrity && valid,
        hasMetrics: metrics.isNotEmpty,
        expectedSha256: expected,
        actualSha256: actual,
        integrityVerified: integrity,
        modelVersion: metrics['model_version'] is String
            ? metrics['model_version'] as String
            : null,
        trainingDataset: metrics['training_dataset'] is String
            ? metrics['training_dataset'] as String
            : null,
        contract: contract,
        metadataValid: valid,
        internalValidation: evaluation,
      );
    }
  }

  static bool _sameQuantization(Object? expected, List<num> actual) =>
      expected is List &&
      expected.length == 2 &&
      expected[0] is num &&
      expected[1] is num &&
      expected[0] == actual[0] &&
      expected[1] == actual[1];

  Future<List<OfflineModelStatus>> modelStatuses() async {
    await _initialize();
    return [for (final name in modelNames) _statuses[name]!];
  }

  Future<OfflineRiskPrediction> neonatalSepsisRisk(OfflineFeatureBag bag) =>
      _predict('neonatal_sepsis', bag);
  Future<OfflineRiskPrediction> childPneumoniaRisk(OfflineFeatureBag bag) =>
      _predict('child_pneumonia', bag);
  Future<OfflineRiskPrediction> preeclampsiaRisk(OfflineFeatureBag bag) =>
      _predict('preeclampsia_risk', bag);
  Future<OfflineRiskPrediction> lbwSgaRisk(OfflineFeatureBag bag) =>
      _predict('lbw_sga', bag);

  Future<Map<String, OfflineRiskPrediction>> runAllPredictions(
    OfflineFeatureBag bag, {
    bool includeNeonatal = true,
    bool includeChildPneumonia = true,
    bool includePreeclampsia = true,
    bool includeLbwSga = true,
  }) async {
    final enabled = [
      includeNeonatal,
      includeChildPneumonia,
      includePreeclampsia,
      includeLbwSga,
    ];
    final values = await Future.wait([
      for (var i = 0; i < modelNames.length; i++)
        if (enabled[i]) _predict(modelNames[i], bag),
    ]);
    return {for (final p in values) p.modelName: p};
  }

  /// Input ablation for technical tests, not a causal treatment recommendation.
  Future<OfflineRiskPrediction> predictWithout({
    required String modelName,
    required OfflineFeatureBag bag,
    required String removedFeature,
  }) => _predict(modelName, bag.withoutFeature(removedFeature));

  Future<OfflineRiskPrediction> _predict(
    String name,
    OfflineFeatureBag bag,
  ) async {
    if (!modelNames.contains(name)) {
      throw ArgumentError.value(name, 'modelName');
    }
    await _initialize();
    final watch = Stopwatch()..start();
    final status = _statuses[name]!;
    final c = status.contract;
    final evidence = switch (c['evidence']) {
      'legacy_real_data' => ModelEvidence.legacyRealData,
      'synthetic' => ModelEvidence.synthetic,
      'retrospective_research' => ModelEvidence.retrospectiveResearch,
      _ => ModelEvidence.unknown,
    };
    var applicability = ModelApplicability.applicable;
    if (name == 'neonatal_sepsis') {
      if (bag.ageDays == null) {
        applicability = ModelApplicability.unknownCohort;
      } else if (bag.isMaternal || bag.ageDays! < 0 || bag.ageDays! > 59) {
        applicability = ModelApplicability.unsupportedCohort;
      }
    } else if (name == 'child_pneumonia') {
      if (bag.ageMonths == null) {
        applicability = ModelApplicability.unknownCohort;
      } else if (bag.isMaternal || bag.ageMonths! < 2 || bag.ageMonths! > 59) {
        applicability = ModelApplicability.unsupportedCohort;
      }
    } else if (!bag.isMaternal) {
      applicability = ModelApplicability.unsupportedCohort;
    } else if (bag.gestationalWeeks == null) {
      applicability = ModelApplicability.unknownCohort;
    } else if (bag.gestationalWeeks! <
            (name == 'preeclampsia_risk' ? 20 : 36) ||
        bag.gestationalWeeks! > 45) {
      applicability = ModelApplicability.unsupportedCohort;
    }
    final used = <String>[],
        missing = <String>[],
        unsupported = <String>[],
        invalid = <String>[],
        outside = <String>[];
    final observed = <String, double>{};
    final measured = <String, double>{};
    final units = <String, String>{};
    final fixed = <String, String>{};
    final imputed = <String>[], requiredMissing = <String>[];
    final features = status.metadataValid
        ? (c['features'] as List).cast<Map>()
        : <Map>[];
    final tensor = Float32List(features.length);
    final raw = bag.rawFeatures;
    for (var i = 0; i < features.length; i++) {
      final f = features[i];
      final key = (f['input_source'] ?? f['name']) as String;
      if (f['input_policy'] == 'constant_normalized') {
        tensor[i] = (f['constant_normalized'] as num).toDouble();
        fixed[f['name'] as String] = f['fixed_reason'] as String;
        continue;
      }
      if (f['supported'] != true) {
        unsupported.add(key);
        continue;
      }
      final value = raw[key];
      if (value == null) {
        missing.add(key);
        if (f['required'] == true || f['imputation'] == null) {
          requiredMissing.add(key);
        } else {
          final lo = (f['min'] as num).toDouble(),
              hi = (f['max'] as num).toDouble();
          tensor[i] = ResearchTransform.normalize(
            (f['imputation'] as num).toDouble(),
            lo,
            hi,
          );
          imputed.add(key);
        }
        continue;
      }
      final lo = (f['min'] as num).toDouble(),
          hi = (f['max'] as num).toDouble();
      final physiological = switch (key) {
        'temperature_celsius' => (25.0, 45.0),
        'respiratory_rate_per_min' => (1.0, 150.0),
        'heart_rate_per_min' => (1.0, 300.0),
        'oxygen_saturation' || 'oxygen_saturation_per_cent' => (1.0, 100.0),
        _ => (0.0, double.infinity),
      };
      if (!value.isFinite ||
          (f['kind'] == 'bool' && value != 0 && value != 1) ||
          value < physiological.$1 ||
          value > physiological.$2) {
        invalid.add(key);
        continue;
      }
      if (value < lo || value > hi) {
        outside.add(key);
        continue;
      }
      tensor[i] = ResearchTransform.normalize(value, lo, hi);
      used.add(key);
      observed[key] = tensor[i];
      measured[key] = value;
      units[key] = f['unit'] as String;
    }
    final support = c['age_days_support'];
    if (status.metadataValid &&
        support is List &&
        bag.ageDays != null &&
        (bag.ageDays! < (support[0] as num) ||
            bag.ageDays! > (support[1] as num))) {
      outside.add('age_days');
    }
    final quality = invalid.isNotEmpty
        ? ModelInputQuality.invalidValues
        : outside.isNotEmpty
        ? ModelInputQuality.outsideSupport
        : requiredMissing.isNotEmpty
        ? ModelInputQuality.missingObservations
        : ModelInputQuality.complete;
    var execution = ModelExecution.notRun;
    String reason;
    double? researchOutput, rawNeuralOutput;
    var sensitivityStatus = ModelSensitivityStatus.notRun;
    final sensitivities = <ModelFeatureSensitivity>[];
    final experimental =
        status.metadataValid && c['input_policy_version'] == neonatalPolicy;
    if (!status.isModelPresent) {
      execution = ModelExecution.unavailable;
      reason =
          'Model file unavailable. Clinical guidance is still available offline.';
    } else if (!status.integrityVerified) {
      execution = ModelExecution.integrityFailure;
      reason =
          'File integrity could not be checked. Model execution is blocked.';
    } else if (!status.metadataValid) {
      execution = ModelExecution.invalidMetadata;
      reason =
          'Model metadata is missing or incompatible. Model execution is blocked.';
    } else if (applicability != ModelApplicability.applicable) {
      reason = applicability == ModelApplicability.unknownCohort
          ? 'Age or pregnancy eligibility is unknown.'
          : 'This model does not apply to this assessment cohort.';
    } else if (quality == ModelInputQuality.invalidValues) {
      reason =
          'Review invalid measurements. Clinical danger-sign guidance remains active.';
    } else if (quality == ModelInputQuality.outsideSupport) {
      reason =
          'Observed values are outside model support; this is not a clinical reassurance.';
    } else if (quality == ModelInputQuality.missingObservations) {
      reason =
          'Required observations are missing: ${requiredMissing.join(', ')}. No model output is shown.';
    } else if ((!experimental &&
            evidence != ModelEvidence.retrospectiveResearch) ||
        c['patient_output_allowed'] != true) {
      reason =
          'Research only. This artifact has not passed patient-output evidence checks.';
    } else {
      try {
        if (features.any(
          (f) =>
              f['input_policy'] != 'constant_normalized' &&
              (f['supported'] != true ||
                  (raw[f['input_source'] ?? f['name']] == null &&
                      !imputed.contains(f['input_source'] ?? f['name']))),
        )) {
          throw const FormatException(
            'Incomplete exported-model input contract',
          );
        }
        final p = await _runner.run(
          assetPath: status.modelAssetPath,
          input: tensor,
        );
        if (!p.isFinite || p < 0 || p > 1) {
          throw const FormatException('Invalid model output');
        }
        final cal = c['calibration'] as Map;
        rawNeuralOutput = p;
        researchOutput = _adjust(p, cal);
        if (!researchOutput.isFinite) {
          throw const FormatException('Invalid calibrated output');
        }
        execution = ModelExecution.completed;
        reason =
            'Experimental model output — not a diagnosis or treatment threshold.';
      } catch (_) {
        researchOutput = null;
        rawNeuralOutput = null;
        execution = ModelExecution.failed;
        reason =
            'Model execution failed. Clinical guidance remains available offline.';
      }
    }
    if (execution == ModelExecution.completed && experimental) {
      try {
        for (var i = 0; i < features.length; i++) {
          final f = features[i];
          if (f['input_policy'] != 'observed') continue;
          final key = f['input_source'] as String;
          final baseline = _neonatalMeans[f['name']]!;
          final replacement = Float32List.fromList(tensor)..[i] = baseline;
          final output = await _runner.run(
            assetPath: status.modelAssetPath,
            input: replacement,
          );
          sensitivities.add(
            ModelFeatureSensitivity(
              featureKey: key,
              rawValue: measured[key]!,
              unit: units[key]!,
              baselineNormalized: baseline,
              scorePointDelta:
                  100 *
                  (researchOutput! - _adjust(output, c['calibration'] as Map)),
            ),
          );
        }
        sensitivities.sort((a, b) {
          final magnitude = b.scorePointDelta.abs().compareTo(
            a.scorePointDelta.abs(),
          );
          return magnitude != 0
              ? magnitude
              : used
                    .indexOf(a.featureKey)
                    .compareTo(used.indexOf(b.featureKey));
        });
        sensitivityStatus = ModelSensitivityStatus.completed;
      } catch (_) {
        sensitivities.clear();
        sensitivityStatus = ModelSensitivityStatus.unavailable;
      }
    }
    return OfflineRiskPrediction(
      modelName: name,
      usingModel: execution == ModelExecution.completed,
      riskProbability: null,
      classification: 'unavailable',
      featuresUsed: used,
      featuresMissing: missing,
      predictedAt: DateTime.now(),
      modelVersion: status.modelVersion,
      inferenceMs: watch.elapsedMilliseconds,
      featureValues: observed,
      researchOutput: researchOutput,
      rawNeuralOutput: rawNeuralOutput,
      patientOutputAllowed: c['patient_output_allowed'] == true,
      outputScope: c['output_scope'] is String
          ? c['output_scope'] as String
          : null,
      artifactSha256: status.actualSha256,
      inputPolicyVersion: c['input_policy_version'] is String
          ? c['input_policy_version'] as String
          : null,
      runtimeVerified: status.isModelUsable,
      observedValues: Map.unmodifiable(measured),
      featureUnits: Map.unmodifiable(units),
      fixedFeatures: Map.unmodifiable(fixed),
      postprocessing: status.metadataValid && c['calibration'] is Map
          ? Map.unmodifiable(Map<String, Object?>.from(c['calibration'] as Map))
          : const {},
      sensitivities: List.unmodifiable(sensitivities),
      sensitivityStatus: sensitivityStatus,
      execution: execution,
      applicability: applicability,
      inputQuality: quality,
      evidence: evidence,
      unsupportedFeatures: unsupported,
      invalidFeatures: invalid,
      imputedFeatures: imputed,
      driftDetected: outside.isNotEmpty,
      driftFeatures: outside.toSet().toList(),
      statusReason: reason,
    );
  }
}

extension ResearchFeatures on OfflineFeatureBag {
  Map<String, double?> get rawFeatures {
    double? b(bool? value) => value == null
        ? null
        : value
        ? 1
        : 0;
    double? either(bool? a, bool? c) => a == true || c == true
        ? 1
        : a == false && c == false
        ? 0
        : null;
    return {
      'age_days': ageDays?.toDouble(),
      'temperature_celsius': temperatureCelsius,
      'respiratory_rate_per_min': respiratoryRatePerMin?.toDouble(),
      'heart_rate_per_min': heartRatePerMin?.toDouble(),
      'oxygen_saturation_per_cent': oxygenSaturationPerCent?.toDouble(),
      'oxygen_saturation': oxygenSaturationPerCent?.toDouble(),
      'birth_weight_kg': birthWeightKg,
      'current_weight_kg': currentWeightKg,
      'apgar_5_minute': apgar5Minute?.toDouble(),
      'history_of_convulsions': b(historyOfConvulsions),
      'severe_chest_indrawing': b(severeChestIndrawing),
      'nasal_flaring_grunting': either(nasalFlaring, grunting),
      'bulging_fontanelle': b(bulgingFontanelle),
      'jaundice_before_24h': b(jaundiceBefore24h),
      'feeding_difficulty': b(feedingDifficulty),
      'abdominal_distension': b(abdominalDistension),
      'cord_infection': either(cordPus, cordRednessBeyondBase),
      'skin_pustules': b(skinPustules),
      'lethargic_unconscious': b(lethargicOrUnconscious),
      'bleeding': b(bleedingFromAnySite),
      'hiv_exposed': b(hivExposedOrInfected),
      'multiple_birth': b(multipleBirth),
      'cough_present': b(coughPresent),
      'chest_indrawing': b(chestIndrawing),
      'stridor_calm': b(stridorCalm),
      'general_danger_sign': b(generalDangerSign),
      'maternal_age': maternalAgeYears?.toDouble(),
      'gravida': gravida?.toDouble(),
      'parity': parity?.toDouble(),
      'systolic_bp': systolicBloodPressureMmhg?.toDouble(),
      'diastolic_bp': diastolicBloodPressureMmhg?.toDouble(),
      'haemoglobin': haemoglobinGDl,
      'urine_protein': urineProtein0To4?.toDouble(),
      'maternal_muac_mm': maternalMuacMm?.toDouble(),
      'maternal_bmi': maternalBmi,
      'oedema_hands_or_face': b(oedemaHandsOrFace),
      'epigastric_pain': b(epigastricPain),
      'headache_severe': b(headacheSevere),
      'blurred_vision': b(blurredVision),
      'brisk_reflexes': b(briskReflexes),
      'oliguria': b(oliguria),
      'weight_gain_over_1kg_per_week': b(weightGainOver1kgPerWeek),
      'previous_losses': previousPregnancyLosses?.toDouble(),
      'prev_caesarean': b(prevCaesareanSection),
      'weight_gain_kg_this_pregnancy': weightGainKgThisPregnancy,
    };
  }
}
