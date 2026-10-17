import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../core/audio/speech_content_policy.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/glass.dart';
import '../../../core/theme/lumina.dart';
import '../../../core/theme/motion.dart';
import '../../../domain/entities/caregiver.dart';
import '../../../domain/entities/core.dart';
import '../../../domain/enums.dart';
import '../../../domain/services/caregiver_today_planner.dart';
import '../../shared/app_image.dart';
import '../../shared/audio_button.dart';
import '../caregiver_providers.dart';
import '../check/triage_screen.dart';
import '../food/food_page.dart';
import '../help/audio_guide_screen.dart';
import '../widgets/companion.dart';
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
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        StaggeredReveal(
          index: 0,
          child: _FamilyHero(name: name, now: now, householdId: householdId),
        ),
        const SizedBox(height: 28),
        day.when(
          loading: () =>
              const _LocalPlaceholder(label: 'Reading family priorities…'),
          error: (_, _) => CompanionLoadError(
            message:
                'Could not read family priorities. If anyone is very unwell, use Emergency help now.',
            onRetry: () {
              ref.invalidate(caregiverClinicalProvider(scope));
              ref.invalidate(caregiverTodayProvider(scope));
            },
          ),
          data: (d) => d.attention.isEmpty
              ? const SizedBox.shrink()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _SectionTitle(title: 'Needs attention'),
                    for (final focus in d.attention)
                      focusCard(focus, d.dateKey),
                    const SizedBox(height: 16),
                  ],
                ),
        ),
        StaggeredReveal(
          index: 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SectionTitle(
                title: 'Our family',
                subtitle: 'Choose who you are caring for',
              ),
              members.when(
                loading: () =>
                    const _LocalPlaceholder(label: 'Reading your family list…'),
                error: (_, _) => CompanionLoadError(
                  onRetry: () =>
                      ref.invalidate(householdMembersProvider(householdId)),
                ),
                data: (people) =>
                    _FamilyCarousel(members: people, householdId: householdId),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        StaggeredReveal(
          index: 2,
          child: _QuickActions(
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
        ),
        const SizedBox(height: 28),
        StaggeredReveal(
          index: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SectionTitle(
                title: 'Today for your family',
                subtitle: 'Little moments of care, one at a time',
              ),
              day.when(
                loading: () => const _LocalPlaceholder(
                  label: "Preparing today's guidance…",
                ),
                error: (_, _) => const _PearlCard(
                  child: Text(
                    "Today's list is unavailable. You can still check on someone or get help.",
                  ),
                ),
                data: (d) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (d.routine.isEmpty)
                      _PearlCard(
                        child: Text(
                          members.valueOrNull?.isEmpty == true
                              ? 'Add a family member above to see everyday ideas.'
                              : 'No everyday ideas are listed here yet. Confirm ages in the family record for age-specific guidance.',
                          style: Lumina.body(color: Lumina.diveSoft),
                        ),
                      ),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final split =
                            constraints.maxWidth >= 620 &&
                            MediaQuery.textScalerOf(context).scale(14) < 21;
                        return Wrap(
                          spacing: 16,
                          children: [
                            for (final (i, focus) in d.focus.indexed)
                              SizedBox(
                                width: split && i > 0
                                    ? (constraints.maxWidth - 16) / 2
                                    : constraints.maxWidth,
                                child: focusCard(focus, d.dateKey),
                              ),
                          ],
                        );
                      },
                    ),
                    if (d.routine.length > 3)
                      OutlinedButton.icon(
                        icon: const Icon(Icons.view_list_rounded),
                        label: Text('See all ${d.routine.length} priorities'),
                        onPressed: () => Navigator.of(context).push(
                          GlassPageRoute<void>(
                            builder: (routeContext) => CompanionPage(
                              title: 'All family priorities',
                              child: Consumer(
                                builder: (context, ref, _) => ref
                                    .watch(caregiverTodayProvider(scope))
                                    .when(
                                      loading: () => const _LocalPlaceholder(
                                        label: 'Reading priorities…',
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
                                                  ?.where(
                                                    (p) => p.id == f.personId,
                                                  )
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
                      ),
                    if (d.focus.any((f) => f.canComplete)) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Done means you reported trying an activity today. It does not confirm recovery or close a referral.',
                        style: Lumina.body(size: 12, color: Lumina.inkMuted),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Lumina.display(19, weight: 700)),
        if (subtitle != null) ...[
          const SizedBox(height: 5),
          Text(
            subtitle!,
            style: Lumina.body(size: 12.5, color: Lumina.inkMuted),
          ),
        ],
      ],
    ),
  );
}

class _PearlCard extends StatelessWidget {
  const _PearlCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => LumenCard(hero: true, child: child);
}

class _LocalPlaceholder extends StatelessWidget {
  const _LocalPlaceholder({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Text(label, style: Lumina.body(size: 13.5, color: Lumina.inkMuted)),
  );
}

class _FamilyHero extends ConsumerWidget {
  const _FamilyHero({
    required this.name,
    required this.now,
    required this.householdId,
  });
  final String name;
  final DateTime now;
  final String householdId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final household = ref.watch(householdProvider(householdId)).valueOrNull;
    final part = now.hour < 12
        ? 'Good morning'
        : now.hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    return Column(
      children: [
        Container(
          height: 1.4,
          margin: const EdgeInsets.only(bottom: 3),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.transparent, Lumina.glow, Colors.transparent],
            ),
          ),
        ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Lumina.rLg),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Lumina.deep, Lumina.navy, Color(0xFF1E4785)],
              stops: [0.0, 0.55, 1.0],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x4D040E1F),
                blurRadius: 34,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(1.1, -1.1),
                      radius: 1.15,
                      colors: [
                        Lumina.bright.withValues(alpha: 0.26),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              const Positioned(
                right: -16,
                top: 6,
                child: ExcludeSemantics(child: _FamilyOrbitMark()),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 21, 22, 19),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LumeFrost(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const LumePulse(color: Lumina.glow, size: 7),
                          const SizedBox(width: 9),
                          Flexible(
                            child: Text(
                              DateFormat(
                                'EEEE  ·  d MMMM',
                              ).format(now).toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      '$part, $name.',
                      style: Lumina.display(25, color: Colors.white),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      household?.name ?? 'Your family, together.',
                      style: Lumina.body(
                        size: 15,
                        color: Lumina.diveInk,
                        weight: 600,
                      ),
                    ),
                    if (household != null &&
                        household.community.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        household.community,
                        style: Lumina.body(size: 12.5, color: Lumina.diveMuted),
                      ),
                    ],
                    const SizedBox(height: 17),
                    LumeFrost(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      radius: 14,
                      sigma: 10,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.lock_outline_rounded,
                            size: 14,
                            color: Lumina.diveInk,
                          ),
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              'Local-only notes and home checks are not '
                              'automatically uploaded.',
                              style: const TextStyle(
                                fontSize: 11,
                                height: 1.35,
                                fontWeight: FontWeight.w600,
                                color: Lumina.diveInk,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Fine-line family orbit, borrowed from celestial navigation. Purely
/// decorative: it never encodes a health state or asks for an interpretation.
class _FamilyOrbitMark extends StatelessWidget {
  const _FamilyOrbitMark();

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 124,
    height: 120,
    child: CustomPaint(painter: _FamilyOrbitPainter()),
  );
}

class _FamilyOrbitPainter extends CustomPainter {
  const _FamilyOrbitPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.55, size.height * 0.48);
    final orbitPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Lumina.glow.withValues(alpha: 0.16);
    for (final rect in [
      Rect.fromCenter(center: center, width: 58, height: 36),
      Rect.fromCenter(center: center, width: 90, height: 68),
      Rect.fromCenter(center: center, width: 120, height: 98),
    ]) {
      canvas.drawOval(rect, orbitPaint);
    }
    final stars = [
      (Offset(center.dx - 40, center.dy - 26), 3.0),
      (Offset(center.dx + 44, center.dy - 12), 2.1),
      (Offset(center.dx + 2, center.dy + 34), 2.5),
      (Offset(center.dx - 8, center.dy - 3), 4.3),
    ];
    for (var i = 0; i < stars.length; i++) {
      final (point, radius) = stars[i];
      canvas.drawCircle(
        point,
        radius,
        Paint()
          ..color = Lumina.glow.withValues(
            alpha: i == stars.length - 1 ? 0.42 : 0.22,
          ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FamilyOrbitPainter oldDelegate) => false;
}

class _FamilyCarousel extends ConsumerStatefulWidget {
  const _FamilyCarousel({required this.members, required this.householdId});
  final List<Person> members;
  final String householdId;

  @override
  ConsumerState<_FamilyCarousel> createState() => _FamilyCarouselState();
}

class _FamilyCarouselState extends ConsumerState<_FamilyCarousel> {
  bool _saving = false;
  bool _failed = false;

  Future<void> _select(String? id) async {
    if (_saving) return;
    final scope = ref.read(caregiverScopeProvider);
    if (scope == null) return;
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      await ref
          .read(caregiverWriterProvider(scope))
          .settings(
            (s) => id == null
                ? s.copyWith(allFamily: true)
                : s.copyWith(selectedPersonId: id),
          );
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(caregiverScopeProvider);
    if (scope == null) return const SizedBox.shrink();
    final settings = ref.watch(caregiverSettingsProvider(scope));
    final selected = widget.members
        .where((p) => p.id == settings.valueOrNull?.selectedPersonId)
        .firstOrNull;
    final wide = MediaQuery.textScalerOf(context).scale(14) > 21;
    final orbs = [
      _MemberOrb(
        label: 'All family',
        selected: selected == null,
        wide: wide,
        onTap: () => _select(null),
      ),
      for (final person in widget.members)
        _MemberOrb(
          label: person.fullName,
          person: person,
          selected: selected?.id == person.id,
          wide: wide,
          onTap: () => _select(person.id),
        ),
    ];
    void viewRecord(Person person) => Navigator.of(context).push(
      GlassPageRoute<void>(
        builder: (_) => CaregiverPersonDetail(personId: person.id),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.members.isEmpty)
          Text(
            'Add the people you care for to get started.',
            style: Lumina.body(color: Lumina.inkMuted),
          )
        else if (!settings.hasValue) ...[
          if (settings.hasError)
            CompanionLoadError(
              message:
                  'Could not read your selection. Family records are still available.',
              onRetry: () => ref.invalidate(caregiverSettingsProvider(scope)),
            )
          else
            const _LocalPlaceholder(label: 'Reading your family selection…'),
          for (final person in widget.members)
            TextButton.icon(
              icon: const Icon(Icons.person_outline_rounded),
              label: Text('View record: ${person.fullName}'),
              onPressed: () => viewRecord(person),
            ),
        ] else if (wide)
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: orbs)
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: orbs,
            ),
          ),
        if (_saving || _failed)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _saving
                    ? 'Saving selection…'
                    : 'Could not save. Tap the family member to retry.',
              ),
            ),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            CaregiverAddMemberButton(householdId: widget.householdId),
            if (selected != null)
              TextButton.icon(
                icon: const Icon(Icons.person_outline_rounded),
                label: const Text('View record'),
                onPressed: () => viewRecord(selected),
              ),
          ],
        ),
      ],
    );
  }
}

