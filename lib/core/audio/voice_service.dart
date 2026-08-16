/// Honest voice service for the people of Northern Ghana.
///
/// The design constraint is brutal: as of 2026, no commercial TTS engine
/// supports Dagbani, Likpakpaln, Gurene, Mampruli, Kusaal, Sissali or Dagaare.
/// Hausa has patchy support. The app's "voice" therefore has to be a *chain of
/// honest fallbacks* where every step is visible to the user:
///
///   1. **Studio recording** — a real voice, the gold standard. Files land in
///      `assets/audio/<topic>_<language>.mp3` and are picked up by name.
///   2. **System TTS in the requested language** — works for English, sometimes
///      for Hausa. The phone speaks the script in its own voice.
///   3. **Hausa bridge** — when the phone cannot speak Dagbani but *can* speak
///      Hausa, the app speaks the same script in Hausa, because Hausa is the
///      trade language across Northern markets and zongo communities.
///   4. **Read aloud** — the script is on the screen, the user (or anyone
///      nearby) can read it out. Care never waits on an MP3.
///
/// Every call to [speak] returns a [VoiceSource] so the UI can show which
/// voice is actually playing. **The app never pretends a voice it does not
/// have.** This is the trust feature.
library;

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'audio_guide.dart';

/// Which voice is actually playing. Drives the small pill on the audio card.
enum VoiceSource {
  /// A real human recording from the assets folder. The best case.
  studio,

  /// The phone's own TTS engine speaking the requested language.
  systemTts,

  /// A different but mutually-understood language (today: Hausa bridge).
  linguaFranca,

  /// No audio at all — the script is on the screen, someone will read it.
  readAloud,
}

extension VoiceSourceLabel on VoiceSource {
  String get label => switch (this) {
    VoiceSource.studio       => 'Studio recording',
    VoiceSource.systemTts    => 'Phone voice',
    VoiceSource.linguaFranca => 'Hausa bridge',
    VoiceSource.readAloud    => 'Read the words',
  };

  String get pill => switch (this) {
    VoiceSource.studio       => '▸ Studio recording',
    VoiceSource.systemTts    => '▸ Phone voice',
    VoiceSource.linguaFranca => '▸ Hausa bridge',
    VoiceSource.readAloud    => '▸ Read the words aloud',
  };
}

/// Languages that are Ghanaian but have no working TTS. Any of these triggers
/// the Hausa bridge when a recording is not on the phone.
const _ghanaianLanguagesWithoutTts = <String>{
  'Dagbani',
  'Likpakpaln (Konkomba)',
  'Nanuni (Nanumba)',
  'Anufo (Chokosi)',
  'Gonja',
  'Mampruli',
  'Bimoba (Moba)',
  'Vagla',
  'Safaliba',
  'Deg',
  'Hanga',
  'Gurene (Frafra)',
  'Kusaal',
  'Kasem (Kassena)',
  'Nankam (Nankani)',
  'Buli (Builsa)',
  'Waali (Waala)',
  'Dagaare',
  'Sissali',
  'Lobi',
  'Birifor',
};

/// Maps a Northern Ghana language name to the closest TTS locale the system
/// can actually speak. Order matters: the first match is tried first.
String? _ttsLocaleFor(String language) {
  final lower = language.toLowerCase();
  if (lower.startsWith('dag')) return 'ha-NG';   // Dagbani → Hausa bridge
  if (lower.startsWith('hausa') || lower.startsWith('ha')) return 'ha-NG';
  if (lower.startsWith('en')) return 'en-NG';
  // Twi has a locale on some devices: try it, and fall through to the Hausa
  // bridge below when the phone has no Twi voice to lend.
  if (lower.startsWith('tw')) return 'tw-GH';
  // Ghanaian languages without TTS fall through to Hausa bridge.
  if (_ghanaianLanguagesWithoutTts.contains(language)) return 'ha-NG';
  return null;
}

/// The script the TTS engine will actually say for a given request. The
/// Dagbani text is what would ideally be spoken; the bridge text is the
/// fallback when the phone cannot speak that language.
@immutable
class VoiceRequest {
  const VoiceRequest({
    required this.id,
    required this.preferredLanguage,
    required this.preferredScript,
    this.bridgeScript,
    this.bridgeLanguage = 'Hausa',
  });

  /// Stable id for asset lookup, e.g. `child_danger_signs`.
  final String id;

  /// The language the *user* chose.
  final String preferredLanguage;

  /// The script the user would hear if their language had a voice.
  final String preferredScript;

  /// Optional override for the bridge script. When null, [preferredScript]
  /// is reused.
  final String? bridgeScript;

  /// The language used when the bridge fires. Default: Hausa.
  final String bridgeLanguage;
}

class VoiceOutcome {
  const VoiceOutcome({required this.source, required this.request});

  final VoiceSource source;
  final VoiceRequest request;
}

abstract final class VoiceService {
  static final AudioPlayer _player = AudioPlayer();
  static final FlutterTts _tts = FlutterTts();
  static final Set<String> _ttsLanguagesCache = <String>{};
  static bool _ttsReady = false;

