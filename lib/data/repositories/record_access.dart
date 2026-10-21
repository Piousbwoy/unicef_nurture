/// The policy decision point for reading a patient record.
///
/// ### What this replaces
///
/// Before this existed, the question "may this worker open this record?" was
/// answered by two guards on the repository: does the actor hold the permission,
/// and is this their own household. Both were correct as far as they went, and
/// neither could answer the question that actually matters under Act 843 — *on
/// what lawful basis, and can you show me afterwards?*
///
/// ### The model
///
/// Access is decided by **relationship first, consent second, override last**:
///
///  1. *Care relationship.* The patient is in this worker's own caseload — she
///     registered the household, or it sits in her district. No consent is
///     needed to treat your own patient; requiring it would be a clinical hazard
///     dressed up as governance.
///  2. *Consent.* Same region, different district: exactly the continuity-of-care
///     case the cross-worker search was built for. The family granted it, so the
///     basis is their decision, recorded with the notice version they saw.
///  3. *Vital interests.* An emergency read is never blocked. It is recorded as
///     what it was and flagged for review, which is how a system can be strict
///     without ever being the reason a sick child waited.
///  4. *Break the glass.* A worker with no relationship and no consent can still
///     look — deliberately, because blocking care is worse — but must say why,
///     and the entry is flagged for a supervisor and named in the family's
///     disclosure. The control is not a wall; it is a light that comes on.
///
/// ### The guarantee this carries, and its deliberate limit
///
/// An out-of-caseload read writes its own evidence row in the same transaction as
/// the read. If that row cannot be written, the read is refused — *for
/// discretionary access only*. A worker's own caseload is never held hostage by a
/// logging failure: an unrecorded access is a governance problem, a blocked
/// assessment is a clinical one, and the repository's audit helper already makes
/// that distinction. Here it is applied the other way round, on the read path.
library;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sqflite/sqflite.dart';

import '../../domain/compliance.dart';
import '../../domain/entities/core.dart';
import '../local/app_database.dart';
import '../local/compliance_dao.dart';
import '../local/household_dao.dart';
import '../local/user_dao.dart';

/// The outcome of one access decision, already recorded.
class AccessDecision {
  const AccessDecision({
    required this.allowed,
    required this.basis,
    required this.purpose,
    required this.flagged,
    required this.subjectPersonId,
    this.note,
    this.reason,
    this.canBreakGlass = false,
  });

  final bool allowed;
  final AccessBasis basis;
  final AccessPurpose purpose;

  /// True when this access belongs in a supervisor's review queue: an override,
  /// an emergency read, or an out-of-caseload look with no consent recorded.
  final bool flagged;
  final String subjectPersonId;

  /// Short human-readable explanation, stored in the ledger's note column and
  /// shown verbatim in the family's disclosure.
  final String? note;

  /// Populated only when [allowed] is false, and written for a person rather
  /// than for a log: an honest refusal says what to do next.
  final String? reason;

  /// True when this refusal is one a stated reason would turn into an opening.
  /// Lets a screen offer the way forward instead of only the wall.
  final bool canBreakGlass;

  bool get isRefusal => !allowed;
}

/// Inputs the decision needs, resolved once per access.
class AccessContext {
  const AccessContext({
    required this.actor,
    required this.household,
    required this.subjectPersonId,
    required this.isOwnCaseload,
    required this.isDataSubject,
    required this.crossFacilityConsent,
    required this.now,
    this.isSensitive = false,
    this.isResponsibleWorker = false,
  });

  final AppUser actor;
  final Household? household;

  /// The person whose record this is, or the household id when the access was to
  /// the household as a whole. Kept in one column so the family's disclosure
  /// query is a single lookup.
  final String subjectPersonId;
  final bool isOwnCaseload;
  final bool isDataSubject;
  final bool crossFacilityConsent;
  final DateTime now;

  /// The subject's record carries a [SensitivityCategory]. Household-level
  /// access is never sensitive: the family is findable, the person's own record
  /// is what the class protects.
  final bool isSensitive;

  /// The worker who registered the household — the one person outside the family
  /// for whom a sensitive record still opens without a stated reason.
  final bool isResponsibleWorker;
}

