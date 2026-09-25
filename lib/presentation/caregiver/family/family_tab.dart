import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../core/audio/speech_content_policy.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/glass.dart';
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
                          style: AppType.body.copyWith(
                            color: CompanionColors.muted,
                          ),
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
                        style: AppType.caption.copyWith(
                          color: CompanionColors.muted,
                        ),
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
        Text(
          title,
          style: AppType.title.copyWith(
            fontSize: 19,
            color: CompanionColors.ink,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 5),
          Text(
            subtitle!,
            style: AppType.caption.copyWith(color: CompanionColors.muted),
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
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: CaregiverLuxePalette.pearlSurface,
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: CaregiverLuxePalette.hairLineQuiet, width: 0.5),
      boxShadow: CaregiverLuxePalette.featheredShadow,
    ),
    child: child,
  );
}

class _LocalPlaceholder extends StatelessWidget {
  const _LocalPlaceholder({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Text(
      label,
      style: AppType.body.copyWith(color: CompanionColors.muted),
    ),
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
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: CaregiverLuxePalette.horizon,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: CaregiverLuxePalette.specularStroke,
          width: 0.5,
        ),
        boxShadow: CaregiverLuxePalette.featheredShadow,
      ),
      child: Stack(
        children: [
          const Positioned(
            right: -22,
            top: -28,
            child: ExcludeSemantics(
              child: Icon(
                Icons.wb_sunny_outlined,
                size: 170,
                color: Color(0x0FFFFFFF),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  DateFormat('EEEE, d MMMM').format(now),
                  style: AppType.caption.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                Text(
                  '$part,\n$name',
                  style: AppType.headline.copyWith(
                    color: Colors.white,
                    fontSize: 26,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  household?.name ?? 'A little care, every day.',
                  style: AppType.body.copyWith(color: Colors.white),
                ),
                if (household != null && household.community.isNotEmpty)
                  Text(
                    household.community,
                    style: AppType.caption.copyWith(color: Colors.white70),
                  ),
                const SizedBox(height: 16),
                Text(
                  'Local-only notes and home checks are not automatically uploaded.',
                  style: AppType.caption.copyWith(
                    color: Colors.white70,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
            style: AppType.body.copyWith(color: CompanionColors.muted),
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
      width: 76,
      height: 76,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: CaregiverLuxePalette.pearlSurface,
        border: Border.all(
          color: selected
              ? CaregiverLuxePalette.azurePrimary
              : CaregiverLuxePalette.hairLineQuiet,
          width: selected ? 2.5 : 1,
        ),
      ),
      child: ClipOval(
        child: image == null
            ? ColoredBox(
                color: CaregiverLuxePalette.azureIce,
                child: Icon(
                  person == null
                      ? Icons.family_restroom_rounded
                      : Icons.person_outline_rounded,
                  color: CompanionColors.blue,
                  size: 30,
                ),
              )
            : Image.asset(image, fit: BoxFit.cover, excludeFromSemantics: true),
      ),
    );
    final name = Text(
      label,
      textAlign: wide ? TextAlign.start : TextAlign.center,
      style: AppType.label.copyWith(
        color: selected ? CompanionColors.blue : CompanionColors.ink,
        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
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
      FilledButton.icon(
        onPressed: onCheck,
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 56),
          padding: const EdgeInsets.all(16),
          backgroundColor: CompanionColors.blue,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
        icon: const Icon(Icons.health_and_safety_outlined),
        label: const Text('Check on someone now', textAlign: TextAlign.center),
      ),
      const SizedBox(height: 12),
      LayoutBuilder(
        builder: (context, constraints) {
          final wideText = MediaQuery.textScalerOf(context).scale(14) > 21;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final (label, icon, action) in [
                ('Local foods', Icons.restaurant_outlined, onFood),
                ('Play & learn', Icons.toys_outlined, onPlay),
                ('Audio guides', Icons.volume_up_outlined, onListen),
              ])
                SizedBox(
                  width: wideText
                      ? constraints.maxWidth
                      : (constraints.maxWidth - 20) / 3,
                  child: Material(
                    color: CaregiverLuxePalette.pearlSurface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                      side: const BorderSide(
                        color: CaregiverLuxePalette.hairLineQuiet,
                      ),
                    ),
                    child: InkWell(
                      onTap: action,
                      borderRadius: BorderRadius.circular(22),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 16,
                        ),
                        child: Column(
                          children: [
                            Icon(icon, color: CompanionColors.blue, size: 25),
                            const SizedBox(height: 10),
                            Text(
                              label,
                              textAlign: TextAlign.center,
                              style: AppType.label.copyWith(
                                color: CompanionColors.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
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
    final accent = focus.priority <= 1
        ? AppColors.triageRed
        : CompanionColors.blue;
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    focus.source.label,
                    style: AppType.label.copyWith(color: accent),
                  ),
                ),
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
              style: AppType.title.copyWith(
                color: CompanionColors.ink,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              who,
              style: AppType.caption.copyWith(color: CompanionColors.muted),
            ),
            const SizedBox(height: 10),
            Text(
              focus.detail,
              style: AppType.body.copyWith(color: CompanionColors.muted),
            ),
            if (due != null) ...[
              const SizedBox(height: 10),
              Text(
                due,
                style: AppType.label.copyWith(
                  color: overdue ? AppColors.triageRed : CompanionColors.muted,
                ),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => onOpen(),
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.all(14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: const Text('Open guidance', textAlign: TextAlign.center),
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
