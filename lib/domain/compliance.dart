/// The accountability core: purpose, lawful basis, consent, and a tamper-evident
/// access chain.
///
/// ### Why this file exists
///
/// A health record system that cannot answer *"who opened this child's record,
/// why, and under what authority"* is not a clinical system — it is a database
/// with a stethoscope. Ghana's Data Protection Act, 2012 (Act 843) treats health
/// data as **special personal data**: processing is prohibited unless a stated
/// condition applies. So the app must not merely *avoid* misuse; it must be able
/// to *show* that every single access had a lawful reason, including accesses
/// nobody thought to ask about.
///
/// Two properties are load-bearing here, and they are the two that separate a
/// log from an evidence trail:
///
///  1. **Every access carries a purpose and a basis.** Not "user 7 read row 12"
///     but "user 7 opened this record *to continue her own caseload*". A log
///     without purpose cannot be reviewed, because the reviewer cannot tell a
///     legitimate look from a curiosity.
///
///  2. **The trail is tamper-evident.** Each entry commits to the hash of the
///     entry before it, and each hash is keyed with a secret held in the
///     device's secure enclave (Android Keystore via flutter_secure_storage) —
///     not in the database an attacker would edit. Alter or delete one line and
///     every line after it fails to verify. That is the difference between
///     "trust our logs" and "test our logs".
///
/// ### What the chain does *not* claim
///
/// A keyed chain on one device proves that whoever holds the database file did
/// not quietly rewrite history *without also holding that device's key*. It is
/// not a third-party witness. The production answer is anchoring the periodic
/// chain head to an independent timestamp authority (RFC 3161) or an append-only
/// transparency log with inclusion proofs; the [SealedChain] seam below is
/// deliberately the only place that has to change, and the head hash is already
/// pushed to the district server so an off-device copy of the trail exists from
/// day one.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Purpose and basis: the two fields that make an access reviewable
// ─────────────────────────────────────────────────────────────────────────────

/// Why the record is being opened.
///
/// Purpose limitation (Act 843; GDPR Art. 5(1)(b)) means a grant for one purpose
/// is not a grant for another. A caregiver consenting to *care* has not
/// consented to *research* — and this app already runs on-device models, so the
/// difference is not academic.
enum AccessPurpose {
  /// The worker is delivering care to this patient now: assessment, referral,
  /// follow-up, or a visit at the compound.
  continuingCare('Continue care', 'This patient is in this worker’s caseload'),

  /// The patient is not the worker's own, but care is on the clock — a danger
  /// sign, an urgent referral, or a child in front of them.
  emergency('Emergency care', 'Urgent clinical need, relationship unverified'),

  /// Someone is checking the trail itself, not the patient: an audit or
  /// supervision review of who has seen a record.
  accountReview('Review of access', 'Audit or supervision review'),

  /// The person whose record it is, or their own family.
  ownRecord('Own record', 'The data subject or their own household'),

  /// No stated reason was given, and none could be inferred.
  unstated('No purpose recorded', 'Purpose was not captured');

  const AccessPurpose(this.label, this.shortReason);
  final String label;
  final String shortReason;
}

/// The lawful reason the access was permitted.
///
/// Exactly one of these is recorded per access, so the disclosure statement a
/// family receives can say *why* the law allowed it — which is the question a
/// District Director of Health Services or a Data Protection Commission officer
/// actually asks.
enum AccessBasis {
  /// The actor holds this patient's caseload (her own register, or her zone).
  careRelationship('Care relationship'),

  /// The family granted this specific scope, at a specific notice version.
  consent('Consent'),

  /// Life or limb; recorded, flagged, reviewed after the fact.
  vitalInterest('Emergency — vital interests'),

  /// A worker looked outside their caseload with no consent in place. Allowed,
  /// because a nurse must never be blocked from a patient — and *deliberately
  /// uncomfortable*: reason required, flagged to the supervisor, in the family's
  /// disclosure.
  breakGlass('Break-the-glass override'),

