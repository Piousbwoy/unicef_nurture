/// Turns the evidence graph into the sentences a nurse actually reads.
///
/// Deterministic, like every other engine here: the same record always yields
/// the same brief, and every clause is traceable to a node. Nothing is
/// generated freely, so nothing can be invented — the wording is chosen from
/// the graph, not written about it.
library;

import '../enums.dart';
import 'clinical_evidence_graph.dart';
import 'clinical_impression_resolver.dart';

class BriefRecommendation {
  const BriefRecommendation({
    required this.instruction,
    required this.urgency,
    required this.why,
    required this.isTraceable,
    required this.isPrereferral,
  });

  /// Verbatim from the plan — the brief frames it, never rewrites it.
  final String instruction;
  final ReferralUrgency urgency;

  /// Why it is on the list, in one clause.
  final String why;
  final bool isTraceable;
  final bool isPrereferral;
}

class ClinicalBrief {
  const ClinicalBrief({
    required this.headline,
    required this.insight,
    required this.recommendations,
    required this.unknowns,
    required this.careGaps,
    required this.isUrgent,
    this.impression,
  });

  /// The ranked condition behind the urgency word, when a caller resolved one.
  /// Null keeps the brief exactly as it has always read, so wiring the
  /// resolver into one screen cannot silently reword another.
  final ClinicalImpression? impression;

  /// The clinical state in one line — what the nurse would say first.
  final String headline;

  /// Two or three sentences: what was found, what it means, what happens next.
  final String insight;

  final List<BriefRecommendation> recommendations;

  /// Missing observations, each with its consequence.
  final List<String> unknowns;

  /// Prevention outstanding. Never urgency.
  final List<String> careGaps;

  final bool isUrgent;
}

abstract final class ClinicalBriefEngine {
  /// Builds the brief. [subject] is the patient's first name when known.
  static ClinicalBrief build(
    ClinicalEvidenceGraph graph, {
    String? subject,
    int? followUpInDays,
    ClinicalImpression? impression,
  }) {
    final who = (subject == null || subject.trim().isEmpty)
        ? 'This child'
        : subject.trim();

    final drivers = graph.drivers.take(2).toList(growable: false);
    final driverText = drivers.isEmpty
        ? null
        : drivers.map((n) => n.statement).join('; ');
    final gaps = graph.preventive.length;
    final dueToday = graph.actions
        .where((a) => a.instruction.toLowerCase().startsWith('give today'))
        .length;

    final headline = switch (graph.urgency) {
      TriageLevel.urgent => 'Urgent — act before the family leaves',
      TriageLevel.priority => 'Needs treatment today',
      TriageLevel.watch => 'Review before the family leaves',
      TriageLevel.routine => graph.preventive.isNotEmpty
          ? 'Clinically well — prevention outstanding'
          : 'Clinically well — routine care',
    };

    final parts = <String>[];
    // The condition's *meaning* goes here, not its name: the name is rendered
    // as the line above by whoever shows the brief, and repeating it in the
    // paragraph is the double-speech this page was rebuilt to remove. Skipped
    // when the visit resolved to well, because the headline already says so.
    if (impression != null && impression.tier != ImpressionTier.well) {
      parts.add(impression.plainWords);
    }
    if (graph.isClinicallyUrgent) {
      parts.add(driverText == null
          ? '$who is urgent on protocol criteria.'
          : '$who is urgent: $driverText.');
    } else if (drivers.isNotEmpty) {
      parts.add('$who needs attention today: $driverText.');
    } else {
      // The headline already says the child is well; repeating it here made the
      // card say the same thing three times. This clause adds only what is new.
      parts.add('Nothing found needs referral.');
    }

    if (gaps > 0) {
      parts.add(
        dueToday > 0
            ? '$gaps ${gaps == 1 ? 'dose is' : 'doses are'} overdue and '
                  '$dueToday ${dueToday == 1 ? 'is' : 'are'} due today.'
            : '$gaps ${gaps == 1 ? 'dose is' : 'doses are'} overdue.',
      );
    }

    if (graph.unknowns.isNotEmpty) {
      parts.add('${graph.unknowns.length} observation'
          '${graph.unknowns.length == 1 ? '' : 's'} missing — see below.');
    }

    if (graph.needsReferral) {
      parts.add('A referral is issued.');
    } else if (followUpInDays != null && !graph.isClinicallyUrgent) {
      parts.add('Review in $followUpInDays '
          '${followUpInDays == 1 ? 'day' : 'days'}.');
    }

    final recommendations = <BriefRecommendation>[
      for (final action in graph.actions)
        BriefRecommendation(
          instruction: action.instruction,
          urgency: action.urgency,
          isPrereferral: action.isPrereferral,
          isTraceable: action.isTraceable,
          why: action.isTraceable
              ? _whyFrom(graph, action.evidenceIds)
              : action.rationale ?? 'Standing protocol for this visit.',
        ),
    ]..sort((a, b) {
      int rank(ReferralUrgency u) => switch (u) {
        ReferralUrgency.immediate => 0,
        ReferralUrgency.sameDay => 1,
        _ => 2,
      };
      final byUrgency = rank(a.urgency).compareTo(rank(b.urgency));
      if (byUrgency != 0) return byUrgency;
      return a.isPrereferral == b.isPrereferral ? 0 : (a.isPrereferral ? -1 : 1);
    });

    return ClinicalBrief(
      headline: headline,
      insight: parts.join(' '),
      recommendations: List.unmodifiable(recommendations),
      unknowns: List.unmodifiable([
        for (final u in graph.unknowns) '${u.toString().split(' — ').first}.',
      ]),
      careGaps: List.unmodifiable([for (final n in graph.preventive) n.label]),
      isUrgent: graph.isClinicallyUrgent,
      impression: impression,
    );
  }

  static String _whyFrom(ClinicalEvidenceGraph graph, List<String> ids) {
    final labels = [
      for (final id in ids)
        for (final node in graph.nodes)
          if (node.id == id) node.label,
    ];
    if (labels.isEmpty) return 'No single finding named.';
    // Label only: the measured value already appears once in the insight, and
    // repeating it on the action row is the duplication this page was built to
    // remove.
    return labels.join('; ');
  }
}
