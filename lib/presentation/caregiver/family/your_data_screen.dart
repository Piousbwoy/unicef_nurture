/// Your record — the family's own page about their data.
///
/// ### Why this is a reading and not a table
///
/// A disclosure delivered as a compliance artefact (columns of purposes, bases and
/// timestamps) is only legible to the person who designed the schema. This page
/// therefore renders every access as one sentence in the family's language, and
/// makes the whole list speakable, because the right of access is only real if the
/// person holding the right can actually exercise it — and a mother who cannot read
/// small print in English has no use for a perfectly good audit log.
///
/// ### What it deliberately does not do
///
/// It does not claim that pressing "erase" deletes anything. Under Ghana's Data
/// Protection Act a request is a duty the district owes, with a deadline, and a
/// child's immunisation record may be one the law requires them to keep. So the
/// button opens a tracked request and says so. A screen that quietly deleted rows
/// would be both non-compliant and a lie about what just happened.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../core/audio/speech_content_policy.dart';
import '../../../data/local/compliance_dao.dart';
import '../../../domain/compliance.dart';
import '../../../domain/entities/core.dart';
import '../caregiver_providers.dart';
import '../widgets/companion.dart';
import '../../shared/audio_button.dart';

class CaregiverYourDataScreen extends ConsumerStatefulWidget {
  const CaregiverYourDataScreen({super.key, required this.person});
  final Person person;

  @override
  ConsumerState<CaregiverYourDataScreen> createState() =>
      _CaregiverYourDataScreenState();
}

class _Bundle {
  const _Bundle({
    required this.trail,
    required this.consent,
    required this.requests,
  });

  final List<DisclosureLine> trail;
  final Map<ConsentScope, ConsentEvent?> consent;
  final List<RightsRequest> requests;
}

