/// Motion vocabulary for the glass layer. Extends [AppMotion].
///
/// Every duration here goes through [VisualEffects.scale], so under the OS
/// reduced-motion setting or the user's Lite mode all of these become
/// instant: the same final frame, no tweens. Nothing in this file is allowed
/// to carry meaning that would be lost when motion is off.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'glass.dart';

/// Fade + 12px rise, delayed by 45ms × [index] (capped at index 8) so a list
/// of cards settles like a hand of cards being dealt.
class StaggeredReveal extends StatefulWidget {
  const StaggeredReveal({
    super.key,
    required this.index,
    required this.child,
    this.duration = const Duration(milliseconds: 380),
  });

  final int index;
  final Widget child;
  final Duration duration;

  @override
  State<StaggeredReveal> createState() => _StaggeredRevealState();
}

class _StaggeredRevealState extends State<StaggeredReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _t;
  bool _armed = false;

  @override
  void initState() {
    super.initState();
    // The per-index stagger is baked into the curve as a leading Interval
    // rather than a Timer, so nothing is left pending if the widget is
    // disposed (or a test ends) before the reveal starts.
    final delay = Duration(milliseconds: 45 * math.min(widget.index, 8));
    final total = delay + widget.duration;
    _c = AnimationController(vsync: this, duration: total);
    final start = total.inMicroseconds == 0
        ? 0.0
        : delay.inMicroseconds / total.inMicroseconds;
    _t = CurvedAnimation(
      parent: _c,
      curve: Interval(start, 1, curve: AppMotion.curve),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_armed) return;
    _armed = true;
    final fx = VisualEffects.of(context);
    if (!fx.motion) {
      _c.value = 1;
      return;
    }
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _t,
    builder: (context, child) => Opacity(
      opacity: _t.value,
      child: Transform.translate(
        offset: Offset(0, 12 * (1 - _t.value)),
        child: child,
      ),
    ),
    child: widget.child,
  );
}

/// A number that counts up to [value] over 600ms. With motion off it renders
/// the final value immediately.
class CountUpText extends StatelessWidget {
  const CountUpText({
    super.key,
    required this.value,
    this.style,
    this.formatter,
    this.textAlign,
  });

  final num value;
  final TextStyle? style;
  final String Function(num)? formatter;
  final TextAlign? textAlign;

  String _format(num v) => formatter?.call(v) ?? v.round().toString();

  @override
  Widget build(BuildContext context) {
    final fx = VisualEffects.of(context);
    final d = fx.scale(const Duration(milliseconds: 600));
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value.toDouble()),
      duration: d,
      curve: AppMotion.curve,
      builder: (context, v, _) => Text(
        _format(value is int ? v.round() : v),
        style: style,
        textAlign: textAlign,
      ),
    );
  }
}

/// A soft breathing ring drawn behind something that is "live" — the breath
/// counter while it is running. Static when motion is off.
class PulseRing extends StatefulWidget {
  const PulseRing({
    super.key,
    required this.child,
    this.active = true,
    this.colour = AppColors.primary,
    this.size = 220,
    this.progress,
  });

  final Widget child;
  final bool active;
  final Color colour;
  final double size;

  /// Optional 0–1 arc drawn on top of the ring (elapsed time).
  final double? progress;

