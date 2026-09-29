/// LUMEN — a Material & Light engine.
///
/// The canvas is two colours and two colours only: Luxury White and Luxury
/// Blue. Here they are not hex codes, they are *substances and light*.
///
///  * Luxury White is carved **alabaster** (matte, top-lit, cool bounce),
///    frosted **aerospace glass** (refraction rim, caustic edge) and
///    luminescent **pearl** (an iridescent sheen that rides a light angle).
///  * Luxury Blue is **liquid sapphire** (deep, translucent, lit from within),
///    **bioluminescent cobalt** (an emissive bloom — the only true light
///    source on the page) and **glacial ice** (a pale, cold secondary plane).
///
/// Depth is chiaroscuro: a single warm-neutral key, a soft ambient fill and a
/// cool bounce, so a surface does not merely sit on the page, it is *lit* by
/// it. Rhythm follows the golden section, not a base-8 grid, for museum-grade
/// asymmetric negative space. Type is monolithic — Sora ExtraBold carrying
/// tight, negative kerning, used as structural art before it is used as text.
///
/// Every surface degrades honestly. Under the OS reduced-motion flag or the
/// user's Lite mode ([VisualEffects.of]) the frosted refraction and the
/// breathing light resolve to their exact resting frame: the Sanctuary is
/// brighter on a low-end handset, never emptier. Nothing loops without a
/// motion gate, so widget tests that disable animations always settle.
library;

import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'fhw_luxe.dart';
import 'glass.dart';

// ─── Golden-ratio rhythm ────────────────────────────────────────────────────

/// Spacing and layout ratios derived from φ, not a base-8 grid. The point of a
/// golden scale is that no two intervals feel equal — negative space becomes
/// deliberate, and a composition divides at the golden section rather than the
/// midpoint. Values are the Fibonacci ladder nearest the existing [Gap] tokens
/// so this coexists with them.
abstract final class Lux {
  static const double phi = 1.6180339887;

  static const double xs = 8;
  static const double sm = 13;
  static const double md = 21;
  static const double lg = 34;
  static const double xl = 55;
  static const double xxl = 89;

  /// A plane divided by the golden section — the far segment.
  static const double major = 0.618;

  /// The near segment of the same division.
  static const double minor = 0.382;

  /// Carved surfaces use generous, asymmetric breathing room.
  static const EdgeInsets gallery = EdgeInsets.fromLTRB(md, lg, md, lg);
}

// ─── The materials, as paint ────────────────────────────────────────────────

/// Named physical substances. Whites are lit top-to-bottom and cool at the
/// base (alabaster under a north window); blues are lit from within (sapphire
/// with a light source trapped inside it).
abstract final class Lumen {
  // — Luxury White as matter —

  /// Carved matte alabaster: near-white at the crown easing to a cool grey
  /// foot, so a flat sheet reads as a solid you could run a hand across.
  static const LinearGradient alabaster = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFFFFF), Color(0xFFF3F6FB), Color(0xFFE9EEF7)],
    stops: [0.0, 0.62, 1.0],
  );

  /// A brighter alabaster for surfaces that float highest above the field.
  static const LinearGradient alabasterRaised = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFFFFF), Color(0xFFF7FAFF)],
  );

  /// Luminescent pearl — the iridescent fill laid over type or a rim so white
  /// carries a cold blue-green shimmer, never a warm cream.
  static const LinearGradient pearl = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFEAF1FF),
      Color(0xFFFFFFFF),
      Color(0xFFDCE9FF),
      Color(0xFFF6FAFF),
    ],
    stops: [0.0, 0.34, 0.66, 1.0],
  );

  // — Luxury Blue as matter —

  /// Liquid sapphire: a deep, translucent royal body lit toward the top, the
  /// primary mass of a blue surface.
  static const LinearGradient sapphireLiquid = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF2E73FF), Color(0xFF1B56DB), Color(0xFF0D2E73)],
    stops: [0.0, 0.5, 1.0],
  );

  /// A darker, glassier sapphire for the deepest plane behind the light.
  static const LinearGradient sapphireDeepPool = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0C2350), Color(0xFF123E93), Color(0xFF1B56DB)],
  );

  /// Glacial ice — a pale, cold secondary surface, blue-white rather than the
  /// grey of the whites, so two "light" planes never look like one material.
  static const LinearGradient glacialIce = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFF2F7FF), Color(0xFFE3EEFF)],
  );

  /// Bioluminescent cobalt — the emissive bloom. A radial that starts as pure
  /// light and dissolves to transparent; the single source the page is lit by.
  static RadialGradient cobaltBloom({double alpha = 0.55}) => RadialGradient(
    colors: [
      FhwLuxePalette.sapphireElectric.withValues(alpha: alpha),
      FhwLuxePalette.sapphireRoyal.withValues(alpha: alpha * 0.35),
      Colors.transparent,
    ],
    stops: const [0.0, 0.5, 1.0],
  );

  /// The refraction rim of aerospace glass: a hairline that is bright where it
  /// catches the key and fades at the shadowed edge.
  static const LinearGradient refractionRim = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xB3FFFFFF), Color(0x22FFFFFF), Color(0x66FFFFFF)],
    stops: [0.0, 0.5, 1.0],
  );
}

