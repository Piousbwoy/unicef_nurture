/// Barrier evidence — the step from "we asked why" to "the district can act".
///
/// `BarrierDao.withinDays` already pulls every barrier reported in a window, and
/// `CareBarrier.suggestedAction` already says what a CHO can do for one family.
/// Neither of those changes anything for a facility that shuts at 2pm. The
/// engine's job is the missing middle: group what households said, decide
/// whether it is a pattern rather than nine anecdotes, and name **who can
/// actually fix it** — because that determines whether the escalation goes to a
/// sub-district officer, a community fund, or the CHO's own diary.
library;

import '../entities/visit.dart';
import '../enums.dart';

/// Who owns the fix for a barrier. Assigned here rather than on [CareBarrier]
/// itself: the enum is a vocabulary of what families say, and "who can act on
/// it" is a judgement about the health system, not a property of the sentence.
enum BarrierOwner {
  household('This household', 'The CHO can solve this in the next contact.'),
  community(
    'The community',
    'Needs a community asset — transport fund, mother-led group, '
        'engagement with traditional providers.',
  ),
  facility(
    'The facility',
    'A staffing, hours or treatment-quality problem. This is a sub-district '
        'escalation, not a family instruction.',
  ),
  system(
    'The wider system',
    'Financing or infrastructure. Evidence goes up the chain; the CHO cannot '
        'fix it alone.',
  ),
  season(
    'The calendar',
    'Predictable and plannable: move the contact, not the family.',
  );

  const BarrierOwner(this.label, this.escalation);
  final String label;
  final String escalation;
}

extension BarrierOwnerOnCareBarrier on CareBarrier {
  BarrierOwner get owner => switch (this) {
    CareBarrier.noPermission => BarrierOwner.household,
    CareBarrier.didNotThinkItSerious => BarrierOwner.household,
    CareBarrier.fearOfProcedure => BarrierOwner.household,
    CareBarrier.noChildcare => BarrierOwner.community,
    CareBarrier.preferredTraditional => BarrierOwner.community,
    CareBarrier.facilityClosed => BarrierOwner.facility,
    CareBarrier.pastBadExperience => BarrierOwner.facility,
    CareBarrier.noTransportMoney => BarrierOwner.system,
    CareBarrier.noNhisCard => BarrierOwner.system,
    CareBarrier.distanceTooFar => BarrierOwner.system,
    CareBarrier.floodedRoad => BarrierOwner.season,
    CareBarrier.farmWorkload => BarrierOwner.season,
  };
}

/// One barrier, reported by enough households in the window to stop being
/// individual bad luck.
class BarrierPattern {
  const BarrierPattern({
    required this.barrier,
    required this.households,
    required this.reports,
    required this.unresolved,
  });

  final CareBarrier barrier;

  /// Distinct households, which is the number that makes it a pattern. Nine
  /// reports from three families is a family problem; three families with the
  /// same sentence is a system one.
  final int households;
  final int reports;

  /// Reports still open. A pattern the CHO has already worked around is still
  /// worth reporting — the workaround is not the fix.
  final int unresolved;

  BarrierOwner get owner => barrier.owner;

  /// The line a CHO reads to a sub-district officer.
  String get statement =>
      '$households ${households == 1 ? 'household' : 'households'} said '
      '"${barrier.label}" in the last ${BarrierEvidence.windowDays} days. '
      '${owner.escalation}';
}

class BarrierEvidence {
  /// A CHPS sub-district reports monthly, so the window matches the cycle the
  /// evidence has to survive in.
  static const windowDays = 30;

  /// Three is where "coincidence" stops being a reasonable explanation. Two
  /// households can share a bad road; three sharing a closed facility is a
  /// staffing fact, and a CHO saying it with a count gets further than nine
  /// separate notes saying "did not attend".
  static const householdsForPattern = 3;

  /// Grouped, ranked, patterns first. Non-patterns are returned too — a CHO
  /// scanning the list wants to see that transport is the *only* one-off left,
  /// not a silently filtered absence.
  static List<BarrierPattern> summarise(List<BarrierReport> reports) {
    final households = <CareBarrier, Set<String>>{};
    final counts = <CareBarrier, int>{};
    final unresolved = <CareBarrier, int>{};
    for (final report in reports) {
      for (final barrier in report.barriers) {
        (households[barrier] ??= <String>{})
            .add(report.householdId);
        counts[barrier] = (counts[barrier] ?? 0) + 1;
        if (!report.resolved) {
          unresolved[barrier] = (unresolved[barrier] ?? 0) + 1;
        }
      }
    }
    final patterns = [
      for (final entry in counts.entries)
        BarrierPattern(
          barrier: entry.key,
          households: households[entry.key]!.length,
          reports: entry.value,
          unresolved: unresolved[entry.key] ?? 0,
        ),
    ]..sort((a, b) {
        final byHouseholds = b.households.compareTo(a.households);
        return byHouseholds != 0
            ? byHouseholds
            : b.barrier.label.compareTo(a.barrier.label);
      });
    return patterns;
  }

  /// The subset worth escalating, with the reason it crossed.
  static List<BarrierPattern> escalatable(List<BarrierPattern> patterns) => [
    for (final p in patterns)
      if (p.households >= householdsForPattern) p,
  ];
}
