/// The shared UI vocabulary.
///
/// Two rules run through all of it.
///
/// **Colour means triage and nothing else.** The IMCI chart booklet's
/// pink/yellow/green convention is already in every Ghanaian CHO's muscle
/// memory. Reusing it means the app needs no explanation; using red for a
/// decorative accent somewhere would quietly destroy that.
///
/// **Every clinical statement carries its source.** A verdict a CHO cannot
/// interrogate is a verdict they will either follow blindly or ignore entirely,
/// and both of those are worse than a paper register.
///
/// The visual idiom is editorial: warm ivory surfaces, hairline borders,
/// diffuse shadows and generous air. Playfair carries the titles, Inter the
/// information.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/enums.dart';

/// Triage colours, resolved in one place so nothing can drift.
({Color fg, Color bg}) triageColours(TriageLevel level) => switch (level) {
  TriageLevel.urgent => (fg: AppColors.triageRed, bg: AppColors.triageRedBg),
  TriageLevel.priority => (
    fg: AppColors.triageAmber,
    bg: AppColors.triageAmberBg,
  ),
  TriageLevel.watch => (fg: AppColors.triageAmber, bg: AppColors.triageAmberBg),
  TriageLevel.routine => (
    fg: AppColors.triageGreen,
    bg: AppColors.triageGreenBg,
  ),
};

IconData triageIcon(TriageLevel level) => switch (level) {
  TriageLevel.urgent => Icons.priority_high_rounded,
  TriageLevel.priority => Icons.error_outline_rounded,
  TriageLevel.watch => Icons.visibility_outlined,
  TriageLevel.routine => Icons.check_circle_outline_rounded,
};

class TriageBadge extends StatelessWidget {
  const TriageBadge(this.level, {super.key, this.label, this.compact = false});

  final TriageLevel level;
  final String? label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = triageColours(level);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? Gap.sm : Gap.md,
        vertical: compact ? Gap.xs : 6,
      ),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(Gap.radiusSm),
        border: Border.all(color: c.fg.withValues(alpha: 0.30), width: 1),
      ),
      // The label is flexible so a long verdict like "PRIORITY — TREAT AND
      // FOLLOW UP" can never push the badge (or the row containing it) off
      // the screen. In a bounded parent it ellipsises; call sites that put
      // the badge inside a Row should wrap it in [Flexible] for the same
      // reason.
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(triageIcon(level), size: compact ? 13 : 15, color: c.fg),
          const SizedBox(width: Gap.xs),
          Flexible(
            child: Text(
              (label ?? level.label).toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.fg,
                fontWeight: FontWeight.w700,
                fontSize: compact ? 10.5 : 11.5,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A titled block. Used instead of bare [Card] so every section on every screen
/// has the same header weight and the same internal padding.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.icon,
    this.trailing,
    this.accent,
    this.padding = const EdgeInsets.all(Gap.lg),
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final Color? accent;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Gap.radius),
        border: Border.all(color: AppColors.line, width: Gap.hairline),
        boxShadow: const [AppShadows.card],
      ),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: accent ?? AppColors.accent),
                  const SizedBox(width: Gap.sm),
                ],
                Expanded(
                  child: Text(title!, style: AppType.title),
                ),
                if (trailing != null) ?trailing,
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: Gap.xs),
              Text(
                subtitle!,
                style: AppType.caption.copyWith(height: 1.55),
              ),
            ],
            const SizedBox(height: Gap.lg),
          ],
          child,
        ],
      ),
    );
  }
}

/// One clinical finding, with the protocol line it came from.
///
/// The `source` and `measured vs threshold` row is the part that matters. It is
/// what lets a CHO say "the app flagged this because the breathing was 62 and
/// IMCI's cut-off is 60" to a doubtful family, or to a doctor at the referral
/// facility who wants to know why the child was sent.
class FindingTile extends StatelessWidget {
  const FindingTile({
    super.key,
    required this.label,
    required this.detail,
    required this.severity,
    this.source,
    this.measured,
    this.threshold,
  });

  final String label;
  final String detail;
  final TriageLevel severity;
  final String? source;
  final String? measured;
  final String? threshold;

