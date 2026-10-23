/// Barrier-aware ordering, expressed as a rule the nurse can argue with.
///
/// ## Why there is no score in this file
///
/// A prioritiser that prints "utility 0.62" invites one question — *of what?*
/// There is no measured distribution of this population to derive weights from,
/// and inventing one is the exact failure this codebase spent a day removing from
/// the confidence figure. So ordering is **lexicographic** and said out loud:
///
///   1. **Urgency** — the guideline's own band, computed by the engines.
///   2. **Kind of action** — pre-referral treatment, treatment, referral,
///      counselling (the synthesizer's category rank).
///   3. **Only on a tie of the first two:** how far this family is from the
///      facility, so a step they can do today is listed before one that needs the
///      walk.
///
/// Because the distance rule sits last, it can never demote a treatment below a
/// referral or move an urgent step behind a routine one. It reorders items that
/// are, clinically, already equally weighty. And one kind is protected outright:
/// a pre-referral treatment is never displaced by convenience, because "give it
/// before they travel" is the whole point of it.
library;

import '../entities/visit.dart';

/// How far the household is from the facility, as the ordering rule sees it.
enum WalkDistance { near, far, unknown }

abstract final class ActionPrioritizer {
  /// The line this build draws between "reachable" and "a real obstacle".
  ///
  /// A convention of this software, not a figure from a guideline — which is
  /// exactly why it is published as a named constant and quoted in the
  /// explanation, so a nurse or a judge can tell us it is wrong.
  static const int farWalkMinutes = 30;

  static WalkDistance distance(int? walkingMinutesToFacility) {
    if (walkingMinutesToFacility == null) return WalkDistance.unknown;
    return walkingMinutesToFacility >= farWalkMinutes
        ? WalkDistance.far
        : WalkDistance.near;
  }

  /// The third key. Returns 0 whenever it has no opinion, which is most of the
  /// time — the first two keys decide nearly every pair.
  static int tieBreak(
    RecommendedAction a,
    RecommendedAction b, {
    required int? walkingMinutesToFacility,
  }) {
    // Pre-referral treatment is protected before anything else is considered, so
    // no distance rule can ever push it behind the transfer it accompanies.
    final protectedA = a.isPrereferralTreatment ? 0 : 1;
    final protectedB = b.isPrereferralTreatment ? 0 : 1;
    if (protectedA != protectedB) return protectedA.compareTo(protectedB);

    if (distance(walkingMinutesToFacility) != WalkDistance.far) return 0;
    return _facilityBound(a).compareTo(_facilityBound(b));
  }

  /// 1 when the action needs the family to reach a facility, 0 when it can be
  /// done where they are. Read from the flags the engines set — never guessed
  /// from the wording of an instruction, which is how a keyword heuristic starts
  /// deciding clinical order.
  static int _facilityBound(RecommendedAction a) => a.isReferral ? 1 : 0;

  /// The rule, in the user's language. Shown wherever the list explains itself,
  /// so the ordering can be contested item by item instead of taken on trust.
  static String explain({required int? walkingMinutesToFacility}) {
    final walk = switch (walkingMinutesToFacility) {
      null => 'walking time not recorded',
      final int minutes => 'the walk to the facility is $minutes min',
    };
    return 'Order: clinical urgency first, then the kind of action, then — only '
        'between steps of equal weight — what this household can reach today '
        '($walk; $farWalkMinutes min or more counts as far here).';
  }
}
