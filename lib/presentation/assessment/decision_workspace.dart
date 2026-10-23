import 'package:flutter/material.dart';
import '../../core/ml/offline_inference_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/glass.dart';
import '../../core/theme/motion.dart';
import '../../domain/enums.dart';
import 'types.dart';

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
  bool get mayShowOutput => prediction.mayDisplayExperimentalOutput;
}

/// A single clinical decision. Color belongs to urgency, never a model score.
class ClinicalDecisionHeader extends StatelessWidget {
  const ClinicalDecisionHeader({
    super.key,
    required this.classification,
    required this.level,
    required this.missingCount,
    required this.rationale,
    this.audio,
    this.overrideNote,
    this.evidence,
    this.completeness,
    this.flat = false,
  });
  final String classification, rationale;
  final TriageLevel level;
  final int missingCount;
  final Widget? audio, overrideNote, evidence;
  final ObservationCompleteness? completeness;
  final bool flat;

  @override
  Widget build(BuildContext context) {
    final p = ClinicalPaletteScope.of(context);
    final urgent = level == TriageLevel.urgent;
    final watch = level == TriageLevel.watch || level == TriageLevel.priority;
    final tone = urgent
        ? p.triageRed
        : watch
        ? p.triageAmber
        : p.triageGreen;
    final wash = urgent
        ? p.triageRedBg
        : watch
        ? p.triageAmberBg
        : p.triageGreenBg;
    final content = Padding(
      padding: const EdgeInsets.all(Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'PROTOCOL DECISION',
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w700,
                    color: p.inkMuted,
                  ),
                ),
              ),
              ?audio,
            ],
          ),
          const SizedBox(height: Gap.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: wash,
              borderRadius: BorderRadius.circular(Gap.radiusXs),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  urgent
                      ? Icons.warning_amber_rounded
                      : Icons.fact_check_outlined,
                  color: tone,
                  size: 20,
                ),
                const SizedBox(width: Gap.sm),
                Flexible(
                  child: Text(
                    level.label,
                    style: TextStyle(
                      color: p.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.md),
          Semantics(
            header: true,
            child: Text(
              classification,
              style: TextStyle(
                fontFamily: 'Sora',
                fontSize: 22,
                fontWeight: FontWeight.w600,
                height: 1.3,
                color: p.ink,
              ),
            ),
          ),
          const SizedBox(height: Gap.sm),
          if (evidence != null)
            evidence!
          else
            Text(
              rationale,
              style: TextStyle(fontSize: 15, height: 1.5, color: p.inkMuted),
            ),
          if (completeness != null) ...[
            const SizedBox(height: Gap.md),
            ObservationCompletenessView(summary: completeness!),
          ] else if (missingCount > 0) ...[
            const SizedBox(height: Gap.sm),
            Text(
              '$missingCount observations need review',
              style: TextStyle(color: p.inkMuted),
            ),
          ],
          if (overrideNote != null) ...[
            const SizedBox(height: Gap.md),
            overrideNote!,
          ],
        ],
      ),
    );
    if (flat) return content;
    return Container(
      decoration: BoxDecoration(
        color: p.surfaceSolid,
        borderRadius: BorderRadius.circular(Gap.radius),
        border: Border.all(color: p.line),
        boxShadow: const [AppShadows.card],
      ),
      child: Material(type: MaterialType.transparency, child: content),
    );
  }
}

/// A transparent denominator and named gaps, with no diagnostic interpretation.
class ObservationCompletenessView extends StatelessWidget {
  const ObservationCompletenessView({super.key, required this.summary});
  final ObservationCompleteness summary;

