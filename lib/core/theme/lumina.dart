/// LUMINA — the app's luxury language: light through deep water.
///
/// Every surface is luminous pearl-white; every drop of blue is energy that
/// lives *under* the glass, not painted on top of it. Depth comes from
/// blue-tinted shadow pairs and a single specular hairline per card — never
/// grey, never a hard border. Motion is liquid: long release curves with a
/// small overshoot, staggered reveals, nothing that snaps.
///
/// When urgency arrives the interface *dives*: the pearl world sinks into
/// deep sapphire and the cards read as lit from within. Urgency is never a
/// red alert bolted onto a bright screen; it is a change of depth.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'glass.dart';

abstract final class Lumina {
  // ── The sapphire scale — energy ─────────────────────────────────────────
  static const abyss = Color(0xFF040E1F); // the dive floor
  static const deep = Color(0xFF0A1931); // == twilightMidnight, the dive
  static const navy = Color(0xFF132B50); // raised dark surface
  static const core = Color(0xFF1B56DB); // brand sapphire
  static const azure = Color(0xFF2563EB); // interactive blue
  static const bright = Color(0xFF3B82F6); // active / glow source
  static const glow = Color(0xFF7FA9FF); // blue that passes AA on navy
  static const tint = Color(0xFFE8F0FE); // quiet blue fill on pearl
  static const ice = Color(0xFFF2F7FF); // the coolest wash

  // ── The pearl scale — light ─────────────────────────────────────────────
  static const pearl = Color(0xFFFFFFFF); // raised cards
  static const nacre = Color(0xFFFBFDFF); // hero canvases
  static const mist = Color(0xFFF4F8FE); // sunken wells
  static const canvas = Color(0xFFF6F9FD); // app background

  // ── Ink — always blue, never black, never grey ─────────────────────────
  static const ink = Color(0xFF0A1931);
  static const inkMuted = Color(0xFF44608A); // body copy on pearl (AA)
  static const inkFaint = Color(0xFF8AA0BC); // chrome only, never a sentence

  /// Ink for the dive world: pearl text sunk on abyss, and its muted pair.
  static const diveInk = Color(0xFFDCE9FF);
  static const diveMuted = Color(0xFF8FB0DC);

  // ── Hairlines and edges ─────────────────────────────────────────────────
  /// The gradient of a card's 1px edge: sapphire light catching the top-left
  /// rim, fading to a whisper before the bottom-right.
  static const edgeGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x2E1B56DB), Color(0x14FFFFFF), Color(0x0F0A1931)],
    stops: [0.0, 0.45, 1.0],
  );

  /// A top-only specular line: the flash of light along a glass rim.
  static const specular = LinearGradient(
    colors: [Colors.transparent, Color(0x9FFFFFFF), Colors.transparent],
  );

  // ── Shadow pairs — blue-tinted, always two layers ──────────────────────
  static const lift = [
    BoxShadow(color: Color(0x140A2A5A), blurRadius: 40, offset: Offset(0, 16)),
    BoxShadow(color: Color(0x0D0A2A5A), blurRadius: 12, offset: Offset(0, 3)),
  ];
  static const liftQuiet = [
    BoxShadow(color: Color(0x0F0A2A5A), blurRadius: 24, offset: Offset(0, 10)),
  ];
  static const aura = BoxShadow(
    color: Color(0x332563EB),
    blurRadius: 28,
    offset: Offset(0, 10),
  );

  // ── Gradients ───────────────────────────────────────────────────────────
  /// The brand tide: deep sapphire into open blue, used on filled controls.
  static const tide = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [core, Color(0xFF2E6FE8), azure],
  );

  /// The dive: what the whole interface sinks to under an alarm.
  static const dive = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [deep, abyss],
  );

  /// Pearl sheet: the faintest blue wash top-to-bottom behind content.
  static const sheen = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [nacre, canvas],
  );

  // ── Radii — one soft monolith family ────────────────────────────────────
  static const rSm = 16.0;
  static const rMd = 22.0;
  static const rLg = 30.0;
  static const rXl = 38.0;

  // ── Motion — liquid ─────────────────────────────────────────────────────
  /// Long release with a breath of overshoot: water settling, not a click.
  static const liquid = Cubic(0.22, 1.12, 0.28, 1.0);
  /// Pure deceleration for entrances.
  static const glide = Cubic(0.16, 1.0, 0.3, 1.0);
  static const quick = Duration(milliseconds: 180);
  static const standard = Duration(milliseconds: 320);
  static const slow = Duration(milliseconds: 520);

  // ── Typography — razor rules ────────────────────────────────────────────
  /// Display type gets tighter tracking as it grows; micro labels get wide
  /// letterspacing. Sora is the only bundled display face (weights 400-800).
  static TextStyle display(double size, {Color color = ink, int weight = 800}) =>
      TextStyle(
        fontFamily: 'Sora',
        fontSize: size,
        fontWeight: FontWeight.values[weight ~/ 100 - 1],
        height: size >= 24 ? 1.12 : 1.22,
        letterSpacing: size >= 28 ? -1.2 : size >= 22 ? -0.7 : -0.3,
        color: color,
      );

  static TextStyle body({double size = 14.5, Color color = inkMuted, int weight = 500}) =>
      TextStyle(
        fontSize: size,
        fontWeight: FontWeight.values[weight ~/ 100 - 1],
        height: 1.5,
        color: color,
      );

  static TextStyle micro({Color color = inkFaint, int weight = 800}) =>
      TextStyle(
        fontSize: 9.5,
        fontWeight: FontWeight.values[weight ~/ 100 - 1],
        letterSpacing: 1.6,
        height: 1.35,
        color: color,
      );
}

