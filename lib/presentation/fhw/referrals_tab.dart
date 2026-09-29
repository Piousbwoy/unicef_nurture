/// The follow-up desk: what is still unknown, and what one tap can close.
///
/// This screen used to be a list of referrals sorted by how urgent they were
/// *when they were issued*. That is the wrong order for a chase. The right
/// question is not "which child was sickest three weeks ago" — it is "which of
/// these can I answer on the walk I am already doing today, and which still has
/// no answer at all".
///
/// So the desk has three buckets and one thread per case:
///
///   • **Awaiting answer** — nobody has recorded what happened. Households on
///     today's route come first, because an answer there costs a detour rather
///     than a day.
///   • **Answered — needs action** — someone went and asked, and the answer was
///     not "treated". This is where a family that queued from 6am and went home
///     untreated now survives. Under the old lifecycle they were `arrived`, and
///     `arrived` is not an open state, so they vanished from the list while the
///     child was still sick.
///   • **Closed** — care confirmed, or the case handed to a fresh referral.
///     Evidence, kept behind a count.
///
/// The grouping rule itself is not in this file. It is [buildFollowUpDesk],
/// which is pure and tested, so that a change to what the worker sees first is
/// a change to a rule somebody can argue with rather than a tweak to a widget.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/fhw_luxe.dart';
import '../../data/repositories/care_repository.dart';
import '../../domain/entities/core.dart';
import '../../domain/entities/visit.dart';
import '../../domain/enums.dart';
import '../../domain/services/follow_up_policy.dart';
import '../shared/ui.dart';
import '../visit/sbar_card.dart';
import 'clinic_widgets.dart';
import 'community_support_screen.dart';
import 'follow_up/follow_up_providers.dart';
import 'follow_up/trace_line.dart';
import 'follow_up_check_in_screen.dart';
import 'household_screen.dart';

/// An empty board, so the tab can render a header and an error together
/// without reaching through a provider it is not watching.
final _emptyBoard = FollowUpBoard(
  desk: buildFollowUpDesk(
    referrals: const [],
    ledger: const {},
    householdOf: const {},
    routeHouseholds: const {},
    now: DateTime(2026),
  ),
  people: const {},
  routeHouseholds: const {},
  chaseDueAt: const {},
  generatedAt: DateTime(2026),
);

class ReferralsTab extends ConsumerWidget {
  const ReferralsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => _Desk(ref: ref);
}

class _Desk extends ConsumerWidget {
  const _Desk({required this.ref});

  final WidgetRef ref;

  Future<void> _refresh() async {
    refreshFollowUpDesk(ref);
    await ref.read(followUpDeskProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SizedBox.shrink();
    final board = ref.watch(followUpDeskProvider);

    return ColoredBox(
      color: AppColors.surface,
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: board.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(Gap.md),
            children: [
              _DeskHero(board: _emptyBoard),
              const SizedBox(height: Gap.lg),
              ErrorView(error: error, onRetry: _refresh),
            ],
          ),
          data: (data) => _DeskBody(user: user, board: data),
        ),
      ),
    );
  }
}

class _DeskBody extends ConsumerWidget {
  const _DeskBody({required this.user, required this.board});

  final AppUser user;
  final FollowUpBoard board;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final desk = board.desk;
    return ListView(
      key: const PageStorageKey('follow-up-desk'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.md, Gap.xl),
      children: [
        _DeskHero(board: board),
        const SizedBox(height: Gap.lg),
        if (user.can(Permission.confirmReferralArrival)) ...[
          _StaffCodeAction(),
          const SizedBox(height: Gap.md),
        ],
        if (desk.isEmpty) ...[
          const _EmptyDesk(),
        ] else ...[
          _AwaitingSection(board: board),
          if (desk.needsAction.isNotEmpty)
            _NeedsActionSection(board: board),
          if (desk.settled.isNotEmpty) _ClosedSection(board: board),
        ],
        const SizedBox(height: Gap.md),
        const _HonestyFootnote(),
      ],
    );
  }
}

// ------------------------------------------------------------------- the hero

class _DeskHero extends StatelessWidget {
  const _DeskHero({required this.board});

  final FollowUpBoard board;

