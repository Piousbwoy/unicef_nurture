/// Premium Triage Banner
/// Immersive, full-width banner with urgent visual hierarchy
/// Part of the CareBridge Premium Design System

import 'package:flutter/material.dart';
import '../../../../core/theme/premium_design_tokens.dart';

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
          gradient: const [
            Color(0xFFDC2626),
            Color(0xFFB91C1C),
          ],
          shadow: const Color(0xFFDC2626).withOpacity(0.4),
          icon: Icons.emergency,
        );
      case TriageLevel.watch:
        return TriageColors(
          primary: PremiumDesignTokens.watch,
          light: PremiumDesignTokens.watchLight,
          gradient: const [
            Color(0xFFD97706),
            Color(0xFFB45309),
          ],
          shadow: const Color(0xFFD97706).withOpacity(0.3),
          icon: Icons.visibility,
        );
      case TriageLevel.routine:
        return TriageColors(
          primary: PremiumDesignTokens.routine,
          light: PremiumDesignTokens.routineLight,
          gradient: const [
            Color(0xFF059669),
            Color(0xFF047857),
          ],
          shadow: const Color(0xFF059669).withOpacity(0.25),
          icon: Icons.check_circle,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = _colors;

    return AnimatedContainer(
      duration: animationDuration,
      curve: PremiumDesignTokens.emphasizedCurve,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors.gradient,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: colors.shadow,
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // Animated background pulse for urgent
            if (level == TriageLevel.urgent)
              Positioned.fill(
                child: _PulseAnimation(
                  color: Colors.white.withOpacity(0.1),
                ),
              ),

            // Content
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icon and label row
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          colors.icon,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          level.name.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
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
                    style: const TextStyle(
                      color: Colors.white,
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
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                        height: 1.5,
                      ),
                    ),
                  ],

                  // Pre-referral actions
                  if (preReferralActions.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.medical_services,
                                color: Colors.white.withOpacity(0.9),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'DO NOW — BEFORE TRANSPORT',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.9),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ...preReferralActions.map((action) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      margin: const EdgeInsets.only(top: 6),
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        action,
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.95),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          height: 1.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )),
                        ],
                      ),
                    ),
                  ],

                  // Action button
                  if (actionLabel != null && onAction != null) ...[
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: onAction,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: colors.primary,
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

/// Subtle pulse animation for urgent triage
class _PulseAnimation extends StatefulWidget {
  const _PulseAnimation({required this.color});

  final Color color;

  @override
  State<_PulseAnimation> createState() => _PulseAnimationState();
}

class _PulseAnimationState extends State<_PulseAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 0.5 + (_animation.value * 0.5),
              colors: [
                widget.color.withOpacity(0.3 * (1 - _animation.value)),
                Colors.transparent,
              ],
            ),
          ),
        );
      },
    );
  }
}
