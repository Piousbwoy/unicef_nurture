import 'package:flutter/material.dart';
import '../../core/ml/offline_inference_service.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/enums.dart';
import '../shared/ui.dart';

/// Presentation decisions are independent of clinical triage and referral state.
class AnalysisViewModel {
  const AnalysisViewModel(this.prediction);
  final OfflineRiskPrediction prediction;
  String get title => switch (prediction.modelName) {
    'neonatal_sepsis' => 'Neonatal sepsis research',
    'child_pneumonia' => 'Child pneumonia artifact',
    'preeclampsia_risk' => 'Preeclampsia research',
    'lbw_sga' => 'Birth-weight research (not SGA)',
    _ => prediction.modelName,
  };
  String get status => switch (prediction.execution) {
    ModelExecution.integrityFailure => 'Integrity failure',
    ModelExecution.invalidMetadata => 'Invalid metadata',
    ModelExecution.failed => 'Execution failure',
    ModelExecution.unavailable => 'Model unavailable',
    _ =>
      prediction.applicability != ModelApplicability.applicable
          ? 'Unsupported or unknown cohort'
          : switch (prediction.inputQuality) {
              ModelInputQuality.missingObservations => 'Missing observations',
              ModelInputQuality.invalidValues => 'Review measurements',
              ModelInputQuality.outsideSupport => 'Outside model support',
              _ => 'Research only',
            },
  };
  bool get mayShowOutput =>
      prediction.evidence == ModelEvidence.retrospectiveResearch &&
      prediction.execution == ModelExecution.completed &&
      prediction.applicability == ModelApplicability.applicable &&
      prediction.inputQuality == ModelInputQuality.complete &&
      prediction.researchOutput?.isFinite == true &&
      prediction.researchOutput! >= 0 &&
      prediction.researchOutput! <= 1;
}

class ClinicalDecisionHeader extends StatelessWidget {
  const ClinicalDecisionHeader({
    super.key,
    required this.classification,
    required this.level,
    required this.missingCount,
    required this.rationale,
    required this.onNext,
    this.audio,
    this.overrideNote,
  });
  final String classification, rationale;
  final TriageLevel level;
  final int missingCount;
  final VoidCallback onNext;
  final Widget? audio, overrideNote;

  @override
  Widget build(BuildContext context) {
    final colors = triageColours(level);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.fg, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(
                level == TriageLevel.urgent
                    ? Icons.warning_amber_rounded
                    : Icons.fact_check_outlined,
                color: colors.fg,
                size: 28,
              ),
              Text(
                level.label,
                style: TextStyle(
                  color: colors.fg,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              ?audio,
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'PROTOCOL DECISION',
            style: TextStyle(
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            classification,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 12),
          Text(rationale, style: const TextStyle(fontSize: 16, height: 1.5)),
          const Divider(height: 32),
          Text(
            missingCount == 0
                ? 'Input completeness: no gaps reported by the protocol.'
                : 'Input completeness: $missingCount observations need review.',
            style: const TextStyle(fontSize: 14, color: AppColors.inkMuted),
          ),
          if (overrideNote != null) ...[
            const SizedBox(height: 12),
            overrideNote!,
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onNext,
            style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
            icon: const Icon(Icons.checklist_rounded),
            label: const Text('Open action worklist'),
          ),
        ],
      ),
    );
  }
}

/// Nurse-only evidence. Never included in caregiver care plans.
class ResearchAnalysisPanel extends StatelessWidget {
  const ResearchAnalysisPanel({
    super.key,
    required this.predictions,
    required this.statuses,
    required this.onEdit,
    this.showEvidence = false,
  });
  final Future<Map<String, OfflineRiskPrediction>> predictions;
  final Future<List<OfflineModelStatus>> statuses;
  final VoidCallback onEdit;
  final bool showEvidence;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.symmetric(vertical: 16),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.science_outlined),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Analysis status',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Clinical guidance uses observed findings and protocol rules. '
            'Experimental models do not change treatment or referral.',
            style: TextStyle(fontSize: 14, height: 1.5),
          ),
          FutureBuilder<Map<String, OfflineRiskPrediction>>(
            future: predictions,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'Analysis unavailable. Clinical guidance remains available offline.',
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'Checking local model evidence. You can continue clinical care.',
                  ),
                );
              }
              final values = snapshot.data!.values.toList();
              if (values.isEmpty) {
                return const Text(
                  'No research model supports this assessment type.',
                );
              }
              return FutureBuilder<List<OfflineModelStatus>>(
                future: statuses,
                builder: (context, statusSnapshot) {
                  final byName = {
                    for (final s
                        in statusSnapshot.data ?? <OfflineModelStatus>[])
                      s.name: s,
                  };
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (statusSnapshot.hasError)
                        const Text(
                          'Evidence metadata unavailable. No experimental output is shown.',
                        )
                      else if (statusSnapshot.connectionState !=
                          ConnectionState.done)
                        const Text('Checking local evidence metadata…'),
                      for (final prediction in values)
                        _ModelEvidence(
                          model: AnalysisViewModel(prediction),
                          status: byName[prediction.modelName],
                          expandedAvailable: showEvidence,
                        ),
                      if (values.any(
                        (p) =>
                            p.featuresMissing.isNotEmpty ||
                            p.invalidFeatures.isNotEmpty,
                      ))
                        TextButton.icon(
                          onPressed: onEdit,
                          style: TextButton.styleFrom(
                            minimumSize: const Size(48, 48),
                          ),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Review assessment inputs'),
                        ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    ),
  );
}

