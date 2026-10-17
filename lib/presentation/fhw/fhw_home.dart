import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/fhw_luxe.dart';
import '../assessment/emergency_tunnel.dart';
import '../shared/narration_button.dart';
import 'assess_tab.dart';
import 'clinic_widgets.dart' show DeskFilterBar;
import 'day_plan_tab.dart';
import 'home_tab.dart';
import 'luxe_components.dart';
import 'profile_tab.dart';
import 'receive_patient_sheet.dart';
import 'referrals_tab.dart';

class FhwHome extends ConsumerStatefulWidget {
  const FhwHome({super.key});

  @override
  ConsumerState<FhwHome> createState() => _FhwHomeState();
}

class _FhwHomeState extends ConsumerState<FhwHome> {
  int _tab = 0;
  int _followUpTab = 0;
  final _opened = <int>{0};
  static const _titles = ['Today', 'Patients', 'Follow-up', 'Me'];
  static const _icons = [
    Icons.space_dashboard_outlined,
    Icons.people_outline_rounded,
    Icons.fact_check_outlined,
    Icons.person_outline_rounded,
  ];

  void _select(int tab, {int? followUpTab}) => setState(() {
    _tab = tab;
    _opened.add(tab);
    if (followUpTab != null) _followUpTab = followUpTab;
  });

  @override
  Widget build(BuildContext context) {
    ref.watch(fhwLanguageWarmupProvider);
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SizedBox.shrink();
    final queue = ref.watch(clinicQueueProvider);
    final waiting = queue.valueOrNull?.length ?? 0;
    // The hero's two honest readouts — how many records this phone holds, and
    // what is still waiting to sync — now live on the header, so the Today tab
    // is one panel rather than a header stacked on a second hero.
    final householdCount =
        ref.watch(visibleHouseholdsProvider).valueOrNull?.length ?? 0;
    final sync = ref.watch(syncStatusProvider).valueOrNull;
    final connection = ref
        .watch(connectivityProvider)
        .when(
          data: (online) => online ? 'Network available' : 'Working offline',
          error: (_, _) => 'Connection unknown',
          loading: () => 'Checking connection',
        );

    return Scaffold(
      backgroundColor: FhwLuxePalette.porcelainCanvas,
      body: Column(
        children: [
          _ClinicHeader(
            greeting: _greeting(),
            name: user.fullName.split(' ').first,
            zone: user.chpsZone ?? user.community,
            waiting: waiting,
            queueLoading: queue.isLoading,
            queueError: queue.hasError,
            householdCount: householdCount,
            connectionLabel: connection,
            pendingSync: sync?.pending,
            syncFailures: sync?.failing,
            onReceive: _receive,
            onEmergency: _emergency,
            onRefresh: refreshClinicWorkspace,
            onOpenQueue: () => _select(2, followUpTab: 0),
            onOpenRecords: () => _select(1),
            onSync: () => _select(3),
            onRetryQueue: () => ref.invalidate(clinicQueueProvider),
          ),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                TickerMode(
                  enabled: _tab == 0,
                  child: FhwHomeTab(
                    onOpenFamilies: () => _select(1),
                    onOpenQueue: () => _select(2, followUpTab: 0),
                    onOpenReferrals: () => _select(2, followUpTab: 1),
                    onOpenProfile: () => _select(3),
                  ),
                ),
                TickerMode(
                  enabled: _tab == 1,
                  child: _opened.contains(1)
                      ? const AssessTab()
                      : const SizedBox.shrink(),
                ),
                TickerMode(
                  enabled: _tab == 2,
                  child: _opened.contains(2)
                      ? _followUp()
                      : const SizedBox.shrink(),
                ),
                TickerMode(
                  enabled: _tab == 3,
                  child: _opened.contains(3)
                      ? const ProfileTab()
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: FloatingAcrylicDock(
        index: _tab,
        titles: _titles,
        icons: _icons,
        onSelect: _select,
      ),
    );
  }

  Widget _followUp() => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
        child: DeskFilterBar(
          options: const ['Care reviews', 'Referrals'],
          selectedIndex: _followUpTab,
          onSelected: (index) => setState(() => _followUpTab = index),
        ),
      ),
      Expanded(
        child: IndexedStack(
          index: _followUpTab,
          children: [
            TickerMode(enabled: _followUpTab == 0, child: const DayPlanTab()),
            TickerMode(enabled: _followUpTab == 1, child: const ReferralsTab()),
          ],
        ),
      ),
    ],
  );

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  Future<void> _receive() async {
    final households =
        ref.read(visibleHouseholdsProvider).valueOrNull ?? const [];
    await showReceivePatientSheet(context, knownHouseholds: households);
    if (mounted) refreshClinicWorkspace();
  }

