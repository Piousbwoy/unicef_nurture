/// Model-specific frontend shared by native and browser Piper runners.
/// Twi uses the pinned GhanaNLP IPA rules, not raw orthographic characters.
/// Hausa uses the checkpoint's character inventory. Neither path may silently
/// discard an unknown symbol or omit the padding used during training.
library;

import 'dart:convert';

/// Tokenizes text into phoneme-ID sequences for Piper VITS inference.
class PiperPhonemizer {
  PiperPhonemizer._(this.phonemeIdMap, this.language, this._rules)
    : _orderedRules = _rules.keys.toList()
        ..sort((a, b) => b.length.compareTo(a.length));

  final Map<String, List<int>> phonemeIdMap;
  final String language;
  final Map<String, String> _rules;
  final List<String> _orderedRules;

  /// Load a phonemizer from a Piper `model.onnx.json` config string + language.
  factory PiperPhonemizer.fromConfig(
    String jsonConfig,
    String language, {
    String? twiRules,
  }) {
    final cfg = jsonDecode(jsonConfig) as Map<String, dynamic>;
    final rawMap = cfg['phoneme_id_map'];
    if (rawMap is! Map || !['Twi', 'Hausa'].contains(language)) {
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

  /// No unknown text is included in exceptions: diagnostics must not leak PHI.
  List<String> phonemes(String text) {
    final normalized = text.toLowerCase().trim();
    if (normalized.isEmpty) return [];
    if (language == 'Hausa') {
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
    final token = '«${languageToken ?? (language == 'Twi' ? 'twi' : 'ha')}»';
    if (phonemeIdMap.containsKey(token)) {
      ids.addAll([...phonemeIdMap[token]!, ...pad]);
    }
    for (final unit in units) {
      ids.addAll([...phonemeIdMap[unit]!, ...pad]);
    }
    return [...ids, ...phonemeIdMap[r'$']!];
  }

  List<int> encode(String text) => encodeUnits(phonemes(text));
}
