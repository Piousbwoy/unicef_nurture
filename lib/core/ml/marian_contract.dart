import 'dart:convert';

/// Explicit bounded greedy generation contract, shared by native and WASM.
class MarianGeneration {
  MarianGeneration(String source, {required this.vocabularySize}) {
    final config = jsonDecode(source) as Map<String, dynamic>;
    int token(String name) {
      final value = config[name];
      if (value is! int || value < 0 || value >= vocabularySize) {
        throw const FormatException('Invalid Marian generation token');
      }
      return value;
    }

    start = token('decoder_start_token_id');
    eos = token('eos_token_id');
    pad = token('pad_token_id');
    final limit = config['max_length'];
    if (limit is! int ||
        limit < 2 ||
        limit > 512 ||
        config['num_beams'] != 1 ||
        config['do_sample'] != false ||
        (config['min_length'] ?? 0) != 0 ||
        (config['repetition_penalty'] ?? 1.0) != 1.0 ||
        (config['no_repeat_ngram_size'] ?? 0) != 0 ||
        config['forced_bos_token_id'] != null ||
        config['suppress_tokens'] != null ||
        config['begin_suppress_tokens'] != null) {
      throw const FormatException('Unsupported Marian generation policy');
    }
    maxLength = limit;
    for (final word in config['bad_words_ids'] as List? ?? const []) {
      if (word is! List ||
          word.length != 1 ||
          word.single is! int ||
          word.single < 0 ||
          word.single >= vocabularySize) {
        throw const FormatException('Unsupported Marian suppression rule');
      }
      suppressed.add(word.single as int);
    }
  }
  final int vocabularySize;
  late final int start;
  late final int eos;
  late final int pad;
  late final int maxLength;
  final suppressed = <int>{};

  int nextToken(List<num> scores) {
    if (scores.length != vocabularySize || scores.any((v) => !v.isFinite)) {
      throw const FormatException(
        'Decoder must return finite vocabulary logits',
      );
    }
    int? best;
    for (var i = 0; i < scores.length; i++) {
      if (suppressed.contains(i)) continue;
      if (best == null || scores[i] > scores[best]) best = i;
    }
    if (best == null) {
      throw const FormatException('No allowed generation tokens');
    }
    return best;
  }
}