// ─── Chiaroscuro light ──────────────────────────────────────────────────────

/// Layered shadows that behave like one lighting rig: a tight contact shade
/// (direct), a wide soft shade (ambient), and a cool blue bounce so a white
/// surface reflects the field it floats above.
abstract final class Chiaroscuro {
  /// A carved alabaster sheet resting on the page.
  static const List<BoxShadow> alabaster = [
    BoxShadow(color: Color(0x140B2A6B), blurRadius: 4, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x110B2A6B), blurRadius: 22, offset: Offset(0, 10)),
    BoxShadow(color: Color(0x0D1B56DB), blurRadius: 46, offset: Offset(0, 22)),
  ];

  /// The highest plane — the hero — lifted further and cooler.
  static const List<BoxShadow> raised = [
    BoxShadow(color: Color(0x1A0B2A6B), blurRadius: 8, offset: Offset(0, 4)),
    BoxShadow(color: Color(0x140B2A6B), blurRadius: 30, offset: Offset(0, 16)),
    BoxShadow(color: Color(0x121B56DB), blurRadius: 60, offset: Offset(0, 30)),
  ];

  /// Emissive halo around a lit sapphire surface.
  static List<BoxShadow> bloom(Color colour, {double alpha = 0.5}) => [
    BoxShadow(
      color: colour.withValues(alpha: alpha),
      blurRadius: 34,
      spreadRadius: -6,
      offset: const Offset(0, 12),
    ),
    BoxShadow(
      color: colour.withValues(alpha: alpha * 0.4),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];
}

// ─── The Sanctuary depth field ───────────────────────────────────────────────

/// A luminous field the surfaces float inside: a glacial vertical wash, cobalt
/// blooms placed at the golden section, and — when motion is permitted — a
/// slow drift so the light reads as alive without any element looping loudly.
/// This is the frosted backdrop's light source: [GlassSurface] blurs it.
class Sanctum extends StatefulWidget {
  const Sanctum({
    super.key,
    required this.child,
    this.focus = Alignment.topCenter,
  });

  final Widget child;

  /// Where the strongest bloom sits — usually near the hero.
  final Alignment focus;

  @override
  State<Sanctum> createState() => _SanctumState();
}

class _SanctumState extends State<Sanctum> with SingleTickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 26),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Only a real, permitted motion context starts the drift; Lite mode and
    // reduced-motion (and every widget test, which disables animations) render
    // the single resting frame.
    if (VisualEffects.of(context).motion) {
      if (!_drift.isAnimating) _drift.repeat();
    } else {
      _drift.stop();
      _drift.value = 0;
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _drift,
            builder: (context, _) => CustomPaint(
              painter: _DepthPainter(t: _drift.value, focus: widget.focus),
            ),
          ),
        ),
        // Motion off: the animated builder above already sits at its resting
        // t, so the field renders as one still frame with nothing extra.
        widget.child,
      ],
    );
  }
}