  /// A worker acting in a stated official capacity — supervising, auditing, or
  /// answering a family's request. Not consent, not emergency: the basis most
  /// enterprise systems end up needing and most forget to model, so a supervisor's
  /// own reads get recorded as what they are instead of being stretched into
  /// someone's caseload.
  officialAuthority('Official authority — supervision'),

  /// The data subject reading their own record.
  dataSubject('Data subject’s own access'),

  /// Nothing authorised it, and the read was refused.
  none('Refused — no lawful basis');

  const AccessBasis(this.label);
  final String label;
}

/// Records that are held to a narrower rule than the rest of the register.
///
/// ### Why a district-wide caseload is too wide for these
///
/// The ordinary care relationship is the whole district a worker is posted to,
/// which is right for a vaccination schedule and wrong for an HIV result: in a
/// small community, the colleague at the next compound may be a neighbour. So a
/// sensitive record opens without ceremony only for the worker responsible for it
/// and the family itself. Everyone else — including a same-district colleague —
/// can still open it, because care is never blocked, but only by stating why, or
/// in an emergency. The reason is recorded, flagged for review and shown to the
/// family.
///
/// The categories are the ones where disclosure itself does harm in this setting,
/// not a general "private" flag: a marking that is applied to everything protects
/// nothing, because every worker learns to type the same reason.
enum SensitivityCategory {
  hivAndSti('HIV or a sexually transmitted infection'),
  adolescentReproductive('Adolescent sexual or reproductive health'),
  violenceOrAbuse('Violence or abuse'),
  mentalHealth('Mental health'),
  familyRequest('The family asked for extra privacy');

  const SensitivityCategory(this.label);
  final String label;

  /// Null for an unmarked record or a category this build does not know — which
  /// is still treated as sensitive by the policy, because an unreadable marking
  /// must fail closed, not open.
  static SensitivityCategory? fromStored(String? name) {
    if (name == null) return null;
    for (final c in values) {
      if (c.name == name) return c;
    }
    return null;
  }
}

/// Something the shape of the access trail suggests that no single entry does.
///
/// ### Why this exists alongside the finding queue
///
/// A flagged entry answers "was *this* look explained?". It cannot answer "is this
/// worker browsing the district?" or "is everyone at the compound reading the same
/// woman's HIV result?", because each individual read in those patterns can look
/// ordinary on its own. Every patient-privacy monitoring product in real service
/// works on exactly this shift — from single events to volumes.
///
/// ### Why it is phrased as a question and not an accusation
///
/// Both patterns have innocent readings, and the commonest one in this setting is
/// a shared caseload or a mass campaign day. A supervisor who is handed "possible
/// misuse by Aminata Fusea" will defend the worker rather than ask her. So the
/// sentence states only what was counted, and the follow-up is a conversation.
enum AccessPatternKind {
  /// One worker, many families, none of them theirs.
  outOfCaseloadVolume('Records opened outside the worker’s own caseload'),

  /// One sensitive record, read by several different workers in a short window.
  sharedSensitiveSubject('Sensitive record opened by several workers');

  const AccessPatternKind(this.label);
  final String label;
}

class AccessPattern {
  const AccessPattern({
    required this.kind,
    required this.count,
    required this.latest,
    this.actorName,
    this.subjectName,
  });

  final AccessPatternKind kind;

  /// How many — distinct families for [AccessPatternKind.outOfCaseloadVolume],
  /// distinct workers for [AccessPatternKind.sharedSensitiveSubject].
  final int count;
  final DateTime latest;
  final String? actorName;
  final String? subjectName;

  /// Written to be read aloud to a supervisor, counting-first so the number that
  /// justifies the conversation is the first thing they see.
  String get sentence => switch (kind) {
    AccessPatternKind.outOfCaseloadVolume =>
      '$actorName opened $count different family records that are not in their '
          'own caseload, most recently on ${_day(latest)}.',
    AccessPatternKind.sharedSensitiveSubject =>
      '$count different workers opened $subjectName’s protected record, most '
          'recently on ${_day(latest)}.',
  };