  @override
  Widget build(BuildContext context) {
    final desk = board.desk;
    return LuxeHeroHeader(
      eyebrow: 'Follow-up desk',
      title: desk.awaitingCount == 0 && desk.actionCount == 0
          ? 'Nothing waits on you'
          : 'Who is still waiting?',
      body:
          'Answered from what you saw. Arrival is not treatment, and no '
          'facility record reaches this phone.',
      icon: Icons.explore_outlined,
      stats: [
        LuxeStatPill(value: '${desk.awaitingCount}', label: 'no answer'),
        LuxeStatPill(value: '${desk.actionCount}', label: 'answered, not cared for'),
        LuxeStatPill(
          value: '${board.routeHouseholds.length}',
          label: 'households on today’s route',
        ),
      ],
    );
  }
}

/// Verified staff action, kept well away from the family-report path.
///
/// The distinction this button exists to protect: a mother saying "we went" and
/// a facility clerk signing a code are two different facts, and only one of
/// them can be checked afterwards.
class _StaffCodeAction extends StatelessWidget {
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    style: OutlinedButton.styleFrom(
      foregroundColor: FhwLuxePalette.sapphireRoyal,
      minimumSize: const Size.fromHeight(Gap.tapTarget),
      side: const BorderSide(color: FhwLuxePalette.hairLine),
    ),
    icon: const Icon(Icons.verified_user_outlined, size: 18),
    label: const Text('Confirm a code · verified staff action'),
    onPressed: () => showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _ConfirmArrivalDialog(),
    ),
  );
}

class _EmptyDesk extends StatelessWidget {
  const _EmptyDesk();

  @override
  Widget build(BuildContext context) => const ClinicCard(
    title: 'No referral has an open answer on this phone',
    child: Text(
      'This is not the same as every patient being cared for. Referrals '
      'issued on another device, and anything not recorded here, is not '
      'counted.',
      style: TextStyle(color: AppColors.ink, height: 1.45),
    ),
  );
}

class _HonestyFootnote extends StatelessWidget {
  const _HonestyFootnote();

  @override
  Widget build(BuildContext context) => const ClinicStatusLine(
    text: 'Sorted from records saved on this phone.',
    icon: Icons.info_outline_rounded,
  );
}

// ------------------------------------------------------------------- sections

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.count,
    required this.detail,
    required this.children,
    this.tone,
  });

  final String title;
  final int count;
  final String detail;
  final List<Widget> children;
  final Color? tone;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: Gap.md, bottom: Gap.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (tone != null)
              Padding(
                // A static dot, not the app's breathing one: this would pulse
                // on every section of a screen a worker stares at all morning.
                padding: const EdgeInsets.only(right: Gap.sm, top: 5),
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
                ),
              ),
            Expanded(
              child: Text(
                '$title · $count',
                style: AppType.title.copyWith(fontSize: 19),
              ),
            ),
          ],
        ),
      ),
      Text(
        detail,
        style: AppType.caption.copyWith(
          color: AppColors.inkMuted,
          height: 1.4,
        ),
      ),
      const SizedBox(height: Gap.md),
      ...children,
    ],
  );
}

class _LaneLabel extends StatelessWidget {
  const _LaneLabel({required this.text, required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Gap.sm, bottom: Gap.sm),
    child: Row(
      children: [
        Icon(icon, size: 14, color: AppColors.inkMuted),
        const SizedBox(width: Gap.sm),
        Expanded(
          child: Text(
            text,
            style: AppType.eyebrow.copyWith(
              color: AppColors.inkMuted,
              fontSize: 10.5,
            ),
          ),
        ),
      ],
    ),
  );
}

class _AwaitingSection extends StatelessWidget {
  const _AwaitingSection({required this.board});

  final FollowUpBoard board;

