/// The clinic intake flow — a household arrives, one session for everyone.
///
/// The dominant reality at a CHPS compound in Northern Ghana is that the
/// family comes to the health worker, not the other way around — and they
/// rarely come alone. A mother walks in with a newborn on her back, a
/// two-year-old holding her wrapper, and the grandmother who walked with
/// her. This screen owns that path, end to end:
///
///   1. **Pick or create a household.** Most arrivals are from a household
///      the CHO has seen before; a search box finds it. The remainder are a
///      new household — a referral letter, a community volunteer reporting a
///      new family — and a single button registers it.
///   2. **Mark who came today.** Everyone registered in the household is
///      listed; the CHO unticks anyone who stayed home and can register
///      anyone new on the spot (delegating to [MemberFormScreen], which
///      knows the five genuinely different forms a person can take: mother,
///      postpartum, WRA, newborn, child-under-five).
///   3. **Assess everyone who came.** One session is opened for the whole
///      group: barriers check → [RollCallScreen] resumes the open session
///      and queues every person for assessment in clinical order, then the
///      household sign-off. One session, any number of people — a mother
///      arriving with three children is one encounter, not four restarts.
///
/// Every step has a back button. A CHO who picks the wrong household does
/// not lose the family; a CHO who picked the wrong form can rewind it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/local/visit_dao.dart';
import '../../data/repositories/care_repository.dart';
import '../../domain/entities/core.dart';
import '../../domain/entities/visit.dart';
import '../../domain/enums.dart';
import '../fhw/families_tab.dart';
import '../registration/member_form_screen.dart';
import '../shared/ui.dart';
import '../visit/barrier_check_screen.dart';
import '../visit/roll_call_screen.dart';

const _uuid = Uuid();

class PatientIntakeScreen extends ConsumerStatefulWidget {
  const PatientIntakeScreen({super.key, this.knownHouseholds = const []});

  /// Pre-loaded list of households the CHO can see. The intake screen
  /// re-fetches under the standard provider so the picker is always live,
  /// but the constructor parameter is what the home tab already had in
  /// memory when the CTA was tapped.
  final List<Household> knownHouseholds;

  @override
  ConsumerState<PatientIntakeScreen> createState() =>
      _PatientIntakeScreenState();
}

class _PatientIntakeScreenState extends ConsumerState<PatientIntakeScreen> {
  /// Which step of the flow we are on. Step 1 picks the household; step 2
  /// marks who came and why; step 3 is the assessment session running on
  /// top of this screen (barriers → queue → sign-off).
  int _step = 1;

  Household? _household;

  /// Reasons the family came, and who is standing here. Both live on the
  /// parent state so navigating between steps never loses them.
  final Set<VisitReason> _reasons = {};
  final Map<String, bool> _present = {};

  bool _busy = false;
  String? _error;

  /// Lets the step widgets below rebuild this screen.
  void update(VoidCallback change) => setState(change);

