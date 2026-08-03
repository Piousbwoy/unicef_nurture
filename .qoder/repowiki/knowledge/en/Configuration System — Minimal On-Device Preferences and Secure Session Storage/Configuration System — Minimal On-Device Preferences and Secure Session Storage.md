---
kind: configuration_system
name: Configuration System — Minimal On-Device Preferences and Secure Session Storage
category: configuration_system
scope:
    - '**'
source_files:
    - lib/data/local/preferences_store.dart
    - lib/core/auth/session.dart
    - pubspec.yaml
    - android/app/build.gradle.kts
    - ios/Flutter/Debug.xcconfig
    - ios/Flutter/Release.xcconfig
    - ios/Runner/Info.plist
---

This Flutter monorepo does not use a centralized configuration framework, .env files, or feature-flag system. Instead, runtime configuration is split across three small, purpose-built mechanisms that reflect the app's offline-first, low-resource field context in Northern Ghana.

1. **On-device preferences (non-sensitive flags)**
   - Implemented in `lib/data/local/preferences_store.dart` as a tiny key=value file (`preferences.txt`) written to the app documents directory via `dart:io` + `path_provider`. No `shared_preferences` dependency is used to keep the install footprint small.
   - Keys are simple strings: `onboarding_seen` and `preferred_language`. The store reads/writes a flat map and silently ignores I/O errors since preference loss is not treated as data loss.
   - Used by the splash/router flow to decide whether to show onboarding again and which language to default to.

2. **Secure session storage (sensitive identifiers only)**
   - `lib/core/auth/session.dart` uses `flutter_secure_storage` to persist only the signed-in user id and last phone number under keys `carebridge.session.user_id` and `carebridge.session.last_phone`. PINs are never stored; they are hashed before any persistence.
   - Lock-out state (failed attempts, lock duration) is intentionally kept in-memory only so it does not survive reboots, per the threat model for shared handsets.
   - All secure-storage calls are wrapped in try/catch blocks that degrade gracefully when the keystore is unavailable (e.g., desktop test hosts), falling back to "not remembered" rather than crashing.

3. **Build-time / platform configuration**
   - `pubspec.yaml` declares the Dart SDK constraint (`^3.10.0`) and all runtime dependencies; there is no separate config manifest.
   - Android build config lives in `android/app/build.gradle.kts` (defaultConfig, signingConfig placeholder) and iOS config in `ios/Flutter/*.xcconfig` plus `ios/Runner/Info.plist`; these are standard Flutter-generated files, not application settings.
   - Environment variables such as `PACKAGE_CONFIG` are exported by Flutter's own `flutter_export_environment.sh` and are not consumed by application code.

4. **Design conventions observed**
   - Configuration is colocated with the subsystem that owns it (preferences → data layer, session → auth core); there is no global Config singleton.
   - Failures to read/write non-critical config are swallowed silently; failures to read critical config degrade to safe defaults rather than throwing.
   - No environment-specific branches (debug/prod) exist in Dart code; behavior differences come from persisted flags and device capabilities (secure storage availability, connectivity).
   - There is no secrets management beyond `flutter_secure_storage`, and no remote configuration endpoint is wired up — the app is designed to run fully offline.