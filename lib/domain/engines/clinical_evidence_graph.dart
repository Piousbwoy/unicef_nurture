/// The evidence behind one assessment, classified by what it is allowed to do.
///
/// A [CarePlan] is a decision plus a flat list of findings. That list mixes
/// things that must never be mixed: a danger sign that changes urgency, a
/// missed vaccine that changes only the care a nurse owes, a model's
/// experimental number that changes nothing, and a measurement-quality flag
/// that changes only trust. Rendering them uniformly is what made a well child
/// read as a priority case.
///
/// This graph is the layer between the engines and the screen. It invents
/// nothing: every node is a finding the engines already produced, carrying the
/// same value, cut-off and citation. What it adds is the classification, so the
/// brief can say "this is why she is urgent" and "this is only prevention"
/// without a human sorting it by eye.
library;

import '../entities/visit.dart';
import '../enums.dart';
import 'recommendation_engine.dart';

/// What kind of obligation a piece of evidence creates.
enum EvidenceKind {
  /// IMCI clinical finding. May raise urgency.
  clinical,

  /// Prevention, not illness — an overdue or age-barred dose.
  preventive,

  /// The reading itself is suspect. Changes trust, not urgency.
  dataQuality,

  /// An experimental model's output. Never raises urgency.
  experimental,
}

class EvidenceNode {
  const EvidenceNode({
    required this.id,
    required this.kind,
    required this.label,
    required this.detail,
    required this.severity,
    this.measuredValue,
    this.threshold,
    this.protocolSource,
    this.raisesUrgency = false,
  });

  /// Stable across rebuilds of the same record, so a brief can reference a
  /// node without holding the object.
  final String id;
  final EvidenceKind kind;
  final String label;
  final String detail;
  final TriageLevel severity;
  final String? measuredValue;
  final String? threshold;
  final String? protocolSource;

  /// Whether this node is permitted to set the urgency of the visit. Only
  /// clinical findings are, and only when the engine says so.
  final bool raisesUrgency;

  /// "Fast breathing · 62/min (cut-off ≥ 50/min)" — the sentence a nurse can
  /// check against the chart.
  String get statement {
    if (measuredValue == null) return '$label — $detail';
    final cutoff = threshold == null ? '' : ' (cut-off $threshold)';
    return '$label · $measuredValue$cutoff';
  }
}

/// An action with the evidence that justified it.
class EvidenceAction {
  const EvidenceAction({
    required this.instruction,
    required this.urgency,
    this.rationale,
    this.protocolSource,
    this.isPrereferral = false,
    this.evidenceIds = const [],
  });

  final String instruction;
  final ReferralUrgency urgency;
  final String? rationale;
  final String? protocolSource;
  final bool isPrereferral;

  /// Nodes this action answers. Empty when the action is not traceable to a
  /// finding, which the brief must state rather than guess at.
  final List<String> evidenceIds;

  bool get isTraceable => evidenceIds.isNotEmpty;
}

class ClinicalEvidenceGraph {
  const ClinicalEvidenceGraph({
    required this.classification,
    required this.urgency,
    required this.needsReferral,
    required this.nodes,
    required this.actions,
    required this.unknowns,
  });

  final String classification;
  final TriageLevel urgency;
  final bool needsReferral;
  final List<EvidenceNode> nodes;
  final List<EvidenceAction> actions;

  /// What was not recorded, verbatim from the engines.
  final List<String> unknowns;

  List<EvidenceNode> get clinical => _ofKind(EvidenceKind.clinical);
  List<EvidenceNode> get preventive => _ofKind(EvidenceKind.preventive);
  List<EvidenceNode> get dataQuality => _ofKind(EvidenceKind.dataQuality);
  List<EvidenceNode> get experimental => _ofKind(EvidenceKind.experimental);

  /// The nodes that actually decided the urgency, worst first.
  List<EvidenceNode> get drivers {
    final raising = nodes.where((n) => n.raisesUrgency).toList()
      ..sort((a, b) => _rank(a.severity).compareTo(_rank(b.severity)));
    return raising;
  }

  /// True when the visit is urgent for a clinical reason. A plan whose only
  /// escalation came from prevention cannot be described this way, because
  /// prevention never sets [urgency] in the first place.
  bool get isClinicallyUrgent => urgency == TriageLevel.urgent;

  /// True when the child is clinically well but has work outstanding.
  bool get isWellWithCareGaps =>
      urgency == TriageLevel.routine && preventive.isNotEmpty;

  List<EvidenceNode> _ofKind(EvidenceKind kind) =>
      nodes.where((n) => n.kind == kind).toList(growable: false);

  static int _rank(TriageLevel level) => switch (level) {
    TriageLevel.urgent => 0,
    TriageLevel.priority => 1,
    TriageLevel.watch => 2,
    TriageLevel.routine => 3,
  };

  /// Builds the graph from the synthesized plan. No re-derivation of clinical
  /// meaning: severity, measured value, cut-off and citation pass through
  /// untouched, and urgency is the plan's own verdict.
  factory ClinicalEvidenceGraph.fromPlan(
    CarePlan plan, {
    required String classification,
    required bool needsReferral,
  }) {
    final nodes = <EvidenceNode>[
      for (final f in plan.findings)
        EvidenceNode(
          id: '${_kindOf(f).name}:${f.label}',
          kind: _kindOf(f),
          label: f.label,
          detail: f.detail,
          severity: f.severity,
          measuredValue: f.measuredValue,
          threshold: f.threshold,
          protocolSource: f.protocolSource,
          raisesUrgency: f.raisesTriage && _kindOf(f) == EvidenceKind.clinical,
        ),
    ];

    final actions = <EvidenceAction>[
      for (final a in plan.actions)
        EvidenceAction(
          instruction: a.instruction,
          urgency: a.urgency,
          rationale: a.rationale,
          protocolSource: a.protocolSource,
          isPrereferral: a.isPrereferralTreatment,
          evidenceIds: [
            for (final node in nodes)
              if (a.instruction.toLowerCase().contains(
                    node.label.toLowerCase(),
                  ))
                node.id,
          ],
        ),
    ];

    return ClinicalEvidenceGraph(
      classification: classification,
      urgency: plan.overallTriage,
      needsReferral: needsReferral,
      nodes: List.unmodifiable(nodes),
      actions: List.unmodifiable(actions),
      unknowns: List.unmodifiable(plan.missingData),
    );
  }

  /// Node id for a finding label, when one exists.
  String? idFor(String label) {
    for (final node in nodes) {
      if (node.label == label) return node.id;
    }
    return null;
  }

  static EvidenceKind _kindOf(ClinicalFinding f) {
    if (f.aiGenerated) return EvidenceKind.experimental;
    final source = f.protocolSource ?? '';
    if (source.contains('measurement-quality')) return EvidenceKind.dataQuality;
    if (!f.raisesTriage) return EvidenceKind.preventive;
    return EvidenceKind.clinical;
  }
}