abstract final class RecordAccess {
  /// Resolves the facts a decision depends on, then decides.
  ///
  /// One round of lookups per access, all of them on rows the caller has already
  /// loaded or is about to show, so the control does not add a query storm to the
  /// register on a low-end handset.
  static Future<AccessContext> context({
    required AppUser actor,
    required String householdId,
    required String subjectPersonId,
    DatabaseExecutor? db,
    DateTime Function()? clock,
  }) async {
    final at = (clock ?? DateTime.now)();
    final household = await HouseholdDao.byId(householdId);

    // Caregiver scope: the account is bound to exactly one household, recorded at
    // registration. For a family member, "own record" is not a permission to
    // grant or refuse — it is the person's own data.
    final linked = await UserDao.linkedHouseholdFor(actor.id);
    final isDataSubject = linked != null && linked == householdId;

    // The care relationship. A worker's own registrations, and everything in the
    // district she is posted to. Deliberately *not* the whole region: the region
    // is the reach of the search box, not the depth of the entitlement.
    final isOwnCaseload =
        isDataSubject ||
        actor.id == household?.createdBy ||
        (household != null &&
            household.region == actor.region &&
            household.district == actor.district);

    final consent = await ConsentLedgerDao.current(
      subjectPersonId,
      ConsentScope.crossFacilitySearch,
    );

    // Resolved from the person row itself, so a marking that arrived by pull from
    // a colleague's handset is enforced here exactly as on the device that set it.
    final person = subjectPersonId == householdId
        ? null
        : await PersonDao.byId(subjectPersonId);

    return AccessContext(
      actor: actor,
      household: household,
      subjectPersonId: subjectPersonId,
      isOwnCaseload: isOwnCaseload,
      isDataSubject: isDataSubject,
      crossFacilityConsent: ConsentLedgerDao.isGranted(consent),
      now: at,
      isSensitive: person?.isSensitive ?? false,
      isResponsibleWorker: actor.id == household?.createdBy,
    );
  }

  /// Pure decision — no writes. Split out so the reasoning is unit-testable
  /// without a database, and so a UI can ask "would this be flagged?" before
  /// asking the worker for a reason.
  static AccessDecision decide(
    AccessContext ctx, {
    required AccessPurpose purpose,
    String? breakGlassReason,
  }) {
    // A family looking at its own record needs no basis but the obvious one.
    if (ctx.isDataSubject) {
      return AccessDecision(
        allowed: true,
        basis: AccessBasis.dataSubject,
        purpose: AccessPurpose.ownRecord,
        flagged: false,
        subjectPersonId: ctx.subjectPersonId,
        note: 'The family’s own access',
      );
    }

    // A worker may not reach across regions at all: the register is region-wide by
    // design, and a record from another region has no business being opened here.
    final household = ctx.household;
    final sameRegion =
        household == null || household.region == ctx.actor.region;
    if (!sameRegion) {
      return AccessDecision(
        allowed: false,
        basis: AccessBasis.none,
        purpose: purpose,
        flagged: true,
        subjectPersonId: ctx.subjectPersonId,
        note: 'Cross-region access attempt',
        reason:
            'This family is outside your region. If they are in front of you, '
            'register them here — the record stays theirs, and the two sets of '
            'notes will be linked by their name, not by an override.',
      );
    }

    // For a sensitive record the care relationship narrows to the worker who is
    // responsible for it. A same-district colleague falls through to the paths
    // below, where she can still open it — by saying why, or in an emergency.
    final ownCaseload = ctx.isSensitive
        ? ctx.isResponsibleWorker
        : ctx.isOwnCaseload;
    if (ownCaseload) {
      return AccessDecision(
        allowed: true,
        basis: AccessBasis.careRelationship,
        purpose: purpose,
        flagged: false,
        subjectPersonId: ctx.subjectPersonId,
        note: ctx.isSensitive
            ? 'Sensitive record, opened by the worker responsible for it'
            : 'This patient is in the worker’s caseload',
      );
    }

    // Out of caseload, in region: the continuity-of-care case.
    if (purpose == AccessPurpose.emergency) {
      return AccessDecision(
        allowed: true,
        basis: AccessBasis.vitalInterest,
        purpose: purpose,
        flagged: true,
        subjectPersonId: ctx.subjectPersonId,
        note: 'Emergency read — to be reviewed after care',
      );
    }

    // Consent to be *found* by another facility is not consent to have a sensitive
    // record read: the family agreed to continuity of care, not to disclosure of
    // the one thing they would most want kept close.
    if (ctx.crossFacilityConsent && !ctx.isSensitive) {
      return AccessDecision(
        allowed: true,
        basis: AccessBasis.consent,
        purpose: purpose,
        flagged: false,
        subjectPersonId: ctx.subjectPersonId,
        note: 'The family allowed another facility to find their record',
      );
    }

    if (breakGlassReason != null && breakGlassReason.trim().isNotEmpty) {
      return AccessDecision(
        allowed: true,
        basis: AccessBasis.breakGlass,
        purpose: purpose,
        flagged: true,
        subjectPersonId: ctx.subjectPersonId,
        note: breakGlassReason.trim(),
      );
    }

    // The one refusal in the register that exists to be answered rather than
    // obeyed: silence is not an option for a sensitive record, but a sentence is.
    if (ctx.isSensitive) {
      return AccessDecision(
        allowed: false,
        basis: AccessBasis.none,
        purpose: purpose,
        flagged: true,
        subjectPersonId: ctx.subjectPersonId,
        note: 'Sensitive record — opening attempted without a stated reason',
        reason:
            'This record is marked sensitive, so it opens without a reason only '
            'for the worker responsible for it. To open it, say why you need it. '
            'Your reason is recorded, reviewed by the district, and shown to the '
            'family.',
        canBreakGlass: true,
      );
    }

    // Still allowed — this is a care system, not a turnstile — but the absence of
    // both a relationship and a recorded permission is precisely what a reviewer
    // should have to look at, so it is flagged rather than blessed.
    return AccessDecision(
      allowed: true,
      basis: AccessBasis.careRelationship,
      purpose: purpose,
      flagged: true,
      subjectPersonId: ctx.subjectPersonId,
      note:
          'Opened outside the worker’s own district with no recorded consent '
          'from this family',
    );
  }

