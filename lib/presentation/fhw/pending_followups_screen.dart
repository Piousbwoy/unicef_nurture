/// Pending follow-ups (Screen 74).
///
/// The literal answer to "Referred But No Follow-Through": a list of everyone
/// referred but not yet confirmed to have reached care. Tapping a row opens the
/// check-in screen that records what actually happened.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/visit.dart';
import '../../domain/enums.dart';
import '../shared/ui.dart';
import 'community_support_screen.dart';
import 'follow_up_check_in_screen.dart';

class PendingFollowUpsScreen extends ConsumerWidget {
  const PendingFollowUpsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final referrals = ref.watch(openReferralsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Pending follow-ups')),
      body: referrals.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(openReferralsProvider),
        ),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.check_circle_outline_rounded,
              title: 'No pending follow-ups',
              message:
                  'Every open referral has been accounted for, or there are no '
                  'referrals yet.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(openReferralsProvider),
            child: ListView.builder(
              padding: const EdgeInsets.all(Gap.lg),
              itemCount: list.length,
              itemBuilder: (_, i) => _FollowUpCard(
                referral: list[i],
                onTap: () async {
                  final changed = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => FollowUpCheckInScreen(
                        referral: list[i],
                      ),
                    ),
                  );
                  if (changed == true && context.mounted) {
                    ref.invalidate(openReferralsProvider);
                    ref.invalidate(dayPlanProvider);
                  }
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

extension _ReferralUrgencyTriage on ReferralUrgency {
  TriageLevel get triage => switch (this) {
    ReferralUrgency.immediate => TriageLevel.urgent,
    ReferralUrgency.sameDay => TriageLevel.priority,
    ReferralUrgency.withinTwoDays => TriageLevel.watch,
    ReferralUrgency.scheduled => TriageLevel.routine,
  };
}

class _FollowUpCard extends StatelessWidget {
  const _FollowUpCard({required this.referral, required this.onTap});

  final Referral referral;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = triageColours(referral.urgency.triage);

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Gap.radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(Gap.radius),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Gap.radius),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                      Icon(triageIcon(referral.urgency.triage), size: 16, color: c.fg),
                      const SizedBox(width: Gap.xs),
                      Text(
                        referral.urgency.label,
                        style: TextStyle(
                          color: c.fg,
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${referral.hoursOpen}h open',
                        style: TextStyle(
                          color: c.fg,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
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
                        referral.reason,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${referral.referenceCode} · ${referral.facilityName}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.inkMuted,
                        ),
                      ),
                      if (referral.clinicalSummary != null) ...[
                        const SizedBox(height: Gap.sm),
                        Text(
                          referral.clinicalSummary!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.caption.copyWith(height: 1.35),
                        ),
                      ],
                      const SizedBox(height: Gap.md),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => CommunitySupportScreen(
                                    referral: referral,
                                  ),
                                ),
                              ),
                              icon: const Icon(
                                Icons.people_outline_rounded,
                                size: 17,
                              ),
                              label: const Text('Loop in support'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
