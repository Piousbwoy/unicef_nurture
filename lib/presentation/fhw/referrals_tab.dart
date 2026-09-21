/// Referral follow-up: family reports and staff confirmation are distinct actions.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/visit.dart';
import '../../domain/enums.dart';
import '../shared/ui.dart';
import '../visit/sbar_card.dart';
import 'clinic_widgets.dart';
import 'community_support_screen.dart';
import 'follow_up_check_in_screen.dart';
import 'household_screen.dart';
import 'pending_followups_screen.dart';

void _refreshReferrals(WidgetRef ref) {
  ref.invalidate(openReferralsProvider);
  ref.invalidate(dayPlanProvider);
  ref.invalidate(referralCompletionProvider);
}

class ReferralsTab extends ConsumerWidget {
  const ReferralsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SizedBox.shrink();
    final open = ref.watch(openReferralsProvider);
    final completion = ref.watch(referralCompletionProvider);

    return ColoredBox(
      color: AppColors.surface,
      child: RefreshIndicator(
        onRefresh: () async {
          _refreshReferrals(ref);
          await ref.read(openReferralsProvider.future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(Gap.md),
          children: [
            const LuxeHeroHeader(
              eyebrow: 'Follow-up desk',
              title: 'Referral follow-up',
              body:
                  'Record what happened after referral. Arrival is not '
                  'treatment.',
              icon: Icons.fact_check_outlined,
            ),
            const SizedBox(height: Gap.lg),
            completion.when(
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const ClinicStatusLine(
                text: 'Referral summary unavailable. Pull down to retry.',
                icon: Icons.info_outline_rounded,
              ),
              data: (c) => ClinicCard(
                title: 'Arrival records · last 90 days',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${c.arrived} of ${c.issued} referrals recorded as arrived or treated',
                      style: AppType.body,
                    ),
                    const SizedBox(height: Gap.sm),
                    Text(
                      '${(c.rate * 100).round()}% · Includes family reports. '
                      'Not a measure of verified treatment.',
                      style: AppType.caption,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Gap.md),
            if (user.can(Permission.confirmReferralArrival)) ...[
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  minimumSize: const Size(48, 48),
                  padding: const EdgeInsets.all(Gap.md),
                ),
                onPressed: () => showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => const _ConfirmArrivalDialog(),
                ),
                child: const Text('Confirm code · verified staff action'),
              ),
              const SizedBox(height: Gap.md),
            ],
            open.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => ErrorView(
                error: error,
                onRetry: () => _refreshReferrals(ref),
              ),
              data: (list) {
                if (list.isEmpty) {
                  return const ClinicCard(
                    title: 'No pending arrival records',
                    child: Text(
                      'No referrals are currently recorded as issued or travelling. '
                      'This does not mean all patients received treatment.',
                    ),
                  );
                }
                final urgent =
                    list
                        .where(
                          (r) =>
                              r.urgency == ReferralUrgency.immediate ||
                              r.urgency == ReferralUrgency.sameDay,
                        )
                        .toList()
                      ..sort((a, b) => a.issuedAt.compareTo(b.issuedAt));
                final routine =
                    list
                        .where(
                          (r) =>
                              r.urgency != ReferralUrgency.immediate &&
                              r.urgency != ReferralUrgency.sameDay,
                        )
                        .toList()
                      ..sort((a, b) => a.issuedAt.compareTo(b.issuedAt));
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (urgent.isNotEmpty) ...[
                      _LaneHeader(
                        title: 'Urgent follow-up',
                        count: urgent.length,
                        subtitle:
                            'Immediate and same-day referrals, oldest first.',
                      ),
                      for (final referral in urgent)
                        _ReferralTile(referral: referral),
                    ],
                    if (routine.isNotEmpty) ...[
                      _LaneHeader(
                        title: 'Other pending arrivals',
                        count: routine.length,
                        subtitle: 'Check arrival and ask about care received.',
                      ),
                      for (final referral in routine)
                        _ReferralTile(referral: referral),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: Gap.md),
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const PendingFollowUpsScreen(),
                ),
              ),
              child: const Text('Open pending follow-ups'),
            ),
            const SizedBox(height: Gap.lg),
          ],
        ),
      ),
    );
  }
}

class _LaneHeader extends StatelessWidget {
  const _LaneHeader({
    required this.title,
    required this.count,
    required this.subtitle,
  });
  final String title;
  final int count;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Gap.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$title ($count)', style: AppType.title.copyWith(fontSize: 17)),
        const SizedBox(height: Gap.xs),
        Text(subtitle, style: AppType.caption),
      ],
    ),
  );
}

class _ReferralTile extends ConsumerWidget {
  const _ReferralTile({required this.referral});
  final Referral referral;

