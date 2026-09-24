/// Weight-based dispensing arithmetic.
///
/// These pin the numbers a CHO would act on at the bedside, and — just as
/// importantly — the cases where the app must say nothing: no weight, no
/// calculated dose. A silently wrong tablet count is worse than none.
library;

import 'package:carebridge_ai/domain/engines/child_engine.dart';
import 'package:carebridge_ai/domain/engines/protocols/dispensing.dart';
import 'package:carebridge_ai/domain/engines/protocols/stabilization_protocols.dart';
import 'package:flutter_test/flutter_test.dart';

/// Amoxicillin 40 mg/kg as the child-pneumonia protocol states it.
const amoxicillin = DosePerKilogram(
  mgPerKg: 40,
  unit: DrugUnit(label: '250 mg dispersible tablet', mg: 250),
  citation: 'test citation',
);

void main() {
  group('DosePerKilogram — counted units', () {
    test('11.2 kg works out to 448 mg and rounds to two 250 mg tablets', () {
      final d = amoxicillin.dispense(11.2)!;

      expect(d.working, '40 mg/kg × 11.2 kg = 448 mg');
      expect(d.measure, '2 × 250 mg dispersible tablet = 500 mg');
      expect(d.unmeasurable, isFalse);
      expect(d.caution, isNull);
      // 500 against a 448 target.
      expect(d.driftPercent, closeTo(11.607, 0.001));
    });

    test('a halvable unit measures in half-tablets', () {
      const halfTablet = DosePerKilogram(
        mgPerKg: 40,
        unit: DrugUnit(
          label: '250 mg dispersible tablet',
          mg: 250,
          halvable: true,
        ),
        citation: 'test citation',
      );

      final d = halfTablet.dispense(3.5)!;

      expect(d.working, '40 mg/kg × 3.5 kg = 140 mg');
      expect(d.measure, '0.5 × 250 mg dispersible tablet = 125 mg');
      expect(d.driftPercent, closeTo(-10.714, 0.001));
      expect(d.unmeasurable, isFalse);
    });

    test('a dose under one whole tablet is reported, not rounded up', () {
      final d = amoxicillin.dispense(3.0)!;

      expect(d.unmeasurable, isTrue);
      expect(d.measure, contains('cannot be counted out accurately'));
      expect(d.caution, isNotNull);
    });

    test(
      'a rounding that misses the target by over 20% is flagged unusable',
      () {
        // 4.5 kg → 180 mg; the only measurable amount is 250 mg, +38.9%.
        final d = amoxicillin.dispense(4.5)!;

        expect(d.unmeasurable, isTrue);
        expect(d.driftPercent, closeTo(38.889, 0.001));
        expect(d.caution, contains('38.9%'));
        expect(d.caution, contains('Do not round to this figure'));
      },
    );

    test('a stated ceiling caps the dose but the working still shows the maths',
        () {
      const capped = DosePerKilogram(
        mgPerKg: 40,
        unit: DrugUnit(label: '250 mg tablet', mg: 250),
        maximumSingleDoseMg: 1000,
        citation: 'test citation',
      );

      final d = capped.dispense(30)!;

      // The published per-kg figure is still 1200 mg for this child...
      expect(d.working, '40 mg/kg × 30 kg = 1200 mg');
      // ...but the ceiling the citation states governs what is dispensed.
      expect(d.measure, '4 × 250 mg tablet = 1000 mg');
      expect(d.driftPercent, closeTo(-16.667, 0.001));
    });

    test('no ceiling means no invented ceiling', () {
      // Guards the deliberate default: guessing an adult maximum is how a
      // child gets an adult dose.
      expect(amoxicillin.maximumSingleDoseMg, isNull);
      expect(
        amoxicillin.dispense(30)!.measure,
        '5 × 250 mg dispersible tablet = 1250 mg',
      );
    });

    test('no weight produces no number', () {
      expect(amoxicillin.dispense(null), isNull);
      expect(amoxicillin.dispense(0), isNull);
      expect(amoxicillin.dispense(-4), isNull);
    });
  });

  group('FluidPerKilogram — ORS Plan B', () {
    const planB = FluidPerKilogram(
      mlPerKg: 75,
      hours: 4,
      citation: 'WHO Plan B',
    );

    test('11.2 kg needs 840 ml over 4 hours from one sachet', () {
      final d = planB.dispense(11.2)!;

      expect(d.working, '75 ml/kg × 11.2 kg = 840 ml');
      expect(
        d.measure,
        'Give 840 ml over 4 hours — about 210 ml an hour, '
        'from 1 × 1000 ml sachet',
      );
    });

    test('14 kg crosses into a second sachet and a fractional hourly rate', () {
      final d = planB.dispense(14)!;

      expect(
        d.measure,
        'Give 1050 ml over 4 hours — about 262.5 ml an hour, '
        'from 2 × 1000 ml sachets',
      );
    });

    test('no weight produces no volume', () {
      expect(planB.dispense(null), isNull);
    });
  });

  group('MilligramTarget — figure without a strength table', () {
    const artesunate = MilligramTarget(
      mgPerKg: 10,
      selectNote: 'Choose the rectal artesunate strength closest to this figure.',
      citation: 'MSF Medical Guidelines',
    );

    test('12 kg is a 120 mg target and the CHO picks the strength', () {
      final d = artesunate.dispense(12)!;

      expect(d.working, '10 mg/kg × 12 kg = 120 mg');
      expect(
        d.measure,
        '120 mg total. Choose the rectal artesunate strength closest to '
        'this figure.',
      );
      // The whole point of this variant: no invented tablet count.
      expect(d.unmeasurable, isFalse);
      expect(d.driftPercent, isNull);
    });

    test('no weight produces no target', () {
      expect(artesunate.dispense(null), isNull);
    });
  });

  group('Protocol wiring', () {
    test('the amoxicillin step calculates from the weight it is shown', () {
      final step = childPneumoniaProtocol.steps.first;
      final dosing = step.dispensing;

      expect(dosing, isA<DosePerKilogram>());
      // The published dose string and the arithmetic must never disagree.
      expect((dosing! as DosePerKilogram).mgPerKg, 40);
      expect(step.dose, contains('40 mg/kg'));
      expect(step.toMap()['weight_based'], true);
    });

    test('a step with no dispensing stays a plain dose string', () {
      final oxygen = childPneumoniaProtocol.steps[1];

      expect(oxygen.dispensing, isNull);
      expect(oxygen.toMap().containsKey('weight_based'), isFalse);
    });

    test('fixed-dose protocols carry no weight arithmetic', () {
      for (final step in preEclampsiaProtocol.steps) {
        expect(step.dispensing, isNull, reason: step.action);
      }
    });
  });

  group('ChildEngine — the calculated amount reaches the action', () {
    test('Plan B names the volume for a weighed child', () {
      final result = ChildEngine.assess(
        const ChildInput(
          ageInMonths: 14,
          diarrhoea: true,
          restlessOrIrritable: true,
          drinksEagerly: true,
          weightKg: 11.2,
        ),
      );

      final ors = result.actions.firstWhere(
        (a) => a.instruction.contains('ORS over 4 hours'),
      );
      expect(ors.instruction, contains('Give 840 ml over 4 hours'));
      expect(ors.instruction, contains('75 ml/kg × 11.2 kg = 840 ml'));
    });

    test('Plan B stays generic when the child was not weighed', () {
      final result = ChildEngine.assess(
        const ChildInput(
          ageInMonths: 14,
          diarrhoea: true,
          restlessOrIrritable: true,
          drinksEagerly: true,
        ),
      );

      final ors = result.actions.firstWhere(
        (a) => a.instruction.contains('ORS over 4 hours'),
      );
      expect(ors.instruction, isNot(contains('ml')));
    });

    test('pre-referral rectal artesunate gives mg but no strength count', () {
      final result = ChildEngine.assess(
        const ChildInput(
          ageInMonths: 30,
          feverReported: true,
          lethargicOrUnconscious: true,
          weightKg: 12,
        ),
      );

      final artesunate = result.actions.firstWhere(
        (a) => a.instruction.contains('rectal artesunate'),
      );
      expect(artesunate.instruction, contains('120 mg total'));
      expect(artesunate.instruction, contains('10 mg/kg × 12 kg = 120 mg'));
      expect(artesunate.instruction, contains('closest to this figure'));
      // Deferred by the owner until the Ghana NMPC strength table is supplied.
      expect(artesunate.instruction, isNot(contains('suppositor')));
    });
  });
}
