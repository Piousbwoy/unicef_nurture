/// Grapheme-to-token converter for Piper VITS models.
///
/// Both Hausa and Twi Piper models use `phoneme_type: "text"` — meaning the
/// model's phoneme inventory IS the raw text alphabet (Hausa) or text alphabet
/// + a few digraphs (Twi). No IPA conversion needed.
///
/// For Hausa: each character in the text maps 1:1 to a phoneme_id_map token.
/// For Twi: orthographic clusters (gb, kp, dz, ts, etc.) map to multi-char
///          tokens, and remaining characters map 1:1.
///
/// The encode() method produces a list of integer token IDs ready for VITS.
library;

import 'dart:convert';

/// Tokenizes text into phoneme-ID sequences for Piper VITS inference.
class PiperPhonemizer {
  PiperPhonemizer._({
    required this.phonemeIdMap,
    required this.language,
    required this.sortedTokens,
    required this.bosId,
    required this.eosId,
  });

  /// Raw map from phoneme token string → integer ID (from model.onnx.json).
  final Map<String, int> phonemeIdMap;
  final String language;

  /// Token strings sorted by length descending (greedy multi-char match).
  final List<String> sortedTokens;

  final int bosId;
  final int eosId;

  /// Load a phonemizer from a Piper `model.onnx.json` config string + language.
  factory PiperPhonemizer.fromConfig(String jsonConfig, String language) {
    final cfg = jsonDecode(jsonConfig) as Map<String, dynamic>;
    final rawMap = cfg['phoneme_id_map'] as Map<String, dynamic>?;

    final phonemeIdMap = <String, int>{};
    if (rawMap != null) {
      for (final entry in rawMap.entries) {
        final ids = entry.value;
        if (ids is List && ids.isNotEmpty) {
          phonemeIdMap[entry.key] = ids.first as int;
        }
      }
    }

    // Sort token strings by length descending for greedy matching.
    // Exclude special tokens (_, ^, $) from the matching pool.
    final tokens = phonemeIdMap.keys
        .where((k) => k.isNotEmpty && k != '_' && k != '^' && k != r'$')
        .toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    return PiperPhonemizer._(
      phonemeIdMap: phonemeIdMap,
      language: language,
      sortedTokens: tokens,
      bosId: phonemeIdMap['^'] ?? 1,
      eosId: phonemeIdMap[r'$'] ?? 2,
    );
  }

  /// Convert text to a sequence of phoneme token IDs for VITS input.
  /// Format: [^, tokens..., $] (begin-of-sentence + content + end-of-sentence).
  List<int> encode(String text) {
    final normalized = text.toLowerCase().trim();
    if (normalized.isEmpty) return [];

    final ids = <int>[bosId];

    if (language == 'Hausa') {
      // Hausa: pure 1:1 character mapping.
      for (final ch in normalized.split('')) {
        final id = phonemeIdMap[ch];
        if (id != null) ids.add(id);
        // Unknown chars silently dropped (graceful degradation).
      }
    } else {
      // Twi and others: greedy multi-character matching.
      var i = 0;
      while (i < normalized.length) {
        var matched = false;
        for (final token in sortedTokens) {
          if (normalized.startsWith(token, i)) {
            final id = phonemeIdMap[token];
            if (id != null) ids.add(id);
            i += token.length;
            matched = true;
            break;
          }
        }
        if (!matched) {
          // Skip unmapped character.
          i++;
        }
      }
    }

    ids.add(eosId);
    return ids;
  }
}
