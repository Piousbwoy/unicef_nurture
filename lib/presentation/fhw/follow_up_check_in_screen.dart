/// Follow-up check-in (Screen 75).
///
/// Records whether a referred family reached the facility, and if not, why.
/// A "No" or "Partially" answer updates the referral status and re-flags the
/// household on the priority list instead of letting it quietly disappear.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/local/household_dao.dart';
import '../../data/local/visit_dao.dart';
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

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
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
      side: BorderSide(
        color: selected ? AppColors.accent : AppColors.line,
      ),
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
