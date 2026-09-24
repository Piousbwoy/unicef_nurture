/// Luxe FHW components — the floating acrylic dock, the Catalyst Capsule and
/// the bento telemetry deck.
///
/// Every surface degrades honestly: frosted blur and motion come from
/// [VisualEffects.of], so under reduced-motion / Lite mode each widget
/// renders a solid crisp card with the identical layout, strings and tap
/// targets. Clinical red/amber/green appear only as triage colours, never
/// as decoration.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/fhw_luxe.dart';
import '../../core/theme/glass.dart';
import '../shared/ui.dart' show PressScale;
import 'luxe_motion.dart';

// ─── Floating acrylic island navigation dock ───────────────────────────────

/// The detached frosted island that replaces an edge-to-edge bottom bar:
/// 14px above the safe area, 16px lateral margins, glass catch-light edge,
/// a sapphire pill that glides behind the active tab, and a light haptic
/// on every switch. Labels stay visible on every destination.
class FloatingAcrylicDock extends StatelessWidget {
  const FloatingAcrylicDock({
    super.key,
    required this.index,
    required this.titles,
    required this.icons,
    required this.onSelect,
  });

  final int index;
  final List<String> titles;
  final List<IconData> icons;
  final ValueChanged<int> onSelect;

  static const double height = 64;

