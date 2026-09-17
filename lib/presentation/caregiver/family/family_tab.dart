import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/glass.dart';
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
      padding: const EdgeInsets.all(20),
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
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14, left: 2),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.triageRed,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Needs attention',
                            style: TextStyle(
                              fontFamily: 'Sora',
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
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
          data: (people) => CaregiverPersonSelector(members: people),
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
        CompanionCard(
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
                    color: AppColors.primaryLight.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(Gap.radiusSm),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 16,
                        color: AppColors.primary.withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Done means you reported trying an activity today. It does not confirm recovery or close a referral.',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.primary.withValues(alpha: 0.75),
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

class _ShimmerLine extends StatelessWidget {
  const _ShimmerLine();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 16,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.line.withValues(alpha: 0.5),
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
        color: AppColors.caregiverSurface,
        borderRadius: BorderRadius.circular(Gap.radius),
        border: Border.all(color: AppColors.line, width: 1),
      ),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.group_add_outlined,
              size: 24,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Add a family member to see everyday ideas',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          const Text(
            'Unknown ages need confirmation before age-specific guidance.',
            style: TextStyle(
              fontSize: 12.5,
              color: AppColors.inkMuted,
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
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.primary, width: 1.2),
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      icon: const Icon(Icons.view_list_rounded, size: 18),
      label: Text(
        'See all $count priorities',
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    );
  }
}

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
    return GlassSurface(
      tier: GlassTier.hero,
      blur: false,
      padding: EdgeInsets.zero,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(GlassTier.hero.radius),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.checkNavy,
              AppColors.checkBlue,
              AppColors.checkBlueLight,
            ],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -40,
              top: -40,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.05),
                ),
              ),
            ),
            Positioned(
              right: 30,
              bottom: -50,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.04),
                ),
              ),
            ),
            Positioned(
              left: -20,
              bottom: -20,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.03),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
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
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
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
                          color: Colors.white.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
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
                    style: const TextStyle(
                      fontFamily: 'Sora',
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
                      color: AppColors.white80,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 18),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.asset(
                      AppImages.caregiverHero,
                      height: 110,
                      fit: BoxFit.cover,
                      excludeFromSemantics: true,
                      errorBuilder: (_, _, _) => Container(
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.family_restroom,
                          size: 40,
                          color: Colors.white38,
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
          color: AppColors.caregiverSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line, width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.primary, size: 20),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                color: AppColors.inkMuted,
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
            style: TextStyle(
              fontFamily: 'Sora',
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
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primaryLight.withValues(alpha: 0.6),
                          AppColors.primaryLight.withValues(alpha: 0.2),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.home_outlined,
                            color: AppColors.primary,
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
                                  color: AppColors.ink,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                h.community,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.inkMuted,
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
          error: (_, _) => const Text('Family members could not be loaded.'),
          data: (people) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (people.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.caregiverSurface,
                    borderRadius: BorderRadius.circular(Gap.radius),
                    border: Border.all(color: AppColors.line, width: 1),
                  ),
                  child: const Text(
                    'No one is on your family list yet. Add the people you care for to get started.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.inkMuted,
                      height: 1.5,
                    ),
                  ),
                ),
              for (final p in people)
                CaregiverPersonCard(
                  person: p,
                  onTap: () => Navigator.of(context).push(
                    GlassPageRoute<void>(
                      builder: (_) =>
                          CaregiverPersonDetail(personId: p.id),
                    ),
                  ),
                ),
              CaregiverAddMemberButton(householdId: householdId),
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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Gap.radius),
        border: Border.all(color: AppColors.line, width: 1),
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
                  color: AppColors.primaryLight,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.key_outlined,
                  size: 16,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your family code',
                      style: const TextStyle(
                        fontFamily: 'Sora',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const Text(
                      'FOR HEALTH WORKERS',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.inkMuted,
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
              color: AppColors.inkMuted,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primaryLight.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.15),
                width: 1,
              ),
            ),
            child: SelectableText(
              FamilyCode.pretty(householdId),
              style: const TextStyle(
                fontFamily: 'Sora',
                fontWeight: FontWeight.w800,
                fontSize: 24,
                color: AppColors.primaryDeep,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
    final accent = isUrgent ? AppColors.triageRed : AppColors.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(Gap.radius),
          border: Border.all(
            color: isUrgent
                ? accent.withValues(alpha: 0.25)
                : AppColors.line,
            width: isUrgent ? 1.2 : 1,
          ),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(Gap.radius),
                    bottomLeft: Radius.circular(Gap.radius),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
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
                              color: accent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              focus.source.label,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: accent,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                          const Spacer(),
                          if (focus.dueDate != null)
                            Text(
                              'Due ${DateFormat('d MMM').format(focus.dueDate!)}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.inkMuted,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        focus.title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(
                            person?.fullName ?? 'Family member',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                          Text(
                            ' \u2022 ${person == null ? 'Age unavailable' : caregiverAge(person!)}',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: AppColors.inkMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        focus.detail,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.inkMuted,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: onOpen,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: accent,
                                side: BorderSide(
                                  color: accent.withValues(alpha: 0.4),
                                  width: 1,
                                ),
                                minimumSize: const Size.fromHeight(40),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: const Icon(
                                Icons.arrow_forward_rounded,
                                size: 16,
                              ),
                              label: const Text(
                                'Open guidance',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          if (focus.canComplete) ...[
                            const SizedBox(width: 8),
                            CaregiverTaskToggle(
                              personId: focus.personId,
                              kind: CaregiverActivityKind.dailyTask,
                              sourceId: focus.sourceId,
                              itemKey: focus.itemKey,
                              occurrenceKey: dateKey,
                              label: "Today's activity",
                            ),
                          ],
                        ],
                      ),
                    ],
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