  @override
  Widget build(BuildContext context) {
    final p = ClinicalPaletteScope.of(context);
    final missing = summary.labelsFor(ObservationState.missing);
    final review = summary.labelsFor(ObservationState.needsReview);
    return Material(
      color: p.primaryLight,
      borderRadius: BorderRadius.circular(Gap.radiusSm),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    'Observation completeness',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: p.ink,
                    ),
                  ),
                ),
                const SizedBox(width: Gap.sm),
                Text(
                  summary.percent == null ? '—' : '${summary.percent}%',
                  style: TextStyle(
                    fontFamily: 'Sora',
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: p.ink,
                  ),
                ),
              ],
            ),
            Text(
              summary.unavailableReason ??
                  '${summary.recorded} of ${summary.total} core measurements '
                      'recorded · not diagnostic confidence',
              style: TextStyle(fontSize: 12, height: 1.5, color: p.inkMuted),
            ),
            if (missing.isNotEmpty)
              Text(
                'Not recorded: ${missing.join(', ')}',
                style: TextStyle(fontSize: 13, height: 1.5, color: p.ink),
              ),
            if (review.isNotEmpty)
              Text(
                'Review: ${review.join(', ')}',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: p.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Every core measurement and the state it earned, for the clinical dossier.
class ObservationCoverageLedger extends StatelessWidget {
  const ObservationCoverageLedger({super.key, required this.summary});
  final ObservationCompleteness summary;

  @override
  Widget build(BuildContext context) {
    final p = ClinicalPaletteScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in summary.checks.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  entry.value == ObservationState.recorded
                      ? Icons.check_circle_outline
                      : Icons.info_outline,
                  size: 18,
                  color: p.inkMuted,
                ),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text(
                    '${entry.key} — ${switch (entry.value) {
                      ObservationState.recorded => 'recorded, within plausibility limits',
                      ObservationState.missing => 'not recorded',
                      ObservationState.needsReview => 'needs review, excluded from the score',
                    }}',
                    style: TextStyle(fontSize: 13, height: 1.5, color: p.ink),
                  ),
                ),
              ],
            ),
          ),
        Text(
          'Presence and basic plausibility only — not measurement accuracy. '
          'Symptoms, history and other protocol gaps are not in this count.',
          style: TextStyle(fontSize: 12, height: 1.5, color: p.inkMuted),
        ),
      ],
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
  Widget build(BuildContext context) {
    final p = ClinicalPaletteScope.of(context);
    return Padding(
      // Neutral glass: research output carries no tone colour, ever.
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: GlassSurface(
        blur: false,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: p.primaryLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.science_outlined,
                    size: 18,
                    color: p.primaryDark,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'RESEARCH ANALYSIS',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: p.inkMuted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Experimental model evidence',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: p.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: p.surfaceTint.withValues(alpha: p.isDark ? 0.5 : 0.3),
                borderRadius: BorderRadius.circular(Gap.radiusSm),
              ),
              child: Text(
                'Clinical guidance uses observed findings and protocol rules. '
                'Experimental models do not change treatment or referral.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: p.inkMuted,
                ),
              ),
            ),
            FutureBuilder<Map<String, OfflineRiskPrediction>>(
              future: predictions,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _AnalysisError(
                    message:
                        'Analysis unavailable. Clinical guidance remains available offline.',
                  );
                }
                if (!snapshot.hasData) {
                  return const _AnalysisSkeleton();
                }
                final values = snapshot.data!.values.toList();
                if (values.isEmpty) {
                  return _AnalysisError(
                    message: 'No research model supports this assessment type.',
                    icon: Icons.info_outline_rounded,
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
                          _AnalysisError(
                            message:
                                'Evidence metadata unavailable. No experimental output is shown.',
                          )
                        else if (statusSnapshot.connectionState !=
                            ConnectionState.done)
                          const _AnalysisSkeleton(),
                        // Always show the model cards, even when statuses are loading or failed
                        for (final prediction in values)
                          _ModelEvidenceCard(
                            model: AnalysisViewModel(prediction),
                            status: byName[prediction.modelName],
                            expandedAvailable: showEvidence,
                          ),
                        if (values.any(
                          (p) =>
                              p.featuresMissing.isNotEmpty ||
                              p.invalidFeatures.isNotEmpty,
                        ))
                          Padding(
                            padding: const EdgeInsets.only(top: Gap.md),
                            child: OutlinedButton.icon(
                              onPressed: onEdit,
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(48, 44),
                                side: BorderSide(color: p.primary),
                                foregroundColor: p.primaryDark,
                              ),
                              icon: const Icon(Icons.edit_outlined, size: 16),
                              label: const Text('Review assessment inputs'),
                            ),
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
}

/// Skeleton placeholder shown while model predictions are loading.
class _AnalysisSkeleton extends StatelessWidget {
  const _AnalysisSkeleton();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Gap.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Shimmer(width: 140, height: 14, radius: 4),
        const SizedBox(height: Gap.sm),
        Shimmer(width: double.infinity, height: 60, radius: Gap.radiusSm),
        const SizedBox(height: Gap.md),
        const Shimmer(width: 180, height: 14, radius: 4),
        const SizedBox(height: Gap.sm),
        Shimmer(width: double.infinity, height: 80, radius: Gap.radiusSm),
      ],
    ),
  );
}

/// Error state with icon and muted styling.
class _AnalysisError extends StatelessWidget {
  const _AnalysisError({
    required this.message,
    this.icon = Icons.error_outline_rounded,
  });

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final p = ClinicalPaletteScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Gap.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: p.inkMuted),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12.5, color: p.inkMuted, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// A modern expandable card for model evidence. Replaces ExpansionTile with
/// a custom animated expansion and a visual risk gauge for the 0-1 output.
class _ModelEvidenceCard extends StatefulWidget {
  const _ModelEvidenceCard({
    required this.model,
    required this.status,
    required this.expandedAvailable,
  });

  final AnalysisViewModel model;
  final OfflineModelStatus? status;
  final bool expandedAvailable;

  @override
  State<_ModelEvidenceCard> createState() => _ModelEvidenceCardState();
}

