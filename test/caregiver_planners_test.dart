import 'package:carebridge_ai/data/reference/local_foods.dart';
import 'package:carebridge_ai/domain/entities/caregiver.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:carebridge_ai/domain/services/caregiver_check_policy.dart';
import 'package:carebridge_ai/domain/services/caregiver_milestone_policy.dart';
import 'package:carebridge_ai/domain/services/caregiver_food_planner.dart';
import 'package:carebridge_ai/domain/services/caregiver_today_planner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  var now = DateTime(2026, 8, 10, 12);
  const scope = CaregiverScope(userId: 'u', householdId: 'h');
  Person child({
    String id = 'baby',
    DateTime? dob,
    bool unknown = false,
    ClientType type = ClientType.newborn,
  }) => Person(
    id: id,
    householdId: 'h',
    fullName: 'Awah',
    clientType: type,
    dateOfBirth: unknown ? null : dob ?? DateTime(2026, 8, 1),
  );
  test('negative milestone wording cannot invert caregiver flags', () {
    // One age per band that carries a negatively-worded milestone ID.
    final cases = <int>[5, 10, 13, 20];
    for (final months in cases) {
      final person = child(dob: now.subtract(Duration(days: (months * 30.4375).ceil())), type: ClientType.childUnderFive);
      final band = CaregiverMilestonePolicy.bandFor(person, now)!;
      final negatives = band.milestones.where((m) => m.id.startsWith('no_') || m.id.startsWith('not_')).toList();
      expect(negatives, isNotEmpty, reason: 'band ${band.label} should have a negative milestone');
      for (final negativeId in negatives) {
        expect(negativeId.question, isNot(contains(' not ')));
        final answers = {for (final m in band.milestones) m.id: CaregiverAnswer.yes};
        CaregiverDraft draft() => CaregiverDraft(id: 'milestone', scope: scope, personId: person.id,
          kind: CaregiverDraftKind.milestone, questionVersion: CaregiverMilestonePolicy.questionVersion,
          cohortKey: CaregiverMilestonePolicy.cohortKey(person, band), answers: answers,
          startedAt: now, updatedAt: now);
        expect(CaregiverMilestonePolicy.report(draft(), person, now).verdict, MilestoneVerdict.onTrack);
        answers[negativeId.id] = CaregiverAnswer.no;
        expect(CaregiverMilestonePolicy.report(draft(), person, now).flags, contains(negativeId.question));
      }
    }
  });

  final policy = CaregiverCheckPolicy(clock: () => now);
  final foodPlanner = CaregiverFoodPlanner(clock: () => now);
  final todayPlanner = CaregiverTodayPlanner(clock: () => now);
  CaregiverSettings settings({
    Set<String> have = const {},
    Set<String> avoid = const {},
    bool low = true,
  }) => CaregiverSettings(
    scope: scope,
    updatedAt: now,
    foodsHave: have,
    foodsAvoid: avoid,
    lowCost: low,
  );
  Assessment assessment({String id = 'a', int? days = 3, String? raw}) =>
      Assessment(
        id: id,
        visitId: 'visit',
        personId: 'baby',
        clientType: ClientType.newborn,
        performedBy: 'nurse',
        performedAt: DateTime(2026, 8, 1, 9),
        inputs: const {},
        carePlanJson: raw,
        result: AssessmentResult(
          clientType: ClientType.newborn,
          triage: TriageLevel.routine,
          classification: 'Review feeding',
          findings: const [],
          actions: const [],
          confidence: RecommendationConfidence.high,
          followUpInDays: days,
        ),
      );
  HomeCheck home({HomeCheckVerdict verdict = HomeCheckVerdict.urgent}) =>
      HomeCheck(
        id: 'check',
        householdId: 'h',
        personId: 'baby',
        clientType: ClientType.newborn,
        verdict: verdict,
        yesSigns: const ['Not feeding'],
        unsureSigns: const [],
        checkedBy: 'u',
        checkedAt: now,
      );
  ScheduledContact contact({
    String id = 'contact',
    String purpose = 'Review feeding — review',
    DateTime? completed,
  }) => ScheduledContact(
    id: id,
    personId: 'baby',
    householdId: 'h',
    assessmentId: 'a',
    dueDate: DateTime(2026, 8, 7),
    purpose: purpose,
    createdBy: 'nurse',
    completedAt: completed,
  );
  setUp(() => now = DateTime(2026, 8, 10, 12));

  group('caregiver safety policy', () {
    for (final person in [
      child(),
      child(dob: DateTime(2025, 8, 1)),
      child(type: ClientType.pregnantWoman),
      child(type: ClientType.postpartumWoman),
    ]) {
      final label = '${person.clientType.name}-${person.dateOfBirth}';
      test('$label: only all-NO completion is routine', () {
        final set = policy.questionsFor(person)!;
        expect(policy.decide(set, {}), CaregiverCheckDecision.incomplete);
        expect(
          policy.decide(set, {set.questions.first.key: CaregiverAnswer.no}),
          CaregiverCheckDecision.incomplete,
        );
        final answers = {
          for (final q in set.questions) q.key: CaregiverAnswer.no,
        };
        expect(policy.decide(set, answers), CaregiverCheckDecision.routine);
        answers[set.questions.first.key] = CaregiverAnswer.unsure;
        expect(
          policy.decide(set, answers),
          CaregiverCheckDecision.contactToday,
        );
      });
      test(
        '$label: every positive sign is immediately urgent, including partial checks',
        () {
          final set = policy.questionsFor(person)!;
          for (final question in set.questions) {
            expect(
              policy.decide(set, {question.key: CaregiverAnswer.yes}),
              CaregiverCheckDecision.urgent,
              reason: question.key,
            );
            expect(set.speechId(question), '${set.group}.${question.key}');
          }
        },
      );
    }
    test('unknown, future and out-of-range child ages are unsupported', () {
      for (final person in [
        child(unknown: true),
        child(dob: DateTime(2027)),
        child(dob: DateTime(2018)),
        child(type: ClientType.womanOfReproductiveAge),
      ]) {
        expect(policy.questionsFor(person), isNull);
        expect(policy.decide(null, {}), CaregiverCheckDecision.unsupported);
      }
    });
    test('each blocked record gets its own reason, supported ones none', () {
      expect(
        policy.blockReasonFor(child(unknown: true))!.headline,
        'A birth date is missing',
      );
      expect(
        policy.blockReasonFor(child(dob: DateTime(2027)))!.headline,
        'The birth date looks wrong',
      );
      final aged = policy.blockReasonFor(child(dob: DateTime(2018)))!;
      expect(aged.headline, 'Past the under-five window');
      expect(aged.detail, contains('This check covers children under five'));
      final general = policy.blockReasonFor(
        child(type: ClientType.womanOfReproductiveAge),
      )!;
      expect(general.headline, 'A different kind of record');
      expect(
        general.detail,
        contains(ClientType.womanOfReproductiveAge.label),
      );
      for (final ok in [
        child(),
        child(type: ClientType.childUnderFive),
        child(type: ClientType.pregnantWoman),
        child(type: ClientType.postpartumWoman),
      ]) {
        expect(policy.blockReasonFor(ok), isNull, reason: ok.clientType.name);
      }
    });
    test(
      'cohort boundary is 59/60 days and pregnancy-only sign is conditional',
      () {
        expect(
          policy
              .questionsFor(child(dob: now.subtract(const Duration(days: 59))))!
              .group,
          'newborn',
        );
        expect(
          policy
              .questionsFor(child(dob: now.subtract(const Duration(days: 60))))!
              .group,
          'child',
        );
        expect(
          policy
              .questionsFor(child(type: ClientType.postpartumWoman))!
              .questions
              .any((q) => q.key == 'move'),
          isFalse,
        );
        expect(
          policy
              .questionsFor(child(type: ClientType.pregnantWoman))!
              .questions
              .any((q) => q.key == 'move'),
          isTrue,
        );
      },
    );
    test('cohort and question version changes invalidate a draft', () {
      final person = child(dob: now.subtract(const Duration(days: 59)));
      final draft = CaregiverDraft(
        id: 's',
        scope: scope,
        personId: person.id,
        kind: CaregiverDraftKind.homeCheck,
        questionVersion: 1,
        cohortKey: policy.questionsFor(person)!.cohortKey,
        answers: const {},
        startedAt: now,
        updatedAt: now,
      );
      expect(policy.compatible(draft, person), isTrue);
      now = now.add(const Duration(days: 1));
      expect(policy.compatible(draft, person), isFalse);
    });
  });

  group('general food ideas', () {
    test('unknown age and infants have no current meal builder', () {
      expect(
        foodPlanner.build(child(unknown: true), settings()).gate,
        CaregiverFoodGate.confirmAge,
      );
      final infant = foodPlanner.build(
        child(),
        settings(have: {'Millet', 'Groundnut paste'}),
      );
      expect(infant.gate, CaregiverFoodGate.feedingSupport);
      expect(infant.meals, isEmpty);
      expect(infant.available, isEmpty);
      expect(
        foodPlanner.alternatives(LocalFoods.all.first, child(), settings()),
        isEmpty,
      );
    });
    test('six-month boundary uses calendar months', () {
      final person = child(dob: DateTime(2026, 2, 10));
      now = DateTime(2026, 8, 9);
      expect(
        foodPlanner.build(person, settings()).gate,
        CaregiverFoodGate.feedingSupport,
      );
      now = DateTime(2026, 8, 10);
      expect(
        foodPlanner.build(person, settings()).gate,
        CaregiverFoodGate.ready,
      );
    });
    test(
      'meals only use actual selections, not avoided or age-restricted ingredients',
      () {
        final person = child(dob: DateTime(2026, 2, 1));
        final ideas = foodPlanner.build(
          person,
          settings(
            have: {
              'Millet',
              'Groundnut paste',
              'Bambara beans',
              'Wagashi (local cheese)',
            },
            avoid: {'Groundnut paste'},
          ),
        );
        expect(ideas.available.map((f) => f.name), ['Millet']);
        expect(ideas.meals.single.ingredients.map((f) => f.name), ['Millet']);
        expect(foodPlanner.build(person, settings()).meals, isEmpty);
      },
    );
    test(
      'reported foods can be used out of season; alternatives retain restrictions',
      () {
        final person = child(dob: DateTime(2025, 8, 1));
        final preferences = settings(have: {'Yam'}, avoid: {'Millet', 'Rice'});
        expect(
          foodPlanner.build(person, preferences).available.map((f) => f.name),
          ['Yam'],
        );
        final alternatives = foodPlanner.alternatives(
          LocalFoods.all.first,
          person,
          preferences,
        );
        expect(
          alternatives.every(
            (f) =>
                f.group == FoodGroup.grainsRootsTubers &&
                !preferences.foodsAvoid.contains(f.name),
          ),
          isTrue,
        );
        expect(
          alternatives.every(
            (f) => f.availableIn(8) || preferences.foodsHave.contains(f.name),
          ),
          isTrue,
        );
      },
    );
    test('no suitable alternative is represented by an empty list', () {
      final eggs = LocalFoods.all.firstWhere((f) => f.group == FoodGroup.eggs);
      final choices = foodPlanner.alternatives(
        eggs,
        child(dob: DateTime(2025)),
        settings(avoid: {'Chicken eggs', 'Guinea fowl eggs'}),
      );
      expect(choices, isEmpty);
    });
    test('new preparation copy omits nutrient adequacy and outcome claims', () {
      for (final food in LocalFoods.all) {
        expect(
          CaregiverFoodPlanner.preparationFor(food),
          isNot(contains('transforms')),
        );
        expect(
          CaregiverFoodPlanner.preparationFor(food),
          isNot(contains('complete protein')),
        );
      }
      expect(
        CaregiverFoodPlanner.preparationFor(
          LocalFoods.all.firstWhere((f) => f.name == 'Fresh cow milk'),
        ),
        contains('Not a main drink under one year'),
      );
    });
  });

  group('today planner', () {
    test(
      'urgent clinic referral and concerning checks precede routine focus',
      () {
        final referral = Referral(
          id: 'r',
          referenceCode: 'TEST',
          personId: 'baby',
          assessmentId: 'a',
          facilityName: 'CHPS',
          reason: 'Urgent review',
          urgency: ReferralUrgency.immediate,
          issuedBy: 'nurse',
          issuedAt: now,
        );
        final day = todayPlanner.build(
          scope: scope,
          members: [child()],
          checks: [home()],
          referrals: [referral],
          contacts: [contact()],
        );
        expect(day.attention.map((f) => f.source), [
          CaregiverFocusSource.clinic,
          CaregiverFocusSource.homeCheck,
        ]);
        expect(day.attention.every((f) => !f.canComplete), isTrue);
        expect(day.routine.first.source, CaregiverFocusSource.clinic);
        expect(day.focus.length, lessThanOrEqualTo(3));
      },
    );
    test('a recheck promise made yesterday surfaces today until discharged', () {
      final yesterday = DateTime(2026, 8, 9, 12);
      final promise = CaregiverActivity(
        id: 'p1',
        scope: scope,
        personId: 'baby',
        kind: CaregiverActivityKind.dailyTask,
        sourceId: 'check-1',
        itemKey: 'recheck',
        occurrenceKey: caregiverDateKey(now),
        occurredAt: yesterday,
        updatedAt: yesterday,
      );
      final day = todayPlanner.build(
        scope: scope,
        members: [child()],
        checks: const [],
        activity: [promise],
      );
      expect(day.attention.any((f) => f.itemKey == 'recheck-promised'), isTrue);
      // A check completed today discharges the promise.
      final discharged = todayPlanner.build(
        scope: scope,
        members: [child()],
        checks: [
          HomeCheck(
            id: 'check2',
            householdId: 'h',
            personId: 'baby',
            clientType: ClientType.newborn,
            verdict: HomeCheckVerdict.fine,
            yesSigns: const [],
            unsureSigns: const [],
            checkedBy: 'u',
            checkedAt: now,
          ),
        ],
        activity: [promise],
      );
      expect(
        discharged.attention.any((f) => f.itemKey == 'recheck-promised'),
        isFalse,
      );
    });
    test('follow-up uses the original assessment date, not today', () {
      final day = todayPlanner.build(
        scope: scope,
        members: [child()],
        assessments: [assessment()],
      );
      final followUp = day.routine.firstWhere((f) => f.itemKey == 'follow-up');
      expect(followUp.dueDate, DateTime(2026, 8, 4));
      expect(followUp.detail, contains('not a booked appointment'));
    });
    test('matching explicit contact wins and duplicates are removed', () {
      final day = todayPlanner.build(
        scope: scope,
        members: [child()],
        assessments: [assessment()],
        contacts: [
          contact(),
          contact(id: 'duplicate'),
        ],
      );
      expect(
        day.routine.where((f) => f.source == CaregiverFocusSource.clinic),
        hasLength(1),
      );
      expect(day.routine.first.dueDate, DateTime(2026, 8, 7));
      final completed = todayPlanner.build(
        scope: scope,
        members: [child()],
        assessments: [assessment()],
        contacts: [contact(completed: now)],
      );
      expect(
        completed.routine.where((f) => f.source == CaregiverFocusSource.clinic),
        isEmpty,
      );
    });
    test('unrelated appointment does not suppress a clinician review', () {
      final day = todayPlanner.build(
        scope: scope,
        members: [child()],
        assessments: [assessment()],
        contacts: [contact(purpose: 'Vaccination')],
      );
      expect(
        day.routine.where((f) => f.source == CaregiverFocusSource.clinic),
        hasLength(2),
      );
    });
    test(
      'daily completion resets on local midnight without clearing danger signs',
      () {
        final activity = CaregiverActivity(
          id: 'activity',
          scope: scope,
          personId: 'baby',
          kind: CaregiverActivityKind.dailyTask,
          sourceId: 'everyday',
          itemKey: 'feeding',
          occurrenceKey: '2026-08-10',
          occurredAt: now,
          updatedAt: now,
        );
        CaregiverDay plan() => todayPlanner.build(
          scope: scope,
          members: [child()],
          activity: [activity],
          checks: [home()],
        );
        expect(
          plan().routine.singleWhere((f) => f.itemKey == 'feeding').done,
          isTrue,
        );
        expect(plan().attention, hasLength(1));
        now = DateTime(2026, 8, 11);
        expect(
          plan().routine.singleWhere((f) => f.itemKey == 'feeding').done,
          isFalse,
        );
        expect(plan().attention, hasLength(1));
      },
    );
    test(
      'selection filters routine tasks but never hides family emergencies',
      () {
        final day = todayPlanner.build(
          scope: scope,
          members: [
            child(),
            child(id: 'sibling'),
          ],
          checks: [home()],
          selectedPersonId: 'sibling',
        );
        expect(day.routine.every((f) => f.personId == 'sibling'), isTrue);
        expect(day.attention.single.personId, 'baby');
      },
    );
    test('unknown birth date invents neither feeding age nor play tasks', () {
      final day = todayPlanner.build(
        scope: scope,
        members: [child(unknown: true)],
      );
      expect(day.routine, isEmpty);
    });
    test(
      'malformed clinic plan is surfaced, not replaced with invented follow-up',
      () {
        final day = todayPlanner.build(
          scope: scope,
          members: [child()],
          assessments: [assessment(raw: 'broken')],
        );
        expect(day.routine.first.itemKey, 'unreadable-plan');
        expect(day.routine.where((f) => f.itemKey == 'follow-up'), isEmpty);
      },
    );
  });
}