  /// Drives the section-card sub-titles. "Step 1 of 3" is more honest than
  /// "step 1" because the user can see how much is left.
  static const _steps = 3;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clinic intake'),
        leading: IconButton(
          // The AppBar default back button would pop the whole flow; we
          // want a step-aware back that walks *inside* the flow.
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: _step == 1 ? 'Back' : 'Back to step ${_step - 1}',
          onPressed: _busy ? null : _onBack,
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(36),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Gap.lg,
              0,
              Gap.lg,
              Gap.sm,
            ),
            child: _StepIndicator(step: _step, total: _steps),
          ),
        ),
      ),
      body: switch (_step) {
        1 => _PickHouseholdStep(
            known: widget.knownHouseholds,
            picked: _household,
            onPicked: (h) => setState(() {
              _household = h;
              _error = null;
              _step = 2;
            }),
          ),
        2 => _WhoCameStep(this),
        _ => const _SessionRunningPlaceholder(),
      },
    );
  }

  void _onBack() {
    if (_step <= 1) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _step -= 1;
      _error = null;
    });
  }

  /// Opens one session for everyone who came. The visit + participants are
  /// written here; the barriers check and the assessment queue then run on
  /// top, exactly like the household-screen entry point. [RollCallScreen]
  /// resumes the open session and lands straight in the queue.
  Future<void> _startSession(List<Person> people) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final householdId = _household!.id;

    if (_reasons.isEmpty) {
      setState(
        () => _error =
            'Pick at least one reason the family came. It is what the '
            'follow-up schedule and the monthly report are built from.',
      );
      return;
    }

    final present = people
        .where((p) => _present[p.id] ?? true)
        .toList(growable: false);
    if (present.isEmpty) {
      setState(
        () => _error =
            'Nobody is marked as came. Tick the people standing in front of '
            'you, or register them if they are not on the list yet.',
      );
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final visit = Visit(
      id: _uuid.v4(),
      householdId: householdId,
      conductedBy: user.id,
      startedAt: DateTime.now(),
      reasons: _reasons.toList(growable: false),
    );

    // Queue order is the clinical order the member list already arrived in:
    // mother, then newborns, then under-fives. Everyone registered is on the
    // roll — absent members included — so a child who stayed home becomes a
    // follow-up target instead of silently disappearing.
    final roll = <VisitParticipant>[
      for (final (i, p) in people.indexed)
        VisitParticipant(
          visitId: visit.id,
          personId: p.id,
          wasPresent: _present[p.id] ?? true,
          queueOrder: i,
        ),
    ];

    try {
      await ref.read(careRepositoryProvider).startVisit(user, visit, roll);
    } on AccessDenied catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
      return;
    }

    if (!mounted) return;
    ref.invalidate(visibleHouseholdsProvider);
    ref.invalidate(householdMembersProvider(householdId));
    ref.invalidate(dayPlanProvider);

    setState(() {
      _busy = false;
      _step = 3;
    });

    // Barriers first — same pattern as the household entry point. Skipping
    // is allowed and never blocks care; the result is intentionally ignored.
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BarrierCheckScreen(householdId: householdId),
      ),
    );
    if (!mounted) return;

    // The session is open, so the roll call resumes it and lands directly in
    // the assessment queue: one Assess button per person, clinical order,
    // then the household sign-off.
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RollCallScreen(householdId: householdId),
      ),
    );
    if (!mounted) return;

    // Session signed off (or abandoned — the open session stays resumable
    // from the Assess tab either way). Return the household id so the home
    // tab knows the intake ran to the end.
    Navigator.of(context).pop(householdId);
  }
}

// ----------------------------------------------------------------- Step 1: pick

/// "Which household does this family belong to?" A search box for the known
/// list and a single button for the new-household case, because the
/// new-household case is the rarer one and should not occupy equal weight in
/// the layout.
class _PickHouseholdStep extends ConsumerStatefulWidget {
  const _PickHouseholdStep({
    required this.known,
    required this.picked,
    required this.onPicked,
  });

  final List<Household> known;
  final Household? picked;
  final ValueChanged<Household> onPicked;

  @override
  ConsumerState<_PickHouseholdStep> createState() =>
      _PickHouseholdStepState();
}