  @override
  Widget build(BuildContext context) {
    final cases = board.desk.awaitingAnswer;
    final onRoute = [
      for (final item in cases)
        if (item.onRoute) item,
    ];
    final offRoute = [
      for (final item in cases)
        if (!item.onRoute) item,
    ];
    // An empty column is not a column. A worker who has answered everything
    // should see the answers, not a headline reading zero.
    if (cases.isEmpty) return const SizedBox.shrink();
    return _Section(
      title: 'Awaiting answer',
      count: cases.length,
      detail:
          'No one has recorded what happened after these referrals. On-route '
          'households first — the cheapest answer is the one you can get '
          'walking past.',
      tone: FhwLuxePalette.clinicalAmber,
      children: [
        if (onRoute.isNotEmpty) ...[
          const _LaneLabel(
            text: 'ON YOUR ROUTE TODAY',
            icon: Icons.directions_walk_rounded,
          ),
          for (final item in onRoute) _CaseCard(board: board, item: item),
        ],
        if (offRoute.isNotEmpty) ...[
          const _LaneLabel(
            text: 'NO VISIT PLANNED SOON',
            icon: Icons.place_outlined,
          ),
          for (final item in offRoute) _CaseCard(board: board, item: item),
        ],
      ],
    );
  }
}

class _NeedsActionSection extends StatelessWidget {
  const _NeedsActionSection({required this.board});

  final FollowUpBoard board;

  @override
  Widget build(BuildContext context) {
    final cases = board.desk.needsAction;
    return _Section(
      title: 'Answered — not cared for',
      count: cases.length,
      detail:
          'Someone went and asked, and the answer was not treatment. These '
          'are the cases an arrival label used to hide.',
      tone: FhwLuxePalette.clinicalRed,
      children: [for (final item in cases) _CaseCard(board: board, item: item)],
    );
  }
}

class _ClosedSection extends StatelessWidget {
  const _ClosedSection({required this.board});

  final FollowUpBoard board;