class _ModelEvidence extends StatelessWidget {
  const _ModelEvidence({
    required this.model,
    required this.status,
    required this.expandedAvailable,
  });
  final AnalysisViewModel model;
  final OfflineModelStatus? status;
  final bool expandedAvailable;

  @override
  Widget build(BuildContext context) {
    final p = model.prediction;
    final c = status?.contract ?? const <String, Object?>{};
    final heading = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            model.title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            model.status,
            style: const TextStyle(fontSize: 14, color: AppColors.inkMuted),
          ),
          if (expandedAvailable) ...[
            const SizedBox(height: 4),
            Text(p.statusReason, style: const TextStyle(height: 1.4)),
          ],
        ],
      ),
    );
    if (!expandedAvailable) {
      return heading;
    }
    String names(List<String> values) => values.isEmpty
        ? 'None'
        : values.map((e) => e.replaceAll('_', ' ')).join(', ');
    return ExpansionTile(
      key: PageStorageKey('research-${p.modelName}'),
      tilePadding: EdgeInsets.zero,
      title: heading,
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      childrenPadding: const EdgeInsets.only(bottom: 20),
      children: [
        const Text(
          'Experimental model output — not a diagnosis or treatment threshold.',
          style: TextStyle(fontWeight: FontWeight.w700, height: 1.5),
        ),
        if (model.mayShowOutput &&
            status?.isModelUsable == true &&
            status?.modelVersion == p.modelVersion &&
            c['patient_output_allowed'] == true) ...[
          const Text('Research output (0–1 scale)'),
          Text(
            p.researchOutput!.toStringAsFixed(3),
            style: const TextStyle(fontSize: 24),
          ),
        ],
        _detail('Model version', p.modelVersion ?? 'Unavailable'),
        _detail(
          'File integrity',
          status?.integrityVerified == true
              ? 'File integrity checked'
              : 'Not checked',
        ),
        _detail('Dataset', c['dataset']?.toString() ?? 'Not documented'),
        _detail(
          'Dataset outcome',
          c['outcome']?.toString() ?? 'Not documented',
        ),
        _detail(
          'Supported population',
          '${c['cohort'] ?? 'Not documented'}${c['age_days_support'] == null ? '' : ' · age in days ${c['age_days_support']}'}',
        ),
        _detail('Observed predictors', names(p.featuresUsed)),
        _detail('Missing predictors', names(p.featuresMissing)),
        _detail('Imputed predictors', names(p.imputedFeatures)),
        _detail('Unsupported predictors', names(p.unsupportedFeatures)),
        _detail(
          'Input support warnings',
          names({...p.invalidFeatures, ...p.driftFeatures}.toList()),
        ),
        _detail(
          'Exported-model evaluation',
          status?.headlineValidation.isNotEmpty == true
              ? status!.headlineValidation.entries
                    .map((e) => '${e.key}: ${e.value}')
                    .join('\n')
              : 'No validated exported-model evaluation is attached to this artifact. Legacy teacher-only metrics are not its accuracy.',
        ),
        for (final limitation
            in c['limitations'] is List ? c['limitations'] as List : const [])
          _detail('Limitation', limitation.toString()),
        const Text(
          'Repository datasets have been explored previously. Retrospective results do not establish clinical readiness in Northern Ghana.',
          style: TextStyle(fontSize: 14, height: 1.5),
        ),
      ],
    );
  }

  Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label\n',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          TextSpan(text: value),
        ],
      ),
      style: const TextStyle(fontSize: 14, height: 1.5),
    ),
  );
}
