import 'package:flutter/material.dart';
import '../../core/ml/offline_inference_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/glass.dart';
import '../../core/theme/motion.dart';
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
    this.flat = false,
  });
  final String classification, rationale;
  final TriageLevel level;
  final int missingCount;
  final VoidCallback onNext;
  final Widget? audio, overrideNote;

  /// No frame of its own: the caller supplies the surface (the glass hero
  /// on the verdict page) and the triage colour stays on the icon and text.
  final bool flat;

  Gradient get _gradient => switch (level) {
    TriageLevel.urgent => const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFDC2626), Color(0xFF991B1B), Color(0xFF7F1D1D)],
      stops: [0.0, 0.55, 1.0],
    ),
    TriageLevel.priority => const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFF59E0B), Color(0xFFD97706), Color(0xFFB45309)],
      stops: [0.0, 0.55, 1.0],
    ),
    TriageLevel.watch => const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFBBF24), Color(0xFFF59E0B), Color(0xFFD97706)],
      stops: [0.0, 0.55, 1.0],
    ),
    TriageLevel.routine => const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF10B981), Color(0xFF059669), Color(0xFF047857)],
      stops: [0.0, 0.55, 1.0],
    ),
  };

  String get _confidenceLabel => switch (missingCount) {
    0 => 'Full data confidence',
    1 => '1 observation needs review',
    _ => '$missingCount observations need review',
  };

  double get _confidenceFraction => missingCount == 0
      ? 1.0
      : missingCount <= 2
          ? 0.66
          : 0.33;

  @override
  Widget build(BuildContext context) {
    if (flat) {
      return _flatContent();
    }
    return Container(
      decoration: BoxDecoration(
        gradient: _gradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: _shadowColor,
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -20,
            top: -20,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Positioned(
            left: -30,
            bottom: -30,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.04),
              ),
            ),
          ),
          _flatContent(),
        ],
      ),
    );
  }

  Color get _shadowColor => switch (level) {
    TriageLevel.urgent => const Color(0xFFDC2626).withValues(alpha: 0.25),
    TriageLevel.priority => const Color(0xFFF59E0B).withValues(alpha: 0.25),
    TriageLevel.watch => const Color(0xFFFBBF24).withValues(alpha: 0.2),
    TriageLevel.routine => const Color(0xFF10B981).withValues(alpha: 0.25),
  };

  Widget _flatContent() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Flexible so a long level label can wrap instead of pushing
              // the row past narrow viewports at large text scales.
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: flat
                        ? triageColours(level).bg
                        : Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        level == TriageLevel.urgent
                            ? Icons.warning_amber_rounded
                            : Icons.fact_check_outlined,
                        color: flat ? triageColours(level).fg : Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          level.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: flat
                                ? triageColours(level).fg
                                : Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (audio != null) ...[
                const Spacer(),
                if (flat)
                  audio!
                else
                  _TintedAudio(audio: audio!),
              ],
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'PROTOCOL DECISION',
            style: TextStyle(
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
              fontSize: 11,
              color: flat ? AppColors.inkMuted : Colors.white.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            classification,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.25,
              color: flat ? AppColors.ink : Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            rationale,
            style: TextStyle(
              fontSize: 14.5,
              height: 1.5,
              color: flat
                  ? AppColors.inkMuted
                  : Colors.white.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: flat
                  ? AppColors.surfaceTint.withValues(alpha: 0.3)
                  : Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  height: 36,
                  child: CustomPaint(
                    painter: _ConfidenceRing(
                      fraction: _confidenceFraction,
                      ringColor: flat
                          ? triageColours(level).fg
                          : Colors.white,
                      trackColor: flat
                          ? AppColors.line
                          : Colors.white.withValues(alpha: 0.15),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _confidenceLabel,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: flat
                          ? AppColors.ink
                          : Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (overrideNote != null) ...[
            const SizedBox(height: 12),
            overrideNote!,
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: onNext,
              style: FilledButton.styleFrom(
                backgroundColor: flat
                    ? AppColors.primary
                    : Colors.white,
                foregroundColor: flat
                    ? Colors.white
                    : switch (level) {
                        TriageLevel.urgent => const Color(0xFF7F1D1D),
                        TriageLevel.priority => const Color(0xFFB45309),
                        TriageLevel.watch => const Color(0xFFB45309),
                        TriageLevel.routine => const Color(0xFF047857),
                      },
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.medical_services_outlined, size: 20),
              label: const Text(
                'Open care plan',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TintedAudio extends StatelessWidget {
  const _TintedAudio({required this.audio});
  final Widget audio;
  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(
      iconTheme: const IconThemeData(color: Colors.white),
    ),
    child: audio,
  );
}

class _ConfidenceRing extends CustomPainter {
  _ConfidenceRing({
    required this.fraction,
    required this.ringColor,
    required this.trackColor,
  });
  final double fraction;
  final Color ringColor;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 3;
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);

    final ringPaint = Paint()
      ..color = ringColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -3.14159 / 2,
      2 * 3.14159 * fraction,
      false,
      ringPaint,
    );
  }

  @override
  bool shouldRepaint(_ConfidenceRing old) => old.fraction != fraction;
}

/// Nurse-only evidence. Never included in caregiver care plans.
///
/// Modernised: skeleton loaders during async fetch, a modern expandable card
/// instead of ExpansionTile, and a visual risk gauge for the 0-1 output.
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
  Widget build(BuildContext context) => Padding(
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
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.science_outlined,
                  size: 18,
                  color: AppColors.primaryDeep,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'RESEARCH ANALYSIS',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: AppColors.inkMuted,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Experimental model evidence',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
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
              color: AppColors.surfaceTint.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(Gap.radiusSm),
            ),
            child: const Text(
              'Clinical guidance uses observed findings and protocol rules. '
              'Experimental models do not change treatment or referral.',
              style: TextStyle(fontSize: 12.5, height: 1.5, color: AppColors.inkMuted),
            ),
          ),
          FutureBuilder<Map<String, OfflineRiskPrediction>>(
            future: predictions,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _AnalysisError(
                  message: 'Analysis unavailable. Clinical guidance remains available offline.',
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
                          message: 'Evidence metadata unavailable. No experimental output is shown.',
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
                              side: const BorderSide(color: AppColors.primary),
                              foregroundColor: AppColors.primaryDeep,
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
  const _AnalysisError({required this.message, this.icon = Icons.error_outline_rounded});

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Gap.md),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.inkMuted),
        const SizedBox(width: Gap.sm),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.inkMuted,
              height: 1.5,
            ),
          ),
        ),
      ],
    ),
  );
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
    final p = widget.model.prediction;
    final c = widget.status?.contract ?? const <String, Object?>{};
    final usable = widget.status?.isModelUsable == true;
    final showGauge = widget.model.mayShowOutput &&
        usable &&
        widget.status?.modelVersion == p.modelVersion &&
        c['patient_output_allowed'] == true;

    return Container(
      margin: const EdgeInsets.only(top: Gap.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Gap.radius),
        border: Border.all(color: AppColors.line, width: Gap.hairline),
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
                          color: usable ? AppColors.triageGreen : AppColors.inkFaint,
                        ),
                      ),
                      const SizedBox(width: Gap.sm),
                      Expanded(
                        child: Text(
                          widget.model.title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      if (widget.expandedAvailable)
                        RotationTransition(
                          turns: Tween(begin: 0.0, end: 0.5).animate(_anim),
                          child: const Icon(
                            Icons.expand_more_rounded,
                            size: 20,
                            color: AppColors.inkMuted,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.model.status,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.inkMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (showGauge) ...[
                    const SizedBox(height: Gap.sm),
                    _RiskGauge(value: p.researchOutput!),
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
                    child: _EvidenceDetail(model: widget.model, status: widget.status),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// Visual gauge for the 0-1 research output.
class _RiskGauge extends StatelessWidget {
  const _RiskGauge({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final pct = (value * 100).round();
    final color = value >= 0.7
        ? AppColors.triageRed
        : value >= 0.4
            ? AppColors.triageAmber
            : AppColors.triageGreen;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Research output',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: AppColors.inkMuted,
                letterSpacing: 0.3,
              ),
            ),
            const Spacer(),
            Text(
              '$pct%',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 6,
            backgroundColor: AppColors.surfaceTint,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          '0–1 scale — experimental, not a diagnosis',
          style: TextStyle(
            fontSize: 10,
            color: AppColors.inkFaint,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
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
          const Divider(height: 1, thickness: 1, color: AppColors.line),
          const SizedBox(height: Gap.md),
          const Text(
            'Experimental model output — not a diagnosis or treatment threshold.',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppColors.inkMuted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: Gap.md),
          _DetailRow(label: 'Model version', value: p.modelVersion ?? 'Unavailable'),
          _DetailRow(
            label: 'File integrity',
            value: status?.integrityVerified == true
                ? 'Checked'
                : 'Not checked',
          ),
          _DetailRow(label: 'Dataset', value: c['dataset']?.toString() ?? 'Not documented'),
          _DetailRow(
            label: 'Dataset outcome',
            value: c['outcome']?.toString() ?? 'Not documented',
          ),
          _DetailRow(
            label: 'Supported population',
            value: '${c['cohort'] ?? 'Not documented'}'
                '${c['age_days_support'] == null ? '' : ' · age in days ${c['age_days_support']}'}',
          ),
          _DetailRow(label: 'Observed predictors', value: names(p.featuresUsed)),
          _DetailRow(label: 'Missing predictors', value: names(p.featuresMissing)),
          _DetailRow(label: 'Imputed predictors', value: names(p.imputedFeatures)),
          _DetailRow(label: 'Unsupported predictors', value: names(p.unsupportedFeatures)),
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
          const Text(
            'Repository datasets have been explored previously. Retrospective results do not establish clinical readiness in Northern Ghana.',
            style: TextStyle(fontSize: 11.5, height: 1.5, color: AppColors.inkMuted),
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label  ',
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppColors.inkMuted,
            ),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.ink,
              height: 1.4,
            ),
          ),
        ],
      ),
    ),
  );
}
