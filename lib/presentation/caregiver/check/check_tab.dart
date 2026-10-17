import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/lumina.dart';
import '../../../core/theme/motion.dart';
import '../../../domain/entities/core.dart';
import '../../../domain/entities/visit.dart';
import '../../../domain/enums.dart';
import '../../shared/speakable_text.dart';
import '../caregiver_providers.dart';
import '../family/person_detail.dart';
import '../widgets/companion.dart';
import 'triage_screen.dart';

class CaregiverCheckTab extends ConsumerWidget {
  const CaregiverCheckTab({super.key, required this.householdId});
  final String householdId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(caregiverScopeProvider);
    if (scope == null) return const SizedBox.shrink();
    final selected = ref
        .watch(caregiverSettingsProvider(scope))
        .valueOrNull
        ?.selectedPersonId;
    final members = ref.watch(householdMembersProvider(householdId));
    final checks = ref.watch(householdHomeChecksProvider(householdId));
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        StaggerReveal(
          order: 0,
          child: _CheckHero(
            householdId: householdId,
            selectedPersonId: selected,
            members: members.valueOrNull ?? const [],
            checks: checks.valueOrNull ?? const [],
          ),
        ),
        const SizedBox(height: 24),
        members.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => CompanionLoadError(
            onRetry: () =>
                ref.invalidate(householdMembersProvider(householdId)),
          ),
          data: (people) => StaggerReveal(
            order: 1,
            child: _PersonList(
              people: people,
              selectedId: selected,
              householdId: householdId,
              checks: checks.valueOrNull ?? const [],
            ),
          ),
        ),
        const SizedBox(height: 28),
        StaggerReveal(
          order: 2,
          child: _HistorySection(
            householdId: householdId,
            selectedPersonId: selected,
            checks: checks,
            members: members.valueOrNull ?? const [],
          ),
        ),
      ],
    );
  }
}

class _CheckHero extends StatelessWidget {
  const _CheckHero({
    required this.householdId,
    required this.selectedPersonId,
    required this.members,
    required this.checks,
  });

  final String householdId;
  final String? selectedPersonId;
  final List<Person> members;
  final List<HomeCheck> checks;