/// Tells the subtree it is living in the dive: an alarm dropped the pearl
/// canvas into deep sapphire, and surfaces should read as lit instruments.
class LumeField extends InheritedWidget {
  const LumeField({
    super.key,
    required this.lume,
    required super.child,
  });

  final bool lume;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LumeField>()?.lume ?? false;

  @override
  bool updateShouldNotify(LumeField oldWidget) => oldWidget.lume != lume;
}

/// An uppercase micro label — the only "small caps" the language allows.
class MicroLabel extends StatelessWidget {
  const MicroLabel(this.text, {super.key, this.color, this.icon});

  final String text;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final ink = color ?? Lumina.inkFaint;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: ink.withValues(alpha: 0.8)),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            text.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Lumina.micro(color: ink),
          ),
        ),
      ],
    );
  }
}

/// A pearl glass card: white fill, gradient hairline edge, blue shadow pair,
/// and an optional specular rim. The workhorse surface of the language.
class LumenCard extends StatelessWidget {
  const LumenCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = Lumina.rLg,
    this.fill = Lumina.pearl,
    this.shadow = Lumina.lift,
    this.specular = true,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color fill;
  final List<BoxShadow> shadow;
  final bool specular;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fx = VisualEffects.of(context);
    final shape = BorderRadius.circular(radius);
    Widget content = Padding(padding: padding, child: child);
    if (onTap != null) {
      content = InkWell(borderRadius: shape, onTap: onTap, child: content);
    }
    return Container(
      decoration: BoxDecoration(
        borderRadius: shape,
        gradient: Lumina.edgeGradient,
        boxShadow: fx.blur ? shadow : const [],
      ),
      padding: const EdgeInsets.all(1.1),
      child: Material(
        color: fill,
        borderRadius: shape,
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            if (specular && fx.blur)
              const Positioned(
                top: 0,
                left: 22,
                right: 22,
                child: IgnorePointer(
                  child: SizedBox(
                    height: 1.2,
                    child: DecoratedBox(
                      decoration: BoxDecoration(gradient: Lumina.specular),
                    ),
                  ),
                ),
              ),
            content,
          ],
        ),
      ),
    );
  }
}

/// A titled pearl section: micro eyebrow, razor display title, content.
/// The standard block of the tab pages — one margin, one voice.
class LumeSection extends StatelessWidget {
  const LumeSection({
    super.key,
    required this.title,
    required this.child,
    this.eyebrow,
    this.padding = const EdgeInsets.all(20),
  });

  final String title;
  final Widget child;
  final String? eyebrow;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: LumenCard(
      radius: Lumina.rMd,
      shadow: Lumina.liftQuiet,
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (eyebrow != null) ...[
            MicroLabel(eyebrow!),
            const SizedBox(height: 6),
          ],
          Text(title, style: Lumina.display(17)),
          const SizedBox(height: 14),
          child,
        ],
      ),
    ),
  );
}

/// A filled sapphire control. The press dips and the aura tightens; the label
/// promises the outcome, never a process.
class SapphireButton extends StatefulWidget {
  const SapphireButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = false,
    this.radius,
    this.dense = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;
  final double? radius;
  final bool dense;

  @override
  State<SapphireButton> createState() => _SapphireButtonState();
}

class _SapphireButtonState extends State<SapphireButton> {
  bool _pressed = false;

  bool get _live => widget.onPressed != null;