  static String _day(DateTime d) =>
      '${d.day}/${d.month}/${d.year} at ${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}

/// What a family can say yes or no to.
///
/// Scopes are deliberately narrow and each one is enforced somewhere real,
/// because a consent control that changes nothing is decoration:
///
///  * [crossFacilitySearch] — whether this family may be *found* by a health
///    worker outside their own zone (identity + minimal index only; the full
///    record still needs a basis). Withdrawal is enforced in
///    `server/src/pull.js`, so the data stops travelling — not just hidden.
///  * [shareCareTeam] — whether the district server may hold the clinical
///    record at all, so other workers can continue the care.
///  * [hospitalHandoff] — whether a printable, signed hand-off summary may be
///    produced for a referral to a hospital.
///  * [researchSecondary] — whether de-identified data may contribute to
///    aggregate health research. Never assumed, and it does not unlock the
///    on-device model outputs.
enum ConsentScope {
  shareCareTeam('Keep the record with the district team', 'Required for care'),
  crossFacilitySearch(
    'Let another health worker find this family',
    'Finds the name only — not the notes',
  ),
  hospitalHandoff(
    'Prepare a signed summary for a hospital',
    'Carried to the facility',
  ),
  researchSecondary(
    'Count this family in anonymised health research',
    'Never names anyone',
  );

  const ConsentScope(this.label, this.hint);
  final String label;
  final String hint;
}

/// A recorded consent decision. Consent is a *history*, not a boolean: what
/// matters legally is which notice the family agreed to, when, in which
/// language, and that a withdrawal is never overwritten.
enum ConsentDecision { granted, withdrawn, objected }

/// A decision as recorded. Immutable — the row is never updated, only
/// superseded by a later one.
class ConsentEvent {
  const ConsentEvent({
    required this.id,
    required this.subjectPersonId,
    required this.scope,
    required this.decision,
    required this.noticeVersion,
    required this.occurredAt,
    required this.capturedBy,
    this.language = 'English',
    this.voiceArtifact,
    this.deviceId,
    this.witnessName,
    this.note,
  });

  final String id;
  final String subjectPersonId;
  final ConsentScope scope;
  final ConsentDecision decision;

  /// Which notice text was actually shown. Bumping [CareNotice.currentVersion]
  /// means every existing grant is provably for an older text, and the app can
  /// ask again rather than assume.
  final String noticeVersion;
  final DateTime occurredAt;
  final String capturedBy;

  /// The language the family was addressed in — and, when it matters most,
  /// whether it was *spoken* to them.
  final String language;

  /// Identity of the audio artefact that voiced the notice (asset + model
  /// version). Recording this is what turns "low-literacy consent" from a
  /// claim into an evidenced fact.
  final String? voiceArtifact;
  final String? deviceId;

  /// For a child or an adult who cannot read: who witnessed the decision.
  final String? witnessName;
  final String? note;

  bool get isGrant => decision == ConsentDecision.granted;
}

// ─────────────────────────────────────────────────────────────────────────────
// The access ledger entry
// ─────────────────────────────────────────────────────────────────────────────

/// One line of the trail.
class AccessRecord {
  const AccessRecord({
    required this.seq,
    required this.actorId,
    required this.actorRole,
    required this.deviceId,
    required this.action,
    required this.entityTable,
    required this.entityId,
    required this.subjectPersonId,
    required this.purpose,
    required this.basis,
    required this.occurredAt,
    required this.entryHash,
    required this.previousHash,
    this.note,
    this.flagged = false,
  });

  final int seq;
  final String actorId;
  final String actorRole;

  /// Which handset, not merely which person: a shared CHPS phone has several
  /// accounts, and "the CHO's PIN from the nurse's device" is a fact worth
  /// keeping separate.
  final String deviceId;
  final String action;
  final String entityTable;
  final String entityId;

  /// Whose record this is — the patient's stable person id. Every query a
  /// family is entitled to make ("who has seen my child?") hangs off this one
  /// column, which is why it is stored on the entry rather than recovered by
  /// joining at read time.
  final String subjectPersonId;
  final AccessPurpose purpose;
  final AccessBasis basis;
  final DateTime occurredAt;
  final String? note;

