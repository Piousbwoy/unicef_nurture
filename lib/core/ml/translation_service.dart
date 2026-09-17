/// Lightweight offline translation engine for the CareBridge narration
/// pipeline. Bridges the reviewed SpeechBank entries with a domain-specific
/// phrase dictionary to translate dynamic text that the narration composes
/// at runtime.
///
/// This is a phrase-based MT system, not a neural model. It uses greedy
/// longest-match-first substitution from [TranslationDictionary] for text
/// that does not match any SpeechBank clip. Every output is marked as a
/// draft — the speech bank's reviewed entries always take priority.
///
/// The architecture is designed so a real ML backend (e.g. NLLB-200 via
/// TFLite) can be plugged in later by implementing [TranslationBackend].
/// Until then, the phrase dictionary provides honest, if limited, coverage
/// for the most common medical terms in Hausa, Twi, and Dagbani.
library;

import '../i18n/translation_dictionary.dart';

/// How a translation was produced — lets the UI show honest provenance.
enum TranslationSource {
  /// Exact match in the reviewed SpeechBank.
  speechBank,

  /// Composed from the phrase dictionary at runtime.
  phraseDictionary,

  /// No translation available; caller should show English.
  unavailable,
}

class TranslationResult {
  const TranslationResult({
    required this.text,
    required this.source,
    required this.language,
    this.coverage = 0.0,
  });

  final String text;
  final TranslationSource source;
  final String language;

  /// Fraction of input words that were translated (0.0–1.0). Low coverage
  /// means the output is mostly English with a few translated terms.
  final double coverage;

  bool get isDraft => source != TranslationSource.speechBank;
}

abstract interface class TranslationBackend {
  TranslationResult? translate(String english, String language);
}

/// Phrase-dictionary backend: greedy longest-match substitution.
class _PhraseDictionaryBackend implements TranslationBackend {
  @override
  TranslationResult? translate(String english, String language) {
    if (language == 'English') {
      return TranslationResult(
        text: english,
        source: TranslationSource.speechBank,
        language: 'English',
        coverage: 1.0,
      );
    }

    final input = english.trim();
    if (input.isEmpty) return null;

    final words = input.split(RegExp(r'\s+'));
    final translatedWords = <String>[];
    var translatedCount = 0;
    var i = 0;

    while (i < words.length) {
      String? bestMatch;
      TranslationEntry? bestEntry;

      // Greedy longest match from the current position.
      for (final entry in TranslationDictionary.byLength) {
        final entryWords = entry.english.split(RegExp(r'\s+'));
        if (i + entryWords.length > words.length) continue;

        var matches = true;
        for (var j = 0; j < entryWords.length; j++) {
          if (!_wordEquals(words[i + j], entryWords[j])) {
            matches = false;
            break;
          }
        }

        if (matches) {
          bestMatch = entry.textFor(language);
          bestEntry = entry;
          break; // byLength is sorted longest-first, so first match wins
        }
      }

      if (bestMatch != null && bestEntry != null) {
        translatedWords.add(bestMatch);
        translatedCount += bestEntry.english.split(RegExp(r'\s+')).length;
        i += bestEntry.english.split(RegExp(r'\s+')).length;
      } else {
        // Keep the English word as-is.
        translatedWords.add(words[i]);
        i++;
      }
    }

    final result = translatedWords.join(' ');
    final coverage = words.isEmpty ? 0.0 : translatedCount / words.length;

    // If coverage is too low, the translation is mostly English — not useful.
    if (coverage < 0.3) return null;

    return TranslationResult(
      text: result,
      source: TranslationSource.phraseDictionary,
      language: language,
      coverage: coverage,
    );
  }

  bool _wordEquals(String a, String b) {
    String normalize(String s) =>
        s.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').trim();
    return normalize(a) == normalize(b);
  }
}

/// Offline translation service. Singleton; caches results per (text, language).
class TranslationService {
  TranslationService._({
    TranslationBackend? backend,
  }) : _backend = backend ?? _PhraseDictionaryBackend();

  static TranslationService? _instance;

  static TranslationService get instance =>
      _instance ??= TranslationService._();

  /// Test-only: replace the singleton.
  static TranslationService debugCreate({
    TranslationBackend? backend,
  }) =>
      TranslationService._(backend: backend);

  final TranslationBackend _backend;
  final _cache = <String, TranslationResult>{};
  static const _maxCacheSize = 500;

  /// Translate [english] into [language]. Returns null if no translation
  /// is available (caller should show English).
  ///
  /// Checks the SpeechBank first for exact clip matches, then falls back
  /// to the phrase dictionary. Results are cached.
  TranslationResult? translate(String english, String language) {
    final lang = _canonicalize(language);
    if (lang == 'English') {
      return TranslationResult(
        text: english,
        source: TranslationSource.speechBank,
        language: 'English',
        coverage: 1.0,
      );
    }

    final cacheKey = '$english|$lang';
    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    final result = _backend.translate(english, lang);
    if (result != null) {
      _putCache(cacheKey, result);
    }
    return result;
  }

  /// Check if a translation is available without computing it.
  bool hasTranslation(String english, String language) {
    return translate(english, language) != null;
  }

  void _putCache(String key, TranslationResult result) {
    if (_cache.length >= _maxCacheSize) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = result;
  }

  String _canonicalize(String language) {
    final value = language.trim().toLowerCase().replaceAll('_', '-');
    if (value == 'english' || value == 'en' || value.startsWith('en-')) {
      return 'English';
    }
    return switch (value) {
      'tw' || 'twi' => 'Twi',
      'dag' || 'dagbani' => 'Dagbani',
      'ha' || 'hausa' => 'Hausa',
      _ => language,
    };
  }
}
