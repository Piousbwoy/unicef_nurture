/// The referrals the worker has issued and has not yet seen completed.
///
/// Three lanes, in the order that maps onto the worker's afternoon:
///
/// 1. **Urgent and unconfirmed** — somebody was told to go to a facility today,
///    and nobody knows whether they did. Nothing else outranks this.
/// 2. **Open (not urgent)** — the routine referrals still in flight.
/// 3. **Recently closed** — last thirty days of completions, so the worker
///    can see their own throughput without leaving the screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/visit.dart';
import '../../domain/enums.dart';
import '../shared/ui.dart';
import 'household_screen.dart';

class ReferralsTab extends ConsumerWidget {
  const ReferralsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SizedBox.shrink();

    final open = ref.watch(openReferralsProvider);
    final completion = ref.watch(referralCompletionProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(openReferralsProvider);
        ref.invalidate(referralCompletionProvider);
      },
      child: ListView(
        padding: const EdgeInsets.all(Gap.lg),
        children: [
          completion.when(
            loading: () => const SizedBox.shrink(),
            error: (e, _) => const SizedBox.shrink(),
            data: (c) => _CompletionCard(issued: c.issued, arrived: c.arrived, rate: c.rate),
          ),
          const SizedBox(height: Gap.lg),
          open.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(Gap.xl),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (e, _) => ErrorView(error: e),
            data: (list) {
              if (list.isEmpty) {
                return SectionCard(
                  title: 'No open referrals',
                  subtitle:
                      'When you issue a referral from an assessment it will '
                      'appear here, with the code, the urgency and the facility.',
                  icon: Icons.local_hospital_outlined,
                  child: const SizedBox.shrink(),
                );
              }
              final urgent = list
                  .where(
                    (r) =>
                        r.urgency == ReferralUrgency.immediate ||
                        r.urgency == ReferralUrgency.sameDay,
                  )
                  .toList(growable: false);
              final routine = list
                  .where(
                    (r) =>
                        r.urgency != ReferralUrgency.immediate &&
                        r.urgency != ReferralUrgency.sameDay,
                  )
                  .toList(growable: false);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (urgent.isNotEmpty) ...[
                    SectionCard(
                      title: 'Emergency Referral Tracing (Priority 1)',
                      subtitle:
                          'Immediate and same-day emergency referrals pending facility arrival confirmation. Critical to preventing maternal and neonatal transport delays.',
                      icon: Icons.crisis_alert_rounded,
                      accent: AppColors.triageRed,
                      child: Column(
                        children: [
                          for (final r in urgent) _ReferralTile(referral: r),
                        ],
                      ),
                    ),
                    const SizedBox(height: Gap.lg),
                  ],
                  if (routine.isNotEmpty) ...[
                    SectionCard(
                      title: 'Routine Clinical Referrals',
                      subtitle:
                          'Standard clinical referrals scheduled for specialized diagnostic follow-up or scheduled facility consultative visits.',
                      icon: Icons.local_hospital_outlined,
                      child: Column(
                        children: [
                          for (final r in routine) _ReferralTile(referral: r),
                        ],
                      ),
                    ),
                    const SizedBox(height: Gap.lg),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: Gap.xxl),
        ],
      ),
    );
  }
}

class _CompletionCard extends StatelessWidget {
  const _CompletionCard({
    required this.issued,
    required this.arrived,
    required this.rate,
  });

  final int issued;
  final int arrived;
  final double rate;

  @override
  Widget build(BuildContext context) {
    final colour = rate >= 0.7
        ? AppColors.triageGreen
        : rate >= 0.4
        ? AppColors.triageAmber
        : AppColors.triageRed;
    return SectionCard(
      title: 'Referral completion',
      subtitle:
          'Of the referrals you have issued in the last 90 days, how many '
          'have been confirmed as arrived at the facility.',
      icon: Icons.analytics_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colour.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(Gap.radiusSm),
                ),
                child: Text(
                  '${(rate * 100).round()}%',
                  style: TextStyle(
                    color: colour,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$arrived of $issued arrived',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      rate >= 0.7
                          ? 'Strong follow-through.'
                          : rate >= 0.4
                          ? 'Some families are not making it. Look at the '
                                'barriers section for the commonest reasons.'
                          : 'A large share are not arriving. The day plan '
                                'should favour these families.',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.inkMuted,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: rate.clamp(0, 1),
              minHeight: 8,
              backgroundColor: AppColors.canvas,
              valueColor: AlwaysStoppedAnimation(colour),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReferralTile extends ConsumerWidget {
  const _ReferralTile({required this.referral});
  final Referral referral;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final person = ref.watch(personProvider(referral.personId));
    final household = person.maybeWhen(
      data: (p) => p?.householdId,
      orElse: () => null,
    );

    final urgent = referral.urgency == ReferralUrgency.immediate ||
        referral.urgency == ReferralUrgency.sameDay;
    final overdue = referral.status != ReferralStatus.arrived &&
        referral.hoursOpen > (urgent ? 12 : 72);

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: Material(
        color: urgent ? AppColors.triageRedBg : AppColors.canvas,
        borderRadius: BorderRadius.circular(Gap.radiusSm),
        child: InkWell(
          borderRadius: BorderRadius.circular(Gap.radiusSm),
          onTap: household == null
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => HouseholdScreen(householdId: household),
                  ),
                ),
          child: Padding(
            padding: const EdgeInsets.all(Gap.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Gap.sm,
                        vertical: Gap.xs,
                      ),
                      decoration: BoxDecoration(
                        color: urgent
                            ? AppColors.triageRed
                            : AppColors.primary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        referral.referenceCode,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    const SizedBox(width: Gap.sm),
                    Expanded(
                      child: Text(
                        person.valueOrNull?.fullName ?? '…',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                        ),
                      ),
                    ),
                    if (overdue)
                      const Icon(
                        Icons.schedule_rounded,
                        size: 16,
                        color: AppColors.triageRed,
                      ),
                  ],
                ),
                const SizedBox(height: Gap.xs),
                Text(
                  referral.reason,
                  style: const TextStyle(fontSize: 13.5, height: 1.35),
                ),
                const SizedBox(height: Gap.xs),
                Wrap(
                  spacing: Gap.sm,
                  runSpacing: Gap.xs,
                  children: [
                    _MetaChip(
                      icon: Icons.local_hospital_rounded,
                      label: referral.facilityName,
                    ),
                    _MetaChip(
                      icon: Icons.timer_rounded,
                      label:
                          '${referral.urgency.label} · open ${referral.hoursOpen}h',
                      colour: urgent
                          ? AppColors.triageRed
                          : AppColors.inkMuted,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label, this.colour});
  final IconData icon;
  final String label;
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    final c = colour ?? AppColors.inkMuted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: c),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            color: c,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
