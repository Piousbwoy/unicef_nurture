/// AI Insight Card - Glassmorphism Design
///
/// The on-device model's voice on the result page: the continuous acuity
/// index, its 95% band, the patient-specific narrative it generated, the
/// feature attributions behind the number, and what would change it.
/// Fed entirely by [ClinicalReasoning] — every sentence and every number on
/// this card is derived from THIS patient's measurements, so two patients
/// with similar-but-different records never read identically.
///
/// The card explains and grades; the protocol verdict governs care. It
/// never issues treatment or referral instructions.
/// Part of the CareBridge Premium Design System.
library;

import 'package:flutter/material.dart';

import '../../../core/ml/clinical_reasoning_engine.dart';
import '../../../core/theme/glass.dart';
import '../../../core/theme/premium_design_tokens.dart';

class AiInsightCard extends StatelessWidget {
  const AiInsightCard({
    super.key,
    required this.reasoning,
    this.onExplainTapped,
    this.animationDuration = PremiumDesignTokens.standardTransition,
  });

  final ClinicalReasoning reasoning;
  final VoidCallback? onExplainTapped;
  final Duration animationDuration;

  Color get _indexColor {
    final v = reasoning.acuityIndex;
    if (v >= 65) return PremiumDesignTokens.urgent;
    if (v >= 40) return PremiumDesignTokens.watch;
    return PremiumDesignTokens.routine;
  }

  @override
  Widget build(BuildContext context) {
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
                            'On-device AI assessment',
                            style: PremiumDesignTokens.headlineSmall.copyWith(
                              color: PremiumDesignTokens.neutral800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          _ConfidenceBadge(
                            confidencePct: reasoning.confidencePct,
                            color: color,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // ── The index, its band and its band ─────────────────────
                _AcuityGauge(
                  index: reasoning.acuityIndex,
                  band: reasoning.bandLabel,
                  color: color,
                ),

                const SizedBox(height: 10),
                // Wrap, not Row: the chips must fold onto a second line on
                // narrow screens at large text scales instead of
                // overflowing.
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _StatChip(
                      label:
                          '95% band ${reasoning.ci95.lo.round()}–'
                          '${reasoning.ci95.hi.round()}',
                    ),
                    _StatChip(label: 'Confidence ${reasoning.confidencePct}%'),
                  ],
                ),

                // ── The narrative: the model speaking about THIS patient ──
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: PremiumDesignTokens.neutral50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: PremiumDesignTokens.neutral200,
                    ),
                  ),
                  child: Text(
                    reasoning.narrative,
                    style: PremiumDesignTokens.bodyMedium.copyWith(
                      color: PremiumDesignTokens.neutral800,
                      height: 1.55,
                    ),
                  ),
                ),

                // ── Feature attributions ─────────────────────────────────
                if (reasoning.contributions.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'What moves the number',
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
                if (reasoning.whatWouldChangeThis.isNotEmpty) ...[
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
                  'Generated on-device from this visit’s measurements. It '
                  'explains and grades — the protocol verdict above governs '
                  'treatment and referral.',
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
  const _ConfidenceBadge({required this.confidencePct, required this.color});

  final int confidencePct;
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
          Text(
            '$confidencePct% confidence',
            style: PremiumDesignTokens.labelSmall.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

/// The continuous acuity index, rendered as a gradient progress gauge.
class _AcuityGauge extends StatelessWidget {
  const _AcuityGauge({
    required this.index,
    required this.band,
    required this.color,
  });

  final double index;
  final String band;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      tier: GlassTier.chip,
      blur: false,
      shadow: false,
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // FittedBox: the big number and its unit keep their natural size
          // on wide screens and scale down together on narrow ones, instead
          // of overflowing a fixed-width row.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  index.round().toString(),
                  style: PremiumDesignTokens.displayLarge.copyWith(
                    color: color,
                    fontSize: 56,
                  ),
                ),
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    '/ 100 acuity',
                    style: PremiumDesignTokens.headlineMedium.copyWith(
                      color: color.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              band,
              style: PremiumDesignTokens.labelLarge.copyWith(color: color),
            ),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: index / 100,
              backgroundColor: PremiumDesignTokens.neutral200,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 8,
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
