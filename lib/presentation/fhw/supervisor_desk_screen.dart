/// The supervision desk — where the accountability spine either gets read or
/// becomes decoration.
///
/// ### Why one screen with two queues, rather than a dashboard
///
/// A tamper-evident ledger that nobody opens is a compliance artefact: it satisfies
/// an auditor and changes nothing. This app already knows that failure mode — the
/// paper defaulter list is feared precisely because someone is *named* on it. So
/// the desk is not a chart of access volumes. It is the list of things that need an
/// answer, split into the two kinds of answer owed:
///
///  1. **Access no consent and no caseload explains** — a worker looked at a family
///     they have no recorded relationship with. Care is never blocked by a log, so
///     these reads are allowed and flagged; flagging only means something if a
///     human writes down what they concluded.
///  2. **Families still waiting on an answer** — a request to correct, object, erase
///     or carry away their data, with the 30-day promise the notice made counting
///     down against it.
///
/// Both queues sit on one page on purpose. Tabs would let a supervisor clear the
/// interesting one and never scroll to the one with a deadline running.
///
/// ### How a finding is closed
///
/// By appending, never by editing. The flagged row keeps its hash — it is the
/// evidence — and the review lands as a second row pointing back at it, filed
/// against the family's own subject id so it appears in *their* disclosure as
/// supervision. A review the supervised party can never see is housekeeping, not
/// oversight.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/fhw_luxe.dart';
import '../../data/local/compliance_dao.dart';
import '../../data/repositories/care_repository.dart';
import '../../domain/compliance.dart';
import '../shared/ui.dart';
import 'clinic_widgets.dart';

class SupervisorDeskScreen extends ConsumerStatefulWidget {
  const SupervisorDeskScreen({super.key});

  @override
  ConsumerState<SupervisorDeskScreen> createState() =>
      _SupervisorDeskScreenState();
}

class _Desk {
  const _Desk({
    required this.integrity,
    required this.findings,
    required this.waiting,
    required this.patterns,
  });

  final ChainVerification integrity;
  final List<AccessFinding> findings;
  final List<RightsRequest> waiting;
  final List<AccessPattern> patterns;

  int get unreviewed => findings.where((f) => !f.reviewed).length;
}

class _SupervisorDeskScreenState extends ConsumerState<SupervisorDeskScreen> {
  Future<_Desk>? _load;
  bool _busy = false;
  String? _note;

  @override
  void initState() {
    super.initState();
    _load = _fetch();
  }

  Future<_Desk> _fetch() async {
    final user = ref.read(currentUserProvider);
    // A desk with no signed-in supervisor is an error, not an empty list: showing
    // "nothing needs explaining" to a room would be the most misleading possible
    // outcome of a login problem.
    if (user == null) {
      throw StateError('No signed-in account to supervise with.');
    }
    final repo = ref.read(careRepositoryProvider);
    return _Desk(
      integrity: await repo.verifyAccessTrail(user),
      findings: await repo.accessFindings(user),
      waiting: await repo.openDataRightsQueue(user),
      patterns: await repo.accessPatterns(user),
    );
  }

  void _reload() {
    if (!mounted) return;
    setState(() => _load = _fetch());
  }