  @override
  Widget build(BuildContext context) {
    final cases = board.desk.settled;
    return Padding(
      padding: const EdgeInsets.only(top: Gap.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Closed · ${cases.length}',
            style: AppType.title.copyWith(fontSize: 19),
          ),
          const SizedBox(height: Gap.xs),
          Text(
            'Care confirmed, or handed to a new referral. Tied threads.',
            style: AppType.caption.copyWith(color: AppColors.inkMuted),
          ),
          const SizedBox(height: Gap.sm),
          ExpansionTile(
            // ExpansionTile stores its open/closed state in PageStorage and
            // reads it back as a bool. Lazily built inside this scroll view, a
            // keyless tile can land in a neighbouring bucket and read the list
            // scroll offset (a double) as its own state, crashing on a cast in
            // initState. An isolated PageStorageKey keeps its state its own.
            key: const PageStorageKey<String>('closed-referrals-section'),
            tilePadding: EdgeInsets.zero,
            minTileHeight: Gap.tapTarget,
            shape: const Border(),
            title: Text(
              cases.length == 1 ? 'Show 1 closed case' : 'Show ${cases.length} closed cases',
            ),
            children: [
              for (final item in cases)
                Padding(
                  padding: const EdgeInsets.only(bottom: Gap.md),
                  child: _CaseCard(board: board, item: item),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------------- the card

class _CaseCard extends ConsumerWidget {
  const _CaseCard({required this.board, required this.item});

  final FollowUpBoard board;
  final FollowUpCase item;

  Future<void> _openCheckIn(BuildContext context, WidgetRef ref) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => FollowUpCheckInScreen(
          referral: item.referral,
          householdId: item.householdId,
        ),
      ),
    );
    if (saved == true) refreshFollowUpDesk(ref);
  }

  /// The whole point of the desk's second lane: the visit gets booked, in one
  /// tap, with no dialog standing between a worker and a decision they have
  /// already made.
  Future<void> _planVisit(BuildContext context, WidgetRef ref) async {
    final user = ref.read(currentUserProvider);
    final householdId = item.householdId;
    if (user == null || householdId == null) return;
    final due = _tomorrowMorning();
    try {
      await ref.read(careRepositoryProvider).planChaseVisit(
        user,
        ScheduledContact(
          id: const Uuid().v4(),
          personId: item.referral.personId,
          householdId: householdId,
          dueDate: due,
          purpose: 'Chase referral ${item.referral.referenceCode}',
          createdBy: user.id,
          referralId: item.referral.id,
          priority: item.referral.urgency == ReferralUrgency.immediate ||
                  item.referral.urgency == ReferralUrgency.sameDay
              ? TriageLevel.urgent
              : TriageLevel.routine,
        ),
      );
      if (!context.mounted) return;
      refreshFollowUpDesk(ref);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${item.referral.referenceCode} added to your route for '
            '${DateFormat('EEE d MMM').format(due)}. It will appear under '
            'Care reviews.',
          ),
        ),
      );
    } on AccessDenied catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save the visit. Nothing was scheduled.'),
        ),
      );
    }
  }

  static DateTime _tomorrowMorning() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day + 1, 9);
  }

  /// The one action, decided by the policy rather than by this widget — except
  /// that a booked chase turns "go and look" into "you already are going".
  String get _actionLabel => switch (item.nextStep) {
    FollowUpNextStep.answerNow => 'Answer it at this visit',
    FollowUpNextStep.reviewAnswer => 'Record what changed',
    FollowUpNextStep.bringOnRoute => chaseDue == null
        ? 'Put this household on a route'
        : 'Answer it now — visit already booked',
    FollowUpNextStep.none => 'Closed',
  };

  bool get _plans =>
      item.nextStep == FollowUpNextStep.bringOnRoute &&
      chaseDue == null &&
      item.householdId != null;

  /// When a visit is already booked to chase this referral, if it is.
  DateTime? get chaseDue => board.chaseDue(item);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final person = board.personOf(item);
    final reading = TraceReading.of(item);
    final booked = chaseDue;
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Gap.radiusLg),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: FhwLuxePalette.cardSurface,
            boxShadow: [AppShadows.card],
          ),
          // IntrinsicHeight is what lets the spine run the full card: the Row
          // stretches its children, and inside a scroll view it is given an
          // unbounded height to stretch against.
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Spine(reading: reading, item: item),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Gap.md,
                      Gap.md,
                      Gap.md,
                      Gap.sm,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _Headline(item: item, person: person),
                        const SizedBox(height: Gap.xs),
                        Text(
                          item.referral.facilityName,
                          style: AppType.caption.copyWith(
                            color: AppColors.inkMuted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: Gap.md),
                        _Reason(item: item),
                        if (item.blockers.isNotEmpty) ...[
                          const SizedBox(height: Gap.sm),
                          _Blockers(item: item),
                        ],
                        if (item.attempts > 0 && !item.isClosed) ...[
                          const SizedBox(height: Gap.sm),
                          ClinicStatusLine(
                            text:
                                '${item.attempts} unanswered '
                                '${item.attempts == 1 ? 'visit' : 'visits'}'
                                '${item.isTraced ? ' · trace started' : ''}',
                            icon: Icons.doorbell_outlined,
                          ),
                        ],
                        if (booked != null && !item.isClosed) ...[
                          const SizedBox(height: Gap.sm),
                          ClinicStatusLine(
                            text:
                                'Visit booked ${DateFormat('EEE d MMM').format(booked)}'
                                ' · nothing answered yet',
                            icon: Icons.event_available_outlined,
                          ),
                        ],
                        const SizedBox(height: Gap.md),
                        _Action(
                          label: _actionLabel,
                          hint: item.isClosed
                              ? _closedHint(item)
                              : item.nextStep.hint,
                          dark: !item.isClosed,
                          onTap: item.isClosed
                              ? () => _openCheckIn(context, ref)
                              : _plans
                              ? () => _planVisit(context, ref)
                              : () => _openCheckIn(context, ref),
                        ),
                        const SizedBox(height: Gap.sm),
                        _Secondary(item: item, person: person),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _closedHint(FollowUpCase item) => item.handedOver
      ? 'Handed to a new referral raised from this answer.'
      : item.referral.status == ReferralStatus.treated
      ? 'Care confirmed. Nothing to chase.'
      : item.referral.status == ReferralStatus.died
      ? 'The patient died. This case is closed.'
      : '${item.referral.status.label}. No care was confirmed.';
}

class _Headline extends StatelessWidget {
  const _Headline({required this.item, required this.person});

  final FollowUpCase item;
  final Person? person;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Text(
          person?.fullName ?? 'Name not on this phone',
          style: AppType.title.copyWith(
            fontSize: 17.5,
            color: FhwLuxePalette.textPrimary,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      const SizedBox(width: Gap.sm),
      _Urgency(urgency: item.referral.urgency),
    ],
  );
}

