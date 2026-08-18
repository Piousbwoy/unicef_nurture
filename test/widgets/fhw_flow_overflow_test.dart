/// FHW flow overflow regression guard.
///
/// Pumps the three core screens of the field-worker flow — household,
/// visit summary, assessment result — at a real phone width (390 logical
/// pixels, the class of device the judges and frontline health workers
/// actually use). Any RenderFlex overflow throws during layout and fails
/// the test, so the "everything feels clunky" overflow class cannot
/// silently return. The screens are fed dense, real-shaped data: long
/// classification strings, multi-line findings, a walking-time factor, an
/// open referral, and five missing measurements.
library;

import 'package:carebridge_ai/app/providers.dart';
import 'package:carebridge_ai/domain/engines/vulnerability_engine.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:carebridge_ai/presentation/assessment/result_screen.dart';
import 'package:carebridge_ai/presentation/assessment/types.dart';
import 'package:carebridge_ai/presentation/fhw/household_screen.dart';
import 'package:carebridge_ai/presentation/visit/household_summary_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

AppUser _user() => AppUser(
  id: 'u-fhw-1',
  fullName: 'Amina Fuseini',
  phone: '0244000000',
  role: UserRole.frontlineHealthWorker,
  region: 'Northern Region',
  district: 'Savelugu Municipal',
  community: 'Tamale Central',
);

const _household = Household(
  id: 'h-1',
  name: 'Achana household',
  region: 'Northern Region',
  district: 'Savelugu Municipal',
  community: 'Tamale Central',
  createdBy: 'u-fhw-1',
  headName: 'Achana Yakubu',
  contactPhone: '02445678901',
  familySize: 6,
  hasValidNhis: false,
  walkingMinutesToFacility: 120,
  landmark: 'Near the central mosque at the main market square',
);

Person _person(String id, String name, ClientType type) => Person(
  id: id,
  householdId: _household.id,
  fullName: name,
  clientType: type,
  dateOfBirth: DateTime.now().subtract(switch (type) {
    ClientType.newborn => const Duration(days: 2),
    ClientType.childUnderFive => const Duration(days: 400),
    _ => const Duration(days: 365 * 27),
  }),
);

Assessment _assessment(Person p, TriageLevel triage, String classification) =>
    Assessment(
      id: 'a-${p.id}',
      visitId: 'v-1',
      personId: p.id,
      clientType: p.clientType,
      performedBy: 'u-fhw-1',
      performedAt: DateTime.now().subtract(const Duration(days: 3)),
      inputs: const {},
      result: AssessmentResult(
        clientType: p.clientType,
        triage: triage,
        classification: classification,
        findings: [
          ClinicalFinding(
            label: 'Moderate maternal anaemia',
            detail:
                'Hb 9.0 g/dL is below the 11.0 g/dL threshold for this '
                'gestation (WHO ANC 2016).',
            severity: triage,
            protocolSource: 'WHO ANC 2016',
            measuredValue: '9.0 g/dL',
            threshold: '≥ 11.0 g/dL',
            weight: 12,
          ),
        ],
        actions: [
          RecommendedAction(
            instruction:
                'Start iron-folate 60 mg + folic acid 400 mcg daily '
                'and review in 2 weeks',
            urgency: ReferralUrgency.withinTwoDays,
            rationale:
                'Anaemia is a leading driver of maternal mortality in '
                'the Northern Region.',
            protocolSource: 'WHO ANC 2016',
            isTreatment: true,
          ),
        ],
        confidence: RecommendationConfidence.low,
        missingData: const [
          'Haemoglobin not tested',
          'Maternal MUAC not measured',
          'Blood pressure not measured',
          'Urine protein not tested',
          'Gestational age by dates not confirmed',
        ],
      ),
    );

VulnerabilityScore _score() => const VulnerabilityScore(
  score: 41,
  band: VulnerabilityBand.high,
  dataCompleteness: 0.44,
  confidence: RecommendationConfidence.low,
  unknowns: ['Maternal MUAC', 'Blood pressure', 'Haemoglobin'],
  factors: [
    RiskFactor(
      label: 'Moderate maternal anaemia',
      detail:
          'Hb 9.0 g/dL — 44% prevalence in this region. The single '
          'biggest modifiable contributor to this score.',
      points: 12,
      isModifiable: true,
      source: 'Maternal record',
      suggestedAction: 'Iron-folate supplementation + dietary counselling',
    ),
    RiskFactor(
      label: 'More than 90 minutes from a facility',
      detail:
          '120 min walk. A "go now" referral is not advice here; it is a '
          'logistics problem that must be solved while the family is present.',
      points: 8,
      isModifiable: false,
      source: 'Household record',
    ),
  ],
);

