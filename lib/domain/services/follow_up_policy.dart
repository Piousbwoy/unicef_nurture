/// The rules that turn a follow-up answer into a record.
///
/// Kept apart from both the widgets and the database for one reason: these are
/// the decisions the referral system is actually making, and they deserve to be
/// read, argued with and tested without a phone, a screen or a file.
///
/// The rule they exist to fix:
///
/// **An answer is not a status.** A family who walked to the facility, queued
/// from 6am, and went home untreated had *arrived* — and `arrived` is not an
/// open state, so under the old model their child silently left the chase list
/// while still being sick. Here the answer decides, and "attended but
/// untreated" stays actionable because the ledger says so, not the lifecycle.
library;

import '../entities/visit.dart';
import '../enums.dart';

/// What the worker found. Four taps and a line of notes — the whole of the
/// check-in screen's payload.
///
/// Every field keeps its `unknown` value legal. A worker who reached the
/// compound but not the family must be able to say so truthfully, and the app
/// must not upgrade that into an outcome nobody observed.
class FollowUpAnswer {
  const FollowUpAnswer({
    required this.channel,
    required this.reached,
    required this.care,
    required this.condition,
    this.barriers = const {},
    this.note,
  });

  final FollowUpChannel channel;
  final FollowUpReach reached;
  final FollowUpCare care;
  final FollowUpCondition condition;

  /// Why care did not happen, when it did not.
  final Set<CareBarrier> barriers;
  final String? note;

  /// Nobody was home / nothing could be confirmed. Counts as an attempt, which
  /// is how two quiet afternoons become a trace rather than a gap in the data.
  bool get isAttemptOnly => reached == FollowUpReach.unknown;
}

/// The fresh referral a worsening child needs, stated by the screen that asks
/// for it.
///
/// [id] and [referenceCode] come from the caller rather than being minted here
/// because the family is shown the code *before* the save. A code minted at
/// commit time would change on the worker's second tap after a slow write, and
/// a family holding `CB-QQ4T` while the register says `CB-8W2P` has two slips
/// for one child.
class FollowUpReReferral {
  const FollowUpReReferral({
    required this.id,
    required this.referenceCode,
    required this.facilityName,
    required this.reason,
    required this.urgency,
  });

  final String id;
  final String referenceCode;
  final String facilityName;
  final String reason;
  final ReferralUrgency urgency;
}

/// Where the case sits on the desk after an answer.
enum FollowUpOutcome {
  /// Nobody could be reached. The referral is still open and the attempt is on
  /// the record.
  attemptLogged('Attempt logged', 'Nobody reached. Try again or phone ahead.'),

  /// Care was confirmed delivered. The trace ends here.
  settled('Settled', 'Care confirmed. This referral is closed.'),

  /// The patient died. The chase ends honestly, not as a lost child.
  deceased('Death recorded', 'The patient died. This referral is closed.'),

  /// The family declined, or the referral was cancelled. Closed on purpose.
  closed('Case closed', 'This referral is closed and no longer chased.'),

  /// An answer exists, and it is not "the child was treated".
  stillWaiting(
    'Needs action',
    'Answered, but the child still needs care.',
  ),

  /// The child was worse or unchanged, and a chained referral was raised.
  reReferred(
    'Re-referred',
    'A new referral has been raised under this case.',
  );

  const FollowUpOutcome(this.label, this.explanation);
  final String label;
  final String explanation;

  /// True when the case must stay on the worker's list.
  bool get needsMoreWork =>
      this == attemptLogged || this == stillWaiting || this == reReferred;
}

/// The outcome of [CareRepository.recordFollowUp]: what was written, and what
/// the desk should now show.
typedef FollowUpResult = ({
  FollowUpOutcome outcome,
  FollowUpContact contact,
  Referral referral,
  Referral? raised,
});

/// Visits that found nobody before a case is treated as a trace rather than a
/// single missed afternoon.
///
/// Two, not three: a CHPS worker's day is a walk, and a third try costs a
/// family another day of being watched while the answer stays unknown.
const int kUnansweredAttemptsBeforeTrace = 2;

