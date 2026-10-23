/// Two claims the judges asked for and a rule engine can honestly make:
///
///   1. how far the measurement was from the line it crossed, and
///   2. what value would have changed the answer.
///
/// Both are arithmetic on the guideline's own cut-offs, and the second one
/// re-runs the real engine rather than quoting a stored sentence. A respiratory
/// rate of 51 against a cut-off of 50 is the same classification as 62 — and it
/// is a much less comfortable one. That difference is the most useful thing a
/// decision support system can say to a nurse, and it is the thing a single
/// blended "confidence" percentage hides.
library;

import 'package:carebridge_ai/domain/engines/child_engine.dart';
import 'package:carebridge_ai/domain/engines/protocol_counterfactual.dart';
import 'package:flutter_test/flutter_test.dart';

ChildInput _child({
  int? rr,
  double? temp,
  double? muac,
  int months = 14,
  bool cough = false,
}) => ChildInput(
  ageInMonths: months,
  respiratoryRate: rr,
  temperatureCelsius: temp,
  muacCm: muac,
  cough: cough,
);

void main() {
  group('criterion margin — how close was the call', () {
    test('one beat above the cut-off is borderline', () {
      // 8 months sits in the <12 month band, where the cut-off is 50/min.
      final margins = ProtocolThresholds.forChild(_child(rr: 51, months: 8));
      final fast = margins.firstWhere((m) => m.label == 'Fast breathing');
      expect(fast.borderline, isTrue);
      expect(fast.cutoff, 50);
    });

    test('twelve beats above it is a clear call', () {
      final margins = ProtocolThresholds.forChild(_child(rr: 62));
      final fast = margins.firstWhere((m) => m.label == 'Fast breathing');
      expect(fast.borderline, isFalse);
    });

    test('a below-the-line test reads its own direction', () {
      // MUAC classifies when it is UNDER 11.5 cm. A margin computed with the
      // wrong sign would call 15 cm the borderline value, which is nonsense.
      final margins = ProtocolThresholds.forChild(
        _child(rr: 40, muac: 11.6, months: 14),
      );
      final muac = margins.firstWhere((m) => m.label.contains('malnutrition'));
      expect(muac.abnormalSide, AbnormalSide.below);
      expect(muac.borderline, isTrue);
    });

    test('an unmeasured value produces no margin rather than a zero', () {
      // 0 is not "far from the cut-off" — it means nobody counted. Inventing a
      // margin here would be inventing confidence.
      final margins = ProtocolThresholds.forChild(_child());
      final fast = margins.firstWhere((m) => m.label == 'Fast breathing');
      expect(fast.measured, isFalse);
      expect(fast.borderline, isFalse);
      expect(fast.statement, contains('not counted'));
    });

    test('the cut-off travels with the age band', () {
      // <12 months uses 50/min, 12-59 months uses 40/min.
      expect(
        ProtocolThresholds.forChild(_child(rr: 45, months: 8))
            .firstWhere((m) => m.label == 'Fast breathing')
            .cutoff,
        50,
      );
      expect(
        ProtocolThresholds.forChild(_child(rr: 45, months: 24))
            .firstWhere((m) => m.label == 'Fast breathing')
            .cutoff,
        40,
      );
    });
  });

  group('counterfactual — re-run the engine, do not recite a sentence', () {
    test('dropping the rate below the cut-off flips the classification', () {
      final cf = ProtocolCounterfactual.forChild(
        input: _child(rr: 62, cough: true, months: 8),
        measurement: 'respiratoryRate',
        toValue: 48,
      );
      expect(cf, isNotNull);
      expect(cf!.verdictChanges, isTrue);
      expect(cf.conditionBefore, contains('PNEUMONIA'));
      expect(cf.conditionAfter, isNot(contains('PNEUMONIA')));
      expect(cf.sentence, contains('48'));
    });

    test('a change that stays above the cut-off says so honestly', () {
      final cf = ProtocolCounterfactual.forChild(
        input: _child(rr: 62, cough: true),
        measurement: 'respiratoryRate',
        toValue: 55,
      );
      expect(cf!.verdictChanges, isFalse);
      expect(cf.sentence, contains('still'));
    });

    test('the smallest value that changes the verdict is found, not assumed',
        () {
      // Pneumonia is >= 50/min for an 8-month-old, so 49 is the first integer
      // that clears it. This is searched by re-running the engine, so it stays
      // true if the band logic ever moves.
      final flip = ProtocolCounterfactual.nearestFlipForChild(
        input: _child(rr: 62, cough: true, months: 8),
        measurement: 'respiratoryRate',
      );
      expect(flip, isNotNull);
      expect(flip!.toValue, 49);
      expect(flip.verdictChanges, isTrue);
    });

    test('nothing is counterfactual about a measurement never taken', () {
      expect(
        ProtocolCounterfactual.forChild(
          input: _child(),
          measurement: 'respiratoryRate',
          toValue: 40,
        ),
        isNull,
      );
    });

    test('an unknown measurement name returns null, not a guess', () {
      final cf = ProtocolCounterfactual.forChild(
        input: _child(rr: 62, cough: true),
        measurement: 'systolicBloodPressure',
        toValue: 90,
      );
      expect(cf, isNull);
    });
  });

  group('the probe cannot silently drop a field', () {
    test('a copy with nothing changed assesses identically', () {
      // ChildInput.copyWith has 63 fields. An omitted one would not be a
      // compile error — it would read as false or as unmeasured, and the
      // counterfactual would start lying quietly. This catches it as a changed
      // verdict instead.
      final full = ChildInput(
        ageInMonths: 18,
        respiratoryRate: 62,
        temperatureCelsius: 38.6,
        weightKg: 9.4,
        heightCm: 80,
        muacCm: 12.1,
        cough: true,
        coughDurationDays: 4,
        diarrhoea: true,
        diarrhoeaDurationDays: 3,
        bloodInStool: true,
        unableToDrinkOrBreastfeed: true,
        feverReported: true,
        malariaRdtDone: true,
        malariaRdtPositive: true,
        measlesRash: true,
        earDischarge: true,
        somePalmarPallor: true,
        haemoglobin: 9.8,
        mealsPerDay: 3,
        foodGroupsEatenYesterday: 2,
        immunisationsUpToDate: false,
        overdueVaccines: const ['Measles 2'],
        householdHasValidNhis: false,
        walkingMinutesToFacility: 95,
      );
      final before = ChildEngine.assess(full);
      final after = ChildEngine.assess(full.copyWith());
      expect(after.classification, before.classification);
      expect(after.triage, before.triage);
      expect(after.findings.length, before.findings.length);
      expect(after.actions.length, before.actions.length);
      expect(after.evidenceSufficiency, before.evidenceSufficiency);
    });
  });
}