  @override
  Widget build(BuildContext context) {
    final fx = VisualEffects.of(context);
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: GlassSurface(
        tier: GlassTier.hero,
        radius: BorderRadius.circular(28),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: SizedBox(
          height: height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final slot = constraints.maxWidth / titles.length;
              return Stack(
                children: [
                  MagneticPill(index: index, slotWidth: slot),
                  Positioned.fill(
                    child: Row(
                      children: [
                        for (var i = 0; i < titles.length; i++)
                          Expanded(
                            child: _DockItem(
                              key: ValueKey('fhw-tab-$i'),
                              title: titles[i],
                              icon: icons[i],
                              selected: index == i,
                              duration: fx.scale(AppMotion.fast),
                              onTap: () {
                                if (i != index) {
                                  HapticFeedback.lightImpact();
                                }
                                onSelect(i);
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DockItem extends StatelessWidget {
  const _DockItem({
    super.key,
    required this.title,
    required this.icon,
    required this.selected,
    required this.duration,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final bool selected;
  final Duration duration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween<double>(end: selected ? 1 : 0),
                duration: duration,
                curve: AppMotion.curve,
                builder: (context, t, child) => IconTheme(
                  data: IconThemeData(
                    color: Color.lerp(
                      FhwLuxePalette.textSecondary,
                      Colors.white,
                      t,
                    ),
                  ),
                  child: child!,
                ),
                child: Icon(icon, size: 22),
              ),
              const SizedBox(height: 3),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.label.copyWith(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected
                      ? Colors.white
                      : FhwLuxePalette.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Catalyst Capsule ──────────────────────────────────────────────────────

/// The command-center hero: a sculpted sapphire capsule with celestial
/// light pools, a high-precision micro-badge, the cinematic heading, and a
/// shimmering catch-light sweep across the primary action on mount.
class CatalystCapsule extends StatelessWidget {
  const CatalystCapsule({
    super.key,
    required this.badge,
    required this.heading,
    required this.body,
    required this.button,
    this.footer,
  });

  final String badge;
  final Widget heading;
  final Widget body;
  final Widget button;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: FhwLuxePalette.sapphireHeroGradient,
        borderRadius: BorderRadius.all(Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Color(0x59050F26),
            blurRadius: 34,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(28)),
        child: Stack(
          children: [
            // Cool celestial pool, top-right; deep sapphire aura,
            // bottom-left — the lit-glass depth of the hero surface.
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0.9, -0.8),
                    radius: 1.1,
                    colors: [Color(0x2E60A5FA), Color(0x00000000)],
                  ),
                ),
              ),
            ),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(-0.9, 1.0),
                    radius: 1.0,
                    colors: [Color(0x1F1D4ED8), Color(0x00000000)],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const BreathingDot(
                        size: 6,
                        colour: FhwLuxePalette.sapphireElectric,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          badge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.eyebrow.copyWith(
                            fontSize: 10,
                            letterSpacing: 1.2,
                            color: Colors.white.withValues(alpha: 0.78),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  heading,
                  const SizedBox(height: 8),
                  body,
                  const SizedBox(height: 22),
                  ShimmerCatchlight(child: button),
                  if (footer != null) ...[
                    const SizedBox(height: 10),
                    footer!,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Bento telemetry deck ──────────────────────────────────────────────────

/// The asymmetric metric deck: a prominent priority-queue hero tile, a
/// due-today tile with a session-completion micro-arc, a live offline
/// telemetry tile, and compact referral/household tiles. Every tile keeps
/// its tap target and a press-scale affordance.
class BentoTelemetryDeck extends StatelessWidget {
  const BentoTelemetryDeck({
    super.key,
    required this.queueCount,
    required this.queueNames,
    this.oldestWaitMinutes,
    this.dueToday,
    this.overdue,
    this.sessionDone,
    this.sessionTotal,
    this.pendingSync,
    this.failingSync,
    required this.engineReady,
    this.referrals,
    this.households,
    required this.onQueueTap,
    required this.onDueTap,
    required this.onSyncTap,
    required this.onReferralsTap,
    required this.onFamiliesTap,
  });

  final int queueCount;
  final List<String> queueNames;
  final int? oldestWaitMinutes;
  final int? dueToday;
  final int? overdue;
  final int? sessionDone;
  final int? sessionTotal;
  final int? pendingSync;
  final int? failingSync;
  final bool engineReady;
  final int? referrals;
  final int? households;
  final VoidCallback onQueueTap;
  final VoidCallback onDueTap;
  final VoidCallback onSyncTap;
  final VoidCallback onReferralsTap;
  final VoidCallback onFamiliesTap;

  @override
  Widget build(BuildContext context) {
    final queueTile = _BentoTile(
      onTap: onQueueTap,
      child: _QueueHero(
        count: queueCount,
        names: queueNames,
        oldestWaitMinutes: oldestWaitMinutes,
      ),
    );
    final dueTile = _BentoTile(
      onTap: onDueTap,
      child: _DueTodayTile(
        due: dueToday,
        overdue: overdue,
        sessionDone: sessionDone,
        sessionTotal: sessionTotal,
      ),
    );
    final syncTile = _BentoTile(
      onTap: onSyncTap,
      child: _OfflineTile(
        engineReady: engineReady,
        pending: pendingSync,
        failing: failingSync,
      ),
    );
    final refTile = _BentoTile(
      onTap: onReferralsTap,
      child: _CompactTile(
        icon: Icons.local_hospital_outlined,
        label: 'Open referrals',
        value: referrals,
      ),
    );
    final hhTile = _BentoTile(
      onTap: onFamiliesTap,
      child: _CompactTile(
        icon: Icons.folder_shared_outlined,
        label: 'Households',
        value: households,
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow =
            constraints.maxWidth < 300 ||
            MediaQuery.textScalerOf(context).scale(12) > 18;
        if (narrow) {
          return Column(
            children: [
              queueTile,
              const SizedBox(height: 12),
              dueTile,
              const SizedBox(height: 12),
              syncTile,
              const SizedBox(height: 12),
              refTile,
              const SizedBox(height: 12),
              hhTile,
            ],
          );
        }
        return Column(
          children: [
            queueTile,
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: dueTile),
                const SizedBox(width: 12),
                Expanded(child: syncTile),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: refTile),
                const SizedBox(width: 12),
                Expanded(child: hhTile),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _BentoTile extends StatelessWidget {
  const _BentoTile({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: FhwLuxePalette.hairLine),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    );
    return Semantics(
      button: true,
      child: PressScale(
        onTap: onTap,
        radius: BorderRadius.circular(16),
        child: card,
      ),
    );
  }
}

class _QueueHero extends StatelessWidget {
  const _QueueHero({
    required this.count,
    required this.names,
    this.oldestWaitMinutes,
  });

  final int count;
  final List<String> names;
  final int? oldestWaitMinutes;

  @override
  Widget build(BuildContext context) {
    final wait = oldestWaitMinutes;
    final waitLabel = wait == null
        ? null
        : wait < 60
        ? 'Waiting ${wait}m'
        : 'Waiting ${wait ~/ 60}h ${wait % 60}m';
    return Row(
      children: [
        _AvatarStack(names: names),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PRIORITY QUEUE',
                style: AppType.eyebrow.copyWith(
                  fontSize: 9.5,
                  letterSpacing: 1.1,
                  color: FhwLuxePalette.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                count == 0
                    ? 'Queue clear'
                    : '$count in the clinic queue',
                style: AppType.stat.copyWith(fontSize: 19),
              ),
              if (waitLabel != null) ...[
                const SizedBox(height: 3),
                Text(
                  'Longest wait $waitLabel',
                  style: AppType.caption.copyWith(
                    fontSize: 12,
                    color: FhwLuxePalette.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        const Icon(
          Icons.chevron_right_rounded,
          size: 20,
          color: FhwLuxePalette.textFaint,
        ),
      ],
    );
  }
}

class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.names});

  final List<String> names;

  @override
  Widget build(BuildContext context) {
    final initials = names
        .take(3)
        .map((n) => n.trim().isEmpty ? '?' : n.trim()[0].toUpperCase())
        .toList();
    if (initials.isEmpty) {
      return Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: FhwLuxePalette.sapphireIce,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.people_outline_rounded,
          size: 20,
          color: FhwLuxePalette.sapphireRoyal,
        ),
      );
    }
    return SizedBox(
      width: 44 + (initials.length - 1) * 18,
      height: 44,
      child: Stack(
        children: [
          for (var i = 0; i < initials.length; i++)
            Positioned(
              left: i * 18,
              child: Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: i.isEven
                      ? FhwLuxePalette.sapphireCardGlow
                      : const LinearGradient(
                          colors: [
                            FhwLuxePalette.sapphireDeep,
                            FhwLuxePalette.sapphireElectric,
                          ],
                        ),
                  border: Border.all(
                    color: FhwLuxePalette.cardSurface,
                    width: 2,
                  ),
                ),
                child: Text(
                  initials[i],
                  style: AppType.label.copyWith(
                    fontSize: 12,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DueTodayTile extends StatelessWidget {
  const _DueTodayTile({
    this.due,
    this.overdue,
    this.sessionDone,
    this.sessionTotal,
  });

  final int? due;
  final int? overdue;
  final int? sessionDone;
  final int? sessionTotal;

  @override
  Widget build(BuildContext context) {
    final total = sessionTotal;
    final done = sessionDone;
    final overdue = this.overdue;
    final fraction = (total == null || total == 0)
        ? null
        : (done ?? 0).clamp(0, total) / total;
    final caption = overdue != null && overdue > 0
        ? '$overdue overdue'
        : fraction != null
        ? 'Session $done/$total assessed'
        : 'Scheduled on this phone';
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                due?.toString() ?? '—',
                style: AppType.stat.copyWith(fontSize: 26),
              ),
              const SizedBox(height: 2),
              Text(
                'Due today',
                style: AppType.label.copyWith(
                  fontSize: 12,
                  color: FhwLuxePalette.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.caption.copyWith(
                  fontSize: 11,
                  color: FhwLuxePalette.textFaint,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        _MicroArc(fraction: fraction),
      ],
    );
  }
}

/// A small circular progress arc for session completion. Renders an empty
/// track when there is no session to measure.
class _MicroArc extends StatelessWidget {
  const _MicroArc({this.fraction});

  final double? fraction;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: fraction == null
          ? 'No open session to measure'
          : 'Session ${(fraction! * 100).round()} percent assessed',
      child: SizedBox(
        width: 44,
        height: 44,
        child: CustomPaint(
          painter: _MicroArcPainter(fraction: fraction),
        ),
      ),
    );
  }
}

class _MicroArcPainter extends CustomPainter {
  const _MicroArcPainter({required this.fraction});

  final double? fraction;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 4;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = FhwLuxePalette.pearlSurface;
    canvas.drawCircle(center, radius, track);
    final f = fraction;
    if (f == null || f <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF1B56DB), Color(0xFF2E7BFF)],
      ).createShader(Offset.zero & size);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -3.14159 / 2,
      2 * 3.14159 * f.clamp(0.0, 1.0),
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_MicroArcPainter old) => old.fraction != fraction;
}

class _OfflineTile extends StatelessWidget {
  const _OfflineTile({
    required this.engineReady,
    required this.pending,
    required this.failing,
  });

  final bool engineReady;
  final int? pending;
  final int? failing;

  @override
  Widget build(BuildContext context) {
    final pending = this.pending;
    final failing = this.failing;
    final allClear = engineReady && pending == 0;
    final headline = !engineReady
        ? 'Reading local records'
        : allClear
        ? 'Offline engine ready'
        : '$pending changes waiting';
    final caption = failing != null && failing > 0
        ? '$failing need retry'
        : allClear
        ? 'Zero pending data loss'
        : 'Saved on this phone, sending when able';
    return Row(
      children: [
        BreathingDot(
          size: 7,
          colour: allClear
              ? FhwLuxePalette.emeraldPulse
              : FhwLuxePalette.sapphireElectric,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                headline,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.label.copyWith(fontSize: 12.5),
              ),
              const SizedBox(height: 4),
              Text(
                caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.caption.copyWith(
                  fontSize: 11,
                  color: FhwLuxePalette.textFaint,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CompactTile extends StatelessWidget {
  const _CompactTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final int? value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: FhwLuxePalette.sapphireIce,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 19, color: FhwLuxePalette.sapphireRoyal),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value?.toString() ?? '—',
                style: AppType.stat.copyWith(fontSize: 20),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.label.copyWith(
                  fontSize: 11.5,
                  color: FhwLuxePalette.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