  @override
  Widget build(BuildContext context) {
    final person = members.where((p) => p.id == selectedPersonId).firstOrNull;
    final today = DateTime.now();
    final dayLabel = _dayLabel(today);
    final dateStr = _formatDate(today);
    // The status line must describe the person the button names. A household
    //-wide "all clear" above "Check Ama" can hide a sibling's danger report.
    final relevantChecks = selectedPersonId == null
        ? checks
        : checks.where((c) => c.personId == selectedPersonId);
    final lastCheck = relevantChecks.isNotEmpty
        ? relevantChecks.reduce(
            (a, b) => a.checkedAt.isAfter(b.checkedAt) ? a : b,
          )
        : null;
    final statusLine = lastCheck == null
        ? (person == null
              ? 'No checks done yet'
              : 'No check yet for ${person.fullName.split(' ').first}')
        : _statusSummary(lastCheck);
    // Same verdict colours the tiles and history use — one status language
    // per screen, blue stays brand, red/amber/green stay clinical.
    final statusColor = lastCheck == null
        ? Colors.white.withValues(alpha: 0.7)
        : switch (lastCheck.verdict) {
            HomeCheckVerdict.urgent => AppColors.triageRed,
            HomeCheckVerdict.caution => AppColors.triageAmber,
            HomeCheckVerdict.fine => AppColors.triageGreen,
          };

    return Column(
      children: [
        // The sunlit swatch: one thin band of caught light over the dive card.
        Container(
          height: 1.4,
          margin: const EdgeInsets.only(bottom: 3),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                Lumina.glow.withValues(alpha: 0.7),
                Colors.transparent,
              ],
            ),
          ),
        ),
        Container(
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
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Lumina.rLg),
                  child: Container(
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
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        LumeFrost(
                          child: Text(
                            '$dayLabel \u2022 $dateStr',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        const Spacer(),
                        LumeFrost(
                          padding: const EdgeInsets.all(10),
                          sigma: 16,
                          child: const Icon(
                            Icons.shield_outlined,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    const MicroLabel('Aura Nurture', color: Lumina.glow),
                    const SizedBox(height: 8),
                    Text(
                      'Danger-sign check',
                      style: Lumina.display(26, color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        LumePulse(color: statusColor, size: 8),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            statusLine,
                            style: Lumina.body(
                              size: 13.5,
                              color: AppColors.white85,
                              weight: 600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Container(
                      height: 1,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            Colors.white.withValues(alpha: 0.12),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SapphireButton(
                      label: person != null
                          ? 'Check ${person.fullName.split(' ').first}'
                          : 'Start the check',
                      expand: true,
                      onPressed: () => Navigator.of(context).push(
                        GlassPageRoute<void>(
                          builder: (_) => CaregiverTriageScreen(
                            householdId: householdId,
                            personId: selectedPersonId,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Emergency is an exit, not a footnote: full-width
                    // target with button semantics, so a frightened thumb
                    // and a screen reader both find it.
                    Semantics(
                      button: true,
                      child: GestureDetector(
                        onTap: () => showCaregiverEmergency(context),
                        child: Container(
                          width: double.infinity,
                          constraints: const BoxConstraints(minHeight: 48),
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFFF6B6B,
                            ).withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(Lumina.rSm),
                            border: Border.all(
                              color: const Color(
                                0xFFFF6B6B,
                              ).withValues(alpha: 0.45),
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                color: Color(0xFFFF6B6B),
                                size: 18,
                              ),
                              SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'Emergency — do not wait. Get help now',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    height: 1.25,
                                  ),
                                ),
                              ),
                            ],
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
      ],
    );
  }

  String _dayLabel(DateTime d) {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return days[d.weekday - 1];
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}';
  }

  String _statusSummary(HomeCheck check) {
    final when = caregiverWhen(check.checkedAt);
    return switch (check.verdict) {
      HomeCheckVerdict.urgent =>
        'Last check $when \u2014 a danger sign was found',
      HomeCheckVerdict.caution => 'Last check $when \u2014 some uncertainty',
      HomeCheckVerdict.fine => 'Last check $when \u2014 all clear',
    };
  }
}

class _PersonList extends StatelessWidget {
  const _PersonList({
    required this.people,
    required this.selectedId,
    required this.householdId,
    required this.checks,
  });

  final List<Person> people;
  final String? selectedId;
  final String householdId;
  final List<HomeCheck> checks;

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) {
      return CompanionCard(
        title: 'No family members yet',
        child: const SpeakableText(
          'Add someone you care for to begin checking danger signs.',
        ),
      );
    }
    final latestByPerson = <String, HomeCheck>{};
    for (final c in checks) {
      final existing = latestByPerson[c.personId];
      if (existing == null || c.checkedAt.isAfter(existing.checkedAt)) {
        latestByPerson[c.personId] = c;
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 14, left: 2),
          child: Text('Who are you checking?', style: Lumina.display(17)),
        ),
        for (final person in people)
          _PersonTile(
            person: person,
            lastCheck: latestByPerson[person.id],
            onTap: () => Navigator.of(context).push(
              GlassPageRoute<void>(
                builder: (_) => CaregiverTriageScreen(
                  householdId: householdId,
                  personId: person.id,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({
    required this.person,
    required this.lastCheck,
    required this.onTap,
  });

  final Person person;
  final HomeCheck? lastCheck;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // A pearl list card, so the triage signals stay in their saturated
    // clinical colours; the tab's one hero sits above this list.
    final statusColor = lastCheck == null
        ? Lumina.inkFaint
        : switch (lastCheck!.verdict) {
            HomeCheckVerdict.urgent => AppColors.triageRed,
            HomeCheckVerdict.caution => AppColors.triageAmber,
            HomeCheckVerdict.fine => AppColors.triageGreen,
          };
    final statusLabel = lastCheck == null
        ? 'Not checked yet'
        : switch (lastCheck!.verdict) {
            HomeCheckVerdict.urgent => 'Danger sign found',
            HomeCheckVerdict.caution => 'Some uncertainty',
            HomeCheckVerdict.fine => 'All clear',
          };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: LumenCard(
        onTap: onTap,
        radius: Lumina.rMd,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Tide-lit circle with white initials
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(
                gradient: Lumina.tide,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                person.fullName.isNotEmpty
                    ? person.fullName.characters.first.toUpperCase()
                    : '?',
                style: const TextStyle(
                  fontFamily: 'Sora',
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 14),
            // Name + role/age
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    person.fullName,
                    style: Lumina.display(16, weight: 700, color: Lumina.ink),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${person.ageLabel} \u2022 ${person.effectiveClientType.label}',
                    style: Lumina.body(
                      size: 12.5,
                      weight: 500,
                      color: Lumina.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
            // Status pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Lumina.tint,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                statusLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: statusColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistorySection extends ConsumerWidget {
  const _HistorySection({
    required this.householdId,
    required this.selectedPersonId,
    required this.checks,
    required this.members,
  });

  final String householdId;
  final String? selectedPersonId;
  final AsyncValue<List<HomeCheck>> checks;
  final List<Person> members;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 14, left: 2),
          child: Text('Check history', style: Lumina.display(17)),
        ),
        checks.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => CompanionLoadError(
            onRetry: () =>
                ref.invalidate(householdHomeChecksProvider(householdId)),
          ),
          data: (allChecks) {
            final filtered = selectedPersonId == null
                ? allChecks
                : allChecks.where((c) => c.personId == selectedPersonId);
            final sorted = filtered.toList()
              ..sort((a, b) => b.checkedAt.compareTo(a.checkedAt));
            if (sorted.isEmpty) {
              return LumenCard(
                padding: const EdgeInsets.all(24),
                radius: Lumina.rMd,
                child: Column(
                  children: [
                    Icon(
                      Icons.history_rounded,
                      size: 36,
                      color: Lumina.inkFaint,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'No completed checks yet',
                      style: Lumina.display(14, weight: 700, color: Lumina.ink),
                    ),
                    const SizedBox(height: 4),
                    // Force the parent Column's cross-axis to be tight so
                    // SpeakableText's internal Row sizes correctly and the
                    // centred hint icon lines up with the wrapped text.
                    const SizedBox(
                      width: double.infinity,
                      child: SpeakableText(
                        'A saved draft does not count as a completed check.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Lumina.inkMuted,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }
            return Column(
              children: [
                for (final check in sorted.take(10))
                  _HistoryTile(
                    check: check,
                    memberName: members
                        .where((p) => p.id == check.personId)
                        .firstOrNull
                        ?.fullName,
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.check, required this.memberName});

  final HomeCheck check;
  final String? memberName;

  @override
  Widget build(BuildContext context) {
    final color = switch (check.verdict) {
      HomeCheckVerdict.urgent => AppColors.triageRed,
      HomeCheckVerdict.caution => AppColors.triageAmber,
      HomeCheckVerdict.fine => AppColors.triageGreen,
    };
    final icon = switch (check.verdict) {
      HomeCheckVerdict.urgent => Icons.warning_amber_rounded,
      HomeCheckVerdict.caution => Icons.help_outline_rounded,
      HomeCheckVerdict.fine => Icons.check_circle_outline_rounded,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: LumenCard(
        onTap: () => Navigator.of(context).push(
          GlassPageRoute<void>(
            builder: (_) => CaregiverPersonDetail(personId: check.personId),
          ),
        ),
        radius: Lumina.rMd,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: Lumina.tint,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    memberName ?? 'Family member',
                    style: Lumina.display(14, weight: 700, color: Lumina.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${caregiverWhen(check.checkedAt)}  \u2022  ${caregiverCheckLabel(check.verdict)}',
                    style: Lumina.body(
                      size: 12.5,
                      weight: 500,
                      color: Lumina.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Lumina.inkFaint,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
