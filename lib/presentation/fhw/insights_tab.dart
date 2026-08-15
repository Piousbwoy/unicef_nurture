/// The zone-level view: what a paper register can never show.
///
/// Three reads, each answering a question a CHO is asked and cannot currently
/// answer:
///
/// **Which children are falling?** — the trajectory engine, aggregated. Every
/// child here has a *green* MUAC on every single reading and is still losing
/// ground. This is the "predict risk before crisis" challenge made concrete.
///
/// **Why is care not happening?** — the barrier reports, aggregated into
/// patterns with an interpretation and an escalation target. An individual
/// "no transport money" is a story; forty of them in one month is a budget
/// line the sub-district can act on.
///
/// **Do referrals land?** — the completion rate. A referral system nobody
/// checks is a referral system that quietly refers into the void.
///
/// Read weekly, not hourly — which is why it is the third tab.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/engines/barrier_engine.dart';
import '../../domain/engines/trajectory_engine.dart';
import '../../domain/entities/core.dart';
import '../shared/ui.dart';
import 'household_screen.dart';

class InsightsTab extends ConsumerWidget {
  const InsightsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final declining = ref.watch(decliningChildrenProvider);
    final barriers = ref.watch(barrierPatternsProvider);
    final completion = ref.watch(referralCompletionProvider);
    final impact = ref.watch(impactSummaryProvider);
    final mine = ref.watch(workerImpactProvider);