class _ModelEvidenceCardState extends State<_ModelEvidenceCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      if (_expanded) {
        _anim.forward();
      } else {
        _anim.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final pal = ClinicalPaletteScope.of(context);
    final p = widget.model.prediction;
    final c = widget.status?.contract ?? const <String, Object?>{};
    final usable = widget.status?.isModelUsable == true;
    final showGauge =
        widget.model.mayShowOutput &&
        usable &&
        widget.status?.modelVersion == p.modelVersion &&
        c['patient_output_allowed'] == true;

    return Container(
      margin: const EdgeInsets.only(top: Gap.md),
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(Gap.radius),
        border: Border.all(color: pal.line, width: Gap.hairline),
        boxShadow: const [AppShadows.card],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header — tappable to expand
          InkWell(
            onTap: widget.expandedAvailable ? _toggle : null,
            borderRadius: BorderRadius.circular(Gap.radius),
            child: Padding(
              padding: const EdgeInsets.all(Gap.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: usable ? pal.triageGreen : pal.inkFaint,
                        ),
                      ),
                      const SizedBox(width: Gap.sm),
                      Expanded(
                        child: Text(
                          widget.model.title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: pal.ink,
                          ),
                        ),
                      ),
                      if (widget.expandedAvailable)
                        RotationTransition(
                          turns: Tween(begin: 0.0, end: 0.5).animate(_anim),
                          child: Icon(
                            Icons.expand_more_rounded,
                            size: 20,
                            color: pal.inkMuted,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.model.status,
                    style: TextStyle(
                      fontSize: 12,
                      color: pal.inkMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (showGauge) ...[
                    const SizedBox(height: Gap.sm),
                    const Text('Experimental model score'),
                    Text('${(100 * p.researchOutput!).toStringAsFixed(1)}/100'),
                    LinearProgressIndicator(
                      value: p.researchOutput!,
                      semanticsLabel: 'Experimental model score',
                      semanticsValue: (100 * p.researchOutput!).toStringAsFixed(
                        1,
                      ),
                    ),
                    const Text(
                      'Not a calibrated clinical risk estimate. Clinician review required.',
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Expandable detail
          if (widget.expandedAvailable)
            AnimatedBuilder(
              animation: _anim,
              builder: (context, _) {
                if (_anim.isDismissed) return const SizedBox.shrink();
                return ClipRect(
                  child: SizeTransition(
                    sizeFactor: _anim,
                    alignment: Alignment.topLeft,
                    child: _EvidenceDetail(
                      model: widget.model,
                      status: widget.status,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// Expanded detail content for a model evidence card.
class _EvidenceDetail extends StatelessWidget {
  const _EvidenceDetail({required this.model, required this.status});

  final AnalysisViewModel model;
  final OfflineModelStatus? status;

  @override
  Widget build(BuildContext context) {
    final pal = ClinicalPaletteScope.of(context);
    final p = model.prediction;
    final c = status?.contract ?? const <String, Object?>{};
    String names(List<String> values) => values.isEmpty
        ? 'None'
        : values.map((e) => e.replaceAll('_', ' ')).join(', ');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(height: 1, thickness: 1, color: pal.line),
          const SizedBox(height: Gap.md),
          Text(
            'Experimental model output — not a diagnosis or treatment threshold.',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: pal.inkMuted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: Gap.md),
          _DetailRow(
            label: 'Model version',
            value: p.modelVersion ?? 'Unavailable',
          ),
          _DetailRow(
            label: 'File integrity',
            value: status?.integrityVerified == true
                ? 'Checked'
                : 'Not checked',
          ),
          _DetailRow(
            label: 'Dataset',
            value: c['dataset']?.toString() ?? 'Not documented',
          ),
          _DetailRow(
            label: 'Dataset outcome',
            value: c['outcome']?.toString() ?? 'Not documented',
          ),
          _DetailRow(
            label: 'Supported population',
            value:
                '${c['cohort'] ?? 'Not documented'}'
                '${c['age_days_support'] == null ? '' : ' · age in days ${c['age_days_support']}'}',
          ),
          _DetailRow(
            label: 'Observed predictors',
            value: names(p.featuresUsed),
          ),
          _DetailRow(
            label: 'Missing predictors',
            value: names(p.featuresMissing),
          ),
          _DetailRow(
            label: 'Imputed predictors',
            value: names(p.imputedFeatures),
          ),
          _DetailRow(
            label: 'Unsupported predictors',
            value: names(p.unsupportedFeatures),
          ),
          _DetailRow(
            label: 'Input support warnings',
            value: names({...p.invalidFeatures, ...p.driftFeatures}.toList()),
          ),
          _DetailRow(
            label: 'Exported-model evaluation',
            value: status?.headlineValidation.isNotEmpty == true
                ? status!.headlineValidation.entries
                      .map((e) => '${e.key}: ${e.value}')
                      .join('\n')
                : 'No validated exported-model evaluation is attached to this artifact.',
          ),
          for (final limitation
              in c['limitations'] is List ? c['limitations'] as List : const [])
            _DetailRow(label: 'Limitation', value: limitation.toString()),
          const SizedBox(height: Gap.sm),
          Text(
            'Repository datasets have been explored previously. Retrospective results do not establish clinical readiness in Northern Ghana.',
            style: TextStyle(fontSize: 11.5, height: 1.5, color: pal.inkMuted),
          ),
        ],
      ),
    );
  }
}

/// A single label-value row in the evidence detail.
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final p = ClinicalPaletteScope.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label  ',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: p.inkMuted,
              ),
            ),
            TextSpan(
              text: value,
              style: TextStyle(fontSize: 11.5, color: p.ink, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