  @override
  Widget build(BuildContext context) {
    final fx = VisualEffects.of(context);
    final radius = BorderRadius.circular(widget.radius ?? 999);
    final content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.icon != null) ...[
          Icon(widget.icon, size: 18, color: Colors.white),
          const SizedBox(width: 9),
        ],
        Flexible(
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Sora',
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.1,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
    return Semantics(
      button: true,
      enabled: _live,
      label: widget.label,
      child: GestureDetector(
        onTapDown: _live ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: _live ? () => setState(() => _pressed = false) : null,
        onTapUp: _live ? (_) => setState(() => _pressed = false) : null,
        onTap: widget.onPressed,
        child: AnimatedScale(
          duration: fx.scale(Lumina.quick),
          curve: Lumina.liquid,
          scale: _pressed && fx.motion ? 0.975 : 1,
          child: AnimatedContainer(
            duration: fx.scale(Lumina.quick),
            curve: Lumina.glide,
            padding: EdgeInsets.symmetric(
              horizontal: widget.dense ? 16 : 22,
              vertical: widget.dense ? 11 : 15,
            ),
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: Lumina.tide,
              boxShadow: fx.blur
                  ? [
                      BoxShadow(
                        color: Lumina.azure.withValues(
                          alpha: _pressed ? 0.48 : 0.30,
                        ),
                        blurRadius: _pressed ? 34 : 24,
                        offset: const Offset(0, 10),
                      ),
                    ]
                  : const [],
            ),
            width: widget.expand ? double.infinity : null,
            child: Opacity(
              opacity: _live ? 1 : 0.45,
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

/// A quiet pearl pill for secondary actions: sapphire ink on a glass chip.
class GhostPill extends StatelessWidget {
  const GhostPill({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.selected = false,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final fx = VisualEffects.of(context);
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onPressed,
        child: AnimatedContainer(
          duration: fx.scale(Lumina.quick),
          curve: Lumina.glide,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: selected ? Lumina.azure : Lumina.pearl,
            border: Border.all(
              color: selected
                  ? Colors.transparent
                  : Lumina.core.withValues(alpha: 0.16),
            ),
            boxShadow: fx.blur && !selected ? Lumina.liftQuiet : const [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 15,
                  color: selected
                      ? Colors.white
                      : Lumina.inkMuted.withValues(alpha: 0.9),
                ),
                const SizedBox(width: 7),
              ],
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Sora',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                  color: selected ? Colors.white : Lumina.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The tide line: progress as a thin sapphire waterline with a glow head,
/// replacing every chunky progress bar.
class TideProgress extends StatelessWidget {
  const TideProgress({
    super.key,
    required this.fraction,
    this.height = 3,
    this.color = Lumina.azure,
  });

  final double fraction;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final fx = VisualEffects.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 200.0;
        return TweenAnimationBuilder<double>(
          tween: Tween(end: fraction.clamp(0.0, 1.0)),
          duration: fx.scale(Lumina.slow),
          curve: Lumina.glide,
          builder: (context, t, _) => SizedBox(
            height: height,
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(height),
                      color: Lumina.core.withValues(alpha: 0.10),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: width * t,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(height),
                      gradient: LinearGradient(
                        colors: [
                          color.withValues(alpha: 0.55),
                          color,
                          Colors.white.withValues(alpha: 0.9),
                        ],
                      ),
                      boxShadow: fx.blur
                          ? [
                              BoxShadow(
                                color: color.withValues(alpha: 0.55),
                                blurRadius: 8,
                              ),
                            ]
                          : const [],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Entrance choreography: content rises a few pixels into full opacity after
/// [order] * 45ms. With motion off it simply appears.
class StaggerReveal extends StatefulWidget {
  const StaggerReveal({
    super.key,
    required this.child,
    this.order = 0,
    this.rise = 14,
  });

  final Widget child;
  final int order;
  final double rise;

  @override
  State<StaggerReveal> createState() => _StaggerRevealState();
}

class _StaggerRevealState extends State<StaggerReveal> {
  bool _shown = false;
  Timer? _timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_shown) return;
    final fx = VisualEffects.of(context);
    if (!fx.motion) {
      _shown = true;
      return;
    }
    _timer = Timer(
      Duration(milliseconds: 45 * widget.order.clamp(0, 8) + 16),
      () {
        if (mounted) setState(() => _shown = true);
      },
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fx = VisualEffects.of(context);
    return AnimatedOpacity(
      duration: fx.scale(Lumina.standard),
      curve: Lumina.glide,
      opacity: _shown ? 1 : 0,
      child: AnimatedSlide(
        duration: fx.scale(Lumina.slow),
        curve: Lumina.liquid,
        offset: _shown ? Offset.zero : Offset(0, widget.rise / 64),
        child: widget.child,
      ),
    );
  }
}

/// The background of the pearl world: the faintest sapphire auras drifting at
/// the top of the canvas, so white is never flat.
class LumenAura extends StatelessWidget {
  const LumenAura({super.key, required this.child, this.intensity = 1});

  final Widget child;
  final double intensity;

  @override
  Widget build(BuildContext context) {
    final fx = VisualEffects.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: Lumina.sheen,
        boxShadow: fx.blur
            ? [
                BoxShadow(
                  color: Lumina.bright.withValues(alpha: 0.10 * intensity),
                  blurRadius: 90,
                  offset: const Offset(-40, -50),
                  spreadRadius: 30,
                ),
                BoxShadow(
                  color: Lumina.core.withValues(alpha: 0.07 * intensity),
                  blurRadius: 110,
                  offset: const Offset(120, -30),
                  spreadRadius: 10,
                ),
              ]
            : const [],
      ),
      child: child,
    );
  }
}