  /// Asks for a written decision and refuses to accept silence. The point of the
  /// sentence is that it must exist afterwards; a review button that records only
  /// "reviewed by X" proves that someone clicked.
  Future<String?> _askOutcome({
    required String title,
    required String explain,
    required String confirmLabel,
  }) async {
    final controller = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              explain,
              style: AppType.caption.copyWith(
                color: FhwLuxePalette.textSecondary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: Gap.md),
            TextField(
              controller: controller,
              minLines: 3,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'What I decided, and why',
                hintText: 'Talked to the worker; family was in transit…',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isEmpty) return;
              Navigator.of(context).pop(true);
            },
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    final text = submitted == true ? controller.text.trim() : null;
    controller.dispose();
    return (text == null || text.isEmpty) ? null : text;
  }

  Future<void> _review(AccessFinding finding) async {
    final outcome = await _askOutcome(
      title: 'Record what you decided',
      explain:
          'This adds a new line to the trail and leaves the access itself '
          'untouched — its hash is the evidence. ${finding.subjectName} will see '
          'that you reviewed it, and what you wrote, if they ask for their '
          'disclosure.',
      confirmLabel: 'Add the review',
    );
    if (outcome == null) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(careRepositoryProvider)
          .reviewAccess(
            ref.read(currentUserProvider)!,
            entryId: finding.entryId,
            subjectPersonId: finding.subjectPersonId,
            outcome: outcome,
          );
      _say('Review added to the trail.');
    } catch (e) {
      _say('The review could not be written: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    _reload();
  }

  Future<void> _answer(RightsRequest request, {required bool refuse}) async {
    final outcome = await _askOutcome(
      title: refuse
          ? 'Refuse this request — say why'
          : 'Close this request — say what you did',
      explain: refuse
          ? 'A refusal with no reason is not an answer. Say which law requires '
                'the record to be kept, or what else stands in the way, in words '
                'the family can read.'
          : 'Write what the family will be given, and when. This text is the '
                'record that the obligation was met.',
      confirmLabel: refuse ? 'Record the refusal' : 'Mark it answered',
    );
    if (outcome == null) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(careRepositoryProvider)
          .resolveDataRight(
            ref.read(currentUserProvider)!,
            requestId: request.id,
            status: refuse ? RequestStatus.refused : RequestStatus.fulfilled,
            resolution: outcome,
          );
      _say(
        refuse
            ? 'Refusal recorded with its reason.'
            : 'Marked answered — the family is off the queue.',
      );
    } catch (e) {
      _say('That could not be saved: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    _reload();
  }

  void _say(String text) {
    if (mounted) setState(() => _note = text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FhwLuxePalette.porcelainCanvas,
      appBar: AppBar(
        backgroundColor: FhwLuxePalette.porcelainCanvas,
        surfaceTintColor: Colors.transparent,
        foregroundColor: FhwLuxePalette.textPrimary,
        title: const Text('Supervision desk'),
      ),
      body: FutureBuilder<_Desk>(
        future: _load,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            // AccessDenied is the honest case for a worker who has no
            // supervisory permission, and it should read as such rather than as a
            // crash.
            return ErrorView(error: snapshot.error!);
          }
          final desk = snapshot.data;
          if (desk == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(Gap.lg),
            children: [
              _IntegrityStrip(integrity: desk.integrity, onRecheck: _reload),
              if (_note != null) ...[
                const SizedBox(height: Gap.md),
                Text(
                  _note!,
                  style: AppType.label.copyWith(
                    color: FhwLuxePalette.textPrimary,
                  ),
                ),
              ],
              const SizedBox(height: Gap.lg),
              _FindingsSection(
                findings: desk.findings,
                busy: _busy,
                onReview: _review,
              ),
              const SizedBox(height: Gap.lg),
              _WaitingSection(
                waiting: desk.waiting,
                busy: _busy,
                onAnswer: _answer,
              ),
              const SizedBox(height: Gap.lg),
              _PatternsSection(patterns: desk.patterns),
              const SizedBox(height: Gap.lg),
              const _BoundaryCard(),
              const SizedBox(height: Gap.lg),
              const _StoragePostureCard(),
            ],
          );
        },
      ),
    );
  }
}

/// The verdict on the evidence itself, asked before any finding is shown. If the
/// chain no longer matches, every number below it is describing a history somebody
/// could have edited.
class _IntegrityStrip extends StatelessWidget {
  const _IntegrityStrip({required this.integrity, required this.onRecheck});

  final ChainVerification integrity;
  final VoidCallback onRecheck;

