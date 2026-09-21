/// Clinic intake: choose a household, confirm attendance, open one session.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/local/visit_dao.dart' show VisitParticipant;
import '../../data/repositories/care_repository.dart';
import '../../domain/entities/core.dart';
import '../../domain/entities/visit.dart';
import '../../domain/enums.dart';
import '../fhw/clinic_widgets.dart';
import '../fhw/families_tab.dart';
import 'member_form_screen.dart';
import '../visit/barrier_check_screen.dart';
import '../visit/roll_call_screen.dart';

const _steps = [
  'Household record',
  'Who is here',
  'Assessment queue',
  'Review session',
];

class PatientIntakeScreen extends ConsumerStatefulWidget {
  const PatientIntakeScreen({
    super.key,
    this.knownHouseholds = const [],
    this.initialHousehold,
  });

  /// The picker refreshes this snapshot through the normal scoped provider.
  final List<Household> knownHouseholds;
  final Household? initialHousehold;

  @override
  ConsumerState<PatientIntakeScreen> createState() =>
      _PatientIntakeScreenState();
}

class _PatientIntakeScreenState extends ConsumerState<PatientIntakeScreen> {
  Household? _household;
  int _step = 0;
  final Set<VisitReason> _reasons = {};
  final Map<String, bool> _present = {};
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _household = widget.initialHousehold;
    _step = _household == null ? 0 : 1;
  }

  void _pick(Household household) {
    if (_busy) return;
    setState(() {
      if (_household?.id != household.id) {
        _present.clear();
        _reasons.clear();
      }
      _household = household;
      _step = 1;
      _error = null;
    });
  }

  void _back() {
    if (_busy) return;
    if (_step == 0) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _step = 0;
        _error = null;
      });
    }
  }

  Future<void> _addMember() async {
    if (_busy) return;
    final household = _household!;
    setState(() => _busy = true);
    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MemberFormScreen(household: household),
        ),
      );
      if (!mounted) return;
      ref.invalidate(householdMembersProvider(household.id));
      ref.invalidate(householdScoreProvider(household.id));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openQueue(String householdId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RollCallScreen(householdId: householdId),
      ),
    );
    if (mounted) Navigator.of(context).pop(householdId);
  }

  Future<void> _startSession(List<Person> people) async {
    if (_busy) return;
    final user = ref.read(currentUserProvider);
    if (user == null) {
      setState(() => _error = 'Sign in again to start a clinic session.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repository = ref.read(careRepositoryProvider);
      // Real clinic queue: if THIS household already has an open session, join
      // it rather than starting a duplicate. A different household is free to
      // open its own ticket, so a nurse can receive several families at once
      // and move between them.
      final open = await repository.openVisitForHousehold(
        user,
        _household!.id,
      );
      if (!mounted) return;
      if (open != null) {
        await _openQueue(open.householdId);
        return;
      }
      if (_reasons.isEmpty) {
        setState(
          () => _error = 'Select at least one reason for this clinic session.',
        );
        return;
      }
      if (!people.any((p) => _present[p.id] == true)) {
        setState(
          () => _error = 'Select the people who are here before continuing.',
        );
        return;
      }
      final householdId = _household!.id;
      final visit = Visit(
        id: const Uuid().v4(),
        householdId: householdId,
        conductedBy: user.id,
        startedAt: DateTime.now(),
        reasons: _reasons.toList(growable: false),
      );
      await repository.startVisit(user, visit, [
        for (final (i, p) in people.indexed)
          VisitParticipant(
            visitId: visit.id,
            personId: p.id,
            wasPresent: _present[p.id] ?? false,
            queueOrder: i,
          ),
      ]);
      if (!mounted) return;
      ref.invalidate(dayPlanProvider);
      ref.invalidate(visitHistoryProvider(householdId));
      final proceed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => BarrierCheckScreen(householdId: householdId),
        ),
      );
      if (!mounted) return;
      if (proceed != true) {
        setState(
          () => _error =
              'Session left open. Attendance is saved; continue to resume it.',
        );
        return;
      }
      await _openQueue(householdId);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is AccessDenied
              ? e.message
              : 'Could not continue. Try again; any session already created will be offered for resume.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy && _step == 0,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _back();
    },
    child: Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Clinic session'),
        leading: BackButton(onPressed: _busy ? null : _back),
      ),
      body: _step == 0
          ? _PickHouseholdStep(
              known: widget.knownHouseholds,
              picked: _household,
              onPicked: _pick,
            )
          : ref
                .watch(householdMembersProvider(_household!.id))
                .when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      const ClinicStatusLine(
                        text: 'Could not load household members.',
                      ),
                      OutlinedButton(
                        onPressed: () => ref.invalidate(
                          householdMembersProvider(_household!.id),
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                  data: _attendance,
                ),
    ),
  );

  Widget _attendance(List<Person> people) {
    final count = people.where((p) => _present[p.id] == true).length;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const ClinicStepHeader(steps: _steps, current: 1),
        Text(_household!.name, style: AppType.title),
        const SizedBox(height: 16),
        ClinicCard(
          title: 'Who is here?',
          subtitle:
              'Select each person attending today. Nobody is selected automatically.',
          child: Column(
            children: [
              if (people.isEmpty)
                const Text('Register a family member to begin.'),
              for (final p in people)
                CheckboxListTile(
                  key: ValueKey('attendance-${p.id}'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _present[p.id] ?? false,
                  onChanged: _busy
                      ? null
                      : (value) =>
                            setState(() => _present[p.id] = value ?? false),
                  title: Text(
                    p.fullName,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    '${p.effectiveClientType.label} · ${p.ageLabel}',
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _busy ? null : _addMember,
          icon: const Icon(Icons.person_add_alt_1_outlined),
          label: const Text('Register a family member'),
        ),
        const SizedBox(height: 20),
        ClinicCard(
          title: 'Reason for the session',
          subtitle: 'Select all that apply.',
          child: Column(
            children: [
              // Home-visit reasons remain available in historical records, not
              // as a misleading default for a new clinic encounter.
              for (final reason in VisitReason.values.where(
                (r) => r != VisitReason.routineHomeVisit,
              ))
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(reason.label),
                  value: _reasons.contains(reason),
                  onChanged: _busy
                      ? null
                      : (on) => setState(() {
                          if (on == true) {
                            _reasons.add(reason);
                          } else {
                            _reasons.remove(reason);
                          }
                        }),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (_error != null) ...[
          ClinicStatusLine(text: _error!, icon: Icons.info_outline),
          const SizedBox(height: 16),
        ],
        Text('$count selected', style: AppType.label),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : () => _startSession(people),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: Text(
            _busy ? 'Opening session…' : 'Continue to assessment queue',
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

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
  ConsumerState<_PickHouseholdStep> createState() => _PickHouseholdStepState();
}

class _PickHouseholdStepState extends ConsumerState<_PickHouseholdStep> {
  String _query = '';
  bool _opening = false;

  @override
  Widget build(BuildContext context) {
    final households = ref.watch(visibleHouseholdsProvider);
    final list = households.valueOrNull ?? widget.known;
    final q = _query.trim().toLowerCase();
    final filtered = list.where(
      (h) =>
          q.isEmpty ||
          h.name.toLowerCase().contains(q) ||
          h.community.toLowerCase().contains(q) ||
          (h.headName?.toLowerCase().contains(q) ?? false),
    );
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const ClinicStepHeader(steps: _steps, current: 0),
        ClinicCard(
          title: 'Find the household record',
          subtitle: 'Choose the family attending the clinic.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  labelText: 'Search households',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 16),
              if (households.isLoading) const LinearProgressIndicator(),
              if (households.hasError)
                ClinicStatusLine(
                  text: 'Could not refresh households. Tap to retry.',
                  onTap: () => ref.invalidate(visibleHouseholdsProvider),
                ),
              if (filtered.isEmpty && !households.isLoading)
                const Text(
                  'No matching household. You can register one below.',
                ),
              for (final household in filtered)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  selected: widget.picked?.id == household.id,
                  title: Text(
                    household.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  subtitle: Text(
                    '${household.community} · ${household.district}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _opening ? null : () => widget.onPicked(household),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: _opening
              ? null
              : () async {
                  setState(() => _opening = true);
                  try {
                    final created = await showModalBottomSheet<bool>(
                      context: context,
                      isScrollControlled: true,
                      showDragHandle: true,
                      builder: (_) => const HouseholdFormSheet(),
                    );
                    if (mounted && created == true) {
                      ref.invalidate(visibleHouseholdsProvider);
                    }
                  } finally {
                    if (mounted) setState(() => _opening = false);
                  }
                },
          icon: const Icon(Icons.add_home_outlined),
          label: const Text('Register a new household'),
        ),
      ],
    );
  }
}
