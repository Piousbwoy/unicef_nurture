import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/fhw_luxe.dart';
import '../../core/theme/glass.dart';
import '../shared/ui.dart' show PressScale;

/// One quick action revealed behind a swiped queue card.
class SwipeAction {
  const SwipeAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.tone,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final Color? tone;
}

/// A foreground card that swipes left to reveal quick actions behind it.
///
/// Tap on the closed card fires the primary action (the obvious thing);
/// tap while open closes the reveal. The reveal is a direct manipulation,
/// not decoration, so it stays available under reduced motion — it simply
/// snaps instead of easing.
class SwipeRevealActions extends StatefulWidget {
  const SwipeRevealActions({
    super.key,
    required this.actions,
    required this.child,
    this.onTap,
    this.revealWidth = 156,
  });

  final List<SwipeAction> actions;
  final Widget child;
  final VoidCallback? onTap;
  final double revealWidth;

  @override
  State<SwipeRevealActions> createState() => _SwipeRevealActionsState();
}

class _SwipeRevealActionsState extends State<SwipeRevealActions> {
  double _offset = 0;

  void _updateDrag(double dx) {
    setState(() {
      _offset = (_offset + dx).clamp(-widget.revealWidth, 0.0);
    });
  }

  void _endDrag(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    setState(() {
      _offset = velocity < -300 || _offset < -widget.revealWidth / 2
          ? -widget.revealWidth
          : 0.0;
    });
  }

  void _tap() {
    if (_offset != 0) {
      setState(() => _offset = 0);
      return;
    }
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.actions.isEmpty) return widget.child;
    final fx = VisualEffects.of(context);
    final duration = fx.scale(const Duration(milliseconds: 220));
    final actionWidth = widget.revealWidth / widget.actions.length;
    return ClipRRect(
      borderRadius: BorderRadius.circular(Gap.radius),
      child: Stack(
        children: [
          Positioned.fill(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                for (final action in widget.actions)
                  Semantics(
                    button: true,
                    label: action.label,
                    child: InkWell(
                      onTap: action.onPressed,
                      child: Container(
                        width: actionWidth,
                        color:
                            (action.tone ?? AppColors.primary).withValues(
                              alpha: 0.10,
                            ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              action.icon,
                              size: 19,
                              color: action.tone ?? AppColors.primaryDark,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              action.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.label.copyWith(
                                fontSize: 10.5,
                                color: action.tone ?? AppColors.primaryDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(end: _offset),
            duration: duration,
            curve: AppMotion.curve,
            builder: (context, value, child) => Transform.translate(
              offset: Offset(value, 0),
              child: child,
            ),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _tap,
              onHorizontalDragUpdate: (details) => _updateDrag(details.delta.dx),
              onHorizontalDragEnd: _endDrag,
              child: widget.child,
            ),
          ),
        ],
      ),
    );
  }
}

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
      side: BorderSide(color: accent ?? FhwLuxePalette.hairLine),
    );
    // The surface has to be a Material, not a coloured box: rows inside a
    // card are frequently ListTiles, and ink on a DecoratedBox paints under
    // it — the tap feedback silently disappears.
    final card = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: const [
          BoxShadow(
            color: Color(0x080F2042),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
          BoxShadow(
            color: Color(0x0A0F2042),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: FhwLuxePalette.cardSurface,
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