class _CaregiverYourDataScreenState
    extends ConsumerState<CaregiverYourDataScreen> {
  Future<_Bundle>? _load;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load = _fetch();
  }

  Future<_Bundle> _fetch() async {
    final scope = ref.read(caregiverScopeProvider);
    final user = ref.read(currentUserProvider);
    // No signed-in family is an error, not an empty answer: rendering "nobody has
    // opened this record" here would tell a family their record is clean when the
    // real fact is that nothing could be read.
    if (scope == null || user == null) {
      throw StateError('No signed-in family account to read a disclosure for.');
    }
    final repo = ref.read(careRepositoryProvider);
    // One page, three honest questions: who looked, what we agreed to, what we
    // have asked for. Each is a separate read because a family may act on one
    // without the others changing.
    final trail = await repo.accessTrail(
      user,
      subjectPersonId: widget.person.id,
      householdId: widget.person.householdId,
    );
    final consent = await repo.consentFor(user, widget.person.id);
    final requests = await repo.dataRightsFor(user, widget.person.id);
    return _Bundle(trail: trail, consent: consent, requests: requests);
  }

  /// Every action finishes by re-reading. Guarded because a family can leave the
  /// page while the write is still landing, and setState on a disposed state is a
  /// framework error the user never asked for.
  void _refresh() {
    if (!mounted) return;
    setState(() => _load = _fetch());
  }

  Future<void> _setConsent(ConsentScope scope, bool granted) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(careRepositoryProvider)
          .recordConsent(
            user,
            subjectPersonId: widget.person.id,
            scope: scope,
            decision: granted
                ? ConsentDecision.granted
                : ConsentDecision.withdrawn,
            language: ref.read(narrationLanguageProvider),
          );
      // The old decision stays in the ledger; this screen shows the current one.
      _say(granted ? 'Noted: you agree.' : 'Noted: you do not agree.');
    } catch (e) {
      _say('That could not be saved: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    _refresh();
  }

  Future<void> _raise(DataRight right) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    if (right == DataRight.erasure) {
      // Erasure is the one request that cannot be taken back, and the one a
      // family might expect to wipe the phone. Confirm, and say what it does.
      final go = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Ask the district to erase this record?'),
          content: Text(
            'This sends a request to the health district. It does not delete '
            'anything on this phone today, and some records — like a '
            'child\u2019s immunisation history — may be ones the law asks them '
            'to keep. They must answer within '
            '${CareNotice.serviceDeadlineLabel}.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Send the request'),
            ),
          ],
        ),
      );
      if (go != true) return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(careRepositoryProvider)
          .raiseDataRight(
            user,
            subjectPersonId: widget.person.id,
            right: right,
          );
      _say(
        'Sent. The district now has ${CareNotice.serviceDeadlineLabel} to '
        'answer.',
      );
    } catch (e) {
      _say('That could not be sent: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    _refresh();
  }

  void _say(String text) {
    if (mounted) setState(() => _message = text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CompanionPage(
      title: 'Your record',
      child: FutureBuilder<_Bundle>(
        future: _load,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return CompanionLoadError(onRetry: _refresh);
          }
          final data = snapshot.data;
          if (data == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              CompanionCard(
                title: widget.person.fullName,
                eyebrow: 'What we hold about them',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'The health worker writes down what they see, the visits '
                      'that are due, and any referral. This phone holds your '
                      'copy; the district holds another. Nothing here is sold, '
                      'and no one outside health care is given the names.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: AudioButton(
                        text: _spokenSummary(data),
                        language: ref.watch(narrationLanguageProvider),
                        // Explainer content, not clinical instruction: it is what
                        // the guidance policy is for.
                        policy: SpeechContentPolicy.guidance,
                        compact: true,
                      ),
                    ),
                  ],
                ),
              ),
              if (_message != null) ...[
                const SizedBox(height: 12),
                // Announced, and readable: a toast that vanishes in three seconds
                // is not how a legal confirmation should arrive.
                Text(
                  _message!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              _TrailSection(trail: data.trail, person: widget.person),
              const SizedBox(height: 18),
              _ConsentSection(
                consent: data.consent,
                person: widget.person,
                busy: _busy,
                onSet: _setConsent,
              ),
              const SizedBox(height: 18),
              _RightsSection(
                requests: data.requests,
                busy: _busy,
                onRaise: _raise,
              ),
              const SizedBox(height: 18),
              CompanionCard(
                title: 'What this page cannot tell you',
                child: Text(
                  'This page lists the times a health worker opened this record on '
                  'THIS phone. If a worker at another compound opened it, that line '
                  'goes to the district office and does not come back here — so ask '
                  'the health worker to look it up for you, and they must. Anything '
                  'written only on paper is not listed here either: ask, and they '
                  'will read the paper with you.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// The whole page in three sentences, for the speaker button. Built from the
  /// same bundle the screen just rendered, so the spoken and written versions of
  /// the numbers cannot drift apart and disagree.
  String _spokenSummary(_Bundle data) {
    final n = data.trail.length;
    final agreed = data.consent.entries
        .where((e) => ConsentLedgerDao.isGranted(e.value))
        .length;
    return '${widget.person.fullName}. This is your record. '
        '$n times a health worker has opened it'
        '${n == 0 ? ', and none of them was outside their duties' : ''}. '
        'You have said yes to $agreed of the ${ConsentScope.values.length} '
        'choices. You can change any of them, and you can ask us to correct '
        'anything that is wrong.';
  }
}

class _TrailSection extends StatelessWidget {
  const _TrailSection({required this.trail, required this.person});

  final List<DisclosureLine> trail;
  final Person person;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CompanionCard(
      title: 'Who has opened this record',
      eyebrow: trail.isEmpty ? null : 'Newest first',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            trail.isEmpty
                ? 'No one has opened this record beyond the worker who wrote '
                      'it. You are allowed to ask this question at any visit, '
                      'and the answer must be given to you.'
                : 'Each line is one time someone looked. Ask about any of them '
                      'and the worker must explain why.',
            style: theme.textTheme.bodyMedium,
          ),
          for (final line in trail.take(20)) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),
            // A sentence, not a row. The purpose and the basis are folded into
            // ordinary language because "basis: legitimateRelationship" is not a
            // disclosure a family can act on.
            Text(
              _sentence(line),
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            if (line.flagged) ...[
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.help_outline_rounded,
                    size: 16,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'This one has not been explained yet. You can ask the '
                      'district supervisor to explain it.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  String _sentence(DisclosureLine line) {
    final when = DateFormat('d MMMM yyyy').format(line.occurredAt);
    final who = '${line.actorName}, ${line.actorRole}';
    final extra = (line.note ?? '').trim();
    // The five purposes the policy can actually produce, each said as a reason a
    // person would recognise. A purpose enum value on its own is not a disclosure.
    final what = switch (line.purpose) {
      AccessPurpose.continuingCare =>
        'opened this record to look after ${_object()}',
      AccessPurpose.emergency =>
        'opened this record in an emergency, when ${_object()} was in danger '
            'and the family could not be reached',
      AccessPurpose.accountReview =>
        'opened this record to check who has looked at it, as part of '
            'supervision',
      AccessPurpose.ownRecord =>
        'opened this record because it belongs to your own family',
      AccessPurpose.unstated =>
        'opened this record for a reason that was not written down',
    };
    return '$who $what, on $when.'
        '${extra.isEmpty ? '' : ' They wrote: \u201c$extra.\u201d'}';
  }

  /// Her / his / them — said plainly, and never guessed. Where sex was not
  /// registered the sentence stays grammatical with "them" rather than inventing
  /// a gender for a child.
  String _object() => switch (person.sex) {
    .female => 'her',
    .male => 'him',
    null => 'them',
  };
}

class _ConsentSection extends StatelessWidget {
  const _ConsentSection({
    required this.consent,
    required this.person,
    required this.busy,
    required this.onSet,
  });

  final Map<ConsentScope, ConsentEvent?> consent;
  final Person person;
  final bool busy;
  final void Function(ConsentScope, bool) onSet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final months = person.ageInMonths;
    // Under five an adult decides for the child. Where the age was never
    // registered the page does not guess parenthood — it simply offers the
    // choice to the person holding the phone.
    final isChild = months != null && months < 180;
    return CompanionCard(
      title: 'What you have agreed to',
      eyebrow: isChild
          ? 'You answer for ${person.fullName}'
          : 'You can change any of these',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Saying no to one of these does not stop the care you are '
            'entitled to at the CHPS compound.',
            style: theme.textTheme.bodyMedium,
          ),
          for (final scope in ConsentScope.values)
            _ConsentRow(
              scope: scope,
              event: consent[scope],
              personName: person.fullName,
              busy: busy,
              onSet: onSet,
            ),
        ],
      ),
    );
  }
}