class _Urgency extends StatelessWidget {
  const _Urgency({required this.urgency});

  final ReferralUrgency urgency;

  @override
  Widget build(BuildContext context) {
    final (Color ink, Color halo) = switch (urgency) {
      ReferralUrgency.immediate => (
        FhwLuxePalette.clinicalRed,
        FhwLuxePalette.clinicalRedHalo,
      ),
      ReferralUrgency.sameDay => (
        FhwLuxePalette.clinicalAmber,
        FhwLuxePalette.clinicalAmberHalo,
      ),
      _ => (FhwLuxePalette.textSecondary, FhwLuxePalette.pearlSurface),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 3),
      decoration: BoxDecoration(
        color: halo,
        borderRadius: BorderRadius.circular(Gap.radiusSm),
      ),
      child: Text(
        urgency.label,
        style: AppType.label.copyWith(color: ink, fontSize: 11),
      ),
    );
  }
}

class _Reason extends StatelessWidget {
  const _Reason({required this.item});

  final FollowUpCase item;

  @override
  Widget build(BuildContext context) => Text(
    item.referral.reason,
    style: AppType.body.copyWith(
      color: FhwLuxePalette.textSecondary,
      height: 1.45,
    ),
    maxLines: 3,
    overflow: TextOverflow.ellipsis,
  );
}

/// Why care did not happen, as chips — because the barrier is the finding.
class _Blockers extends StatelessWidget {
  const _Blockers({required this.item});

  final FollowUpCase item;

  @override
  Widget build(BuildContext context) {
    final blockers = item.blockers.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    return Wrap(
      spacing: Gap.xs + 2,
      runSpacing: Gap.xs,
      children: [
        for (final barrier in blockers.take(3))
          Container(
            padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 3),
            decoration: BoxDecoration(
              color: FhwLuxePalette.pearlSurface,
              borderRadius: BorderRadius.circular(Gap.radiusSm),
              border: Border.all(color: FhwLuxePalette.hairLine),
            ),
            child: Text(
              barrier.label,
              style: AppType.caption.copyWith(
                color: FhwLuxePalette.textPrimary,
                fontSize: 11.5,
              ),
            ),
          ),
        if (blockers.length > 3)
          Padding(
            padding: const EdgeInsets.only(left: Gap.xs),
            child: Text(
              '+${blockers.length - 3} more',
              style: AppType.caption.copyWith(color: AppColors.inkMuted),
            ),
          ),
      ],
    );
  }
}

/// The primary control. Full width, states the outcome in its own label, and
/// never sits there disabled.
class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.hint,
    required this.dark,
    required this.onTap,
  });

  final String label;
  final String hint;
  final bool dark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = dark ? Colors.white : FhwLuxePalette.textPrimary;
    return PressScale(
      onTap: onTap,
      radius: BorderRadius.circular(Gap.radius),
      child: Container(
        constraints: const BoxConstraints(minHeight: Gap.tapTarget),
        padding: const EdgeInsets.symmetric(
          horizontal: Gap.md,
          vertical: Gap.sm + 2,
        ),
        decoration: BoxDecoration(
          gradient: dark ? FhwLuxePalette.sapphireHeroGradient : null,
          color: dark ? null : FhwLuxePalette.pearlSurface,
          borderRadius: BorderRadius.circular(Gap.radius),
          border: Border.all(
            color: dark ? Colors.transparent : FhwLuxePalette.hairLine,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: AppType.label.copyWith(
                      color: foreground,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (hint.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      hint,
                      style: AppType.caption.copyWith(
                        color: dark
                            ? Colors.white.withValues(alpha: 0.82)
                            : AppColors.inkMuted,
                        fontSize: 11.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: Gap.sm),
            Icon(
              dark ? Icons.arrow_forward_rounded : Icons.chevron_right_rounded,
              size: 20,
              color: foreground,
            ),
          ],
        ),
      ),
    );
  }
}

/// Everything that is not the answer, in one quiet row plus a disclosure.
class _Secondary extends ConsumerWidget {
  const _Secondary({required this.item, required this.person});

