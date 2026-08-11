/// An assessment session, from roll call to sign-off.
///
/// The single most important design decision in the app is on this screen:
/// **the unit of care is the session, and a session can contain several
/// people.**
///
/// Every district register, and almost every digital tool built on top of one,
/// treats a contact as one client. That is not what happens at the clinic. A
/// mother walks over with a three-week-old twin on her back and a two-year-old
/// holding her wrapper, and mentions on the way out that she has been feverish
/// since the delivery. That is three assessments, three protocols and one
/// conversation. A tool that forces the CHO to start over three times gets used
/// once and then abandoned for the paper register, and the two-year-old — the one
/// nobody came about — is the one who never gets measured.
///
/// So: roll call first, then a queue in clinical order, then one sign-off.
///
/// **Absence is recorded, not skipped.** "The baby is with the grandmother at
/// home" is the beginning of a defaulter trail, and it is free to capture while
/// the CHO is standing there.
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
import '../assessment/assessment_screen.dart';
import '../registration/member_form_screen.dart';
import '../shared/ui.dart';
import 'household_summary_screen.dart';

const _uuid = Uuid();

class RollCallScreen extends ConsumerStatefulWidget {
  const RollCallScreen({super.key, required this.householdId});

  final String householdId;

  @override
  ConsumerState<RollCallScreen> createState() => _RollCallScreenState();
}

class _RollCallScreenState extends ConsumerState<RollCallScreen> {
  final Set<VisitReason> _reasons = {};
  final Map<String, bool> _present = {};
  final Map<String, String> _absenceNotes = {};

  Visit? _visit;
  final Set<String> _assessed = {};
  bool _busy = false;
  String? _error;
  final _notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Pick up a visit that was interrupted. Phones die, families get called
    // away, and a half-finished visit that cannot be resumed is a half-finished
    // record that gets re-entered from memory.
    Future.microtask(_resumeIfOpen);
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  /// Lets the two phase widgets below rebuild this screen.
  void update(VoidCallback change) => setState(change);

  Future<void> _resumeIfOpen() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final open = await ref.read(careRepositoryProvider).resumableVisit(user);
    if (open == null || open.householdId != widget.householdId) return;

    final roll = await ref.read(careRepositoryProvider).rollCall(user, open.id);
    if (!mounted) return;
    setState(() {
      _visit = open;
      _reasons.addAll(open.reasons);
      for (final p in roll) {
        _present[p.personId] = p.wasPresent;
        if (p.assessed) _assessed.add(p.personId);
        if (p.absenceNote != null) _absenceNotes[p.personId] = p.absenceNote!;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(householdMembersProvider(widget.householdId));
    final household = ref.watch(householdProvider(widget.householdId));

    return Scaffold(
      appBar: AppBar(
        title: Text(_visit == null ? 'Who came today?' : 'Assessment in progress'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(22),
          child: Padding(
            padding: const EdgeInsets.only(
              left: Gap.lg,
              right: Gap.lg,
              bottom: Gap.sm,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                household.valueOrNull?.name ?? '',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.inkMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
      body: members.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          error: e is AccessDenied ? e.message : e,
        ),
        data: (people) => people.isEmpty
            ? const EmptyState(
                icon: Icons.person_off_outlined,
                title: 'Nobody registered here',
                message:
                    'Register the mother and any children in this household '
                    'before starting an assessment.',
              )
            : _visit == null
            ? _RollCallPhase(this, people, household.valueOrNull)
            : _QueuePhase(this, people),
      ),
    );
  }

  // ------------------------------------------------------------------ Actions

  Future<void> _start(List<Person> people) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    if (_reasons.isEmpty) {
      setState(
        () => _error =
            'Pick at least one reason for today\u2019s assessment. It is what '
            'the follow-up schedule and the monthly report are built from.',
      );
      return;
    }

    final present = people
        .where((p) => _present[p.id] ?? true)
        .toList(growable: false);
    if (present.isEmpty) {
      setState(
        () => _error =
            'Nobody is marked present. If nobody came, record it as a '
            'defaulter trace instead of an assessment.',
      );
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final visit = Visit(
      id: _uuid.v4(),
      householdId: widget.householdId,
      conductedBy: user.id,
      startedAt: DateTime.now(),
      reasons: _reasons.toList(growable: false),
    );

    // Queue order is the clinical order the list already arrived in: mother,
    // then newborns, then under-fives. Preserved so the record shows who was
    // seen first if it is ever reviewed after a death.
    final roll = <VisitParticipant>[
      for (final (i, p) in people.indexed)
        VisitParticipant(
          visitId: visit.id,
          personId: p.id,
          wasPresent: _present[p.id] ?? true,
          absenceNote: (_present[p.id] ?? true) ? null : _absenceNotes[p.id],
          queueOrder: i,
        ),
    ];

    try {
      await ref.read(careRepositoryProvider).startVisit(user, visit, roll);
      if (!mounted) return;
      setState(() {
        _visit = visit;
        _busy = false;
      });
    } on AccessDenied catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      // Anything else must never wedge the button: reset busy and say what
      // happened, right next to the CTA where the user is looking.
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not start the assessments. Please try again.';
      });
    }
  }

  Future<void> _assess(Person person) async {
    final visit = _visit;
    if (visit == null) return;

    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AssessmentScreen(visit: visit, personId: person.id),
      ),
    );
    if (!mounted || done != true) return;