class _MemberOrb extends StatelessWidget {
  const _MemberOrb({
    required this.label,
    required this.selected,
    required this.wide,
    required this.onTap,
    this.person,
  });
  final String label;
  final bool selected;
  final bool wide;
  final VoidCallback onTap;
  final Person? person;

  @override
  Widget build(BuildContext context) {
    final image = switch (person?.clientType) {
      ClientType.newborn => AppImages.cardNewborn,
      ClientType.childUnderFive => AppImages.cardChild,
      ClientType.pregnantWoman ||
      ClientType.postpartumWoman => AppImages.cardMother,
      ClientType.womanOfReproductiveAge => AppImages.cardWoman,
      _ => null,
    };
    final portrait = Container(
      width: 82,
      height: 82,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: selected ? Lumina.tide : null,
        border: selected
            ? null
            : Border.all(color: Lumina.core.withValues(alpha: 0.16)),
        boxShadow: selected && VisualEffects.of(context).blur
            ? const [Lumina.aura]
            : const [],
      ),
      child: ClipOval(
        child: ColoredBox(
          color: Lumina.pearl,
          child: image == null
              ? Icon(
                  person == null
                      ? Icons.family_restroom_rounded
                      : Icons.person_outline_rounded,
                  color: Lumina.core,
                  size: 30,
                )
              : Image.asset(
                  image,
                  fit: BoxFit.cover,
                  excludeFromSemantics: true,
                ),
        ),
      ),
    );
    final name = Text(
      label,
      textAlign: wide ? TextAlign.start : TextAlign.center,
      style: TextStyle(
        fontFamily: 'Sora',
        fontSize: 12.5,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
        letterSpacing: -0.1,
        color: selected ? Lumina.core : Lumina.ink,
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: 'Select $label',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          splashFactory: VisualEffects.of(context).motion
              ? null
              : NoSplash.splashFactory,
          child: ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: wide
                  ? Row(
                      children: [
                        portrait,
                        const SizedBox(width: 14),
                        Expanded(child: name),
                      ],
                    )
                  : SizedBox(
                      width: 100,
                      child: Column(
                        children: [portrait, const SizedBox(height: 10), name],
                      ),
                    ),
            ),
          ),
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
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Lumina.rMd),
          gradient: Lumina.tide,
          boxShadow: VisualEffects.of(context).blur
              ? const [Lumina.aura]
              : const [],
        ),
        child: Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Lumina.rMd),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onCheck,
            child: SizedBox(
              height: 58,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.health_and_safety_outlined,
                    color: Colors.white,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      'Check on someone now',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Sora',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 14),
      Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          GhostPill(
            label: 'Local foods',
            icon: Icons.restaurant_outlined,
            onPressed: onFood,
          ),
          GhostPill(
            label: 'Play & learn',
            icon: Icons.toys_outlined,
            onPressed: onPlay,
          ),
          GhostPill(
            label: 'Audio guides',
            icon: Icons.volume_up_outlined,
            onPressed: onListen,
          ),
        ],
      ),
    ],
  );
}

