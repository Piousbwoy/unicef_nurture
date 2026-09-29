/// LumenHero — the Today instrument, reimagined as a sanctuary.
///
/// This replaces the rejected weaving metaphor entirely. There is no cloth and
/// no shuttle. There is a single carved plane of alabaster floating in a field
/// of glacial light, a bar of cold sapphire that holds the day's focal, and a
/// bead of bioluminescent cobalt that pours along a rail to whichever moment the
/// worker chooses. The colour is exactly Luxury White and Luxury Blue; the depth
/// is chiaroscuro; the type is monolithic.
///
/// The signature interaction is the **light well**: three magnetic capsules —
/// Receive, Continue care, Close the loop — sit above a rail of travelling
/// light. Choosing one draws the capsule inward, releases a specular bloom, and
/// pours the cobalt bead to that station while the sapphire plane re-lights to
/// the moment's truth. It changes focus only: it never closes a case or touches
/// a clinical priority. Every control is a real button, so the whole instrument
/// is operable without any of the motion.
///
/// Params are a one-to-one match with the previous hero so the wiring in
/// home_tab is a direct swap. The connection and moment copy is held identical
/// to the contract the tests pin.
library;

import 'package:flutter/services.dart';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/fhw_luxe.dart';
import '../../core/theme/glass.dart';
import '../../core/theme/lumen.dart';

enum _Moment { receive, care, followThrough }

class LumenHero extends StatefulWidget {
  const LumenHero({
    super.key,
    required this.dateLabel,
    required this.zone,
    required this.connectionLabel,
    required this.pendingSync,
    required this.syncFailures,
    required this.householdCount,
    required this.openSessions,
    required this.peopleWaiting,
    required this.dueToday,
    required this.overdue,
    required this.urgentReferrals,
    required this.onReceive,
    required this.onResume,
    required this.onFollowThrough,
    required this.onSync,
  });

  final String dateLabel;
  final String zone;
  final String connectionLabel;
  final int? pendingSync;
  final int? syncFailures;
  final int householdCount;
  final int openSessions;
  final int peopleWaiting;
  final int dueToday;
  final int overdue;
  final int urgentReferrals;
  final VoidCallback onReceive;
  final VoidCallback onResume;
  final VoidCallback onFollowThrough;
  final VoidCallback onSync;

  @override
  State<LumenHero> createState() => _LumenHeroState();
}

class _LumenHeroState extends State<LumenHero> {
  _Moment _moment = _Moment.receive;

  static const _stops = ['Receive', 'Care', 'Close loop'];

  void _select(_Moment value) {
    if (value == _moment) return;
    final forward = value.index > _moment.index;
    // A moment taken up is a firm thunk; stepping back is a light tick.
    if (forward) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.selectionClick();
    }
    setState(() => _moment = value);
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    late final String eyebrow;
    late final String title;
    late final String detail;
    late final String count;
    late final String action;
    late final IconData icon;
    late final VoidCallback callback;

    switch (_moment) {
      case _Moment.receive:
        eyebrow = '01  ·  RECEIVE';
        title = 'Begin with the person here.';
        detail = 'Find an existing record or start a new household encounter.';
        count = '${w.householdCount}';
        action = 'Receive a patient';
        icon = Icons.add_rounded;
        callback = w.onReceive;
      case _Moment.care:
        eyebrow = '02  ·  CONTINUE CARE';
        title = w.peopleWaiting == 0
            ? 'Your clinic queue is clear.'
            : '${w.peopleWaiting} '
                  '${w.peopleWaiting == 1 ? 'person' : 'people'} still waiting.';
        detail = w.openSessions == 0
            ? 'Open a session when someone is ready.'
            : '${w.openSessions} open '
                  '${w.openSessions == 1 ? 'session' : 'sessions'} · '
                  'saved assessments stay in place.';
        count = '${w.peopleWaiting}';
        action = w.peopleWaiting == 0 ? 'Open care reviews' : 'Resume care';
        icon = Icons.arrow_forward_rounded;
        callback = w.onResume;
      case _Moment.followThrough:
        eyebrow = '03  ·  CLOSE THE LOOP';
        title = w.urgentReferrals > 0
            ? '${w.urgentReferrals} urgent '
                  '${w.urgentReferrals == 1 ? 'referral' : 'referrals'} to trace.'
            : w.overdue > 0
            ? '${w.overdue} overdue '
                  '${w.overdue == 1 ? 'contact' : 'contacts'}.'
            : 'Keep planned care moving.';
        detail = '${w.dueToday} due today · ${w.overdue} overdue';
        count = '${w.urgentReferrals + w.overdue + w.dueToday}';
        action = 'Open follow-up';
        icon = Icons.north_east_rounded;
        callback = w.onFollowThrough;
    }

    final urgency = _moment == _Moment.followThrough && w.urgentReferrals > 0;
    final motion = VisualEffects.of(context).motion;

