/// The words a listener is allowed to hear, and nothing else.
///
/// Speech input is only offered where the answer is already a choice from a
/// known list, because that is the one setting in which a recogniser can be
/// honest: it may pick among candidates, and it may say "unclear". Open dictation
/// is a different surface (notes) and never uses this registry.
class SpeechAnswer {
  const SpeechAnswer({
    required this.answer,
    required this.utterances,
    required this.verified,
  });

  /// The app-side value, e.g. `yes`. Language-independent, so the same set can
  /// drive an English-labelled button row.
  final String answer;

  /// Every spoken form accepted for [answer], written in the app's orthography.
  /// A multi-word form is one entry: it must arrive as a sequence.
  final List<String> utterances;

  /// True only when a native speaker of this language has signed the forms off.
  /// Unverified sets still work — a confident hearsay only ever *proposes*, and
  /// the human tap is what records — but the voice check screen says so.
  final bool verified;
}

class SpeechAnswerSet {
  const SpeechAnswerSet({required this.language, required this.answers});
  final String language;
  final List<SpeechAnswer> answers;

  /// One unverified form is enough to make the whole set unverified: a yes/no
  /// pair signed off unevenly is a pair we cannot tell apart with authority.
  bool get isVerified => answers.every((a) => a.verified);

  static const _yesNo = [
    SpeechAnswer(answer: 'yes', utterances: ['Ee'], verified: false),
    SpeechAnswer(answer: 'no', utterances: ['Ayi'], verified: false),
    SpeechAnswer(answer: 'unsure', utterances: ['Mi bɛ mi'], verified: false),
  ];

  /// Twi forms are authored from the app's own Twi question style, not from a
  /// speaker: `Ɛyɛ` / `Aane` for yes, `Nni` for no, `Minnim` for not sure.
  /// They are marked unverified for exactly that reason and need the same
  /// sign-off as the Dagbani set before this can be trusted unsupervised.
  static const _twiYesNo = [
    SpeechAnswer(
      answer: 'yes',
      utterances: ['Ɛyɛ', 'Aane', 'Yes'],
      verified: false,
    ),
    SpeechAnswer(answer: 'no', utterances: ['Nni', 'Mmo'], verified: false),
    SpeechAnswer(
      answer: 'unsure',
      utterances: ['Minnim', 'Nnim'],
      verified: false,
    ),
  ];

  static SpeechAnswerSet? forLanguage(String language) => switch (language) {
    'Dagbani' => SpeechAnswerSet(language: language, answers: _yesNo),
    'Twi' => SpeechAnswerSet(language: language, answers: _twiYesNo),
    _ => null,
  };
}
