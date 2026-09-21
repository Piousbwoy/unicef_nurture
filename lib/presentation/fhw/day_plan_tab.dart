/// Scheduled care reviews and record-based household priorities.
/// Opening a record or an assessment never completes a scheduled contact.
library;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/insight_repository.dart';
import '../../domain/entities/core.dart';
import '../../domain/entities/visit.dart';
import '../../domain/enums.dart';
import '../shared/ui.dart';
import '../shared/speakable_text.dart';
import 'clinic_widgets.dart';
import 'follow_up_check_in_screen.dart';
import 'home_tab.dart' show openVisit;
import 'household_screen.dart';

class DayPlanTab extends ConsumerWidget {
  const DayPlanTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ColoredBox(
    color: AppColors.surface,
    child: ref
        .watch(dayPlanProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorView(
            error: e,
            onRetry: () => ref.invalidate(dayPlanProvider),
          ),
          data: (plan) => RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(dayPlanProvider);
              await ref.read(dayPlanProvider.future);
            },
            child: _PlanBody(plan),
          ),
        ),
  );
}

class _PlanBody extends StatelessWidget {
  const _PlanBody(this.plan);
  final DayPlan plan;

  @override
  Widget build(BuildContext context) {
    final byHousehold = {for (final p in plan.priorities) p.household.id: p};
    final byPerson = {
      for (final p in plan.priorities)
        for (final member in p.members) member.id: p,
    };
    return ListView(
      key: const PageStorageKey('care-reviews-worklist'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(Gap.md),
      children: [
        ClinicCard(
          title: 'Care reviews',
          subtitle: 'Schedule for ${_date(context, plan.generatedAt)}',
          child: const NarrationSection(
            narrationKey: 'fhw:day-plan:intro',
            text: 'Review the saved purpose, then open the household or assess the '
                'patient. Opening a record does not mark a contact completed.',
            child: SpeakableText(
              'Review the saved purpose, then open the household or assess the '
              'patient. Opening a record does not mark a contact completed.',
              style: TextStyle(color: AppColors.inkMuted, height: 1.4),
            ),
          ),
        ),
        const SizedBox(height: Gap.md),
        const ClinicStatusLine(text: 'Based on records saved on this phone'),
        if (plan.chaseReferrals.isNotEmpty) ...[
          _SectionHeading(
            title: 'Urgent referral checks',
            count: plan.chaseReferrals.length,
            detail:
                'Arrival is not confirmed in the saved record. Check what '
                'happened; this does not mean the family did not attend.',
          ),
          for (final referral in plan.chaseReferrals)
            _ChaseTile(
              referral: referral,
              priority: byPerson[referral.personId],
            ),
        ],
        _SectionHeading(title: 'Overdue', count: plan.overdueContacts.length),
        for (final contact in plan.overdueContacts)
          _ContactTile(
            key: ValueKey('contact-${contact.id}'),
            contact: contact,
            priority: byHousehold[contact.householdId],
            overdue: true,
          ),
        _SectionHeading(title: 'Due today', count: plan.dueContacts.length),
        for (final contact in plan.dueContacts)
          _ContactTile(
            key: ValueKey('contact-${contact.id}'),
            contact: contact,
            priority: byHousehold[contact.householdId],
          ),
        if (plan.overdueContacts.isEmpty && plan.dueContacts.isEmpty)
          const ClinicCard(
            child: Text(
              'No care reviews scheduled on this phone',
              style: TextStyle(color: AppColors.ink, height: 1.4),
            ),
          ),
        if (plan.priorities.isNotEmpty) ...[
          _SectionHeading(
            title: 'Household priorities',
            count: plan.priorities.length,
            detail:
                'Ordered from saved records, not a current triage diagnosis. '
                'Confirm findings in a clinical assessment.',
          ),
          for (final priority in plan.priorities)
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.md),
              child: HouseholdPriorityCard(priority: priority),
            ),
        ],
        const SizedBox(height: Gap.lg),
      ],
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.title,
    required this.count,
    this.detail,
  });
  final String title;
  final int count;
  final String? detail;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Gap.lg, bottom: Gap.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            '$title ($count)',
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (detail != null) ...[
          const SizedBox(height: Gap.sm),
          SpeakableText(detail!, style: const TextStyle(color: AppColors.inkMuted)),
        ],
      ],
    ),
  );
}

class _ContactTile extends ConsumerWidget {
  const _ContactTile({
    super.key,
    required this.contact,
    this.priority,
    this.overdue = false,
  });

