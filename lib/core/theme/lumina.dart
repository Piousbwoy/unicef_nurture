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
import 'dart:ui' show ImageFilter;

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

  /// The two whites every hero card writes with: body copy and iconography.
  static const diveSoft = Color(0xD9FFFFFF);
  static const diveSoftIcon = Color(0xE6FFFFFF);

  // ── Hairlines and edges ─────────────────────────────────────────────────
  /// A top-only specular line: the flash of light along a glass rim.
  static const specular = LinearGradient(
    colors: [Colors.transparent, Color(0x9FFFFFFF), Colors.transparent],
  );

  // ── Shadow pairs — blue-tinted, always two layers ──────────────────────
  static const liftQuiet = [
    BoxShadow(color: Color(0x0F0A2A5A), blurRadius: 24, offset: Offset(0, 10)),
  ];
  static const aura = BoxShadow(
    color: Color(0x332563EB),
    blurRadius: 28,
    offset: Offset(0, 10),
  );

  /// The shadow a hero card throws on the pearl canvas: midnight, not grey.
  static const diveLift = [
    BoxShadow(color: Color(0x40040E1F), blurRadius: 30, offset: Offset(0, 14)),
    BoxShadow(color: Color(0x1A0A1931), blurRadius: 10, offset: Offset(0, 3)),
  ];

  /// Shade falling from a dive well's top rim into its floor.
  static const wellShade = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.center,
    colors: [Color(0x40040E1F), Color(0x00040E1F)],
  );

  /// The lifted light along a dive well's bottom lip.
  static const wellLight = LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.center,
    colors: [Color(0x26FFFFFF), Color(0x00FFFFFF)],
  );

  /// Frost: the ice a chip wears over the dive.
  static const frost = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x2EFFFFFF), Color(0x12FFFFFF)],
  );

  // ── Gradients ───────────────────────────────────────────────────────────
  /// The hero dive: the check-hero blue that every card in the caregiver
  /// flow now wears — midnight sapphire at the top-left running into open
  /// light at the bottom-right.
  static const hero = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0C2B73), core, bright],
  );

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
  /// Color stays null unless pinned so text reads correctly on both the
  /// pearl canvas and a dive card: unstyled text inherits the ground it
  /// stands on (DefaultTextStyle), explicit colors override it.
  static TextStyle display(double size, {Color? color, int weight = 800}) =>
      TextStyle(
        fontFamily: 'Sora',
        fontSize: size,
        fontWeight: FontWeight.values[weight ~/ 100 - 1],
        height: size >= 24 ? 1.12 : 1.22,
        letterSpacing: size >= 28
            ? -1.2
            : size >= 22
            ? -0.7
            : -0.3,
        color: color,
      );

  static TextStyle body({double size = 14.5, Color? color, int weight = 500}) =>
      TextStyle(
        fontSize: size,
        fontWeight: FontWeight.values[weight ~/ 100 - 1],
        height: 1.5,
        color: color,
      );

  static TextStyle micro({Color? color, int weight = 800}) => TextStyle(
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
  const LumeField({super.key, required this.lume, required super.child});

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
    final ink = color ?? Lumina.glow;
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

/// A hero card: the check-hero dive gradient under a white hairline, lit by a
/// specular rim, throwing a midnight shadow on the pearl canvas. Text and
/// icons inherit the dive whites unless a call site says otherwise. When
/// tappable it answers the thumb: the card takes the press as a scale down
/// and the lift drains away, so releasing feels like surfacing.
/// A card in one of two grounds. `hero: true` is the dive: the sapphire
/// gradient with a specular rim and a midnight shadow, reserved for the one
/// primary card a screen wants you to feel. The default is pearl: a white
/// sheet with a hairline edge and a quiet lift, ink on light — the resting
/// surface everything else reads on. Balance is the point: a page of hero
/// cards is noise; one hero among pearls is an accent. When tappable the
/// card answers the thumb: it takes the press as a scale down and the lift
/// drains away, so releasing feels like surfacing.
class LumenCard extends StatefulWidget {
  const LumenCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = Lumina.rLg,
    this.specular = true,
    this.hero = false,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool specular;
  final bool hero;
  final VoidCallback? onTap;

  @override
  State<LumenCard> createState() => _LumenCardState();
}

class _LumenCardState extends State<LumenCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final fx = VisualEffects.of(context);
    final hero = widget.hero;
    final shape = BorderRadius.circular(widget.radius);
    Widget content = Padding(padding: widget.padding, child: widget.child);
    if (widget.onTap != null) {
      content = InkWell(
        borderRadius: shape,
        onTap: widget.onTap,
        onHighlightChanged: (h) => setState(() => _pressed = h),
        child: content,
      );
    }
    final sunk = _pressed && widget.onTap != null;
    content = LumeField(
      lume: hero,
      child: DefaultTextStyle.merge(
        style: TextStyle(color: hero ? Lumina.diveSoft : Lumina.ink),
        child: hero
            ? ListTileTheme(
                data: const ListTileThemeData(
                  textColor: Lumina.diveSoft,
                  iconColor: Lumina.diveSoftIcon,
                ),
                child: Theme(
                  data: Theme.of(context).copyWith(
                    filledButtonTheme: FilledButtonThemeData(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Lumina.core,
                      ),
                    ),
                    textButtonTheme: TextButtonThemeData(
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                      ),
                    ),
                    outlinedButtonTheme: OutlinedButtonThemeData(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                    checkboxTheme: CheckboxThemeData(
                      fillColor: WidgetStateProperty.resolveWith(
                        (s) => s.contains(WidgetState.selected)
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.12),
                      ),
                      checkColor: WidgetStateProperty.all(Lumina.core),
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                  child: IconTheme(
                    data: const IconThemeData(color: Lumina.diveSoftIcon),
                    child: content,
                  ),
                ),
              )
            : content,
      ),
    );
    return AnimatedScale(
      duration: fx.scale(Lumina.quick),
      curve: Lumina.liquid,
      scale: sunk && fx.motion ? 0.985 : 1,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: shape,
          gradient: hero ? Lumina.hero : null,
          color: hero ? null : Lumina.pearl,
          border: Border.all(
            color: hero
                ? Colors.white.withValues(alpha: 0.14)
                : const Color(0xFFE2EBF5),
          ),
          boxShadow: fx.blur
              ? sunk
                    ? const []
                    : hero
                    ? Lumina.diveLift
                    : Lumina.liftQuiet
              : const [],
        ),
        child: Material(
          color: sunk
              ? (hero ? const Color(0x14FFFFFF) : const Color(0x080A1931))
              : Colors.transparent,
          borderRadius: shape,
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              if (hero && widget.specular && fx.blur)
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
      ),
    );
  }
}

