// The graph exists to stop one kind of evidence speaking with another's
// authority: a missed vaccine must not sound like pneumonia, and a model's
// research number must not sound like either.
import 'package:carebridge_ai/domain/engines/clinical_evidence_graph.dart';
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

const _clinical = ClinicalFinding(
  label: 'Fast breathing',
  detail: 'Above the band for this age.',
  severity: TriageLevel.priority,
  protocolSource: 'IMCI child',
  measuredValue: '62/min',
  threshold: '≥ 50/min',
);

const _preventive = ClinicalFinding(
  label: 'Measles-rubella overdue',
  detail: 'Twenty weeks late.',
  severity: TriageLevel.priority,
  protocolSource: 'Ghana EPI schedule',
  raisesTriage: false,
);

const _model = ClinicalFinding(
  label: 'Sepsis research score',
  detail: 'Experimental index 61.',
  severity: TriageLevel.watch,
  protocolSource: 'neonatal_sepsis',
  aiGenerated: true,
);

const _quality = ClinicalFinding(
  label: 'Check the temperature reading',
  detail: 'Outside plausible range.',
  severity: TriageLevel.watch,
  protocolSource: 'CareBridge measurement-quality screen',
);

ClinicalEvidenceGraph _graph({
  TriageLevel triage = TriageLevel.routine,
  List<ClinicalFinding> findings = const [_clinical, _preventive, _model, _quality],
  List<RecommendedAction> actions = const [],
  List<String> missing = const [],
}) => ClinicalEvidenceGraph.fromPlan(
  _plan(
    triage: triage,
    findings: findings,
    actions: actions,
    missing: missing,
  ),
  classification: 'PNEUMONIA',
  needsReferral: false,
);

void main() {
  test('each finding is classified by what it is allowed to do', () {
    final graph = _graph();

    expect(graph.clinical.single.label, 'Fast breathing');
    expect(graph.preventive.single.label, 'Measles-rubella overdue');
    expect(graph.experimental.single.label, 'Sepsis research score');
    expect(graph.dataQuality.single.label, 'Check the temperature reading');
  });

  test('only clinical findings may raise urgency', () {
    final graph = _graph();

    expect(graph.clinical.single.raisesUrgency, isTrue);
    expect(graph.preventive.single.raisesUrgency, isFalse);
    expect(graph.experimental.single.raisesUrgency, isFalse);
    expect(graph.dataQuality.single.raisesUrgency, isFalse);
    expect(graph.drivers.map((n) => n.label), ['Fast breathing']);
  });

  test('a well child with care gaps is not described as urgent', () {
    final graph = _graph(findings: const [_preventive]);

    expect(graph.isClinicallyUrgent, isFalse);
    expect(graph.isWellWithCareGaps, isTrue);
    expect(graph.preventive, hasLength(1));
  });

  test('urgency is the plan verdict, never recomputed here', () {
    expect(
      _graph(triage: TriageLevel.urgent, findings: const [_clinical]).urgency,
      TriageLevel.urgent,
    );
    expect(_graph().isClinicallyUrgent, isFalse);
  });

  test('measured value and cut-off survive the trip intact', () {
    final node = _graph().clinical.single;

    expect(node.measuredValue, '62/min');
    expect(node.threshold, '≥ 50/min');
    expect(node.statement, 'Fast breathing · 62/min (cut-off ≥ 50/min)');
    expect(node.protocolSource, 'IMCI child');
  });

  test('an action is linked to the finding it names, and stays verbatim', () {
    final graph = _graph(
      actions: const [
        RecommendedAction(
          instruction: 'Treat fast breathing with oral amoxicillin',
          urgency: ReferralUrgency.sameDay,
          isPrereferralTreatment: false,
        ),
        RecommendedAction(
          instruction: 'Book the next weighing',
          urgency: ReferralUrgency.scheduled,
        ),
      ],
    );

    expect(
      graph.actions.first.instruction,
      'Treat fast breathing with oral amoxicillin',
    );
    expect(graph.actions.first.evidenceIds, contains('clinical:Fast breathing'));
    expect(graph.actions.first.isTraceable, isTrue);
    expect(graph.actions.last.isTraceable, isFalse);
  });

  test('unknowns are reported verbatim and never invented', () {
    final graph = _graph(missing: const ['MUAC not measured']);

    expect(graph.unknowns, ['MUAC not measured']);
    expect(_graph().unknowns, isEmpty);
  });

  test('node ids resolve back to their labels for cross-referencing', () {
    final graph = _graph();

    expect(graph.idFor('Fast breathing'), 'clinical:Fast breathing');
    expect(graph.idFor('Not a finding'), isNull);
  });
}
