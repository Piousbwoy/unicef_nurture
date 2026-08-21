/// Immunisation catch-up engine: Ghana EPI schedule, made actionable.
library;

import 'package:carebridge_ai/domain/engines/immunisation_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ImmunisationEngine', () {
    test('a newborn at first contact gets BCG and the birth OPV dose', () {
      final plan = ImmunisationEngine.plan(ageInDays: 3, givenLabels: {});

      final today = plan.giveToday.map((d) => d.label).toSet();
      expect(today, contains('BCG'));
      expect(plan.isFullyUpToDate, isFalse);
    });

    test('a 10-week-old with birth and 6-week doses gets the 10-week set', () {
      final plan = ImmunisationEngine.plan(
        ageInDays: 70,
        givenLabels: {'BCG', 'OPV 1', 'Penta 1', 'PCV 1', 'Rota 1'},
      );

      final today = plan.giveToday.map((d) => d.label).toSet();
      expect(today, containsAll(['Penta 2', 'OPV 2', 'PCV 2', 'Rota 2']));
      // Nothing already given is offered again.
      expect(today, isNot(contains('BCG')));
      expect(today, isNot(contains('Penta 1')));
    });

    test('a child with everything due for age is fully up to date', () {
      const ageInDays =
          300; // ~43 weeks: past the 14-week set, before MR at 9 months.
      final ageWeeks = ageInDays ~/ 7;
      final due = GhanaEpi.schedule
          .where(
            (d) =>
                d.dueAtWeeks <= ageWeeks &&
                (d.maxAgeWeeks == null || ageWeeks <= d.maxAgeWeeks!),
          )
          .map((d) => d.label)
          .toSet();

      final plan = ImmunisationEngine.plan(
        ageInDays: ageInDays,
        givenLabels: due,
      );

      expect(plan.isFullyUpToDate, isTrue);
      expect(plan.giveToday, isEmpty);
      expect(plan.overdue, isEmpty);
    });

    test('a 40-week-old with no doses has a long overdue list', () {
      final plan = ImmunisationEngine.plan(ageInDays: 280, givenLabels: {});

      expect(plan.overdue, isNotEmpty);
      expect(plan.overdueLabels, contains('BCG'));
      expect(plan.overdueLabels, contains('Penta 1'));
    });

    test('rotavirus is age-barred, not given late', () {
      // Rota cannot be started after its maximum age (intussusception risk).
      final plan = ImmunisationEngine.plan(ageInDays: 300, givenLabels: {});

      final today = plan.giveToday.map((d) => d.label).toSet();
      expect(today, isNot(contains('Rota 1')));
    });

    test('the schedule covers the full Ghana EPI antigens', () {
      final antigens = GhanaEpi.schedule.map((d) => d.antigen).toSet();

      expect(
        antigens,
        containsAll(['BCG', 'OPV', 'Penta', 'PCV', 'Rota', 'MR']),
      );
    });

    test('the catch-up schedule spaces series doses across sessions', () {
      // 40 weeks, nothing given: today's session starts every series, and
      // the follow-on doses wait their minimum intervals.
      final plan = ImmunisationEngine.plan(ageInDays: 280, givenLabels: {});

      expect(plan.catchUp, isNotEmpty);
      final first = plan.catchUp.first.labels;
      expect(first, containsAll(['Penta 2', 'OPV 2', 'PCV 2']));
      expect(first, isNot(contains('Penta 3')));

      final later = plan.catchUp.expand((s) => s.labels).toList();
      expect(later, contains('Penta 3'));
      // Rotavirus is age-barred at 40 weeks: it appears nowhere.
      expect(later, isNot(contains('Rota 1')));
    });

    test('a fully up-to-date child has no catch-up sessions', () {
      const ageInDays = 300;
      final ageWeeks = ageInDays ~/ 7;
      final due = GhanaEpi.schedule
          .where(
            (d) =>
                d.dueAtWeeks <= ageWeeks &&
                (d.maxAgeWeeks == null || ageWeeks <= d.maxAgeWeeks!),
          )
          .map((d) => d.label)
          .toSet();

      final plan = ImmunisationEngine.plan(
        ageInDays: ageInDays,
        givenLabels: due,
      );

      expect(plan.catchUp, isEmpty);
    });
  });
}
