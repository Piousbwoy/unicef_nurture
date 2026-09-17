/// The frontline health worker's shell.
///
/// Five tabs, in the order a working day actually runs:
///
/// **Today** — a glance: counts and the "Register & assess" button. Opens here
/// because the first question every morning is "what does my day look like?",
/// and the answer is a number, not a list.
///
/// **Queue** — the ranked plan. The detailed queue, with reasons and tags.
///
/// **Assess** — the register with a launch point. Search a household and start
/// a clinical assessment straight from the bottom nav, without first opening
/// the household detail screen.
///
/// **Referrals** — the open work that doesn't depend on a family being in
/// front of you. These need a phone call, not an assessment.
///
/// **Profile** — sync state, account, sign out. Sign-out is here and obvious because
/// handing the phone to a mother for caregiver mode is a normal daily action.
///
/// An [IndexedStack] rather than a `PageView`: switching from Assess back to
/// Today must not re-run the day plan, which is five queries and a scoring pass
/// over the whole zone.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/glass.dart';
import '../../core/theme/motion.dart';
import '../assessment/emergency_tunnel.dart';
import '../shared/ui.dart';
import 'assess_tab.dart';
import 'day_plan_tab.dart';
import 'home_tab.dart';
import 'profile_tab.dart';
import 'referrals_tab.dart';

class FhwHome extends ConsumerStatefulWidget {
  const FhwHome({super.key});

  @override
  ConsumerState<FhwHome> createState() => _FhwHomeState();
}

class _FhwHomeState extends ConsumerState<FhwHome> {
  int _tab = 0;

  static const _titles = ['Today', 'Visits', 'Assess', 'Referrals', 'Profile'];

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final isOnline = ref.watch(connectivityProvider).valueOrNull ?? false;
    if (user == null) return const SizedBox.shrink();

    return VisualEffectsScope(
      child: AmbientBackdrop(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: true,
          appBar: GlassAppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_titles[_tab], style: AppType.title),
                const SizedBox(height: 2),
                Text(
                  user.chpsZone ?? '${user.community}, ${user.district}',
                  style: AppType.caption.copyWith(fontSize: 11.5),
                ),
              ],
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: Gap.md),
                child: Center(child: ConnectivityDot(isOnline: isOnline)),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: () {
                  ref.invalidate(dayPlanProvider);
                  ref.invalidate(visibleHouseholdsProvider);
                  ref.invalidate(decliningChildrenProvider);
                  ref.invalidate(barrierPatternsProvider);
                  ref.invalidate(openReferralsProvider);
                },
                icon: const Icon(Icons.refresh_rounded, size: 20),
              ),
              const SizedBox(width: Gap.xs),
            ],
          ),
          body: IndexedStack(
            index: _tab,
            children: [
              FhwHomeTab(
                onOpenFamilies: () => setState(() => _tab = 2),
                onOpenQueue: () => setState(() => _tab = 1),
              ),
              const DayPlanTab(),
              const AssessTab(),
              const ReferralsTab(),
              const ProfileTab(),
            ],
          ),
          // The emergency tunnel: one red button on every tab, because the
          // convulsing child never arrives while the CHO is on the "right"
          // screen. It asks for no patient, no household, no network — six
          // questions and a verdict. Choosing "full assessment" lands the CHO
          // on the Assess tab. The button is a full-red disc with a white
          // ring: unmissable, but clean against the glass shell.
          floatingActionButton: Padding(
            padding: const EdgeInsets.only(bottom: 72),
            child: PressScale(
              onTap: () async {
                final continueToAssess = await Navigator.of(context).push<bool>(
                  GlassPageRoute<bool>(
                    builder: (_) => const EmergencyTunnelScreen(),
                  ),
                );
                if (continueToAssess == true && mounted) {
                  setState(() => _tab = 2);
                }
              },
              child: Semantics(
                button: true,
                label: 'Emergency',
                child: Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.triageRed,
                        AppColors.triageRed.withValues(alpha: 0.82),
                      ],
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2.5),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.triageRed.withValues(alpha: 0.45),
                        blurRadius: 26,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.emergency_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
            ),
          ),
          bottomNavigationBar: GlassNavBar(
            currentIndex: _tab,
            onTap: (i) => setState(() => _tab = i),
            items: const [
              GlassNavItem(
                icon: Icons.calendar_month_outlined,
                selectedIcon: Icons.calendar_month_rounded,
                label: 'Today',
              ),
              GlassNavItem(
                icon: Icons.people_outlined,
                selectedIcon: Icons.people_rounded,
                label: 'Visits',
              ),
              GlassNavItem(
                icon: Icons.medical_services_outlined,
                selectedIcon: Icons.medical_services_rounded,
                label: 'Assess',
              ),
              GlassNavItem(
                icon: Icons.local_hospital_outlined,
                selectedIcon: Icons.local_hospital_rounded,
                label: 'Referrals',
              ),
              GlassNavItem(
                icon: Icons.person_outlined,
                selectedIcon: Icons.person_rounded,
                label: 'Profile',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
