/// The glass layer of "Clinical Luxe".
///
/// Frosted, translucent surfaces that sit over a softly lit backdrop. The
/// effect is expensive on the GPU, so it is budgeted rather than sprinkled:
/// **blur is on only for the hero, the app/nav bars, bottom action bars and
/// the active vitals capture card.** Cards inside scrolling lists pass
/// `blur: false` and get the same glass *look* (translucent fill, catch-light
/// stroke, floating shadow) without a per-item `BackdropFilter`.
///
/// Everything here degrades honestly. When the OS asks for reduced motion, or
/// the user picks the "Lite" visual mode on a low-end handset, every
/// `BackdropFilter` disappears and the surface renders as a flat translucent
/// card. Layouts, strings and tap targets are identical in both modes.
///
/// The IMCI red / amber / green are never used here for decoration.
library;

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/preferences_store.dart';
import 'app_theme.dart';

// ─── Visual effects preference ────────────────────────────────────────────

/// What the renderer is allowed to spend on this device.
@immutable
class VisualEffects {
  const VisualEffects({required this.blur, required this.motion});

  /// Backdrop blur permitted.
  final bool blur;

  /// Animations permitted. When false every duration is [Duration.zero].
  final bool motion;

  static const full = VisualEffects(blur: true, motion: true);
  static const lite = VisualEffects(blur: false, motion: false);

  /// Resolves the effective effects for this build: the user's Lite choice
  /// wins, then the platform's reduced-motion setting turns both motion and
  /// blur off (a device asking for less is a device we should not tax).
  static VisualEffects of(BuildContext context) {
    final lite = _LiteScope.maybeOf(context) ?? false;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final on = !lite && !reduced;
    return VisualEffects(blur: on, motion: on);
  }

  /// Zero when motion is off, otherwise [d].
  Duration scale(Duration d) => motion ? d : Duration.zero;
}

/// Holds the Lite flag and persists it through [PreferencesStore].
class VisualEffectsController extends StateNotifier<bool> {
  VisualEffectsController() : super(false) {
    _load();
  }

  Future<void> _load() async {
    try {
      final v = await PreferencesStore.reducedEffects();
      if (mounted) state = v;
    } catch (_) {
      // Preferences unavailable (tests without a mock) — keep Full mode.
    }
  }

  Future<void> setLite(bool value) async {
    state = value;
    try {
      await PreferencesStore.setReducedEffects(value);
    } catch (_) {
      // Persisting is best-effort; the in-memory choice still applies.
    }
  }
}

/// `true` when the user has chosen Lite (no blur, no motion).
final visualEffectsProvider =
    StateNotifierProvider<VisualEffectsController, bool>(
      (ref) => VisualEffectsController(),
    );

/// Puts the Lite flag into the tree so [VisualEffects.of] can read it
/// without a `ref`. Mount once near the root (both shells do), and in tests
/// that want Lite behaviour.
class VisualEffectsScope extends ConsumerWidget {
  const VisualEffectsScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lite = ref.watch(visualEffectsProvider);
    return _LiteScope(lite: lite, child: child);
  }
}

class _LiteScope extends InheritedWidget {
  const _LiteScope({required this.lite, required super.child});

  final bool lite;

  static bool? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_LiteScope>()?.lite;

  @override
  bool updateShouldNotify(_LiteScope oldWidget) => oldWidget.lite != lite;
}

// ─── Glass surface ────────────────────────────────────────────────────────

/// How much a surface is allowed to cost and how loud it may be.
enum GlassTier {
  /// Page hero, identity strip, the active capture card. Strongest blur,
  /// brand-tinted fill.
  hero(sigma: 18, radius: 28),

  /// Standard content card. Medium blur when allowed.
  card(sigma: 12, radius: Gap.radius),

  /// Small pills and chips.
  chip(sigma: 8, radius: Gap.radiusSm);

  const GlassTier({required this.sigma, required this.radius});

  final double sigma;
  final double radius;
}

