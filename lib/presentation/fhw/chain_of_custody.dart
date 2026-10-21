/// Chain of custody — the record's access trail, shown to the worker who is
/// accountable for it.
///
/// ### Why this is a section on the record and not an admin screen
///
/// An audit log that lives somewhere else is a compliance artefact: it exists, it
/// satisfies someone, and nobody reads it. Put the trail on the record itself,
/// where the worker already is, and it becomes a fact about the care rather than a
/// fact about the system — the same reason the register shows a referral's trace
/// line instead of linking to a report.
///
/// ### What the integrity line is, and what it is not
///
/// `verify()` walks the device's own hash chain. Intact means every entry still
/// hashes to the one before it, so nothing has been edited or removed *in the copy
/// on this phone*. It is deliberately worded that way on screen: an intact chain
/// is not a promise that nobody looked at something they should not have, it is a
/// promise that the record of who looked can be trusted. Overstating it would make
/// the whole feature a lie with extra steps.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/fhw_luxe.dart';
import '../../data/local/compliance_dao.dart';
import '../../domain/compliance.dart';
import '../../domain/entities/core.dart';
import '../shared/ui.dart';
import 'clinic_widgets.dart';

/// The card on the household record. A summary line, because a worker scanning
/// their register should learn something without tapping — and a count of
/// accesses by other facilities is exactly the kind of fact worth glancing at.
class ChainOfCustodySection extends ConsumerStatefulWidget {
  const ChainOfCustodySection({
    super.key,
    required this.household,
    required this.members,
  });

  final Household household;
  final List<Person> members;

  @override
  ConsumerState<ChainOfCustodySection> createState() =>
      _ChainOfCustodySectionState();
}

class _ChainOfCustodySectionState extends ConsumerState<ChainOfCustodySection> {
  Future<List<DisclosureLine>>? _trail;

  @override
  void initState() {
    super.initState();
    _trail = _fetch();
  }

  @override
  void didUpdateWidget(ChainOfCustodySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Read once, and again only when this family's trail could actually have
    // changed. A future built inside build() is a new future on every rebuild:
    // it re-queries the ledger each time the register repaints, and flashes back
    // to "counting" in front of the worker.
    if (oldWidget.household.id != widget.household.id ||
        _subject(oldWidget.members) != _subject(widget.members)) {
      setState(() => _trail = _fetch());
    }
  }

  /// A household with no members registered yet is still a record with a
  /// history, so the household id carries the trail rather than the card quietly
  /// disappearing.
  String _subject(List<Person> members) =>
      members.isEmpty ? widget.household.id : members.first.id;

  Future<List<DisclosureLine>> _fetch() {
    final user = ref.read(currentUserProvider);
    if (user == null) return Future<List<DisclosureLine>>.value(const []);
    return ref
        .read(careRepositoryProvider)
        .accessTrail(
          user,
          subjectPersonId: _subject(widget.members),
          householdId: widget.household.id,
        );
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(currentUserProvider) == null) return const SizedBox.shrink();

