import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:carebridge_ai/app/providers.dart';
import 'package:carebridge_ai/core/theme/app_theme.dart';
import 'package:carebridge_ai/core/theme/lumina.dart';
import 'package:carebridge_ai/data/repositories/care_repository.dart';
import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:carebridge_ai/presentation/shared/ui.dart';
import '../caregiver_providers.dart';
import '../widgets/companion.dart';

/// The quiet honesty note that travels with each care-plan section.
Widget _sectionCaveat(IconData icon, String text) => Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Icon(icon, size: 18, color: Lumina.core),
    const SizedBox(width: 10),
    Expanded(
      child: Text(text, style: Lumina.body(size: 13, color: Lumina.inkMuted)),
    ),
  ],
);

// ----------------------------------------------------------------- Referrals

class CaregiverReferralsSection extends ConsumerWidget {
  const CaregiverReferralsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final referrals = ref.watch(openReferralsProvider);

    return referrals.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => ErrorView(error: e),
      data: (list) {
        if (list.isEmpty) return const SizedBox.shrink();
        return LumeSection(
          title: 'Referrals to complete',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionCaveat(
                Icons.local_hospital_outlined,
                'Show the saved referral details to a health worker. A code '
                'alone does not confirm that a facility can retrieve the '
                'record.',
              ),
              const SizedBox(height: 14),
              for (final r in list) _ReferralTile(referral: r),
            ],
          ),
        );
      },
    );
  }
}

class _ReferralTile extends ConsumerWidget {
  const _ReferralTile({required this.referral});

  final Referral referral;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final person = ref.watch(personProvider(referral.personId));

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: LumeWell(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Gap.md,
                    vertical: Gap.xs,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    referral.referenceCode,
                    style: const TextStyle(
                      color: Lumina.core,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text(
                    person.valueOrNull?.fullName ?? '…',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                      color: Lumina.ink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Gap.xs),
            Text(
              referral.reason,
              style: const TextStyle(fontSize: 13.5, height: 1.35),
            ),
            const SizedBox(height: Gap.xs),
            Text(
              'Go to: ${referral.facilityName} · ${referral.urgency.label} · '
              '${referral.status.label}',
              style: const TextStyle(
                fontSize: 12.5,
                color: Lumina.inkMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ Contacts

class CaregiverContactsSection extends ConsumerWidget {
  const CaregiverContactsSection({super.key, required this.householdId});

  final String householdId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts = ref.watch(householdContactsProvider(householdId));

    return contacts.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => ErrorView(error: e),
      data: (list) {
        if (list.isEmpty) return const SizedBox.shrink();
        return LumeSection(
          title: 'Appointments coming up',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionCaveat(
                Icons.event_available_rounded,
                'These are saved scheduled contacts. Check the details with '
                'your health worker; the app cannot confirm facility '
                'availability.',
              ),
              const SizedBox(height: 14),
              for (final c in list) _ContactTile(contact: c),
            ],
          ),
        );
      },
    );
  }
}

class _ContactTile extends ConsumerWidget {
  const _ContactTile({required this.contact});

  final ScheduledContact contact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final person = ref.watch(personProvider(contact.personId));
    final overdue = contact.daysUntilDue < 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Gap.sm,
              vertical: Gap.xs,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFE2EBF5)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              DateFormat('d MMM').format(contact.dueDate),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: overdue ? AppColors.triageAmber : Lumina.core,
              ),
            ),
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact.purpose,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${person.valueOrNull?.fullName ?? ''} · '
                  '${_dueLabel(contact.daysUntilDue)}',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: overdue ? AppColors.triageAmber : Lumina.inkMuted,
                    fontWeight: overdue ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _dueLabel(int days) => switch (days) {
    0 => 'today',
    1 => 'tomorrow',
    > 1 => 'in $days days',
    -1 => 'yesterday — please attend soon',
    _ => '${-days} days overdue',
  };
}

// ------------------------------------------------------------------- Barriers

/// The channel through which the family tells the system why care is hard.
/// A caregiver's "no transport money" is more reliable than any CHO guess,
/// which is why both roles hold [Permission.recordBarrier].
class CaregiverBarrierCard extends ConsumerWidget {
  const CaregiverBarrierCard({super.key, required this.householdId});

  final String householdId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final history = ref.watch(barrierHistoryProvider(householdId));

