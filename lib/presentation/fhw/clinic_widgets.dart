import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../shared/ui.dart' show PressScale;

class ClinicCard extends StatelessWidget {
  const ClinicCard({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.trailing,
    this.accent,
    this.padding = const EdgeInsets.all(20),
    this.onTap,
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final Color? accent;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(Gap.radius);
    final shape = RoundedRectangleBorder(
      borderRadius: radius,
      side: BorderSide(color: accent ?? AppColors.line),
    );
    // The surface has to be a Material, not a coloured box: rows inside a
    // card are frequently ListTiles, and ink on a DecoratedBox paints under
    // it — the tap feedback silently disappears.
    final card = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: const [AppShadows.card],
      ),
      child: Material(
        // A raised warm-white surface: it reads as lifted paper against the
        // ivory canvas, warmer than a pure clinical white.
        color: AppColors.canvas,
        clipBehavior: Clip.antiAlias,
        shape: shape,
        child: Stack(
          children: [
            Padding(
              padding: padding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (title != null) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title!,
                            style: AppType.title.copyWith(fontSize: 17),
                          ),
                        ),
                        ?trailing,
                      ],
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        subtitle!,
                        style: AppType.body.copyWith(
                          fontSize: 13,
                          color: AppColors.inkMuted,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                  ],
                  child,
                ],
              ),
            ),
            // A gradient accent edge that hugs the card height. A Positioned
            // bar (not a Row child) is used on purpose: inside a ListView the
            // card has unbounded height, and a stretched Row child would be
            // forced to infinite height.
            if (accent != null)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 4,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [accent!, accent!.withValues(alpha: 0.55)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (onTap == null) return card;
    // A felt-not-seen press on tappable cards; the press is a transient
    // AnimatedScale with no looping controller, so widget tests stay safe.
    return PressScale(onTap: onTap, radius: radius, child: card);
  }
}

class ClinicStepHeader extends StatelessWidget {
  const ClinicStepHeader({
    super.key,
    required this.steps,
    required this.current,
  });

  final List<String> steps;
  final int current;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Step ${current + 1} of ${steps.length}: ${steps[current]}',
    child: ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (var i = 0; i < steps.length; i++)
                  Expanded(
                    child: Container(
                      height: 4,
                      margin: EdgeInsets.only(
                        right: i == steps.length - 1 ? 0 : 6,
                      ),
                      decoration: BoxDecoration(
                        // Completed steps cool into brass; the step in progress
                        // keeps the teal brand voice. Brass is chrome, never a
                        // clinical status colour.
                        gradient: i < current ? AppColors.brassEdge : null,
                        color: i == current
                            ? AppColors.primary
                            : (i < current ? null : AppColors.line),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${current + 1} / ${steps.length}   ${steps[current]}',
              style: AppType.label.copyWith(
                fontSize: 13,
                color: AppColors.primaryDark,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class ClinicStatusLine extends StatelessWidget {
  const ClinicStatusLine({
    super.key,
    required this.text,
    this.icon = Icons.phone_android_rounded,
    this.onTap,
  });

  final String text;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(Gap.radiusXs),
            ),
            child: Icon(icon, size: 17, color: AppColors.primaryDark),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: AppType.caption.copyWith(
                color: AppColors.inkMuted,
                fontSize: 12,
              ),
            ),
          ),
          if (onTap != null)
            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: AppColors.inkMuted,
            ),
        ],
      ),
    );
    return Material(
      color: AppColors.surfaceTint,
      borderRadius: BorderRadius.circular(12),
      child: onTap == null
          ? content
          : InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: content,
            ),
    );
  }
}