/// A titled section: micro eyebrow, razor display title, content. The
/// standard block of the tab pages — one margin, one voice. Pearl by
/// default; `hero: true` puts the sapphire gradient on it for the one
/// section a page leads with.
class LumeSection extends StatelessWidget {
  const LumeSection({
    super.key,
    required this.title,
    required this.child,
    this.eyebrow,
    this.hero = false,
    this.padding = const EdgeInsets.all(20),
  });

  final String title;
  final Widget child;
  final String? eyebrow;
  final bool hero;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: LumenCard(
      hero: hero,
      radius: Lumina.rMd,
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (eyebrow != null) ...[
            MicroLabel(eyebrow!, color: hero ? Lumina.glow : Lumina.core),
            const SizedBox(height: 6),
          ],
          Text(
            title,
            style: Lumina.display(17, color: hero ? Colors.white : Lumina.ink),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    ),
  );
}

/// A sunken well inside a card: content pressed *into* the surface. On a
/// hero card it is a dive well — translucent ice with a midnight shade from
/// the top rim and lifted light on the bottom lip. On a pearl card it reads
/// as mist: a quiet blue-grey recess with a hairline. It senses the ground
/// through [LumeField], so call sites never branch.
class LumeWell extends StatelessWidget {
  const LumeWell({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = Lumina.rSm,
    this.fill = const Color(0x14FFFFFF),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    final fx = VisualEffects.of(context);
    final dive = LumeField.of(context);
    final shape = BorderRadius.circular(radius);
    final floor = dive
        ? fill
        : (fill == const Color(0x14FFFFFF) ? Lumina.mist : fill);
    return Container(
      decoration: BoxDecoration(
        borderRadius: shape,
        color: floor,
        border: Border.all(
          color: dive
              ? Colors.white.withValues(alpha: 0.10)
              : const Color(0xFFE2EBF5),
        ),
      ),
      child: ClipRRect(
        borderRadius: shape,
        child: Stack(
          children: [
            if (dive && fx.blur) ...[
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 22,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(gradient: Lumina.wellShade),
                  ),
                ),
              ),
              const Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: 22,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(gradient: Lumina.wellLight),
                  ),
                ),
              ),
            ],
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }
}