/// A frosted surface.
///
/// Full mode: `RepaintBoundary > ClipRRect > BackdropFilter > DecoratedBox`.
/// Lite mode or `blur: false`: the same decoration at 94% white, no filter.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.tier = GlassTier.card,
    this.blur = true,
    this.tint,
    this.radius,
    this.padding,
    this.border = true,
    this.shadow = true,
  });

  final Widget child;
  final GlassTier tier;

  /// Request a real backdrop blur. Honoured only when [VisualEffects.blur]
  /// is true. Cards in scrolling lists should pass `false`.
  final bool blur;

  /// Optional colour mixed into the fill (hero surfaces use the brand blue).
  final Color? tint;
  final BorderRadius? radius;
  final EdgeInsetsGeometry? padding;
  final bool border;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final fx = VisualEffects.of(context);
    final blurOn = blur && fx.blur;
    final r = radius ?? BorderRadius.circular(tier.radius);

    final base = tint ?? Colors.white;
    final isHero = tier == GlassTier.hero;
    final gradient = blurOn
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(
                Colors.white,
                base,
                isHero ? 0.10 : 0.0,
              )!.withValues(alpha: 0.78),
              Color.lerp(
                Colors.white,
                base,
                isHero ? 0.18 : 0.0,
              )!.withValues(alpha: 0.58),
            ],
          )
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(
                Colors.white,
                base,
                isHero ? 0.06 : 0.0,
              )!.withValues(alpha: 0.94),
              Color.lerp(
                Colors.white,
                base,
                isHero ? 0.12 : 0.0,
              )!.withValues(alpha: 0.94),
            ],
          );

    final decorated = DecoratedBox(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: r,
        border: border
            ? Border.all(color: AppColors.glassStroke, width: Gap.hairline)
            : null,
      ),
      child: Stack(
        children: [
          // Top inner highlight — the thin bright line that sells "glass".
          Positioned(
            top: 0,
            left: 12,
            right: 12,
            child: IgnorePointer(
              child: Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0),
                      Colors.white.withValues(alpha: 0.9),
                      Colors.white.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          padding == null ? child : Padding(padding: padding!, child: child),
        ],
      ),
    );

    Widget surface = ClipRRect(
      borderRadius: r,
      child: blurOn
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: tier.sigma, sigmaY: tier.sigma),
              child: decorated,
            )
          : decorated,
    );

    if (shadow) {
      surface = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: r,
          boxShadow: [isHero ? AppShadows.glass : AppShadows.card],
        ),
        child: surface,
      );
    }

    return blurOn ? RepaintBoundary(child: surface) : surface;
  }
}

// ─── Ambient backdrop ─────────────────────────────────────────────────────

enum AmbientVariant { clinical, warm }

/// Three static radial blobs on white. Gives the glass something to blur;
/// on its own it is a quiet, expensive-looking page background.
class AmbientBackdrop extends StatelessWidget {
  const AmbientBackdrop({
    super.key,
    required this.child,
    this.variant = AmbientVariant.clinical,
  });

  final Widget child;
  final AmbientVariant variant;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      RepaintBoundary(child: CustomPaint(painter: _AmbientPainter(variant))),
      child,
    ],
  );
}

class _AmbientPainter extends CustomPainter {
  const _AmbientPainter(this.variant);

  final AmbientVariant variant;

  static const _warm = Color(0xFFFFE7C2);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.canvas);
    final w = size.width;
    final h = size.height;

    void blob(Offset c, double r, Color colour, double alpha) {
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            colour.withValues(alpha: alpha),
            colour.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: c, radius: r));
      canvas.drawCircle(c, r, paint);
    }

    switch (variant) {
      case AmbientVariant.clinical:
        blob(Offset(w * 0.15, h * 0.05), w * 0.7, AppColors.primaryGlow, 0.22);
        blob(Offset(w * 0.95, h * 0.35), w * 0.6, AppColors.surfaceTint, 0.9);
        blob(Offset(w * 0.3, h * 0.95), w * 0.7, AppColors.primaryLight, 0.9);
      case AmbientVariant.warm:
        blob(Offset(w * 0.1, h * 0.05), w * 0.7, _warm, 0.85);
        blob(Offset(w * 0.95, h * 0.4), w * 0.6, AppColors.surfaceTint, 0.9);
        blob(Offset(w * 0.4, h * 0.98), w * 0.7, AppColors.primaryGlow, 0.14);
    }
  }

  @override
  bool shouldRepaint(_AmbientPainter old) => old.variant != variant;
}

// ─── Glass nav bar ────────────────────────────────────────────────────────

class GlassNavItem {
  const GlassNavItem({
    required this.icon,
    required this.label,
    this.selectedIcon,
  });

  final IconData icon;
  final IconData? selectedIcon;
  final String label;
}

/// A floating frosted pill that replaces [BottomNavigationBar]. Labels are
/// always visible (never icon-only) and every item is at least 48px.
class GlassNavBar extends StatelessWidget {
  const GlassNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  final List<GlassNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  static const double height = 64;

