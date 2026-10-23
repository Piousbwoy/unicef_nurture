/// Barrier-aware ordering, stated as a rule rather than as a score.
///
/// A prioritiser invites one question: "60% of what?" There is no measured
/// distribution here to derive weights from, so this file refuses to invent any.
/// What it uses instead is a **lexicographic rule** the nurse can be told in one
/// breath and disagree with item by item: urgency first (the guideline's), then
/// the kind of action, then — only when the first two are tied — how far this
/// family is from the facility.
///
/// The third key is deliberately the weakest one. It can only reorder actions of
/// identical urgency *and* identical kind, which means it can never demote a
/// treatment below a referral, or an urgent step below a routine one. A long walk
/// changes what the family can do today; it does not change what is dangerous.
library;

import 'package:carebridge_ai/domain/engines/action_prioritizer.dart';
import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

RecommendedAction act({
  String label = 'action',
  ReferralUrgency urgency = ReferralUrgency.scheduled,
  bool referral = false,
  bool treatment = false,
  bool prereferral = false,
}) => RecommendedAction(
  instruction: label,
  urgency: urgency,
  rationale: 'test fixture',
  protocolSource: 'test',
  isReferral: referral,
  isTreatment: treatment,
  isPrereferralTreatment: prereferral,
);

void main() {
  group('the distance band is declared, not guessed', () {
    test('a walk at or beyond the threshold counts as far', () {
      expect(ActionPrioritizer.distance(45), WalkDistance.far);
      expect(ActionPrioritizer.distance(30), WalkDistance.far);
      expect(ActionPrioritizer.distance(10), WalkDistance.near);
    });

    test('an unknown walk changes nothing', () {
      // Distance is often not recorded. Pretending it is 0 would quietly mark
      // every household as nearby, so unknown must mean "no opinion".
      expect(ActionPrioritizer.distance(null), WalkDistance.unknown);
      expect(
        ActionPrioritizer.tieBreak(
          act(label: 'refer', referral: true),
          act(label: 'ORS at home'),
          walkingMinutesToFacility: null,
        ),
        0,
      );
    });
  });

  group('the third key only moves ties', () {
    test('a far walk puts the household step first', () {
      final home = act(label: 'Give ORS at home');
      final facility = act(label: 'Refer to facility', referral: true);
      expect(
        ActionPrioritizer.tieBreak(
          home,
          facility,
          walkingMinutesToFacility: 55,
        ),
        lessThan(0),
        reason: 'same urgency and same kind: the step they can do today comes '
            'first',
      );
    });

    test('a near walk leaves the order alone', () {
      final home = act(label: 'Give ORS at home');
      final facility = act(label: 'Refer to facility', referral: true);
      expect(
        ActionPrioritizer.tieBreak(
          home,
          facility,
          walkingMinutesToFacility: 5,
        ),
        0,
      );
    });

    test('two referrals tie — distance does not invent a preference', () {
      expect(
        ActionPrioritizer.tieBreak(
          act(label: 'refer a', referral: true),
          act(label: 'refer b', referral: true),
          walkingMinutesToFacility: 90,
        ),
        0,
      );
    });

    test('a referral never outranks a pre-referral treatment', () {
      // The one comparison that must never be decided by convenience.
      expect(
        ActionPrioritizer.tieBreak(
          act(label: 'Refer', referral: true, urgency: ReferralUrgency.immediate),
          act(
            label: 'Rectal artesunate now',
            urgency: ReferralUrgency.immediate,
            prereferral: true,
          ),
          walkingMinutesToFacility: 90,
        ),
        greaterThan(0),
      );
    });
  });

  group('the rule is publishable in words', () {
    test('a far family is told how distance affected the list', () {
      expect(
        ActionPrioritizer.explain(walkingMinutesToFacility: 55),
        contains('55'),
      );
      expect(ActionPrioritizer.explain(walkingMinutesToFacility: 55), allOf(
        contains('urgency'),
        contains('kind'),
      ));
    });

    test('an unmeasured walk is admitted, not hidden', () {
      expect(
        ActionPrioritizer.explain(walkingMinutesToFacility: null),
        contains('not recorded'),
      );
    });

    test('the threshold is visible so it can be argued with', () {
      expect(ActionPrioritizer.farWalkMinutes, 30);
    });
  });
}
