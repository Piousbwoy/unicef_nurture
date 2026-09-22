import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_sentencepiece_tokenizer/dart_sentencepiece_tokenizer.dart';

/// SentencePiece indices and Marian vocabulary indices are different spaces.
/// Activation requires the Python fixtures for this exact tokenizer artifact.
class MarianTokenizer {
  MarianTokenizer({
    required Uint8List sourceModel,
    required Uint8List targetModel,
    required String vocabulary,
    required String fixtures,
  }) : _source = SentencePieceTokenizer.fromBytes(sourceModel),
       _target = SentencePieceTokenizer.fromBytes(targetModel) {
    final decoded = jsonDecode(vocabulary) as Map<String, dynamic>;
    for (final entry in decoded.entries) {
      if (entry.value is! int ||
          (entry.value as int) < 0 ||
          _pieces.containsKey(entry.value)) {
        throw const FormatException('Invalid Marian vocabulary');
      }
      _vocabulary[entry.key] = entry.value as int;
      _pieces[entry.value as int] = entry.key;
    }
    eos = _vocabulary['</s>']!;
    pad = _vocabulary['<pad>']!;
    unknown = _vocabulary['<unk>']!;
    verifyFixtures(fixtures);
  }
  final SentencePieceTokenizer _source;
  final SentencePieceTokenizer _target;
  final _vocabulary = <String, int>{};
  final _pieces = <int, String>{};
  late final int eos;
  late final int pad;
  late final int unknown;
  int get vocabularySize => _pieces.length;

  List<int> encode(String text) {
    final pieces = _source.tokenize(text);
    final ids = <int>[];
    var previousUnknown = false;
    final unknownPiece = _source.vocab.idToPiece(_source.vocab.unkId);
    for (final piece in pieces) {
      final isUnknown = piece == unknownPiece;
      // SentencePiece coalesces adjacent unknown characters into one piece.
      // Do not coalesce known SPM pieces absent from Marian's joint vocabulary.
      if (!isUnknown || !previousUnknown) {
        ids.add(_vocabulary[piece] ?? unknown);
      }
      previousUnknown = isUnknown;
    }
    return [...ids, eos];
  }

  String decode(List<int> ids) {
    final tokens = <String>[];
    for (final id in ids) {
      if (id == eos || id == pad || id == unknown) continue;
      final piece = _pieces[id];
      if (piece == null) throw const FormatException('Invalid generated token');
      tokens.add(piece);
    }
    // Marian has a joint vocabulary. Source-only pieces can be generated too;
    // SentencePiece DecodePieces preserves their text instead of remapping IDs.
    if (tokens.every(_target.vocab.contains)) {
      return _target.decode(
        _target.convertTokensToIds(tokens),
        skipSpecialTokens: false,
      );
    }
    if (tokens.any(
      (piece) => RegExp(r'^<0x[0-9A-Fa-f]{2}>$').hasMatch(piece),
    )) {
      throw const FormatException('Unsupported byte-piece decoding');
    }
    return tokens.join().replaceAll('▁', ' ').trim();
  }

  void verifyFixtures(String source) {
    final fixture = jsonDecode(source) as Map<String, dynamic>;
    if (fixture['contract'] != 'marian-sentencepiece-v1' ||
        fixture['special']['eos'] != eos ||
        fixture['special']['pad'] != pad ||
        fixture['special']['unk'] != unknown) {
      throw const FormatException('Incompatible Marian tokenizer contract');
    }
    final encoding = fixture['encode'] as List;
    final decoding = fixture['decode'] as List;
    if (encoding.isEmpty || decoding.isEmpty) {
      throw const FormatException('Missing tokenizer parity fixtures');
    }
    for (final item in encoding) {
      final actual = encode(item['text'] as String);
      final expected = List<int>.from(item['ids']);
      if (actual.length != expected.length ||
          List.generate(
            actual.length,
            (i) => actual[i] == expected[i],
          ).contains(false)) {
        throw const FormatException('SentencePiece encoding parity failed');
      }
    }
    for (final item in decoding) {
      if (decode(List<int>.from(item['ids'])) != item['decoded']) {
        throw const FormatException('SentencePiece decoding parity failed');
      }
    }
  }
}