class _DepthPainter extends CustomPainter {
  const _DepthPainter({required this.t, required this.focus});

  final double t;
  final Alignment focus;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Cold vertical base — glacial, never the warm ivory canvas.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF9FBFF), Color(0xFFEDF3FC), Color(0xFFE5EEFA)],
        ).createShader(Offset.zero & size),
    );

    void bloom(Offset c, double r, double alpha) {
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            FhwLuxePalette.sapphireElectric.withValues(alpha: alpha),
            FhwLuxePalette.sapphireRoyal.withValues(alpha: alpha * 0.4),
            Colors.transparent,
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: r));
      canvas.drawCircle(c, r, paint);
    }

    // The key bloom, near the focus, drifting a hair over its long period.
    final fx = (focus.x * 0.5 + 0.5);
    final fy = (focus.y * 0.5 + 0.5);
    final drift = math.sin(t * 2 * math.pi) * 0.02;
    bloom(
      Offset(w * (0.28 + fx * 0.4 + drift), h * (0.14 + fy * 0.2)),
      w * 0.72,
      0.16,
    );
    // A cool fill bloom low-left so the bottom of the page is lit, not flat.
    bloom(Offset(w * 0.12, h * 0.82 - drift * w), w * 0.6, 0.10);
    // A faint pearl lift top-right — the bounce light.
    bloom(Offset(w * 0.92, h * 0.04), w * 0.5, 0.06);
  }

  @override
  bool shouldRepaint(_DepthPainter old) => old.t != t || old.focus != focus;
}

// ─── Carved alabaster sheet ─────────────────────────────────────────────────

/// The primary white surface: a solid of carved matte alabaster, top-lit, with
/// a refraction rim and a cool bounce beneath. Not glass, not a flat card —
/// stone that has been lit.
class AlabasterSheet extends StatelessWidget {
  const AlabasterSheet({
    super.key,
    required this.child,
    this.radius = Gap.radiusLg,
    this.padding,
    this.raised = false,
    this.blur = false,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;

  /// The highest plane gets the deeper chiaroscuro.
  final bool raised;

  /// Aerospace variant: a real backdrop blur over the [Sanctum].
  final bool blur;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    final fx = VisualEffects.of(context);
    final blurOn = blur && fx.blur;

    final sheet = DecoratedBoxTint(
      radius: r,
      shadows: raised ? Chiaroscuro.raised : Chiaroscuro.alabaster,
      gradient: Lumen.alabaster,
      blurOn: blurOn,
      sigma: GlassTier.hero.sigma,
      child: ClipRRect(
        borderRadius: r,
        child: Stack(
          children: [
            // The refraction rim: bright at the lit top-left, thinning away.
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: r,
                    border: Border.all(
                      color: FhwLuxePalette.glassBorderLight,
                      width: 1.1,
                    ),
                  ),
                ),
              ),
            ),
            // The crown catch-light — the single bright line that sells mass.
            Positioned(
              top: 0,
              left: radius,
              right: radius,
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
            padding == null ? child : Padding(padding: padding!, child: child),
          ],
        ),
      ),
    );
    return fx.blur && blurOn ? RepaintBoundary(child: sheet) : sheet;
  }
}

/// A decorated surface that optionally frosts the backdrop behind it, so the
/// alabaster sheets and the sapphire pools share one implementation of
/// "gradient + radius + layered shadow (+ blur)".
class DecoratedBoxTint extends StatelessWidget {
  const DecoratedBoxTint({
    super.key,
    required this.radius,
    required this.shadows,
    required this.gradient,
    required this.child,
    this.blurOn = false,
    this.sigma = 16,
    this.solidColor,
  });

  final BorderRadius radius;
  final List<BoxShadow> shadows;
  final Gradient gradient;
  final Widget child;
  final bool blurOn;
  final double sigma;
  final Color? solidColor;