  @override
  Widget build(BuildContext context) {
    final broken = integrity is ChainBroken;
    return LumenCard(
      title: broken
          ? 'The trail itself needs reporting'
          : 'The trail is intact',
      subtitle: integrity.humanMessage,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            broken
                ? 'Stop here. A line in the ledger no longer matches the seal on '
                      'the next one, so nothing in the two queues below can be '
                      'treated as reliable until this is reported.'
                : 'Every access below is sealed by the one before it, so an '
                      'edit or a deletion anywhere in the history would surface '
                      'here instead of quietly improving the numbers.',
            style: AppType.caption.copyWith(
              color: FhwLuxePalette.lacquerInk,
              height: 1.5,
            ),
          ),
          const SizedBox(height: Gap.sm),
          TextButton.icon(
            onPressed: onRecheck,
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: const Text('Re-check the chain'),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _FindingsSection extends StatelessWidget {
  const _FindingsSection({
    required this.findings,
    required this.busy,
    required this.onReview,
  });

  final List<AccessFinding> findings;
  final bool busy;
  final void Function(AccessFinding) onReview;

  @override
  Widget build(BuildContext context) {
    final open = findings.where((f) => !f.reviewed).length;
    return SectionCard(
      title: 'Access no consent or caseload explains',
      subtitle: findings.isEmpty
          ? 'Nothing recorded on this handset needs an explanation — which is '
                'not the same as nothing needing one anywhere.'
          : '$open still waiting for a decision. Each one was allowed, because a '
                'worker must never be blocked from a patient — and each one is '
                'flagged, because it still has to be accounted for.',
      icon: Icons.visibility_off_outlined,
      accent: findings.isEmpty ? null : FhwLuxePalette.clinicalAmber,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final finding in findings.take(30))
            _FindingTile(finding: finding, busy: busy, onReview: onReview),
          if (findings.length > 30)
            Text(
              '+${findings.length - 30} older findings',
              style: AppType.caption,
            ),
        ],
      ),
    );
  }
}

class _FindingTile extends StatelessWidget {
  const _FindingTile({
    required this.finding,
    required this.busy,
    required this.onReview,
  });

  final AccessFinding finding;
  final bool busy;
  final void Function(AccessFinding) onReview;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The finding stated as one sentence, because that is the form a
          // supervisor has to repeat out loud to the worker afterwards.
          Text(
            '${finding.actorName}, ${finding.actorRole}, opened '
            '${finding.subjectName}’s record for '
            '${finding.purpose.label.toLowerCase()}.',
            style: AppType.label.copyWith(fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 2),
          Text(
            '${DateFormat('d MMM y, HH:mm').format(finding.occurredAt)} · '
            '${finding.basis.label} · ${finding.deviceId}',
            style: AppType.caption.copyWith(
              fontSize: 11.5,
              color: FhwLuxePalette.textSecondary,
              height: 1.4,
            ),
          ),
          if ((finding.note ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'Their words: “${finding.note!.trim()}”',
              style: AppType.caption.copyWith(
                fontSize: 11.5,
                fontStyle: FontStyle.italic,
                color: FhwLuxePalette.textSecondary,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: Gap.sm),
          finding.reviewed
              ? Row(
                  children: [
                    const Icon(
                      Icons.how_to_reg_rounded,
                      size: 15,
                      color: FhwLuxePalette.emeraldPulse,
                    ),
                    const SizedBox(width: Gap.xs),
                    Text(
                      'A review is on file',
                      style: AppType.caption.copyWith(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: FhwLuxePalette.textPrimary,
                      ),
                    ),
                  ],
                )
              : Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : () => onReview(finding),
                    icon: const Icon(Icons.rate_review_outlined, size: 17),
                    label: const Text('Record what I decided'),
                  ),
                ),
          const Divider(height: Gap.lg),
        ],
      ),
    );
  }
}

class _WaitingSection extends StatelessWidget {
  const _WaitingSection({
    required this.waiting,
    required this.busy,
    required this.onAnswer,
  });