  /// Records the decision on the trail.
  ///
  /// Returns the decision unchanged so a caller can chain, and swallows nothing
  /// silently: [requireEvidence] is what turns "we log accesses" into "an
  /// unlogged access cannot happen" for the discretionary paths.
  static Future<AccessDecision> commit(
    DatabaseExecutor db,
    AccessContext ctx,
    AccessDecision decision, {
    required String action,
    required String entityTable,
    required String entityId,
    String? deviceId,
    bool requireEvidence = false,
  }) async {
    try {
      await AccessLedgerDao.append(
        db,
        actor: ctx.actor,
        deviceId: deviceId,
        action: action,
        entityTable: entityTable,
        entityId: entityId,
        subjectPersonId: decision.subjectPersonId,
        purpose: decision.purpose,
        basis: decision.basis,
        at: ctx.now,
        note: decision.note,
        flagged: decision.flagged,
      );
    } catch (error) {
      // Refuse only where the access was discretionary.
      if (requireEvidence) {
        return AccessDecision(
          allowed: false,
          basis: AccessBasis.none,
          purpose: decision.purpose,
          flagged: true,
          subjectPersonId: decision.subjectPersonId,
          note: 'Evidence could not be written: $error',
          reason:
              'This record cannot be opened because the access log is '
              'unavailable. The log is what makes an outside look reviewable, so '
              'without it the look is not permitted. Restart the app; if it '
              'persists, tell the district team.',
        );
      }
      // Own caseload: care comes first. The gap is itself recorded as loudly as
      // the device allows, on the existing best-effort audit path.
      await AuditDao.record(
        action: 'access log unavailable',
        outcome: 'degraded',
        actorId: ctx.actor.id,
        actorRole: ctx.actor.role.name,
        entityTable: entityTable,
        entityId: entityId,
        detail: '$error',
      );
    }
    return decision;
  }