    if (user == null || !user.can(Permission.recordBarrier)) {
      return const SizedBox.shrink();
    }

    return LumeSection(
      title: 'What makes care difficult?',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionCaveat(
            Icons.report_problem_outlined,
            'Save what made care difficult. This report uses the existing '
            'clinical sync when available. Saving or syncing does not mean a '
            'health worker has read it or will respond. For urgent help, call '
            'or go to a facility.',
          ),
          const SizedBox(height: 14),
          history.when(
            loading: () => const Text('Loading earlier reports…'),
            error: (_, _) => CompanionLoadError(
              onRetry: () =>
                  ref.invalidate(barrierHistoryProvider(householdId)),
            ),
            data: (list) => list.isEmpty
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(bottom: Gap.md),
                    child: Text(
                      'You have told us about: '
                      '${list.map((b) => b.label).toSet().join(', ')}.',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Lumina.inkMuted,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Lumina.core,
              side: BorderSide(color: Lumina.core.withValues(alpha: 0.45)),
            ),
            onPressed: () => _report(context, ref),
            icon: const Icon(Icons.add_comment_outlined),
            label: const Text('Report a difficulty'),
          ),
        ],
      ),
    );
  }

  Future<void> _report(BuildContext context, WidgetRef ref) async {
    final ownerId = ref.read(currentUserProvider)?.id;
    if (ownerId == null) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _BarrierSheet(householdId: householdId, ownerId: ownerId),
    );
    if (saved == true && context.mounted) {
      ref.invalidate(barrierHistoryProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Report saved. This does not confirm anyone has read it.',
          ),
        ),
      );
    }
  }
}

class _BarrierSheet extends ConsumerStatefulWidget {
  const _BarrierSheet({required this.householdId, required this.ownerId});

  final String householdId;
  final String ownerId;

  @override
  ConsumerState<_BarrierSheet> createState() => _BarrierSheetState();
}

class _BarrierSheetState extends ConsumerState<_BarrierSheet> {
  final Set<CareBarrier> _chosen = {};
  final _notes = TextEditingController();
  bool _busy = false;
  String? _error;
  BarrierReport? _pending;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final user = ref.read(currentUserProvider);
    if (_busy ||
        user == null ||
        user.id != widget.ownerId ||
        ref.read(caregiverScopeProvider)?.householdId != widget.householdId) {
      return;
    }
    if (_chosen.isEmpty) {
      setState(() => _error = 'Choose at least one difficulty.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    final report = _pending ??= BarrierReport(
      id: const Uuid().v4(),
      householdId: widget.householdId,
      barriers: _chosen.toList(growable: false),
      recordedBy: user.id,
      recordedAt: DateTime.now(),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    );

    try {
      await ref.read(careRepositoryProvider).recordBarrier(user, report);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AccessDenied catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not save — please retry.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(caregiverScopeProvider);
    if (scope?.userId != widget.ownerId ||
        scope?.householdId != widget.householdId) {
      return const SafeArea(
        child: Text('Your account changed. Close this form.'),
      );
    }
    return Padding(
      padding: EdgeInsets.only(
        left: Gap.lg,
        right: Gap.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + Gap.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'What stood in the way?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: Gap.sm),
            const Text(
              'Choose everything that applies. There are no wrong answers and '
              'nothing here is a complaint against you.',
              style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
            ),
            const SizedBox(height: Gap.md),
            for (final barrier in CareBarrier.values)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _chosen.contains(barrier),
                title: Text(
                  barrier.label,
                  style: const TextStyle(fontSize: 14.5),
                ),
                onChanged: _busy
                    ? null
                    : (v) => setState(() {
                        _pending = null;
                        v == true
                            ? _chosen.add(barrier)
                            : _chosen.remove(barrier);
                      }),
              ),
            TextField(
              controller: _notes,
              enabled: !_busy,
              onChanged: (_) => _pending = null,
              maxLength: 1000,
              maxLines: 2,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Anything else (optional)',
              ),
            ),
            const SizedBox(height: Gap.md),
            if (_error != null) ...[
              Text(
                _error!,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.triageRed,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: Gap.md),
            ],
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.send_rounded),
              label: Text(_busy ? 'Saving…' : 'Save difficulty report'),
            ),
            const SizedBox(height: Gap.lg),
          ],
        ),
      ),
    );
  }
}