class CaregiverFocusCard extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    // On the hero blue, alarm is a warm pearl-red, calm is plain light.
    final accent = focus.priority <= 1 ? const Color(0xFFFFB4B4) : Colors.white;
    final now = ref.watch(caregiverCalendarProvider).toLocal();
    final overdue =
        focus.dueDate != null &&
        DateUtils.dateOnly(focus.dueDate!).isBefore(DateUtils.dateOnly(now));
    final due = focus.dueDate == null
        ? null
        : '${overdue ? 'Overdue' : 'Due'} ${DateFormat('d MMM').format(focus.dueDate!)}';
    final who =
        '${person?.fullName ?? 'Family member'} • ${person == null ? 'Age unavailable' : caregiverAge(person!)}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: _PearlCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 3,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                gradient: LinearGradient(
                  colors: [accent, accent.withValues(alpha: 0.12)],
                ),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: MicroLabel(focus.source.label, color: accent)),
                const SizedBox(width: 8),
                AudioButton(
                  text:
                      '$who. ${focus.title}. ${focus.detail}${due == null ? '' : ' $due.'}',
                  language: ref.watch(narrationLanguageProvider),
                  policy: focus.source == CaregiverFocusSource.everyday
                      ? SpeechContentPolicy.guidance
                      : SpeechContentPolicy.clinical,
                  id: 'family-${focus.identity}',
                  compact: true,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              focus.title,
              style: Lumina.display(17.5, weight: 700, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              who,
              style: Lumina.body(
                size: 12.5,
                weight: 600,
                color: Lumina.diveMuted,
              ),
            ),
            const SizedBox(height: 10),
            Text(focus.detail, style: Lumina.body(color: Lumina.diveSoft)),
            if (due != null) ...[
              const SizedBox(height: 10),
              Text(
                due,
                style: Lumina.body(
                  size: 12.5,
                  weight: 700,
                  color: overdue ? const Color(0xFFFFB4B4) : Lumina.diveMuted,
                ),
              ),
            ],
            const SizedBox(height: 18),
            if (focus.priority <= 1)
              FilledButton.icon(
                onPressed: () => onOpen(),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.triageRed,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(48, 50),
                  padding: const EdgeInsets.all(14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Lumina.rSm),
                  ),
                ),
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: const Text('Open guidance', textAlign: TextAlign.center),
              )
            else
              SapphireButton(
                onPressed: () => onOpen(),
                icon: Icons.arrow_forward_rounded,
                label: 'Open guidance',
                expand: true,
                radius: Lumina.rSm,
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
                tone: accent,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
