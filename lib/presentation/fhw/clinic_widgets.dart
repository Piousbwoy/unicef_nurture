import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/fhw_luxe.dart';
import '../../core/theme/glass.dart';
import '../../core/theme/lumen.dart';
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
                        color: (action.tone ?? AppColors.primary).withValues(
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
            builder: (context, value, child) =>
                Transform.translate(offset: Offset(value, 0), child: child),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _tap,
              onHorizontalDragUpdate: (details) =>
                  _updateDrag(details.delta.dx),
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
    // The surface has to be a Material, not a coloured box: rows inside a
    // card are frequently ListTiles, and ink on a DecoratedBox paints under
    // it — the tap feedback silently disappears. The Material keeps its opaque
    // cardSurface (consumers and their tests rely on a legible, non-transparent
    // fill); the sanctuary depth comes from the carved chiaroscuro beneath it,
    // the refraction rim around it and the crown catch-light across the top.
    final card = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(
          color: accent ?? FhwLuxePalette.glassBorderLight,
          width: 1.1,
        ),
        boxShadow: Chiaroscuro.alabaster,
      ),
      child: Material(
        color: FhwLuxePalette.cardSurface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: radius),
        child: Stack(
          children: [
            // The crown catch-light — the single bright line that sells mass.
            Positioned(
              top: 0,
              left: Gap.radius,
              right: Gap.radius,
              child: IgnorePointer(
                child: Container(
                  height: 1.2,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0x00FFFFFF),
                        Color(0xCCFFFFFF),
                        Color(0x00FFFFFF),
                      ],
                    ),
                  ),
                ),
              ),
            ),
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

/// The sanctuary-grade sibling of [ClinicCard], used by the FHW dashboard.
///
/// Same content contract as [ClinicCard] — identical [title] / [subtitle] /
/// [child] rendering so every pinned string is untouched — but carved from
/// matte alabaster: the surface is a solid lit top-to-bottom and cooled at the
/// foot, held off the field by layered chiaroscuro, edged with a refraction rim
/// and a single crown catch-light. A [Material] stays transparent over the
/// stone so ListTile and row ink still fires. Where [ClinicCard] must keep a
/// flat opaque fill for other consumers, dashboard panels use this.
class LumenCard extends StatelessWidget {
  const LumenCard({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.trailing,
    this.accent,
    this.padding = const EdgeInsets.fromLTRB(20, 20, 20, 22),
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
    final radius = BorderRadius.circular(Gap.radiusLg);
    final content = Padding(
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
                    style: AppType.title.copyWith(
                      fontSize: 17.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color: FhwLuxePalette.sapphireDeep,
                    ),
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
            // A hairline of cold light separates the header from the body —
            // the museum label rule, drawn in sapphire rather than ink.
            const SizedBox(height: 14),
            const IgnorePointer(
              child: SizedBox(
                height: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0x1A1B56DB), Color(0x001B56DB)],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          child,
        ],
      ),
    );

    final carved = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: Lumen.alabaster,
        border: Border.all(
          color: accent ?? FhwLuxePalette.glassBorderLight,
          width: 1.1,
        ),
        boxShadow: Chiaroscuro.alabaster,
      ),
      child: Material(
        // Transparent so the carved alabaster shows through while the Material
        // still hosts ink for the rows this card frequently contains.
        color: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: radius),
        child: Stack(
          children: [
            // The crown catch-light across the top of the stone.
            Positioned(
              top: 0,
              left: Gap.radiusLg,
              right: Gap.radiusLg,
              child: IgnorePointer(
                child: Container(
                  height: 1.2,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0x00FFFFFF),
                        Color(0xE6FFFFFF),
                        Color(0x00FFFFFF),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            content,
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
    if (onTap == null) return carved;
    return PressScale(onTap: onTap!, radius: radius, child: carved);
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
