// The answer-led follow-up ledger: what the worker saw at the household,
// stored as a queryable row instead of prose in a notes column.
import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FollowUpContact', () {
    test('survives a map round-trip with every answer field', () {
      final contact = FollowUpContact(
        id: 'fc-1',
        referralId: 'ref-1',
        personId: 'p-1',
        householdId: 'h-1',
        at: DateTime(2026, 9, 24, 10, 30),
        channel: FollowUpChannel.phoneCall,
        reached: FollowUpReach.went,
        care: FollowUpCare.seenWaiting,
        condition: FollowUpCondition.worse,
        barriers: const {CareBarrier.noTransportMoney, CareBarrier.distanceTooFar},
        note: 'Father said the motorcycle fare was too high.',
        recordedBy: 'u-1',
      );

      final restored = FollowUpContact.fromMap(contact.toMap());

      expect(restored.id, 'fc-1');
      expect(restored.referralId, 'ref-1');
      expect(restored.personId, 'p-1');
      expect(restored.householdId, 'h-1');
      expect(restored.at, DateTime(2026, 9, 24, 10, 30));
      expect(restored.channel, FollowUpChannel.phoneCall);
      expect(restored.reached, FollowUpReach.went);
      expect(restored.care, FollowUpCare.seenWaiting);
      expect(restored.condition, FollowUpCondition.worse);
      expect(restored.barriers, {
        CareBarrier.noTransportMoney,
        CareBarrier.distanceTooFar,
      });
      expect(restored.note, 'Father said the motorcycle fare was too high.');
      expect(restored.recordedBy, 'u-1');
      expect(restored.linkedReferralId, isNull);
    });

    test('carries the chained referral it raised', () {
      final contact = FollowUpContact(
        id: 'fc-2',
        referralId: 'ref-1',
        householdId: 'h-1',
        at: DateTime(2026, 9, 24),
        channel: FollowUpChannel.householdVisit,
        reached: FollowUpReach.didNotGo,
        care: FollowUpCare.none,
        condition: FollowUpCondition.worse,
        recordedBy: 'u-1',
        linkedReferralId: 'ref-9',
      );

      expect(FollowUpContact.fromMap(contact.toMap()).linkedReferralId, 'ref-9');
    });

    test('tolerates the empty barrier and note columns', () {
      final restored = FollowUpContact.fromMap({
        'id': 'fc-3',
        'referral_id': 'ref-1',
        'household_id': 'h-1',
        'at': DateTime(2026, 9, 24).toIso8601String(),
        'channel': 'householdVisit',
        'reached': 'unknown',
        'care': 'unknown',
        'condition': 'notSeen',
        'barriers': '',
        'recorded_by': 'u-1',
      });

      expect(restored.barriers, isEmpty);
      expect(restored.note, isNull);
      expect(restored.personId, isNull);
    });

    test('falls back to unknown instead of inventing an answer', () {
      final restored = FollowUpContact.fromMap({
        'id': 'fc-4',
        'referral_id': 'ref-1',
        'household_id': 'h-1',
        'at': DateTime(2026, 9, 24).toIso8601String(),
        'channel': 'carrier-pigeon',
        'reached': 'maybe',
        'care': 'treated',
        'condition': 'notSeen',
        'recorded_by': 'u-1',
      });

      expect(restored.channel, FollowUpChannel.unknown);
      expect(restored.reached, FollowUpReach.unknown);
      // A value this app never writes must not be resurrected as an answer.
      expect(restored.care, FollowUpCare.unknown);
    });

    test('is unanswered until the family is actually reached', () {
      FollowUpContact reached(String? id) => FollowUpContact(
        id: id ?? 'fc',
        referralId: 'ref-1',
        householdId: 'h-1',
        at: DateTime(2026, 9, 24),
        channel: FollowUpChannel.householdVisit,
        reached: FollowUpReach.unknown,
        care: FollowUpCare.unknown,
        condition: FollowUpCondition.notSeen,
        recordedBy: 'u-1',
      );

      expect(reached(null).isAnswered, isFalse);

      final answered = FollowUpContact.fromMap({
        ...reached(null).toMap(),
        'reached': 'went',
      });
      expect(answered.isAnswered, isTrue);
    });

    test('labels read as the worker\'s own words, not clinical jargon', () {
      expect(
        FollowUpChannel.values.map((c) => c.label).toList(),
        containsAll(['Household visit', 'Phone call']),
      );
      expect(FollowUpReach.didNotGo.label, 'Did not go');
      expect(FollowUpCare.seenTreated.label, isNotNull);
      expect(FollowUpCondition.better.label, isNotNull);
    });
  });

  group('Referral chain', () {
    test('records which referral a re-referral answers', () {
      final referral = Referral(
        id: 'ref-9',
        referenceCode: 'CB-9K2M',
        personId: 'p-1',
        assessmentId: 'a-2',
        facilityName: 'Bawku Municipal Hospital',
        reason: 'Worsening breathing',
        urgency: ReferralUrgency.immediate,
        issuedBy: 'u-1',
        issuedAt: DateTime(2026, 9, 24),
        linkFromReferralId: 'ref-1',
      );

      expect(Referral.fromMap(referral.toMap()).linkFromReferralId, 'ref-1');
    });

    test('a first referral has no chain parent', () {
      final referral = Referral(
        id: 'ref-1',
        referenceCode: 'CB-1K2M',
        personId: 'p-1',
        assessmentId: 'a-1',
        facilityName: 'Bawku Municipal Hospital',
        reason: 'Fast breathing',
        urgency: ReferralUrgency.sameDay,
        issuedBy: 'u-1',
        issuedAt: DateTime(2026, 9, 22),
      );

      expect(referral.linkFromReferralId, isNull);
      expect(referral.isChained, isFalse);
      expect(Referral.fromMap(referral.toMap()).linkFromReferralId, isNull);
    });

    test('a re-referral knows its parent', () {
      final referral = Referral(
        id: 'ref-9',
        referenceCode: 'CB-9K2M',
        personId: 'p-1',
        assessmentId: 'a-2',
        facilityName: 'Bawku Municipal Hospital',
        reason: 'Worsening breathing',
        urgency: ReferralUrgency.immediate,
        issuedBy: 'u-1',
        issuedAt: DateTime(2026, 9, 24),
        linkFromReferralId: 'ref-1',
      );

      expect(referral.isChained, isTrue);
    });
  });

  group('ScheduledContact', () {
    test('carries the referral it exists to chase', () {
      final contact = ScheduledContact(
        id: 'sc-1',
        personId: 'p-1',
        householdId: 'h-1',
        dueDate: DateTime(2026, 9, 26),
        purpose: 'Re-check referral CB-1K2M',
        createdBy: 'u-1',
        referralId: 'ref-1',
      );

      expect(ScheduledContact.fromMap(contact.toMap()).referralId, 'ref-1');
    });

    test('a routine growth visit has no referral', () {
      final contact = ScheduledContact(
        id: 'sc-2',
        personId: 'p-1',
        householdId: 'h-1',
        dueDate: DateTime(2026, 9, 26),
        purpose: 'Weight check',
        createdBy: 'u-1',
      );

      expect(contact.referralId, isNull);
    });
  });
}
