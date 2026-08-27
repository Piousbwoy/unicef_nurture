/// AI Insight Card - Glassmorphism Design
/// Displays AI risk prediction with confidence and explainability
/// Part of the CareBridge Premium Design System

import 'package:flutter/material.dart';
import '../../../../core/theme/premium_design_tokens.dart';

class AiInsightCard extends StatelessWidget {
  const AiInsightCard({
    super.key,
    required this.riskProbability,
    this.confidenceInterval,
    this.confidenceLevel = ConfidenceLevel.medium,
    this.topFeatures = const [],
    this.driftDetected = false,
    this.onExplainTapped,
    this.animationDuration = PremiumDesignTokens.standardTransition,
  });

  /// Risk probability (0.0 - 1.0)
  final double riskProbability;

  /// 95% confidence interval [lower, upper]
  final List<double>? confidenceInterval;

  /// Confidence level based on data quality
  final ConfidenceLevel confidenceLevel;

  /// Top 3 features driving the prediction
  final List<FeatureImportance> topFeatures;

  /// Whether drift was detected (reduces confidence)
  final bool driftDetected;

  /// Callback when user taps "Explain"
  final VoidCallback? onExplainTapped;

  final Duration animationDuration;

  String get _riskLabel {
    if (riskProbability >= 0.8) return 'Very High Risk';
    if (riskProbability >= 0.6) return 'High Risk';
    if (riskProbability >= 0.4) return 'Moderate Risk';
    if (riskProbability >= 0.2) return 'Low Risk';
    return 'Very Low Risk';
  }

  Color get _riskColor {
    if (riskProbability >= 0.7) return PremiumDesignTokens.urgent;
    if (riskProbability >= 0.4) return PremiumDesignTokens.watch;
    return PremiumDesignTokens.routine;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: PremiumDesignTokens.glassCard(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            // Gradient overlay based on risk
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _riskColor.withOpacity(0.08),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row with icon and badge
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _riskColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.psychology,
                          color: _riskColor,
                          size: 24,
                        ),
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
                            _ConfidenceBadge(
                              level: confidenceLevel,
                              driftDetected: driftDetected,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Risk probability with gauge
                  _RiskGauge(
                    probability: riskProbability,
                    label: _riskLabel,
                    color: _riskColor,
                  ),

                  // Confidence interval
                  if (confidenceInterval != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      '95% Confidence: ${(confidenceInterval![0] * 100).toStringAsFixed(0)}–${(confidenceInterval![1] * 100).toStringAsFixed(0)}%',
                      style: PremiumDesignTokens.bodyMedium.copyWith(
                        color: PremiumDesignTokens.neutral500,
                      ),
                    ),
                  ],

                  // Drift warning
                  if (driftDetected) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: PremiumDesignTokens.watchLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: PremiumDesignTokens.watch.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: PremiumDesignTokens.watch,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Input outside training range. Rely on clinical judgment.',
                              style: PremiumDesignTokens.bodyMedium.copyWith(
                                color: PremiumDesignTokens.neutral700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Explainability section
                  if (topFeatures.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Why this risk?',
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
                    ...topFeatures.take(3).map((feature) => _FeatureBar(
                          feature: feature,
                          maxImpact: topFeatures.first.impact,
                        )),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Confidence level badge
class _ConfidenceBadge extends StatelessWidget {
  const _ConfidenceBadge({
    required this.level,
    required this.driftDetected,
  });

  final ConfidenceLevel level;
  final bool driftDetected;

  Color get _color {
    if (driftDetected) return PremiumDesignTokens.watch;
    switch (level) {
      case ConfidenceLevel.high:
        return PremiumDesignTokens.routine;
      case ConfidenceLevel.medium:
        return PremiumDesignTokens.watch;
      case ConfidenceLevel.low:
        return PremiumDesignTokens.urgent;
    }
  }

  String get _label {
    if (driftDetected) return 'Low Confidence';
    return '${level.name[0].toUpperCase()}${level.name.substring(1)} Confidence';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: _color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _label,
            style: PremiumDesignTokens.labelSmall.copyWith(
              color: _color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Animated risk gauge with progress indicator
class _RiskGauge extends StatelessWidget {
  const _RiskGauge({
    required this.probability,
    required this.label,
    required this.color,
  });

  final double probability;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: PremiumDesignTokens.neutral50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: PremiumDesignTokens.neutral200,
        ),
      ),
      child: Column(
        children: [
          // Probability text
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${(probability * 100).toStringAsFixed(0)}',
                style: PremiumDesignTokens.displayLarge.copyWith(
                  color: color,
                  fontSize: 56,
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '%',
                  style: PremiumDesignTokens.headlineMedium.copyWith(
                    color: color.withOpacity(0.8),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Risk label
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              label,
              style: PremiumDesignTokens.labelLarge.copyWith(
                color: color,
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: probability,
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

/// Feature importance bar for explainability
class _FeatureBar extends StatelessWidget {
  const _FeatureBar({
    required this.feature,
    required this.maxImpact,
  });

  final FeatureImportance feature;
  final double maxImpact;

  @override
  Widget build(BuildContext context) {
    final ratio = (feature.impact.abs() / maxImpact).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  feature.name,
                  style: PremiumDesignTokens.bodyMedium.copyWith(
                    color: PremiumDesignTokens.neutral700,
                  ),
                ),
              ),
              Text(
                feature.impact > 0 ? '+${(feature.impact * 100).toStringAsFixed(0)}%' : '${(feature.impact * 100).toStringAsFixed(0)}%',
                style: PremiumDesignTokens.bodyMedium.copyWith(
                  color: feature.impact > 0
                      ? PremiumDesignTokens.urgent
                      : PremiumDesignTokens.routine,
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
              valueColor: AlwaysStoppedAnimation<Color>(
                feature.impact > 0
                    ? PremiumDesignTokens.urgent
                    : PremiumDesignTokens.routine,
              ),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }
}

/// Confidence level enum
enum ConfidenceLevel { high, medium, low }

/// Feature importance model
class FeatureImportance {
  const FeatureImportance({
    required this.name,
    required this.impact,
  });

  final String name;
  final double impact;
}
