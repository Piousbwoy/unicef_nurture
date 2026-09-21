/// One clinic session: deliberate attendance, a persisted queue, then review.
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
import '../assessment/assessment_screen.dart';
import '../fhw/clinic_widgets.dart';
import '../registration/member_form_screen.dart';
import 'household_summary_screen.dart';
import 'sbar_card.dart';

const _steps = [
  'Household record',
  'Who is here',
  'Assessment queue',
  'Review session',
];

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
  final _notes = TextEditingController();
  Visit? _visit;
  List<VisitParticipant> _roll = [];
  List<Assessment> _assessments = [];
  bool _loading = true;
  bool _busy = false;
  bool _needsReload = false;
  String? _error;
  String _omissionReason = '';

  Set<String> get _assessed => _assessments.map((a) => a.personId).toSet();

  @override
  void initState() {
    super.initState();
    Future.microtask(_resumeIfOpen);
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  String _message(Object e, String fallback) =>
      e is AccessDenied ? e.message : fallback;

  Future<void> _resumeIfOpen() async {
    if (_busy) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = ref.read(currentUserProvider);
      if (user == null) throw StateError('Sign in required');
      final open = await ref
          .read(careRepositoryProvider)
          .openVisitForHousehold(user, widget.householdId);
      if (!mounted) return;
      if (open != null) {
        await _loadSession(open, restoreNotes: true);
      } else {
        setState(() => _needsReload = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _needsReload = true;
          _error = _message(
            e,
            'Could not load the session. Retry before starting or assessing.',
          );
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// The stored roll, not the current household membership, defines attendance.
  /// A saved assessment may outlive a failed participant update. Reconcile it
  /// without asking for another clinical assessment or changing queue order.
  Future<void> _loadSession(Visit visit, {bool restoreNotes = false}) async {
    final user = ref.read(currentUserProvider);
    if (user == null) throw StateError('Sign in required');
    final repository = ref.read(careRepositoryProvider);
    final roll = (await repository.rollCall(user, visit.id)).toList()
      ..sort((a, b) => a.queueOrder.compareTo(b.queueOrder));
    final histories = await Future.wait([
      for (final p in roll) repository.assessmentHistory(user, p.personId),
    ]);
    final assessments = histories
        .expand((h) => h)
        .where((a) => a.visitId == visit.id)
        .toList();
    if (!mounted) return;
    setState(() {
      _visit = visit;
      _roll = roll;
      _assessments = assessments;
      if (restoreNotes) _notes.text = visit.notes ?? '';
    });
    for (var i = 0; i < roll.length; i++) {
      final p = roll[i];
      final saved = assessments.any((a) => a.personId == p.personId);
      if (p.assessed != saved) {
        final updated = p.copyWith(assessed: saved);
        await repository.updateRollCall(user, updated);
        roll[i] = updated;
      }
    }
    if (mounted) {
      setState(() {
        _roll = roll;
        _needsReload = false;
        _error = null;
      });
    }
  }

  Future<void> _retry() async {
    if (_busy || _loading) return;
    if (_visit == null) {
      await _resumeIfOpen();
      return;
    }
    setState(() => _busy = true);
    try {
      await _loadSession(_visit!);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = _message(
            e,
            'Could not refresh the queue. Saved assessments do not need to be repeated. Retry.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start(List<Person> people) async {
    if (_busy || _loading || _needsReload) return;
    final user = ref.read(currentUserProvider);
    if (user == null) {
      setState(() => _error = 'Sign in again to start a clinic session.');
      return;
    }
    if (_reasons.isEmpty || !people.any((p) => _present[p.id] == true)) {
      setState(
        () => _error = 'Select a reason and at least one person who is here.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repository = ref.read(careRepositoryProvider);
      final open = await repository.openVisitForHousehold(
        user,
        widget.householdId,
      );
      if (!mounted) return;
      if (open != null) {
        await _loadSession(open, restoreNotes: true);
        return;
      }
      final visit = Visit(
        id: const Uuid().v4(),
        householdId: widget.householdId,
        conductedBy: user.id,
        startedAt: DateTime.now(),
        reasons: _reasons.toList(),
      );
      final roll = [
        for (final (i, p) in people.indexed)
          VisitParticipant(
            visitId: visit.id,
            personId: p.id,
            wasPresent: _present[p.id] ?? false,
            absenceNote: _present[p.id] == true ? null : _absenceNotes[p.id],
            queueOrder: i,
          ),
      ];
      await repository.startVisit(user, visit, roll);
      if (!mounted) return;
      setState(() {
        _visit = visit;
        _roll = roll;
      });
      ref.invalidate(dayPlanProvider);
      ref.invalidate(visitHistoryProvider(widget.householdId));
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = _message(
            e,
            'Could not open the session. Try again; an existing session will be resumed.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _assess(Person person) async {
    final visit = _visit;
    if (visit == null || _busy || _needsReload) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => AssessmentScreen(visit: visit, personId: person.id),
        ),
      );
      if (!mounted) return;
      // Refresh even after back/cancel: the result may have saved successfully
      // before a downstream operation or the navigation callback failed.
      ref.invalidate(latestAssessmentProvider(person.id));
      ref.invalidate(householdScoreProvider(widget.householdId));
      await _loadSession(visit);
    } catch (e) {
      if (mounted) {
        setState(() {
          _needsReload = true;
          _error = _message(
            e,
            'Could not refresh the session. Any saved assessment is kept. Retry the queue update; do not repeat the assessment.',
          );
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish() async {
    if (_visit == null || _busy || _needsReload) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _loadSession(_visit!);
      if (!mounted) return;
      // Review owns the required reason field, keeping omissions visible beside
      // the saved results rather than hiding them in a confirmation dialog.
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => HouseholdSummaryScreen(
            visit: _visit!,
            householdId: widget.householdId,
            assessedIds: _assessed.toList(),
            participants: List.of(_roll),
            assessments: List.of(_assessments),
            notes: _notes.text,
            omissionReason: _omissionReason,
            onOmissionReasonChanged: (reason) => _omissionReason = reason,
          ),
        ),
      );
      if (mounted && saved == true) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _needsReload = true;
          _error = _message(
            e,
            'Could not prepare review. Retry; this session is still open.',
          );
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    if (_busy || _loading) return;
    if (_visit == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _busy = true);
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave session open?'),
        content: const Text(
          'Recorded attendance and saved assessments can be resumed. Unfinished assessment forms and unsaved clinic notes are not saved when you leave.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep working'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Leave session open'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (leave == true) Navigator.of(context).pop();
  }

  Future<void> _addPerson(Household household) async {
    if (_busy) return;
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

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(householdMembersProvider(widget.householdId));
    final household = ref.watch(householdProvider(widget.householdId));
    return PopScope(
      canPop: !_busy && !_loading && _visit == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          title: const Text('Clinic session'),
          leading: BackButton(onPressed: _busy || _loading ? null : _leave),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : members.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    const ClinicStatusLine(
                      text: 'Could not load household members.',
                    ),
                    OutlinedButton(
                      onPressed: () => ref.invalidate(
                        householdMembersProvider(widget.householdId),
                      ),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
                data: (people) => ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    ClinicStepHeader(
                      steps: _steps,
                      current: _visit == null ? 1 : 2,
                    ),
                    Text(
                      household.valueOrNull?.name ?? 'Household session',
                      style: AppType.title,
                    ),
                    const SizedBox(height: 16),
                    if (_error != null) ...[
                      ClinicStatusLine(text: _error!, icon: Icons.info_outline),
                      if (_needsReload)
                        OutlinedButton(
                          onPressed: _busy ? null : _retry,
                          child: const Text('Retry queue update'),
                        ),
                      const SizedBox(height: 16),
                    ],
                    if (_visit == null)
                      ..._attendance(people, household.valueOrNull)
                    else
                      ..._queue(people),
                  ],
                ),
              ),
      ),
    );
  }

  List<Widget> _attendance(List<Person> people, Household? household) => [
    ClinicCard(
      title: 'Who is here?',
      subtitle:
          'Select each person attending the clinic. Attendance is not assumed.',
      child: Column(
        children: [
          if (people.isEmpty) const Text('Register a family member to begin.'),
          for (final person in people) ...[
            CheckboxListTile(
              key: ValueKey('attendance-${person.id}'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _present[person.id] ?? false,
              title: Text(
                person.fullName,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              subtitle: Text(
                '${person.effectiveClientType.label} · ${person.ageLabel}',
              ),
              onChanged: _busy || _needsReload
                  ? null
                  : (value) =>
                        setState(() => _present[person.id] = value ?? false),
            ),
            if (_present[person.id] != true)
              TextFormField(
                key: ValueKey('absence-${person.id}'),
                initialValue: _absenceNotes[person.id],
                enabled: !_busy && !_needsReload,
                decoration: const InputDecoration(
                  labelText: 'Absence note (optional)',
                ),
                onChanged: (value) => _absenceNotes[person.id] = value,
              ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    ),
    const SizedBox(height: 16),
    OutlinedButton.icon(
      onPressed: household == null || _busy || _needsReload
          ? null
          : () => _addPerson(household),
      icon: const Icon(Icons.person_add_alt_1_outlined),
      label: const Text('Register a family member'),
    ),
    const SizedBox(height: 20),
    ClinicCard(
      title: 'Reason for the session',
      subtitle: 'Select all that apply.',
      child: Column(
        children: [
          for (final reason in VisitReason.values.where(
            (r) => r != VisitReason.routineHomeVisit,
          ))
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(reason.label),
              value: _reasons.contains(reason),
              onChanged: _busy || _needsReload
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
    FilledButton(
      onPressed: _busy || _needsReload ? null : () => _start(people),
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      child: Text(_busy ? 'Opening session…' : 'Start assessment queue'),
    ),
  ];

  List<Widget> _queue(List<Person> people) {
    final byId = {for (final p in people) p.id: p};
    final assessed = _assessed;
    final triageOf = {
      for (final a in _assessments) a.personId: a.effectiveTriage,
    };
    final waiting = _roll
        .where((p) => p.wasPresent && !assessed.contains(p.personId))
        .toList();
    // Consultation board: the most clinically urgent saved verdict floats to
    // the top, so a nurse who returns to a paused session meets the sickest
    // child first rather than the last name on the roll.
    final saved =
        _roll.where((p) => assessed.contains(p.personId)).toList()
          ..sort((a, b) {
            final sa = triageOf[a.personId]?.severity ?? 0;
            final sb = triageOf[b.personId]?.severity ?? 0;
            return sb.compareTo(sa);
          });
    final absent = _roll.where((p) => !p.wasPresent).toList();
    final next = waiting
        .map((p) => byId[p.personId])
        .whereType<Person>()
        .firstOrNull;
    final laterMembers = people
        .where((p) => !_roll.any((r) => r.personId == p.id))
        .length;
    return [
      ClinicStatusLine(
        text:
            '${waiting.length} waiting · ${saved.length} assessment${saved.length == 1 ? '' : 's'} saved · ${absent.length} not here',
        icon: Icons.list_alt_outlined,
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: _busy || _needsReload || next == null
            ? null
            : () => _assess(next),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        child: const Text('Assess next person'),
      ),
      const SizedBox(height: 20),
      ClinicCard(
        title: 'Waiting (${waiting.length})',
        subtitle: 'People here without a saved assessment in this session.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (waiting.isEmpty) const Text('No one waiting for assessment.'),
            for (final p in waiting)
              _queuePerson(p, byId[p.personId], saved: false),
          ],
        ),
      ),
      const SizedBox(height: 20),
      ClinicCard(
        title: 'Assessment saved (${saved.length})',
        subtitle: 'Saved is a record status, not a clinical outcome.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (saved.isEmpty)
              const Text('No assessments saved in this session yet.'),
            for (final p in saved)
              _queuePerson(
                p,
                byId[p.personId],
                saved: true,
                triage: triageOf[p.personId],
                assessment: _assessments
                    .where((a) => a.personId == p.personId)
                    .firstOrNull,
              ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      ClinicCard(
        title: 'Not here (${absent.length})',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (absent.isEmpty)
              const Text('All people on this session roll are here.'),
            for (final p in absent)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  '${byId[p.personId]?.fullName ?? 'Household member'} — ${p.absenceNote?.trim().isNotEmpty == true ? p.absenceNote : 'Not here'}',
                ),
              ),
          ],
        ),
      ),
      if (laterMembers > 0) ...[
        const SizedBox(height: 16),
        ClinicStatusLine(
          text:
              '$laterMembers household member(s) are not on this session roll. Their attendance has not been recorded.',
        ),
      ],
      const SizedBox(height: 20),
      ClinicCard(
        title: 'Clinic note',
        subtitle:
            'Saved when you close the session. This note is not autosaved.',
        child: TextField(
          controller: _notes,
          enabled: !_busy,
          minLines: 3,
          maxLines: null,
          decoration: const InputDecoration(
            hintText: 'Context or follow-up arrangements',
          ),
        ),
      ),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: _busy || _needsReload ? null : _finish,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        child: Text(_busy ? 'Please wait…' : 'Review session'),
      ),
      const SizedBox(height: 16),
      OutlinedButton(
        onPressed: _busy ? null : _leave,
        child: const Text('Leave session open'),
      ),
      const SizedBox(height: 16),
      const ClinicStatusLine(
        text:
            'Only recorded attendance and saved assessments can be resumed. Draft assessment forms and unsaved notes are not durable.',
      ),
      const SizedBox(height: 20),
    ];
  }

  Widget _queuePerson(
    VisitParticipant participant,
    Person? person, {
    required bool saved,
    TriageLevel? triage,
    Assessment? assessment,
  }) {
    final name = person?.fullName.trim() ?? '';
    final initial = name.isEmpty ? '•' : name[0].toUpperCase();
    final waited = _visit == null
        ? null
        : DateTime.now().difference(_visit!.startedAt);
    final waitLabel = waited == null
        ? null
        : waited.inMinutes < 60
        ? 'Waiting ${waited.inMinutes} min'
        : 'Waiting ${waited.inHours}h ${waited.inMinutes % 60}m';
    final triageColor = switch (triage) {
      TriageLevel.urgent => AppColors.triageRed,
      TriageLevel.priority => AppColors.triageAmber,
      TriageLevel.watch => AppColors.triageAmber,
      TriageLevel.routine => AppColors.triageGreen,
      null => null,
    };
    final triageShort = switch (triage) {
      TriageLevel.urgent => 'Urgent',
      TriageLevel.priority => 'Priority',
      TriageLevel.watch => 'Watch',
      TriageLevel.routine => 'Routine',
      null => 'Saved',
    };
    return Container(
      key: ValueKey('queue-${participant.personId}'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: saved ? AppColors.primaryLight : AppColors.canvas,
        borderRadius: BorderRadius.circular(Gap.radiusSm),
        border: Border.all(
          color: triageColor ?? AppColors.line,
          width: triageColor == null ? Gap.hairline : 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.primaryDeep,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  initial,
                  style: AppType.label.copyWith(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      person?.fullName ?? 'Household member unavailable',
                      style: AppType.label.copyWith(color: AppColors.ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      saved
                          ? 'Assessment saved'
                          : person?.effectiveClientType.label ??
                                'Reload the household record to assess.',
                      style: AppType.caption,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (saved && triageColor != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: triageColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    triageShort,
                    style: AppType.label.copyWith(
                      fontSize: 11,
                      color: triageColor,
                    ),
                  ),
                )
              else if (!saved && waitLabel != null)
                Text(waitLabel, style: AppType.caption),
            ],
          ),
          if (person != null && person.ageLabel.isNotEmpty && !saved) ...[
            const SizedBox(height: 8),
            Text(person.ageLabel, style: AppType.caption),
          ],
          if (!saved && person != null) ...[
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy || _needsReload ? null : () => _assess(person),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('Assess'),
            ),
          ],
          if (saved && assessment != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy || _needsReload
                  ? null
                  : () => showSbarSheet(
                      context,
                      SbarCard.fromAssessment(assessment, person),
                    ),
              icon: const Icon(Icons.notes_rounded, size: 18),
              label: const Text('Handover note'),
            ),
          ],
        ],
      ),
    );
  }
}