/// The status an answer implies, or null when it implies no change.
///
/// Null matters as much as a status here. An unanswered attempt must leave the
/// lifecycle exactly where it was — writing `didNotAttend` because nobody
/// answered a knock would turn a missed visit into a family that refused care,
/// which is the kind of entry that follows a household for years.
ReferralStatus? statusImpliedBy(
  FollowUpAnswer answer,
  {
  required ReferralStatus from,
}) {
  // Death is the strongest fact on the record and outranks the journey. A
  // patient who has died closes the case as a death whatever the family did or
  // did not do at the facility — this is the IMCI child the old flow lost by
  // marking "attended" and never asking how the patient was.
  final target =
      answer.reached != FollowUpReach.unknown &&
          answer.condition == FollowUpCondition.died
      ? ReferralStatus.died
      : switch (answer.reached) {
          FollowUpReach.unknown => null,
          // A refusal is a decision, not a missed afternoon: it closes the case.
          FollowUpReach.declined => ReferralStatus.refused,
          FollowUpReach.didNotGo => ReferralStatus.didNotAttend,
          // Went. Treatment is only claimed when it was seen; anything else —
          // still queued, turned away, outcome unknown — confirms arrival.
          FollowUpReach.went => answer.care == FollowUpCare.seenTreated
              ? ReferralStatus.treated
              : ReferralStatus.arrived,
        };
  if (target == null || !_canMove(from, target)) return null;
  return target;
}

/// Whether the lifecycle may move from [from] to [to].
///
/// Forward only, and never out of a settled state. A confirmed treatment, a
/// refusal, a cancellation and a death are decisions someone made on purpose;
/// a later household visit is evidence about the child, not a licence to
/// reopen the paperwork.
bool _canMove(ReferralStatus from, ReferralStatus to) {
  if (from == to) return false;
  // A settled case is never reopened by a later answer about the patient.
  if (from.isSettled) return false;
  // Death and refusal are facts learned later; they may land on any open case.
  if (to == ReferralStatus.died || to == ReferralStatus.refused) return true;
  return switch (from) {
    ReferralStatus.issued || ReferralStatus.travelling => true,
    // Arrival can still become treatment. It cannot become "did not attend".
    ReferralStatus.arrived => to == ReferralStatus.treated,
    _ => false,
  };
}

/// Whether a verifier at the facility may record [to] against a referral
/// currently in [from]. This is the facility-side sibling of [_canMove]: the
/// three states a health worker can witness in person — arrival, treatment,
/// death — and nothing else. Refusal and non-attendance stay out; they are
/// things the family reports, not things a facility attests.
///
/// A settled case is never reopened here either, so a mistyped or stale
/// reference code cannot rewrite a closed record into a fresh outcome.
bool facilityOutcomeAllowed(ReferralStatus from, ReferralStatus to) =>
    to.isFacilityConfirmable && !from.isSettled;

/// The desk bucket an answer lands in.
FollowUpOutcome followUpOutcomeFor({
  required FollowUpAnswer answer,
  required Referral referral,
  required Referral? raised,
}) {
  if (raised != null) return FollowUpOutcome.reReferred;
  if (answer.isAttemptOnly) return FollowUpOutcome.attemptLogged;
  return switch (referral.status) {
    ReferralStatus.treated => FollowUpOutcome.settled,
    ReferralStatus.died => FollowUpOutcome.deceased,
    ReferralStatus.refused ||
    ReferralStatus.cancelled => FollowUpOutcome.closed,
    _ => FollowUpOutcome.stillWaiting,
  };
}

// ------------------------------------------------------------------- The desk

/// One referral with everything the desk knows about it: its answers, in order,
/// and whether the household is on the route today.
class FollowUpCase {
  const FollowUpCase({
    required this.referral,
    required this.trace,
    required this.householdId,
    required this.onRoute,
    required this.now,
  });

  final Referral referral;

  /// Every contact recorded against this referral, oldest first — the trace a
  /// district nurse reads as "we chased this, here is what we found".
  final List<FollowUpContact> trace;

  /// Null when the person behind the referral is no longer on file. The case
  /// stays on the desk regardless: an unanswerable referral is still a referral
  /// someone issued, and dropping it silently is how a child disappears.
  final String? householdId;

  /// True when today's route passes this household, so an answer costs a detour
  /// rather than a day.
  final bool onRoute;
  final DateTime now;

  FollowUpContact? get latest => trace.isEmpty ? null : trace.last;

  /// Attempts that found nobody. Two of these and the case is a trace, not a
  /// missed afternoon.
  int get attempts => trace.where((c) => !c.isAnswered).length;

  /// Every barrier this case has produced, across all its answers.
  Set<CareBarrier> get blockers => {
    for (final contact in trace)
      ...contact.barriers,
  };

  bool get isChained => referral.linkFromReferralId != null;

  /// This case's own answer raised a fresh referral, so the live work has moved
  /// to that one. The trace shows the handover; the desk does not list the
  /// case twice for one child.
  bool get handedOver => latest?.linkedReferralId != null;

  /// The loop ended one way or the other: care confirmed, someone closed it on
  /// purpose, or the answer re-referred the patient. Anything else is work.
  ///
  /// Note what is *not* here: `arrived`. An arrival that produced no answer is
  /// the exact case the old chase list lost.
  bool get isClosed => referral.status.isSettled || handedOver;