  @override
  Widget build(BuildContext context) {
    final decorated = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: solidColor == null ? gradient : null,
        color: solidColor,
      ),
      child: child,
    );
    final clipped = ClipRRect(
      borderRadius: radius,
      child: blurOn
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.5),
                      Colors.white.withValues(alpha: 0.28),
                    ],
                  ),
                ),
                child: child,
              ),
            )
          : decorated,
    );

    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: radius, boxShadow: shadows),
      child: clipped,
    );
  }
}

// ─── Liquid sapphire pool ───────────────────────────────────────────────────

/// A raised body of liquid sapphire — translucent royal blue lit from within,
/// with a bioluminescent bloom and a refracted top edge. The dark counterweight
/// to the alabaster; where you want weight and light, not information density.
class SapphirePool extends StatelessWidget {
  const SapphirePool({
    super.key,
    required this.child,
    this.radius = Gap.radiusLg,
    this.padding,
    this.emissive = true,
    this.gradient = Lumen.sapphireLiquid,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final bool emissive;
  final Gradient gradient;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        gradient: gradient,
        boxShadow: emissive
            ? Chiaroscuro.bloom(FhwLuxePalette.sapphireRoyal, alpha: 0.42)
            : Chiaroscuro.alabaster,
      ),
      child: ClipRRect(
        borderRadius: r,
        child: Stack(
          children: [
            // Inner glow trapped beneath the surface — the light source inside.
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0.1, -0.9),
                      radius: 1.1,
                      colors: [
                        Colors.white.withValues(alpha: 0.28),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Refracted top edge.
            Positioned(
              top: 0,
              left: radius,
              right: radius,
              child: IgnorePointer(
                child: Container(
                  height: 1.2,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0x00FFFFFF),
                        Color(0x80FFFFFF),
                        Color(0x00FFFFFF),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            padding == null ? child : Padding(padding: padding!, child: child),
          ],
        ),
      ),
    );
  }
}

// ─── Pearl-sheened monolithic type ──────────────────────────────────────────

/// Luminescent pearl text: the [Lumen.pearl] iridescence masked into the
/// glyphs, so a headline is a bar of cold light rather than painted ink.
class PearlText extends StatelessWidget {
  const PearlText({
    super.key,
    required this.text,
    this.style,
    this.maxLines,
    this.align,
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextAlign? align;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => Lumen.pearl.createShader(bounds),
      child: Text(
        text,
        maxLines: maxLines,
        overflow: maxLines == null ? null : TextOverflow.ellipsis,
        textAlign: align,
        style: (style ?? AppType.display).copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.2,
        ),
      ),
    );
  }
}

/// Structural type: one large Sora ExtraBold figure or word, tight-kerned, used
/// as the architecture of the surface rather than as text to read.
class Monolith extends StatelessWidget {
  const Monolith({
    super.key,
    required this.value,
    this.unit,
    this.fontSize = 64,
    this.pearled = true,
    this.tone = FhwLuxePalette.sapphireDeep,
  });

  final String value;
  final String? unit;
  final double fontSize;

