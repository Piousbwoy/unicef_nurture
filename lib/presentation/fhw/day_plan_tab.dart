/// "Plan My Day" — the ranked household plan.
///
/// This screen is the answer to the hackathon's first challenge: predicting risk
/// *before* the crisis. A CHO covering 200-plus households with a paper
/// register plans by proximity and memory, which means the quiet household
/// with the falling child is seen last. Here the order is computed, and —
/// this is the part that decides whether it gets used — every position comes
/// with the reason it holds that position.
///
/// The order of the sections is a clinical judgement, not a layout preference:
///
/// 1. **Unconfirmed urgent referrals.** Somebody was told to go to a facility and
///    nobody knows whether they did. Nothing outranks this.
/// 2. **Overdue scheduled contacts.** A missed day-3 PNC check is the
///    interval where most neonatal deaths in this region happen.
/// 3. **The ranked households**, critical first, each with its reason.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/insight_repository.dart';
import '../../domain/entities/visit.dart';
import '../shared/ui.dart';
import 'follow_up_check_in_screen.dart';
import 'household_screen.dart';

class DayPlanTab extends ConsumerWidget {
  const DayPlanTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(dayPlanProvider);
    final sync = ref.watch(syncStatusProvider);

    return Column(
      children: [
        sync.maybeWhen(
          data: (s) => SyncBanner(
            pending: s.pending,
            failing: s.failing,
            detail: s.detail,
            onTap: () => ref.read(syncServiceProvider).valueOrNull?.drain(),
          ),
          orElse: () => const SizedBox.shrink(),
        ),
        Expanded(
          child: plan.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorView(
              error: e,
              onRetry: () => ref.invalidate(dayPlanProvider),
            ),
            data: (data) => RefreshIndicator(
              onRefresh: () async => ref.invalidate(dayPlanProvider),
              child: _PlanBody(data),
            ),
          ),
        ),
      ],
    );
  }
}

class _PlanBody extends ConsumerWidget {
  const _PlanBody(this.plan);