    final user = ref.read(currentUserProvider);
    if (user != null) {
      await ref.read(careRepositoryProvider).updateRollCall(
        user,
        VisitParticipant(
          visitId: visit.id,
          personId: person.id,
          wasPresent: true,
          queueOrder: 0,
          assessed: true,
        ),
      );
    }
    ref.invalidate(latestAssessmentProvider(person.id));
    ref.invalidate(householdScoreProvider(widget.householdId));
    if (!mounted) return;
    setState(() => _assessed.add(person.id));
  }

  Future<void> _finish(List<Person> people) async {
    final visit = _visit;
    final user = ref.read(currentUserProvider);
    if (visit == null || user == null) return;

    final pending = people
        .where((p) => (_present[p.id] ?? true) && !_assessed.contains(p.id))
        .toList(growable: false);

    if (pending.isNotEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Finish without assessing everyone?'),
          content: Text(
            '${pending.map((p) => p.fullName).join(', ')} '
            '${pending.length == 1 ? 'was' : 'were'} present but not assessed.\n\n'
            'This is the gap the app was built to close: the child nobody came '
            'about is the one who goes unmeasured. Assess them if you can.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Go back'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Finish anyway'),
            ),
          ],
        ),
      );
      if (go != true) return;
    }

    if (!mounted) return;
    setState(() => _busy = true);

    // Master flow [47] → [58]: a visit is not "done" until every queued
    // person has a result AND the CHO has signed off the whole encounter in
    // one view. The summary screen performs the actual save.
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => HouseholdSummaryScreen(
          visit: visit,
          householdId: widget.householdId,
          assessedIds: _assessed.toList(growable: false),
          notes: _notes.text,
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (saved == true) Navigator.of(context).pop();
  }
}

// ------------------------------------------------------------------- Phase one

class _RollCallPhase extends StatelessWidget {
  const _RollCallPhase(this.state, this.people, this.household);

  final _RollCallScreenState state;
  final List<Person> people;
  final Household? household;

