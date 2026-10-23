/// Secondary model evidence for clinicians, separate from the care decision.
///
/// Eligible experimental neural output, or an explicit availability status.
/// Measured inputs, fixed training slots, and local replacement sensitivities
/// remain distinct. Neither variant claims a calibrated clinical probability.
///
/// The card explains and grades; the protocol verdict governs care. It
/// never issues treatment or referral instructions.
/// Part of the CareBridge Premium Design System.
library;

import 'package:flutter/material.dart';

import '../../../core/ml/clinical_reasoning_engine.dart';
import '../../../core/ml/offline_inference_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/premium_design_tokens.dart';

class AiInsightCard extends StatelessWidget {
  const AiInsightCard({
    super.key,
    required this.reasoning,
    this.onExplainTapped,
    this.pending = false,
    this.unavailableReason,
    this.animationDuration = PremiumDesignTokens.standardTransition,
  });

  final ClinicalReasoning reasoning;
  final bool pending;
  final String? unavailableReason;
  final VoidCallback? onExplainTapped;
  final Duration animationDuration;

  Widget _experimentalCard(
    BuildContext context,
    ExperimentalAssessment assessment,
  ) {
    final p = assessment.prediction;
    final palette = ClinicalPaletteScope.of(context);
    final observed = p.observedValues.length;
    final fixed = p.fixedFeatures.length;
    return _surface(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading(context),
          const SizedBox(height: Gap.sm),
          const Text('Neonatal sepsis · On-device research'),
          const SizedBox(height: Gap.md),
          const Text('Experimental model score'),
          Text(
            '${assessment.scoreIndex.toStringAsFixed(1)} / 100',
            style: TextStyle(
              fontFamily: 'Sora',
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: palette.ink,
            ),
          ),
          const Text('0–100 research index — not a clinical probability'),
          const SizedBox(height: Gap.sm),
          Text(
            fixed == 0
                ? '$observed observed · Fixed-input record unavailable'
                : '$observed/${observed + fixed} observed · $fixed fixed',
          ),
          const SizedBox(height: Gap.sm),
          Text(
            'Not clinically validated. Does not change treatment or referral.',
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: palette.inkMuted,
            ),
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: Gap.sm),
            title: Text(
              'Why this score',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: palette.primary,
              ),
            ),
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(assessment.sensitivitySummary),
                  const SizedBox(height: Gap.md),
                  for (final entry in p.observedValues.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Gap.sm),
                      child: Text(
                        '${ExperimentalAssessment.featureLabel(entry.key)}: '
                        '${entry.value} ${p.featureUnits[entry.key] ?? ''}',
                      ),
                    ),
                  if (p.sensitivityStatus == ModelSensitivityStatus.completed &&
                      assessment.sensitivities.any(
                        (s) => s.scorePointDelta != 0,
                      )) ...[
                    const SizedBox(height: Gap.sm),
                    const Text(
                      'Local model sensitivities',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const Text(
                      'One measured input replaced with its training mean; '
                      'not causal effects or treatment suggestions.',
                    ),
                    const SizedBox(height: Gap.sm),
                    for (final s in assessment.sensitivities.take(3))
                      Padding(
                        padding: const EdgeInsets.only(bottom: Gap.sm),
                        child: Text(
                          '${ExperimentalAssessment.featureLabel(s.featureKey)} · '
                          '${s.rawValue} ${s.unit}\n'
                          '${s.scorePointDelta >= 0 ? '+' : ''}${s.scorePointDelta.toStringAsFixed(2)} '
                          'score points against baseline ${s.baselineNormalized}',
                        ),
                      ),
                  ],
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Model provenance and limitations'),
                    children: [
                      Text(
                        'Version: ${p.modelVersion ?? 'Unavailable'}\n'
                        'Raw neural output: ${p.rawNeuralOutput}\n'
                        'Adjusted experimental output: ${p.researchOutput}\n'
                        'Postprocessing: ${p.postprocessing['formula'] ?? 'Not recorded'}\n'
                        'A = ${p.postprocessing['A']}; B = ${p.postprocessing['B']}\n'
                        'Unvalidated legacy-teacher transform; not validated for this neural artifact.\n'
                        'Current weight is an experimental proxy for admission weight; measurement timing is unverified.\n'
                        'Age support: 0–3 days.\n'
                        'Input policy: ${p.inputPolicyVersion}\n'
                        'Artifact SHA-256: ${p.artifactSha256}\n'
                        'Fixed normalized inputs: ${p.fixedFeatures.isEmpty ? 'Not recorded' : p.fixedFeatures.entries.map((e) => '${e.key}: ${e.value}').join('; ')}',
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _surface(BuildContext context, Widget child) {
    final p = ClinicalPaletteScope.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: p.surfaceSolid,
        borderRadius: BorderRadius.circular(Gap.radius),
        border: Border.all(color: p.line),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: DefaultTextStyle.merge(
          style: TextStyle(fontSize: 14, height: 1.5, color: p.ink),
          child: child,
        ),
      ),
    );
  }

  Widget _heading(BuildContext context) {
    final p = ClinicalPaletteScope.of(context);
    return Row(
      children: [
        Icon(Icons.memory_outlined, size: 20, color: p.inkMuted),
        const SizedBox(width: Gap.sm),
        Expanded(
          child: Text(
            'Experimental AI evidence',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: p.ink,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final experimental = reasoning.experimentalAssessment;
    if (experimental != null) return _experimentalCard(context, experimental);
    final p = ClinicalPaletteScope.of(context);
    return _surface(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading(context),
          const SizedBox(height: Gap.sm),
          Semantics(
            liveRegion: true,
            child: Text(
              pending
                  ? 'Model analysis pending — clinical guidance is ready.'
                  : unavailableReason ??
                        'No experimental output is available for this assessment.',
            ),
          ),
          const SizedBox(height: Gap.sm),
          Text(
            'Clinical rules determine the care plan. Experimental models do not change treatment or referral.',
            style: TextStyle(fontSize: 13, height: 1.5, color: p.inkMuted),
          ),
          if (onExplainTapped != null)
            TextButton(
              onPressed: onExplainTapped,
              child: const Text('Model details'),
            ),
        ],
      ),
    );
  }
}
