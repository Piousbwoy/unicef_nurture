import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/motion.dart';
import '../../../domain/entities/caregiver.dart';
import '../../../domain/entities/core.dart';
import '../../../domain/family_code.dart';
import '../../../domain/services/caregiver_today_planner.dart';
import '../../shared/app_image.dart';
import '../caregiver_providers.dart';
import '../check/check_widgets.dart';
import '../check/triage_screen.dart';
import '../food/food_page.dart';
import '../help/audio_guide_screen.dart';
import '../widgets/companion.dart';
import '../widgets/premium_button.dart';
import 'add_member.dart';
import 'person_detail.dart';

/// The caregiver dashboard, dressed in the flow's one identity: deep navy.
///
/// Every card here is a shade of the same dark blue — navy glass, white ink,
/// one royal-blue accent — so the screen reads as a single premium surface.
/// Red appears for danger only, exactly as IMCI training expects.
class CaregiverFamilyTab extends ConsumerWidget {
  const CaregiverFamilyTab({
    super.key,
    required this.householdId,
    required this.onSwitch,
  });
  final String householdId;
  final ValueChanged<int> onSwitch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final scope = ref.watch(caregiverScopeProvider);
    if (scope == null) return const SizedBox.shrink();
    final now = ref.watch(caregiverCalendarProvider).toLocal();
    final part = now.hour < 12
        ? 'Good morning'
        : now.hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    final name = user?.fullName.trim().split(RegExp(r'\s+')).first ?? 'Friend';
    final members = ref.watch(householdMembersProvider(householdId));
    final settings = ref.watch(caregiverSettingsProvider(scope));
    final day = ref.watch(caregiverTodayProvider(scope));
    final selected = settings.valueOrNull?.selectedPersonId;
    final writer = ref.watch(caregiverWriterProvider(scope));
    void check([String? personId]) => Navigator.of(context).push(
      GlassPageRoute<void>(
        builder: (_) => CaregiverTriageScreen(
          householdId: householdId,
          personId: personId ?? selected,
          onDone: () => onSwitch(0),
        ),
      ),
    );
    Future<void> open(CaregiverFocus focus) async {
      switch (focus.route) {
        case CaregiverFocusRoute.check:
          check(focus.personId);
        case CaregiverFocusRoute.food:
          await Navigator.of(context).push(
            GlassPageRoute<void>(
              builder: (_) => CaregiverFoodPage(
                householdId: householdId,
                personId: focus.personId,
              ),
            ),
          );
        case CaregiverFocusRoute.carePlan:
        case CaregiverFocusRoute.play:
        case CaregiverFocusRoute.help:
          await writer.settings(
            (s) => s.copyWith(selectedPersonId: focus.personId),
          );
          if (context.mounted) {
            onSwitch(switch (focus.route) {
              CaregiverFocusRoute.carePlan => 3,
              CaregiverFocusRoute.play => 2,
              _ => 4,
            });
          }
      }
    }