  Duration get age => now.difference(referral.issuedAt);

  /// Urgent, unconfirmed and past 48 hours: the referral that should already
  /// have a supervisor's attention.
  bool get isOverdue =>
      !isClosed &&
      referral.escalatedAt == null &&
      age >= const Duration(hours: 48) &&
      (referral.urgency == ReferralUrgency.immediate ||
          referral.urgency == ReferralUrgency.sameDay);

  bool get isTraced => referral.escalatedAt != null;

  /// The single next action this card can offer. Kept to one so the desk never
  /// presents a list of plausible taps and makes the worker guess.
  FollowUpNextStep get nextStep {
    if (isClosed) return FollowUpNextStep.none;
    if (latest?.isAnswered ?? false) return FollowUpNextStep.reviewAnswer;
    return onRoute ? FollowUpNextStep.answerNow : FollowUpNextStep.bringOnRoute;
  }
}

/// The one action a desk card offers.
enum FollowUpNextStep {
  answerNow('Answer it at this visit', 'This household is on today’s route.'),
  bringOnRoute(
    'Put this household on a route',
    'No visit planned soon — the answer needs a trip.',
  ),
  reviewAnswer(
    'Record what changed',
    'Answered, and the care is still not confirmed.',
  ),
  none('', '');

  const FollowUpNextStep(this.label, this.hint);
  final String label;
  final String hint;
}

/// The desk, already sorted into the three things a worker can be asked about.
class FollowUpDesk {
  const FollowUpDesk({
    required this.awaitingAnswer,
    required this.needsAction,
    required this.settled,
  });

  /// No answer yet. Route-first, then urgent, then oldest.
  final List<FollowUpCase> awaitingAnswer;

  /// Someone answered, and the answer was not "treated".
  final List<FollowUpCase> needsAction;

  /// Closed cases. Read-only evidence, newest first, hidden behind a count.
  final List<FollowUpCase> settled;

  int get awaitingCount => awaitingAnswer.length;
  int get actionCount => needsAction.length;
  int get settledCount => settled.length;

  bool get isEmpty =>
      awaitingAnswer.isEmpty && needsAction.isEmpty && settled.isEmpty;
}

/// Sort the last 21 days of referrals into the desk.
///
/// Pure, so the ordering a worker trusts can be read without running the app —
/// and so a change to the sort is a change to a rule, not to a widget.
FollowUpDesk buildFollowUpDesk({
  required List<Referral> referrals,
  required Map<String, List<FollowUpContact>> ledger,
  required Map<String, String> householdOf,
  required Set<String> routeHouseholds,
  required DateTime now,
}) {
  final cases = [
    for (final referral in referrals)
      FollowUpCase(
        referral: referral,
        trace: _chronological(ledger[referral.id]),
        householdId: householdOf[referral.personId],
        onRoute: routeHouseholds.contains(householdOf[referral.personId]),
        now: now,
      ),
  ];
  final awaiting = <FollowUpCase>[
    for (final c in cases)
      if (!c.isClosed && !(c.latest?.isAnswered ?? false)) c,
  ]..sort(_workOrder);
  final action = <FollowUpCase>[
    for (final c in cases)
      if (!c.isClosed && (c.latest?.isAnswered ?? false)) c,
  ]..sort(_workOrder);
  final closed = <FollowUpCase>[
    for (final c in cases)
      if (c.isClosed) c,
  ]..sort((a, b) => b.referral.issuedAt.compareTo(a.referral.issuedAt));
  return FollowUpDesk(
    awaitingAnswer: awaiting,
    needsAction: action,
    settled: closed,
  );
}

List<FollowUpContact> _chronological(List<FollowUpContact>? contacts) {
  if (contacts == null || contacts.isEmpty) return const [];
  return [...contacts]..sort((a, b) => a.at.compareTo(b.at));
}

/// Route first — a visit already happening is the cheapest answer there is —
/// then acuity, then how long the family has been waiting.
int _workOrder(FollowUpCase a, FollowUpCase b) {
  if (a.onRoute != b.onRoute) return a.onRoute ? -1 : 1;
  final byUrgency = _rank(a.referral).compareTo(_rank(b.referral));
  if (byUrgency != 0) return byUrgency;
  return a.referral.issuedAt.compareTo(b.referral.issuedAt);
}

int _rank(Referral r) => switch (r.urgency) {
  ReferralUrgency.immediate => 0,
  ReferralUrgency.sameDay => 1,
  ReferralUrgency.withinTwoDays => 2,
  ReferralUrgency.scheduled => 3,
};
