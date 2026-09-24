import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/fhw_luxe.dart';
import '../assessment/emergency_tunnel.dart';
import '../shared/narration_button.dart';
import 'assess_tab.dart';
import 'day_plan_tab.dart';
import 'home_tab.dart';
import 'luxe_components.dart';
import 'luxe_motion.dart';
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
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SizedBox.shrink();
    final queue = ref.watch(clinicQueueProvider);
    final waiting = queue.valueOrNull?.length ?? 0;

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
            onReceive: _receive,
            onEmergency: _emergency,
            onRefresh: refreshClinicWorkspace,
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
        child: Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Care reviews'),
                selected: _followUpTab == 0,
                onSelected: (_) => setState(() => _followUpTab = 0),
              ),
              ChoiceChip(
                label: const Text('Referrals'),
                selected: _followUpTab == 1,
                onSelected: (_) => setState(() => _followUpTab = 1),
              ),
            ],
          ),
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

/// The deep-blue gradient header that replaces the old flat white AppBar and the
/// red strip. It is fixed chrome above every tab: a time-of-day greeting, the
/// worker's name and CHPS zone, a live queue count, a brass-edged "Receive
/// patient" pill, and the emergency action — still unmistakably red, because
/// red belongs to clinical safety and nothing else — docked beside it rather
/// than eating a band of body height. A radial light sheen over the midnight
/// blue gives the surface depth, so it reads as luxurious lit glass.
class _ClinicHeader extends StatelessWidget {
  const _ClinicHeader({
    required this.greeting,
    required this.name,
    required this.zone,
    required this.waiting,
    required this.queueLoading,
    required this.onReceive,
    required this.onEmergency,
    required this.onRefresh,
  });

  final String greeting;
  final String name;
  final String zone;
  final int waiting;
  final bool queueLoading;
  final VoidCallback onReceive;
  final VoidCallback onEmergency;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.only(
      bottomLeft: Radius.circular(32),
      bottomRight: Radius.circular(32),
    );
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: FhwLuxePalette.sapphireHeroGradient,
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Color(0x59050F26),
            blurRadius: 34,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            // Depth: a cool light pools from the top-right and a faint royal
            // glow lifts from the bottom-left — the lit-glass sheen that
            // separates a luxurious surface from a flat blue block.
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0.9, -0.7),
                    radius: 1.2,
                    colors: [Color(0x2E9FC4FF), Color(0x00000000)],
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
                    colors: [Color(0x261B56DB), Color(0x00000000)],
                  ),
                ),
              ),
            ),
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 10, 18, 22),
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
                                  color: Colors.white.withValues(alpha: 0.66),
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppType.title.copyWith(
                                  fontSize: 25,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 9),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Flexible(
                                    child: Row(
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
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(child: _ReceivePill(onTap: onReceive)),
                        const SizedBox(width: 10),
                        _EmergencyDock(onTap: onEmergency),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A quiet brass-edged chip reporting how many patients are still open in the
/// clinic queue. Brass is chrome; it never carries a clinical verdict.
class _QueueBadge extends StatelessWidget {
  const _QueueBadge({required this.waiting, required this.loading});

  final int waiting;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final label = loading
        ? 'Checking queue\u2026'
        : waiting == 0
        ? 'Queue clear'
        : '$waiting in the queue';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: FhwLuxePalette.glassBorderLight),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!loading)
            const Padding(
              padding: EdgeInsets.only(right: 5),
              child: BreathingDot(size: 6),
            ),
          const Icon(
            Icons.groups_rounded,
            size: 13,
            color: FhwLuxePalette.sapphireElectric,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppType.label.copyWith(fontSize: 11.5, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

/// The premium receiving action: a translucent pill edged in brass.
class _ReceivePill extends StatelessWidget {
  const _ReceivePill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: Gap.tapTarget,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.30),
                Colors.white.withValues(alpha: 0.12),
              ],
            ),
            border: Border.all(
              color: FhwLuxePalette.glassBorderLight,
              width: 1.2,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x2E000000),
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.16),
                ),
                child: const Icon(
                  Icons.add_rounded,
                  color: Colors.white,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  'Receive patient',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: AppType.label.copyWith(
                    color: Colors.white,
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
/// safety and nothing else — but it is rendered as a lit crimson-to-deep-red
/// gradient with a soft red glow, a bevelled light edge and an alert glyph in
/// a glass badge, so it reads as a premium, urgent control rather than a flat
/// block. The ValueKey and label are unchanged.
class _EmergencyDock extends StatelessWidget {
  const _EmergencyDock({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey('fhw-emergency'),
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: Gap.tapTarget,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFE5393F), Color(0xFFB0141C)],
            ),
            border: Border.all(color: Color(0x4DFFFFFF), width: 1),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66B0141C),
                blurRadius: 22,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.34),
                    width: 1,
                  ),
                ),
                child: const Icon(
                  Icons.emergency_rounded,
                  color: Colors.white,
                  size: 15,
                ),
              ),
              const SizedBox(width: 9),
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

/// A frosted circular chip that hosts an icon-only control on the deep-blue
/// header. Narration and refresh share it so the tertiary tier reads as a
/// deliberate, tappable pair rather than two bare default icons.
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
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.20),
            Colors.white.withValues(alpha: 0.05),
          ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.26),
          width: 1,
        ),
      ),
      child: child,
    );
  }
}
