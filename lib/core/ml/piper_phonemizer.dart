/// Model-specific frontend shared by native and browser Piper runners.
/// Twi uses the pinned GhanaNLP IPA rules, not raw orthographic characters.
/// Hausa uses the checkpoint's character inventory. Neither path may silently
/// discard an unknown symbol or omit the padding used during training.
///
/// A third path serves ONNX models exported straight from Hugging Face VITS
/// checkpoints. Those were trained on a character tokenizer, so the pack ships
/// that tokenizer's vocabulary and sentence fixtures; the frontend reproduces
/// its blank pattern exactly and refuses to load unless it matches them.
library;

import 'dart:convert';

/// Tokenizes text into phoneme-ID sequences for Piper VITS inference.
class PiperPhonemizer {
  /// Whether [jsonConfig] describes a character-orthography frontend, in which
  /// case no IPA rules file is needed (or wanted).
  static bool usesCharacterFrontend(String jsonConfig) =>
      (jsonDecode(jsonConfig) as Map)['character_frontend'] is Map;

  PiperPhonemizer._(this.phonemeIdMap, this.language, this._rules)
    : _orderedRules = _rules.keys.toList()
        ..sort((a, b) => b.length.compareTo(a.length)),
      _characters = null,
      _padChar = null,
      _padId = 0,
      _spaceId = 0,
      _aliases = const {};

  PiperPhonemizer.characters(
    this.language,
    Map<String, int> characters,
    String padChar,
    int spaceId,
    int padId,
    Map<String, String> aliases,
  ) : _characters = characters,
      _padChar = padChar,
      _padId = padId,
      _spaceId = spaceId,
      _aliases = aliases,
      phonemeIdMap = const {},
      _rules = const {},
      _orderedRules = const [];

  final Map<String, List<int>> phonemeIdMap;
  final String language;
  final Map<String, String> _rules;
  final List<String> _orderedRules;
  final Map<String, int>? _characters;
  final String? _padChar;
  final int _padId;
  final int _spaceId;
  final Map<String, String> _aliases;

  /// The language tag a checkpoint was trained with, if it uses one.
  static const _languageTokens = {
    'Twi': 'twi',
    'Hausa': 'ha',
    'Dagbani': 'dag',
  };

  /// Separator and punctuation carry no meaning of their own, so a voice may
  /// drop them. Letters and digits may not: a dropped 'ɔ' mispronounces a
  /// word and a dropped '3' changes a dose.
  static final _droppable = RegExp(
    r'^[\p{P}\p{S}\p{M}\p{Zs}\p{Cc}]$',
    unicode: true,
  );

  /// Load a phonemizer from a Piper `model.onnx.json` config string + language.
  factory PiperPhonemizer.fromConfig(
    String jsonConfig,
    String language, {
    String? twiRules,
  }) {
    final cfg = jsonDecode(jsonConfig) as Map<String, dynamic>;
    final characterFrontend = cfg['character_frontend'];
    if (characterFrontend is Map) {
      return PiperPhonemizer._fromCharacterFrontend(
        cfg,
        characterFrontend,
        language,
      );
    }
    final rawMap = cfg['phoneme_id_map'];
    if (rawMap is! Map || !_languageTokens.containsKey(language)) {
      throw const FormatException('Unsupported voice frontend');
    }
    final map = <String, List<int>>{};
    for (final entry in rawMap.entries) {
      final value = entry.value;
      if (value is! List ||
          value.isEmpty ||
          value.any((v) => v is! int || v < 0)) {
        throw const FormatException('Invalid phoneme inventory');
      }
      map[entry.key as String] = List<int>.from(value);
    }
    for (final special in ['_', '^', r'$']) {
      if (!map.containsKey(special)) {
        throw const FormatException('Missing phoneme boundary token');
      }
    }
    Map<String, String> rules = const {};
    if (language == 'Twi') {
      if (twiRules == null) {
        throw const FormatException('Twi IPA rules are required');
      }
      final raw = (jsonDecode(twiRules) as Map<String, dynamic>)['graphemes'];
      rules = Map<String, String>.from(raw as Map);
      if (rules.isEmpty ||
          rules.keys.any((k) => k.isEmpty) ||
          rules.values.any((v) => !map.containsKey(v))) {
        throw const FormatException('Twi rules do not match this checkpoint');
      }
    }
    return PiperPhonemizer._(map, language, rules);
  }

  factory PiperPhonemizer._fromCharacterFrontend(
    Map<String, dynamic> cfg,
    Map<dynamic, dynamic> frontend,
    String language,
  ) {
    final pad = frontend['pad_id'];
    final rawVocab = frontend['vocabulary'];
    if (pad is! int || pad < 0 || rawVocab is! Map) {
      throw const FormatException('Invalid character frontend');
    }
    final characters = <String, int>{};
    for (final entry in rawVocab.entries) {
      final key = entry.key as String;
      final value = entry.value;
      if (key.runes.length != 1 || value is! int || value < 0) {
        throw const FormatException('Invalid character frontend');
      }
      characters[key] = value;
    }
    final space = characters[' '];
    final padChar = characters.entries
        .where((e) => e.value == pad)
        .map((e) => e.key)
        .firstOrNull;
    if (characters.isEmpty || space == null || padChar == null) {
      throw const FormatException('Character frontend has no word separator');
    }
    final aliases = <String, String>{};
    for (final entry in (frontend['aliases'] as Map? ?? const {}).entries) {
      if (entry.key is! String ||
          entry.value is! String ||
          (entry.key as String).runes.length != 1 ||
          (entry.value as String).isEmpty) {
        throw const FormatException('Invalid character alias');
      }
      aliases[entry.key as String] = entry.value as String;
    }
    final phonemizer = PiperPhonemizer.characters(
      language,
      characters,
      padChar,
      space,
      pad,
      aliases,
    );
    // The table is only trusted if it reproduces the training tokenizer on
    // whole sentences. A pack that fails here is rejected, never half-used.
    final fixtures = cfg['frontend_fixtures'];
    if (fixtures is! List || fixtures.isEmpty) {
      throw const FormatException('Character frontend has no fixtures');
    }
    for (final fixture in fixtures) {
      if (fixture is! Map ||
          fixture['text'] is! String ||
          fixture['ids'] is! List) {
        throw const FormatException('Invalid character frontend fixture');
      }
      final expected = (fixture['ids'] as List).cast<int>();
      if (!_sameIds(
        phonemizer.encodeCharacters(fixture['text'] as String),
        expected,
      )) {
        throw const FormatException(
          'Character frontend does not match its tokenizer',
        );
      }
    }
    return phonemizer;
  }

