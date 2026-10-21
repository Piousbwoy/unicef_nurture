import 'dart:math' as math;
import 'dart:typed_data';

import 'asr_contract.dart';

/// One scored candidate of a closed set.
class CandidateScore {
  const CandidateScore({
    required this.id,
    required this.logLikelihood,
    required this.perFrame,
    required this.posterior,
  });

  final String id;

  /// Total CTC log-probability of the best alignment for this candidate.
  final double logLikelihood;

  /// `logLikelihood / frames`: the length-independent absolute measure, which is
  /// what makes refusal possible. A candidate can win the race between two
  /// answers and still be nonsense relative to silence, and that case must be
  /// refused rather than reported as the less bad of two wrong answers.
  final double perFrame;

  /// Softmax over the candidate set: 1.0 means "if it was one of these, it was
  /// this one". Says nothing about whether it was any of them.
  final double posterior;
}

/// Greedy best-path reading, used where the app accepts free text (notes).
class AsrReading {
  const AsrReading({required this.text, required this.meanFrameProbability});
  final String text;
  final double meanFrameProbability;
}

/// Connectionist temporal classification over the encoder's frame posteriors.
///
/// Two jobs, deliberately separated because they carry different risk:
/// [restricted] is the exact forward algorithm over a closed set and is the only
/// path allowed to touch a clinical answer; [greedy] transcribes and is only used
/// where a wrong word costs a re-typed note.
class CtcDecoder {
  const CtcDecoder(this.spec);
  final AsrModelSpec spec;

  /// [frames] is T x labels, each row a probability distribution.
  AsrReading greedy(List<Float32List> frames) {
    final tokens = <String>[];
    var total = 0.0;
    int? previous;
    for (final frame in frames) {
      var best = 0;
      for (var i = 1; i < frame.length; i++) {
        if (frame[i] > frame[best]) {
          best = i;
        }
      }
      total += frame[best];
      if (best != spec.blankIndex && best != previous) {
        tokens.add(spec.labels[best]);
      }
      previous = best;
    }
    return AsrReading(
      text: _join(tokens),
      meanFrameProbability: frames.isEmpty ? 0 : total / frames.length,
    );
  }

  /// Score every candidate in [candidates] (id -> the label sequences that answer
  /// may be spoken as).
  ///
  /// An answer is marginalised over its spoken forms with log-sum-exp, because a
  /// caregiver who says `Aane` and one who says `Ɛyɛ` both mean yes, and scoring
  /// only the first form lets a *different* answer win the audio outright. That
  /// is not a refusal, it is a wrong clinical proposal, which is the one thing
  /// this layer exists to avoid.
  ///
  /// Each sequence is matched against the lattice of explicit leading, interior
  /// and trailing blanks, so a repeated letter inside a word (`aa`) needs the
  /// blank between them and is scored as the two frames separated by silence
  /// that it actually has to be.
  List<CandidateScore> restricted(
    List<Float32List> frames,
    Map<String, List<List<int>>> candidates,
  ) {
    if (frames.isEmpty || candidates.isEmpty) return const [];
    final scores = <String, double>{
      for (final entry in candidates.entries)
        entry.key: _logSumExp([
          for (final sequence in entry.value) _forward(frames, sequence),
        ]),
    };
    final top = scores.values.reduce(math.max);
    final exponentials = {
      for (final entry in scores.entries)
        entry.key: entry.value == -double.infinity
            ? 0.0
            : math.exp(entry.value - top),
    };
    final sum = exponentials.values.fold<double>(0, (a, b) => a + b);
    return [
      for (final entry in scores.entries)
        CandidateScore(
          id: entry.key,
          logLikelihood: entry.value,
          perFrame: entry.value / frames.length,
          posterior: sum <= 0 ? 0 : exponentials[entry.key]! / sum,
        ),
    ]..sort((a, b) => b.logLikelihood.compareTo(a.logLikelihood));
  }

  /// Log-domain CTC forward pass for one fixed transcription, over blank-extended
  /// states `blank, l0, blank, l1, …, blank`.
  ///
  /// Two different labels may follow each other with no silence between them, so
  /// a label state can be entered from the label state before it. Two identical
  /// labels cannot: they need a real blank frame, which is why `Ee` is worth
  /// testing for. Leaving the skip out altogether is not a small error — it
  /// charges every letter boundary a blank frame, so a six-letter answer is
  /// systematically weaker than a three-letter one and the shorter word wins.
  double _forward(List<Float32List> frames, List<int> labels) {
    final states = labels.length * 2 + 1;
    var alpha = List<double>.filled(states, -double.infinity);
    alpha[0] = 0;
    for (final frame in frames) {
      final next = List<double>.filled(states, -double.infinity);
      for (var s = 0; s < states; s++) {
        final label = s ~/ 2;
        final symbol = s.isEven ? spec.blankIndex : labels[label];
        final emit = math.log(math.max(1e-12, frame[symbol]));
        var from = s == 0 ? -double.infinity : alpha[s - 1];
        // Odd states only, and only over a label that is not the one before it.
        if (s.isOdd && s >= 3 && labels[label] != labels[label - 1]) {
          from = _logAdd(from, alpha[s - 2]);
        }
        next[s] = emit + _logAdd(alpha[s], from);
      }
      alpha = next;
    }
    // A transcription ends either on its last label or on the blank after it.
    final beforeLast = states == 1 ? -double.infinity : alpha[states - 2];
    return _logAdd(alpha[states - 1], beforeLast);
  }

  /// Sum of probabilities given as logs, shifted by the maximum first: a raw
  /// `exp` of a log-likelihood underflows to zero on any real take, and a zero
  /// denominator turns "unsure" into a division by zero.
  static double _logSumExp(List<double> values) {
    final top = values.reduce(math.max);
    // Every form impossible (a doubled letter with no blank frame between the
    // two, say) is minus infinity, not a number: subtracting it from itself is
    // NaN, and one NaN silently poisons the ranking of every answer.
    if (top == -double.infinity) return -double.infinity;
    return top +
        math.log(
          values.fold<double>(
            0,
            (sum, value) => sum + math.exp(value - top),
          ),
        );
  }

  static double _logAdd(double a, double b) {
    if (a.isInfinite && a < 0) return b;
    if (b.isInfinite && b < 0) return a;
    final top = math.max(a, b);
    return top + math.log(1 + math.exp(-((a - b).abs())));
  }

  /// Word-piece labels start with `▁` to mark a word boundary; the app reads
  /// plain text, so the marker becomes a space and nothing else changes.
  static String _join(List<String> tokens) {
    final buffer = StringBuffer();
    for (final token in tokens) {
      if (token.startsWith('▁')) {
        if (buffer.isNotEmpty) buffer.write(' ');
        buffer.write(token.substring(1));
      } else if (token == '|') {
        // Both Ghanaian inventories in this app use `|` as the word boundary
        // the CTC model was trained to emit, not as a letter. Dropping it would
        // weld every word to its neighbour; printing it would put punctuation in
        // a caregiver's note.
        if (buffer.isNotEmpty && !buffer.toString().endsWith(' ')) {
          buffer.write(' ');
        }
      } else {
        buffer.write(token);
      }
    }
    // A boundary the model emitted at the very start or end of a take is not a
    // word with a space attached to it.
    return buffer.toString().trim();
  }
}
