/// One household, in full.
///
/// This is where the ranking from "Plan My Day" has to justify itself. The day
/// plan says *this household first*; this screen says *why*, in the arithmetic,
/// and then — the part that actually changes an outcome — separates the risk a
/// CHO can do something about this week from the risk they cannot.
///
/// Three deliberate choices:
///
/// **The score is recomputed here, not passed in.** [householdScoreProvider]
/// runs the same engine over the same inputs as the day plan, so the number on
/// this screen can never disagree with the number that put the household in the
/// queue. A detail view that contradicts the list is a detail view a CHO stops
/// believing, and then the whole ranking is dead.
///
/// **Modifiable risk comes first.** "Previous stillbirth: 18 points" is real and
/// unfixable. "No IPTp doses given: 10 points" is fixable today, with a tablet
/// that is already in the CHPS fridge. The second list is the one that saves
/// somebody, so it is the one at the top.
///
/// **Members are listed in visit order, not alphabetically.** Mother, then
/// newborns, then under-fives by age — the order care is actually delivered, and
/// the order the roll call will use. A mother who arrives with a newborn twin and
/// a three-year-old sees all three here, in one place, which is the scenario the
/// whole app was built around.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/care_repository.dart';
import '../../domain/engines/trajectory_engine.dart';
import '../../domain/engines/vulnerability_engine.dart';
import '../../domain/entities/core.dart';
import '../../domain/entities/visit.dart';
import '../../domain/enums.dart';
import '../auth/setup_screen.dart' show FamilyCodeSheet;
import '../registration/member_form_screen.dart';
import '../shared/ui.dart';
import '../visit/barrier_check_screen.dart';
import '../visit/roll_call_screen.dart';

class HouseholdScreen extends ConsumerWidget {
  const HouseholdScreen({super.key, required this.householdId});

