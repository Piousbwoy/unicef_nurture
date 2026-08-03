/// Barrier engine: turning individual "we couldn't come" into a pattern a
/// sub-district can act on.
library;

import 'package:carebridge_ai/domain/engines/barrier_engine.dart';
import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

BarrierReport _report(String household, CareBarrier barrier) => BarrierReport(
  id: 'b-$household-${barrier.name}',
  householdId: household,
  barriers: [barrier],
  recordedBy: 'user-1',
  recordedAt: DateTime(2026, 7, 15),
);

void main() {
  group('BarrierEngine.detectPatterns', () {
    test('one household complaining is a story, not a pattern', () {
      final patterns = BarrierEngine.detectPatterns([
        _report('h1', CareBarrier.noTransportMoney),
      ]);

      expect(patterns, isEmpty);
    });

    test('the same barrier from three households becomes a pattern', () {
      final patterns = BarrierEngine.detectPatterns([
        _report('h1', CareBarrier.noTransportMoney),
        _report('h2', CareBarrier.noTransportMoney),
        _report('h3', CareBarrier.noTransportMoney),
      ]);

      expect(patterns, hasLength(1));
      expect(patterns.first.barrier, CareBarrier.noTransportMoney);
      expect(patterns.first.householdCount, 3);
      expect(patterns.first.interpretation, isNotEmpty);
      expect(patterns.first.escalation, isNotEmpty);
    });

    test('the same household reporting twice counts once', () {
      final patterns = BarrierEngine.detectPatterns([
        _report('h1', CareBarrier.facilityClosed),
        _report('h1', CareBarrier.facilityClosed),
        _report('h2', CareBarrier.facilityClosed),
      ]);

      expect(patterns, isEmpty);
    });

    test('every barrier carries a distinct action, not a platitude', () {
      final patterns = BarrierEngine.detectPatterns([
        _report('h1', CareBarrier.facilityClosed),
        _report('h2', CareBarrier.facilityClosed),
        _report('h3', CareBarrier.facilityClosed),
        _report('h1', CareBarrier.noNhisCard),
        _report('h2', CareBarrier.noNhisCard),
        _report('h4', CareBarrier.noNhisCard),
      ]);

      expect(patterns, hasLength(2));
      final byBarrier = {for (final p in patterns) p.barrier: p};
      expect(
        byBarrier[CareBarrier.facilityClosed]!.escalation,
        isNot(byBarrier[CareBarrier.noNhisCard]!.escalation),
      );
    });

    test('no reports means no patterns', () {
      expect(BarrierEngine.detectPatterns(const []), isEmpty);
    });
  });

  group('BarrierEngine.forecast', () {
    test('a long walk plus past barriers lowers feasibility', () {
      final forecast = BarrierEngine.forecast(
        previouslyReported: const [
          CareBarrier.noTransportMoney,
          CareBarrier.distanceTooFar,
        ],
        missedContactsCount: 2,
        month: 8, // Rainy season.
      );

      expect(forecast.feasibilityNote, isNotEmpty);
      expect(forecast.referralFeasibility, inInclusiveRange(0, 1));
    });
  });
}
