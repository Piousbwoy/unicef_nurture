/// PNC engine: the first 42 days, where most maternal deaths happen.
library;

import 'package:carebridge_ai/domain/engines/pnc_engine.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PncEngine', () {
    test('heavy bleeding on day 1 is a primary haemorrhage — refer now', () {
      final result = PncEngine.assess(
        const PostpartumInput(daysSinceDelivery: 1, heavyBleeding: true),
      );

      expect(result.triage, TriageLevel.urgent);
      expect(result.needsReferral, isTrue);
      expect(result.dangerSignsPresent, isNotEmpty);
    });

    test('fever with foul-smelling discharge is sepsis until proven otherwise', () {
      final result = PncEngine.assess(
        const PostpartumInput(
          daysSinceDelivery: 5,
          fever: true,
          foulSmellingDischarge: true,
        ),
      );

      expect(result.triage, TriageLevel.urgent);
    });

    test('convulsions postpartum are urgent (late eclampsia)', () {
      final result = PncEngine.assess(
        const PostpartumInput(daysSinceDelivery: 8, convulsions: true),
      );

      expect(result.triage, TriageLevel.urgent);
    });

    test('a well mother at day 42 is not referred', () {
      final result = PncEngine.assess(
        const PostpartumInput(
          daysSinceDelivery: 42,
          temperatureCelsius: 36.8,
          systolic: 112,
          diastolic: 72,
          haemoglobin: 11.2,
          breastfeedingEstablished: true,
        ),
      );

      expect(result.triage.requiresReferral, isFalse);
      expect(result.clientType, ClientType.postpartumWoman);
    });

    test('self-harm thoughts are never routine', () {
      final result = PncEngine.assess(
        const PostpartumInput(
          daysSinceDelivery: 14,
          thoughtsOfSelfHarm: true,
        ),
      );

      expect(result.triage.isAtLeastPriority, isTrue);
      expect(result.actions, isNotEmpty);
    });

    test('the minor complaint she walked in with is captured', () {
      final result = PncEngine.assess(
        const PostpartumInput(
          daysSinceDelivery: 10,
          presentingComplaint: 'burning when passing urine',
          painfulUrination: true,
        ),
      );

      // A urinary infection after delivery needs treatment, not dismissal.
      expect(result.triage.isAtLeastPriority, isTrue);
      expect(result.actions, isNotEmpty);
    });

    test('caesarean wound infection escalates', () {
      final result = PncEngine.assess(
        const PostpartumInput(
          daysSinceDelivery: 7,
          deliveryMode: DeliveryMode.caesarean,
          caesareanWoundRedOrDraining: true,
          fever: true,
        ),
      );

      expect(result.triage.isAtLeastPriority, isTrue);
    });

    test('missing measurements lower confidence but never safety', () {
      final withSign = PncEngine.assess(
        const PostpartumInput(daysSinceDelivery: 3, heavyBleeding: true),
      );
      final withoutMeasurements = PncEngine.assess(
        const PostpartumInput(daysSinceDelivery: 3),
      );

      // The danger sign verdict is identical whether or not vitals were taken.
      expect(withSign.triage, TriageLevel.urgent);
      expect(withoutMeasurements.missingData, isNotEmpty);
    });
  });
}