  final String householdId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final household = ref.watch(householdProvider(householdId));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          household.valueOrNull?.name ?? 'Household',
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (household.valueOrNull != null)
            IconButton(
              tooltip: 'Family code',
              icon: const Icon(Icons.qr_code_2_rounded),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                builder: (_) => FamilyCodeSheet(household: household.value!),
              ),
            ),
        ],
      ),
      body: household.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          error: e is AccessDenied ? e.message : e,
          onRetry: () => ref.invalidate(householdProvider(householdId)),
        ),
        data: (h) => h == null
            ? const EmptyState(
                icon: Icons.home_outlined,
                title: 'Household not found',
                message:
                    'This record may have been removed, or it belongs to '
                    'another zone.',
              )
            : _Body(h),
      ),
      bottomNavigationBar: household.valueOrNull == null
          ? null
          : _Actions(household.value!),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body(this.household);

  final Household household;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final score = ref.watch(householdScoreProvider(household.id));
    final members = ref.watch(householdMembersProvider(household.id));
    final contacts = ref.watch(householdContactsProvider(household.id));
    final barriers = ref.watch(barrierHistoryProvider(household.id));
    final homeChecks = ref.watch(householdHomeChecksProvider(household.id));
    final milestoneChecks = ref.watch(
      householdMilestoneChecksProvider(household.id),
    );

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(householdScoreProvider(household.id));
        ref.invalidate(householdMembersProvider(household.id));
      },
      child: ListView(
        padding: const EdgeInsets.all(Gap.lg),
        children: [
          _Identity(household),
          const SizedBox(height: Gap.lg),

          score.when(
            loading: () => const SectionCard(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => ErrorView(error: e),
            data: (s) => _RiskCard(s),
          ),
          const SizedBox(height: Gap.lg),

          members.when(
            loading: () => const SizedBox.shrink(),
            error: (e, _) => ErrorView(error: e),
            data: (list) => _Members(household: household, members: list),
          ),
          const SizedBox(height: Gap.lg),

          contacts.maybeWhen(
            data: (list) => list.isEmpty
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(bottom: Gap.lg),
                    child: SectionCard(
                      title: 'Scheduled next',
                      subtitle:
                          'Contacts already booked for this household. Overdue '
                          'ones are shown in red.',
                      icon: Icons.event_outlined,
                      child: Column(
                        children: [
                          for (final c in list)
                            Padding(
                              padding: const EdgeInsets.only(bottom: Gap.sm),
                              child: Row(
                                children: [
                                  TriageBadge(
                                    c.priority,
                                    label: c.isOverdue
                                        ? '${-c.daysUntilDue}d late'
                                        : c.daysUntilDue == 0
                                        ? 'Today'
                                        : 'In ${c.daysUntilDue}d',
                                    compact: true,
                                  ),
                                  const SizedBox(width: Gap.md),
                                  Expanded(
                                    child: Text(
                                      c.purpose,
                                      style: const TextStyle(
                                        fontSize: 13.5,
                                        height: 1.3,
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
            orElse: () => const SizedBox.shrink(),
          ),

          barriers.maybeWhen(
            data: (list) => list.isEmpty
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(bottom: Gap.lg),
                    child: SectionCard(
                      title: 'What has stopped care here before',
                      subtitle:
                          'Reported by this family. Read it before issuing a '
                          'referral — a barrier already named should never have '
                          'to be discovered twice.',
                      icon: Icons.report_problem_outlined,
                      accent: AppColors.triageAmber,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final b in list.toSet())
                            Padding(
                              padding: const EdgeInsets.only(bottom: Gap.md),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    b.label,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    b.suggestedAction,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      color: AppColors.inkMuted,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),

          homeChecks.maybeWhen(
            data: (list) {
              // Two weeks is the window in which a family's report still
              // changes what the worker examines first; older than that it is
              // history, not triage.
              final recent = list
                  .where(
                    (c) =>
                        DateTime.now().difference(c.checkedAt).inDays <= 14,
                  )
                  .take(4)
                  .toList(growable: false);
              if (recent.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: Gap.lg),
                child: SectionCard(
                  title: 'What the family reported',
                  subtitle:
                      'Danger-sign checks this family ran on their own '
                      'phone. Their words, not a diagnosis — but examine '
                      'these people first.',
                  icon: Icons.campaign_outlined,
                  accent: AppColors.triageRed,
                  child: Column(
                    children: [
                      for (final c in recent) _FamilyReportTile(check: c),
                    ],
                  ),
                ),
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),

          milestoneChecks.maybeWhen(
            data: (list) {
              // Development is read as "where is this child now", not as a
              // diary: keep only the newest check per child, then surface the
              // CCD flags before everything else.
              final latestByChild = <String, MilestoneCheck>{};
              for (final c in list) {
                latestByChild.putIfAbsent(c.personId, () => c);
              }
              final recent = latestByChild.values
                  .where(
                    (c) =>
                        DateTime.now().difference(c.checkedAt).inDays <= 30,
                  )
                  .toList(growable: false)
                ..sort((a, b) {
                  final flagA =
                      a.verdict == MilestoneVerdict.flag ? 0 : 1;
                  final flagB =
                      b.verdict == MilestoneVerdict.flag ? 0 : 1;
                  final byFlag = flagA.compareTo(flagB);
                  if (byFlag != 0) return byFlag;
                  return b.checkedAt.compareTo(a.checkedAt);
                });
              final show = recent.take(4).toList(growable: false);
              if (show.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: Gap.lg),
                child: SectionCard(
                  title: 'What the family says the children can do',
                  subtitle:
                      'Milestone checks run on the family\u2019s own phone. '
                      'Flags first — these are the WHO Care for Child '
                      'Development signs the family answered "not yet" to. '
                      'Examine these children before the rest.',
                  icon: Icons.child_care_rounded,
                  accent: AppColors.primary,
                  child: Column(
                    children: [
                      for (final c in show) _MilestoneReportTile(check: c),
                    ],
                  ),
                ),
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),

          const SizedBox(height: Gap.xxl * 2),
        ],
      ),
    );
  }
}

/// One home check, as the family reported it. The verdict keeps its colour
/// so a red report is visible before it is read.
class _FamilyReportTile extends ConsumerWidget {
  const _FamilyReportTile({required this.check});

  final HomeCheck check;

  Color get _colour => switch (check.verdict) {
    HomeCheckVerdict.urgent => AppColors.triageRed,
    HomeCheckVerdict.caution => AppColors.triageAmber,
    HomeCheckVerdict.fine => AppColors.triageGreen,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final person = ref.watch(personProvider(check.personId));
    final days = DateTime.now().dateOnly.difference(
      check.checkedAt.dateOnly,
    ).inDays;
    final when = switch (days) {
      <= 0 => 'today',
      1 => 'yesterday',
      _ => '$days days ago',
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 5),
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: _colour,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${person.valueOrNull?.fullName ?? '…'} · $when',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  check.verdict.label,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: check.verdict == HomeCheckVerdict.fine
                        ? AppColors.inkMuted
                        : _colour,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (check.yesSigns.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'They said yes to: ${check.yesSigns.join('; ')}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.inkMuted,
                      height: 1.35,
                    ),
                  ),
                ],
                if (check.unsureSigns.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Not sure about: ${check.unsureSigns.join('; ')}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.inkFaint,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One milestone check as the family reported it. The family's words again —
/// a flag is a reason to examine, never a developmental diagnosis.
class _MilestoneReportTile extends ConsumerWidget {
  const _MilestoneReportTile({required this.check});

  final MilestoneCheck check;

  Color get _colour => switch (check.verdict) {
    MilestoneVerdict.flag => AppColors.triageRed,
    MilestoneVerdict.watch => AppColors.triageAmber,
    MilestoneVerdict.onTrack => AppColors.triageGreen,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final person = ref.watch(personProvider(check.personId));
    final days = DateTime.now().dateOnly.difference(
      check.checkedAt.dateOnly,
    ).inDays;
    final when = switch (days) {
      <= 0 => 'today',
      1 => 'yesterday',
      _ => '$days days ago',
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 5),
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: _colour,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${person.valueOrNull?.fullName ?? '…'} · $when',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${check.bandLabel} · ${check.verdict.label}',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: check.verdict == MilestoneVerdict.onTrack
                        ? AppColors.inkMuted
                        : _colour,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (check.notYet.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Not yet: ${check.notYet.join('; ')}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.inkMuted,
                      height: 1.35,
                    ),
                  ),
                ],
                if (check.flags.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'CCD flags: ${check.flags.join('; ')}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.triageRed,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Where the household is and how hard it is to reach.
///
/// Walking time and NHIS validity sit here rather than in an admin tab because
/// they are clinical facts in this setting: a 120-minute walk decides whether a
/// "go to the health centre today" referral is advice or fiction.
class _Identity extends StatelessWidget {
  const _Identity(this.household);

  final Household household;

  @override
  Widget build(BuildContext context) {
    final h = household;
    return SectionCard(
      title: h.name,
      subtitle: '${h.community}, ${h.district}, ${h.region}',
      icon: Icons.home_work_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (h.landmark != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.place_outlined,
                  size: 16,
                  color: AppColors.inkMuted,
                ),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text(
                    h.landmark!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.inkMuted,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Gap.md),
          ],
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            children: [
              if (h.headName != null)
                _Fact(
                  icon: Icons.person_outline_rounded,
                  label: 'Head',
                  value: h.headName!,
                ),
              if (h.familySize != null)
                _Fact(
                  icon: Icons.groups_outlined,
                  label: 'People',
                  value: '${h.familySize}',
                ),
              if (h.walkingMinutesToFacility != null)
                _Fact(
                  icon: Icons.directions_walk_rounded,
                  label: 'To facility',
                  value: '${h.walkingMinutesToFacility} min walk',
                  danger: h.walkingMinutesToFacility! >= 90,
                ),
              _Fact(
                icon: h.hasValidNhis == true
                    ? Icons.credit_card_rounded
                    : Icons.credit_card_off_outlined,
                label: 'NHIS',
                value: switch (h.hasValidNhis) {
                  true => 'Valid',
                  false => 'Not valid',
                  null => 'Not recorded',
                },
                danger: h.hasValidNhis == false,
              ),
              if (h.contactPhone != null)
                _Fact(
                  icon: Icons.phone_outlined,
                  label: 'Phone',
                  value: h.contactPhone!,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({
    required this.icon,
    required this.label,
    required this.value,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final colour = danger ? AppColors.triageRed : AppColors.inkMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.sm),
      decoration: BoxDecoration(
        color: danger ? AppColors.triageRedBg : AppColors.canvas,
        borderRadius: BorderRadius.circular(Gap.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colour),
          const SizedBox(width: Gap.xs),
          Text(
            '$label: ',
            style: TextStyle(fontSize: 12, color: colour),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: danger ? AppColors.triageRed : AppColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// The score, decomposed.
class _RiskCard extends StatelessWidget {
  const _RiskCard(this.score);

  final VulnerabilityScore score;

  @override
  Widget build(BuildContext context) {
    final c = triageColours(score.band.triage);

    return SectionCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(Gap.lg),
            decoration: BoxDecoration(
              color: c.bg,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(Gap.radius),
              ),
            ),
            child: Row(
              children: [
                Icon(triageIcon(score.band.triage), color: c.fg, size: 22),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${score.band.label} risk · ${score.band.action}',
                        style: TextStyle(
                          color: c.fg,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        score.whyThisRanking,
                        style: TextStyle(
                          color: c.fg.withValues(alpha: 0.9),
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Gap.sm),
                Text(
                  '${score.score.round()}',
                  style: TextStyle(
                    color: c.fg,
                    fontWeight: FontWeight.w800,
                    fontSize: 30,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(Gap.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ConfidenceChip(
                      score.confidence,
                      missingCount: score.unknowns.length,
                    ),
                    const SizedBox(width: Gap.sm),
                    Text(
                      '${(score.dataCompleteness * 100).round()}% measured',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.inkMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.lg),

                if (score.modifiable.isNotEmpty) ...[
                  const _RiskHeading(
                    'What can be changed',
                    'These are the points that come off if something is done. '
                        'This list is the follow-up plan.',
                    Icons.build_circle_outlined,
                    AppColors.primary,
                  ),
                  for (final f in score.modifiable) _FactorTile(f, actionable: true),
                  const SizedBox(height: Gap.lg),
                ],

                if (score.nonModifiable.isNotEmpty) ...[
                  const _RiskHeading(
                    'Fixed history',
                    'Cannot be undone, but it changes how closely this family '
                        'should be watched.',
                    Icons.lock_outline_rounded,
                    AppColors.inkMuted,
                  ),
                  for (final f in score.nonModifiable) _FactorTile(f),
                  const SizedBox(height: Gap.lg),
                ],

                if (score.unknowns.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(Gap.md),
                    decoration: BoxDecoration(
                      color: AppColors.canvas,
                      borderRadius: BorderRadius.circular(Gap.radiusSm),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.help_outline_rounded,
                              size: 16,
                              color: AppColors.inkMuted,
                            ),
                            SizedBox(width: Gap.sm),
                            Text(
                              'Not measured yet',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: Gap.xs),
                        const Text(
                          'Recording these is the cheapest way to make this '
                          'score trustworthy. Missing information never lowers '
                          'the risk here — it only lowers the confidence.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.inkFaint,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: Gap.sm),
                        for (final u in score.unknowns)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text(
                              '• $u',
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: AppColors.inkMuted,
                                height: 1.35,
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
    );
  }
}

class _RiskHeading extends StatelessWidget {
  const _RiskHeading(this.title, this.blurb, this.icon, this.colour);

  final String title;
  final String blurb;
  final IconData icon;
  final Color colour;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Gap.sm),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: colour),
            const SizedBox(width: Gap.xs),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: colour,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          blurb,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.inkFaint,
            height: 1.35,
          ),
        ),
      ],
    ),
  );
}

class _FactorTile extends StatelessWidget {
  const _FactorTile(this.factor, {this.actionable = false});

  final RiskFactor factor;
  final bool actionable;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Gap.md),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The weight, shown. A CHO who can see the arithmetic can argue with it,
        // and one who can argue with it will use it.
        Container(
          width: 34,
          padding: const EdgeInsets.symmetric(vertical: 3),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: actionable ? AppColors.primaryLight : AppColors.canvas,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '+${factor.points.round()}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: actionable ? AppColors.primary : AppColors.inkMuted,
            ),
          ),
        ),
        const SizedBox(width: Gap.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                factor.label,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                factor.detail,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.inkMuted,
                  height: 1.35,
                ),
              ),
              if (factor.suggestedAction != null) ...[
                const SizedBox(height: Gap.xs),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.arrow_forward_rounded,
                      size: 13,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        factor.suggestedAction!,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (factor.source != null) ...[
                const SizedBox(height: Gap.xs),
                Text(
                  factor.source!,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.inkFaint,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class _Members extends StatelessWidget {
  const _Members({required this.household, required this.members});

  final Household household;
  final List<Person> members;

  @override
  Widget build(BuildContext context) => SectionCard(
    title: 'Who lives here',
    subtitle: members.isEmpty
        ? null
        : 'In the order care is given: mother first, then newborns, then '
              'children under five.',
    icon: Icons.diversity_3_outlined,
    trailing: Text(
      '${members.length}',
      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
    ),
    child: members.isEmpty
        ? Padding(
            padding: const EdgeInsets.only(top: Gap.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Nobody is registered in this household yet. A household '
                  'with no members cannot be assessed or scored properly.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.inkMuted,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: Gap.md),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => MemberFormScreen(household: household),
                    ),
                  ),
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('Add the first person'),
                ),
              ],
            ),
          )
        : Column(
            children: [for (final p in members) _MemberTile(p)],
          ),
  );
}

class _MemberTile extends ConsumerWidget {
  const _MemberTile(this.person);

  final Person person;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = person.effectiveClientType;
    final last = ref.watch(latestAssessmentProvider(person.id));
    final isChild =
        type == ClientType.newborn || type == ClientType.childUnderFive;

    return Container(
      margin: const EdgeInsets.only(bottom: Gap.sm),
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(Gap.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.primaryLight,
                child: Icon(
                  switch (type) {
                    ClientType.pregnantWoman => Icons.pregnant_woman_rounded,
                    ClientType.postpartumWoman => Icons.woman_rounded,
                    ClientType.womanOfReproductiveAge => Icons.woman_outlined,
                    ClientType.newborn => Icons.child_friendly_rounded,
                    ClientType.childUnderFive => Icons.child_care_rounded,
                  },
                  size: 19,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      person.fullName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                      ),
                    ),
                    Text(
                      '${type.label} · ${person.ageLabel}'
                      '${person.isDobEstimated ? ' (estimated)' : ''}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              // The protocol that governs this person. Printed because it is the
              // chart booklet the CHO will reach for, and because it changes on
              // its own as the child ages past 59 days.
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Gap.sm,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.line),
                ),
                child: Text(
                  type.protocolLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.inkMuted,
                  ),
                ),
              ),
            ],
          ),

          last.maybeWhen(
            data: (a) => a == null
                ? const Padding(
                    padding: EdgeInsets.only(top: Gap.sm),
                    child: Text(
                      'Never assessed on this device.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.inkFaint,
                      ),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.only(top: Gap.sm),
                    child: Row(
                      children: [
                        TriageBadge(a.effectiveTriage, compact: true),
                        const SizedBox(width: Gap.sm),
                        Expanded(
                          child: Text(
                            '${a.result.classification} · '
                            '${_ago(a.performedAt)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.inkMuted,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),

          if (isChild) _GrowthLine(person.id),
        ],
      ),
    );
  }

  static String _ago(DateTime when) {
    final days = DateTime.now().difference(when).inDays;
    if (days <= 0) return 'today';
    if (days == 1) return 'yesterday';
    if (days < 30) return '$days days ago';
    final months = (days / 30.4375).round();
    return '$months month${months == 1 ? '' : 's'} ago';
  }
}

/// The trajectory, in one line.
///
/// This is the app's sharpest clinical claim and it belongs on the member tile,
/// not three taps away: a child whose MUAC has fallen 0.4 cm a month is in
/// trouble while every single reading still says "yellow". The slope is the
/// finding.
class _GrowthLine extends ConsumerWidget {
  const _GrowthLine(this.personId);

  final String personId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trajectoryProvider(personId));

    return t.maybeWhen(
      data: (r) {
        if (r.trend == GrowthTrend.insufficientData) {
          return const SizedBox.shrink();
        }
        final falling = r.trend == GrowthTrend.falling;
        final flat = r.trend == GrowthTrend.flat;
        final colour = falling
            ? AppColors.triageRed
            : flat
            ? AppColors.triageAmber
            : AppColors.triageGreen;

        return Padding(
          padding: const EdgeInsets.only(top: Gap.sm),
          child: Container(
            padding: const EdgeInsets.all(Gap.sm),
            decoration: BoxDecoration(
              color: colour.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  falling
                      ? Icons.trending_down_rounded
                      : flat
                      ? Icons.trending_flat_rounded
                      : Icons.trending_up_rounded,
                  size: 15,
                  color: colour,
                ),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Growth: ${r.trend.label}'
                        '${r.daysToSamThreshold == null ? '' : ' — severe '
                              'malnutrition in about ${r.daysToSamThreshold} '
                              'days at this rate'}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: colour,
                          height: 1.3,
                        ),
                      ),
                      if (r.explanation.isNotEmpty)
                        Text(
                          r.explanation,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.inkMuted,
                            height: 1.3,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

/// The two things a CHO does from this screen.
///
/// Both are permission-gated, and the gate is a capability rather than a role —
/// a caregiver who somehow reached this screen sees the household but cannot
/// start a clinical assessment, which is also what the repository would tell
/// them.
class _Actions extends ConsumerWidget {
  const _Actions(this.household);

  final Household household;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SizedBox.shrink();

    final canAssess = user.can(Permission.runClinicalAssessment);
    final canRegister = user.can(Permission.registerHousehold);
    if (!canAssess && !canRegister) return const SizedBox.shrink();

    return SafeArea(
      minimum: const EdgeInsets.all(Gap.lg),
      child: Row(
        children: [
          if (canRegister) ...[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context)
                    .push(
                      MaterialPageRoute(
                        builder: (_) => MemberFormScreen(household: household),
                      ),
                    )
                    .then((_) {
                      ref.invalidate(householdMembersProvider(household.id));
                      ref.invalidate(householdScoreProvider(household.id));
                    }),
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: const Text('Add person'),
              ),
            ),
            const SizedBox(width: Gap.md),
          ],
          if (canAssess)
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: () async {
                  await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) =>
                          BarrierCheckScreen(householdId: household.id),
                    ),
                  );
                  if (!context.mounted) return;
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          RollCallScreen(householdId: household.id),
                    ),
                  );
                  if (!context.mounted) return;
                  ref.invalidate(householdScoreProvider(household.id));
                  ref.invalidate(dayPlanProvider);
                },
                icon: const Icon(Icons.play_circle_outline_rounded),
                label: const Text('Start assessment'),
              ),
            ),
        ],
      ),
    );
  }
}
