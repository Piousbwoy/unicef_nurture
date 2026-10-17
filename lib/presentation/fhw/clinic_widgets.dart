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
        border: Border.all(color: accent ?? FhwLuxePalette.hairLine, width: 1),
        // A clean elevation on the white desk: a tight cool contact plus a wide
        // soft drop, so a porcelain card lifts off bright paper on shadow and a
        // hairline edge rather than a tone gap. (Neumorphic extrusion needs a
        // canvas darker than the card; on pure white its highlight goes
        // invisible.) Still pure BoxShadow — never a blur filter.
        boxShadow: Chiaroscuro.alabaster,
      ),
      child: Material(
        // The opaque cardSurface is pinned by consumers and their tests. The
        // heavenly light is laid on the Material's ink layer via [Ink], so the
        // alabaster wash never covers a ListTile ripple — the splash still
        // surfaces above it.
        color: FhwLuxePalette.cardSurface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: radius),
        child: Ink(
          // A bright, top-lit white fill that stays clearly lighter than the
          // ice canvas beneath it, so the card lifts off the page instead of
          // blending into it. Gradient + BoxShadow only — no blur filter.
          decoration: const BoxDecoration(gradient: Lumen.alabasterRaised),
          child: Stack(
            children: [
              // Faux-glass sheen — the premium-fintech signature: a soft
              // diagonal sweep of light from the top-left, as if the porcelain
              // were a pane of frosted glass catching a key light. It is a
              // translucent gradient laid beneath the ink (never a
              // BackdropFilter), so it stays cheap on a low-end handset and
              // leaves text contrast untouched.
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0x4DFFFFFF),
                          Color(0x14FFFFFF),
                          Color(0x00FFFFFF),
                          Color(0x0FFFFFFF),
                        ],
                        stops: [0.0, 0.3, 0.62, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
              // The crown seam — light spilling over the top edge, carrying a
              // faint pearl tint at its tail so the rim reads iridescent.
              Positioned(
                top: 0,
                left: Gap.radius,
                right: Gap.radius,
                child: IgnorePointer(
                  child: Container(
                    height: 1.6,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color(0x00FFFFFF),
                          Color(0xE6FFFFFF),
                          Color(0x33DCE9FF),
                          Color(0x00FFFFFF),
                        ],
                        stops: [0.0, 0.42, 0.7, 1.0],
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
                            color: FhwLuxePalette.textSecondary,
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
      ),
    );
    if (onTap == null) return card;
    // A felt-not-seen press on tappable cards; the press is a transient
    // AnimatedScale with no looping controller, so widget tests stay safe.
    return PressScale(onTap: onTap, radius: radius, child: card);
  }
}

/// The dashboard-grade sibling of [ClinicCard], used by the FHW Today tab.
///
/// Same content contract as [ClinicCard] — identical [title] / [subtitle] /
/// [child] rendering so every pinned string is untouched — but finished as a
/// royal lacquer panel: one blue hue with a lit corner and a shadow corner, a
/// lit glaze pooled under the surface at the top-left, a crisp hairline of
/// catch-light on the top edge, a soft sapphire bloom that lifts it off the
/// white, and a matte accent bar when one is warranted. Still one blue with no
/// second hue bleeding in and no backdrop blur — the panel reads as a poured,
/// lit object with depth, not atmosphere. A [Material] stays transparent so
/// ListTile and row ink still fire over the fill.
///
/// Two things make a panel auditable, which is what a working register has to
/// be: a [count] seat that states how many items the card holds, and a header
/// rule that runs the full width of the panel the way a printed form's does.
class LumenCard extends StatelessWidget {
  const LumenCard({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.trailing,
    this.count,
    this.accent,
    this.padding = const EdgeInsets.fromLTRB(20, 20, 20, 22),
    this.onTap,
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final int? count;
  final Color? accent;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(Gap.radius);
    final edges = padding is EdgeInsets
        ? padding as EdgeInsets
        : const EdgeInsets.fromLTRB(20, 20, 20, 22);

    // Header and body are inset separately so the rule between them is a
    // direct child of the column: it then spans the panel edge to edge, the
    // way the ruling on a printed form does. The bleed has to be structural —
    // Padding cannot be negative, RenderPadding asserts it.
    final content = title == null
        ? Padding(padding: edges, child: child)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  edges.left,
                  edges.top,
                  edges.right,
                  14,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                              color: Colors.white,
                            ),
                          ),
                        ),
                        ?trailing,
                        if (count != null) ...[
                          const SizedBox(width: 8),
                          CountSeat(count: count!),
                        ],
                      ],
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        subtitle!,
                        style: AppType.body.copyWith(
                          fontSize: 13,
                          color: FhwLuxePalette.lacquerInk,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const IgnorePointer(
                child: SizedBox(
                  height: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: FhwLuxePalette.lacquerRule,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  edges.left,
                  14,
                  edges.right,
                  edges.bottom,
                ),
                child: child,
              ),
            ],
          );

    final panel = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: FhwLuxePalette.sapphireLacquer,
        border: Border.all(
          color: accent ?? Colors.white.withValues(alpha: 0.18),
          width: accent == null ? 1 : 1.2,
        ),
        boxShadow: const [
          // A cool contact shade keeps the panel grounded on bright paper…
          BoxShadow(
            color: Color(0x5914295E),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
          // …and a soft sapphire bloom lifts it, so the lacquer reads as a lit
          // object floating on the white — the premium-fintech signature.
          BoxShadow(
            color: Color(0x3D2970FF),
            blurRadius: 30,
            spreadRadius: -8,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Material(
        // Transparent so the flat blue shows through while the Material
        // still hosts ink for the rows this panel frequently contains.
        color: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: radius),
        child: Stack(
          children: [
            // The lit glaze — a light source pooled under the surface at the
            // top-left, so the lacquer reads poured and glossy rather than a
            // flat fill. A radial gradient beneath the content; no blur filter.
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(-0.75, -1.0),
                      radius: 1.2,
                      colors: [
                        Colors.white.withValues(alpha: 0.20),
                        Colors.white.withValues(alpha: 0.05),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.42, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            content,
            // The one hairline of catch-light along the top edge. Clipped by
            // the panel's own corner, so it stops short of the radius instead
            // of drawing a straight line across a round corner.
            const Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: IgnorePointer(
                child: SizedBox(
                  height: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: FhwLuxePalette.lacquerEdge,
                    ),
                  ),
                ),
              ),
            ),
            if (accent != null)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(width: 4, color: accent),
              ),
          ],
        ),
      ),
    );
    if (onTap == null) return panel;
    return PressScale(onTap: onTap!, radius: radius, child: panel);
  }
}