  /// Set by the policy engine for access that is lawful but deserves a second
  /// look: break-the-glass, off-region, unusual volume, self or family access.
  final bool flagged;

  final String entryHash;
  final String previousHash;

  /// An access that was refused is still evidence. Recording denials is what
  /// lets a supervisor see someone probing at records they cannot reach.
  bool get isDenial => basis == AccessBasis.none;
}

// ─────────────────────────────────────────────────────────────────────────────
// The notice text — versioned, and deliberately short enough to be read aloud
// ─────────────────────────────────────────────────────────────────────────────

/// The plain-language notice a family is asked to agree to.
///
/// Versioned on purpose. If the text changes, previously-recorded consent is
/// consent to the *old* words, and the app must ask again — which is exactly how
/// the version column is used. Every sentence here must be true of the code,
/// because this string is the one a judge can hold you to.
abstract final class CareNotice {
  static const currentVersion = '2026-10-v3';

  /// How often the background timer will push at the latest. Same rule as
  /// [serviceDeadline]: the number in the words a family agrees to and the
  /// interval [SyncService] actually runs on are one number, not two.
  static const syncInterval = Duration(minutes: 15);

  /// Truthful sentences, each one enforceable enough to be tested.
  static const points = <(String, String)>[
    (
      'Kept on this phone first',
      'The health worker records what they find on this phone. It works with no '
          'network and no airtime.',
    ),
    (
      'Sent to the district on its own, when there is signal',
      'When this phone finds a network, the record is copied to the district '
          'team’s server so a nurse at another centre can continue your care. '
          'That happens by itself — within seconds of the signal returning, and '
          'at least every 15 minutes while there is a network. No button needs '
          'pressing, and nothing is held back waiting for one. The day-to-day '
          'checks and notes a family keeps for itself never leave this phone.',
    ),
    (
      'Opened only by people with a reason',
      'Every time a record is opened, the app writes down who opened it, when, '
          'and why. You can ask to see that list.',
    ),
    (
      'You can say no, and change your mind',
      'You can refuse to be found by another zone, ask for a correction, ask for '
          'your record to be erased, or withdraw consent at any time. Anything '
          'already handed to a facility is listed for you, honestly.',
    ),
    (
      'Research never carries your name',
      'If you agree, your record may be counted in a summary of many families. '
          'A summary cannot be traced back to you.',
    ),
  ];

  /// Shown wherever the notice is read, so the promise can be kept: an
  /// incomplete or missing list of who read the record is a defect, not a
  /// design choice.
  static const disclosureHeading = 'Who has seen this record';

  /// One line, safe to speak aloud.
  static const summary =
      'Your health information is kept on this phone, sent to the district team '
      'only to continue your care, and every access to it is recorded with a '
      'reason. You may ask to see those records of access, and you may change '
      'your mind at any time.';

  /// How long the app is allowed to leave a family's request unanswered. Stated
  /// in words here because a promise a screen makes and a deadline a queue
  /// enforces must not be two different numbers.
  static const serviceDeadlineLabel = '30 days';

  /// The turnaround the label above commits to, in the same place.
  static const serviceDeadline = Duration(days: 30);
}

// ─────────────────────────────────────────────────────────────────────────────
// Data-subject rights: a request is a workflow with a deadline, not a button
// ─────────────────────────────────────────────────────────────────────────────

/// The rights Act 843 gives a data subject, expressed as things this app does.
enum DataRight {
  access('See who accessed my record'),
  rectification('Correct something that is wrong'),
  objection('Object to a use I did not agree to'),
  erasure('Have my record erased'),
  portability('Take my record with me');

  const DataRight(this.label);
  final String label;
}

enum RequestStatus { open, fulfilled, refused }

class RightsRequest {
  const RightsRequest({
    required this.id,
    required this.subjectPersonId,
    required this.right,
    required this.requestedAt,
    required this.requestedBy,
    this.subjectName,
    this.status = RequestStatus.open,
    this.resolvedAt,
    this.resolution,
  });

