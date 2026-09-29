/// The follow-up desk grouping: which referrals a worker must answer, in the
/// order their own route makes them reachable.
library;

import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:carebridge_ai/domain/services/follow_up_policy.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 9, 25, 11);

Referral _referral({
  String id = 'r-1',
  String personId = 'p-1',
  ReferralStatus status = ReferralStatus.issued,
  ReferralUrgency urgency = ReferralUrgency.sameDay,
  Duration ago = const Duration(days: 3),
  String? linkFrom,
}) => Referral(
  id: id,
  referenceCode: 'CB-${id.toUpperCase()}',
  personId: personId,
  assessmentId: 'a-$id',
  facilityName: 'Savelugu Health Centre',
  reason: 'Danger signs',
  urgency: urgency,
  issuedBy: 'w-1',
  issuedAt: _now.subtract(ago),
  status: status,
  linkFromReferralId: linkFrom,
);

FollowUpContact _contact({
  String id = 'c-1',
  String referralId = 'r-1',
  String householdId = 'h-1',
  Duration ago = const Duration(days: 1),
  FollowUpReach reached = FollowUpReach.went,
  FollowUpCare care = FollowUpCare.none,
  FollowUpCondition condition = FollowUpCondition.same,
  Set<CareBarrier> barriers = const {},
  String? linkedReferralId,
}) => FollowUpContact(
  id: id,
  referralId: referralId,
  householdId: householdId,
  personId: 'p-1',
  at: _now.subtract(ago),
  channel: FollowUpChannel.householdVisit,
  reached: reached,
  care: care,
  condition: condition,
  barriers: barriers,
  recordedBy: 'w-1',
  linkedReferralId: linkedReferralId,
);

FollowUpDesk _desk({
  required List<Referral> referrals,
  Map<String, List<FollowUpContact>> ledger = const {},
  Map<String, String> householdOf = const {},
  Set<String> routeHouseholds = const {},
}) => buildFollowUpDesk(
  referrals: referrals,
  ledger: ledger,
  householdOf: householdOf,
  routeHouseholds: routeHouseholds,
  now: _now,
);

List<String> _ids(List<FollowUpCase> cases) =>
    cases.map((c) => c.referral.id).toList();

FollowUpCase _caseIn(FollowUpDesk desk, String id) => [
  ...desk.awaitingAnswer,
  ...desk.needsAction,
  ...desk.settled,
].firstWhere((c) => c.referral.id == id);