    Widget focusCard(CaregiverFocus focus, String dateKey) =>
        CaregiverFocusCard(
          focus: focus,
          dateKey: dateKey,
          person: members.valueOrNull
              ?.where((p) => p.id == focus.personId)
              .firstOrNull,
          onOpen: () => open(focus),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      children: [
        _FamilyHero(part: part, name: name, now: now),
        const SizedBox(height: 24),
        day.when(
          loading: () => const _ShimmerLine(),
          error: (_, _) => CompanionLoadError(
            message:
                'Could not read family priorities. If anyone is very unwell, use Emergency help now.',
            onRetry: () {
              ref.invalidate(caregiverClinicalProvider(scope));
              ref.invalidate(caregiverTodayProvider(scope));
            },
          ),
          data: (d) => d.attention.isNotEmpty
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionHeader(attention: true),
                    for (final focus in d.attention)
                      focusCard(focus, d.dateKey),
                    const SizedBox(height: 8),
                  ],
                )
              : const SizedBox.shrink(),
        ),
        members.when(
          loading: () => const _ShimmerLine(),
          error: (_, _) => CompanionLoadError(
            onRetry: () =>
                ref.invalidate(householdMembersProvider(householdId)),
          ),
          data: (people) => _CaringCard(members: people),
        ),
        const SizedBox(height: 8),
        _QuickActions(
          onCheck: () => check(),
          onFood: () => Navigator.of(context).push(
            GlassPageRoute<void>(
              builder: (_) => CaregiverFoodPage(
                householdId: householdId,
                personId: selected,
              ),
            ),
          ),
          onPlay: () => onSwitch(2),
          onListen: () => Navigator.of(context).push(
            GlassPageRoute<void>(
              builder: (_) =>
                  CaregiverAudioGuideScreen(householdId: householdId),
            ),
          ),
        ),
        const SizedBox(height: 28),
        _NavyCard(
          title: 'Today for your family',
          eyebrow: 'DAILY GUIDANCE',
          child: day.when(
            loading: () => const Text("Preparing today's guidance\u2026"),
            error: (_, _) => const Text(
              "Today's list is unavailable. You can still check on someone or get help.",
            ),
            data: (d) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (d.routine.isEmpty)
                  _EmptyRoutine(
                    onAdd: () => CaregiverAddMemberButton(
                      householdId: householdId,
                      dark: true,
                    ),
                  ),
                for (final focus in d.focus) focusCard(focus, d.dateKey),
                if (d.routine.length > 3) ...[
                  const SizedBox(height: 8),
                  _SeeAllButton(
                    onPressed: () => Navigator.of(context).push(
                      GlassPageRoute<void>(
                        builder: (routeContext) => CompanionPage(
                          title: 'All family priorities',
                          child: Consumer(
                            builder: (context, ref, _) => ref
                                .watch(caregiverTodayProvider(scope))
                                .when(
                                  loading: () => const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                  error: (_, _) => CompanionLoadError(
                                    onRetry: () => ref.invalidate(
                                      caregiverTodayProvider(scope),
                                    ),
                                  ),
                                  data: (all) => ListView(
                                    padding: const EdgeInsets.all(20),
                                    children: [
                                      for (final f in [
                                        ...all.attention,
                                        ...all.routine,
                                      ])
                                        CaregiverFocusCard(
                                          focus: f,
                                          dateKey: all.dateKey,
                                          person: members.valueOrNull
                                              ?.where((p) => p.id == f.personId)
                                              .firstOrNull,
                                          onOpen: () async {
                                            Navigator.pop(routeContext);
                                            await open(f);
                                          },
                                        ),
                                    ],
                                  ),
                                ),
                          ),
                        ),
                      ),
                    ),
                    count: d.routine.length,
                  ),
                ],
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(Gap.radiusSm),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        size: 16,
                        color: AppColors.checkBlueBright,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Done means you reported trying an activity today. It does not confirm recovery or close a referral.',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.white70,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),
        _FamilySection(householdId: householdId),
        const SizedBox(height: 20),
        _FamilyCodeCard(householdId: householdId),
      ],
    );
  }
}