  @override
  State<PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<PulseRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(PulseRing old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final fx = VisualEffects.of(context);
    if (widget.active && fx.motion) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.size,
    height: widget.size,
    child: AnimatedBuilder(
      animation: _c,
      builder: (context, child) => CustomPaint(
        painter: _RingPainter(
          t: _c.value,
          colour: widget.colour,
          progress: widget.progress,
          active: widget.active,
        ),
        child: child,
      ),
      child: Center(child: widget.child),
    ),
  );
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.t,
    required this.colour,
    required this.progress,
    required this.active,
  });

  final double t;
  final Color colour;
  final double? progress;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    // Two expanding halos.
    if (active) {
      for (final phase in [0.0, 0.5]) {
        final p = (t + phase) % 1.0;
        canvas.drawCircle(
          c,
          r * (0.72 + 0.28 * p),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = colour.withValues(alpha: 0.35 * (1 - p)),
        );
      }
    }
    // Track.
    canvas.drawCircle(
      c,
      r * 0.72,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..color = colour.withValues(alpha: 0.12),
    );
    // Progress arc.
    final p = progress;
    if (p != null && p > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r * 0.72),
        -math.pi / 2,
        2 * math.pi * p.clamp(0.0, 1.0),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round
          ..color = colour,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.t != t ||
      old.progress != progress ||
      old.active != active ||
      old.colour != colour;
}

/// A loading placeholder: a rounded bar with a slow travelling sheen. Static
/// tint when motion is off.
class Shimmer extends StatefulWidget {
  const Shimmer({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.radius = Gap.radiusXs,
  });

  final double width;
  final double height;
  final double radius;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (VisualEffects.of(context).motion) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, _) => Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.radius),
        gradient: LinearGradient(
          begin: Alignment(-1 + 2 * _c.value - 1, 0),
          end: Alignment(-1 + 2 * _c.value + 1, 0),
          colors: const [
            AppColors.surfaceTint,
            AppColors.primaryLight,
            AppColors.surfaceTint,
          ],
        ),
      ),
    ),
  );
}

/// The page transition used for every push inside the glass screens:
/// fade + scale .98→1 + 24px slide, 320ms. Instant when motion is off.
class GlassPageRoute<T> extends PageRouteBuilder<T> {
  GlassPageRoute({required WidgetBuilder builder, super.settings})
    : super(
        pageBuilder: (context, animation, secondary) => builder(context),
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        transitionsBuilder: (context, animation, secondary, child) {
          if (!VisualEffects.of(context).motion) return child;
          final t = CurvedAnimation(parent: animation, curve: AppMotion.curve);
          return FadeTransition(
            opacity: t,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(t),
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.98, end: 1).animate(t),
                child: child,
              ),
            ),
          );
        },
      );
}

/// A worklist row that pops and strikes through when checked. Used for the
/// action worklist on the result screen; the checkbox semantics stay exactly
/// those of a [CheckboxListTile].
class AnimatedCheckTile extends StatelessWidget {
  const AnimatedCheckTile({
    super.key,
    required this.checked,
    required this.onChanged,
    required this.title,
    this.subtitle,
    this.leading,
  });

  final bool checked;
  final ValueChanged<bool> onChanged;
  final Widget title;
  final Widget? subtitle;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final fx = VisualEffects.of(context);
    final d = fx.scale(const Duration(milliseconds: 220));
    return Semantics(
      checked: checked,
      child: InkWell(
        borderRadius: BorderRadius.circular(Gap.radiusSm),
        onTap: () => onChanged(!checked),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: Gap.sm,
              horizontal: Gap.xs,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (leading != null) ...[
                  leading!,
                  const SizedBox(width: Gap.sm),
                ],
                AnimatedScale(
                  scale: checked ? 1.0 : 0.92,
                  duration: d,
                  curve: Curves.easeOutBack,
                  child: AnimatedContainer(
                    duration: d,
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: checked ? AppColors.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: checked
                            ? AppColors.primary
                            : AppColors.lineStrong,
                        width: 1.6,
                      ),
                    ),
                    child: checked
                        ? const Icon(
                            Icons.check_rounded,
                            size: 18,
                            color: Colors.white,
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: AnimatedDefaultTextStyle(
                    duration: d,
                    style: AppType.body.copyWith(
                      color: checked ? AppColors.inkFaint : AppColors.ink,
                      decoration: checked
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                      decorationColor: AppColors.inkFaint,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        title,
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          DefaultTextStyle.merge(
                            style: AppType.caption.copyWith(
                              decoration: TextDecoration.none,
                            ),
                            child: subtitle!,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