  /// Convenience for the commonest call site: decide and record in one go.
  static Future<AccessDecision> open(
    DatabaseExecutor db, {
    required AppUser actor,
    required String householdId,
    required String subjectPersonId,
    required AccessPurpose purpose,
    required String action,
    String? breakGlassReason,
    String? deviceId,
  }) async {
    // One entry per *opening*, not per query. A single household screen reads
    // the household, the members, the checks and the growth history: logging all
    // four as separate accesses would bury the fact that matters — that Aminata
    // opened this child's record once, at 09:14, to continue care. A log that
    // needs summarising to be read is a log nobody reads.
    //
    // Flagged decisions are never collapsed away: an override is exactly the
    // entry a reviewer must not lose.
    final key =
        '${actor.id}|${purpose.name}|$householdId|$subjectPersonId|$action';
    final cached = _recent[key];
    if (cached != null &&
        breakGlassReason == null &&
        purpose != AccessPurpose.emergency &&
        _now().difference(cached.at) < _window) {
      return cached.decision;
    }

    // A reason already given covers the sitting, not one query. Without this, a
    // worker who explained herself once would be refused again by the very next
    // screen that reads the same record — the household view, then the growth
    // chart, then the referral — and would learn that the reason is a formality.
    final glassKey = '${actor.id}|$householdId|$subjectPersonId';
    final grant = _glass[glassKey];
    if (grant != null &&
        breakGlassReason == null &&
        _now().difference(grant.at) < _glassWindow) {
      return grant.decision;
    }
    final recordedAt = _now();

    final ctx = await context(
      actor: actor,
      householdId: householdId,
      subjectPersonId: subjectPersonId,
    );
    final decision = decide(
      ctx,
      purpose: purpose,
      breakGlassReason: breakGlassReason,
    );
    if (decision.isRefusal) {
      // A refused look is still a look someone tried to take. It never reaches the
      // hash chain — nothing was read — but it lands in the device audit log, so a
      // supervisor asking "who tried to open this?" gets an answer.
      await AuditDao.record(
        action: action,
        outcome: 'denied',
        actorId: actor.id,
        actorRole: actor.role.name,
        entityTable: Tables.persons,
        entityId: subjectPersonId,
        detail: decision.note,
      );
      return decision;
    }
    final committed = await commit(
      db,
      ctx,
      decision,
      action: action,
      entityTable: Tables.households,
      entityId: householdId,
      deviceId: deviceId,
      // Discretionary paths must carry their own evidence.
      requireEvidence:
          !ctx.isOwnCaseload && decision.basis != AccessBasis.careRelationship,
    );
    if (committed.allowed && !committed.flagged) {
      // Bounded and self-expiring: a worker browsing a whole region's register
      // must not grow an unbounded map inside a phone app that is never restarted.
      _recent.removeWhere(
        (_, entry) => recordedAt.difference(entry.at) > _window,
      );
      if (_recent.length > 400) _recent.clear();
      _recent[key] = _RecentAccess(committed, recordedAt);
    }
    if (committed.allowed && committed.basis == AccessBasis.breakGlass) {
      _glass.removeWhere(
        (_, entry) => recordedAt.difference(entry.at) > _glassWindow,
      );
      _glass[glassKey] = _RecentAccess(committed, recordedAt);
    }
    return committed;
  }

  static DateTime _now() => DateTime.now();

  /// Forgets this session's already-recorded accesses.
  ///
  /// Not for production use: a fresh process starts empty anyway. Exposed so a
  /// test can assert that an access wrote an evidence row without a previous
  /// test's collapsed decision silently suppressing it.
  @visibleForTesting
  static void clearTrailCache() {
    _recent.clear();
    _glass.clear();
  }

  /// Decisions already recorded this session, for the window above.
  static final Map<String, _RecentAccess> _recent = <String, _RecentAccess>{};
  static const _window = Duration(minutes: 5);

  /// Stated reasons in force, keyed by worker, household and subject.
  ///
  /// Thirty minutes is one sitting with a family — long enough that a worker is
  /// not asked twice while examining the same child, short enough that a reason
  /// given in the morning does not silently cover an afternoon of browsing.
  static final Map<String, _RecentAccess> _glass = <String, _RecentAccess>{};
  static const _glassWindow = Duration(minutes: 30);
}

class _RecentAccess {
  const _RecentAccess(this.decision, this.at);
  final AccessDecision decision;
  final DateTime at;
}
