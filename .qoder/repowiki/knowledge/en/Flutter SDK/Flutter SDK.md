---
kind: external_dependency
name: Flutter SDK
slug: flutter
category: external_dependency
category_hints:
    - vendor_identity
scope:
    - '**'
source_files:
    - pubspec.yaml
    - android/app/build.gradle.kts
    - ios/Runner/Info.plist
---

Cross-platform mobile framework used to build the CareBridge AI app for Android and iOS. Declared as an SDK dependency in pubspec.yaml; Android and iOS platform directories are present with native entry points.