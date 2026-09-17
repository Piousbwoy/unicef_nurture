import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/motion.dart';
import '../../../domain/entities/caregiver.dart';
import '../../../domain/entities/core.dart';
import '../../../domain/entities/visit.dart';
import '../../../domain/enums.dart';
import '../caregiver_providers.dart';
import '../care_plan/saved_advice.dart';
import '../check/nurse_summary.dart';
import '../check/triage_screen.dart';
import '../widgets/companion.dart';

String caregiverCheckLabel(HomeCheckVerdict verdict) => switch (verdict) {
  HomeCheckVerdict.urgent => 'A danger sign was reported',
  HomeCheckVerdict.caution =>
    'Uncertainty was reported — contact a health worker',
  HomeCheckVerdict.fine => 'All danger-sign questions were answered NO',
};

class CaregiverPersonDetail extends ConsumerWidget {
  const CaregiverPersonDetail({super.key, required this.personId});
  final String personId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(caregiverScopeProvider);
    if (scope == null) return const SizedBox.shrink();
    return CompanionPage(
      title: 'Family history',
      child: ref
          .watch(caregiverClinicalProvider(scope))
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => CompanionLoadError(
              onRetry: () => ref.invalidate(caregiverClinicalProvider(scope)),
            ),
            data: (data) {
              final person = data.members
                  .where((p) => p.id == personId)
                  .firstOrNull;
              if (person == null) {
                return const Center(
                  child: Text('This family member is no longer available.'),
                );
              }
              return ref
                  .watch(caregiverActivityProvider(scope))
                  .when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (_, _) => CompanionLoadError(
                      onRetry: () =>
                          ref.invalidate(caregiverActivityProvider(scope)),
                    ),
                    data: (activity) {
                      final checks =
                          data.checks
                              .where((c) => c.personId == personId)
                              .toList()
                            ..sort(
                              (a, b) => b.checkedAt.compareTo(a.checkedAt),
                            );
                      final events =
                          <({DateTime time, String id, Widget card})>[
                            for (final check in checks)
                              (
                                time: check.checkedAt,
                                id: check.id,
                                card: CompanionCard(
                                  title: 'Home danger-sign check',
                                  eyebrow:
                                      '${caregiverWhen(check.checkedAt)} • Caregiver report',
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(caregiverCheckLabel(check.verdict)),
                                      Text(
                                        check.checkedBy == scope.userId
                                            ? 'Recorded by you'
                                            : 'Recorded by another caregiver',
                                      ),
                                      const Text(
                                        'Historical observations, not a diagnosis or today’s health status.',
                                      ),
                                      OutlinedButton(
                                        onPressed: () =>
                                            Navigator.of(context).push(
                                              GlassPageRoute<void>(
                                                builder: (_) =>
                                                    CaregiverNurseSummary(
                                                      person: person,
                                                      report: check,
                                                    ),
                                              ),
                                            ),
                                        child: const Text('Show the nurse'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            for (final m in data.milestones.where(
                              (m) => m.personId == personId,
                            ))
                              (
                                time: m.checkedAt,
                                id: m.id,
                                card: CompanionCard(
                                  title: 'Milestone observations',
                                  eyebrow:
                                      '${caregiverWhen(m.checkedAt)} • Caregiver report',
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        '${m.bandLabel} at the time of this check',
                                      ),
                                      Text(
                                        'Observed: ${m.canDo.isEmpty ? 'None recorded' : m.canDo.join('; ')}',
                                      ),
                                      Text(
                                        'Not yet: ${m.notYet.isEmpty ? 'None recorded' : m.notYet.join('; ')}',
                                      ),
                                      if (m.flags.isNotEmpty)
                                        Text(
                                          'Discuss with a health worker: ${m.flags.join('; ')}',
                                        ),
                                      const Text(
                                        'Trying a play activity does not record a milestone.',
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            for (final a in data.assessments.where(
                              (a) => a.personId == personId,
                            ))
                              (
                                time: a.performedAt,
                                id: a.id,
                                card: CompanionCard(
                                  title: 'Saved clinical plan',
                                  eyebrow:
                                      '${caregiverWhen(a.performedAt)} • From your clinic',
                                  child: ExpansionTile(
                                    title: Text(a.result.classification),
                                    children: [
                                      CaregiverSavedAdvice(
                                        key: ValueKey(a.id),
                                        person: person,
                                        assessment: a,
                                        editable: false,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            for (final a in activity.where(
                              (a) =>
                                  a.personId == personId &&
                                  {
                                    CaregiverActivityKind.note,
                                    CaregiverActivityKind.observation,
                                    CaregiverActivityKind.arrival,
                                    CaregiverActivityKind.playSession,
                                  }.contains(a.kind),
                            ))
                              (
                                time: a.occurredAt,
                                id: a.id,
                                card: CompanionCard(
                                  title: switch (a.kind) {
                                    CaregiverActivityKind.observation =>
                                      'Later observation: ${a.observation == CaregiverObservation.unsure ? 'Not sure' : a.observation?.name ?? 'Unknown'}',
                                    CaregiverActivityKind.arrival =>
                                      'Arrival reported',
                                    CaregiverActivityKind.playSession =>
                                      'Play together • ${a.done ? 'Tried' : 'Undone'}',
                                    _ => 'Your note',
                                  },
                                  eyebrow:
                                      '${caregiverWhen(a.occurredAt)} • Your local report',
                                  child: Text(
                                    '${a.note.isEmpty ? a.itemKey : a.note}\n${a.kind == CaregiverActivityKind.observation || a.kind == CaregiverActivityKind.arrival ? 'This does not clear an earlier danger sign or referral.' : 'Saved on this phone only.'}',
                                  ),
                                ),
                              ),
                          ]..sort((a, b) {
                            final time = b.time.compareTo(a.time);
                            return time == 0 ? a.id.compareTo(b.id) : time;
                          });
                      return ListView(
                        padding: const EdgeInsets.all(20),
                        children: [
                          CompanionCard(
                            title: person.fullName,
                            eyebrow: caregiverAge(person),
                            child: const Text(
                              'A dated family story. Clinic records and caregiver observations remain separate.',
                            ),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(context).push(
                              GlassPageRoute<void>(
                                builder: (_) => CaregiverTriageScreen(
                                  householdId: person.householdId,
                                  personId: person.id,
                                ),
                              ),
                            ),
                            child: const Text('Start a new check'),
                          ),
                          OutlinedButton(
                            onPressed: () => Navigator.of(context).push(
                              GlassPageRoute<void>(
                                builder: (_) => CaregiverNotePage(
                                  person: person,
                                  report: checks.firstOrNull,
                                ),
                              ),
                            ),
                            child: const Text(
                              'Add a note or later observation',
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (events.isEmpty)
                            const CompanionCard(
                              title: 'Your timeline starts here',
                              child: Text(
                                'No saved checks, milestones, clinic plans, or notes yet.',
                              ),
                            ),
                          for (final event in events)
                            KeyedSubtree(
                              key: ValueKey(event.id),
                              child: event.card,
                            ),
                        ],
                      );
                    },
                  );
            },
          ),
    );
  }
}

class CaregiverNotePage extends ConsumerStatefulWidget {
  const CaregiverNotePage({super.key, required this.person, this.report});
  final Person person;
  final HomeCheck? report;
  @override
  ConsumerState<CaregiverNotePage> createState() => _CaregiverNotePageState();
}

class _CaregiverNotePageState extends ConsumerState<CaregiverNotePage> {
  final _text = TextEditingController();
  CaregiverObservation? _observation;
  CaregiverActivity? _entry;
  bool _saving = false;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(caregiverScopeProvider);
    if (scope == null) return const SizedBox.shrink();
    final writer = ref.watch(caregiverWriterProvider(scope));
    final concern =
        _observation == CaregiverObservation.worse ||
        _observation == CaregiverObservation.unsure;
    return CompanionPage(
      title: 'Your family note',
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('${widget.person.fullName} • ${caregiverAge(widget.person)}'),
          const Text('Only saved on this phone. Not sent to a health worker.'),
          if (widget.report != null) ...[
            Text(
              'Optional observation after the check on ${caregiverWhen(widget.report!.checkedAt)}',
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final value in CaregiverObservation.values)
                  ChoiceChip(
                    label: Text(
                      value == CaregiverObservation.unsure
                          ? 'Not sure'
                          : '${value.name[0].toUpperCase()}${value.name.substring(1)}',
                    ),
                    selected: _observation == value,
                    onSelected: _saving
                        ? null
                        : (selected) => setState(() {
                            _observation = selected ? value : null;
                            _entry = null;
                          }),
                  ),
              ],
            ),
          ],
          if (concern)
            CompanionCard(
              title: 'Please seek help',
              child: Column(
                children: [
                  const Text(
                    'Worse or not sure: contact a health worker today. If very unwell or there is a danger sign, seek urgent care now. Do not wait to save this note.',
                  ),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).push(
                      GlassPageRoute<void>(
                        builder: (_) => CaregiverTriageScreen(
                          householdId: widget.person.householdId,
                          personId: widget.person.id,
                        ),
                      ),
                    ),
                    child: const Text('Check again or get urgent help'),
                  ),
                ],
              ),
            ),
          TextField(
            controller: _text,
            enabled: !_saving,
            maxLength: 500,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'What would you like to remember?',
            ),
            onChanged: (_) => _entry = null,
          ),
          const Text(
            'An improved observation never medically clears a previous danger sign.',
          ),
          CaregiverSaveAction(
            primary: true,
            label: 'Save note on this phone',
            onSave: () async {
              if (_text.text.trim().isEmpty && _observation == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Write a note or choose an observation.'),
                  ),
                );
                return;
              }
              setState(() => _saving = true);
              _entry ??= writer.entry(
                kind: _observation == null
                    ? CaregiverActivityKind.note
                    : CaregiverActivityKind.observation,
                personId: widget.person.id,
                sourceId: _observation == null ? '' : widget.report!.id,
                itemKey: _observation == null ? 'note' : 'later-observation',
                note: _text.text.trim(),
                observation: _observation,
              );
              try {
                await writer.activity(_entry!);
                if (context.mounted) Navigator.pop(context);
              } finally {
                if (mounted) setState(() => _saving = false);
              }
            },
          ),
        ],
      ),
    );
  }
}
