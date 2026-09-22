import 'dart:js_interop';
import 'dart:typed_data';

import 'marian_contract.dart';
import 'marian_tokenizer.dart';
import 'translation_runner.dart';
import 'voice_web_bridge.dart';

TranslationRunner buildTranslationRunner() => _WebTranslationRunner();

class _WebTranslationRunner implements TranslationRunner {
  String? _language;
  String? _base;
  MarianTokenizer? _tokenizer;
  Future<void> _tail = Future.value();
  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  @override
  bool get available => VoiceWebBridge.available;
  @override
  bool hasModel(String language) => _language == language && _tokenizer != null;
  @override
  Future<void> init({
    required String language,
    required String assetBasePath,
  }) => _serial(() async {
    _language = null;
    _tokenizer = null;
    final base = 'assets/$assetBasePath';
    final cache = (await VoiceWebBridge.metadata(base))['cache'] as String;
    final tokenizer = MarianTokenizer(
      sourceModel: await VoiceWebBridge.read(base, 'source.spm', cache),
      targetModel: await VoiceWebBridge.read(base, 'target.spm', cache),
      vocabulary: await VoiceWebBridge.text(base, 'vocab.json', cache),
      fixtures: await VoiceWebBridge.text(
        base,
        'tokenizer_fixtures.json',
        cache,
      ),
    );
    final generation = MarianGeneration(
      await VoiceWebBridge.text(base, 'generation_config.json', cache),
      vocabularySize: tokenizer.vocabularySize,
    );
    if (generation.eos != tokenizer.eos || generation.pad != tokenizer.pad) {
      throw const FormatException('Tokenizer generation mismatch');
    }
    await VoiceWebBridge.call('load', {'kind': 'marian', 'base': base});
    if ((await VoiceWebBridge.metadata(base))['cache'] != cache) {
      throw StateError('Translation pack changed');
    }
    _tokenizer = tokenizer;
    _language = language;
    _base = base;
  });
  @override
  Future<String?> translate(
    String english, {
    required String language,
    String? langToken,
  }) => _serial(() async {
    if (!hasModel(language) ||
        (langToken?.isNotEmpty ?? false) ||
        english.length > 4000 ||
        english.trim().isEmpty) {
      return null;
    }
    try {
      final tokenizer = _tokenizer!;
      final ids = tokenizer.encode(english);
      if (ids.length > 512 || ids.contains(tokenizer.unknown)) return null;
      final result = await VoiceWebBridge.call('translate', {
        'kind': 'marian',
        'base': _base,
        'ids': Int32List.fromList(ids).toJS,
      });
      final tokens = (result as JSInt32Array).toDart;
      if (tokens.contains(tokenizer.unknown)) return null;
      final translated = tokenizer.decode(tokens).trim();
      return translated.isEmpty ||
              translated.toLowerCase() == english.trim().toLowerCase()
          ? null
          : translated;
    } catch (_) {
      return null;
    }
  });
  @override
  Future<void> dispose(String language) => _serial(() async {
    if (_language != language) return;
    _language = null;
    _tokenizer = null;
    _base = null;
    await VoiceWebBridge.call('release', {'kind': 'marian'});
  });
}
