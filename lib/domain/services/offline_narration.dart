import '../../core/i18n/speech_bank.dart';
import '../engines/recommendation_engine.dart';
import '../entities/caregiver.dart';
import '../entities/visit.dart';
import '../enums.dart';
import 'caregiver_check_policy.dart';

enum NarrationAudience { caregiver, healthWorker }

class NarrationLine {
  const NarrationLine(this.text, {this.clipId});
  factory NarrationLine.bank(BankScript script) =>
      NarrationLine(script.english, clipId: script.id);

  final String text;
  final String? clipId;
}

class OfflineNarration {
  OfflineNarration(Iterable<NarrationLine> lines)
    : lines = List.unmodifiable(lines.where((line) => line.text.trim().isNotEmpty));

  final List<NarrationLine> lines;
  String get english => lines.map((line) => line.text).join(' ');

  List<String>? get clipIds {
    if (lines.isEmpty || lines.any((line) => line.clipId == null)) return null;
    if (lines.any((line) => SpeechBank.byId(line.clipId!)?.english != line.text)) {
      return null;
    }
    return List.unmodifiable(lines.map((line) => line.clipId!));
  }
}

abstract final class OfflineNarrator {
  /// Selects from multiple phrasings using a stable hash. The same inputs
  /// always produce the same selection (deterministic per patient), but
  /// different patients get different wording.
  static String _pick(List<String> variants, String seed) {
    if (variants.length == 1) return variants.first;
    final hash = seed.hashCode.abs();
    return variants[hash % variants.length];
  }