  @override
  Widget build(BuildContext context) {
    final c = triageColours(severity);
    return Container(
      margin: const EdgeInsets.only(bottom: Gap.sm),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(Gap.radius),
        border: Border(left: BorderSide(color: c.fg, width: 3)),
      ),
      padding: const EdgeInsets.all(Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(triageIcon(severity), size: 17, color: c.fg),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.xs),
          Padding(
            padding: const EdgeInsets.only(left: 25),
            child: Text(
              detail,
              style: AppType.body.copyWith(fontSize: 13.5, height: 1.5),
            ),
          ),
          if (measured != null || threshold != null || source != null)
            Padding(
              padding: const EdgeInsets.only(left: 25, top: Gap.sm),
              child: Wrap(
                spacing: Gap.sm,
                runSpacing: Gap.xs,
                children: [
                  if (measured != null)
                    _MetaChip(label: 'Measured', value: measured!),
                  if (threshold != null)
                    _MetaChip(label: 'Cut-off', value: threshold!),
                  if (source != null) _SourceChip(source!),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 3),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(Gap.radiusSm),
      border: Border.all(color: AppColors.line, width: Gap.hairline),
    ),
    child: Text(
      '$label: $value',
      style: AppType.caption.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AppColors.inkMuted,
      ),
    ),
  );
}

class _SourceChip extends StatelessWidget {
  const _SourceChip(this.source);
  final String source;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 3),
    decoration: BoxDecoration(
      color: AppColors.primaryLight,
      borderRadius: BorderRadius.circular(Gap.radiusSm),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.menu_book_outlined, size: 12, color: AppColors.accent),
        const SizedBox(width: 4),
        Text(
          source,
          style: AppType.caption.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.accent,
          ),
        ),
      ],
    ),
  );
}

/// How much the app is willing to stand behind a recommendation.
///
/// Shown on every result, never hidden behind a tap. A system that says "low
/// confidence — three measurements are missing" earns the trust that lets a CHO
/// act on the times it says "protocol certain".
class ConfidenceChip extends StatelessWidget {
  const ConfidenceChip(this.confidence, {super.key, this.missingCount = 0});

  final RecommendationConfidence confidence;
  final int missingCount;

  @override
  Widget build(BuildContext context) {
    final (colour, icon) = switch (confidence) {
      RecommendationConfidence.protocolCertain => (
        AppColors.triageGreen,
        Icons.verified_outlined,
      ),
      RecommendationConfidence.high => (AppColors.accent, Icons.thumb_up_outlined),
      RecommendationConfidence.moderate => (
        AppColors.triageAmber,
        Icons.help_outline_rounded,
      ),
      RecommendationConfidence.low => (
        AppColors.inkMuted,
        Icons.info_outline_rounded,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.sm),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Gap.radiusSm),
        border: Border.all(color: colour.withValues(alpha: 0.28), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colour),
          const SizedBox(width: Gap.xs),
          Flexible(
            child: Text(
              missingCount > 0
                  ? '${confidence.label} · $missingCount item'
                        '${missingCount == 1 ? '' : 's'} not measured'
                  : confidence.label,
              style: TextStyle(
                fontSize: 12,
                color: colour,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The offline banner.
///
/// Phrased as reassurance, because the commonest field fear is that unsent means
/// lost. It never blocks anything and it never asks the CHO to fix the network.
class SyncBanner extends StatelessWidget {
  const SyncBanner({
    super.key,
    required this.pending,
    required this.detail,
    this.failing = 0,
    this.onTap,
  });

  final int pending;
  final int failing;
  final String detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (pending == 0 && failing == 0) return const SizedBox.shrink();
    final isProblem = failing > 0;
    final colour = isProblem ? AppColors.triageAmber : AppColors.offline;
    final bg = isProblem ? AppColors.triageAmberBg : AppColors.offlineBg;

    return Material(
      color: bg,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.lg,
            vertical: Gap.md,
          ),
          child: Row(
            children: [
              Icon(
                isProblem ? Icons.sync_problem_rounded : Icons.cloud_off_rounded,
                size: 17,
                color: colour,
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text(
                  isProblem
                      ? '$failing record${failing == 1 ? '' : 's'} need attention'
                      : '$pending record${pending == 1 ? '' : 's'} saved on this '
                            'phone, waiting for network',
                  style: TextStyle(
                    fontSize: 13,
                    color: colour,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right_rounded, size: 17, color: colour),
            ],
          ),
        ),
      ),
    );
  }
}

/// A persistent connectivity pill — always visible, never blocks anything.
///
/// Unlike the [SyncBanner], which only appears when there are pending records,
/// this pill is always shown so a CHO can tell at a glance whether the device
/// has internet right now. "Online" means the phone has a data connection;
/// "Offline" means it does not, and sync will happen when it returns.
class ConnectivityPill extends StatelessWidget {
  const ConnectivityPill({super.key, required this.isOnline});

  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 6),
      decoration: BoxDecoration(
        color: isOnline
            ? AppColors.triageGreenBg
            : AppColors.offlineBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isOnline
              ? AppColors.triageGreen.withValues(alpha: 0.28)
              : AppColors.offline.withValues(alpha: 0.28),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
            size: 13,
            color: isOnline ? AppColors.triageGreen : AppColors.offline,
          ),
          const SizedBox(width: 6),
          Text(
            isOnline ? 'Online' : 'Offline',
            style: GoogleFonts.manrope(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: isOnline ? AppColors.triageGreen : AppColors.offline,
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(Gap.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Brand-gradient icon medallion — the small visual signature that
          // tells the eye "this is a friendly empty state, not a crash". A
          // flat surface with a hairline border reads as a missing widget
          // and gets tapped once to check.
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              gradient: AppColors.brandGradient,
              shape: BoxShape.circle,
              boxShadow: const [AppShadows.glow],
            ),
            child: Icon(icon, size: 38, color: Colors.white),
          ),
          const SizedBox(height: Gap.lg),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppType.title,
          ),
          const SizedBox(height: Gap.sm),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppType.caption.copyWith(height: 1.55),
          ),
          if (action != null) ...[const SizedBox(height: Gap.xl), action!],
        ],
      ),
    ),
  );
}