  void refreshClinicWorkspace() {
    ref.invalidate(dayPlanProvider);
    ref.invalidate(visibleHouseholdsProvider);
    ref.invalidate(openReferralsProvider);
    ref.invalidate(zoneHomeChecksProvider);
    ref.invalidate(activeClinicSessionProvider);
    ref.invalidate(clinicQueueProvider);
    ref.invalidate(dailyRegisterProvider);
    ref.invalidate(syncStatusProvider);
  }

  Future<void> _emergency() async {
    final assess = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const EmergencyTunnelScreen()),
    );
    if (assess == true && mounted) _select(1);
  }
}

/// The matte command-navy header that sits above every tab. Where the earlier
/// chrome pooled light and glowed, this band is deliberately flat: an
/// operations console reads as structure, not atmosphere. A time-of-day
/// greeting, the worker's name and CHPS zone, a live queue count, one solid
/// white receive action, and the emergency control — still unmistakably red,
/// because red belongs to clinical safety and nothing else — docked beside it.
/// Square corners and a hairline under the band keep it chrome; every control
/// on it is solid, with no glow or gradient to soften it.
class _ClinicHeader extends StatelessWidget {
  const _ClinicHeader({
    required this.greeting,
    required this.name,
    required this.zone,
    required this.waiting,
    required this.queueLoading,
    required this.queueError,
    required this.householdCount,
    required this.connectionLabel,
    required this.pendingSync,
    required this.syncFailures,
    required this.onReceive,
    required this.onEmergency,
    required this.onRefresh,
    required this.onOpenQueue,
    required this.onOpenRecords,
    required this.onSync,
    required this.onRetryQueue,
  });

  final String greeting;
  final String name;
  final String zone;
  final int waiting;
  final bool queueLoading;
  final bool queueError;
  final int householdCount;
  final String connectionLabel;
  final int? pendingSync;
  final int? syncFailures;
  final VoidCallback onReceive;
  final VoidCallback onEmergency;
  final VoidCallback onRefresh;
  final VoidCallback onOpenQueue;
  final VoidCallback onOpenRecords;
  final VoidCallback onSync;
  final VoidCallback onRetryQueue;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        // Deep sapphire lacquer: the command bar reads as a solid of dyed
        // depth — lit toward the crown and settling darker at the base — so the
        // desk opens on a made object rather than a flat navy slab. Held dark
        // end-to-end so every white control keeps field-sunlight contrast: this
        // is structure with mass, not atmosphere. The top hairline is the
        // lacquer catching the key light.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            FhwLuxePalette.sapphireDeep,
            FhwLuxePalette.commandNavy,
            FhwLuxePalette.sapphireGroove,
          ],
          stops: [0.0, 0.52, 1.0],
        ),
        border: Border(
          top: BorderSide(color: Color(0x1FFFFFFF), width: 1),
          bottom: BorderSide(color: Color(0x33000000)),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 10, 18, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          greeting.toUpperCase(),
                          style: AppType.eyebrow.copyWith(
                            color: Colors.white.withValues(alpha: 0.6),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.title.copyWith(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 9),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            // A Wrap hands its children unbounded width,
                            // so `Flexible` is invalid here and throws at
                            // build time; the line needs its own ceiling
                            // for the ellipsis to have anything to work
                            // against.
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 220),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.place_outlined,
                                    size: 13,
                                    color: Colors.white70,
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      zone,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppType.caption.copyWith(
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            _QueueBadge(
                              waiting: waiting,
                              loading: queueLoading,
                              error: queueError,
                              onTap: queueError ? onRetryQueue : onOpenQueue,
                            ),
                            _RecordBadge(
                              count: householdCount,
                              onTap: onOpenRecords,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  _HeaderIconChip(
                    child: const NarrationButton(iconColor: Colors.white),
                  ),
                  const SizedBox(width: 6),
                  _HeaderIconChip(
                    child: IconButton(
                      tooltip: 'Refresh local records',
                      onPressed: onRefresh,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 48,
                        height: 48,
                      ),
                      color: Colors.white,
                      iconSize: 22,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _ReceivePill(onTap: onReceive)),
                  const SizedBox(width: 10),
                  _EmergencyDock(onTap: onEmergency),
                ],
              ),
              const SizedBox(height: 12),
              // The honest sync readout, moved up from the old second hero: a
              // plain instrument line, not a glowing panel.
              _ConnectionLine(
                label: connectionLabel,
                pending: pendingSync,
                failures: syncFailures,
                onTap: onSync,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A quiet chip reporting how many patients are still open in the clinic
/// queue. It reads as a static status instrument — a plain dot, never a
/// pulsing one — because chrome reports state; it does not perform it. It is
/// the one way into the live queue from the dashboard, so it takes a tap.
class _QueueBadge extends StatelessWidget {
  const _QueueBadge({
    required this.waiting,
    required this.loading,
    required this.error,
    required this.onTap,
  });

  final int waiting;
  final bool loading;
  final bool error;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = error
        ? 'Queue check failed · tap to retry'
        : loading
        ? 'Checking queue\u2026'
        : waiting == 0
        ? 'Queue clear'
        : '$waiting in the queue';
    return _HeaderPill(
      onTap: onTap,
      semanticsLabel: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!loading && !error)
            Padding(
              padding: const EdgeInsets.only(right: 5),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: waiting == 0
                      ? Colors.white.withValues(alpha: 0.4)
                      : FhwLuxePalette.sapphireElectric,
                ),
              ),
            ),
          Icon(
            error ? Icons.refresh_rounded : Icons.groups_rounded,
            size: 15,
            color: Colors.white,
          ),
          const SizedBox(width: 6),
          // The label can be as long as 'Queue check failed · tap to retry',
          // so it shrinks-and-ellipsizes inside the pill instead of ever
          // overflowing the header row on a narrow phone.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.label.copyWith(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The shared chrome for a tappable status pill on the navy header. The queue
/// and record counts sit in identical pills, so the two read as one set of
/// instruments rather than two ad-hoc chips.
class _HeaderPill extends StatelessWidget {
  const _HeaderPill({
    required this.onTap,
    required this.semanticsLabel,
    required this.child,
  });

  final VoidCallback onTap;
  final String semanticsLabel;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: semanticsLabel,
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
          ),
          child: child,
        ),
      ),
    ),
  );
}

