/// Records a family's report, separately from staff-verified arrival.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/core.dart';
import '../../domain/entities/visit.dart';
import '../../domain/enums.dart';
import '../shared/ui.dart';
import 'clinic_widgets.dart';

class FollowUpCheckInScreen extends ConsumerStatefulWidget {
  const FollowUpCheckInScreen({super.key, required this.referral});

  final Referral referral;

  @override
  ConsumerState<FollowUpCheckInScreen> createState() =>
      _FollowUpCheckInScreenState();
}

class _FollowUpCheckInScreenState extends ConsumerState<FollowUpCheckInScreen> {
  _FollowUpOutcome? _outcome;
  final Set<CareBarrier> _barriers = {};
  final _notes = TextEditingController();
  bool _busy = false;
  bool _statusSaved = false;
  BarrierReport? _pendingBarrier;
  String? _error;
  late final Future<_LoopContext> _loop;

  @override
  void initState() {
    super.initState();
    _loop = _loadLoop();
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<_LoopContext> _loadLoop() async {
    Assessment? origin;
    Assessment? reassessment;
    GrowthMeasurement? baseline;
    GrowthMeasurement? since;
    final user = ref.read(currentUserProvider);
    if (user != null) {
      final repository = ref.read(careRepositoryProvider);
      try {
        final history = await repository.assessmentHistory(
          user,
          widget.referral.personId,
        );
        for (final assessment in history) {
          if (assessment.id == widget.referral.assessmentId) {
            origin = assessment;
          }
          if (assessment.id != widget.referral.assessmentId &&
              assessment.performedAt.isAfter(widget.referral.issuedAt) &&
              (reassessment == null ||
                  assessment.performedAt.isAfter(reassessment.performedAt))) {
            reassessment = assessment;
          }
        }
      } catch (_) {
        // Context is best-effort; missing history must not block a report.
      }
      try {
        final series = await repository.growthSeries(
          user,
          widget.referral.personId,
        );
        for (final measurement in series) {
          if (measurement.takenAt.isAfter(widget.referral.issuedAt)) {
            if (since == null || measurement.takenAt.isAfter(since.takenAt)) {
              since = measurement;
            }
          } else if (baseline == null ||
              measurement.takenAt.isAfter(baseline.takenAt)) {
            baseline = measurement;
          }
        }
      } catch (_) {
        // Only show measurements this account can read.
      }
    }
    return _LoopContext(origin, reassessment, baseline, since);
  }

  void _refresh() {
    ref.invalidate(openReferralsProvider);
    ref.invalidate(dayPlanProvider);
    ref.invalidate(referralCompletionProvider);
    final householdId = _pendingBarrier?.householdId;
    if (householdId != null) {
      ref.invalidate(barrierHistoryProvider(householdId));
    }
  }

  Future<void> _save() async {
    if (_busy || _outcome == null) return;
    final user = ref.read(currentUserProvider);
    if (user == null) {
      setState(() => _error = 'Sign in again before saving this follow-up.');
      return;
    }
    final outcome = _outcome!;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final repository = ref.read(careRepositoryProvider);
      if (!_statusSaved) {
        final reportNotes = [
          'Self-reported, not facility-verified.',
          'Outcome: ${outcome.label}',
          if (_notes.text.trim().isNotEmpty) 'Notes: ${_notes.text.trim()}',
        ].join('\n');
        _pendingBarrier = null;
        // Resolve the household before writing anything: never silently drop
        // selected barriers when the patient record is unavailable.
        if (outcome.collectBarriers && _barriers.isNotEmpty) {
          final person = await repository.person(
            user,
            widget.referral.personId,
          );
          if (person == null) {
            throw StateError(
              'Patient record unavailable; barriers were not saved.',
            );
          }
          _pendingBarrier = BarrierReport(
            id: const Uuid().v4(),
            householdId: person.householdId,
            personId: person.id,
            referralId: widget.referral.id,
            barriers: _barriers.toList(),
            recordedBy: user.id,
            recordedAt: DateTime.now(),
            notes: reportNotes,
          );
        }
        await repository.updateReferralStatus(
          user,
          referralId: widget.referral.id,
          status: outcome.status ?? widget.referral.status,
          outcomeNotes: [
            if (widget.referral.outcomeNotes?.trim().isNotEmpty ?? false)
              widget.referral.outcomeNotes!,
            reportNotes,
          ].join('\n\n'),
        );
        _statusSaved = true;
        if (mounted) _refresh();
      }
      // These APIs are separate writes. Keep the report ID and form frozen
      // after the first write so a retry does not duplicate the outcome.
      if (_pendingBarrier != null) {
        await repository.recordBarrier(user, _pendingBarrier!);
      }
      if (!mounted) return;
      _refresh();
      setState(() => _busy = false);
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.white,
          scrollable: true,
          title: Text(outcome.confirmationTitle),
          content: Text(
            'Saved locally. Self-reported, not facility-verified.\n\n'
            '${outcome.confirmationDetail}',
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _statusSaved
            ? 'Follow-up saved locally, but barriers were not saved. '
                  'Retry to save the barriers; your choices are kept.'
            : 'Could not save follow-up. Your answers are kept. Please retry.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final person = ref.watch(personProvider(widget.referral.personId));
    final locked = _busy || _statusSaved;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(title: const Text('Record follow-up')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(Gap.md),
            children: [
              ClinicCard(
                title: person.valueOrNull?.fullName ?? 'Referral follow-up',
                subtitle:
                    '${widget.referral.referenceCode} · ${widget.referral.facilityName}',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(widget.referral.reason, style: AppType.body),
                    const SizedBox(height: Gap.sm),
                    const ClinicStatusLine(
                      text:
                          'Record what the family reports. This does not verify '
                          'arrival or treatment with the facility.',
                      icon: Icons.info_outline_rounded,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Gap.md),
              FutureBuilder<_LoopContext>(
                future: _loop,
                builder: (context, snapshot) => snapshot.hasData
                    ? _ReferralContextCard(
                        referral: widget.referral,
                        loop: snapshot.data!,
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: Gap.md),
              ClinicCard(
                title: 'What did the family report?',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final outcome in _FollowUpOutcome.values)
                      _ChoiceTile(
                        label: outcome.label,
                        selected: _outcome == outcome,
                        onTap: locked
                            ? null
                            : () => setState(() => _outcome = outcome),
                      ),
                    if (_outcome == _FollowUpOutcome.unknown)
                      const Text(
                        'Status stays unchanged. Follow up again when '
                        'the outcome is known; no travel or arrival is assumed.',
                      ),
                  ],
                ),
              ),
              if (_outcome?.collectBarriers ?? false) ...[
                const SizedBox(height: Gap.md),
                ClinicCard(
                  title: 'What made care difficult?',
                  subtitle:
                      'Select any reported barriers to help plan the next contact.',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final barrier in CareBarrier.values)
                        _ChoiceTile(
                          label: barrier.label,
                          selected: _barriers.contains(barrier),
                          multiple: true,
                          onTap: locked
                              ? null
                              : () => setState(() {
                                  if (!_barriers.add(barrier)) {
                                    _barriers.remove(barrier);
                                  }
                                }),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: Gap.md),
              ClinicCard(
                title: 'Notes',
                child: TextField(
                  controller: _notes,
                  enabled: !locked,
                  minLines: 3,
                  maxLines: 6,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText:
                        'Optional: who you spoke to, what they said, next contact',
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: Gap.md),
                Semantics(
                  liveRegion: true,
                  child: ClinicStatusLine(
                    text: _error!,
                    icon: Icons.error_outline_rounded,
                  ),
                ),
              ],
              const SizedBox(height: Gap.lg),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(48, 48),
                  padding: const EdgeInsets.all(Gap.md),
                ),
                onPressed: _busy || _outcome == null ? null : _save,
                child: Text(
                  _busy
                      ? 'Saving…'
                      : _error != null
                      ? 'Retry save'
                      : 'Save follow-up',
                ),
              ),
              const SizedBox(height: Gap.sm),
              TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).pop(_statusSaved),
                child: Text(
                  _statusSaved ? 'Close (barriers not saved)' : 'Cancel',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _FollowUpOutcome {
  arrived(
    'Yes — reached the facility',
    ReferralStatus.arrived,
    'Arrival reported',
    'Treatment has not been established. Follow up on care received.',
  ),
  untreated(
    'Reached the facility — not treated',
    ReferralStatus.arrived,
    'Arrival reported',
    'No treatment reported. Follow up on barriers and care still needed.',
  ),
  treated(
    'Treatment received — reported by family',
    ReferralStatus.treated,
    'Treatment reported',
    'Treatment was reported by the family, not verified by facility staff.',
  ),
  no(
    'No — did not go',
    ReferralStatus.didNotAttend,
    'Nonattendance reported',
    'Plan another contact and address any reported barriers.',
  ),
  unknown(
    "Don't know yet",
    null,
    'Follow-up recorded',
    'Referral status unchanged. The outcome still needs follow-up.',
  );

  const _FollowUpOutcome(
    this.label,
    this.status,
    this.confirmationTitle,
    this.confirmationDetail,
  );
  final String label;
  final ReferralStatus? status;
  final String confirmationTitle;
  final String confirmationDetail;
  bool get collectBarriers => this == untreated || this == no;
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.label,
    required this.selected,
    this.onTap,
    this.multiple = false,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final bool multiple;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Gap.sm),
    child: Semantics(
      checked: selected,
      inMutuallyExclusiveGroup: !multiple,
      enabled: onTap != null,
      child: Material(
        color: selected ? AppColors.primaryLight : Colors.white,
        borderRadius: BorderRadius.circular(Gap.radiusSm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Gap.radiusSm),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.all(Gap.md),
            decoration: BoxDecoration(
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.line,
              ),
              borderRadius: BorderRadius.circular(Gap.radiusSm),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  multiple
                      ? (selected
                            ? Icons.check_box
                            : Icons.check_box_outline_blank)
                      : (selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked),
                  color: selected ? AppColors.primary : AppColors.inkMuted,
                ),
                const SizedBox(width: Gap.sm),
                Expanded(child: Text(label, style: AppType.body)),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _LoopContext {
  const _LoopContext(
    this.origin,
    this.reassessment,
    this.baselineGrowth,
    this.sinceGrowth,
  );
  final Assessment? origin;
  final Assessment? reassessment;
  final GrowthMeasurement? baselineGrowth;
  final GrowthMeasurement? sinceGrowth;
}

/// Read-only assessment and growth context, not evidence of referral completion.
class _ReferralContextCard extends StatelessWidget {
  const _ReferralContextCard({required this.referral, required this.loop});
  final Referral referral;
  final _LoopContext loop;

  @override
  Widget build(BuildContext context) {
    final origin = loop.origin;
    final reassessed = loop.reassessment;
    final base = loop.baselineGrowth;
    final since = loop.sinceGrowth;
    return ClinicCard(
      title: 'Referral context',
      subtitle:
          'Issued ${DateFormat('d MMM yyyy, HH:mm').format(referral.issuedAt.toLocal())}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (origin != null) ...[
            Text(
              'Original assessment: ${origin.result.classification}',
              style: AppType.body,
            ),
            Text(
              origin.effectiveTriage.label,
              style: AppType.label.copyWith(
                color: triageColours(origin.effectiveTriage).fg,
              ),
            ),
          ],
          if (reassessed != null) ...[
            const SizedBox(height: Gap.sm),
            Text(
              'Re-assessed ${DateFormat('d MMM yyyy').format(reassessed.performedAt)}: '
              '${reassessed.result.classification}',
              style: AppType.body,
            ),
            Text(
              reassessed.effectiveTriage.label,
              style: AppType.label.copyWith(
                color: triageColours(reassessed.effectiveTriage).fg,
              ),
            ),
          ] else
            const Text('No re-assessment available since referral.'),
          if (base?.weightKg != null && since?.weightKg != null)
            _measurement('Weight', base!.weightKg!, since!.weightKg!, 'kg'),
          if (base?.muacCm != null && since?.muacCm != null)
            _measurement('MUAC', base!.muacCm!, since!.muacCm!, 'cm'),
        ],
      ),
    );
  }

  Widget _measurement(
    String label,
    double before,
    double after,
    String unit,
  ) => Padding(
    padding: const EdgeInsets.only(top: Gap.sm),
    child: Text(
      '$label: ${before.toStringAsFixed(1)} → ${after.toStringAsFixed(1)} $unit '
      '(change ${(after - before).toStringAsFixed(1)} $unit)',
      style: AppType.body,
    ),
  );
}
