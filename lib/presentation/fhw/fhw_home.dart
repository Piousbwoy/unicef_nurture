/// The frontline health worker's shell.
///
/// Five tabs, in the order a working day actually runs:
///
/// **Home** — a glance: counts and the "Register & assess" button. Opens here
/// because the first question every morning is "what does my day look like?",
/// and the answer is a number, not a list.
///
/// **Day plan** — the ranked plan. The detailed queue, with reasons and tags.
///
/// **Assess** — the register with a launch point. Search a household and start
/// a clinical assessment straight from the bottom nav, without first opening
/// the household detail screen.
///
/// **Referrals** — the open work that doesn't depend on a family being in
/// front of you. These need a phone call, not an assessment.
///
/// **Me** — sync state, account, sign out. Sign-out is here and obvious because
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

  static const _titles = [
    'Today',
    'Your day plan',
    'Assess',
    'Referrals',
    'My account',
  ];

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SizedBox.shrink();

    return Scaffold(
      appBar: AppBar(
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
          ),
          const DayPlanTab(),
          const AssessTab(),
          const ReferralsTab(),
          const ProfileTab(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        onTap: (i) => setState(() => _tab = i),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.today_outlined),
            activeIcon: Icon(Icons.today_rounded),
            label: 'Day plan',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.fact_check_outlined),
            activeIcon: Icon(Icons.fact_check_rounded),
            label: 'Assess',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.local_hospital_outlined),
            activeIcon: Icon(Icons.local_hospital_rounded),
            label: 'Referrals',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline_rounded),
            activeIcon: Icon(Icons.person_rounded),
            label: 'Me',
          ),
        ],
      ),
    );
  }
}