  final List<RightsRequest> waiting;
  final bool busy;
  final void Function(RightsRequest, {required bool refuse}) onAnswer;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final late = waiting.where((r) => r.isOverdue(now)).length;
    return SectionCard(
      title: 'Families still waiting on an answer',
      subtitle: waiting.isEmpty
          ? 'No request is open. Nothing here was promised a deadline that is '
                'currently running.'
          : 'Oldest first. The notice tells every family '
                '${CareNotice.serviceDeadlineLabel} — '
                '$late of these have passed it.',
      icon: Icons.pending_actions_rounded,
      accent: late > 0 ? FhwLuxePalette.clinicalAmber : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final request in waiting)
            _WaitingTile(
              request: request,
              now: now,
              busy: busy,
              onAnswer: onAnswer,
            ),
        ],
      ),
    );
  }
}

/// The pattern queue: entries that are individually defensible and collectively
/// worth a conversation.
///
/// Phrased as counts rather than accusations, on purpose. Both detectors have
/// innocent explanations that are common in this setting — a shared caseload, a
/// campaign day, a family that moved — and a supervisor shown the word "misuse"
/// will defend the worker instead of asking her. The number is what earns the
/// question.
class _PatternsSection extends StatelessWidget {
  const _PatternsSection({required this.patterns});

