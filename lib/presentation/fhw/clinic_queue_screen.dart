/// The clinic queue: every patient this nurse has received and not yet closed.
///
/// A real CHPS morning is not one person at a time. Several households are
/// received under the same tree, a routine consult is paused when a sick child
/// arrives, and the nurse moves back and forth between open sessions. This
/// screen surfaces all of that from existing open [Visit] rows — a ticket per
/// open session, in arrival order — without pretending a worker can only have
/// one thing in hand.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/motion.dart';
import '../../domain/entities/visit.dart';
import '../visit/roll_call_screen.dart';
import 'clinic_widgets.dart';
import 'home_tab.dart';
import 'receive_patient_sheet.dart';

class ClinicQueueScreen extends ConsumerStatefulWidget {
  const ClinicQueueScreen({super.key});

  @override
  ConsumerState<ClinicQueueScreen> createState() => _ClinicQueueScreenState();
}

class _ClinicQueueScreenState extends ConsumerState<ClinicQueueScreen> {
  bool _busy = false;

  void _refresh() {
    ref.invalidate(clinicQueueProvider);
    ref.invalidate(activeClinicSessionProvider);
    ref.invalidate(dayPlanProvider);
  }

  Future<void> _resume(String householdId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RollCallScreen(householdId: householdId)),
    );
    if (mounted) _refresh();
  }

  Future<void> _cancel(ClinicQueueTicket ticket) async {
    if (_busy) return;
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this open session?'),
        content: Text(
          'No assessment has been saved for ${ticket.householdName} in this '
          'session. Closing it removes the ticket. Recorded history is never '
          'deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep it open'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.triageRed),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cancel session'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(careRepositoryProvider).completeVisit(user, ticket.visit.id);
      if (mounted) _refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not close the session. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final queue = ref.watch(clinicQueueProvider);
    final pace = ref.watch(clinicDayStatsProvider);
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text('Clinic queue'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: queue.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              ClinicStatusLine(
                text: 'Open sessions could not be loaded. Tap to retry.',
                icon: Icons.refresh_rounded,
                onTap: _refresh,
              ),
            ],
          ),
          data: (tickets) => tickets.isEmpty
              ? _EmptyQueue(onReceive: () => _receive(context), pace: pace)
              : ListView(
                  key: const PageStorageKey('clinic-queue'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                  children: [
                    _ClinicPace(pace: pace),
                    const SizedBox(height: 12),
                    Text(
                      '${tickets.length} patient${tickets.length == 1 ? '' : 's'} '
                      'received and still open',
                      style: AppType.title.copyWith(fontSize: 18),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tap a ticket to continue that consultation. A session '
                      'stays open until you review and close it.',
                      style: AppType.caption,
                    ),
                    const SizedBox(height: 16),
                    for (final (i, ticket) in tickets.indexed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: StaggeredReveal(
                          index: i,
                          duration: const Duration(milliseconds: 220),
                          child: _QueueTicketCard(
                            ticket: ticket,
                            busy: _busy,
                            onResume: () => _resume(ticket.visit.householdId),
                            onCancel: () => _cancel(ticket),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
      floatingActionButton: queue.valueOrNull?.isEmpty ?? false
          ? FloatingActionButton.extended(
              onPressed: () => _receive(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Receive a patient'),
            )
          : null,
    );
  }

  Future<void> _receive(BuildContext context) async {
    await showReceivePatientSheet(
      context,
      knownHouseholds:
          ref.read(visibleHouseholdsProvider).valueOrNull ?? const [],
    );
    if (mounted) _refresh();
  }
}

class _QueueTicketCard extends StatelessWidget {
  const _QueueTicketCard({
    required this.ticket,
    required this.busy,
    required this.onResume,
    required this.onCancel,
  });

  final ClinicQueueTicket ticket;
  final bool busy;
  final VoidCallback onResume;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final arrival = DateFormat('HH:mm').format(ticket.visit.startedAt);
    final waited = DateTime.now().difference(ticket.visit.startedAt);
    final waitedLabel = waited.inMinutes < 60
        ? '${waited.inMinutes} min'
        : '${waited.inHours}h ${waited.inMinutes % 60}m';
    final cancellable = ticket.assessedCount == 0 && !busy;
    final card = ClinicCard(
      accent: ticket.pending > 0 ? AppColors.brass : AppColors.triageGreen,
      title: ticket.householdName,
      subtitle:
          'Arrived $arrival · ${ticket.assessedCount}/${ticket.presentCount} '
          'assessed',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceTint,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Waiting $waitedLabel',
                  style: AppType.label.copyWith(
                    fontSize: 12,
                    color: AppColors.inkMuted,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ticket.allAssessed
                      ? 'All received people assessed. Review to close.'
                      : '${ticket.pending} ${ticket.pending == 1 ? 'person' : 'people'} still to assess.',
                  style: AppType.caption,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: busy ? null : onResume,
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(ticket.allAssessed ? 'Review session' : 'Continue'),
          ),
          if (cancellable) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onCancel,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.triageRed,
              ),
              icon: const Icon(Icons.close_rounded, size: 18),
              label: const Text('Cancel open session'),
            ),
          ],
        ],
      ),
    );
    if (busy) return card;
    // Swipe left for the quick actions; a tap on the card itself resumes.
    return SwipeRevealActions(
      actions: [
        SwipeAction(
          label: 'Resume',
          icon: Icons.play_arrow_rounded,
          onPressed: onResume,
        ),
        if (cancellable)
          SwipeAction(
            label: 'Cancel',
            icon: Icons.close_rounded,
            tone: AppColors.triageRed,
            onPressed: onCancel,
          ),
      ],
      onTap: onResume,
      child: card,
    );
  }
}

class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue({required this.onReceive, required this.pace});
  final VoidCallback onReceive;
  final AsyncValue<ClinicDayStats> pace;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 60, 20, 28),
    children: [
      const SizedBox(height: 24),
      const Icon(
        Icons.inbox_rounded,
        size: 56,
        color: AppColors.inkFaint,
      ),
      const SizedBox(height: 16),
      Text(
        'No open sessions',
        style: AppType.title,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 8),
      Text(
        'When you receive a patient they appear here as a ticket you can '
        'pause and return to.',
        style: AppType.caption,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 24),
      _ClinicPace(pace: pace),
    ],
  );
}

/// Today's front-door pace, derived from existing rows: sessions received,
/// still open (the local stand-in for "left without being seen"), and the
/// mean wait from receiving to the first saved assessment — the CHPS version
/// of door-to-provider time. Renders nothing while loading or unavailable so
/// the board stays about the queue, not the metrics.
class _ClinicPace extends StatelessWidget {
  const _ClinicPace({required this.pace});

  final AsyncValue<ClinicDayStats> pace;

  @override
  Widget build(BuildContext context) {
    final stats = pace.valueOrNull;
    if (stats == null || stats.received == 0) return const SizedBox.shrink();
    return ClinicCard(
      title: 'Clinic pace today',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${stats.received} received · ${stats.openNow} still open',
            style: AppType.body,
          ),
          const SizedBox(height: Gap.xs),
          Text(
            stats.hasAssessments
                ? 'Average wait to first assessment: '
                    '${stats.avgMinutesToFirstAssessment!.round()} min'
                : 'No saved assessments yet — pace appears after the first '
                    'consultation is recorded.',
            style: AppType.caption,
          ),
        ],
      ),
    );
  }
}