  /// No unknown text is included in exceptions: diagnostics must not leak PHI.
  List<String> phonemes(String text) {
    final normalized = text.toLowerCase().trim();
    if (normalized.isEmpty) return [];
    if (language != 'Twi') {
      // Orthographic packs (Hausa, and any trained text-phoneme voice): every
      // codepoint, including the word separator, is a symbol the model learned.
      final units = normalized
          .replaceAll(RegExp(r'\s+'), ' ')
          .runes
          .map(String.fromCharCode)
          .toList();
      _checkUnits(units);
      return units;
    }
    final units = <String>[];
    var offset = 0;
    while (offset < normalized.length) {
      String? matched;
      for (final rule in _orderedRules) {
        if (normalized.startsWith(rule, offset)) {
          matched = rule;
          break;
        }
      }
      if (matched != null) {
        units.add(_rules[matched]!);
        offset += matched.length;
        continue;
      }
      final symbol = String.fromCharCode(
        normalized.runes
            .skip(normalized.substring(0, offset).runes.length)
            .first,
      );
      offset += symbol.length;
      if (symbol.trim().isEmpty) continue;
      if (!phonemeIdMap.containsKey(symbol) ||
          ['_', '^', r'$'].contains(symbol)) {
        throw const FormatException(
          'Text contains an unsupported pronunciation symbol',
        );
      }
      units.add(symbol);
    }
    _checkUnits(units);
    return units;
  }

  void _checkUnits(List<String> units) {
    if (units.any(
      (u) =>
          !phonemeIdMap.containsKey(u) ||
          ['_', '^', r'$'].contains(u) ||
          u.startsWith('«'),
    )) {
      throw const FormatException('Unsupported phoneme');
    }
  }

  List<int> encodeUnits(List<String> units, {String? languageToken}) {
    if (units.isEmpty) return [];
    _checkUnits(units);
    final pad = phonemeIdMap['_']!;
    final ids = <int>[...phonemeIdMap['^']!, ...pad];
    final token = '«${languageToken ?? _languageTokens[language]}»';
    if (phonemeIdMap.containsKey(token)) {
      ids.addAll([...phonemeIdMap[token]!, ...pad]);
    }
    for (final unit in units) {
      ids.addAll([...phonemeIdMap[unit]!, ...pad]);
    }
    return [...ids, ...phonemeIdMap[r'$']!];
  }

  List<int> encode(String text) {
    if (_characters != null) return encodeCharacters(text);
    return encodeUnits(phonemes(text));
  }

  /// Reproduces the checkpoint's own character tokenizer: lowercase, apply the
  /// pack's glyph aliases, drop the separators and punctuation it never saw,
  /// trim its word separator at both ends, then lay out blanks as its padding
  /// does — a run of the blank *letter* (Twi 'a', Hausa 'd', Dagbani '|')
  /// shares the blanks around it, so m of them give m+2 blanks between words,
  /// m+1 at an edge and m when they are all there is.
  List<int> encodeCharacters(String text) {
    final characters = _characters;
    final padChar = _padChar;
    if (characters == null || padChar == null) {
      throw const FormatException('Character frontend unavailable');
    }
    final kept = <String>[];
    for (final rune in text.toLowerCase().runes) {
      final source = String.fromCharCode(rune);
      for (final symbol in (_aliases[source] ?? source).runes) {
        final glyph = String.fromCharCode(symbol);
        if (characters.containsKey(glyph)) {
          kept.add(glyph);
          continue;
        }
        if (_droppable.hasMatch(glyph)) continue;
        throw const FormatException(
          'Text contains a character this voice cannot say',
        );
      }
    }
    while (kept.isNotEmpty && characters[kept.first] == _spaceId) {
      kept.removeAt(0);
    }
    while (kept.isNotEmpty && characters[kept.last] == _spaceId) {
      kept.removeLast();
    }
    final out = <int>[];
    var index = 0;
    while (index < kept.length) {
      if (kept[index] == padChar) {
        var run = 0;
        while (index + run < kept.length && kept[index + run] == padChar) {
          run++;
        }
        final atStart = out.isEmpty;
        final atEnd = index + run == kept.length;
        out.addAll(
          List.filled(
            atStart && atEnd
                ? run
                : atStart || atEnd
                ? run + 1
                : run + 2,
            _padId,
          ),
        );
        index += run;
        continue;
      }
      if (out.isEmpty || out.last != _padId) out.add(_padId);
      out.add(characters[kept[index]]!);
      index++;
    }
    if (out.isNotEmpty && out.last != _padId) out.add(_padId);
    return out;
  }

  static bool _sameIds(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }
}
