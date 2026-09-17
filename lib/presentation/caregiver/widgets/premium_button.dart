/// Premium check button — the signature action of the caregiver Check tab.
///
/// Deep navy gradient, white text, subtle blue glow, and a satisfying press
/// animation. Designed to feel like the primary action in a high-end banking
/// app — because a danger-sign check deserves the same visual weight as
/// "Transfer funds."
///
/// Accessibility contract: the disabled state is *visible* (the button dims
/// and loses its glow, not just its tap handler), the label wraps instead of
/// overflowing at large text scales, and press animation routes through the
/// app-wide reduced-motion scale.
///
/// Used in:
/// - `_CheckHero` in `check_tab.dart`
/// - Family tab quick actions in `family_tab.dart`
/// - Assessment navigation in `triage_screen.dart`
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/glass.dart';

/// A full-width premium action button with deep navy gradient, white text,
/// and a subtle blue glow shadow.
class PremiumCheckButton extends StatefulWidget {
  const PremiumCheckButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.health_and_safety_rounded,
    this.trailingIcon = Icons.arrow_forward_rounded,
    this.height = 60,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData icon;
  final IconData trailingIcon;
  final double height;
  final bool enabled;

  @override
  State<PremiumCheckButton> createState() => _PremiumCheckButtonState();
}

class _PremiumCheckButtonState extends State<PremiumCheckButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    if (widget.enabled) _pressController.forward();
  }

  void _onTapUp(TapUpDetails _) {
    _pressController.reverse();
    if (widget.enabled) widget.onPressed();
  }

  void _onTapCancel() {
    _pressController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final motion = VisualEffects.of(context);
    final duration = motion.scale(AppMotion.fast);
    return Semantics(
      button: true,
      enabled: widget.enabled,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: child,
          );
        },
        child: GestureDetector(
          onTapDown: _onTapDown,
          onTapUp: _onTapUp,
          onTapCancel: _onTapCancel,
          child: AnimatedOpacity(
            // A disabled premium button must LOOK disabled: the glow dies and
            // the surface dims, so "why won't it press" never happens.
            duration: duration,
            opacity: widget.enabled ? 1.0 : 0.45,
            child: Container(
              height: widget.height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: AppColors.checkButtonGradient,
                boxShadow: widget.enabled
                    ? [
                        BoxShadow(
                          color: AppColors.checkBlue.withValues(alpha: 0.2),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ]
                    : const [],
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: widget.enabled ? widget.onPressed : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Icon(widget.icon, color: Colors.white, size: 24),
                        const SizedBox(width: 12),
                        // Flexible so long labels wrap at large text scales
                        // instead of pushing the trailing chevron off-card.
                        Expanded(
                          child: Text(
                            widget.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Sora',
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0.2,
                              height: 1.2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          widget.trailingIcon,
                          color: Colors.white.withValues(alpha: 0.9),
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A smaller variant of the premium button for inline actions.
class PremiumActionButton extends StatelessWidget {
  const PremiumActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = PremiumActionVariant.primary,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final PremiumActionVariant variant;

  @override
  Widget build(BuildContext context) {
    final isPrimary = variant == PremiumActionVariant.primary;

    return Container(
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: isPrimary ? AppColors.checkButtonGradient : null,
        color: isPrimary ? null : Colors.white,
        border: isPrimary
            ? Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1)
            : Border.all(color: AppColors.checkNavy, width: 1.5),
        boxShadow: isPrimary
            ? [
                BoxShadow(
                  color: AppColors.checkBlue.withValues(alpha: 0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onPressed,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  color: isPrimary ? Colors.white : AppColors.checkNavy,
                  size: 20,
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Sora',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isPrimary ? Colors.white : AppColors.checkNavy,
                  ),
                ),
              ),
              if (icon != null) const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

enum PremiumActionVariant { primary, secondary }
