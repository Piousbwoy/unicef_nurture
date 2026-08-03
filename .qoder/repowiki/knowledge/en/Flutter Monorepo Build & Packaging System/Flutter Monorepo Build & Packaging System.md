---
kind: build_system
name: Flutter Monorepo Build & Packaging System
category: build_system
scope:
    - '**'
source_files:
    - pubspec.yaml
    - android/build.gradle.kts
    - android/app/build.gradle.kts
    - ios/Runner.xcodeproj/project.pbxproj
    - web/index.html
---

This repository is a Flutter monorepo that uses the standard Flutter toolchain as its primary build system, with native platform shells for Android and iOS. There are no custom Makefiles, Dockerfiles, CI pipelines, or release scripts present in the repository.

**Build system components:**
- **Dart/Flutter**: The core application is built via `pubspec.yaml` which declares dependencies, SDK constraints (`^3.10.0`), and asset bundling configuration. Versioning follows semantic versioning format `1.0.0+1` (versionCode + buildNumber).
- **Android**: Uses Gradle Kotlin DSL (`build.gradle.kts`) with the official Flutter Gradle plugin (`dev.flutter.flutter-gradle-plugin`). The app module configures Java/Kotlin 17, pulls compile/target SDK versions from Flutter's configuration, and delegates version management to Flutter through `flutter.versionCode` and `flutter.versionName`. A root-level `build.gradle.kts` centralizes repository sources and redirects all build output to a shared `../../build` directory.
- **iOS**: Standard Xcode project structure with generated Flutter configs (`Debug.xcconfig`, `Release.xcconfig`, `Generated.xcconfig`). The project.pbxproj references Flutter framework integration and Swift Package Manager for plugin dependencies.
- **Web**: Basic web support via `web/index.html` and `manifest.json`, with documentation referencing `--base-href` argument for `flutter build web`.

**Build conventions observed:**
- All build artifacts are centralized under a single `build/` directory at the repository root, configured in the Android root Gradle script to avoid scattered build outputs.
- Release builds currently use debug signing configuration (noted as TODO in `android/app/build.gradle.kts`), indicating production signing is not yet configured.
- No automated testing commands, linting pipelines, or continuous integration configuration files exist in the repository.
- Dependencies are managed exclusively through `pubspec.yaml` with no vendoring or lockfile customization beyond the standard `pubspec.lock`.

**Constraints:**
- Android requires Java/Kotlin 17 compilation target.
- Flutter SDK version is pinned to `^3.10.0`.
- The app ID `gh.carebridge.carebridge_ai` is hardcoded in both Android manifest and Gradle configuration.