  /// [16] → [17] → ⟲ [16]. Registering a new person pops back into this same
  /// roll call; the member list is invalidated so the newcomer appears at
  /// once, ready to be ticked present and queued for assessment.
  Future<void> _addPerson(BuildContext context) async {
    final h = household;
    if (h == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MemberFormScreen(household: h)),
    );
    state.ref.invalidate(householdMembersProvider(h.id));
    state.ref.invalidate(householdScoreProvider(h.id));
  }

  @override
  Widget build(BuildContext context) {
    final presentCount =
        people.where((p) => state._present[p.id] ?? true).length;
    final ready = state._reasons.isNotEmpty && presentCount > 0;

    return Column(
    children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(Gap.lg),
          children: [
            SectionCard(
              title: 'Why are you here?',
              subtitle:
                  'More than one is normal. A mother who came about a fever '
                  'often leaves with her child weighed and her own postnatal '
                  'check done.',
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
              title: 'Mark who came',
              subtitle:
                  'Everyone registered in this household. Untick anybody who '
                  'did not come today, and say where they are — that note is '
                  'the start of the follow-up.',
              icon: Icons.how_to_reg_outlined,
              child: Column(
                children: [
                  for (final p in people) _RollTile(state: state, person: p),
                ],
              ),
            ),
            const SizedBox(height: Gap.lg),

            // Master flow [16] → [17]: somebody new showed up today. Register
            // them, then loop straight back into this roll call so they are
            // assessed in the same session — never a second trip.
            OutlinedButton.icon(
              onPressed: household == null ? null : () => _addPerson(context),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Register someone who came today'),
            ),
            const SizedBox(height: Gap.xxl),
          ],
        ),
      ),
      SafeArea(
        minimum: const EdgeInsets.all(Gap.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (state._error != null) ...[
              _Warning(state._error!),
              const SizedBox(height: Gap.sm),
            ],
            if (!ready && !state._busy) ...[
              Text(
                state._reasons.isEmpty
                    ? 'Pick why the family came — then you can start.'
                    : 'Tick at least one person as present to start.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.inkMuted,
                ),
              ),
              const SizedBox(height: Gap.sm),
            ],
            FilledButton.icon(
              onPressed: ready && !state._busy
                  ? () => state._start(people)
                  : null,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(
                state._busy
                    ? 'Starting assessments…'
                    : 'Start the assessments ($presentCount present)',
              ),
            ),
          ],
        ),
      ),
    ],
    );
  }
}

class _RollTile extends StatelessWidget {
  const _RollTile({required this.state, required this.person});

  final _RollCallScreenState state;
  final Person person;