/// How many households this phone holds, seated beside the queue count. It is
/// the record inventory the old hero carried, now a quiet instrument that
/// opens the register when tapped.
class _RecordBadge extends StatelessWidget {
  const _RecordBadge({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _HeaderPill(
    onTap: onTap,
    semanticsLabel: '$count households on record',
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.home_work_rounded, size: 15, color: Colors.white),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            '$count on record',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.label.copyWith(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
      ],
    ),
  );
}

/// The honest connection + sync line — same contract strings as the hero it
/// replaces, set as a plain instrument row beneath the actions.
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
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: [
                Icon(
                  label == 'Working offline'
                      ? Icons.wifi_off_rounded
                      : Icons.sync_rounded,
                  size: 16,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.caption.copyWith(
                      color: Colors.white.withValues(alpha: 0.66),
                      fontSize: 11.5,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: Colors.white54,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The primary receiving action: a solid white control on the navy band. On
/// matte chrome, one solid white button reads as the one way forward — no
/// gradient, no glow, just the highest-contrast action on the screen.
class _ReceivePill extends StatelessWidget {
  const _ReceivePill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: Gap.tapTarget,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.add_rounded,
                color: FhwLuxePalette.commandNavy,
                size: 19,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  'Receive patient',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: AppType.label.copyWith(
                    color: FhwLuxePalette.commandNavy,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
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

/// The danger action. It stays unmistakably red — red belongs to clinical
/// safety and nothing else — rendered flat and matte beside the white receive
/// action, so the two read as one instrument row: one way in, one way fast.
/// The ValueKey and label are unchanged.
class _EmergencyDock extends StatelessWidget {
  const _EmergencyDock({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey('fhw-emergency'),
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: Gap.tapTarget,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.triageRed,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.emergency_rounded,
                color: Colors.white,
                size: 17,
              ),
              const SizedBox(width: 8),
              Text(
                'Emergency',
                style: AppType.label.copyWith(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A flat circular seat for an icon-only control on the navy header.
/// Narration and refresh share it so the tertiary tier reads as a deliberate,
/// tappable pair rather than two bare default icons.
class _HeaderIconChip extends StatelessWidget {
  const _HeaderIconChip({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.08),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.16),
          width: 1,
        ),
      ),
      child: child,
    );
  }
}