  static String carePlan({
    required CarePlan plan,
    required String personName,
    required NarrationAudience audience,
    required TriageLevel effectiveTriage,
    required int? followUpInDays,
    String? overrideReason,
  }) {
    final worker = audience == NarrationAudience.healthWorker;
    final overridden = effectiveTriage != plan.overallTriage;
    final seed = '$personName|${plan.overallTriage.name}|${effectiveTriage.name}|'
        '${plan.dangerSigns.length}|${plan.actions.length}';

    final openings = worker
        ? [
            'Care plan for $personName.',
            'Here is the care plan for $personName.',
            'This is the care plan for $personName.',
          ]
        : [
            'Care plan for $personName.',
            'Your health worker has made a care plan for $personName.',
            'Here is what your health worker recorded for $personName.',
          ];

    final priorityPhrases = [
      'Current priority: ${effectiveTriage.label}.',
      'The priority level is ${effectiveTriage.label}.',
      'This case is classified as ${effectiveTriage.label}.',
    ];

    final parts = <String>[
      _pick(openings, seed),
      _pick(priorityPhrases, seed),
      if (overridden)
        _pick([
          'The health worker changed the assessment priority from ${plan.overallTriage.label}.',
          'The priority was adjusted from ${plan.overallTriage.label} by the health worker.',
          'The health worker updated the assessment from ${plan.overallTriage.label}.',
        ], seed),
      if (overridden && overrideReason != null && overrideReason.trim().isNotEmpty)
        'Reason for the change: ${_sentence(overrideReason)}',
      if (plan.dangerSigns.isNotEmpty)
        _pick([
          'Recorded danger signs: ${_sentence(plan.dangerSigns.toSet().join('; '))}',
          'The danger signs noted are: ${_sentence(plan.dangerSigns.toSet().join('; '))}',
          'Danger signs identified: ${_sentence(plan.dangerSigns.toSet().join('; '))}',
        ], seed),
    ];
    if (worker) {
      if (plan.classifications.isNotEmpty) {
        parts.add(_pick([
          'Assessment findings: ${_sentence(plan.classifications.toSet().join('; '))}',
          'The assessment found: ${_sentence(plan.classifications.toSet().join('; '))}',
          'Clinical findings: ${_sentence(plan.classifications.toSet().join('; '))}',
        ], seed));
      }
      if (!overridden && plan.triageRationale.isNotEmpty) {
        parts.add(_sentence(plan.triageRationale));
      }
      for (final finding in plan.topDrivers.where((finding) => !finding.aiGenerated)) {
        parts.add('${_sentence(finding.label)} ${_sentence(finding.detail)}');
      }
      for (final interaction in plan.interactions) {
        parts.add('${_sentence(interaction.label)} ${_sentence(interaction.detail)}');
      }
    }
    if (plan.actions.isNotEmpty) {
      parts.add(_pick([
        if (worker) ...[
          'The steps in this plan are:',
          'Here are the recommended steps:',
          'The care plan includes:',
        ] else ...[
          'Your health worker has recorded these steps:',
          'Here is what your health worker recommends:',
          'The health worker advises:',
        ],
      ], seed));
      parts.add(actions(plan.actions, audience: audience, seed: seed));
    }
    // An override must not replay the old template's reassurance or return date.
    if (!overridden && plan.caregiverMessage?.trim().isNotEmpty == true) {
      parts.add(_pick([
        'Recorded advice for the family: ${_sentence(plan.caregiverMessage!)}',
        'Advice for the family: ${_sentence(plan.caregiverMessage!)}',
        'The health worker advised: ${_sentence(plan.caregiverMessage!)}',
      ], seed));
    }
    if (plan.missingData.isNotEmpty) {
      parts.add(_pick([
        'This assessment is missing: ${_sentence(plan.missingData.toSet().join('; '))}',
        'Missing information: ${_sentence(plan.missingData.toSet().join('; '))}',
        'The assessment could not capture: ${_sentence(plan.missingData.toSet().join('; '))}',
      ], seed));
      parts.add(_pick([
        'Ask the health worker to check these details. Missing information is not a normal result.',
        'The health worker should verify these details. Incomplete data is unusual.',
        'These details need checking by the health worker. Missing data is not expected.',
      ], seed));
    }
    if (followUpInDays != null) {
      parts.add(_pick([
        if (followUpInDays == 0)
          'The recorded follow-up is today.'
        else
          'The recorded follow-up is in $followUpInDays ${followUpInDays == 1 ? 'day' : 'days'}.',
        if (followUpInDays == 0)
          'Follow-up is scheduled for today.'
        else
          'Follow-up is in $followUpInDays ${followUpInDays == 1 ? 'day' : 'days'}.',
        if (followUpInDays == 0)
          'The patient should return today for follow-up.'
        else
          'Return in $followUpInDays ${followUpInDays == 1 ? 'day' : 'days'} for follow-up.',
      ], seed));
      if (effectiveTriage == TriageLevel.urgent) {
        parts.add(_pick([
          'This follow-up does not replace the urgent referral now.',
          'The urgent referral takes priority over this follow-up.',
          'Do not wait for the follow-up — the referral is urgent.',
        ], seed));
      }
    }
    return parts.join(' ');
  }

  static String actions(
    List<RecommendedAction> actions, {
    required NarrationAudience audience,
    String seed = '',
  }) => [
    for (var i = 0; i < actions.length; i++)
      '${_pick(i == 0 ? ['First', 'Step one,'] : ['Step ${i + 1}', 'Next, step ${i + 1}'], '$seed|$i')}. '
      '${audience == NarrationAudience.caregiver && (actions[i].isTreatment || actions[i].isPrereferralTreatment) ? 'For the health worker to manage: ' : ''}'
      '${_sentence(actions[i].instruction)}'
      '${audience == NarrationAudience.healthWorker && actions[i].rationale?.trim().isNotEmpty == true ? ' Reason: ${_sentence(actions[i].rationale!)}' : ''}',
  ].join(' ');

