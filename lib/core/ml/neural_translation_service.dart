/// Neural ONNX backend for the translation pipeline.
///
/// Wraps [TranslationRunner] as a [TranslationBackend] so it slots into the
/// existing [TranslationService] chain:
///   SpeechBank (exact) → NeuralModel (this) → PhraseDictionary (fallback)
///
/// On web, [TranslationRunner.available] is false — this backend always
/// returns null and the dictionary handles it.
library;

import 'translation_runner.dart';

/// Configuration for a single neural model (per language).
class NeuralModelConfig {
  const NeuralModelConfig({
    required this.language,
    required this.assetPath,
    required this.langToken,
  });
  final String language;
  final String assetPath;
  final String langToken;
}

/// All model configs the app ships.
/// Dagbani is intentionally absent — no open model exists.
/// Language tokens use the `>>xxx<<` Marian format.
/// Verify tokens match the specific model export (see tool/export script).
const neuralModelConfigs = <NeuralModelConfig>[
  NeuralModelConfig(
    language: 'Hausa',
    assetPath: 'assets/models/translation_hausa',
    langToken: '',  // Helsinki-NLP opus-mt-en-ha: monodirectional, no tag needed
  ),
  NeuralModelConfig(
    language: 'Twi',
    assetPath: 'assets/models/translation_twi',
    langToken: '',  // Helsinki-NLP opus-mt-en-tw: monodirectional, no tag needed
  ),
];

/// Orchestrates model loading, inference, and caching for neural translation.
///
/// Lifecycle:
///   1. App start → [initialize] loads available models from assets.
///   2. Narration generates text → [warmTranslation] kicks off async inference.
///   3. UI reads translated text → [getCached] returns it synchronously.
///   4. Signout / memory pressure → [dispose] frees native sessions.
class NeuralTranslationService {
  NeuralTranslationService._();
  static final instance = NeuralTranslationService._();

  /// Test-only factory.
  static NeuralTranslationService debugCreate({TranslationRunner? runner}) {
    final s = NeuralTranslationService._();
    s._runner = runner;
    return s;
  }

  TranslationRunner? _runner;
  TranslationRunner get runner => _runner ??= createTranslationRunner();

  final _loading = <String, Future<void>>{};
  bool isLoaded(String language) => runner.hasModel(language);

  Future<void> initializeLanguage(String language) {
    if (!runner.available || !supportsLanguage(language)) return Future.value();
    return _loading.putIfAbsent(language, () async {
      final config = neuralModelConfigs.firstWhere((c) => c.language == language);
      try {
        await runner.init(language: language, assetBasePath: config.assetPath);
      } catch (_) { /* Missing/corrupt models leave readable guidance. */ }
    });
  }

  bool _initialized = false;
  bool get initialized => _initialized;
  bool get isAvailable => runner.available;

  /// Cache of neural translations: "english|language" → result text.
  final _neuralCache = <String, String>{};
  static const _maxCacheSize = 300;

  /// In-flight translation futures (deduplication).
  final _inFlight = <String, Future<String?>>{};

  /// Load ONNX models from asset bundle. Call once on app initialization.
  /// Safe to call multiple times (idempotent). Silently skips languages
  /// whose model files are missing.
  Future<void> initialize() async {
    if (_initialized || !runner.available) return;
    for (final config in neuralModelConfigs) {
      await initializeLanguage(config.language);
    }
    _initialized = true;
  }

  /// Look up the language token for a canonical language name.
  String? tokenFor(String language) {
    for (final config in neuralModelConfigs) {
      if (config.language == language) return config.langToken;
    }
    return null;
  }

  /// Whether a neural model is loaded for [language].
  bool supportsLanguage(String language) {
    return tokenFor(language) != null;
  }

  /// Return a cached neural translation, or null.
  String? getCached(String english, String language) {
    final key = '$english|$language';
    return _neuralCache[key];
  }

  /// Kick off async neural translation. Populates [_neuralCache] on completion.
  /// Returns a future so callers can await it if they need the result
  /// immediately (e.g. for TTS that needs text before speaking).
  Future<String?> warmTranslation(String english, String language) async {
    if (!runner.available || !supportsLanguage(language)) return null;
    await initializeLanguage(language);
    if (!isLoaded(language)) return null;
    final token = tokenFor(language);
    // token can be empty string for monodirectional models — that's valid.

    final key = '$english|$language';

    // Already cached.
    if (_neuralCache.containsKey(key)) return _neuralCache[key];

    // Already in flight — deduplicate.
    if (_inFlight.containsKey(key)) return _inFlight[key];

    final future = runner.translate(english, language: language, langToken: token?.isNotEmpty == true ? token : null).then((result) {
      _inFlight.remove(key);
      if (result != null && result.isNotEmpty) {
        _putCache(key, result);
      }
      return result;
    }).catchError((_) {
      _inFlight.remove(key);
      return null;
    });

    _inFlight[key] = future;
    return future;
  }

  /// Translate synchronously if cached, otherwise returns null.
  /// Used by [TranslationService.translate()] in the sync path.
  String? translateSync(String english, String language) {
    return getCached(english, language);
  }

  void _putCache(String key, String value) {
    if (_neuralCache.length >= _maxCacheSize) {
      _neuralCache.remove(_neuralCache.keys.first);
    }
    _neuralCache[key] = value;
  }

  /// Release all native model sessions.
  Future<void> dispose() async {
    for (final config in neuralModelConfigs) {
      await runner.dispose(config.language);
    }
    _neuralCache.clear();
    _inFlight.clear();
    _loading.clear();
    _initialized = false;
  }

  /// Test-only: inject a translation directly into the cache.
  void debugCacheTranslation(String english, String language, String result) {
    _neuralCache['$english|$language'] = result;
  }
}