void _phoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('household screen has no overflows at phone width', (
    tester,
  ) async {
    _phoneSize(tester);
    final mother = _person('p-m', 'Achana', ClientType.pregnantWoman);
    final child = _person('p-c', 'sala', ClientType.childUnderFive);
    final assessment = _assessment(
      mother,
      TriageLevel.priority,
      'PREGNANCY WITH RISK FACTORS',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(_user()),
          householdProvider.overrideWith((ref, id) async => _household),
          householdScoreProvider.overrideWith((ref, id) async => _score()),
          householdMembersProvider.overrideWith(
            (ref, id) async => [mother, child],
          ),
          householdContactsProvider.overrideWith(
            (ref, id) async => [
              ScheduledContact(
                id: 'c-1',
                personId: 'p-m',
                householdId: _household.id,
                dueDate: DateTime.now().subtract(const Duration(days: 2)),
                purpose: 'ANC 4th visit — review haemoglobin and BP',
                createdBy: 'u-fhw-1',
                priority: TriageLevel.priority,
              ),
            ],
          ),
          barrierHistoryProvider.overrideWith((ref, id) async => const []),
          householdHomeChecksProvider.overrideWith((ref, id) async => const []),
          householdMilestoneChecksProvider.overrideWith(
            (ref, id) async => const [],
          ),
          latestAssessmentProvider.overrideWith((ref, id) async {
            if (id == mother.id) return assessment;
            if (id == child.id) {
              return _assessment(child, TriageLevel.routine, 'WELL CHILD');
            }
            return null;
          }),
          personProvider.overrideWith(
            (ref, id) async => mother.id == id
                ? mother
                : child.id == id
                ? child
                : null,
          ),
        ],
        child: const MaterialApp(home: HouseholdScreen(householdId: 'h-1')),
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('summary screen has no overflows at phone width', (tester) async {
    _phoneSize(tester);
    final mother = _person('p-m', 'Achana', ClientType.pregnantWoman);
    final child = _person('p-c', 'sala', ClientType.childUnderFive);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(_user()),
          householdProvider.overrideWith((ref, id) async => _household),
          personProvider.overrideWith(
            (ref, id) async => mother.id == id
                ? mother
                : child.id == id
                ? child
                : null,
          ),
          latestAssessmentProvider.overrideWith(
            (ref, id) async => id == mother.id
                ? _assessment(
                    mother,
                    TriageLevel.priority,
                    'PREGNANCY WITH RISK FACTORS',
                  )
                : _assessment(child, TriageLevel.routine, 'WELL CHILD'),
          ),
          openReferralsProvider.overrideWith(
            (ref) async => [
              Referral(
                id: 'r-1',
                referenceCode: 'REF-2026-0417',
                personId: mother.id,
                assessmentId: 'a-p-m',
                facilityName: 'Savelugu Municipal District Hospital',
                reason:
                    'Moderate anaemia with risk factors — treat and '
                    'follow up',
                urgency: ReferralUrgency.withinTwoDays,
                issuedBy: 'u-fhw-1',
                issuedAt: DateTime.now(),
              ),
            ],
          ),
        ],
        child: MaterialApp(
          home: HouseholdSummaryScreen(
            visit: Visit(
              id: 'v-1',
              householdId: _household.id,
              conductedBy: 'u-fhw-1',
              startedAt: DateTime.now(),
              reasons: const [VisitReason.ancFollowUp],
            ),
            householdId: _household.id,
            assessedIds: [mother.id, child.id],
            notes:
                'Husband away in Kumasi until harvest; grandmother is the '
                'decision-maker and needs the referral explained in Dagbani.',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('result screen has no overflows at phone width', (tester) async {
    _phoneSize(tester);
    final person = _person('p-m', 'sala', ClientType.pregnantWoman);
    final draft = AssessmentDraft(
      inputs: const {
        'age_in_days': 0,
        'danger_signs': <String>[],
        'temperature_celsius': 36.8,
        'pulse': 92,
        'respiratory_rate': 18,
      },
      result: AssessmentResult(
        clientType: ClientType.pregnantWoman,
        triage: TriageLevel.priority,
        classification: 'PREGNANCY WITH RISK FACTORS',
        findings: [
          ClinicalFinding(
            label: 'Moderate maternal anaemia',
            detail:
                'Hb 9.0 g/dL is below the 11.0 g/dL threshold for this '
                'gestation (WHO ANC 2016).',
            severity: TriageLevel.priority,
            protocolSource: 'WHO ANC 2016',
            measuredValue: '9.0 g/dL',
            threshold: '≥ 11.0 g/dL',
          ),
        ],
        actions: [
          RecommendedAction(
            instruction:
                'Start iron-folate 60 mg + folic acid 400 mcg daily '
                'and review in 2 weeks',
            urgency: ReferralUrgency.withinTwoDays,
            rationale:
                'Anaemia is a leading driver of maternal mortality in '
                'the Northern Region.',
            protocolSource: 'WHO ANC 2016',
            isTreatment: true,
          ),
        ],
        confidence: RecommendationConfidence.low,
        missingData: const [
          'Haemoglobin not tested',
          'Maternal MUAC not measured',
          'Blood pressure not measured',
          'Urine protein not tested',
          'Gestational age by dates not confirmed',
        ],
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(_user()),
          householdProvider.overrideWith((ref, id) async => _household),
          personProvider.overrideWith((ref, id) async => person),
          latestAssessmentProvider.overrideWith((ref, id) async => null),
        ],
        child: MaterialApp(
          home: AssessmentResultScreen(
            input: AssessmentContext(
              user: _user(),
              household: _household,
              person: person,
            ),
            draft: draft,
            visitId: 'v-1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The result experience is two pages: the verdict moment, then the
    // full clinical report. Both must be overflow-free at phone width.
    final cta = find.text('Open full clinical report');
    await tester.scrollUntilVisible(
      cta,
      300,
      scrollable: find.byType(Scrollable),
    );
    // scrollUntilVisible stops once the button peeks into the viewport,
    // which can leave its centre under the sticky save bar — clear it
    // fully before tapping.
    await tester.drag(find.byType(Scrollable), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(cta);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable), const Offset(0, -1200));
    await tester.pumpAndSettle();
  });
}
