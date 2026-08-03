---
kind: external_dependency
name: Connectivity Detection
slug: connectivity-plus
category: external_dependency
category_hints:
    - client_constraint
scope:
    - '**'
source_files:
    - pubspec.yaml
---

Detects device connectivity status to enable offline-first behavior: sync queue with pending/uploading/completed/failed states, offline badge on splash screen, and graceful degradation when no network is available.