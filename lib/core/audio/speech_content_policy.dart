/// Clinical call sites opt out of unreviewed translation explicitly.
/// Lexical checks supplement that metadata; they do not certify meaning.
enum SpeechContentPolicy { guidance, clinical }

abstract final class SpeechSafety {
  static final _protected = RegExp(
    r'\b(?:\d+(?:[.,]\d+)?\s*(?:mg|mcg|g|kg|ml|l|mmhg|cm|mm|bpm|%|°c)|'
    r'dose|dosage|tablet|capsule|inject|amoxicillin|paracetamol|oxytocin|'
    r'misoprostol|gentamicin|magnesium|antibiotic|ors|rutf|ifa|'
    r'\d{4}-\d{2}-\d{2}|ref(?:erral)?[- :#]+[a-z0-9-]+)\b',
    caseSensitive: false,
  );

  static bool requiresEnglish(String source, SpeechContentPolicy policy) =>
      policy == SpeechContentPolicy.clinical || _protected.hasMatch(source);

  /// Exact ordered token preservation detects some corruption, not accuracy.
  static bool preservesTokens(String source, String translated) {
    final tokens = RegExp(
      r'\d+(?:[.,:/-]\d+)*|\b(?:mg|mcg|kg|ml|mmHg|cm|mm|bpm|'
      r'REF-[a-zA-Z0-9-]+)\b',
      caseSensitive: false,
    );
    String fingerprint(String value) =>
        tokens.allMatches(value).map((m) => m.group(0)).join('|');
    return fingerprint(source) == fingerprint(translated);
  }
}
