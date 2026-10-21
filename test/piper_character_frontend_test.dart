import 'dart:convert';
import 'dart:io';

import 'package:carebridge_ai/core/ml/piper_contract.dart';
import 'package:carebridge_ai/core/ml/piper_phonemizer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Character-orthography VITS packs ship the per-character table measured from
/// their own training tokenizer, plus sentence fixtures. The frontend must
/// reproduce those ids exactly, or the pack is rejected before it can speak a
/// wrong word.
void main() {
  for (final pack in [
    ('Twi', 'twi_farmerline_model.onnx.json'),
    ('Twi', 'twi_mms_model.onnx.json'),
    ('Dagbani', 'dagbani_model.onnx.json'),
    ('Hausa', 'hausa_mms_model.onnx.json'),
    // Frontend generated from the licensed Dagbani corpus by
    // tool/track_b/build_frontend.py: our own training data must clear the
    // same gate a downloaded checkpoint does.
    ('Dagbani', 'dagbani_trained_pack.json'),
  ]) {
    final path = 'test/fixtures/voice/${pack.$2}';
    if (!File(path).existsSync()) continue;
    final config = File(path).readAsStringSync();
    final fixtures =
        (jsonDecode(config) as Map<String, dynamic>)['frontend_fixtures']
            as List;

    test(
      '${pack.$1} ${pack.$2} encodes exactly like its training tokenizer',
      () {
        final frontend = PiperPhonemizer.fromConfig(config, pack.$1);
        expect(fixtures, isNotEmpty);
        for (final fixture in fixtures) {
          final text = fixture['text'] as String;
          expect(
            frontend.encode(text),
            (fixture['ids'] as List).cast<int>(),
            reason: 'encoding drifted from the tokenizer for "$text"',
          );
        }
      },
    );

    test('${pack.$1} ${pack.$2} declares a scale-free tensor contract', () {
      final spec = PiperModelSpec.fromJson(config);
      expect(spec.hasScalesInput, isFalse);
      spec.validateInputs(['input', 'input_lengths']);
      expect(
        () => spec.validateInputs(['input', 'input_lengths', 'scales']),
        throwsFormatException,
      );
    });

    test('${pack.$1} ${pack.$2} refuses text it cannot say faithfully', () {
      final frontend = PiperPhonemizer.fromConfig(config, pack.$1);
      expect(frontend.encode(fixtures.first['text'] as String), isNotEmpty);
      // A letter the checkpoint never learned would be silently dropped, which
      // mispronounces a word, so it may not pass without an error.
      expect(() => frontend.encode('aǯa'), throwsFormatException);
    });

    test('${pack.$1} ${pack.$2} refuses a table that no longer matches', () {
      final decoded = jsonDecode(config) as Map<String, dynamic>;
      final fixtures = decoded['frontend_fixtures'] as List;
      final tampered = jsonEncode({
        ...decoded,
        'frontend_fixtures': [
          ...fixtures,
          {
            'text': 'a b',
            'ids': [0, 1, 0, 2, 0],
          },
        ],
      });
      expect(
        () => PiperPhonemizer.fromConfig(tampered, pack.$1),
        throwsFormatException,
      );
    });
  }

  test('a classic piper config still requires the scales tensor', () {
    const config = '''
{"audio":{"sample_rate":22050},"num_speakers":1,
 "phoneme_id_map":{"_":[0],"^":[1],"\$":[2],"a":[3]},
 "inference":{"noise_scale":0.667,"length_scale":1.0,"noise_w":0.8}}
''';
    final spec = PiperModelSpec.fromJson(config);
    expect(spec.hasScalesInput, isTrue);
    spec.validateInputs(['input', 'input_lengths', 'scales']);
    expect(
      () => spec.validateInputs(['input', 'input_lengths']),
      throwsFormatException,
    );
    expect(PiperPhonemizer.usesCharacterFrontend(config), isFalse);
  });
}