  final FollowUpCase item;
  final Person? person;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phone = person?.phone;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Natural width, wrapping when the screen is narrow. Three equal
        // slices of a small phone leave 'SBAR' with nowhere to go.
        Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          children: [
            _MiniAction(
              icon: Icons.call_outlined,
              label: 'Call',
              onTap: phone == null || phone.trim().isEmpty
                  ? null
                  : () => _call(context, phone),
            ),
            _MiniAction(
              icon: Icons.description_outlined,
              label: 'SBAR',
              onTap: () => showSbarSheet(
                context,
                SbarCard.fromReferral(item.referral, person),
              ),
            ),
            _MiniAction(
              icon: Icons.volunteer_activism_outlined,
              label: 'Support',
              onTap: () async {
                final changed = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) =>
                        CommunitySupportScreen(referral: item.referral),
                  ),
                );
                if (changed == true && context.mounted) {
                  refreshFollowUpDesk(ref);
                }
              },
            ),
          ],
        ),
        if (phone == null || phone.trim().isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Gap.xs),
            child: Text(
              'No family phone number on record.',
              style: AppType.caption.copyWith(color: AppColors.inkMuted),
            ),
          ),
        _Disclosure(
          label: 'Case detail',
          child: _Detail(item: item, person: person),
        ),
      ],
    );
  }

  /// Launches the dialler and nothing else. No contact, no attempt, no outcome.
  Future<void> _call(BuildContext context, String number) async {
    final clean = number.replaceAll(RegExp(r'[^0-9+]'), '');
    try {
      if (clean.isNotEmpty &&
          await launchUrl(
            Uri(scheme: 'tel', path: clean),
            mode: LaunchMode.externalApplication,
          )) {
        return;
      }
    } catch (_) {
      // One actionable message for an unavailable dialler and for a failure.
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not open the dialler. Dial $number directly when telephone '
            'service is available.',
          ),
        ),
      );
    }
  }
}

