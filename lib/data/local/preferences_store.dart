/// Tiny, cross-platform preference store.
///
/// Uses `shared_preferences` so the same code works on Android, iOS, web and
/// desktop — no `dart:io` paths to guard. What we store here is deliberately
/// trivial:
///
/// * has the user seen the onboarding slides? (so they aren't shown twice on
///   a device that has already been set up)
/// * which language do they want guidance in by default? (so the audio card
///   opens to the right language on next launch)
///
/// Everything that touches user data goes through a repository. This file is
/// deliberately outside that contract: preferences are not records, and
/// pretending they were would add an audit row for a UI choice.
library;

import 'package:shared_preferences/shared_preferences.dart';

abstract final class PreferencesStore {
  static const _kOnboardingSeen = 'onboarding_seen';
  static const _kPrivacyConsentSeen = 'privacy_consent_seen';
  static const _kLanguage = 'preferred_language';
  static const _kSyncApiUrl = 'sync_api_url';
  static const _kSyncApiToken = 'sync_api_token';
  static const _kReducedEffects = 'reduced_effects';
  static const _kNarrationEnabled = 'narration_enabled';

  static Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  /// Returns true if the onboarding slides have been completed on this device.
  static Future<bool> hasSeenOnboarding() async {
    final prefs = await _prefs();
    return prefs.getBool(_kOnboardingSeen) ?? false;
  }

  /// Marks the onboarding slides as seen, so they will not be shown again.
  static Future<void> markOnboardingSeen() async {
    final prefs = await _prefs();
    await prefs.setBool(_kOnboardingSeen, true);
  }

  /// Returns true if the privacy notice has been accepted.
  static Future<bool> hasSeenPrivacyConsent() async {
    final prefs = await _prefs();
    return prefs.getBool(_kPrivacyConsentSeen) ?? false;
  }

  /// Marks the privacy notice as accepted.
  static Future<void> markPrivacyConsentSeen() async {
    final prefs = await _prefs();
    await prefs.setBool(_kPrivacyConsentSeen, true);
  }

  /// Clears preference flags — used by the "Reset this device" action.
  static Future<void> reset() async {
    final prefs = await _prefs();
    await prefs.remove(_kOnboardingSeen);
    await prefs.remove(_kPrivacyConsentSeen);
    await prefs.remove(_kLanguage);
    // A reset hands the phone to a new user; the previous worker's sync
    // server and bearer token must not survive that handover.
    await prefs.remove(_kSyncApiUrl);
    await prefs.remove(_kSyncApiToken);
    await prefs.remove(_kReducedEffects);
    await prefs.remove(_kNarrationEnabled);
  }

  /// Whether the user has chosen the "Lite" visual mode — no backdrop blur
  /// and no motion. Defaults to off; the choice belongs to the phone, not
  /// the account, because it is about the handset's GPU.
  static Future<bool> reducedEffects() async {
    final prefs = await _prefs();
    return prefs.getBool(_kReducedEffects) ?? false;
  }

  static Future<void> setReducedEffects(bool value) async {
    final prefs = await _prefs();
    await prefs.setBool(_kReducedEffects, value);
  }

  static Future<String?> preferredLanguage() async {
    final prefs = await _prefs();
    return prefs.getString(_kLanguage);
  }

  static Future<void> setPreferredLanguage(String language) async {
    final prefs = await _prefs();
    await prefs.setString(_kLanguage, language);
  }

  /// Whether universal narration is enabled. When on, any screen that
  /// opts in via [NarrationSection] auto-reads its content, and every
  /// [SpeakableText] responds to long-press with speech. Defaults off
  /// so the app stays silent until the user asks for a voice.
  static Future<bool> narrationEnabled() async {
    final prefs = await _prefs();
    return prefs.getBool(_kNarrationEnabled) ?? false;
  }

  static Future<void> setNarrationEnabled(bool value) async {
    final prefs = await _prefs();
    await prefs.setBool(_kNarrationEnabled, value);
  }

  /// The base URL of the MariaDB sync server, e.g. `https://district.example.com`.
  /// Returns null if not explicitly configured.
  static Future<String?> syncApiUrl() async {
    final prefs = await _prefs();
    return prefs.getString(_kSyncApiUrl);
  }

  /// The effective sync URL, defaulting to `http://localhost:3000` for local
  /// development when no explicit URL is configured.
  static Future<String> effectiveSyncApiUrl() async {
    return await syncApiUrl() ?? 'http://localhost:3000';
  }

  static Future<void> setSyncApiUrl(String url) async {
    final prefs = await _prefs();
    await prefs.setString(_kSyncApiUrl, url);
  }

  /// Bearer token for authenticating with the sync server.
  static Future<String?> syncApiToken() async {
    final prefs = await _prefs();
    return prefs.getString(_kSyncApiToken);
  }

  static Future<void> setSyncApiToken(String token) async {
    final prefs = await _prefs();
    await prefs.setString(_kSyncApiToken, token);
  }

  /// Removes the configured sync server, returning the app to the offline
  /// demonstration transport ([LoopbackTransport]). Used by the "clear" action
  /// on the sync-settings screen.
  static Future<void> clearSync() async {
    final prefs = await _prefs();
    await prefs.remove(_kSyncApiUrl);
    await prefs.remove(_kSyncApiToken);
  }
}
