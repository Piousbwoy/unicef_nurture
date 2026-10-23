// The brief is the sentence a nurse will repeat to a supervisor. These tests
// pin that it says the *right* thing about the visit: a well child with
// overdue doses is never described as urgent, and an urgent child always names
// the finding that made them urgent.
import 'package:carebridge_ai/domain/engines/clinical_brief_engine.dart';
import 'package:carebridge_ai/domain/engines/clinical_evidence_graph.dart';
import 'package:carebridge_ai/domain/engines/clinical_impression_resolver.dart';
import 'package:carebridge_ai/domain/engines/recommendation_engine.dart';
import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

CarePlan _plan({
  TriageLevel triage = TriageLevel.routine,
  List<ClinicalFinding> findings = const [],
  List<RecommendedAction> actions = const [],
  List<String> missing = const [],
}) => CarePlan(
  overallTriage: triage,
  triageRationale: 'test',
  findings: findings,
  actions: actions,
  interactions: const [],
  confidence: RecommendationConfidence.moderate,
  evidenceSufficiency: 80,
  missingData: missing,
  dangerSigns: const [],
  referralCapabilitiesNeeded: const {},
  topDrivers: findings.take(2).toList(),
  summary: 'test',
  classifications: const [],
);

ClinicalBrief _brief({
  TriageLevel triage = TriageLevel.routine,
  List<ClinicalFinding> findings = const [],
  List<RecommendedAction> actions = const [],
  List<String> missing = const [],
  bool referral = false,
  int? followUp,
}) => ClinicalBriefEngine.build(
  ClinicalEvidenceGraph.fromPlan(
    _plan(
      triage: triage,
      findings: findings,
      actions: actions,
      missing: missing,
    ),
    classification: 'TEST',
    needsReferral: referral,
  ),
  subject: 'Rahima',
  followUpInDays: followUp,
);

const _fastBreathing = ClinicalFinding(
  label: 'Fast breathing',
  detail: 'Above the band for this age.',
  severity: TriageLevel.priority,
  protocolSource: 'IMCI child',
  measuredValue: '62/min',
  threshold: '≥ 50/min',
);

const _overdue = ClinicalFinding(
  label: 'Measles-rubella overdue',
  detail: 'Twenty weeks late.',
  severity: TriageLevel.priority,
  protocolSource: 'Ghana EPI schedule',
  raisesTriage: false,
);

const _giveToday = RecommendedAction(
  instruction: 'Give today: measles-rubella',
  urgency: ReferralUrgency.sameDay,
);

void main() {
  test('a resolved visit leads with the one ranked condition', () {
    // The brief used to open with the urgency word and leave the actual
    // classification to a joined string elsewhere. A nurse reads the condition
    // first, then how bad it is.
    final brief = ClinicalBriefEngine.build(
      ClinicalEvidenceGraph.fromPlan(
        _plan(triage: TriageLevel.urgent, findings: [_fastBreathing]),
        classification: 'TEST',
        needsReferral: true,
      ),
      impression: ClinicalImpressionResolver.resolve(
        classifications: const ['VERY SEVERE DISEASE', 'PNEUMONIA'],
        findings: [_fastBreathing],
      ),
    );
    expect(brief.impression?.conditionName, 'Very severe disease');
    expect(brief.insight, contains('general danger sign'));
    // The name is the header line's job. Repeating it inside the paragraph is
    // the double-speech this page was rebuilt to remove.
    expect(brief.insight, isNot(contains('Very severe disease')));
    // The ranked-out condition is not lost.
    expect(brief.impression?.alsoPresent, contains('PNEUMONIA'));
  });

  test('an unresolved visit keeps the urgency-first brief it always had', () {
    // Wiring the resolver into one screen must not silently reword every other
    // consumer of the brief.
    final brief = _brief(
      triage: TriageLevel.urgent,
      findings: [_fastBreathing],
    );
    expect(brief.impression, isNull);
    expect(brief.headline, 'Urgent — act before the family leaves');
  });

  test('a well child with overdue doses is never called urgent', () {
    final brief = _brief(
      findings: const [_overdue, _overdue],
      actions: const [_giveToday],
      followUp: 7,
    );

    expect(brief.isUrgent, isFalse);
    expect(brief.headline, 'Clinically well — prevention outstanding');
    expect(brief.insight, contains('Nothing found needs referral'));
    expect(brief.insight, contains('2 doses are overdue'));
    expect(brief.insight, contains('1 is due today'));
    expect(brief.insight, contains('Review in 7 days'));
    expect(brief.insight, isNot(contains('urgent')));
  });

  test('an urgent visit names its driver with the measured value', () {
    final brief = _brief(triage: TriageLevel.urgent, findings: const [_fastBreathing]);

    expect(brief.isUrgent, isTrue);
    expect(brief.headline, 'Urgent — act before the family leaves');
    expect(brief.insight, contains('Rahima is urgent'));
    expect(brief.insight, contains('62/min'));
    expect(brief.insight, contains('cut-off ≥ 50/min'));
  });

  test('a clean routine visit says so once, without decoration', () {
    final brief = _brief();

    expect(brief.headline, 'Clinically well — routine care');
    expect(brief.insight, contains('Nothing found needs referral'));
    expect(brief.careGaps, isEmpty);
    expect(brief.unknowns, isEmpty);
  });

  test('missing observations are counted, never described', () {
    final brief = _brief(missing: const ['MUAC not measured']);

    expect(brief.insight, contains('1 observation missing'));
    expect(brief.unknowns.single, 'MUAC not measured.');
  });

  test('recommendations are ordered by urgency and keep their reason', () {
    final brief = _brief(
      findings: const [_fastBreathing],
      actions: const [
        RecommendedAction(
          instruction: 'Book the next weighing',
          urgency: ReferralUrgency.scheduled,
        ),
        RecommendedAction(
          instruction: 'Treat fast breathing now',
          urgency: ReferralUrgency.immediate,
        ),
      ],
    );

    expect(brief.recommendations.first.instruction, 'Treat fast breathing now');
    expect(brief.recommendations.first.why, contains('Fast breathing'));
    expect(brief.recommendations.last.isTraceable, isFalse);
    expect(
      brief.recommendations.last.why,
      'Standing protocol for this visit.',
    );
  });

  test('a referral is stated, not implied', () {
    final brief = _brief(
      triage: TriageLevel.urgent,
      findings: const [_fastBreathing],
      referral: true,
    );

    expect(brief.insight, contains('A referral is issued.'));
  });
}