  String get _arrivalState {
    if (referral.status == ReferralStatus.arrived ||
        referral.status == ReferralStatus.treated) {
      return referral.arrivalConfirmedBy != null
          ? 'Arrival confirmed by staff. Treatment is a separate outcome.'
          : 'Arrival reported — not facility-verified.';
    }
    if (referral.status == ReferralStatus.travelling) {
      return 'Arrival pending — previously reported travelling. Check the current outcome.';
    }
    if (referral.status == ReferralStatus.issued) {
      return 'Arrival pending — no arrival recorded. Follow-up needed.';
    }
    return 'Arrival not established · ${referral.status.label}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final person = ref.watch(personProvider(referral.personId));
    final patient = person.valueOrNull;
    final phone = patient?.phone;
    final urgencyColor = switch (referral.urgency) {
      ReferralUrgency.immediate => AppColors.triageRed,
      ReferralUrgency.sameDay => AppColors.triageAmber,
      _ => AppColors.inkMuted,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: ClinicCard(
        title:
            patient?.fullName ??
            (person.isLoading
                ? 'Loading patient…'
                : 'Patient name unavailable'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (person.hasError)
              TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: () =>
                    ref.invalidate(personProvider(referral.personId)),
                child: const Text('Retry patient details'),
              ),
            Text(referral.facilityName, style: AppType.label),
            const SizedBox(height: Gap.sm),
            Text(referral.reason, style: AppType.body),
            const SizedBox(height: Gap.sm),
            Text(
              referral.urgency.label,
              style: AppType.label.copyWith(color: urgencyColor),
            ),
            const SizedBox(height: Gap.sm),
            Text(
              'Issued ${DateFormat('d MMM yyyy, HH:mm').format(referral.issuedAt.toLocal())}',
              style: AppType.caption,
            ),
            const SizedBox(height: Gap.md),
            if (referral.needsEscalation)
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.sm),
                child: ClinicStatusLine(
                  text:
                      'Urgent referral open over 48 hours with no confirmed '
                      'arrival — trace now.',
                  icon: Icons.crisis_alert_rounded,
                ),
              ),
            _StatusTimeline(referral: referral),
            const SizedBox(height: Gap.sm),
            ClinicStatusLine(text: _arrivalState, icon: Icons.schedule_rounded),
            const SizedBox(height: Gap.md),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.all(Gap.md),
              ),
              onPressed: () => Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => FollowUpCheckInScreen(referral: referral),
                ),
              ),
              child: const Text('Record follow-up'),
            ),
            const SizedBox(height: Gap.sm),
            if (phone != null && phone.trim().isNotEmpty)
              _CallButton(number: phone)
            else
              const Text('No family phone number on record.'),
            const SizedBox(height: Gap.sm),
            const Text(
              'Calling requires telephone service and cellular signal. '
              'It does not work offline without signal. Opening the dialler '
              'does not change the referral status.',
            ),
            const SizedBox(height: Gap.sm),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              minTileHeight: 48,
              title: const Text('Record details and support'),
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SelectableText('Referral code: ${referral.referenceCode}'),
                    if (referral.clinicalSummary?.isNotEmpty ?? false) ...[
                      const SizedBox(height: Gap.sm),
                      Text(referral.clinicalSummary!),
                    ],
                    if (referral.outcomeNotes?.isNotEmpty ?? false) ...[
                      const SizedBox(height: Gap.sm),
                      Text('Recorded notes\n${referral.outcomeNotes!}'),
                    ],
                    const SizedBox(height: Gap.sm),
                    TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      onPressed: () => showSbarSheet(
                        context,
                        SbarCard.fromReferral(referral, patient),
                      ),
                      child: const Text('Handover note (SBAR)'),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      onPressed: patient == null
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => HouseholdScreen(
                                  householdId: patient.householdId,
                                ),
                              ),
                            ),
                      child: const Text('Open household record'),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      onPressed: () async {
                        final changed = await Navigator.of(context).push<bool>(
                          MaterialPageRoute(
                            builder: (_) =>
                                CommunitySupportScreen(referral: referral),
                          ),
                        );
                        if (changed == true && context.mounted) {
                          _refreshReferrals(ref);
                        }
                      },
                      child: const Text('Loop in support'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Launches the dialler only; never records contact, travel or arrival.
class _CallButton extends StatelessWidget {
  const _CallButton({required this.number});
  final String number;

  Future<void> _call(BuildContext context) async {
    final clean = number.replaceAll(RegExp(r'[^0-9+]'), '');
    try {
      if (clean.isNotEmpty &&
          await launchUrl(
            Uri(scheme: 'tel', path: clean),
            mode: LaunchMode.externalApplication,
          )) {
        return;
      }
    } catch (_) {
      // The same actionable feedback covers unavailable diallers and errors.
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not open the dialler. Dial $number directly when telephone service is available.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => OutlinedButton(
    style: OutlinedButton.styleFrom(
      foregroundColor: AppColors.primary,
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.all(Gap.md),
    ),
    onPressed: () => _call(context),
    child: const Text('Call family'),
  );
}

/// The referral's journey as a four-node track: issued → travelling →
/// arrived → treated. Family reports move a referral along it; only the
/// staff code confirmation marks arrival as facility-verified. Off-ramps
/// (did not attend, declined, cancelled) render as a plain honest line
/// instead of a track that implies the loop can still complete.
class _StatusTimeline extends StatelessWidget {
  const _StatusTimeline({required this.referral});

  final Referral referral;

  static const _nodes = ['Issued', 'Travelling', 'Arrived', 'Treated'];

  @override
  Widget build(BuildContext context) {
    if (referral.status.isFailure || referral.status == ReferralStatus.cancelled) {
      return ClinicStatusLine(
        text:
            '${referral.status.label} — the arrival loop did not complete.',
        icon: Icons.error_outline_rounded,
      );
    }
    final reached = switch (referral.status) {
      ReferralStatus.issued => 0,
      ReferralStatus.travelling => 1,
      ReferralStatus.arrived => 2,
      ReferralStatus.treated => 3,
      _ => 0,
    };
    String? stamp(int i) {
      final at = i == 0
          ? referral.issuedAt
          : (i <= reached ? referral.statusUpdatedAt : null);
      return at == null ? null : DateFormat('d MMM, HH:mm').format(at.toLocal());
    }

    return Row(
      children: [
        for (var i = 0; i < _nodes.length; i++) ...[
          if (i > 0)
            Expanded(
              flex: 1,
              child: Container(
                height: 2,
                color: i <= reached ? AppColors.primary : AppColors.line,
              ),
            ),
          Expanded(
            flex: 3,
            child: Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < reached
                        ? AppColors.primary
                        : (i == reached ? AppColors.canvas : AppColors.line),
                    border: Border.all(
                      color: i <= reached ? AppColors.primary : AppColors.line,
                      width: i == reached ? 3 : 1,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                // FittedBox keeps the track intact at 320px / 200% text:
                // labels shrink rather than overflow.
                FittedBox(
                  child: Text(
                    _nodes[i],
                    style: AppType.label.copyWith(
                      fontSize: 11,
                      color: i <= reached ? AppColors.ink : AppColors.inkFaint,
                    ),
                  ),
                ),
                FittedBox(
                  child: Text(
                    stamp(i) ?? ' ',
                    style: AppType.caption.copyWith(fontSize: 10),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ConfirmArrivalDialog extends ConsumerStatefulWidget {
  const _ConfirmArrivalDialog();
  @override
  ConsumerState<_ConfirmArrivalDialog> createState() =>
      _ConfirmArrivalDialogState();
}

class _ConfirmArrivalDialogState extends ConsumerState<_ConfirmArrivalDialog> {
  final _code = TextEditingController();
  bool _verified = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final user = ref.read(currentUserProvider);
    if (_busy || !_verified || user == null) return;
    if (_code.text.trim().isEmpty) {
      setState(() => _error = 'Enter the referral code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final referral = await ref
          .read(careRepositoryProvider)
          .confirmArrival(user, _code.text.trim());
      if (!mounted) return;
      if (referral == null) {
        setState(() {
          _busy = false;
          _error = 'Code not found. Check the code and retry.';
        });
        return;
      }
      _refreshReferrals(ref);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Staff-confirmed arrival saved locally. This does not confirm treatment.',
          ),
        ),
      );
      setState(() => _busy = false);
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not save confirmation. Check and retry.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      backgroundColor: Colors.white,
      scrollable: true,
      title: const Text('Confirm arrival code'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Verified staff action only. For a family report, use Record follow-up. '
            'Arrival confirmation does not confirm treatment.',
          ),
          const SizedBox(height: Gap.md),
          TextField(
            controller: _code,
            enabled: !_busy,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Referral code'),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text(
              'I have verified arrival with facility staff or in person.',
            ),
            value: _verified,
            onChanged: _busy
                ? null
                : (value) => setState(() => _verified = value ?? false),
          ),
          if (_error != null) Semantics(liveRegion: true, child: Text(_error!)),
        ],
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size(48, 48),
          ),
          onPressed: _busy || !_verified ? null : _confirm,
          child: Text(_busy ? 'Saving…' : 'Confirm arrival'),
        ),
      ],
    ),
  );
}
