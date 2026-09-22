import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/glass.dart';
import '../shared/narration_button.dart';
import '../shared/ui.dart';
import 'caregiver_providers.dart';
import 'care_plan/care_plan_tab.dart';
import 'check/check_tab.dart';
import 'family/family_tab.dart';
import 'growth/grow_play_tab.dart';
import 'help/help_tab.dart';
import 'help/caregiver_voice.dart';
import 'widgets/companion.dart';

class CaregiverHome extends ConsumerStatefulWidget {
  const CaregiverHome({super.key});
  @override
  ConsumerState<CaregiverHome> createState() => _CaregiverHomeState();
}

class _CaregiverHomeState extends ConsumerState<CaregiverHome> {
  int _tab = 0;
  String? _identity;
  void _switch(int tab) {
    final scope = ref.read(caregiverScopeProvider);
    if (scope != null) ref.read(caregiverVoiceProvider(scope)).stop();
    setState(() => _tab = tab);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final scope = ref.watch(caregiverScopeProvider);
    final isOnline = ref.watch(connectivityProvider).valueOrNull ?? false;
    // Trigger neural model loading in background (non-blocking; UI works
    // with English + dictionary until models are ready, then upgrades).
    ref.read(neuralTranslationProvider.future);
    ref.read(piperTtsProvider.future);
    if (user == null) return const SizedBox.shrink();
    if (scope == null) {
      return CompanionTheme(
        child: Scaffold(
          backgroundColor: AppColors.caregiverCanvas,
          appBar: AppBar(
            title: const Text(
              'CareBridge AI',
              style: TextStyle(fontFamily: 'Sora', fontWeight: FontWeight.w700),
            ),
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.family_restroom_rounded,
                        color: AppColors.primary,
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Your family is not linked to this phone yet',
                      style: TextStyle(
                        fontFamily: 'Sora',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Ask your health worker to help link your family.',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.inkMuted,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    OutlinedButton.icon(
                      onPressed: () =>
                          ref.read(sessionProvider.notifier).signOut(),
                      icon: const Icon(Icons.logout_rounded, size: 18),
                      label: const Text('Sign out'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    final identity = '${scope.userId}/${scope.householdId}';
    if (_identity != identity) {
      _identity = identity;
      _tab = 0;
    }
    ref.watch(caregiverWriterProvider(scope));
    ref.watch(caregiverCalendarProvider);
    ref.watch(caregiverVoiceProvider(scope));
    final household = scope.householdId;
    return CompanionTheme(
      // White canvas; the deep-navy identity lives on the cards.
      child: AmbientBackdrop(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: GlassAppBar(
            title: const Text(
              'My family',
              style: TextStyle(
                fontFamily: 'Sora',
                fontWeight: FontWeight.w700,
                fontSize: 20,
              ),
            ),
            actions: [
              const NarrationButton(compact: true),
              const CaregiverEmergencyButton(),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(child: ConnectivityDot(isOnline: isOnline)),
              ),
            ],
          ),
          body: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
            child: KeyedSubtree(
              key: ValueKey('$identity/$_tab'),
              child: switch (_tab) {
                0 => CaregiverFamilyTab(
                  householdId: household,
                  onSwitch: _switch,
                ),
                1 => CaregiverCheckTab(householdId: household),
                2 => CaregiverGrowPlayTab(householdId: household),
                3 => CaregiverCarePlanTab(householdId: household),
                _ => CaregiverHelpTab(householdId: household),
              },
            ),
          ),
          bottomNavigationBar: CaregiverNavigation(
            index: _tab,
            onSelect: _switch,
          ),
        ),
      ),
    );
  }
}

class CaregiverNavigation extends StatelessWidget {
  const CaregiverNavigation({
    super.key,
    required this.index,
    required this.onSelect,
  });
  final int index;
  final ValueChanged<int> onSelect;
  static const labels = ['Family', 'Check', 'Grow & Play', 'Care plan', 'Help'];
  static const icons = [
    Icons.family_restroom_rounded,
    Icons.health_and_safety_outlined,
    Icons.toys_outlined,
    Icons.event_note_outlined,
    Icons.support_agent_outlined,
  ];
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.caregiverCanvas,
      border: Border(
        top: BorderSide(color: AppColors.line, width: 1),
      ),
    ),
    child: SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, size) {
          final columns =
              size.maxWidth < 360 ||
                  MediaQuery.textScalerOf(context).scale(14) > 20
              ? 3
              : 5;
          return Wrap(
            children: [
              for (var i = 0; i < labels.length; i++)
                SizedBox(
                  width: size.maxWidth / columns,
                  child: Semantics(
                    selected: index == i,
                    button: true,
                    label: labels[i],
                    child: InkWell(
                      onTap: () => onSelect(i),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 64),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 10,
                          ),
                          child: ExcludeSemantics(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  curve: Curves.easeOut,
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: index == i
                                        ? AppColors.primary.withValues(alpha: 0.12)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 200),
                                    child: Icon(
                                      icons[i],
                                      key: ValueKey('${icons[i]}_$i'),
                                      color: index == i
                                          ? AppColors.primary
                                          : AppColors.caregiverMuted,
                                      size: index == i ? 24 : 22,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 200),
                                  curve: Curves.easeOut,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: index == i
                                        ? FontWeight.w800
                                        : FontWeight.w500,
                                    color: index == i
                                        ? AppColors.primary
                                        : AppColors.caregiverMuted,
                                  ),
                                  child: Text(
                                    labels[i],
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}