  static OfflineNarration reportedSigns({
    required CaregiverQuestionSet questions,
    required Map<String, CaregiverAnswer> answers,
    required CaregiverCheckDecision decision,
  }) {
    final yes = questions.questions.where((q) => answers[q.key] == CaregiverAnswer.yes).toList();
    final unsure = questions.questions.where((q) => answers[q.key] == CaregiverAnswer.unsure).toList();
    final seed = '${decision.name}|${yes.length}|${unsure.length}';
    final lines = <NarrationLine>[
      if (decision == CaregiverCheckDecision.urgent)
        NarrationLine.bank(SpeechBank.levelUrgent),
      if (decision == CaregiverCheckDecision.contactToday)
        NarrationLine(_pick(const [
          'Contact a health worker today. Some answers are uncertain.',
          'Some answers are not clear. Speak to a health worker today.',
          'Because some answers are uncertain, contact a health worker today.',
        ], seed)),
      if (decision == CaregiverCheckDecision.incomplete || decision == CaregiverCheckDecision.unsupported)
        NarrationLine(_pick(const [
          'This check is not complete. Do not treat it as a reassuring result.',
          'The check did not finish. Do not assume everything is fine.',
          'This assessment is incomplete — it is not a reassuring result.',
        ], seed)),
      if (yes.isNotEmpty) NarrationLine.bank(SpeechBank.nurseIntro),
      for (final question in yes) _sign(questions, question),
      if (unsure.isNotEmpty) NarrationLine.bank(SpeechBank.nurseUnsure),
      for (final question in unsure) _sign(questions, question),
    ];
    if (decision == CaregiverCheckDecision.routine && yes.isEmpty && unsure.isEmpty) {
      lines.add(NarrationLine(_pick(const [
        'No danger signs were reported in this check. This does not rule out illness. '
            'Check again tomorrow, or contact a health worker if you are worried.',
        'No danger signs came up this time. That does not mean there is no illness. '
            'Check again tomorrow, or see a health worker if something feels wrong.',
        'This check did not find danger signs, but illness can still be present. '
            'Recheck tomorrow or contact a health worker if you have concerns.',
      ], seed)));
    }
    return OfflineNarration(lines);
  }

  static NarrationLine _sign(CaregiverQuestionSet set, CaregiverQuestion question) {
    final clip = SpeechBank.byId('q_${set.speechId(question)}');
    return clip == null ? NarrationLine(question.label) : NarrationLine.bank(clip);
  }

  static String homeGuidance({
    required String personName,
    required OfflineNarration observations,
    required List<String> steps,
    required String feedingAdvice,
    required String advice,
    String? onsetNote,
  }) {
    final name = _displayName(personName);
    final seed = '$personName|${steps.length}';
    final parts = <String>[
      _pick([
        'This home check is for $name.',
        'Home check for $name.',
        'Here is the home check for $name.',
      ], seed),
      observations.english,
      _pick(const [
        'These are reported observations, not a clinical examination.',
        'These observations are what the family reported, not findings from an examination.',
        'What follows is based on the family report, not a clinical exam.',
      ], seed),
      if (onsetNote?.trim().isNotEmpty == true) 'Your note: ${_sentence(onsetNote!)}',
      advice,
      if (steps.isNotEmpty)
        _pick(const [
          'What to do next:',
          'Steps to follow:',
          'Here is what to do:',
        ], seed),
      for (var i = 0; i < steps.length; i++)
        '${_pick(i == 0 ? ['First'] : ['Step ${i + 1}'], '$seed|$i')}. ${_sentence(steps[i])}',
      '${_pick(const [
        'Feeding and comfort',
        'Feeding and soothing',
        'Nutrition and comfort',
      ], seed)}: ${_sentence(feedingAdvice)}',
    ];
    return parts.where((part) => part.trim().isNotEmpty).join(' ');
  }

  static String _sentence(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || RegExp(r'[.!?:]$').hasMatch(trimmed)) return trimmed;
    return '$trimmed.';
  }

  /// Names arrive from the register in whatever case the health worker
  /// typed them — "cee" must read as "Cee" when the phone speaks to the
  /// family. Title-cases the first letter of every word without touching
  /// the rest (names like "Abdul-Rahman" keep their inner capitals).
  static String _displayName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return trimmed;
    return trimmed
        .split(RegExp(r'\s+'))
        .map(
          (word) => word.isEmpty
              ? word
              : '${word[0].toUpperCase()}${word.substring(1)}',
        )
        .join(' ');
  }
}