  @override
  Widget build(BuildContext context) {
    final present = state._present[person.id] ?? true;

    return Container(
      margin: const EdgeInsets.only(bottom: Gap.sm),
      decoration: BoxDecoration(
        color: present ? AppColors.canvas : Colors.white,
        borderRadius: BorderRadius.circular(Gap.radiusSm),
        border: Border.all(
          color: present ? AppColors.line : AppColors.triageAmber,
        ),
      ),
      child: Column(
        children: [
          CheckboxListTile(
            value: present,
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
          if (!present)
            Padding(
              padding: const EdgeInsets.only(
                left: Gap.md,
                right: Gap.md,
                bottom: Gap.md,
              ),
              child: TextField(
                onChanged: (v) => state._absenceNotes[person.id] = v,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Where are they?',
                  hintText: 'e.g. gone to Yendi market with the grandmother',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------- Phase two

class _QueuePhase extends ConsumerWidget {
  const _QueuePhase(this.state, this.people);

  final _RollCallScreenState state;
  final List<Person> people;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final present = people
        .where((p) => state._present[p.id] ?? true)
        .toList(growable: false);
    final absent = people
        .where((p) => !(state._present[p.id] ?? true))
        .toList(growable: false);
    final remaining = present
        .where((p) => !state._assessed.contains(p.id))
        .length;
    // The next person in clinical order — the CHO reads the queue the way
    // they would read a paper list: who am I seeing now, who is next.
    final next = present
        .where((p) => !state._assessed.contains(p.id))
        .firstOrNull;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(Gap.lg),
            children: [
              Container(
                padding: const EdgeInsets.all(Gap.lg),
                decoration: BoxDecoration(
                  color: remaining == 0
                      ? AppColors.triageGreenBg
                      : AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(Gap.radius),
                ),
                child: Row(
                  children: [
                    Icon(
                      remaining == 0
                          ? Icons.task_alt_rounded
                          : Icons.list_alt_rounded,
                      color: remaining == 0
                          ? AppColors.triageGreen
                          : AppColors.primary,
                    ),
                    const SizedBox(width: Gap.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            remaining == 0
                                ? 'Everyone present has been assessed. Add a '
                                      'note if you need to, then sign off.'
                                : '$remaining of ${present.length} still to '
                                      'assess.',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              height: 1.35,
                              color: remaining == 0
                                  ? AppColors.triageGreen
                                  : AppColors.primary,
                            ),
                          ),
                          if (next != null) ...[
                            const SizedBox(height: 3),
                            Text(
                              'Next: ${next.fullName}',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 12.5,
                                color: remaining == 0
                                    ? AppColors.triageGreen
                                    : AppColors.primary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Gap.lg),

              SectionCard(
                title: 'Today\u2019s queue',
                subtitle:
                    'In clinical order: the mother first, then the newborns, '
                    'then the older children.',
                icon: Icons.playlist_add_check_rounded,
                child: Column(
                  children: [
                    for (final (i, p) in present.indexed)
                      _QueueTile(
                        state: state,
                        person: p,
                        index: i + 1,
                        done: state._assessed.contains(p.id),
                      ),
                  ],
                ),
              ),

              if (absent.isNotEmpty) ...[
                const SizedBox(height: Gap.lg),
                SectionCard(
                  title: 'Not here today',
                  subtitle:
                      'Recorded as absent. These become follow-up targets, not '
                      'blank rows.',
                  icon: Icons.person_off_outlined,
                  accent: AppColors.triageAmber,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final p in absent)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Gap.sm),
                          child: Text(
                            '${p.fullName} — '
                            '${state._absenceNotes[p.id]?.trim().isNotEmpty == true ? state._absenceNotes[p.id] : 'no reason given'}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.inkMuted,
                              height: 1.35,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: Gap.lg),
              SectionCard(
                title: 'Clinic note',
                subtitle:
                    'Anything the forms did not ask about. Kept with this '
                    'assessment session.',
                icon: Icons.edit_note_rounded,
                child: TextField(
                  controller: state._notes,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText:
                        'e.g. husband away in Kumasi until harvest; '
                        'grandmother is the decision-maker',
                  ),
                ),
              ),
              const SizedBox(height: Gap.xxl),
            ],
          ),
        ),
        SafeArea(
          minimum: const EdgeInsets.all(Gap.lg),
          child: FilledButton.icon(
            onPressed: state._busy ? null : () => state._finish(people),
            style: remaining == 0
                ? null
                : FilledButton.styleFrom(
                    backgroundColor: AppColors.inkMuted,
                  ),
            icon: const Icon(Icons.check_circle_outline_rounded),
            label: const Text('Finish and sign off'),
          ),
        ),
      ],
    );
  }
}

class _QueueTile extends ConsumerWidget {
  const _QueueTile({
    required this.state,
    required this.person,
    required this.index,
    required this.done,
  });

  final _RollCallScreenState state;
  final Person person;
  final int index;
  final bool done;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final last = ref.watch(latestAssessmentProvider(person.id));

    return Container(
      margin: const EdgeInsets.only(bottom: Gap.sm),
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: done ? AppColors.triageGreenBg : AppColors.canvas,
        borderRadius: BorderRadius.circular(Gap.radiusSm),
      ),
      child: Row(
        children: [
          Container(
            height: 28,
            width: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: done ? AppColors.triageGreen : Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: done ? AppColors.triageGreen : AppColors.line,
              ),
            ),
            child: done
                ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                : Text(
                    '$index',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
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
                    fontSize: 14,
                  ),
                ),
                Text(
                  '${person.effectiveClientType.label} · '
                  '${person.effectiveClientType.protocolLabel} protocol',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.inkMuted,
                  ),
                ),
                if (done)
                  last.maybeWhen(
                    data: (a) => a == null
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(top: Gap.xs),
                            child: Row(
                              children: [
                                Flexible(
                                  child: TriageBadge(
                                    a.effectiveTriage,
                                    compact: true,
                                  ),
                                ),
                                const SizedBox(width: Gap.sm),
                                Expanded(
                                  child: Text(
                                    '${a.result.classification} · '
                                    '${a.result.effectiveConfidenceScore}% '
                                    'confidence',
                                    style: const TextStyle(
                                      fontSize: 11.5,
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
              ],
            ),
          ),
          const SizedBox(width: Gap.sm),
          done
              ? TextButton(
                  onPressed: () => state._assess(person),
                  child: const Text('Redo'),
                )
              : FilledButton(
                  onPressed: () => state._assess(person),
                  // The theme's full-width minimum size throws inside the
                  // unbounded Row; this button sizes to its label instead.
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, Gap.tapTarget),
                  ),
                  child: const Text('Assess'),
                ),
        ],
      ),
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(Gap.md),
    decoration: BoxDecoration(
      color: AppColors.triageAmberBg,
      borderRadius: BorderRadius.circular(Gap.radiusSm),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.info_outline_rounded,
          size: 18,
          color: AppColors.triageAmber,
        ),
        const SizedBox(width: Gap.sm),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.triageAmber,
              height: 1.35,
            ),
          ),
        ),
      ],
    ),
  );
}