  final ScheduledContact contact;
  final HouseholdPriority? priority;
  final bool overdue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final household =
        priority?.household ??
        ref.watch(householdProvider(contact.householdId)).valueOrNull;
    final candidate =
        priority?.members.firstWhereOrNull((p) => p.id == contact.personId) ??
        ref.watch(personProvider(contact.personId)).valueOrNull;
    // Never attach a person from another household to this schedule row.
    final person = candidate?.householdId == contact.householdId
        ? candidate
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: ClinicCard(
        title: person?.fullName ?? 'Patient name unavailable',
        subtitle: household == null
            ? 'Household details unavailable'
            : '${household.name} · ${household.community}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(contact.purpose, style: const TextStyle(color: AppColors.ink)),
            const SizedBox(height: Gap.sm),
            Text(
              '${overdue ? 'Overdue' : 'Due today'} · ${_date(context, contact.dueDate)}',
              style: const TextStyle(
                color: AppColors.inkMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (contact.priority != TriageLevel.routine) ...[
              const SizedBox(height: Gap.sm),
              Text(
                'Priority when scheduled: ${contact.priority.name}. '
                'Not a current assessment.',
                style: const TextStyle(color: AppColors.inkMuted),
              ),
            ],
            if (household == null || person == null) ...[
              const SizedBox(height: Gap.sm),
              const Text(
                'Open the household to check the patient record before assessing.',
                style: TextStyle(color: AppColors.inkMuted),
              ),
            ],
            const SizedBox(height: Gap.md),
            _HouseholdActions(
              householdId: contact.householdId,
              household: person == null ? null : household,
            ),
          ],
        ),
      ),
    );
  }
}

/// A compact explanation of the existing ranking, not a new clinical verdict.
class HouseholdPriorityCard extends StatelessWidget {
  const HouseholdPriorityCard({super.key, required this.priority});
  final HouseholdPriority priority;

  @override
  Widget build(BuildContext context) => ClinicCard(
    title: priority.household.name,
    subtitle:
        '${priority.household.community} · ${priority.household.district}',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Saved-record reason',
          style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: Gap.sm),
        Text(
          priority.reason,
          style: const TextStyle(color: AppColors.inkMuted),
        ),
        const SizedBox(height: Gap.sm),
        Text(
          priority.daysSinceLastVisit == null
              ? 'No visit recorded on this phone'
              : 'Last recorded visit: ${priority.daysSinceLastVisit} days ago',
          style: const TextStyle(color: AppColors.inkMuted),
        ),
        const SizedBox(height: Gap.md),
        _HouseholdActions(
          householdId: priority.household.id,
          household: priority.household,
        ),
      ],
    ),
  );
}

class _HouseholdActions extends ConsumerStatefulWidget {
  const _HouseholdActions({required this.householdId, this.household});
  final String householdId;
  final Household? household;

  @override
  ConsumerState<_HouseholdActions> createState() => _HouseholdActionsState();
}

class _HouseholdActionsState extends ConsumerState<_HouseholdActions> {
  bool _opening = false;

  Future<void> _open({required bool assessment}) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      if (assessment && widget.household != null) {
        await openVisit(context, widget.household!);
      } else {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => HouseholdScreen(householdId: widget.householdId),
          ),
        );
      }
      if (mounted) ref.invalidate(dayPlanProvider);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canAssess =
        ref.watch(currentUserProvider)?.can(Permission.runClinicalAssessment) ??
        false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.household != null && canAssess) ...[
          FilledButton(
            onPressed: _opening ? null : () => _open(assessment: true),
            style: FilledButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.all(12),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Open assessment', textAlign: TextAlign.center),
          ),
          const SizedBox(height: Gap.sm),
        ],
        OutlinedButton(
          onPressed: _opening ? null : () => _open(assessment: false),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.all(12),
            foregroundColor: AppColors.primary,
          ),
          child: const Text('Open household', textAlign: TextAlign.center),
        ),
      ],
    );
  }
}

class _ChaseTile extends ConsumerWidget {
  const _ChaseTile({required this.referral, this.priority});
  final Referral referral;
  final HouseholdPriority? priority;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final person =
        priority?.members.firstWhereOrNull((p) => p.id == referral.personId) ??
        ref.watch(personProvider(referral.personId)).valueOrNull;
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: ClinicCard(
        title: person?.fullName ?? 'Patient name unavailable',
        subtitle: priority?.household.name,
        accent: AppColors.triageRed,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${referral.status.label} · Arrival unconfirmed',
              style: const TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: Gap.sm),
            Text(
              '${referral.referenceCode} · ${referral.facilityName}\n'
              'Issued ${_date(context, referral.issuedAt)} · ${referral.urgency.label}\n'
              'Referral reason: ${referral.reason}',
              style: const TextStyle(color: AppColors.inkMuted),
            ),
            const SizedBox(height: Gap.md),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.all(12),
                foregroundColor: AppColors.primary,
              ),
              onPressed: () async {
                final changed = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => FollowUpCheckInScreen(referral: referral),
                  ),
                );
                if (changed == true && context.mounted) {
                  ref.invalidate(dayPlanProvider);
                  ref.invalidate(openReferralsProvider);
                }
              },
              child: const Text(
                'Check referral status',
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _date(BuildContext context, DateTime date) =>
    MaterialLocalizations.of(context).formatMediumDate(date.toLocal());
