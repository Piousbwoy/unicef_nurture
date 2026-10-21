import 'speech_answers.dart';

/// How strongly a transcript supports one answer, before any acoustic
/// confidence is folded in.
enum MatchStrength { exact, contained, partial, similar, none }

class SpeechMatch {
  const SpeechMatch({
    required this.answer,
    required this.strength,
    required this.score,
    required this.heard,
  });

  final String answer;
  final MatchStrength strength;

  /// 0..1. Multiply with the recogniser's own confidence; both must clear the
  /// policy bar, so a confident hearing of the wrong word still gets refused.
  final double score;
  final String heard;
}

/// Maps a free transcript onto the closed set. Deliberately dumb and total:
/// it never guesses across two candidates, and it never invents an answer that
/// is not in [set].
SpeechMatch? matchSpeech(String transcript, SpeechAnswerSet set) {
  final words = _tokenize(transcript);
  if (words.isEmpty) return null;

  SpeechMatch? best;
  var ambiguous = false;
  for (final candidate in set.answers) {
    for (final utterance in candidate.utterances) {
      final wanted = _tokenize(utterance);
      if (wanted.isEmpty) continue;
      final scored = _score(words, wanted);
      if (scored == null) continue;
      if (best == null || scored.$1 > best.score) {
        best = SpeechMatch(
          answer: candidate.answer,
          strength: scored.$2,
          score: scored.$1,
          heard: utterance,
        );
        ambiguous = false;
      } else if (scored.$1 == best.score && candidate.answer != best.answer) {
        // Two answers read equally well: refuse rather than coin-toss.
        ambiguous = true;
      }
    }
  }
  return ambiguous ? null : best;
}

(double, MatchStrength)? _score(List<String> words, List<String> wanted) {
  if (_equals(words, wanted)) return (1.0, MatchStrength.exact);
  if (_containsRun(words, wanted)) return (0.6, MatchStrength.contained);
  if (wanted.length == 1 && words.length == 1) {
    final distance = _editDistance(words.first, wanted.first);
    if (distance == 1 && wanted.first.length >= 3) {
      return (0.7, MatchStrength.similar);
    }
    if (distance == 2 && wanted.first.length >= 5) {
      return (0.35, MatchStrength.similar);
    }
    return null;
  }
  if (_isSubsequence(words, wanted)) return (0.4, MatchStrength.partial);
  return null;
}

bool _equals(List<String> a, List<String> b) =>
    a.length == b.length && a.asMap().entries.every((e) => e.value == b[e.key]);

bool _containsRun(List<String> words, List<String> wanted) {
  for (var i = 0; i + wanted.length <= words.length; i++) {
    if (_equals(words.sublist(i, i + wanted.length), wanted)) return true;
  }
  return false;
}

bool _isSubsequence(List<String> words, List<String> wanted) {
  var i = 0;
  for (final word in words) {
    if (i < wanted.length && word == wanted[i]) i++;
  }
  return i == wanted.length;
}

int _editDistance(String a, String b) {
  final rows = List.generate(
    a.length + 1,
    (_) => List<int>.generate(b.length + 1, (j) => j),
  );
  for (var i = 1; i <= a.length; i++) {
    rows[i][0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      rows[i][j] = [
        rows[i - 1][j] + 1,
        rows[i][j - 1] + 1,
        rows[i - 1][j - 1] + cost,
      ].reduce((x, y) => x < y ? x : y);
    }
  }
  return rows[a.length][b.length];
}

/// Lowercase, punctuation dropped, whitespace collapsed — and nothing else.
/// In particular `ɛ ɔ ŋ ɣ` survive: folding them away would make `Ee` and
/// `ɛɛ` the same word, which is precisely the confusion a listener must not have.
List<String> _tokenize(String text) => text
    .toLowerCase()
    .replaceAll(_apostrophes, "'")
    .replaceAll(RegExp(r"[^a-z0-9'\u0080-\uffff\s]"), '')
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .toList();

final _apostrophes = RegExp(r"[’‘`´]");
