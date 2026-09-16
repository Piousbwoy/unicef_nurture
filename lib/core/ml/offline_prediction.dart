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