  final String id;
  final String subjectPersonId;

  /// Whose record this concerns, as a name rather than an id. Only the district
  /// queue joins it in, because a family reading their own requests already knows
  /// who they are — and a supervisor working from UUIDs cannot act on anything.
  final String? subjectName;
  final DataRight right;
  final DateTime requestedAt;
  final String requestedBy;
  final RequestStatus status;
  final DateTime? resolvedAt;

  /// What was actually done, in words a person can read back to them. For an
  /// erasure this is where "sealed and scheduled for deletion at the next
  /// backup expiry" is stated rather than glossed over.
  final String? resolution;

  /// Statutory-style turnaround, read from [CareNotice] so the deadline the
  /// notice promises and the one the queue reports are literally the same value
  /// rather than two numbers that happen to agree today.
  static Duration get serviceDeadline => CareNotice.serviceDeadline;

  bool isOverdue(DateTime now) =>
      status == RequestStatus.open &&
      now.difference(requestedAt) > serviceDeadline;
}

// ─────────────────────────────────────────────────────────────────────────────
// The chain itself
// ─────────────────────────────────────────────────────────────────────────────

/// Result of walking the ledger from the first entry to the last.
sealed class ChainVerification {
  const ChainVerification();

  /// Every hash recomputed and matched, including the head seal.
  const factory ChainVerification.intact({required int entries, String? head}) =
      ChainIntact;

  /// Row [seq] does not match the hash committed by its successor: the history
  /// was edited after the fact, or a row was deleted.
  const factory ChainVerification.brokenAt({
    required int seq,
    required String reason,
  }) = ChainBroken;

  /// Nothing to verify yet.
  const factory ChainVerification.empty() = ChainEmpty;

  bool get isValid => this is ChainIntact || this is ChainEmpty;

  String get humanMessage => switch (this) {
    ChainIntact(:final entries, :final head) =>
      'Verified — $entries access record${entries == 1 ? '' : 's'} intact'
          '${head == null ? '' : ' · head ${head.substring(0, 12)}'}',
    ChainBroken(:final seq, :final reason) =>
      'ALERT — the access trail was altered at entry $seq ($reason)',
    ChainEmpty() => 'No access has been recorded against this device yet',
  };
}

class ChainIntact extends ChainVerification {
  const ChainIntact({required this.entries, this.head});
  final int entries;
  final String? head;
}

class ChainBroken extends ChainVerification {
  const ChainBroken({required this.seq, required this.reason});
  final int seq;
  final String reason;
}

class ChainEmpty extends ChainVerification {
  const ChainEmpty();
}

/// The chain's hash rule, kept in one place so the writer and the verifier
/// cannot drift — a ledger whose verification disagrees with its own writing is
/// worse than no ledger, because it cries wolf.
///
/// Canonicalisation matters more than it looks: hashing a JSON map is only
/// reproducible if key order is fixed, so every field goes through an explicit
/// ordered list rather than `jsonEncode` of a map.
abstract final class LedgerHash {
  /// The hash every entry commits to — and that the next entry repeats.
  ///
  /// [previousHash] is folded in, so an attacker who edits entry 42 must also
  /// recompute 43…n; and because each of those requires the key, the whole tail
  /// becomes unforgeable.
  static String of({
    required List<Object?> fields,
    required String previousHash,
    required String key,
  }) {
    final canonical = StringBuffer(previousHash);
    for (final f in fields) {
      // A fixed separator and a fixed field order, so re-hashing a stored row
      // reproduces the original byte-for-byte. `jsonEncode` on a map does not
      // make that promise, and a verifier that disagrees with its own writer is
      // worse than no verifier at all.
      canonical
        ..write('|')
        ..write(f ?? '');
    }
    return Hmac(
      sha256,
      utf8.encode(key),
    ).convert(utf8.encode(canonical.toString())).toString();
  }

  /// The value every entry commits to before the first real one exists.
  static const genesis = 'carebridge-access-chain-v1';
}