class _ConsentRow extends StatelessWidget {
  const _ConsentRow({
    required this.scope,
    required this.event,
    required this.personName,
    required this.busy,
    required this.onSet,
  });

  final ConsentScope scope;
  final ConsentEvent? event;
  final String personName;
  final bool busy;
  final void Function(ConsentScope, bool) onSet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final granted = ConsentLedgerDao.isGranted(event);
    // The first scope is the one care cannot be delivered without; a switch here
    // would invite a family to turn off their own treatment, so it is shown as a
    // stated fact instead.
    if (scope == ConsentScope.shareCareTeam) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 16,
              color: theme.textTheme.bodySmall?.color,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    scope.label,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'This one is not a choice. Without it the district team '
                    'cannot see the record that keeps $personName '
                    'well — but it stays inside health care.',
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        value: granted,
        onChanged: busy ? null : (v) => onSet(scope, v),
        title: Text(
          scope.label,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          event == null
              ? '${scope.hint} · not asked yet'
              : '${scope.hint} · ${DateFormat('d MMM y').format(event!.occurredAt)}',
          style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
        ),
      ),
    );
  }
}

class _RightsSection extends StatelessWidget {
  const _RightsSection({
    required this.requests,
    required this.busy,
    required this.onRaise,
  });

  final List<RightsRequest> requests;
  final bool busy;
  final void Function(DataRight) onRaise;

  static const _askable = [
    DataRight.rectification,
    DataRight.portability,
    DataRight.objection,
    DataRight.erasure,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final open = requests.where((r) => r.status == RequestStatus.open).toList();
    return CompanionCard(
      title: 'Ask us to do something',
      eyebrow: 'Answer within ${CareNotice.serviceDeadlineLabel}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'These are your rights, not requests for a favour. Sending one '
            'opens a task with a deadline that a supervisor can see.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final right in _askable)
                OutlinedButton(
                  onPressed: busy ? null : () => onRaise(right),
                  child: Text(_buttonLabel(right)),
                ),
            ],
          ),
          if (requests.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'What you have asked for',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            for (final request in requests.take(8))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      request.status == RequestStatus.fulfilled
                          ? Icons.check_circle_outline_rounded
                          : request.isOverdue(DateTime.now())
                          ? Icons.schedule_rounded
                          : Icons.pending_outlined,
                      size: 16,
                      color: theme.textTheme.bodySmall?.color,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${request.right.label} · sent '
                        '${DateFormat('d MMM y').format(request.requestedAt)} · '
                        '${_statusLabel(request, open.length)}',
                        style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  String _buttonLabel(DataRight right) => switch (right) {
    DataRight.rectification => 'Correct something wrong',
    DataRight.portability => 'Give me a copy to carry',
    DataRight.objection => 'Object to a use',
    DataRight.erasure => 'Ask for it erased',
    DataRight.access => 'See who opened it',
  };

  String _statusLabel(RightsRequest request, int openCount) {
    if (request.status == RequestStatus.fulfilled) return 'done';
    if (request.status == RequestStatus.refused) {
      // A refusal that gives no reason is not an answer, so the wording points
      // at the missing explanation rather than pretending closure.
      return 'refused — ask them why';
    }
    return request.isOverdue(DateTime.now())
        ? 'still unanswered — this one is late'
        : 'waiting ($openCount open)';
  }
}
