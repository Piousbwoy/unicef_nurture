part of 'offline_inference_service.dart';

enum ModelExecution {
  notRun,
  completed,
  unavailable,
  integrityFailure,
  invalidMetadata,
  failed,
}

enum ModelApplicability { applicable, unsupportedCohort, unknownCohort }

enum ModelInputQuality {
  complete,
  missingObservations,
  invalidValues,
  outsideSupport,
}

enum ModelEvidence { legacyRealData, synthetic, retrospectiveResearch, unknown }

enum ModelSensitivityStatus { notRun, completed, unavailable }

class ModelFeatureSensitivity {
  const ModelFeatureSensitivity({
    required this.featureKey,
    required this.rawValue,
    required this.unit,
    required this.baselineNormalized,
    required this.scorePointDelta,
  });
  final String featureKey;
  final double rawValue;
  final String unit;
  final double baselineNormalized;
  final double scorePointDelta;

  Map<String, Object?> toMap() => {
    'feature_key': featureKey,
    'raw_value': rawValue,
    'unit': unit,
    'baseline_normalized': baselineNormalized,
    'score_point_delta': scorePointDelta,
  };
}

/// Research output is deliberately separate from clinical decision support.
/// Legacy fields remain readable for saved-record and caller compatibility.
class OfflineRiskPrediction {
  const OfflineRiskPrediction({
    required this.modelName,
    required this.usingModel,
    required this.riskProbability,
    required this.classification,
    required this.featuresUsed,
    required this.featuresMissing,
    required this.predictedAt,
    this.modelVersion,
    this.inferenceMs,
    this.driftDetected = false,
    this.driftFeatures = const [],
    this.confidenceInterval95,
    this.conformalQ95,
    this.ruleInCandidate = false,
    this.ruleInThreshold,
    this.featureValues = const {},
    this.researchOutput,
    this.rawNeuralOutput,
    this.patientOutputAllowed = false,
    this.outputScope,
    this.artifactSha256,
    this.inputPolicyVersion,
    this.runtimeVerified = false,
    this.observedValues = const {},
    this.featureUnits = const {},
    this.fixedFeatures = const {},
    this.postprocessing = const {},
    this.sensitivities = const [],
    this.sensitivityStatus = ModelSensitivityStatus.notRun,
    this.execution = ModelExecution.notRun,
    this.applicability = ModelApplicability.unknownCohort,
    this.inputQuality = ModelInputQuality.missingObservations,
    this.evidence = ModelEvidence.unknown,
    this.unsupportedFeatures = const [],
    this.imputedFeatures = const [],
    this.invalidFeatures = const [],
    this.statusReason =
        'Research only; clinical guidance uses observed findings.',
  });

  final String modelName;
  final bool usingModel;
  final double? riskProbability;
  final String classification;
  final List<String> featuresUsed;
  final List<String> featuresMissing;
  final DateTime predictedAt;
  final String? modelVersion;
  final int? inferenceMs;
  final bool driftDetected;
  final List<String> driftFeatures;
  final ({double low, double high})? confidenceInterval95;
  final double? conformalQ95;
  final bool ruleInCandidate;
  final double? ruleInThreshold;
  final Map<String, double> featureValues;
  final double? researchOutput;
  final double? rawNeuralOutput;
  final bool patientOutputAllowed;
  final String? outputScope;
  final String? artifactSha256;
  final String? inputPolicyVersion;
  final bool runtimeVerified;
  final Map<String, double> observedValues;
  final Map<String, String> featureUnits;
  final Map<String, String> fixedFeatures;
  final Map<String, Object?> postprocessing;
  final List<ModelFeatureSensitivity> sensitivities;
  final ModelSensitivityStatus sensitivityStatus;

  bool get mayDisplayExperimentalOutput =>
      runtimeVerified &&
      patientOutputAllowed &&
      outputScope == 'clinician_experimental' &&
      modelName == 'neonatal_sepsis' &&
      evidence == ModelEvidence.legacyRealData &&
      artifactSha256 == OfflineInferenceService.neonatalArtifact &&
      inputPolicyVersion == OfflineInferenceService.neonatalPolicy &&
      execution == ModelExecution.completed &&
      usingModel &&
      applicability == ModelApplicability.applicable &&
      inputQuality == ModelInputQuality.complete &&
      !driftDetected &&
      featuresMissing.isEmpty &&
      invalidFeatures.isEmpty &&
      rawNeuralOutput != null &&
      rawNeuralOutput!.isFinite &&
      rawNeuralOutput! >= 0 &&
      rawNeuralOutput! <= 1 &&
      researchOutput != null &&
      researchOutput!.isFinite &&
      researchOutput! >= 0 &&
      researchOutput! <= 1;
  final ModelExecution execution;
  final ModelApplicability applicability;
  final ModelInputQuality inputQuality;
  final ModelEvidence evidence;
  final List<String> unsupportedFeatures;
  final List<String> imputedFeatures;
  final List<String> invalidFeatures;
  final String statusReason;

  /// No model in this release has clinical deployment authorization.
  /// This is intentionally not controlled by a metadata flag or UI setting.
  bool get clinicallyActionable => false;

  Map<String, Object?> toMap() => {
    'snapshot_version': 2,
    'experimental_raw_output': rawNeuralOutput,
    'experimental_adjusted_output': researchOutput,
    'patient_output_allowed': patientOutputAllowed,
    'output_scope': outputScope,
    'clinical_use_allowed': false,
    'artifact_sha256': artifactSha256,
    'input_policy_version': inputPolicyVersion,
    'runtime_verified': runtimeVerified,
    'observed_values': Map<String, double>.from(observedValues),
    'normalized_observations': Map<String, double>.from(featureValues),
    'feature_units': Map<String, String>.from(featureUnits),
    'fixed_features': Map<String, String>.from(fixedFeatures),
    'postprocessing': Map<String, Object?>.from(postprocessing),
    'sensitivities': sensitivities.map((s) => s.toMap()).toList(),
    'sensitivity_status': sensitivityStatus.name,
    'unsupported_features': List<String>.from(unsupportedFeatures),
    'invalid_features': List<String>.from(invalidFeatures),
    'imputed_features': List<String>.from(imputedFeatures),
    'model_name': modelName,
    'using_model': usingModel ? 1 : 0,
    'risk_probability': null,
    'classification': 'unavailable',
    'features_used': featuresUsed.join(','),
    'features_missing': featuresMissing.join(','),
    'predicted_at': predictedAt.toIso8601String(),
    'model_version': modelVersion,
    'inference_ms': inferenceMs,
    'drift_detected': driftDetected ? 1 : 0,
    'drift_features': driftFeatures.join(','),
    'rule_in_candidate': 0,
    'rule_in_threshold': null,
    'execution': execution.name,
    'applicability': applicability.name,
    'input_quality': inputQuality.name,
    'evidence': evidence.name,
    'status_reason': statusReason,
  };
}
