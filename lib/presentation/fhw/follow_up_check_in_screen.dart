/// Follow-up check-in (Screen 75).
///
/// Records whether a referred family reached the facility, and if not, why.
/// A "No" or "Partially" answer updates the referral status and re-flags the
/// household on the priority list instead of letting it quietly disappear.
///
/// The screen opens with the closed loop: the verdict that issued the
/// referral, any re-assessment since, and any new measurements — so the
/// question "did they reach the facility?" is asked about a story the CHO
/// can see, not a code they have to remember.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/local/household_dao.dart';
import '../../data/local/visit_dao.dart';
import '../../domain/entities/core.dart';
import '../../domain/entities/visit.dart';
import '../../domain/enums.dart';
import '../shared/ui.dart';

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
  String? _error;

  /// The closed loop behind this referral: the assessment that issued it,
  /// any re-assessment since, and the newest measurements on either side
  /// of the referral date. Loaded once, read-only, best-effort — a missing
  /// record quietly narrows the card instead of blocking the check-in.
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
    try {
      origin = await AssessmentDao.byId(widget.referral.assessmentId);
    } catch (_) {}
    Assessment? reassessment;
    try {
      final latest = await AssessmentDao.latestForPerson(
        widget.referral.personId,
      );
      if (latest != null &&
          latest.id != widget.referral.assessmentId &&
          latest.performedAt.isAfter(widget.referral.issuedAt)) {
        reassessment = latest;
      }
    } catch (_) {}
    GrowthMeasurement? baseline;
    GrowthMeasurement? since;
    final user = ref.read(currentUserProvider);
    if (user != null) {
      try {
        final series = await ref
            .read(careRepositoryProvider)
            .growthSeries(user, widget.referral.personId);
        for (final m in series) {
          if (m.takenAt.isAfter(widget.referral.issuedAt)) {
            since = m;
          } else {
            baseline = m;
          }
        }
      } catch (_) {
        // No growth history this account may see; the loop card simply
        // shows the verdicts without the numbers.
      }
    }
    return _LoopContext(
      origin: origin,
      reassessment: reassessment,
      baselineGrowth: baseline,
      sinceGrowth: since,
    );
  }

  Future<void> _save() async {
    final user = ref.read(currentUserProvider);
    if (user == null || _outcome == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final status = _outcome!.status;
      await ReferralDao.updateStatus(
        referralId: widget.referral.id,
        status: status,
        outcomeNotes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      );

      // If the family did not fully attend, capture the barriers so the next
      // contact can address them and the household stays visible.
      if (status.isFailure && _barriers.isNotEmpty) {
        final person = await PersonDao.byId(widget.referral.personId);
        final householdId = person?.householdId;
        if (householdId != null) {
          await BarrierDao.save(
            BarrierReport(
              id: const Uuid().v4(),
              householdId: householdId,
              referralId: widget.referral.id,
              barriers: _barriers.toList(),
              recordedBy: user.id,
              recordedAt: DateTime.now(),
              notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            ),
          );
        }
      }

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not save follow-up: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Follow-up check-in')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Gap.lg),
          children: [
            // The closed loop first: what this referral set out to do, and
            // what has happened since — so the check-in reads as the end
            // of a story, not the start of a form.
            FutureBuilder<_LoopContext>(
              future: _loop,
              builder: (context, snapshot) {
                final loop = snapshot.data;
                if (loop == null) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: Gap.md),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      ),
                    ),
                  );
                }
                return _ClosedLoopCard(referral: widget.referral, loop: loop);
              },
            ),
            const SizedBox(height: Gap.lg),
            SectionCard(
              title: 'Did the family reach the facility?',
              subtitle:
                  '${widget.referral.referenceCode} · ${widget.referral.facilityName}',
              icon: Icons.contact_phone_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final o in _FollowUpOutcome.values)
                    _OutcomeTile(
                      outcome: o,
                      selected: _outcome == o,
                      onTap: () => setState(() => _outcome = o),
                    ),
                ],
              ),
            ),
            if (_outcome != null && _outcome!.status.isFailure) ...[
              const SizedBox(height: Gap.lg),
              SectionCard(
                title: 'What made it hard this time?',
                subtitle:
                    'Choose the barriers that apply. This re-flags the household '
                    'on the priority list.',
                icon: Icons.signpost_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final barrier in CareBarrier.values)
                      _BarrierChip(
                        barrier: barrier,
                        selected: _barriers.contains(barrier),
                        onTap: () {
                          setState(() {
                            if (_barriers.contains(barrier)) {
                              _barriers.remove(barrier);
                            } else {
                              _barriers.add(barrier);
                            }
                          });
                        },
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: Gap.lg),
            SectionCard(
              title: 'Notes',
              icon: Icons.notes_outlined,
              child: TextField(
                controller: _notes,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Optional: who you spoke to, what they said',
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: Gap.lg),
              _ErrorBox(_error!),
            ],
            const SizedBox(height: Gap.xl),
            FilledButton(
              onPressed: _busy || _outcome == null ? null : _save,
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Save follow-up'),
            ),
            const SizedBox(height: Gap.md),
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            const SizedBox(height: Gap.xl),
          ],
        ),
      ),
    );
  }
}