/// A labelled figure. Deliberately verbose labels — "Seen this week", not
/// "Visits" — because an unlabelled number on a dashboard is decoration.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.value,
    required this.label,
    this.colour,
    this.icon,
  });

  final String value;
  final String label;
  final Color? colour;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = colour ?? AppColors.ink;
    return Container(
      padding: const EdgeInsets.all(Gap.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Gap.radius),
        border: Border.all(color: AppColors.line, width: Gap.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 17, color: c),
            const SizedBox(height: Gap.sm),
          ],
          Text(
            value,
            style: AppType.display.copyWith(
              fontSize: 30,
              color: c,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: Gap.xs),
          Text(
            label,
            style: AppType.caption.copyWith(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

/// A form field label with an optional "why we ask" line.
///
/// The explanation is not decoration. A CHO who understands that walking time is
/// asked because it predicts referral failure will give a real answer instead of
/// the first number that dismisses the keyboard.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.label, {super.key, this.why, this.required = false});

  final String label;
  final String? why;
  final bool required;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Gap.sm),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label.toUpperCase(),
              style: AppType.eyebrow.copyWith(color: AppColors.ink),
            ),
            if (required)
              const Text(
                ' *',
                style: TextStyle(color: AppColors.triageRed, fontSize: 13),
              ),
          ],
        ),
        if (why != null) ...[
          const SizedBox(height: 3),
          Text(
            why!,
            style: AppType.caption.copyWith(fontSize: 11.5, height: 1.4),
          ),
        ],
      ],
    ),
  );
}

/// A large yes/no pair.
///
/// Sized for a thumb, because these are answered one-handed while the other hand
/// holds a baby. "Not sure" is a first-class answer rather than a hidden one: a
/// forced guess enters the record as fact, and the confidence machinery cannot
/// tell the difference afterwards.
class YesNoField extends StatelessWidget {
  const YesNoField({
    super.key,
    required this.value,
    required this.onChanged,
    this.yesLabel = 'Yes',
    this.noLabel = 'No',
    this.allowUnknown = false,
    this.dangerOnYes = false,
  });

  final bool? value;
  final ValueChanged<bool?> onChanged;
  final String yesLabel;
  final String noLabel;
  final bool allowUnknown;
  final bool dangerOnYes;