class _MiniAction extends StatelessWidget {
  const _MiniAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final ink = enabled
        ? FhwLuxePalette.sapphireRoyal
        : FhwLuxePalette.textFaint;
    return SizedBox(
      height: 44,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
          side: BorderSide(
            color: enabled
                ? FhwLuxePalette.hairLine
                : FhwLuxePalette.pearlSurface,
          ),
        ),
        // Absent rather than greyed: a phone call that cannot be made is not
        // an action waiting to be unlocked.
        onPressed: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: Gap.xs + 2),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.label.copyWith(fontSize: 12.5, color: ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The evidence, behind one line. A disclosure rather than a page: the worker
/// is on a walk, and the answer they came for is already on the card.
///
/// Deliberately not an `ExpansionTile` — that stores its open state in
/// `PageStorage`, which a scrollable has already filled with its own offset.
class _Disclosure extends StatefulWidget {
  const _Disclosure({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  State<_Disclosure> createState() => _DisclosureState();
}

class _DisclosureState extends State<_Disclosure> {
  bool _open = false;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      PressScale(
        onTap: () => setState(() => _open = !_open),
        child: Semantics(
          expanded: _open,
          button: true,
          child: Container(
            constraints: const BoxConstraints(minHeight: Gap.tapTarget - 8),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.label,
                    style: AppType.label.copyWith(color: AppColors.inkMuted),
                  ),
                ),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: kThemeAnimationDuration,
                  child: Icon(
                    Icons.expand_more_rounded,
                    size: 21,
                    color: AppColors.inkMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      AnimatedSize(
        duration: kThemeAnimationDuration,
        alignment: Alignment.topCenter,
        child: _open
            ? Padding(
                padding: const EdgeInsets.only(top: Gap.xs),
                child: widget.child,
              )
            : const SizedBox(width: double.infinity),
      ),
    ],
  );
}

class _Detail extends StatelessWidget {
  const _Detail({required this.item, required this.person});

  final FollowUpCase item;
  final Person? person;

  @override
  Widget build(BuildContext context) {
    final referral = item.referral;
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            'Referral code: ${referral.referenceCode}',
            style: AppType.body.copyWith(fontSize: 14.5),
          ),
          const SizedBox(height: Gap.xs),
          Text(
            'Issued ${_stamp(referral.issuedAt)}'
            '${item.isChained ? ' · raised by an earlier referral' : ''}',
            style: AppType.caption,
          ),
          if (referral.arrivalConfirmedBy != null) ...[
            const SizedBox(height: Gap.xs),
            Text(
              'Arrival confirmed by staff on ${_stamp(referral.statusUpdatedAt)}.',
              style: AppType.caption,
            ),
          ],
          if (referral.clinicalSummary?.isNotEmpty ?? false) ...[
            const SizedBox(height: Gap.sm),
            Text(referral.clinicalSummary!, style: AppType.body),
          ],
          if (referral.outcomeNotes?.isNotEmpty ?? false) ...[
            const SizedBox(height: Gap.sm),
            Text(
              'Recorded notes',
              style: AppType.eyebrow.copyWith(fontSize: 10.5),
            ),
            const SizedBox(height: Gap.xs),
            Text(referral.outcomeNotes!, style: AppType.body),
          ],
          if (item.trace.isNotEmpty) ...[
            const SizedBox(height: Gap.sm),
            Text(
              'What was found',
              style: AppType.eyebrow.copyWith(fontSize: 10.5),
            ),
            for (final contact in item.trace.reversed)
              Padding(
                padding: const EdgeInsets.only(top: Gap.xs),
                child: Text(
                  '${_stamp(contact.at)} · ${_found(contact)}'
                  '${contact.note == null ? '' : ' — ${contact.note}'}',
                  style: AppType.caption.copyWith(height: 1.4),
                ),
              ),
          ],
          const SizedBox(height: Gap.sm),
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(Gap.tapTarget, Gap.tapTarget),
              foregroundColor: FhwLuxePalette.sapphireRoyal,
            ),
            onPressed: person == null
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          HouseholdScreen(householdId: person!.householdId),
                    ),
                  ),
            child: const Text('Open household record'),
          ),
        ],
      ),
    );
  }

  static String _found(FollowUpContact contact) {
    if (!contact.isAnswered) return 'nobody reached';
    if (contact.condition == FollowUpCondition.died) return 'the patient died';
    final went = switch (contact.reached) {
      FollowUpReach.went => 'went',
      FollowUpReach.declined => 'declined',
      _ => 'did not go',
    };
    final care = switch (contact.care) {
      FollowUpCare.seenTreated => ', treated',
      FollowUpCare.seenWaiting => ', still waiting',
      FollowUpCare.none => ', no care',
      FollowUpCare.unknown => '',
    };
    return '$went$care · ${contact.condition.label.toLowerCase()}';
  }

  static String _stamp(DateTime? at) => at == null
      ? 'no record'
      : DateFormat('d MMM, HH:mm').format(at.toLocal());
}

// -------------------------------------------------------------------- the spine

/// The thread panel: the case's whole chase history in 34 logical pixels.
///
/// Fixed width and fixed height on purpose. Everything that varies — the age,
/// the number of visits — is inside the thread, so no amount of text scaling
/// in the body can move it or push the card apart.
class _Spine extends StatelessWidget {
  const _Spine({required this.reading, required this.item});

  final TraceReading reading;
  final FollowUpCase item;

