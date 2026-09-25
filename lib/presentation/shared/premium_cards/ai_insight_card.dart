/// AI Insight Card - Glassmorphism Design
///
/// Eligible experimental neural output, or an explicitly rule-based fallback.
/// Measured inputs, fixed training slots, and local replacement sensitivities
/// remain distinct. Neither variant claims a calibrated clinical probability.
///
/// The card explains and grades; the protocol verdict governs care. It
/// never issues treatment or referral instructions.
/// Part of the CareBridge Premium Design System.
library;

import 'package:flutter/material.dart';

import '../../../core/ml/clinical_reasoning_engine.dart';
import '../../../core/ml/offline_inference_service.dart';
import '../../../core/theme/glass.dart';
import '../../../core/theme/premium_design_tokens.dart';
import '../../assessment/widgets/cockpit_gauge.dart';

class AiInsightCard extends StatelessWidget {
  const AiInsightCard({
    super.key,
    required this.reasoning,
    this.onExplainTapped,
    this.pending = false,
    this.unavailableReason,
    this.animationDuration = PremiumDesignTokens.standardTransition,
  });

  final ClinicalReasoning reasoning;
  final bool pending;
  final String? unavailableReason;
  final VoidCallback? onExplainTapped;
  final Duration animationDuration;

  Widget _experimentalCard(
    BuildContext context,
    ExperimentalAssessment assessment,
  ) {
    final p = assessment.prediction;
    final score = assessment.scoreIndex;
    final colors = Theme.of(context).colorScheme;
    final color = score >= 70
        ? colors.error
        : score >= 40
        ? colors.onTertiaryContainer
        : score >= 15
        ? colors.tertiary
        : colors.primary;
    // The model-first hero: one circular gauge carries the number, one band
    // pill says what it means, one sentence tells the story. Everything that
    // evidences the figure — inputs, sensitivities, provenance — folds behind
    // a single honest question: "Why this score".
    return Semantics(
      container: true,
      child: GlassSurface(
        blur: false,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.memory_rounded, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'AI Assessment',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            CockpitGauge(
              value: p.researchOutput!,
              valueText: score.toStringAsFixed(1),
              label: 'Experimental model score',
              caption: '0–100 research index — not a clinical probability',
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    assessment.bandLabel,
                    style: PremiumDesignTokens.labelLarge.copyWith(
                      color: color,
                    ),
                  ),
                ),
                const _StatChip(label: '5/20 observed · 15 fixed'),
                _StatChip(label: p.modelVersion ?? 'Version unavailable'),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              assessment.narrative,
              style: PremiumDesignTokens.bodyMedium.copyWith(
                color: PremiumDesignTokens.neutral800,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              assessment.sensitivitySummary,
              style: PremiumDesignTokens.bodyMedium.copyWith(
                color: PremiumDesignTokens.neutral600,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Not a calibrated clinical risk estimate. Display bands are '
              'not clinical thresholds.',
              style: PremiumDesignTokens.labelMedium.copyWith(
                color: PremiumDesignTokens.neutral500,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 4),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: Text(
                'Why this score',
                style: PremiumDesignTokens.labelLarge.copyWith(
                  color: PremiumDesignTokens.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final entry in p.observedValues.entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          '${ExperimentalAssessment.featureLabel(entry.key)}: '
                          '${entry.value} ${p.featureUnits[entry.key] ?? ''}',
                          style: PremiumDesignTokens.bodyMedium.copyWith(
                            color: PremiumDesignTokens.neutral700,
                          ),
                        ),
                      ),
                    if (p.sensitivityStatus ==
                            ModelSensitivityStatus.completed &&
                        assessment.sensitivities.any(
                          (s) => s.scorePointDelta != 0,
                        )) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Local model sensitivities',
                        style: PremiumDesignTokens.headlineSmall.copyWith(
                          color: PremiumDesignTokens.neutral800,
                        ),
                      ),
                      const Text(
                        'One measured input replaced with its training mean; '
                        'not causal effects or treatment suggestions.',
                      ),
                      const SizedBox(height: 8),
                      for (final s in assessment.sensitivities.take(3))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '${ExperimentalAssessment.featureLabel(s.featureKey)} · '
                            '${s.rawValue} ${s.unit}\n'
                            '${s.scorePointDelta >= 0 ? '+' : ''}'
                            '${s.scorePointDelta.toStringAsFixed(2)} score points '
                            'against baseline ${s.baselineNormalized}',
                          ),
                        ),
                    ],
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text(
                        'Model provenance and limitations',
                      ),
                      children: [
                        Text(
                          'Raw neural output: ${p.rawNeuralOutput}\n'
                          'Adjusted experimental output: ${p.researchOutput}\n'
                          'Postprocessing: '
                          '${p.postprocessing['formula'] ?? 'sigmoid(A * logit(p) + B)'}\n'
                          'A = ${p.postprocessing['A']}; '
                          'B = ${p.postprocessing['B']}\n'
                          'Unvalidated legacy-teacher transform; not '
                          'validated for this neural artifact.\n'
                          'Current weight is an experimental proxy for '
                          'admission weight; measurement timing is '
                          'unverified.\n'
                          'Age support: 0–3 days.\n'
                          'Input policy: ${p.inputPolicyVersion}\n'
                          'Artifact SHA-256: ${p.artifactSha256}\n'
                          'Fixed normalized zeros: '
                          '${p.fixedFeatures.entries.map((e) => '${e.key}: ${e.value}').join('; ')}',
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'On-device neural model · Not a diagnosis · Clinician review '
              'required',
              style: PremiumDesignTokens.labelMedium.copyWith(
                color: PremiumDesignTokens.neutral500,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color get _indexColor {
    final v = reasoning.acuityIndex;
    if (v >= 65) return PremiumDesignTokens.urgent;
    if (v >= 40) return PremiumDesignTokens.watch;
    return PremiumDesignTokens.routine;
  }

  @override
  Widget build(BuildContext context) {
    final experimental = reasoning.experimentalAssessment;
    if (experimental != null) return _experimentalCard(context, experimental);
    final color = _indexColor;
    return GlassSurface(
      blur: false,
      padding: EdgeInsets.zero,
      child: Stack(
        children: [
          // Gradient overlay tinted by the index band.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [color.withValues(alpha: 0.08), Colors.transparent],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header row: identity + confidence badge ─────────────
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.psychology, color: color, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'AI Assessment',
                            style: PremiumDesignTokens.headlineSmall.copyWith(
                              color: PremiumDesignTokens.neutral800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          _ConfidenceBadge(color: color),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // ── Runtime availability ────────────────────────────────
                Text(
                  pending
                      ? 'Model analysis pending — clinical guidance is ready.'
                      : unavailableReason ??
                            'No eligible experimental model output is available.',
                ),

                const SizedBox(height: 10),
                // Wrap, not Row: the chips must fold onto a second line on
                // narrow screens at large text scales instead of
                // overflowing.
                const Text('Rule-based summary · Not neural inference'),

                // ── Deterministic rule-based narrative ────────────────────
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: PremiumDesignTokens.neutral50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: PremiumDesignTokens.neutral200),
                  ),
                  child: Text(
                    pending
                        ? 'Clinical protocols remain available while the on-device model runs.'
                        : reasoning.narrative,
                    style: PremiumDesignTokens.bodyMedium.copyWith(
                      color: PremiumDesignTokens.neutral800,
                      height: 1.55,
                    ),
                  ),
                ),

                // ── Feature attributions ─────────────────────────────────
                if (!pending && reasoning.contributions.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 8,
                    children: [
                      Text(
                        'Rule-based contributors',
                        style: PremiumDesignTokens.headlineSmall.copyWith(
                          color: PremiumDesignTokens.neutral800,
                        ),
                      ),
                      if (onExplainTapped != null)
                        TextButton(
                          onPressed: onExplainTapped,
                          child: Text(
                            'Details',
                            style: PremiumDesignTokens.labelLarge.copyWith(
                              color: PremiumDesignTokens.primary,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...reasoning.contributions
                      .take(3)
                      .map(
                        (c) => _ContributionBar(
                          label: c.label,
                          measured: c.measured,
                          points: c.points,
                          maxPoints: reasoning.contributions.first.points,
                          color: color,
                        ),
                      ),
                ],

                // ── What would change this ───────────────────────────────
                if (!pending && reasoning.whatWouldChangeThis.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(
                    'What would change this read',
                    style: PremiumDesignTokens.headlineSmall.copyWith(
                      color: PremiumDesignTokens.neutral800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final change in reasoning.whatWouldChangeThis)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.cached_rounded,
                            size: 15,
                            color: PremiumDesignTokens.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              change,
                              style: PremiumDesignTokens.bodyMedium.copyWith(
                                color: PremiumDesignTokens.neutral700,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],

                const SizedBox(height: 16),
                Text(
                  'Rule-based summary · Not a diagnosis · Clinician review required. '
                  'Clinical protocols govern treatment and referral.',
                  style: PremiumDesignTokens.labelMedium.copyWith(
                    color: PremiumDesignTokens.neutral500,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Confidence badge driven by the model's data-quality arithmetic.
class _ConfidenceBadge extends StatelessWidget {
  const _ConfidenceBadge({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'Rule-based',
              style: PremiumDesignTokens.labelSmall.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// One attribution: label + measured value, signed bar sized by points.
class _ContributionBar extends StatelessWidget {
  const _ContributionBar({
    required this.label,
    required this.measured,
    required this.points,
    required this.maxPoints,
    required this.color,
  });

  final String label;
  final String measured;
  final double points;
  final double maxPoints;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ratio = maxPoints <= 0 ? 0.0 : (points / maxPoints).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$label — $measured',
                  style: PremiumDesignTokens.bodyMedium.copyWith(
                    color: PremiumDesignTokens.neutral700,
                  ),
                ),
              ),
              Text(
                '+${points.toStringAsFixed(1)}',
                style: PremiumDesignTokens.bodyMedium.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              backgroundColor: PremiumDesignTokens.neutral200,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }
}

/// One small stat pill on the index row.
class _StatChip extends StatelessWidget {
  const _StatChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: PremiumDesignTokens.neutral100,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: PremiumDesignTokens.labelMedium.copyWith(
        color: PremiumDesignTokens.neutral600,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