    return ListView(
      padding: const EdgeInsets.all(Gap.lg),
      children: [
        // ------------------------------------------------------- Zone impact
        SectionCard(
          title: 'What this phone has protected',
          subtitle:
              'Outcomes, not activity. Loops closed and danger caught early '
              '— the numbers a district team actually asks for.',
          icon: Icons.shield_outlined,
          child: impact.when(
            loading: () => const SizedBox.shrink(),
            error: (e, _) => const SizedBox.shrink(),
            data: (s) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    StatTile(
                      value: '${s.arrived}',
                      label: 'Referrals arrived\n(90 days)',
                      colour: s.arrived > 0
                          ? AppColors.triageGreen
                          : AppColors.inkMuted,
                    ),
                    const SizedBox(width: Gap.md),
                    StatTile(
                      value: '${s.urgentHomeChecks}',
                      label: 'Urgent checks by\nfamilies (30 days)',
                      colour: s.urgentHomeChecks > 0
                          ? AppColors.triageRed
                          : AppColors.inkMuted,
                    ),
                    const SizedBox(width: Gap.md),
                    StatTile(
                      value: '${s.flaggedChildren}',
                      label: 'Children flagged\nby families (30 days)',
                      colour: s.flaggedChildren > 0
                          ? AppColors.triageAmber
                          : AppColors.inkMuted,
                    ),
                  ],
                ),
                const SizedBox(height: Gap.md),
                const Text(
                  'An urgent home check is a family that found danger '
                  'before the danger found them. A flagged milestone is a '
                  'child examined before falling behind. Each arrived '
                  'referral is a loop closed. These are the records that '
                  'turn into lives — and every one of them was made on '
                  'this phone, offline.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.inkMuted,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Gap.lg),

        // ------------------------------------------ The worker's own month
        SectionCard(
          title: 'Your month with this phone',
          subtitle:
              'What the app did for you — not just what it reported about '
              'your zone.',
          icon: Icons.watch_later_outlined,
          child: mine.when(
            loading: () => const SizedBox.shrink(),
            error: (e, _) => const SizedBox.shrink(),
            data: (w) => w.assessments == 0
                ? const _NoneYet(
                    'Assess your first patient and this card starts counting: '
                    'the records written for you, the register time handed '
                    'back, and the times your judgement stood over the AI\u2019s.',
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          StatTile(
                            value: '${w.assessments}',
                            label: 'Assessments\nwritten (30 days)',
                            colour: AppColors.primary,
                          ),
                          const SizedBox(width: Gap.md),
                          StatTile(
                            value: _savedLabel(w.assessments),
                            label: 'Register time\nhanded back',
                            colour: AppColors.triageGreen,
                          ),
                          const SizedBox(width: Gap.md),
                          StatTile(
                            value: '${w.overrides}',
                            label: 'Times you\noverruled the AI',
                            colour: w.overrides > 0
                                ? AppColors.triageAmber
                                : AppColors.inkMuted,
                          ),
                        ],
                      ),
                      const SizedBox(height: Gap.md),
                      Text(
                        w.overrides > 0
                            ? 'Every assessment above is a register line you '
                                  'never had to write. And each override '
                                  'carries your written reason — your '
                                  'judgement stays the final word, and it is '
                                  'how the thresholds learn.'
                            : 'Every assessment above is a register line you '
                                  'never had to write. When you disagree with '
                                  'a recommendation, override it — your '
                                  'reason is kept with the record, and it is '
                                  'how the thresholds learn.',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.inkMuted,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: Gap.lg),

        // -------------------------------------------------- Declining children
        SectionCard(
          title: 'Children losing ground',
          subtitle:
              'MUAC is falling between visits while each reading still looks '
              'acceptable. The slope is the finding, not the last point.',
          icon: Icons.trending_down_rounded,
          accent: AppColors.triageRed,
          child: declining.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(Gap.lg),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (e, _) => ErrorView(error: e),
            data: (list) => list.isEmpty
                ? const _NoneYet(
                    'No child is currently falling. Keep measuring — the trend '
                    'only appears once a child has at least two readings.',
                  )
                : Column(
                    children: [
                      for (final item in list)
                        _DecliningTile(
                          child: item.child,
                          trajectory: item.trajectory,
                        ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: Gap.lg),

        // ----------------------------------------------------- Barrier patterns
        SectionCard(
          title: 'Why care is not happening',
          subtitle:
              'Barrier reports from the zone, grouped. The interpretation is '
              'the pattern; the escalation says who can act on it.',
          icon: Icons.report_gmailerrorred_rounded,
          accent: AppColors.triageAmber,
          child: barriers.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(Gap.lg),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (e, _) => ErrorView(error: e),
            data: (list) => list.isEmpty
                ? const _NoneYet(
                    'No barriers reported yet. Ask "what stopped you?" at every '
                    'missed contact — the answers are the data.',
                  )
                : Column(
                    children: [
                      for (final p in list) _BarrierTile(pattern: p),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: Gap.lg),

        // ------------------------------------------------- Referral completion
        SectionCard(
          title: 'Do referrals land?',
          subtitle:
              'Of the referrals issued, how many arrived. The gap is the '
              'last-mile follow-up problem.',
          icon: Icons.local_hospital_outlined,
          child: completion.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(Gap.lg),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (e, _) => ErrorView(error: e),
            data: (c) => _CompletionBody(
              issued: c.issued,
              arrived: c.arrived,
              rate: c.rate,
            ),
          ),
        ),
        const SizedBox(height: Gap.xxl),
      ],
    );
  }
}

/// A conservative register cost per patient seen: the register line, the
/// tally sheet and the defaulter cross-check a paper-based CHO pays for
/// every single contact.
const int _minutesPerPaperRecord = 6;

/// "45 min" under an hour, "3.5 h" above it — the way a person says it.
String _savedLabel(int assessments) {
  final minutes = assessments * _minutesPerPaperRecord;
  if (minutes < 60) return '$minutes min';
  final hours = minutes / 60;
  return hours >= 10 ? '${hours.round()} h' : '${hours.toStringAsFixed(1)} h';
}

class _NoneYet extends StatelessWidget {
  const _NoneYet(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Gap.md),
    child: Text(
      message,
      style: const TextStyle(
        fontSize: 12.5,
        color: AppColors.inkMuted,
        height: 1.45,
        fontStyle: FontStyle.italic,
      ),
    ),
  );
}

class _DecliningTile extends StatelessWidget {
  const _DecliningTile({required this.child, required this.trajectory});

  final Person child;
  final TrajectoryResult trajectory;

  @override
  Widget build(BuildContext context) {
    final falling = trajectory.trend == GrowthTrend.falling;
    final colour = falling ? AppColors.triageRed : AppColors.triageAmber;

    return Builder(
      builder: (context) => InkWell(
        borderRadius: BorderRadius.circular(Gap.radiusSm),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => HouseholdScreen(householdId: child.householdId),
          ),
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: Gap.sm),
          padding: const EdgeInsets.all(Gap.md),
          decoration: BoxDecoration(
            color: colour.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(Gap.radiusSm),
            border: Border(left: BorderSide(color: colour, width: 4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      child.fullName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    trajectory.trend.label,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: colour,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Gap.xs),
              if (trajectory.muacChangePerMonth != null)
                Text(
                  'MUAC ${trajectory.muacChangePerMonth! > 0 ? '+' : ''}'
                  '${trajectory.muacChangePerMonth!.toStringAsFixed(1)} cm/month '
                  '· ${trajectory.pointsUsed} readings',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.inkMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              if (trajectory.daysToSamThreshold != null) ...[
                const SizedBox(height: Gap.xs),
                Text(
                  'At this rate, below the SAM cut-off in about '
                  '${trajectory.daysToSamThreshold} days.',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: colour,
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: Gap.xs),
              Text(
                trajectory.explanation,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.inkMuted,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarrierTile extends StatelessWidget {
  const _BarrierTile({required this.pattern});

  final BarrierPattern pattern;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: Gap.sm),
    padding: const EdgeInsets.all(Gap.md),
    decoration: BoxDecoration(
      color: AppColors.canvas,
      borderRadius: BorderRadius.circular(Gap.radiusSm),
      border: Border.all(color: AppColors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                pattern.barrier.label,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Gap.sm,
                vertical: Gap.xs,
              ),
              decoration: BoxDecoration(
                color: AppColors.triageAmberBg,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${pattern.householdCount} '
                'household${pattern.householdCount == 1 ? '' : 's'}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppColors.triageAmber,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.xs),
        Text(
          pattern.interpretation,
          style: const TextStyle(
            fontSize: 12.5,
            color: AppColors.ink,
            height: 1.4,
          ),
        ),
        const SizedBox(height: Gap.xs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.arrow_upward_rounded,
              size: 14,
              color: AppColors.primary,
            ),
            const SizedBox(width: Gap.xs),
            Expanded(
              child: Text(
                pattern.escalation,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _CompletionBody extends StatelessWidget {
  const _CompletionBody({
    required this.issued,
    required this.arrived,
    required this.rate,
  });

  final int issued;
  final int arrived;
  final double rate;

  @override
  Widget build(BuildContext context) {
    final pct = (rate * 100).round();
    final colour = pct >= 70
        ? AppColors.triageGreen
        : pct >= 40
        ? AppColors.triageAmber
        : AppColors.triageRed;

    if (issued == 0) {
      return const _NoneYet(
        'No referrals issued yet. Once they are, this shows how many actually '
        'arrived — the number that tells you whether the referral ladder '
        'works.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            StatTile(value: '$issued', label: 'Issued'),
            const SizedBox(width: Gap.md),
            StatTile(value: '$arrived', label: 'Arrived'),
            const SizedBox(width: Gap.md),
            StatTile(
              value: '$pct%',
              label: 'Completed',
              colour: colour,
            ),
          ],
        ),
        const SizedBox(height: Gap.md),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: rate.clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: AppColors.canvas,
            valueColor: AlwaysStoppedAnimation(colour),
          ),
        ),
        const SizedBox(height: Gap.md),
        Text(
          pct >= 70
              ? 'Most referrals are landing. Keep confirming arrivals — the '
                    'record is what keeps the loop honest.'
              : 'Too many referrals are not arriving. Chase the open ones from '
                    'the day plan, and record the barrier when you find out '
                    'why.',
          style: const TextStyle(
            fontSize: 12.5,
            color: AppColors.inkMuted,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}