    return ClinicCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChainOfCustodyScreen(
            household: widget.household,
            members: widget.members,
          ),
        ),
      ),
      child: FutureBuilder<List<DisclosureLine>>(
        future: _trail,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            // An unreadable trail is stated, not hidden. A section that vanishes
            // on error is how a system looks compliant.
            return Text(
              'The access record for this family could not be read: '
              '${snapshot.error}',
              style: AppType.caption.copyWith(
                color: FhwLuxePalette.textSecondary,
              ),
            );
          }
          if (!snapshot.hasData) {
            return Text(
              'Counting the times this record has been opened…',
              style: AppType.caption.copyWith(
                color: FhwLuxePalette.textSecondary,
              ),
            );
          }
          final lines = snapshot.data!;
          final flagged = lines.where((l) => l.flagged).length;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.history_rounded,
                    size: 16,
                    color: FhwLuxePalette.sapphireRoyal,
                  ),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: Text(
                      'Chain of custody',
                      style: AppType.label.copyWith(fontSize: 14),
                    ),
                  ),
                  Text(
                    lines.isEmpty
                        ? 'No access yet'
                        : '${lines.length} recorded',
                    style: AppType.caption.copyWith(
                      fontSize: 12,
                      color: FhwLuxePalette.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Gap.sm),
              Text(
                lines.isEmpty
                    ? 'Nobody has opened this record beyond the worker who made '
                          'it. Every access is written down, and this family can '
                          'ask for the list.'
                    : 'Every time this record is opened, who and why are written '
                          'down. '
                          '${flagged == 0 ? 'None need review.' : '$flagged need a supervisor’s review.'}',
                style: AppType.caption.copyWith(
                  color: FhwLuxePalette.textSecondary,
                  height: 1.45,
                ),
              ),
              if (flagged > 0) ...[
                const SizedBox(height: Gap.sm),
                // Colour never carries the warning alone — the word does too.
                Row(
                  children: [
                    const Icon(
                      Icons.rule_rounded,
                      size: 15,
                      color: FhwLuxePalette.clinicalAmber,
                    ),
                    const SizedBox(width: Gap.xs),
                    Expanded(
                      child: Text(
                        'Access with no consent and no caseload link',
                        style: AppType.caption.copyWith(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: FhwLuxePalette.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// The full trail for one family: integrity first, then the accesses, then what
/// the family actually agreed to.
class ChainOfCustodyScreen extends ConsumerStatefulWidget {
  const ChainOfCustodyScreen({
    super.key,
    required this.household,
    required this.members,
  });

  final Household household;
  final List<Person> members;

  @override
  ConsumerState<ChainOfCustodyScreen> createState() =>
      _ChainOfCustodyScreenState();
}

class _ChainOfCustodyScreenState extends ConsumerState<ChainOfCustodyScreen> {
  Future<_CustodyReport>? _load;

  @override
  void initState() {
    super.initState();
    _load = _fetch();
  }

  Future<_CustodyReport> _fetch() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return _CustodyReport.noUser();
    final repo = ref.read(careRepositoryProvider);
    // The trail is one query per person plus the household, because a household
    // access and a person access are recorded against different subjects and both
    // belong in the family's answer.
    final lines = <DisclosureLine>[];
    final consent = <String, Map<ConsentScope, ConsentEvent?>>{};
    for (final person in widget.members) {
      lines.addAll(
        await repo.accessTrail(
          user,
          subjectPersonId: person.id,
          householdId: widget.household.id,
        ),
      );
      consent[person.id] = await repo.consentFor(user, person.id);
    }
    lines.sort(
      (a, b) => b.occurredAt.compareTo(a.occurredAt),
    ); // newest first: the question is always "recently?".
    return _CustodyReport(
      integrity: await repo.verifyAccessTrail(user),
      lines: lines,
      consent: consent,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FhwLuxePalette.porcelainCanvas,
      appBar: AppBar(
        backgroundColor: FhwLuxePalette.porcelainCanvas,
        surfaceTintColor: Colors.transparent,
        foregroundColor: FhwLuxePalette.textPrimary,
        title: const Text('Chain of custody'),
      ),
      body: FutureBuilder<_CustodyReport>(
        future: _load,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorView(error: snapshot.error!);
          }
          final report = snapshot.data;
          if (report == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(Gap.lg),
            children: [
              _IntegrityCard(
                verdict: report.integrity,
                onRecheck: () => setState(() => _load = _fetch()),
              ),
              const SizedBox(height: Gap.lg),
              _TrailCard(lines: report.lines),
              const SizedBox(height: Gap.lg),
              _ConsentCard(consent: report.consent, members: widget.members),
              const SizedBox(height: Gap.lg),
              const _LimitCard(),
            ],
          );
        },
      ),
    );
  }
}

class _CustodyReport {
  const _CustodyReport({
    required this.integrity,
    required this.lines,
    required this.consent,
  });

  _CustodyReport.noUser()
    : integrity = const ChainVerification.empty(),
      lines = const [],
      consent = const {};

  final ChainVerification integrity;
  final List<DisclosureLine> lines;
  final Map<String, Map<ConsentScope, ConsentEvent?>> consent;
}

/// The verify control. Green means "this copy has not been altered", and the line
/// says exactly that rather than something grander.
class _IntegrityCard extends StatelessWidget {
  const _IntegrityCard({required this.verdict, required this.onRecheck});

  final ChainVerification verdict;
  final VoidCallback onRecheck;

  @override
  Widget build(BuildContext context) {
    // An empty trail is not a verified trail. The verdict type calls it valid,
    // because nothing has contradicted it — and the card says what is actually
    // true instead: there is nothing to check yet.
    final empty = verdict is ChainEmpty;
    final ok = verdict.isValid && !empty;
    final glyph = empty
        ? Icons.history_rounded
        : (ok
              ? Icons.verified_user_outlined
              : Icons.report_gmailerrorred_rounded);
    return LumenCard(
      // A verdict about data, not about a patient: the plate stays sapphire. Red
      // and amber here would spend the colours the app reserves for clinical
      // danger, and a broken trail is signalled by the sentence plus the icon.
      title: 'Is this record of accesses intact?',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(glyph, size: 18, color: Colors.white),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text(
                  verdict.humanMessage,
                  style: AppType.body.copyWith(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.md),
          Text(
            empty
                ? 'Nothing has been written to the trail on this handset yet, so '
                      'there is no seal to break. The first access from now on '
                      'starts the chain, and every line after it will carry the '
                      'seal of the one before it.'
                : ok
                ? 'Each line is sealed with the line before it, so a change '
                      'anywhere in the history would show up here. It says nothing '
                      'about whether an access was correct — only that the record '
                      'of it has not been edited or deleted.'
                : 'Stop and report this. A line in the trail no longer matches the '
                      'seal on the next one, which means the history was altered '
                      'or a row was removed after it was written.',
            style: AppType.caption.copyWith(
              color: FhwLuxePalette.lacquerInk,
              height: 1.5,
            ),
          ),
          const SizedBox(height: Gap.sm),
          TextButton.icon(
            onPressed: onRecheck,
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: const Text('Re-check now'),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _TrailCard extends StatelessWidget {
  const _TrailCard({required this.lines});

  final List<DisclosureLine> lines;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Who has opened this record',
      subtitle: lines.isEmpty
          ? 'No access has been recorded beyond the worker who created the '
                'register entry.'
          : 'Newest first. Every line names the worker, the reason they were '
                'allowed in, and the handset it happened on.',
      icon: Icons.fact_check_outlined,
      child: Column(
        children: [
          for (final line in lines.take(60)) _TrailLine(line: line),
          if (lines.length > 60)
            Padding(
              padding: const EdgeInsets.only(top: Gap.sm),
              child: Text(
                '+${lines.length - 60} older accesses',
                style: AppType.caption,
              ),
            ),
        ],
      ),
    );
  }
}

class _TrailLine extends StatelessWidget {
  const _TrailLine({required this.line});

  final DisclosureLine line;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  line.actorName,
                  style: AppType.label.copyWith(fontSize: 13.5),
                ),
              ),
              if (line.flagged)
                const Icon(
                  Icons.rule_rounded,
                  size: 15,
                  color: FhwLuxePalette.clinicalAmber,
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${DateFormat('d MMM, HH:mm').format(line.occurredAt)} · '
            '${line.purpose.label.toLowerCase()} · ${line.basis.label.toLowerCase()}',
            style: AppType.caption.copyWith(
              fontSize: 11.5,
              color: FhwLuxePalette.textSecondary,
              height: 1.4,
            ),
          ),
          if (line.note != null && line.note!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              line.note!,
              style: AppType.caption.copyWith(
                fontSize: 11.5,
                fontStyle: FontStyle.italic,
                color: FhwLuxePalette.textSecondary,
                height: 1.4,
              ),
            ),
          ],
          const Divider(height: Gap.lg),
        ],
      ),
    );
  }
}