/// A frosted glass chip for the dive world: real backdrop blur when the
/// device allows it, the same translucent silhouette when it doesn't. The
/// ice that makes hero pills feel like they float a hair above the water.
class LumeFrost extends StatelessWidget {
  const LumeFrost({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    this.radius = 999,
    this.sigma = 12,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double sigma;

  @override
  Widget build(BuildContext context) {
    final fx = VisualEffects.of(context);
    final shape = BorderRadius.circular(radius);
    final chip = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: shape,
        gradient: Lumina.frost,
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: child,
    );
    if (!fx.blur) return chip;
    return ClipRRect(
      borderRadius: shape,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: chip,
      ),
    );
  }
}

/// A status dot that breathes: a few slow tides of glow when it first
/// arrives, then a calm, steady point. It draws the eye once and never
/// taxes a slow phone (or a settling test pump) with an eternal pulse.
class LumePulse extends StatefulWidget {
  const LumePulse({super.key, required this.color, this.size = 8});

  final Color color;
  final double size;

  @override
  State<LumePulse> createState() => _LumePulseState();
}

class _LumePulseState extends State<LumePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  );
  bool _started = false;
  bool _rested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started || _c.isAnimating) return;
    _started = true;
    if (!VisualEffects.of(context).motion) {
      _rested = true;
      return;
    }
    _breathe(4);
  }

  Future<void> _breathe(int cycles) async {
    for (var i = 0; i < cycles; i++) {
      if (!mounted) return;
      await _c.forward();
      if (!mounted) return;
      await _c.reverse();
    }
    if (mounted) setState(() => _rested = true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fx = VisualEffects.of(context);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _rested ? 0.0 : Curves.easeInOut.transform(_c.value);
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
            boxShadow: fx.blur
                ? [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.50 - 0.30 * t),
                      blurRadius: 10 + 12 * t,
                      spreadRadius: 1 + 5 * t,
                    ),
                  ]
                : const [],
          ),
        );
      },
    );
  }
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
          Icon(widget.icon, size: 18, color: Lumina.core),
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
              color: Lumina.core,
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
              color: _pressed ? Lumina.tint : Lumina.pearl,
              boxShadow: fx.blur
                  ? [
                      BoxShadow(
                        color: Lumina.abyss.withValues(
                          alpha: _pressed ? 0.42 : 0.26,
                        ),
                        blurRadius: _pressed ? 30 : 20,
                        offset: const Offset(0, 10),
                      ),
                    ]
                  : const [],
            ),
            width: widget.expand ? double.infinity : null,
            child: Opacity(opacity: _live ? 1 : 0.45, child: content),
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
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Sora',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
                    color: selected ? Colors.white : Lumina.ink,
                  ),
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