  /// Pearl-mask the fill so the monolith lumbers like carved stone under light.
  final bool pearled;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    // Built from the bundled Sora ExtraBold (AppType.numeral is Sora 800 with
    // tabular figures) so it renders offline with the rest of the app.
    final style = AppType.numeral.copyWith(
      fontSize: fontSize,
      height: 0.94,
      letterSpacing: -fontSize * 0.03,
      color: tone,
    );
    final monolith = pearled
        ? ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) => const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2E73FF), Color(0xFF0D2E73)],
            ).createShader(bounds),
            child: Text(value, style: style),
          )
        : Text(value, style: style);
    if (unit == null) return monolith;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        monolith,
        const SizedBox(width: 6),
        Text(
          unit!,
          style: AppType.label.copyWith(
            fontSize: 14,
            color: tone,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

// ─── Emissive cobalt orb ────────────────────────────────────────────────────

/// A single point of bioluminescent light — a status source rendered as an
/// emissive sphere, not a dot. Breathes only when motion is permitted.
class LumenOrb extends StatelessWidget {
  const LumenOrb({
    super.key,
    this.size = 12,
    this.colour = FhwLuxePalette.sapphireElectric,
    this.breathe = true,
  });

  final double size;
  final Color colour;
  final bool breathe;

  @override
  Widget build(BuildContext context) {
    final fx = VisualEffects.of(context);
    return SizedBox(
      width: size * 2.6,
      height: size * 2.6,
      child: Center(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              center: const Alignment(-0.3, -0.3),
              colors: [Colors.white, colour],
            ),
            boxShadow: fx.motion && breathe
                ? Chiaroscuro.bloom(colour, alpha: 0.6)
                : [
                    BoxShadow(
                      color: colour.withValues(alpha: 0.5),
                      blurRadius: size,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
        ),
      ),
    );
  }
}

// ─── Magnetic, dopaminergic control ─────────────────────────────────────────

/// A capsule that behaves like it is magnetic: it draws inward on the press and
/// releases a one-shot specular bloom the instant it is tapped — a small,
/// physical reward. Everything settles, so tests end. Reduced motion renders
/// the resting capsule with no bloom.
class MagneticCapsule extends StatefulWidget {
  const MagneticCapsule({
    super.key,
    required this.child,
    required this.onTap,
    this.radius = 999,
    this.selected = false,
    this.enableBloom = true,
  });

  final Widget child;
  final VoidCallback onTap;
  final double radius;

  /// Selected capsules sit on a liquid sapphire pool; unselected on alabaster.
  final bool selected;
  final bool enableBloom;

  @override
  State<MagneticCapsule> createState() => _MagneticCapsuleState();
}

class _MagneticCapsuleState extends State<MagneticCapsule>
    with TickerProviderStateMixin {
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 150),
    value: 1,
  );
  late final AnimationController _bloom = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
  );
  bool _down = false;

  @override
  void dispose() {
    _press.dispose();
    _bloom.dispose();
    super.dispose();
  }

  void _setDown(bool value) {
    if (!VisualEffects.of(context).motion) return;
    setState(() => _down = value);
    _press.animateTo(value ? 0.94 : 1.0);
  }

  void _fire() {
    if (VisualEffects.of(context).motion && widget.enableBloom) {
      _bloom.forward(from: 0);
    }
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(widget.radius);
    return RepaintBoundary(
      child: GestureDetector(
        onTapDown: (_) => _setDown(true),
        onTapCancel: () => _setDown(false),
        onTapUp: (_) => _setDown(false),
        onTap: _fire,
        behavior: HitTestBehavior.opaque,
        child: AnimatedBuilder(
          animation: Listenable.merge([_press, _bloom]),
          builder: (context, child) {
            final scale = _down ? 0.955 : 1.0;
            final bloomT = _bloom.value;
            return Transform.scale(
              scale: scale,
              child: Stack(
                children: [
                  child!,
                  if (bloomT > 0 && bloomT < 1)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _BloomPainter(
                            t: bloomT,
                            radius: widget.radius,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: r,
              gradient: widget.selected
                  ? Lumen.sapphireLiquid
                  : Lumen.alabasterRaised,
              border: Border.all(
                color: widget.selected
                    ? Colors.white.withValues(alpha: 0.4)
                    : FhwLuxePalette.glassBorderLight,
                width: 1.1,
              ),
              boxShadow: widget.selected
                  ? Chiaroscuro.bloom(FhwLuxePalette.sapphireRoyal, alpha: 0.4)
                  : Chiaroscuro.alabaster,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// The expanding ring of light released on a magnetic tap.
class _BloomPainter extends CustomPainter {
  const _BloomPainter({required this.t, required this.radius});

  final double t;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius > 900 ? size.height / 2 : radius),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3 * (1 - t)
      ..color = FhwLuxePalette.sapphireElectric.withValues(
        alpha: (1 - t) * 0.6,
      );
    // Grow the ring outward from the surface as it fades.
    canvas.save();
    canvas.scale(1 + 0.08 * t, size.width / 2);
    canvas.translate(-size.width * 0.04 * t, 0);
    canvas.drawRRect(rrect, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BloomPainter old) => old.t != t;
}