class _ConsentCard extends StatelessWidget {
  const _ConsentCard({required this.consent, required this.members});

  final Map<String, Map<ConsentScope, ConsentEvent?>> consent;
  final List<Person> members;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'What this family agreed to',
      subtitle:
          'Each decision is recorded against the notice they were shown, '
          'and a withdrawal never erases the answer before it.',
      icon: Icons.handshake_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entry in consent.entries)
            for (final scope in ConsentScope.values)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Gap.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _icon(ConsentLedgerDao.isGranted(entry.value[scope])),
                      size: 15,
                      color: _colour(
                        context,
                        ConsentLedgerDao.isGranted(entry.value[scope]),
                        entry.value[scope],
                      ),
                    ),
                    const SizedBox(width: Gap.sm),
                    Expanded(
                      child: Text(
                        '${_personName(entry.key)}: ${scope.label}',
                        style: AppType.caption.copyWith(fontSize: 12.5),
                      ),
                    ),
                    Text(
                      _state(entry.value[scope]),
                      style: AppType.caption.copyWith(
                        fontSize: 11.5,
                        color: FhwLuxePalette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  String _personName(String id) => members
      .firstWhere((m) => m.id == id, orElse: () => members.first)
      .fullName;

  IconData _icon(bool granted) =>
      granted ? Icons.check_circle_outline_rounded : Icons.cancel_outlined;

  Color _colour(BuildContext context, bool granted, ConsentEvent? event) =>
      event == null
      ? FhwLuxePalette.textFaint
      : granted
      ? FhwLuxePalette.emeraldPulse
      : FhwLuxePalette.textSecondary;

  String _state(ConsentEvent? event) {
    if (event == null) return 'never asked';
    return switch (event.decision) {
      ConsentDecision.granted => 'yes · ${event.language}',
      ConsentDecision.withdrawn => 'withdrawn',
      ConsentDecision.objected => 'objected',
    };
  }
}

/// Says out loud what the screen cannot see, because a trust claim that omits its
/// own boundary is worth less than a smaller claim that states it.
class _LimitCard extends StatelessWidget {
  const _LimitCard();

  @override
  Widget build(BuildContext context) {
    return ClinicCard(
      title: 'What this page cannot see',
      child: Text(
        'This is the trail held on this handset. Lines written here are pushed to '
        'the district server with everything else, but an access made on another '
        'worker\'s phone does not come back to this screen: the trail goes up and is '
        'never pulled down, deliberately — who read whose record is itself patient '
        'data, and until the district has a supervisory role to scope it to, the '
        'place a cross-device history is read is the server, not a field handset. So '
        'a record that looks untouched here may have been opened elsewhere today. '
        'And a look at a printed or spoken copy leaves no line at all, which is why '
        'the paper register and this one are kept side by side rather than '
        'pretended away.',
        style: AppType.caption.copyWith(
          color: FhwLuxePalette.textSecondary,
          height: 1.5,
        ),
      ),
    );
  }
}