    return AlabasterSheet(
      raised: true,
      blur: true,
      padding: Lux.gallery,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The date anchor, set small and cold so the monolith owns the page.
          Row(
            children: [
              Expanded(
                child: Text(
                  w.dateLabel.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.eyebrow.copyWith(
                    color: FhwLuxePalette.textSecondary,
                    letterSpacing: 1.2,
                    fontSize: 10.5,
                  ),
                ),
              ),
              LumenOrb(
                size: 8,
                breathe: motion,
                colour: urgency
                    ? AppColors.triageRed
                    : FhwLuxePalette.sapphireElectric,
              ),
            ],
          ),
          const SizedBox(height: Lux.md),
          // The wells: three magnetic stations above a rail of travelling light.
          _LightWells(
            index: _moment.index,
            stops: _stops,
            onSelect: (i) => _select(_Moment.values[i]),
          ),
          const SizedBox(height: Lux.md),
          // The sapphire plane — the day's focal, lit from within.
          SapphirePool(
            padding: const EdgeInsets.symmetric(
              horizontal: Lux.md,
              vertical: Lux.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        eyebrow,
                        style: AppType.eyebrow.copyWith(
                          color: Colors.white.withValues(alpha: 0.82),
                          letterSpacing: 1.6,
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(height: 9),
                      PearlText(
                        text: title,
                        maxLines: 3,
                        style: AppType.headline.copyWith(
                          fontSize: 22,
                          height: 1.12,
                          letterSpacing: -0.6,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        detail,
                        style: AppType.caption.copyWith(
                          color: Colors.white.withValues(alpha: 0.82),
                          fontSize: 12.5,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Lux.sm),
                // The monolithic count — structural light, not a stat tile.
                _MonolithFocal(value: count, urgent: urgency),
              ],
            ),
          ),
          const SizedBox(height: Lux.md),
          MagneticCapsule(
            key: const ValueKey('fhw-start-intake'),
            selected: true,
            onTap: callback,
            radius: Gap.radius,
            child: SizedBox(
              height: 54,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 19,
                    color: urgency ? AppColors.triageRed : Colors.white,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      action,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.label.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                        color: urgency ? AppColors.triageRed : Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // The urgency variant lifts the label onto porcelain so red stays a
          // clinical signal, never a decorative hue on a blue mass.
          const SizedBox(height: Lux.sm),
          _ConnectionLine(
            label: w.connectionLabel,
            pending: w.pendingSync,
            failures: w.syncFailures,
            onTap: w.onSync,
          ),
        ],
      ),
    );
  }
}

/// Three magnetic stations with a bead of cobalt light that pours to the active
/// one. The rail is the "clockwork": choosing a station slides the light, not a
/// highlight rectangle, to it.
class _LightWells extends StatelessWidget {
  const _LightWells({
    required this.index,
    required this.stops,
    required this.onSelect,
  });

  final int index;
  final List<String> stops;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final motion = VisualEffects.of(context).motion;
    final duration = VisualEffects.of(context).scale(const Duration(milliseconds: 360));
    // The bead's horizontal home tracks the selected third of the rail.
    final dx = (-1.0 + index) * 0.66;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The travelling light, on a recessed rail above the capsules.
        SizedBox(
          height: 8,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    gradient: Lumen.glacialIce,
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x140B2A6B),
                        blurRadius: 4,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedAlign(
                duration: duration,
                curve: motion ? Curves.easeOutCubic : Curves.linear,
                alignment: Alignment(dx, 0),
                child: Container(
                  width: 62,
                  height: 8,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    gradient: Lumen.sapphireLiquid,
                    boxShadow: Chiaroscuro.bloom(
                      FhwLuxePalette.sapphireElectric,
                      alpha: 0.7,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Lux.sm),
        Semantics(
          container: true,
          label: 'Care sequence',
          child: Row(
            children: [
              for (var i = 0; i < stops.length; i++) ...[
                if (i > 0) const SizedBox(width: Lux.xs + 1),
                Expanded(
                  child: MagneticCapsule(
                    key: ValueKey('lumen-well-$i'),
                    selected: i == index,
                    enableBloom: motion,
                    radius: Gap.radiusSm,
                    onTap: () => onSelect(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        stops[i],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: AppType.label.copyWith(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: i == index
                              ? Colors.white
                              : FhwLuxePalette.sapphireDeep,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The active count as a single monolith of light, guarded against overflow at
/// the accessibility floor by scaling down inside a fixed box.
class _MonolithFocal extends StatelessWidget {
  const _MonolithFocal({required this.value, required this.urgent});

  final String value;
  final bool urgent;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 108),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: Monolith(
        value: value,
        fontSize: 52,
        tone: urgent ? AppColors.triageRed : Colors.white,
        // White numerals already read as lit pearl on the sapphire; keep the
        // pearl mask off so urgency red is not iridescent.
        pearled: !urgent,
      ),
    ),
  );
}

/// The honest connection + sync line — same contract strings as before, set in
/// a recessed glacial trough rather than painted on the sheet.
class _ConnectionLine extends StatelessWidget {
  const _ConnectionLine({
    required this.label,
    required this.pending,
    required this.failures,
    required this.onTap,
  });

  final String label;
  final int? pending;
  final int? failures;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = pending == null
        ? '$label · Sync status unavailable'
        : failures != null && failures! > 0
        ? '$label · $pending waiting · $failures need attention'
        : '$label · '
              '${pending == 0 ? 'No items waiting to send' : '$pending saved on this phone'}';
    return Semantics(
      button: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(
              children: [
                Icon(
                  label == 'Working offline'
                      ? Icons.wifi_off_rounded
                      : Icons.sync_rounded,
                  size: 16,
                  color: FhwLuxePalette.sapphireRoyal,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.caption.copyWith(
                      color: FhwLuxePalette.textSecondary,
                      fontSize: 11.5,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: FhwLuxePalette.textFaint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