/// A section heading on the navy ground: white Sora with an optional red
/// pulse for the one section that is allowed to say "danger".
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({this.attention = false});
  final bool attention;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14, left: 2),
      child: Row(
        children: [
          if (attention) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: AppColors.triageRed,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.triageRed.withValues(alpha: 0.5),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            attention ? 'Needs attention' : '',
            style: GoogleFonts.sora(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// The navy card body shared by every dashboard card: the same midnight
/// gradient, the same hairline catch-light, the same white ink.
class _NavyCard extends StatelessWidget {
  const _NavyCard({required this.title, this.eyebrow, required this.child});
  final String title;
  final String? eyebrow;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.checkNavyMid, AppColors.checkNavy],
          ),
          borderRadius: BorderRadius.circular(Gap.radius),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x59000000),
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: DefaultTextStyle.merge(
          style: caregiverBody(color: AppColors.white70),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (eyebrow != null) ...[
                Text(
                  eyebrow!,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    height: 1.2,
                    color: AppColors.checkBlueBright,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Text(
                title,
                style: GoogleFonts.sora(
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                  height: 1.25,
                  letterSpacing: -0.2,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _ShimmerLine extends StatelessWidget {
  const _ShimmerLine();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 16,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.checkNavy.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}

class _EmptyRoutine extends StatelessWidget {
  const _EmptyRoutine({required this.onAdd});
  final Widget Function() onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(Gap.radius),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.checkBlue.withValues(alpha: 0.22),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.group_add_outlined,
              size: 24,
              color: AppColors.checkBlueBright,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Add a family member to see everyday ideas',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          const Text(
            'Unknown ages need confirmation before age-specific guidance.',
            style: TextStyle(
              fontSize: 12.5,
              color: AppColors.white60,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _SeeAllButton extends StatelessWidget {
  const _SeeAllButton({required this.onPressed, required this.count});
  final VoidCallback onPressed;
  final int count;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: AppColors.white70, width: 1.2),
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: const Icon(Icons.view_list_rounded, size: 18),
      label: Text(
        'See all $count priorities',
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// The greeting hero — midnight navy glass with two quiet glows, the date,
/// the greeting and the family picture. It is the deepest, richest blue on
/// the screen, so the page reads as one dark jewel rather than a banner.
class _FamilyHero extends StatelessWidget {
  const _FamilyHero({
    required this.part,
    required this.name,
    required this.now,
  });
  final String part;
  final String name;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF061023), Color(0xFF0C2E66), Color(0xFF1B4FB0)],
          stops: [0.0, 0.5, 1.0],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 30,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0.95, -0.6),
                    radius: 1.3,
                    colors: [Color(0x383B82F6), Color(0x00000000)],
                  ),
                ),
              ),
            ),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(-0.5, 1.25),
                    radius: 1.1,
                    colors: [Color(0x2E1B56DB), Color(0x00000000)],
                  ),
                ),
              ),
            ),
            // The catch-light: a thin bright line across the top edge.
            Positioned(
              top: 0,
              left: 20,
              right: 20,
              child: IgnorePointer(
                child: Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0),
                        Colors.white.withValues(alpha: 0.35),
                        Colors.white.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          DateFormat('EEEE, d MMMM').format(now),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                            width: 1,
                          ),
                        ),
                        child: const Icon(
                          Icons.family_restroom_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Text(
                    '$part, $name',
                    style: GoogleFonts.sora(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Small moments of care. A place for everyone in your family.',
                    style: TextStyle(
                      color: AppColors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                        width: 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(15),
                      child: Image.asset(
                        AppImages.caregiverHero,
                        height: 110,
                        fit: BoxFit.cover,
                        excludeFromSemantics: true,
                        errorBuilder: (_, _, _) => Container(
                          height: 80,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: const Icon(
                            Icons.family_restroom,
                            size: 40,
                            color: Colors.white38,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The family selection card — same job and behaviour as the old light
/// selector, dressed in navy and themed so its outlined buttons read white.
class _CaringCard extends ConsumerWidget {
  const _CaringCard({required this.members});
  final List<Person> members;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(caregiverScopeProvider);
    if (scope == null) return const SizedBox.shrink();
    final writer = ref.watch(caregiverWriterProvider(scope));
    return Theme(
      // Outlined controls on this navy card keep their contrast.
      data: Theme.of(context).copyWith(
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(48, 48),
            foregroundColor: Colors.white,
            side: const BorderSide(color: AppColors.white70, width: 1.4),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            minimumSize: const Size(48, 48),
            foregroundColor: Colors.white,
          ),
        ),
      ),
      child: ref
          .watch(caregiverSettingsProvider(scope))
          .when(
            loading: () => const _NavyCard(
              title: 'All family',
              eyebrow: 'CARING FOR',
              child: Text('Loading your family selection\u2026'),
            ),
            error: (_, _) => _NavyCard(
              title: 'All family',
              eyebrow: 'CARING FOR',
              child: CaregiverSaveAction(
                label: 'Retry family selection',
                onSave: () async {
                  ref.invalidate(caregiverSettingsProvider(scope));
                  await ref.read(caregiverSettingsProvider(scope).future);
                },
              ),
            ),
            data: (settings) {
              final selected = members
                  .where((p) => p.id == settings.selectedPersonId)
                  .firstOrNull;
              return _NavyCard(
                title: selected?.fullName ?? 'All family',
                eyebrow: 'CARING FOR',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (selected != null)
                      Text(
                        caregiverAge(selected),
                        style: const TextStyle(color: AppColors.white60),
                      ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.people_outline),
                      label: const Text('Choose family member'),
                      onPressed: () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        builder: (context) => SafeArea(
                          child: ListView(
                            shrinkWrap: true,
                            padding: const EdgeInsets.all(20),
                            children: [
                              CaregiverSaveAction(
                                label: 'All family',
                                onSave: () async {
                                  await writer.settings(
                                    (s) => s.copyWith(allFamily: true),
                                  );
                                  if (context.mounted) Navigator.pop(context);
                                },
                              ),
                              for (final p in members)
                                CaregiverSaveAction(
                                  label: '${p.fullName} • ${caregiverAge(p)}',
                                  onSave: () async {
                                    await writer.settings(
                                      (s) => s.copyWith(selectedPersonId: p.id),
                                    );
                                    if (context.mounted) Navigator.pop(context);
                                  },
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.onCheck,
    required this.onFood,
    required this.onPlay,
    required this.onListen,
  });
  final VoidCallback onCheck;
  final VoidCallback onFood;
  final VoidCallback onPlay;
  final VoidCallback onListen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PremiumCheckButton(
          label: 'Check on someone now',
          icon: Icons.health_and_safety_outlined,
          height: 58,
          bright: true,
          onPressed: onCheck,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _QuickTile(
                icon: Icons.restaurant_outlined,
                label: 'Food',
                subtitle: 'Meals & feeding',
                onTap: onFood,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _QuickTile(
                icon: Icons.toys_outlined,
                label: 'Play',
                subtitle: 'Activities & bonding',
                onTap: onPlay,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _QuickTile(
                icon: Icons.volume_up_outlined,
                label: 'Listen',
                subtitle: 'Audio guides',
                onTap: onListen,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.checkNavyMid, AppColors.checkNavy],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x40000000),
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.checkBlue.withValues(alpha: 0.22),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.checkBlueBright, size: 20),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                color: AppColors.white60,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _FamilySection extends ConsumerWidget {
  const _FamilySection({required this.householdId});
  final String householdId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(householdMembersProvider(householdId));
    final household = ref.watch(householdProvider(householdId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 14, left: 2),
          child: Text(
            'Our family',
            style: GoogleFonts.sora(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        ),
        household.when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
          data: (h) => h == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.checkNavyMid, AppColors.checkNavy],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppColors.checkBlue.withValues(alpha: 0.22),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.home_outlined,
                            color: AppColors.checkBlueBright,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                h.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                h.community,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.white60,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
        members.when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const Text(
            'Family members could not be loaded.',
            style: TextStyle(color: AppColors.inkMuted),
          ),
          data: (people) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (people.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(Gap.radius),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                      width: 1,
                    ),
                  ),
                  child: const Text(
                    'No one is on your family list yet. Add the people you care for to get started.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.white60,
                      height: 1.5,
                    ),
                  ),
                ),
              for (final p in people)
                CaregiverPersonCard(
                  person: p,
                  dark: true,
                  onTap: () => Navigator.of(context).push(
                    GlassPageRoute<void>(
                      builder: (_) => CaregiverPersonDetail(personId: p.id),
                    ),
                  ),
                ),
              CaregiverAddMemberButton(householdId: householdId, dark: true),
            ],
          ),
        ),
      ],
    );
  }
}

class _FamilyCodeCard extends StatelessWidget {
  const _FamilyCodeCard({required this.householdId});
  final String householdId;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.checkNavyMid, AppColors.checkNavy],
        ),
        borderRadius: BorderRadius.circular(Gap.radius),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x59000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.checkBlue.withValues(alpha: 0.22),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.key_outlined,
                  size: 16,
                  color: AppColors.checkBlueBright,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your family code',
                      style: GoogleFonts.sora(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const Text(
                      'FOR HEALTH WORKERS',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.white60,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Show this code when discussing your family record with a health worker. Local-only notes and home checks are not automatically uploaded.',
            style: TextStyle(
              fontSize: 12.5,
              color: AppColors.white60,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.checkNavyDeep,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 1,
              ),
            ),
            child: SelectableText(
              FamilyCode.pretty(householdId),
              textAlign: TextAlign.center,
              style: GoogleFonts.sora(
                fontWeight: FontWeight.w800,
                fontSize: 24,
                color: AppColors.checkBlueBright,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One family priority as a navy card. Urgent stays red — the IMCI red is the
/// one colour allowed to break the navy — and the tap opens the guidance.
class CaregiverFocusCard extends StatelessWidget {
  const CaregiverFocusCard({
    super.key,
    required this.focus,
    required this.dateKey,
    required this.person,
    required this.onOpen,
  });
  final CaregiverFocus focus;
  final String dateKey;
  final Person? person;
  final Future<void> Function() onOpen;
  @override
  Widget build(BuildContext context) {
    final isUrgent = focus.priority <= 1;
    final accent = isUrgent ? AppColors.triageRed : AppColors.checkBlue;
    // The ink used for the accent's text and top band: the pure triage red
    // and royal blue are too dark to read on navy, so they brighten here.
    final accentText = isUrgent
        ? const Color(0xFFFF8A80)
        : AppColors.checkBlueBright;
    final overdue =
        focus.dueDate != null && focus.dueDate!.isBefore(DateTime.now());
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.checkNavyMid, AppColors.checkNavy],
          ),
          borderRadius: BorderRadius.circular(Gap.radius),
          border: Border.all(
            color: isUrgent
                ? accentText.withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: 0.08),
            width: isUrgent ? 1.2 : 1,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x59000000),
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Gap.radius),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Colour rides the top edge as a slim band — visible, but it
              // can never squeeze content the way a side bar could.
              Container(height: 3, color: accentText),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            focus.source.label,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: accentText,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (overdue)
                          Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.triageRed.withValues(
                                alpha: 0.18,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              'Overdue',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFFF8A80),
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        if (focus.dueDate != null)
                          Text(
                            'Due ${DateFormat('d MMM').format(focus.dueDate!)}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.white60,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      focus.title,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${person?.fullName ?? 'Family member'}'
                      ' \u2022 ${person == null ? 'Age unavailable' : caregiverAge(person!)}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.white60,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      focus.detail,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.white60,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Actions stack, never share a row: two buttons of
                    // unknown width side by side is exactly how labels end
                    // up wrapping one letter per line on a narrow screen.
                    SizedBox(
                      height: 44,
                      child: FilledButton.icon(
                        onPressed: () => onOpen(),
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                        label: const Text('Open guidance'),
                      ),
                    ),
                    if (focus.canComplete) ...[
                      const SizedBox(height: 8),
                      CaregiverTaskToggle(
                        personId: focus.personId,
                        kind: CaregiverActivityKind.dailyTask,
                        sourceId: focus.sourceId,
                        itemKey: focus.itemKey,
                        occurrenceKey: dateKey,
                        label: "Today's activity",
                        light: true,
                        tone: accentText,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