  @override
  Widget build(BuildContext context) {
    final fx = VisualEffects.of(context);
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.all(12),
      child: GlassSurface(
        tier: GlassTier.hero,
        radius: BorderRadius.circular(28),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: SizedBox(
          height: height,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _NavButton(
                    item: items[i],
                    selected: i == currentIndex,
                    duration: fx.scale(AppMotion.fast),
                    onTap: () => onTap(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.selected,
    required this.duration,
    required this.onTap,
  });

  final GlassNavItem item;
  final bool selected;
  final Duration duration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colour = selected ? AppColors.primary : AppColors.inkMuted;
    return Semantics(
      selected: selected,
      button: true,
      label: item.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: AnimatedContainer(
            duration: duration,
            curve: AppMotion.curve,
            margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.10)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  selected ? (item.selectedIcon ?? item.icon) : item.icon,
                  size: 22,
                  color: colour,
                ),
                const SizedBox(height: 3),
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: colour,
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

// ─── Glass app bar ────────────────────────────────────────────────────────

/// A translucent app bar that lets the [AmbientBackdrop] glow through. Same
/// slots as [AppBar] (leading, title, actions, bottom) so screens swap in
/// place.
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GlassAppBar({
    super.key,
    this.title,
    this.leading,
    this.actions,
    this.bottom,
    this.automaticallyImplyLeading = true,
    this.hero = false,
  });

  final Widget? title;
  final Widget? leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final bool automaticallyImplyLeading;

  /// Deep, luxurious blue header — the same midnight-to-royal gradient as the
  /// dashboard hero. When true the bar renders as an *opaque* blue panel with
  /// white content, a soft radial sheen and rounded bottom corners instead of
  /// translucent glass, so the top of the page reads as an intentional header
  /// rather than glass floating over the (dark) device viewport.
  final bool hero;

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final fx = VisualEffects.of(context);
    if (hero) return _buildHero(context);
    final bar = AppBar(
      title: title,
      leading: leading,
      actions: actions,
      bottom: bottom,
      automaticallyImplyLeading: automaticallyImplyLeading,
      backgroundColor: Colors.white.withValues(alpha: fx.blur ? 0.62 : 0.94),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      shape: const Border(
        bottom: BorderSide(color: AppColors.glassStroke, width: Gap.hairline),
      ),
    );
    if (!fx.blur) return bar;
    return RepaintBoundary(
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: bar,
        ),
      ),
    );
  }

  /// The opaque deep-blue header variant. The [AppBar] is laid out on top of a
  /// full-bleed gradient so the blue also paints behind the status bar; a
  /// radial sheen adds depth and the bottom corners round to meet the page.
  Widget _buildHero(BuildContext context) {
    const radius = BorderRadius.only(
      bottomLeft: Radius.circular(28),
      bottomRight: Radius.circular(28),
    );

    final bar = AppBar(
      title: title,
      leading: leading,
      actions: actions,
      bottom: bottom,
      automaticallyImplyLeading: automaticallyImplyLeading,
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: AppType.title.copyWith(color: Colors.white),
      iconTheme: const IconThemeData(color: Colors.white),
      actionsIconTheme: const IconThemeData(color: Colors.white),
    );

    return Container(
      decoration: const BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Color(0x59050F26),
            blurRadius: 30,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: AppColors.heroGradient),
              ),
            ),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0.9, -0.7),
                    radius: 1.0,
                    colors: [Color(0x33A9C8FF), Color(0x00000000)],
                  ),
                ),
              ),
            ),
            bar,
          ],
        ),
      ),
    );
  }
}

/// A full-bleed frosted footer for the primary action(s) at the foot of a
/// screen (save, continue). Bright white frosted glass, deliberately lighter
/// than the content above it: this is the one surface that must read as the
/// clear exit door, never as a dark scrim. It paints *into* the bottom safe
/// area (a floating pill left the inset transparent, so the dark device
/// viewport bled through beneath it). Degrades to an opaque white panel when
/// the platform asks for reduced effects.
class GlassActionBar extends StatelessWidget {
  const GlassActionBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final fx = VisualEffects.of(context);

    final frosted = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: fx.blur ? 0.82 : 0.96),
            Colors.white.withValues(alpha: fx.blur ? 0.94 : 0.99),
          ],
        ),
        border: const Border(
          top: BorderSide(
            color: AppColors.glassStroke,
            width: Gap.hairline,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.md),
        child: child,
      ),
    );

    final surface = fx.blur
        ? ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: frosted,
            ),
          )
        : frosted;

    // SafeArea is *inside* the decorated surface so the frosted background
    // fills the bottom inset rather than leaving it transparent.
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Color(0x1A0B2A6B),
              blurRadius: 24,
              offset: Offset(0, -6),
            ),
          ],
        ),
        child: SafeArea(top: false, child: surface),
      ),
    );
  }
}