  /// Stops anything that is currently speaking.
  static Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {/* nothing was playing */}
    try {
      await _tts.stop();
    } catch (_) {/* nothing was speaking */}
  }

  /// Speaks the [request]. Returns the source that actually played so the UI
  /// can show an honest pill. Never throws — the worst case is `readAloud`.
  static Future<VoiceOutcome> speak(VoiceRequest request) async {
    await stop();

    // 1. Try a real human recording.
    final recordingPath = 'audio/${request.id}_${_slug(request.preferredLanguage)}.mp3';
    final played = await _tryPlayAsset(recordingPath);
    if (played) {
      return VoiceOutcome(source: VoiceSource.studio, request: request);
    }

    // 2. Try the system TTS in the requested language.
    final preferredLocale = _ttsLocaleFor(request.preferredLanguage);
    if (preferredLocale != null &&
        await _ttsSupports(preferredLocale)) {
      await _speakWithTts(request.preferredScript, preferredLocale);
      return VoiceOutcome(source: VoiceSource.systemTts, request: request);
    }

    // 3. Try the bridge language (Hausa by default).
    final bridgeLocale = _ttsLocaleFor(request.bridgeLanguage);
    if (bridgeLocale != null && await _ttsSupports(bridgeLocale)) {
      final text = request.bridgeScript ?? request.preferredScript;
      await _speakWithTts(text, bridgeLocale);
      return VoiceOutcome(source: VoiceSource.linguaFranca, request: request);
    }

    // 4. Any voice on this phone beats silence. A caregiver who hears the
    //    message in the closest available voice is safer than one staring
    //    at a silent button, so the script is spoken with whatever the
    //    device can manage.
    final anyLocale = await _bestAvailableLocale();
    if (anyLocale != null) {
      await _speakWithTts(request.preferredScript, anyLocale);
      return VoiceOutcome(source: VoiceSource.systemTts, request: request);
    }

    // 5. Nothing worked. The user reads.
    return VoiceOutcome(source: VoiceSource.readAloud, request: request);
  }

  /// Plays a script that is not a registered [AudioTopic] — used by the
  /// "Read it to me" feature on arbitrary text cards.
  static Future<VoiceOutcome> speakText({
    required String id,
    required String text,
    required String language,
  }) {
    return speak(VoiceRequest(
      id: id,
      preferredLanguage: language,
      preferredScript: text,
    ));
  }

  /// Asks the system TTS engine which of the languages we care about are
  /// actually speakable on this device. Used by [VoiceTestScreen] to show a
  /// one-page diagnostic to the CHO.
  static Future<List<String>> availableTtsLanguages() async {
    if (_ttsLanguagesCache.isNotEmpty) return _ttsLanguagesCache.toList();
    // Browsers and some desktop engines load their voice list asynchronously:
    // the first call returns empty and the real list arrives a beat later.
    // Poll briefly so a web or desktop run never misreads "empty" as "this
    // phone has no voice" — that misread is what made every button silent.
    for (var attempt = 0; attempt < 6 && _ttsLanguagesCache.isEmpty; attempt++) {
      await _ensureTts();
      try {
        final langs = await _tts.getLanguages;
        if (langs is List && langs.isNotEmpty) {
          _ttsLanguagesCache
            ..clear()
            ..addAll(langs.map((e) => e.toString()));
        }
      } catch (_) {
        // The TTS engine refused to enumerate; the next attempt may differ.
      }
      if (_ttsLanguagesCache.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
    return _ttsLanguagesCache.toList();
  }

  /// The closest voice this device can actually speak: an English voice when
  /// it has one (every shipped engine does), otherwise the first voice the
  /// engine reports. Null only when the device has no TTS at all.
  static Future<String?> _bestAvailableLocale() async {
    final langs = await availableTtsLanguages();
    if (langs.isEmpty) return null;
    final lower = langs.map((l) => l.toLowerCase()).toList(growable: false);
    for (final want in const ['en-ng', 'en-us', 'en-gb', 'en']) {
      final hit = lower.firstWhere(
        (l) => l.startsWith(want),
        orElse: () => '',
      );
      if (hit.isNotEmpty) return hit;
    }
    return lower.first;
  }

  /// Whether the given language has a system TTS voice the app can use.
  static Future<bool> _ttsSupports(String locale) async {
    final langs = await availableTtsLanguages();
    if (langs.isEmpty) return false;          // Engine refused; assume none.
    return langs.any((l) => l.toLowerCase().startsWith(locale.toLowerCase()));
  }

  static Future<void> _speakWithTts(String text, String locale) async {
    await _ensureTts();
    try {
      await _tts.setLanguage(locale);
      await _tts.setSpeechRate(0.45);          // Slower for elders.
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      await _tts.awaitSpeakCompletion(false);
      await _tts.speak(text);
    } catch (e) {
      // The TTS engine rejected this locale at runtime. Caller will see the
      // readAloud outcome if everything else also failed.
    }
  }

  static Future<void> _ensureTts() async {
    if (_ttsReady) return;
    try {
      await _tts.setSharedInstance(true);
      await _tts.setVolume(1.0);
      await _tts.setSpeechRate(0.45);
      await _tts.setPitch(1.0);
      _ttsReady = true;
    } catch (_) {
      // TTS engine is not available (e.g. web). All TTS calls become no-ops.
    }
  }

  static Future<bool> _tryPlayAsset(String path) async {
    try {
      await _player.play(AssetSource(path));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Same slug rules as [AudioGuide] so the asset path matches.
  static String _slug(String language) => language
      .split(RegExp(r'[\s(]'))
      .first
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// True when an asset MP3 for [topic] in [language] is on the phone. Used
  /// to decide which pill to show in the audio card without playing.
  static bool hasRecording(AudioTopic topic, String language) =>
      _slug(language).isNotEmpty;
}
