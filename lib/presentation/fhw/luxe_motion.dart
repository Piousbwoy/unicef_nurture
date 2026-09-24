/// Luxe motion primitives for the FHW flow — the choreography layer.
///
/// Every primitive here is gated first, animated second: under the OS
/// reduced-motion setting or the user's Lite mode ([VisualEffects.of]) each
/// widget renders its exact final frame with no tweens. None of these carry
/// meaning that is lost when motion is off.
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/fhw_luxe.dart';
import '../../core/theme/glass.dart';

/// Orchestrated entrance: children rise 24px and fade in on the directive's
/// staggered ease-out-cubic intervals. A single controller drives every
/// child; items beyond index 6 skip the delay and share the tail of the
/// curve, so long decks never wait for the last card.
class StaggeredEntrance extends StatefulWidget {
  const StaggeredEntrance({super.key, required this.children});

  final List<Widget> children;

  @override
  State<StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<StaggeredEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (VisualEffects.of(context).motion) {
      if (!_c.isAnimating && _c.value < 1) _c.forward();
    } else {
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Animation<double> _of(int i) {
    if (i > 6) return CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    final begin = (i * 0.08).clamp(0.0, 0.52);
    final end = (0.6 + i * 0.08).clamp(begin + 0.08, 1.0);
    return CurvedAnimation(
      parent: _c,
      curve: Interval(begin, end, curve: Curves.easeOutCubic),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, _) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          _EntranceItem(animation: _of(i), child: widget.children[i]),
      ],
    ),
  );
}

class _EntranceItem extends StatelessWidget {
  const _EntranceItem({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: animation.value,
    child: Transform.translate(
      offset: Offset(0, 24 * (1 - animation.value)),
      child: child,
    ),
  );
}

/// A live dot with a breathing aura — the real-time sync signal. Scales
/// 1.0 → 1.2 every 2s when motion is on; a static dot otherwise.
class BreathingDot extends StatefulWidget {
  const BreathingDot({
    super.key,
    this.size = 8,
    this.colour = FhwLuxePalette.emeraldPulse,
    this.haloColour,
  });

  final double size;
  final Color colour;
  final Color? haloColour;

  @override
  State<BreathingDot> createState() => _BreathingDotState();
}

class _BreathingDotState extends State<BreathingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(BreathingDot old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (VisualEffects.of(context).motion) {
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
  Widget build(BuildContext context) {
    final halo = widget.haloColour ?? widget.colour;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final t = _c.value;
          final breathe = 1.0 + 0.2 * (t < 0.5 ? t : 1 - t);
          return SizedBox(
            width: widget.size * 2.4,
            height: widget.size * 2.4,
            child: Center(
              child: Container(
                width: widget.size * breathe,
                height: widget.size * breathe,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.colour,
                  boxShadow: [
                    BoxShadow(
                      color: halo.withValues(alpha: 0.35 + 0.25 * (1 - breathe)),
                      blurRadius: widget.size * (1.6 + 1.2 * (breathe - 1)),
                      spreadRadius: widget.size * 0.15 * (breathe - 1),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A catch-light sheen that sweeps across its child a bounded number of
/// times on mount and then settles — the micro-shimmer on the hero action.
/// Static (plain child) when motion is off.
class ShimmerCatchlight extends StatefulWidget {
  const ShimmerCatchlight({
    super.key,
    required this.child,
    this.loops = 3,
    this.radius = Gap.radiusSm,
  });

  final Widget child;
  final int loops;
  final double radius;

  @override
  State<ShimmerCatchlight> createState() => _ShimmerCatchlightState();
}

class _ShimmerCatchlightState extends State<ShimmerCatchlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  int _sweeps = 0;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener(_onStatus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (VisualEffects.of(context).motion) {
      if (!_c.isAnimating && _sweeps < widget.loops) _c.forward(from: 0);
    } else {
      _c.stop();
      _c.value = 0;
      _sweeps = widget.loops;
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    _sweeps++;
    if (_sweeps < widget.loops) {
      _c.forward(from: 0);
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _c.removeStatusListener(_onStatus);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_sweeps >= widget.loops) return widget.child;
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  final x = -1.6 + 3.2 * _c.value;
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment(x - 0.35, 0),
                        end: Alignment(x, 0),
                        colors: [
                          Colors.white.withValues(alpha: 0),
                          Colors.white.withValues(alpha: 0.34),
                          Colors.white.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The gliding selection pill behind the dock's active tab. Placed as a
/// direct child of a [Stack]; animates its left edge slot-to-slot so the
/// highlight appears to magnetize to the tapped icon. With motion off it
/// jumps instantly.
class MagneticPill extends StatelessWidget {
  const MagneticPill({super.key, required this.index, required this.slotWidth});

  final int index;
  final double slotWidth;

  @override
  Widget build(BuildContext context) {
    final fx = VisualEffects.of(context);
    return AnimatedPositioned(
      duration: fx.scale(const Duration(milliseconds: 240)),
      curve: Curves.easeOutCubic,
      left: index * slotWidth + 4,
      top: 8,
      bottom: 8,
      width: slotWidth - 8,
      child: Container(
        decoration: BoxDecoration(
          gradient: FhwLuxePalette.sapphireCardGlow,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: Color(0x331B56DB),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
      ),
    );
  }
}
