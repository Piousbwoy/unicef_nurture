/// Review only this clinic session's saved records before closing it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/local/visit_dao.dart' show VisitParticipant;
import '../../data/repositories/care_repository.dart';
import '../../domain/entities/visit.dart';
import '../fhw/clinic_widgets.dart';
import '../shared/ui.dart';

class HouseholdSummaryScreen extends ConsumerStatefulWidget {
  const HouseholdSummaryScreen({
    super.key,
    required this.visit,
    required this.householdId,
    required this.assessedIds,
    this.notes,
    this.participants,
    this.assessments,
    this.omissionReason,
    this.onOmissionReasonChanged,
  });

  final Visit visit;
  final String householdId;

  /// Retained for existing callers. Never used as proof of a saved assessment.
  final List<String> assessedIds;
  final String? notes;

  /// Snapshots read from the repository by the queue. Older entry points can
  /// omit these; review will fetch the persisted roll and session history.
  final List<VisitParticipant>? participants;
  final List<Assessment>? assessments;
  final String? omissionReason;
  final ValueChanged<String>? onOmissionReasonChanged;

  @override
  ConsumerState<HouseholdSummaryScreen> createState() =>
      _HouseholdSummaryScreenState();
}

class _HouseholdSummaryScreenState
    extends ConsumerState<HouseholdSummaryScreen> {
  final _reason = TextEditingController();
  List<VisitParticipant> _roll = [];
  List<Assessment> _assessments = [];
  bool _loading = true;
  bool _saving = false;
  bool _loadFailed = false;
  String? _error;

  Set<String> get _savedIds => _assessments.map((a) => a.personId).toSet();
  List<VisitParticipant> get _pending => _roll
      .where((p) => p.wasPresent && !_savedIds.contains(p.personId))
      .toList();
  List<VisitParticipant> get _absent =>
      _roll.where((p) => !p.wasPresent).toList();

  @override
  void initState() {
    super.initState();
    _reason.text = widget.omissionReason ?? '';
    if (widget.participants != null && widget.assessments != null) {
      _adopt(widget.participants!, widget.assessments!);
      _loading = false;
    } else {
      Future.microtask(_load);
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _adopt(List<VisitParticipant> roll, List<Assessment> assessments) {
    _roll = roll.where((p) => p.visitId == widget.visit.id).toList()
      ..sort((a, b) => a.queueOrder.compareTo(b.queueOrder));
    final ids = _roll.map((p) => p.personId).toSet();
    _assessments =
        assessments
            .where(
              (a) => a.visitId == widget.visit.id && ids.contains(a.personId),
            )
            .toList()
          ..sort((a, b) => b.performedAt.compareTo(a.performedAt));
  }

  Future<void> _readRecords() async {
    final user = ref.read(currentUserProvider);
    if (user == null) throw StateError('Sign in required');
    final repository = ref.read(careRepositoryProvider);
    final roll = await repository.rollCall(user, widget.visit.id);
    final histories = await Future.wait([
      for (final p in roll) repository.assessmentHistory(user, p.personId),
    ]);
    if (mounted)
      setState(() => _adopt(roll, histories.expand((h) => h).toList()));
  }

  Future<void> _load() async {
    if (_saving) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _readRecords();
      if (mounted) setState(() => _loadFailed = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadFailed = true;
          _error = e is AccessDenied
              ? e.message
              : 'Could not load the session records. Retry before closing.';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving || _loading || _loadFailed) return;
    final user = ref.read(currentUserProvider);
    if (user == null) {
      setState(() => _error = 'Sign in again to close this session.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // Re-read before closing, including callers that supplied a snapshot.
      await _readRecords();
      if (!mounted) return;
      if (_pending.isNotEmpty && _reason.text.trim().isEmpty) {
        setState(
          () => _error =
              'Add a reason for the people here without a saved assessment, or return to the queue.',
        );
        return;
      }
      final note = widget.notes ?? widget.visit.notes ?? '';
      final omissions = _pending.isEmpty
          ? ''
          : 'Not assessed this session (${_pending.length} present; person IDs: ${_pending.map((p) => p.personId).join(', ')}): ${_reason.text.trim()}';
      final combined = [
        note.trim(),
        omissions,
      ].where((s) => s.isNotEmpty).join('\n\n');
      await ref
          .read(careRepositoryProvider)
          .completeVisit(user, widget.visit.id, notes: combined);
      if (!mounted) return;
      ref.invalidate(dayPlanProvider);
      ref.invalidate(visitHistoryProvider(widget.householdId));
      ref.invalidate(openReferralsProvider);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted)
        setState(
          () => _error = e is AccessDenied
              ? e.message
              : 'Could not close the session. It remains open. Your note is still here; retry when ready.',
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final household = ref.watch(householdProvider(widget.householdId));
    final referrals = ref.watch(openReferralsProvider);
    final assessmentIds = _assessments.map((a) => a.id).toSet();
    final sessionReferrals = (referrals.valueOrNull ?? <Referral>[])
        .where((r) => assessmentIds.contains(r.assessmentId))
        .toList();
    final latestByPerson = <String, Assessment>{};
    for (final assessment in _assessments) {
      latestByPerson.putIfAbsent(assessment.personId, () => assessment);
    }
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          title: const Text('Review session'),
          leading: BackButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const ClinicStepHeader(
                    steps: [
                      'Household record',
                      'Who is here',
                      'Assessment queue',
                      'Review session',
                    ],
                    current: 3,
                  ),
                  ClinicCard(
                    title: household.valueOrNull?.name ?? 'Household session',
                    subtitle: 'Review this clinic encounter before closing.',
                    child: Text(
                      '${_savedIds.length} assessment${_savedIds.length == 1 ? '' : 's'} saved\n'
                      '${_pending.length} pending assessment${_pending.length == 1 ? '' : 's'}\n'
                      '${_absent.length} not here',
                      style: AppType.body.copyWith(color: AppColors.ink),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_loadFailed) ...[
                    ClinicStatusLine(text: _error!, icon: Icons.info_outline),
                    OutlinedButton(
                      onPressed: _load,
                      child: const Text('Retry loading session'),
                    ),
                  ] else ...[
                    ClinicCard(
                      title: 'Saved assessments',
                      subtitle:
                          'Only results saved in this session. Clinical urgency is shown separately.',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (latestByPerson.isEmpty)
                            const Text('No assessments saved in this session.'),
                          for (final p in _roll)
                            if (latestByPerson[p.personId]
                                case final assessment?)
                              _SummaryTile(assessment: assessment),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    ClinicCard(
                      title: 'Pending assessment (${_pending.length})',
                      subtitle:
                          'Here today, without a saved assessment. Attendance will remain recorded as present.',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_pending.isEmpty)
                            const Text('No pending assessments.'),
                          for (final p in _pending)
                            _ParticipantLine(participant: p),
                          if (_pending.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            TextField(
                              key: const ValueKey('omission-reason'),
                              controller: _reason,
                              enabled: !_saving,
                              minLines: 2,
                              maxLines: null,
                              onChanged: widget.onOmissionReasonChanged,
                              decoration: const InputDecoration(
                                labelText: 'Reason for omitted assessments',
                                hintText:
                                    'Explain why these people were not assessed and any follow-up agreed.',
                                helperText:
                                    'Required to close with pending assessments.',
                                helperMaxLines: 4,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    ClinicCard(
                      title: 'Not here (${_absent.length})',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_absent.isEmpty)
                            const Text('No absences on the session roll.'),
                          for (final p in _absent)
                            _ParticipantLine(participant: p),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    ClinicCard(
                      title: 'Open referrals from this session',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (referrals.isLoading)
                            const Text('Loading referrals…')
                          else if (referrals.hasError) ...[
                            const Text(
                              'Could not load referrals. This does not mean there are none.',
                            ),
                            OutlinedButton(
                              onPressed: () =>
                                  ref.invalidate(openReferralsProvider),
                              child: const Text('Retry referrals'),
                            ),
                          ] else if (sessionReferrals.isEmpty)
                            const Text(
                              'No open referrals linked to these assessments.',
                            ),
                          for (final referral in sessionReferrals)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    referral.referenceCode,
                                    style: AppType.label,
                                  ),
                                  Text(referral.facilityName),
                                  Text(referral.urgency.label),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    if ((widget.notes ?? widget.visit.notes)
                            ?.trim()
                            .isNotEmpty ==
                        true) ...[
                      const SizedBox(height: 20),
                      ClinicCard(
                        title: 'Clinic note',
                        child: Text(
                          (widget.notes ?? widget.visit.notes)!.trim(),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    const ClinicStatusLine(
                      text:
                          'Saved assessments are kept on this device. The session and clinic note are signed off only after Save & close succeeds.',
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      ClinicStatusLine(text: _error!, icon: Icons.info_outline),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: Text(
                        _saving ? 'Closing session…' : 'Save & close session',
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Return to assessment queue'),
                    ),
                  ],
                  const SizedBox(height: 20),
                ],
              ),
      ),
    );
  }
}

class _ParticipantLine extends ConsumerWidget {
  const _ParticipantLine({required this.participant});
  final VisitParticipant participant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final person = ref.watch(personProvider(participant.personId));
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        '${person.valueOrNull?.fullName ?? 'Household member (${participant.personId})'}${participant.absenceNote?.trim().isNotEmpty == true ? ' — ${participant.absenceNote}' : ''}',
      ),
    );
  }
}

class _SummaryTile extends ConsumerWidget {
  const _SummaryTile({required this.assessment});
  final Assessment assessment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final person = ref.watch(personProvider(assessment.personId));
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            person.valueOrNull?.fullName ??
                'Household member (${assessment.personId})',
            style: AppType.label,
          ),
          const SizedBox(height: 8),
          const Text(
            'Assessment saved',
            style: TextStyle(
              color: AppColors.primaryDark,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          TriageBadge(assessment.effectiveTriage),
          const SizedBox(height: 8),
          Text(assessment.result.classification),
        ],
      ),
    );
  }
}