  @override
  Widget build(BuildContext context) {
    Widget option(String text, bool? optionValue, Color selectedColour) {
      final selected = value == optionValue;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.only(right: Gap.sm),
          child: Material(
            color: selected
                ? selectedColour.withValues(alpha: 0.08)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(Gap.radiusSm),
            child: InkWell(
              borderRadius: BorderRadius.circular(Gap.radiusSm),
              onTap: () => onChanged(optionValue),
              child: Container(
                height: Gap.tapTarget,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Gap.radiusSm),
                  border: Border.all(
                    color: selected ? selectedColour : AppColors.line,
                    width: selected ? 1.4 : Gap.hairline,
                  ),
                ),
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: selected ? selectedColour : AppColors.inkMuted,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        option(
          yesLabel,
          true,
          dangerOnYes ? AppColors.triageRed : AppColors.accent,
        ),
        option(noLabel, false, AppColors.triageGreen),
        if (allowUnknown) option('Not sure', null, AppColors.inkMuted),
      ],
    );
  }
}

/// Shows the reason a screen is refusing, rather than an empty list.
///
/// The wording is written for the person holding the phone — a mother who has
/// been handed the handset, not a developer reading a stack trace.
class AccessDeniedView extends StatelessWidget {
  const AccessDeniedView({super.key, required this.message, this.onBack});

  final String message;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: Icons.lock_outline_rounded,
    title: 'Not available on this account',
    message: message,
    action: onBack == null
        ? null
        : OutlinedButton(onPressed: onBack, child: const Text('Go back')),
  );
}

/// Standard error presentation for a failed async read. Shows the cause, because
/// "something went wrong" wastes a field visit.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: Icons.warning_amber_rounded,
    title: 'Could not load this',
    message: '$error',
    action: onRetry == null
        ? null
        : FilledButton(onPressed: onRetry, child: const Text('Try again')),
  );
}

/// A subtle, premium press affordance for any tappable surface.
///
/// A real button or card feels different from a flat rectangle the instant a
/// thumb lands on it. This wraps [child] in a [GestureDetector] that, on
/// press-down, scales the child to [pressedScale] and (optionally) swaps in
/// a stronger shadow; on release it springs back via the same eased curve
/// the rest of the app's motion uses ([AppMotion.curve]).
///
/// Two pressures drove the design. The press has to be obvious enough that a
/// CHW on a cracked screen in the sun feels that something happened, and
/// subtle enough that the eye does not chase every interaction across the
/// dashboard. The scale sits at 0.97 — felt, not seen.
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.pressedScale = 0.97,
    this.duration = const Duration(milliseconds: 110),
    this.radius,
    this.hoverLift = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressedScale;
  final Duration duration;
  final BorderRadius? radius;

  /// When true, a pointer hovering over the surface (mouse / trackpad on
  /// desktop / web) lifts the shadow by a touch. Off by default because
  /// touch-first field workers do not need it and the hover state is
  /// reserved for desktop demos.
  final bool hoverLift;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final radius = widget.radius;
    final clip = radius != null
        ? ClipRRect(
            borderRadius: radius,
            child: _scaledChild(),
          )
        : _scaledChild();
    return MouseRegion(
      onEnter: (_) {
        if (widget.hoverLift) setState(() => _hovering = true);
      },
      onExit: (_) {
        if (widget.hoverLift && _hovering) {
          setState(() => _hovering = false);
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.onTap == null
            ? null
            : (_) => setState(() => _down = true),
        onTapCancel: widget.onTap == null
            ? null
            : () => setState(() => _down = false),
        onTapUp: widget.onTap == null
            ? null
            : (_) => setState(() => _down = false),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: clip,
      ),
    );
  }

  Widget _scaledChild() {
    final t = _down ? widget.pressedScale : 1.0;
    return AnimatedScale(
      scale: t,
      duration: widget.duration,
      curve: AppMotion.curve,
      child: widget.child,
    );
  }
}

/// A 3px brand-gradient line, used as a visual signature on top of major
/// cards (the role choice, the FHW hero, anything that wants to feel like a
/// flagship product surface rather than a plain rectangle).
class BrandAccent extends StatelessWidget {
  const BrandAccent({super.key, this.height = 3, this.radius});

  final double height;
  final BorderRadius? radius;

  @override
  Widget build(BuildContext context) {
    final line = Container(
      height: height,
      decoration: const BoxDecoration(gradient: AppColors.brandGradient),
    );
    if (radius == null) return line;
    return ClipRRect(
      borderRadius: radius!,
      child: line,
    );
  }
}