/// How many items a panel is holding, stated in its header. A register that
/// counts its own lines can be checked against the paper one; a panel of
/// unnumbered rows cannot. Set in a cut well so it reads as a stamped field on
/// the form, and scaled down inside a fixed seat so a three-figure count or
/// the 200% text floor can never push the title off the panel.
///
/// Shared by [LumenCard] and the clinic ledger, so every surface that states a
/// total states it the same way.
class CountSeat extends StatelessWidget {
  const CountSeat({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 28),
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
    ),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 44),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: Text(
          '$count',
          style: AppType.label.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ),
    ),
  );
}

/// A column whose children are separated by hairlines, so a short list reads
/// as ruled lines on a register page instead of rows floating in a box.
class RuledColumn extends StatelessWidget {
  const RuledColumn({
    super.key,
    required this.children,
    this.rule = FhwLuxePalette.lacquerRuleQuiet,
  });

  final List<Widget> children;
  final Color rule;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0)
          IgnorePointer(
            child: SizedBox(
              height: 1,
              child: DecoratedBox(decoration: BoxDecoration(color: rule)),
            ),
          ),
        children[i],
      ],
    ],
  );
}

/// The page's reading order, made visible. A cold label riding a hairline
/// rule — the section break of a paper register.
///
/// Promoted from the Today dashboard so every desk surface announces its
/// sections the same way. It is only ever rendered by a group that has
/// something to show, so the spine never points at an empty box. The rule
/// takes whatever the two labels leave and closes to nothing at the
/// accessibility floor rather than overflowing the row.
class SectionSpine extends StatelessWidget {
  const SectionSpine(this.label, {this.detail, super.key});

  final String label;
  final String? detail;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 0, 2, 12),
    child: Row(
      children: [
        Flexible(
          child: Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.eyebrow.copyWith(
              color: FhwLuxePalette.textSecondary,
              fontSize: 10.5,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SizedBox(
            height: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(color: FhwLuxePalette.hairLine),
            ),
          ),
        ),
        if (detail != null) ...[
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              detail!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: AppType.caption.copyWith(
                fontSize: 10.5,
                color: FhwLuxePalette.textFaint,
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

/// A row of view- or filter-switching toggles, finished in the desk's own
/// material rather than the framework default. The chosen toggle takes the
/// royal-lacquer fill the panels are built from and holds a check; the rest
/// recede to pearl. This replaces the stock `ChoiceChip` wherever a control
/// switches what the worker is looking at, so switching a view speaks the same
/// language as the register it switches.
///
/// It lays out as a [Wrap], not a joined track, on purpose: at 320px / 200%
/// text a single-row segment with two-word labels overflows, and a wrapping
/// set of toggles never does. The label text is exactly what callers pass,
/// so every `find.text` pin survives.
class DeskFilterBar extends StatelessWidget {
  const DeskFilterBar({
    super.key,
    required this.options,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (var i = 0; i < options.length; i++)
        _DeskFilter(
          label: options[i],
          selected: i == selectedIndex,
          onTap: () => onSelected(i),
        ),
    ],
  );
}

class _DeskFilter extends StatelessWidget {
  const _DeskFilter({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            gradient: selected ? FhwLuxePalette.sapphireLacquer : null,
            color: selected ? null : FhwLuxePalette.pearlSurface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? Colors.white.withValues(alpha: 0.18)
                  : FhwLuxePalette.hairLine,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                const Icon(Icons.check_rounded, size: 15, color: Colors.white),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: AppType.label.copyWith(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? Colors.white : FhwLuxePalette.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
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
                        // One blue, three depths: a step already taken settles
                        // into the deep sapphire, the step in progress is the
                        // brightest thing on the rail, and a step not yet
                        // reached is the desk's own hairline grey. The desk's
                        // chrome is sapphire — brass belongs to the warm app,
                        // and a second chrome colour is how an identity drifts.
                        color: i < current
                            ? FhwLuxePalette.sapphireDeep
                            : (i == current
                                  ? FhwLuxePalette.sapphireRoyal
                                  : FhwLuxePalette.hairLine),
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
                color: FhwLuxePalette.sapphireDeep,
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
              color: FhwLuxePalette.sapphireRoyal.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(Gap.radiusXs),
            ),
            child: Icon(icon, size: 17, color: FhwLuxePalette.sapphireDeep),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: AppType.caption.copyWith(
                color: FhwLuxePalette.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          if (onTap != null)
            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: FhwLuxePalette.textSecondary,
            ),
        ],
      ),
    );
    return Material(
      color: FhwLuxePalette.sapphireIce,
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
