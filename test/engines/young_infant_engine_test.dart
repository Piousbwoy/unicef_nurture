/// IMCI young infant engine (0–59 days).
///
/// The pink row of the chart must always win: any general danger sign or
/// fast breathing in a young infant is a referral, full stop.
library;

import 'package:carebridge_ai/domain/engines/young_infant_engine.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('YoungInfantEngine', () {
    test('a well two-week-old feeding normally stays routine', () {
      final result = YoungInfantEngine.assess(
        const YoungInfantInput(
          ageInDays: 14,
          respiratoryRate: 44,
          temperatureCelsius: 36.9,
          weightKg: 3.4,
          birthWeightKg: 3.1,
          breastfeedsPerDay: 9,
        ),
      );

      expect(result.triage.requiresReferral, isFalse);
      expect(result.clientType, ClientType.newborn);
    });

    test('fast breathing (60+) is severe disease in a young infant', () {
      final result = YoungInfantEngine.assess(
        const YoungInfantInput(ageInDays: 20, respiratoryRate: 68),
      );

      expect(result.triage, TriageLevel.urgent);
      expect(result.needsReferral, isTrue);
    });

    test('not feeding at all is a pink-row sign', () {
      final result = YoungInfantEngine.assess(
        const YoungInfantInput(ageInDays: 9, unableToFeedAtAll: true),
      );

      expect(result.triage, TriageLevel.urgent);
      expect(result.dangerSignsPresent, isNotEmpty);
    });

    test('convulsions are urgent', () {
      final result = YoungInfantEngine.assess(
        const YoungInfantInput(ageInDays: 30, convulsions: true),
      );

      expect(result.triage, TriageLevel.urgent);
    });

    test('jaundice within the first 24 hours is pathological', () {
      final result = YoungInfantEngine.assess(
        const YoungInfantInput(
          ageInDays: 1,
          jaundicePresent: true,
          jaundiceOnsetWithin24Hours: true,
        ),
      );

      expect(result.triage, TriageLevel.urgent);
    });

    test('severe chest indrawing refers', () {
      final result = YoungInfantEngine.assess(
        const YoungInfantInput(ageInDays: 25, severeChestIndrawing: true),
      );

      expect(result.triage, TriageLevel.urgent);
    });

    test('local umbilical infection alone is not a referral', () {
      final result = YoungInfantEngine.assess(
        const YoungInfantInput(
          ageInDays: 12,
          umbilicusRedOrDraining: true,
          respiratoryRate: 42,
        ),
      );

      // Local infection: treat and review, not refer — unless it spreads.
      expect(result.triage.requiresReferral, isFalse);
      expect(result.triage.isAtLeastPriority, isTrue);
    });

    test('umbilical redness extending to the skin refers', () {
      final result = YoungInfantEngine.assess(
        const YoungInfantInput(
          ageInDays: 12,
          umbilicusRedOrDraining: true,
          umbilicalRednessExtendsToSkin: true,
        ),
      );

      expect(result.triage, TriageLevel.urgent);
    });

    test('dehydration with diarrhoea escalates', () {
      final result = YoungInfantEngine.assess(
        const YoungInfantInput(
          ageInDays: 40,
          diarrhoea: true,
          sunkenEyes: true,
          skinPinchGoesBackVerySlowly: true,
        ),
      );

      expect(result.triage.isAtLeastPriority, isTrue);
    });
  });
}