  @override
  Widget build(BuildContext context) {
    final alert = item.isOverdue;
    return Container(
      width: kTraceGutter + 10,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: alert
              ? const [
                  FhwLuxePalette.clinicalRed,
                  FhwLuxePalette.sapphireMidnight,
                ]
              : const [
                  FhwLuxePalette.sapphireMidnight,
                  FhwLuxePalette.sapphireDeep,
                ],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          SizedBox(
            height: 76,
            child: Center(
              child: TraceLine(reading: reading, height: 72),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.sm),
            child: Column(
              children: [
                Text(
                  _age(item),
                  style: AppType.label.copyWith(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: 11,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  'open',
                  style: AppType.caption.copyWith(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 9,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// How long the family has been waiting, in the unit a worker thinks in.
  static String _age(FollowUpCase item) {
    final days = item.age.inDays;
    if (days >= 1) return '${days}d';
    final hours = item.age.inHours;
    if (hours >= 1) return '${hours}h';
    return '<1h';
  }
}

// --------------------------------------------------------- staff code dialog

class _ConfirmArrivalDialog extends ConsumerStatefulWidget {
  const _ConfirmArrivalDialog();

  @override
  ConsumerState<_ConfirmArrivalDialog> createState() =>
      _ConfirmArrivalDialogState();
}

class _ConfirmArrivalDialogState extends ConsumerState<_ConfirmArrivalDialog> {
  final _code = TextEditingController();
  final _note = TextEditingController();
  bool _verified = false;
  bool _busy = false;
  String? _error;

  /// What the facility did, as witnessed by the verifier. Arrival is the
  /// default so the flow still reads as "confirm a code" for the common case;
  /// treatment and death are the stronger claims that make this more than a
  /// footfall log.
  ReferralStatus _outcome = ReferralStatus.arrived;

  static const _outcomeOptions = <(ReferralStatus, String)>[
    (ReferralStatus.arrived, 'Arrived, awaiting care'),
    (ReferralStatus.treated, 'Seen and treated'),
    (ReferralStatus.died, 'Patient died'),
  ];

  @override
  void dispose() {
    _code.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final user = ref.read(currentUserProvider);
    if (_busy || !_verified || user == null) return;
    final code = _code.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Enter the referral code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final arrivalOnly = _outcome == ReferralStatus.arrived;
    final note = _note.text.trim();
    try {
      final repository = ref.read(careRepositoryProvider);
      final referral = arrivalOnly
          ? await repository.confirmArrival(user, code)
          : await repository.confirmReferralOutcome(
              user,
              code,
              outcome: _outcome,
              outcomeNotes: note.isEmpty ? null : note,
            );
      if (!mounted) return;
      if (referral == null) {
        setState(() {
          _busy = false;
          _error = arrivalOnly
              ? 'Code not found. Check the code and retry.'
              : 'Code not found, or this case is already closed.';
        });
        return;
      }
      refreshFollowUpDesk(ref);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            arrivalOnly
                ? 'Staff-confirmed arrival saved locally. This does not '
                      'confirm treatment.'
                : 'Facility outcome recorded, verified by you. Saved locally.',
          ),
        ),
      );
      setState(() => _busy = false);
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not save confirmation. Check and retry.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      backgroundColor: Colors.white,
      scrollable: true,
      title: const Text('Confirm arrival code'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Verified staff action only. For a family report, answer the '
            'case from the desk. Choose what the facility did; the outcome '
            'needs a code that matches an open case.',
          ),
          const SizedBox(height: Gap.md),
          TextField(
            controller: _code,
            enabled: !_busy,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Referral code'),
          ),
          const SizedBox(height: Gap.md),
          const Text('What did the facility do?'),
          const SizedBox(height: Gap.sm),
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            children: [
              for (final option in _outcomeOptions)
                ChoiceChip(
                  label: Text(option.$2),
                  selected: _outcome == option.$1,
                  onSelected: _busy
                      ? null
                      : (_) => setState(() => _outcome = option.$1),
                ),
            ],
          ),
          if (_outcome != ReferralStatus.arrived) ...[
            const SizedBox(height: Gap.md),
            TextField(
              controller: _note,
              enabled: !_busy,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                helperText: 'Who confirmed it, or what was seen.',
              ),
            ),
          ],
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text(
              'I have verified arrival with facility staff or in person.',
            ),
            value: _verified,
            onChanged: _busy
                ? null
                : (value) => setState(() => _verified = value ?? false),
          ),
          if (_error != null) Semantics(liveRegion: true, child: Text(_error!)),
        ],
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(
            minimumSize: const Size(Gap.tapTarget, Gap.tapTarget),
          ),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: FhwLuxePalette.sapphireRoyal,
            foregroundColor: Colors.white,
            minimumSize: const Size(Gap.tapTarget, Gap.tapTarget),
          ),
          // The only disabled primary on this screen, and the only one whose
          // reason is a lie someone could tell: an unverified code.
          onPressed: _busy || !_verified ? null : _confirm,
          child: Text(
            _busy
                ? 'Saving…'
                : _outcome == ReferralStatus.arrived
                ? 'Confirm arrival'
                : 'Save facility outcome',
          ),
        ),
      ],
    ),
  );
}