  final DayPlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (plan.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 80),
          EmptyState(
            icon: Icons.wb_sunny_outlined,
            title: 'Nothing urgent today',
            message:
                'No household in your zone is flagged. Use today for routine '
                'follow-up, or register a new family.',
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(Gap.lg),
      children: [
        _Headline(plan),
        const SizedBox(height: Gap.lg),

        if (plan.chaseReferrals.isNotEmpty) ...[
          SectionCard(
            title: 'Trace these first',
            subtitle:
                'Urgent referrals with no confirmed arrival. Each one is a '
                'family that was told to go and, as far as this phone knows, '
                'did not.',
            icon: Icons.crisis_alert_rounded,
            accent: AppColors.triageRed,
            child: Column(
              children: [
                for (final r in plan.chaseReferrals)
                  _ChaseTile(
                    referral: r,
                    onCheckIn: () async {
                      final changed = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => FollowUpCheckInScreen(referral: r),
                        ),
                      );
                      if (changed == true && context.mounted) {
                        ref.invalidate(dayPlanProvider);
                        ref.invalidate(openReferralsProvider);
                      }
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: Gap.lg),
        ],

        if (plan.overdueContacts.isNotEmpty) ...[
          SectionCard(
            title: 'Overdue contacts',
            subtitle:
                'Scheduled contacts that have passed their date. A missed '
                'day-3 postnatal check is the highest-risk gap in the whole '
                'schedule.',
            icon: Icons.event_busy_outlined,
            accent: AppColors.triageAmber,
            child: Column(
              children: [
                for (final c in plan.overdueContacts.take(6))
                  _ContactTile(c, overdue: true),
              ],
            ),
          ),
          const SizedBox(height: Gap.lg),
        ],

        if (plan.dueContacts.isNotEmpty) ...[
          SectionCard(
            title: 'Due today',
            icon: Icons.event_available_outlined,
            child: Column(
              children: [
                for (final c in plan.dueContacts.take(6)) _ContactTile(c),
              ],
            ),
          ),
          const SizedBox(height: Gap.lg),
        ],

        Padding(
          padding: const EdgeInsets.only(left: Gap.xs, bottom: Gap.sm),
          child: Row(
            children: [
              const Text(
                'Households by risk',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Text(
                '${plan.priorities.length} in your zone',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.inkMuted,
                ),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(left: Gap.xs, bottom: Gap.md),
          child: Text(
            'Ranked by the risk score, and where two households score the same, '
            'the one we know least about is first — a household nobody has '
            'measured is not a safe household.',
            style: TextStyle(
              fontSize: 12.5,
              color: AppColors.inkFaint,
              height: 1.35,
            ),
          ),
        ),

        for (final p in plan.priorities)
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.md),
            child: HouseholdPriorityCard(priority: p),
          ),
        const SizedBox(height: Gap.xxl),
      ],
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline(this.plan);

  final DayPlan plan;

  @override
  Widget build(BuildContext context) {
    final critical = plan.critical.length;
    final colour = critical > 0 || plan.chaseReferrals.isNotEmpty
        ? AppColors.triageRed
        : AppColors.primary;

    return Container(
      padding: const EdgeInsets.all(Gap.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colour, colour.withValues(alpha: 0.82)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(Gap.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_awesome_rounded,
                color: Colors.white70,
                size: 16,
              ),
              const SizedBox(width: Gap.xs),
              Text(
                'Your plan for today',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          Text(
            plan.headline,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
          const SizedBox(height: Gap.lg),
          Row(
            children: [
              _MiniStat(
                value: '${plan.critical.length}',
                label: 'See today',
              ),
              _MiniStat(value: '${plan.high.length}', label: 'This week'),
              _MiniStat(
                value: '${plan.overdueContacts.length}',
                label: 'Overdue',
              ),
              _MiniStat(
                value: '${plan.priorities.length}',
                label: 'Households',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

/// One household in the queue.
///
/// The card carries its own justification. This is not decoration: an ordering a
/// CHO cannot interrogate is an ordering they will override with their own
/// intuition, and then the ranking has bought nothing.
class HouseholdPriorityCard extends StatelessWidget {
  const HouseholdPriorityCard({super.key, required this.priority});

  final HouseholdPriority priority;

  @override
  Widget build(BuildContext context) {
    final band = priority.band;
    final c = triageColours(band.triage);
    final h = priority.household;

    return Material
    (
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(Gap.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(Gap.radius),
        // Pushed rather than routed: this subtree is already behind the FHW role
        // guard, and the household screen re-checks scope at the repository
        // anyway. Adding a path per household would buy nothing but deep links
        // nobody uses offline.
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => HouseholdScreen(householdId: h.id),
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Gap.radius),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Band strip. Colour is the fastest signal on the screen, and it
              // matches the IMCI chart booklet a CHO already knows.
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Gap.md,
                  vertical: Gap.sm,
                ),
                decoration: BoxDecoration(
                  color: c.bg,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(Gap.radius),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(triageIcon(band.triage), size: 16, color: c.fg),
                    const SizedBox(width: Gap.xs),
                    Text(
                      '${band.label} · ${band.action}',
                      style: TextStyle(
                        color: c.fg,
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${priority.score.score.round()}',
                      style: TextStyle(
                        color: c.fg,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(Gap.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      h.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${h.community}, ${h.district}'
                      '${h.landmark == null ? '' : ' · ${h.landmark}'}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.inkMuted,
                      ),
                    ),
                    const SizedBox(height: Gap.md),
                    Container(
                      padding: const EdgeInsets.all(Gap.md),
                      decoration: BoxDecoration(
                        color: AppColors.canvas,
                        borderRadius: BorderRadius.circular(Gap.radiusSm),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.psychology_outlined,
                            size: 16,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: Gap.sm),
                          Expanded(
                            child: Text(
                              priority.reason,
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.4,
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Gap.md),
                    Wrap(
                      spacing: Gap.sm,
                      runSpacing: Gap.xs,
                      children: [
                        if (priority.mother != null)
                          _Tag(
                            icon: Icons.pregnant_woman_outlined,
                            label: priority.mother!.effectiveClientType
                                .protocolLabel,
                          ),
                        if (priority.childCount > 0)
                          _Tag(
                            icon: Icons.child_care_outlined,
                            label:
                                '${priority.childCount} under 5',
                          ),
                        if (h.walkingMinutesToFacility != null)
                          _Tag(
                            icon: Icons.directions_walk_rounded,
                            label: '${h.walkingMinutesToFacility} min walk',
                            danger: h.walkingMinutesToFacility! >= 90,
                          ),
                        if (priority.daysSinceLastVisit != null)
                          _Tag(
                            icon: Icons.history_rounded,
                            label:
                                'Seen ${priority.daysSinceLastVisit}d ago',
                            danger: priority.daysSinceLastVisit! > 60,
                          )
                        else
                          const _Tag(
                            icon: Icons.help_outline_rounded,
                            label: 'Never assessed',
                            danger: true,
                          ),
                        if (h.hasValidNhis == false)
                          const _Tag(
                            icon: Icons.credit_card_off_outlined,
                            label: 'No NHIS',
                            danger: true,
                          ),
                        if (priority.openReferral != null)
                          _Tag(
                            icon: Icons.local_hospital_outlined,
                            label:
                                'Referral open '
                                '${priority.openReferral!.hoursOpen}h',
                            danger: true,
                          ),
                      ],
                    ),
                    if (priority.score.dataCompleteness < 0.6) ...[
                      const SizedBox(height: Gap.sm),
                      Row(
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            size: 14,
                            color: AppColors.inkFaint,
                          ),
                          const SizedBox(width: Gap.xs),
                          Expanded(
                            child: Text(
                              'Only '
                              '${(priority.score.dataCompleteness * 100).round()}% '
                              'of the risk information has been measured — this '
                              'score may be low for the wrong reason.',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppColors.inkFaint,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
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

class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.label, this.danger = false});

  final IconData icon;
  final String label;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final colour = danger ? AppColors.triageRed : AppColors.inkMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 4),
      decoration: BoxDecoration(
        color: danger ? AppColors.triageRedBg : AppColors.canvas,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: colour),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              color: colour,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChaseTile extends StatelessWidget {
  const _ChaseTile({required this.referral, required this.onCheckIn});

  final Referral referral;
  final VoidCallback onCheckIn;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onCheckIn,
    borderRadius: BorderRadius.circular(Gap.radiusSm),
    child: Container(
      margin: const EdgeInsets.only(bottom: Gap.sm),
    padding: const EdgeInsets.all(Gap.md),
    decoration: BoxDecoration(
      color: AppColors.triageRedBg,
      borderRadius: BorderRadius.circular(Gap.radiusSm),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.directions_run_rounded,
          size: 18,
          color: AppColors.triageRed,
        ),
        const SizedBox(width: Gap.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                referral.reason,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${referral.referenceCode} · ${referral.facilityName} · '
                'open ${referral.hoursOpen}h · ${referral.urgency.label}',
                style: const TextStyle(
                  fontSize: 12,
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
}

class _ContactTile extends StatelessWidget {
  const _ContactTile(this.contact, {this.overdue = false});

  final ScheduledContact contact;
  final bool overdue;

  @override
  Widget build(BuildContext context) {
    final days = contact.daysUntilDue;
    final when = overdue
        ? '${-days} day${days == -1 ? '' : 's'} late'
        : days == 0
        ? 'Today'
        : 'In $days day${days == 1 ? '' : 's'}';

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: Row(
        children: [
          TriageBadge(contact.priority, label: when, compact: true),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Text(
              contact.purpose,
              style: const TextStyle(fontSize: 13.5, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}