enum _FollowUpOutcome {
  yes('Yes — reached the facility', ReferralStatus.arrived),
  partially(
    'Partially — went but did not get treated',
    ReferralStatus.didNotAttend,
  ),
  no('No — did not go', ReferralStatus.didNotAttend),
  unknown('Don\'t know yet', ReferralStatus.travelling);

  const _FollowUpOutcome(this.label, this.status);
  final String label;
  final ReferralStatus status;
}

class _OutcomeTile extends StatelessWidget {
  const _OutcomeTile({
    required this.outcome,
    required this.selected,
    required this.onTap,
  });

  final _FollowUpOutcome outcome;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
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
              SizedBox(
                width: 24,
                height: 24,
                child: selected
                    ? Icon(
                        Icons.radio_button_checked_rounded,
                        color: AppColors.accent,
                      )
                    : Icon(
                        Icons.radio_button_unchecked_rounded,
                        color: AppColors.inkFaint,
                      ),
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text(
                  outcome.label,
                  style: AppType.label.copyWith(fontSize: 14.5),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _BarrierChip extends StatelessWidget {
  const _BarrierChip({
    required this.barrier,
    required this.selected,
    required this.onTap,
  });

  final CareBarrier barrier;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Gap.xs),
    child: FilterChip(
      label: Text(barrier.label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.primaryLight,
      checkmarkColor: AppColors.accent,
      side: BorderSide(color: selected ? AppColors.accent : AppColors.line),
    ),
  );
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox(this.message);

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
              fontSize: 13.5,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Everything the check-in needs to close the loop, loaded best-effort.
class _LoopContext {
  const _LoopContext({
    required this.origin,
    required this.reassessment,
    required this.baselineGrowth,
    required this.sinceGrowth,
  });

  /// The assessment that issued the referral.
  final Assessment? origin;

  /// A newer assessment for this person since the referral, if any.
  final Assessment? reassessment;

  /// Last measurement on or before the referral date.
  final GrowthMeasurement? baselineGrowth;

  /// Newest measurement after the referral date.
  final GrowthMeasurement? sinceGrowth;
}

/// The story this check-in closes: the verdict that issued the referral,
/// any re-assessment since (improving or not), and the measurements on
/// either side of the referral date. A referral nobody checks is a
/// referral into the void — this card makes the loop visible.
class _ClosedLoopCard extends StatelessWidget {
  const _ClosedLoopCard({required this.referral, required this.loop});

  final Referral referral;
  final _LoopContext loop;

  static String _day(DateTime d) => DateFormat('d MMM yyyy').format(d);

  static Widget _pill(TriageLevel level) {
    final c = triageColours(level);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.fg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        level.name.toUpperCase(),
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: Colors.white,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final origin = loop.origin;
    final accent = origin == null
        ? AppColors.primary
        : triageColours(origin.effectiveTriage).fg;
    final reassessed = loop.reassessment;
    final improving =
        reassessed != null &&
        origin != null &&
        reassessed.effectiveTriage.index > origin.effectiveTriage.index;
    final worsening =
        reassessed != null &&
        origin != null &&
        reassessed.effectiveTriage.index < origin.effectiveTriage.index;
    final base = loop.baselineGrowth;
    final since = loop.sinceGrowth;
    final hasWeight = base?.weightKg != null && since?.weightKg != null;
    final hasMuac = base?.muacCm != null && since?.muacCm != null;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Gap.radius),
        border: Border.all(color: AppColors.line, width: Gap.hairline),
        boxShadow: const [AppShadows.card],
      ),
      child: AccentEdge(
        accent: accent,
        width: 3,
        borderRadius: BorderRadius.circular(Gap.radius),
        child: Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceTint,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.loop_rounded,
                      size: 20,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'THE LOOP THIS CHECK-IN CLOSES',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                            color: AppColors.inkMuted,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Referral ${referral.referenceCode} · issued '
                          '${_day(referral.issuedAt)}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // ---- The verdict that started the loop
              const SizedBox(height: Gap.sm),
              Row(
                children: [
                  if (origin != null) _pill(origin.effectiveTriage),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: Text(
                      referral.reason,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Sent to ${referral.facilityName} · '
                '${referral.urgency.label.toLowerCase()}',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.inkMuted,
                  height: 1.4,
                ),
              ),

              // ---- Any re-assessment since
              if (reassessed != null) ...[
                const SizedBox(height: Gap.md),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(Gap.sm + 2),
                  decoration: BoxDecoration(
                    color: AppColors.canvas,
                    borderRadius: BorderRadius.circular(Gap.radiusSm),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.event_repeat_outlined,
                            size: 15,
                            color: AppColors.inkMuted,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Re-assessed ${_day(reassessed.performedAt)}',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.inkMuted,
                              ),
                            ),
                          ),
                          _pill(reassessed.effectiveTriage),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        improving
                            ? 'The verdict has eased since the referral — '
                                  'check what the facility did and keep the '
                                  'follow-up.'
                            : worsening
                            ? 'The verdict has worsened since the referral — '
                                  'if the family has not been treated, this '
                                  'visit is the safety net.'
                            : 'The verdict is unchanged since the referral — '
                                  'whether the family got treated is what '
                                  'this check-in decides.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.ink,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // ---- Measurements on either side of the referral
              if (hasWeight || hasMuac) ...[
                const SizedBox(height: Gap.sm),
                if (hasWeight)
                  _deltaRow(
                    'Weight',
                    '${base!.weightKg!.toStringAsFixed(1)} kg',
                    '${since!.weightKg!.toStringAsFixed(1)} kg',
                    since.weightKg! - base.weightKg!,
                    1,
                    'kg',
                  ),
                if (hasMuac)
                  _deltaRow(
                    'MUAC',
                    '${base!.muacCm!.toStringAsFixed(1)} cm',
                    '${since!.muacCm!.toStringAsFixed(1)} cm',
                    since.muacCm! - base.muacCm!,
                    1,
                    'cm',
                  ),
              ],

              // ---- The honest quiet line
              if (reassessed == null && !hasWeight && !hasMuac) ...[
                const SizedBox(height: Gap.md),
                const Text(
                  'No re-assessment recorded since — what you learn today '
                  'is the only follow-up this referral gets.',
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: AppColors.inkMuted,
                    height: 1.45,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// One before → after measurement line with the honest arithmetic.
  Widget _deltaRow(
    String label,
    String before,
    String after,
    double delta,
    int decimals,
    String unit,
  ) {
    final gain = delta >= 0;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppColors.inkMuted,
              ),
            ),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: '$before  →  $after',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: (gain ? AppColors.triageGreen : AppColors.triageRed)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${gain ? '+' : ''}${delta.toStringAsFixed(decimals)} $unit',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: gain ? AppColors.triageGreen : AppColors.triageRed,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
