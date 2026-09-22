import 'dart:convert';
import 'dart:io';

import 'package:carebridge_ai/core/ml/marian_tokenizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final language in ['hausa', 'twi']) {
    final base = 'assets/models/translation_$language';
    final source = File('$base/source.spm').readAsBytesSync();
    final target = File('$base/target.spm').readAsBytesSync();
    final vocab = File('$base/vocab.json').readAsStringSync();
    final fixtures = File('test/fixtures/translation/translation_$language.json').readAsStringSync();
    test('$language exact Python Marian token IDs and target decoding', () {
      final expected = jsonDecode(fixtures) as Map<String, dynamic>;
      final tokenizer = MarianTokenizer(sourceModel: source, targetModel: target,
          vocabulary: vocab, fixtures: fixtures);
      for (final sample in expected['encode']) {
        expect(tokenizer.encode(sample['text']), sample['ids'], reason: sample['text']);
      }
      for (final sample in expected['decode']) {
        expect(tokenizer.decode(List<int>.from(sample['ids'])), sample['decoded']);
      }
    });
    test('$language activation blocked by failed parity fixtures', () {
      final bad = jsonDecode(fixtures) as Map<String, dynamic>;
      bad['encode'][0]['ids'] = [42];
      expect(() => MarianTokenizer(sourceModel: source, targetModel: target,
          vocabulary: vocab, fixtures: jsonEncode(bad)), throwsFormatException);
    });
  }
}
