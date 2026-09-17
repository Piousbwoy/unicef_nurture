/// Premium Triage Banner
/// Immersive, full-width banner with urgent visual hierarchy
/// Part of the CareBridge Premium Design System
///
/// Rendered as a frosted hero surface. The triage colour is clinical, so it
/// is confined to the accent edge, icon, chips and text — never the surface.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/glass.dart';
import '../../../core/theme/motion.dart';
import '../../../core/theme/premium_design_tokens.dart';
import '../ui.dart';

enum TriageLevel { urgent, watch, routine }

class TriageBanner extends StatelessWidget {
  const TriageBanner({
    super.key,
    required this.level,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.preReferralActions = const [],
    this.animationDuration = PremiumDesignTokens.emphasizedTransition,
  });

  final TriageLevel level;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final List<String> preReferralActions;
  final Duration animationDuration;

  // Color schemes for each triage level
  TriageColors get _colors {
    switch (level) {
      case TriageLevel.urgent:
        return TriageColors(
          primary: PremiumDesignTokens.urgent,
          light: PremiumDesignTokens.urgentLight,
          gradient: const [Color(0xFFDC2626), Color(0xFFB91C1C)],
          shadow: const Color(0xFFDC2626).withValues(alpha: 0.4),
          icon: Icons.emergency,
        );
      case TriageLevel.watch:
        return TriageColors(
          primary: PremiumDesignTokens.watch,
          light: PremiumDesignTokens.watchLight,
          gradient: const [Color(0xFFD97706), Color(0xFFB45309)],
          shadow: const Color(0xFFD97706).withValues(alpha: 0.3),
          icon: Icons.visibility,
        );
      case TriageLevel.routine:
        return TriageColors(
          primary: PremiumDesignTokens.routine,
          light: PremiumDesignTokens.routineLight,
          gradient: const [Color(0xFF059669), Color(0xFF047857)],
          shadow: const Color(0xFF059669).withValues(alpha: 0.25),
          icon: Icons.check_circle,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = _colors;
    final radius = BorderRadius.circular(GlassTier.hero.radius);
    final motion = VisualEffects.of(context).motion;

    return GlassSurface(
      tier: GlassTier.hero,
      padding: EdgeInsets.zero,
      child: AccentEdge(
        accent: colors.primary,
        borderRadius: radius,
        width: 6,
        child: Stack(
          children: [
            // Soft pulse behind urgent content; static under reduced motion.
            if (level == TriageLevel.urgent && motion)
              Positioned(
                top: 12,
                left: 12,
                child: IgnorePointer(
                  child: PulseRing(
                    colour: colors.primary,
                    size: 56,
                    child: const SizedBox.shrink(),
                  ),
                ),
              ),

            // Content
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icon and label row
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.glassFill,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.glassStroke),
                        ),
                        child: Icon(
                          colors.icon,
                          color: colors.primary,
                          size: 28,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.glassFill,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.glassStroke),
                        ),
                        child: Text(
                          level.name.toUpperCase(),
                          style: TextStyle(
                            color: colors.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Title
                  Text(
                    title,
                    style: AppType.headline.copyWith(
                      color: AppColors.ink,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                      letterSpacing: -0.5,
                    ),
                  ),

                  if (subtitle != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        color: AppColors.inkMuted,
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                        height: 1.5,
                      ),
                    ),
                  ],

                  // Pre-referral actions
                  if (preReferralActions.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    GlassSurface(
                      tier: GlassTier.chip,
                      blur: false,
                      shadow: false,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.medical_services,
                                color: colors.primary,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'DO NOW — BEFORE TRANSPORT',
                                  style: TextStyle(
                                    color: colors.primary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ...preReferralActions.map(
                            (action) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    margin: const EdgeInsets.only(top: 6),
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: colors.primary,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      action,
                                      style: const TextStyle(
                                        color: AppColors.ink,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        height: 1.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Action button
                  if (actionLabel != null && onAction != null) ...[
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: onAction,
                        style: FilledButton.styleFrom(
                          backgroundColor: colors.primary,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(52),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          actionLabel!,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
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

/// Color configuration for each triage level
class TriageColors {
  const TriageColors({
    required this.primary,
    required this.light,
    required this.gradient,
    required this.shadow,
    required this.icon,
  });

  final Color primary;
  final Color light;
  final List<Color> gradient;
  final Color shadow;
  final IconData icon;
}