  final List<AccessPattern> patterns;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Patterns worth a conversation',
      subtitle: patterns.isEmpty
          ? 'No worker opened an unusual number of unrelated families, and no '
                'protected record was opened by several workers, in the last day. '
                'This looks at the shape of many entries — it is not a second copy '
                'of the queue above.'
          : 'Neither of these is a finding on its own. Each is a shape in the '
                'trail that a single entry cannot show, and both have ordinary '
                'explanations — ask before you conclude.',
      icon: Icons.insights_rounded,
      accent: patterns.isEmpty ? null : FhwLuxePalette.clinicalAmber,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final p in patterns)
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.sm),
              child: Text(
                p.sentence,
                style: AppType.caption.copyWith(
                  fontSize: 12.5,
                  color: FhwLuxePalette.textPrimary,
                  height: 1.45,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The erasure action, on the request that asked for it.
///
/// Self-contained and one-way: it confirms in plain words what will be erased and
/// what will be kept, because "mark as answered" on an erasure request would let a
/// supervisor close an obligation they never carried out — the quietest way this
/// feature could fail a family.
class _EraseAction extends ConsumerStatefulWidget {
  const _EraseAction({required this.request, required this.busy});

  final RightsRequest request;

  /// The queue's own in-flight flag, so an erase cannot be started while another
  /// answer on this page is still being written.
  final bool busy;

  @override
  ConsumerState<_EraseAction> createState() => _EraseActionState();
}

class _EraseActionState extends ConsumerState<_EraseAction> {
  bool _busy = false;
  String? _done;

  Future<void> _run() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Erase this family’s identifiers?'),
        content: const Text(
          'The name, phone number and health insurance number are removed from '
          'this device and the change is sent to the district.\n\n'
          'Clinical history is kept without names. This app does not decide '
          'statutory retention periods for health records — the district data '
          'protection supervisor does — so tell the family that plainly, and tell '
          'them they may ask for the history too.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Erase identifiers'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    setState(() {
      _busy = true;
      _done = null;
    });
    try {
      await ref
          .read(careRepositoryProvider)
          .eraseIdentifiers(user, requestId: widget.request.id);
      // Not a toast. This is the answer to a family's legal request, and the
      // record of it should still be on the screen when a supervisor reads it out.
      if (mounted) setState(() => _done = 'Identifiers erased. ');
      ref.invalidate(careRepositoryProvider);
    } on ErasureRefused catch (e) {
      if (mounted) setState(() => _done = 'Not done — ${e.message}');
    } catch (e) {
      if (mounted) setState(() => _done = 'Could not be carried out: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_done != null) {
      return Text(
        _done!,
        style: AppType.caption.copyWith(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: FhwLuxePalette.textPrimary,
        ),
      );
    }
    return OutlinedButton(
      onPressed: (_busy || widget.busy) ? null : _run,
      child: Text(_busy ? 'Erasing…' : 'Erase identifiers'),
    );
  }
}

class _WaitingTile extends StatelessWidget {
  const _WaitingTile({
    required this.request,
    required this.now,
    required this.busy,
    required this.onAnswer,
  });

  final RightsRequest request;
  final DateTime now;
  final bool busy;
  final void Function(RightsRequest, {required bool refuse}) onAnswer;

  @override
  Widget build(BuildContext context) {
    final days = now.difference(request.requestedAt).inDays;
    final late = request.isOverdue(now);
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${request.subjectName ?? 'a family'} asked: '
            '${request.right.label.toLowerCase()}.',
            style: AppType.label.copyWith(fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 2),
          // Days counted in words as well as colour: a late item must be legible
          // without relying on amber, and the number is the thing a District
          // Supervisor is actually accountable for.
          Row(
            children: [
              Icon(
                late ? Icons.schedule_rounded : Icons.hourglass_empty_rounded,
                size: 15,
                color: late
                    ? FhwLuxePalette.clinicalAmber
                    : FhwLuxePalette.textSecondary,
              ),
              const SizedBox(width: Gap.xs),
              Expanded(
                child: Text(
                  'Sent ${DateFormat('d MMM y').format(request.requestedAt)} · '
                  '$days day${days == 1 ? '' : 's'} waiting'
                  '${late ? ' · past the promise' : ''}',
                  style: AppType.caption.copyWith(
                    fontSize: 11.5,
                    fontWeight: late ? FontWeight.w700 : FontWeight.w400,
                    color: FhwLuxePalette.textSecondary,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.xs,
            children: [
              // Erasure gets the act, not the tick box. Every other right here is
              // discharged by a decision a supervisor can make from this chair; an
              // erasure is discharged by removing the data, so the only button is
              // the one that does it.
              if (request.right == DataRight.erasure)
                _EraseAction(request: request, busy: busy)
              else
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => onAnswer(request, refuse: false),
                  child: const Text('Mark it answered'),
                ),
              OutlinedButton(
                onPressed: busy ? null : () => onAnswer(request, refuse: true),
                child: const Text('Refuse with a reason'),
              ),
            ],
          ),
          const Divider(height: Gap.lg),
        ],
      ),
    );
  }
}

/// Says the limit out loud. A supervision screen that implies district-wide
/// coverage would be worse than none: it would let a district believe a quiet queue
/// means a quiet caseload.
class _BoundaryCard extends StatelessWidget {
  const _BoundaryCard();

  @override
  Widget build(BuildContext context) {
    return ClinicCard(
      title: 'What this desk can and cannot see',
      child: Text(
        'Both queues are read from the records on THIS handset. A finding raised on '
        'another worker\'s phone, and a request made by a family at another compound, '
        'are pushed to the district server and stay there: they never arrive here, '
        'because an access trail and an unanswered request are both patient data and '
        'there is no supervisory role yet to scope a download to. This list is '
        'therefore a device\'s queue, not the district\'s — do not read an empty screen '
        'as a quiet caseload. The district\'s own copy, which holds every device '
        'together, is read on the server.',
        style: AppType.caption.copyWith(
          color: FhwLuxePalette.textSecondary,
          height: 1.5,
        ),
      ),
    );
  }
}

/// How the register on this handset is actually stored.
///
/// On the supervision desk rather than buried in settings, because this is the
/// question a district is asked second after "who can see it": a supervisor
/// signing off a deployment should not have to trust a slide about encryption when
/// the app can state its own posture, per build, from the code that opened the
/// file. When the answer is "not encrypted, because this is the desktop build", an
/// amber-free plain sentence is exactly what makes the claim above trustworthy.
class _StoragePostureCard extends ConsumerWidget {
  const _StoragePostureCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posture = ref.watch(atRestPostureProvider).valueOrNull;
    return ClinicCard(
      title: 'How the register is stored on this handset',
      child: Text(
        // Static text while unknown rather than a spinner: this card sits on a
        // screen the suite pumps to idle, and an indeterminate indicator there
        // never stops animating.
        posture?.summary ?? 'Checking how this device stores its records…',
        style: AppType.caption.copyWith(
          color: FhwLuxePalette.textSecondary,
          height: 1.5,
        ),
      ),
    );
  }
}