void main() {
  group('the desk sorts by what the worker already knows', () {
    test('a referral with no answer is awaiting an answer', () {
      final desk = _desk(referrals: [_referral()], householdOf: {'p-1': 'h-1'});
      final case_ = desk.awaitingAnswer.single;
      expect(case_.referral.id, 'r-1');
      expect(case_.latest, isNull);
      expect(desk.needsAction, isEmpty);
      expect(desk.settled, isEmpty);
    });

    test('an unanswered attempt is still awaiting, and counts as a try', () {
      final desk = _desk(
        referrals: [_referral()],
        ledger: {
          'r-1': [
            _contact(reached: FollowUpReach.unknown),
            _contact(id: 'c-2', reached: FollowUpReach.unknown),
          ],
        },
        householdOf: {'p-1': 'h-1'},
      );
      final case_ = desk.awaitingAnswer.single;
      expect(case_.latest!.isAnswered, isFalse);
      expect(case_.attempts, 2);
      expect(case_.trace, hasLength(2));
    });

    test('a confirmed treatment closes the case', () {
      final desk = _desk(
        referrals: [_referral(status: ReferralStatus.treated)],
        ledger: {
          'r-1': [_contact(care: FollowUpCare.seenTreated)],
        },
        householdOf: {'p-1': 'h-1'},
      );
      expect(_ids(desk.settled), ['r-1']);
      expect(desk.awaitingAnswer, isEmpty);
      expect(desk.needsAction, isEmpty);
    });

    test('attended but untreated is work, not an answer filed away', () {
      final desk = _desk(
        referrals: [_referral(status: ReferralStatus.arrived)],
        ledger: {
          'r-1': [_contact(care: FollowUpCare.none)],
        },
        householdOf: {'p-1': 'h-1'},
      );
      final case_ = desk.needsAction.single;
      expect(case_.latest!.isAnswered, isTrue);
      expect(case_.isClosed, isFalse);
      expect(desk.awaitingAnswer, isEmpty);
    });

    test('an arrival with no answer recorded is still waiting for one', () {
      // Staff confirmed the family got there; nobody asked what happened next.
      // Dropping this case off the desk would count the child as cared for.
      final desk = _desk(
        referrals: [_referral(status: ReferralStatus.arrived)],
        householdOf: {'p-1': 'h-1'},
      );
      expect(_ids(desk.awaitingAnswer), ['r-1']);
      expect(desk.settled, isEmpty);
    });

    test('a referral closed without care is settled, and keeps its own reason', () {
      final desk = _desk(
        referrals: [_referral(status: ReferralStatus.refused)],
        householdOf: {'p-1': 'h-1'},
      );
      expect(desk.settled.single.referral.status, ReferralStatus.refused);
      expect(desk.awaitingAnswer, isEmpty);
    });

    test('an answer that raised a fresh referral hands the case over', () {
      // The parent's follow-up work is finished — its answer is on record and a
      // new referral carries the child now. Leaving both rows in the working
      // lists would double-count one sick child.
      final desk = _desk(
        referrals: [
          _referral(id: 'parent', status: ReferralStatus.arrived),
          _referral(id: 'child', linkFrom: 'parent'),
        ],
        ledger: {
          'parent': [_contact(referralId: 'parent', linkedReferralId: 'child')],
        },
        householdOf: {'p-1': 'h-1'},
      );
      final parent = _caseIn(desk, 'parent');
      expect(parent.handedOver, isTrue);
      expect(parent.nextStep, FollowUpNextStep.none);
      expect(_ids(desk.settled), ['parent']);
      expect(_ids(desk.awaitingAnswer), ['child']);
      expect(desk.needsAction, isEmpty);
    });
  });

  group('visits drive follow-up', () {
    test('a household on today’s route leads its lane', () {
      final desk = _desk(
        referrals: [
          _referral(id: 'off', personId: 'p-9', ago: const Duration(days: 1)),
          _referral(id: 'on', personId: 'p-1', ago: const Duration(days: 5)),
        ],
        householdOf: {'p-1': 'h-1', 'p-9': 'h-9'},
        routeHouseholds: {'h-1'},
      );
      expect(_ids(desk.awaitingAnswer), ['on', 'off']);
      expect(desk.awaitingAnswer.first.onRoute, isTrue);
      expect(desk.awaitingAnswer.last.onRoute, isFalse);
    });

    test('inside a lane the urgent and the older go first', () {
      final desk = _desk(
        referrals: [
          _referral(id: 'routine', ago: const Duration(days: 9),
              urgency: ReferralUrgency.scheduled),
          _referral(id: 'urgent-recent', ago: const Duration(days: 1)),
          _referral(id: 'urgent-old', ago: const Duration(days: 4)),
        ],
        householdOf: {'p-1': 'h-1'},
      );
      expect(_ids(desk.awaitingAnswer), ['urgent-old', 'urgent-recent', 'routine']);
    });

    test('settled cases read newest first — they are evidence, not work', () {
      final desk = _desk(
        referrals: [
          _referral(id: 'old', status: ReferralStatus.treated,
              ago: const Duration(days: 8)),
          _referral(id: 'new', status: ReferralStatus.treated,
              ago: const Duration(days: 2)),
        ],
        householdOf: {'p-1': 'h-1'},
      );
      expect(_ids(desk.settled), ['new', 'old']);
    });
  });

  group('what the next tap is', () {
    test('on the route the next step is to answer it here', () {
      final desk = _desk(
        referrals: [_referral()],
        householdOf: {'p-1': 'h-1'},
        routeHouseholds: {'h-1'},
      );
      expect(_caseIn(desk, 'r-1').nextStep, FollowUpNextStep.answerNow);
    });

    test('off the route the next step is to make a visit happen', () {
      final desk = _desk(referrals: [_referral()], householdOf: {'p-1': 'h-1'});
      expect(_caseIn(desk, 'r-1').nextStep, FollowUpNextStep.bringOnRoute);
    });

    test('an answered case that still needs care is reviewed, not rescheduled',
        () {
      final desk = _desk(
        referrals: [_referral(status: ReferralStatus.arrived)],
        ledger: {
          'r-1': [_contact(condition: FollowUpCondition.worse)],
        },
        householdOf: {'p-1': 'h-1'},
        routeHouseholds: {'h-1'},
      );
      expect(_caseIn(desk, 'r-1').nextStep, FollowUpNextStep.reviewAnswer);
    });

    test('a settled case has no next step', () {
      final desk = _desk(
        referrals: [_referral(status: ReferralStatus.treated)],
        householdOf: {'p-1': 'h-1'},
        routeHouseholds: {'h-1'},
      );
      expect(_caseIn(desk, 'r-1').nextStep, FollowUpNextStep.none);
    });
  });

  group('the reads a card needs', () {
    test('a referral whose person is gone is still on the desk', () {
      final desk = _desk(
        referrals: [_referral(personId: 'ghost')],
        routeHouseholds: {'h-1'},
      );
      final case_ = desk.awaitingAnswer.single;
      expect(case_.householdId, isNull);
      expect(case_.onRoute, isFalse);
    });

    test('the barrier that blocked care survives onto the case', () {
      final desk = _desk(
        referrals: [_referral(status: ReferralStatus.didNotAttend)],
        ledger: {
          'r-1': [
            _contact(
              reached: FollowUpReach.didNotGo,
              barriers: {CareBarrier.noTransportMoney},
            ),
          ],
        },
        householdOf: {'p-1': 'h-1'},
      );
      expect(desk.needsAction.single.blockers, {CareBarrier.noTransportMoney});
    });

    test('a chained referral knows it answers an earlier one', () {
      final desk = _desk(
        referrals: [_referral(linkFrom: 'r-0')],
        householdOf: {'p-1': 'h-1'},
      );
      expect(desk.awaitingAnswer.single.isChained, isTrue);
    });

    test('the header counts each lane once', () {
      final desk = _desk(
        referrals: [
          _referral(id: 'a'),
          _referral(id: 'b', status: ReferralStatus.arrived),
          _referral(id: 'c', status: ReferralStatus.treated),
        ],
        ledger: {
          'b': [_contact(referralId: 'b')],
        },
        householdOf: {'p-1': 'h-1'},
      );
      expect(desk.awaitingCount, 1);
      expect(desk.actionCount, 1);
      expect(desk.settledCount, 1);
    });

    test('an empty desk is empty in every lane', () {
      expect(_desk(referrals: const []).isEmpty, isTrue);
    });
  });
}