class _PickHouseholdStepState extends ConsumerState<_PickHouseholdStep> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    // Always re-read the visible list so a freshly-registered household
    // shows up here without a manual refresh. The `known` argument is the
    // home tab's snapshot; the provider is the source of truth.
    final async = ref.watch(visibleHouseholdsProvider);
    final list = async.maybeWhen(
      data: (l) => l,
      orElse: () => widget.known,
    );
    final q = _q.trim().toLowerCase();
    final filtered = q.isEmpty
        ? list
        : list.where((h) {
            return h.name.toLowerCase().contains(q) ||
                h.community.toLowerCase().contains(q) ||
                (h.headName?.toLowerCase().contains(q) ?? false);
          }).toList(growable: false);

    return ListView(
      padding: const EdgeInsets.all(Gap.lg),
      children: [
        SectionCard(
          title: 'Which household does this family belong to?',
          subtitle:
              'Pick a household you already know, or register a new one for '
              'a family you have not seen before.',
          icon: Icons.home_work_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                onChanged: (v) => setState(() => _q = v),
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search_rounded, size: 19),
                  hintText: 'Search by household name, community or head',
                ),
              ),
              const SizedBox(height: Gap.md),
              if (filtered.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: Gap.md),
                  child: Text(
                    'No matching household. Register a new one below.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.inkMuted,
                    ),
                  ),
                )
              else
                for (final h in filtered)
                  _HouseholdTile(
                    household: h,
                    selected: widget.picked?.id == h.id,
                    onTap: () => widget.onPicked(h),
                  ),
              const SizedBox(height: Gap.md),
              const Divider(height: 1),
              const SizedBox(height: Gap.md),
              OutlinedButton.icon(
                onPressed: () async {
                  final created =
                      await showModalBottomSheet<bool>(
                    context: context,
                    isScrollControlled: true,
                    showDragHandle: true,
                    builder: (_) => const HouseholdFormSheet(),
                  );
                  if (created == true) {
                    ref.invalidate(visibleHouseholdsProvider);
                  }
                },
                icon: const Icon(Icons.add_home_rounded),
                label: const Text('Register a new household'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HouseholdTile extends StatelessWidget {
  const _HouseholdTile({
    required this.household,
    required this.onTap,
    this.selected = false,
  });
  final Household household;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: Material(
        color: selected ? AppColors.primaryLight : AppColors.canvas,
        borderRadius: BorderRadius.circular(Gap.radiusSm),
        child: InkWell(
          borderRadius: BorderRadius.circular(Gap.radiusSm),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(Gap.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Gap.radiusSm),
              border: Border.all(
                color: selected ? AppColors.accent : AppColors.line,
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.home_outlined,
                  size: 19,
                  color: AppColors.inkMuted,
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        household.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                        ),
                      ),
                      Text(
                        '${household.community} · ${household.district}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.inkFaint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- Step 2: who came

/// "Who came today?" Everyone registered in the household, ticked present by
/// default, with a repeatable register-a-member button for anyone new and
/// the reason chips for the encounter. Continue opens one session for the
/// whole group.
class _WhoCameStep extends ConsumerWidget {
  const _WhoCameStep(this.state);

  final _PatientIntakeScreenState state;

  Future<void> _addMember(BuildContext context) async {
    final h = state._household;
    if (h == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MemberFormScreen(household: h)),
    );
    state.ref.invalidate(householdMembersProvider(h.id));
    state.ref.invalidate(householdScoreProvider(h.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final household = state._household!;
    final members = ref.watch(householdMembersProvider(household.id));

    return members.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(
        error: e is AccessDenied ? e.message : e,
      ),
      data: (people) {
        final came = people
            .where((p) => state._present[p.id] ?? true)
            .length;

        return Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(Gap.lg),
                children: [
                  if (state._error != null) ...[
                    _Error(state._error!),
                    const SizedBox(height: Gap.lg),
                  ],

                  SectionCard(
                    title: 'Why did the family come?',
                    subtitle:
                        'More than one is normal. A mother who came about a '
                        'fever often leaves with her child weighed and her '
                        'own postnatal check done.',
                    icon: Icons.flag_outlined,
                    child: Wrap(
                      spacing: Gap.sm,
                      runSpacing: Gap.sm,
                      children: [
                        for (final r in VisitReason.values)
                          FilterChip(
                            label: Text(r.label),
                            selected: state._reasons.contains(r),
                            onSelected: (on) => state.update(() {
                              if (on) {
                                state._reasons.add(r);
                              } else {
                                state._reasons.remove(r);
                              }
                            }),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Gap.lg),

                  SectionCard(
                    title: 'Who came today?',
                    subtitle:
                        'Everyone registered in this household. Untick '
                        'anybody who stayed home — they become a follow-up, '
                        'not a blank row.',
                    icon: Icons.how_to_reg_outlined,
                    child: people.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: Gap.sm),
                            child: Text(
                              'Nobody is registered in this household yet. '
                              'Register the people who came below.',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.inkMuted,
                                height: 1.4,
                              ),
                            ),
                          )
                        : Column(
                            children: [
                              for (final p in people)
                                _CameTile(state: state, person: p),
                            ],
                          ),
                  ),
                  const SizedBox(height: Gap.lg),

                  OutlinedButton.icon(
                    onPressed: () => _addMember(context),
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: const Text('Register a new family member'),
                  ),
                  const SizedBox(height: Gap.xxl),
                ],
              ),
            ),
            SafeArea(
              minimum: const EdgeInsets.all(Gap.lg),
              child: FilledButton.icon(
                onPressed: state._busy
                    ? null
                    : () => state._startSession(people),
                icon: const Icon(Icons.arrow_forward_rounded),
                label: Text(
                  state._busy
                      ? 'Starting the session…'
                      : came == 0
                          ? 'Continue'
                          : 'Continue — assess $came '
                                '${came == 1 ? 'person' : 'people'}',
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CameTile extends StatelessWidget {
  const _CameTile({required this.state, required this.person});

  final _PatientIntakeScreenState state;
  final Person person;

  @override
  Widget build(BuildContext context) {
    final came = state._present[person.id] ?? true;

    return Container(
      margin: const EdgeInsets.only(bottom: Gap.sm),
      decoration: BoxDecoration(
        color: came ? AppColors.canvas : Colors.white,
        borderRadius: BorderRadius.circular(Gap.radiusSm),
        border: Border.all(
          color: came ? AppColors.line : AppColors.triageAmber,
        ),
      ),
      child: CheckboxListTile(
        value: came,
        onChanged: (v) =>
            state.update(() => state._present[person.id] = v ?? true),
        title: Text(
          person.fullName,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14.5,
          ),
        ),
        subtitle: Text(
          '${person.effectiveClientType.label} · ${person.ageLabel}',
          style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
        ),
      ),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(Gap.md),
    decoration: BoxDecoration(
      color: AppColors.triageRedBg,
      borderRadius: BorderRadius.circular(Gap.radiusSm),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.error_outline_rounded,
          size: 18,
          color: AppColors.triageRed,
        ),
        const SizedBox(width: Gap.sm),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              color: AppColors.triageRed,
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

// --------------------------------------------------- Step 3: session running

/// Briefly visible while the barriers check and the assessment queue are
/// stacked on top. Calm, never an error.
class _SessionRunningPlaceholder extends StatelessWidget {
  const _SessionRunningPlaceholder();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(Gap.lg),
      child: Text(
        'Assessment session in progress — everyone who came is in the queue.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.inkMuted, height: 1.4),
      ),
    ),
  );
}

// ----------------------------------------------------------------- Indicator

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.step, required this.total});
  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    // The pills sit in a Flexible + FittedBox so that on a narrow (phone-width)
    // screen they scale down instead of overflowing the row — the "Step x of y"
    // caption stays full-size and pinned to the trailing edge.
    return Row(
      children: [
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 1; i <= total; i++) ...[
                  if (i > 1)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: Gap.xs),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 14,
                        color: AppColors.inkFaint,
                      ),
                    ),
                  _StepPill(
                    label: _label(i),
                    active: i == step,
                    done: i < step,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: Gap.sm),
        Text(
          'Step $step of $total',
          style: const TextStyle(
            fontSize: 11.5,
            color: AppColors.inkMuted,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  String _label(int i) => switch (i) {
    1 => 'Household',
    2 => 'Who came',
    3 => 'Assess',
    _ => '',
  };
}

class _StepPill extends StatelessWidget {
  const _StepPill({
    required this.label,
    required this.active,
    required this.done,
  });
  final String label;
  final bool active;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final colour = active
        ? AppColors.primary
        : done
            ? AppColors.accent
            : AppColors.inkFaint;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Gap.md,
        vertical: Gap.xs,
      ),
      decoration: BoxDecoration(
        color: active
            ? AppColors.primaryLight
            : done
                ? AppColors.primaryLight
                : AppColors.canvas,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colour.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (done)
            const Icon(Icons.check_rounded, size: 12, color: AppColors.accent)
          else
            Icon(Icons.circle_outlined, size: 12, color: colour),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: colour,
            ),
          ),
        ],
      ),
    );
  }
}
