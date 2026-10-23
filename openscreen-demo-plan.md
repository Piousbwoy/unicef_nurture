# OpenScreen demo plan — CareBridge AI

Handoff file for the `openscreen-demo` skill. Start a new session and say
*continue the OpenScreen demo*; read this and carry on from step 2 of the skill.

---

# CURRENT REQUEST — the verdict screen (23 Oct 2026)

Record a short launch demo of the FHW assessment result screen, specifically the
verdict card rebuilt on 22–23 Oct. One message:

> The verdict comes first, and the screen shows its working: the measurement, the
> cut-off it crossed, what would flip the answer, and what the record is missing.

## Stage

- **Prefer the web build route already proven below** (`flutter build web --release`
  served by `node demo/serve_static.js`, opened in a chrome `--app` window). It sidesteps
  the Windows desktop blocker entirely. Check the build notes in `demo/DEMO_SCRIPT.md`
  first — native ML imports (`tflite_flutter`, `onnxruntime`) are a known
  `flutter build web` failure, so confirm the web build actually completes before
  planning around it.
- If the web build is unusable, the alternative is the Windows build at roughly
  **420 x 860** so the capture reads as a phone. Layout is tested at 390px.
  Currently blocked — see prerequisite below.
- Only the app in the recorded window: no taskbar clock, no file paths, no user name.
- **Do not film the district / barrier-pattern view** — that screen has no seeded data
  behind it. Stay on the assessment flow.

## Storyboard — 5 beats, ~45 s, 16:9

| # | Action on screen | What appears | Callout (<= 6 words) |
|---|---|---|---|
| 1 | Open a saved child result | Red plate: `PNEUMONIA — urgent — refer now`, action first | **Verdict first.** |
| 2 | Pause on the borderline row | `Borderline by respiratory rate — 51 breaths/min against a cut-off of 50.` | **Shows the line it crossed.** |
| 3 | Pause on the re-count row | `Would a re-count change it: RR 50 would not cross this cut-off. RR 51 would.` | **Names what would flip it.** |
| 4 | Re-record with the weight deleted | `…weight not recorded…` inside the clinical sentence | **Missing data, admitted.** |
| 5 | Land on the measurement chip | `2 of 2 core measurements recorded · not diagnostic confidence` | **No fake confidence.** |

Beat 1 must start after the first 2.5 s so the wide opening is intentional.

## Clinical entry values that make each beat fire

Every feature above hangs off a child aged **2–59 months**; a newborn or maternal
record shows almost none of them.

- **Beats 1–3:** age 6 months, respiratory rate **51**, temp 37.6, name recorded,
  weight 7.2 kg. (51 is borderline because the <12-month IMCI cut-off is 50.)
- **Beat 4:** same child, weight field left blank.
- **Alternative second case:** age 14 months, RR **42** — the 12–59-month cut-off is 40,
  so the borderline numbers visibly differ.
- **Routine contrast:** age 24 months, RR 30, no danger signs → green plate,
  `Nothing found needs referral`, plus the published ordering rule.

## Verified today

- Whole Flutter suite green: **1363 passed, 9 skipped, 0 failed**.
- Verdict card renders at 390px and at 320px with 200% text.
- Fresh renders in `pitch/deck8/shots/result-ui-{urgent,routine,night,evidence}.png`.
- The read-aloud summary no longer says "Confidence: High confidence."; it now says
  "Basis: " plus the enum's own explanation, and the four `RecommendationConfidence`
  labels name evidence instead of a probability.
- **Windows desktop build currently fails:**
  `Building with plugins requires symlink support. Please enable Developer Mode`
  (`start ms-settings:developers`, user action only). No Android device or emulator is
  attached either — `flutter devices` shows Windows, Chrome, Edge.

## Say in the pitch, over this footage

> Judges asked for a confidence number. We show the measurement, the line it crossed,
> and what would have to change to change the answer. And where the record cannot
> support that sentence, the screen leaves it blank instead of inventing one.

Never call the 11/11 guideline conformance an accuracy figure, and never claim the app
is clinically validated or nurse-tested.

---

# SETUP IS DONE (recorded 22 Oct 2026, still true — re-verified 23 Oct)

OpenScreen **2.1.2** is installed per-machine at
`C:\Program Files\Openscreen\Openscreen.exe` (from
`Openscreen.Setup.2.1.2-x64.exe`, SHA512 verified against the release's
`latest.yml`). It serves MCP over stdio with `Openscreen.exe mcp`; the handshake
returns `serverInfo { name: "openscreen", version: "2.1.2" }` and the full tool
set (`listSources`, `startRecording`, `stopRecording`, `getFrames`,
`exportVideo`, `setPointerTrack`, `createProject`, and the document tools).

Re-verified 23 Oct: `Openscreen.exe help` lists `mcp`, `record`, `sources`, `export`,
`captions`, `pack`, `info`.

**One machine quirk, already worked around.** Qoder exports
`ELECTRON_RUN_AS_NODE=1` into every child process, and Electron keys off the
variable's *presence* — an empty value still breaks it. With the variable set, the
branded exe behaves like bare Node and dies with
`Cannot find module '...\mcp'`. The fix is
`C:\Users\Alhaji_stunner\AppData\Local\openscreen-mcp.cmd`:

```bat
@echo off
set ELECTRON_RUN_AS_NODE=
"C:\Program Files\Openscreen\Openscreen.exe" %*
```

That shim is registered in Qoder's MCP settings as the user-scoped server
**`openscreen`** (serverId `86d79b93-b5be-47e8-9a79-fbf94a9e49b1`, transport stdio,
status **ready**, no auth). Do not replace it with the raw exe path. If the tools
ever stop loading, re-test the shim by hand before touching anything else:

```
( printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"probe","version":"1"}}}'; sleep 5 ) | "$LOCALAPPDATA/openscreen-mcp.cmd" mcp
```

**Also true:** the Microsoft Store copy (`EtienneLescot.OpenScreen_2.1.2.0`) is
still installed and currently running. If `startRecording` complains, or the
recording bar belongs to the wrong window, quit the Store copy — ask the user
before killing anything — and let the Program Files copy be the only one.

**If the tools are still absent in a new session**, the server was added after this
session started: an agent loads its MCP servers only at session start. Say so in plain
words rather than substituting clicks on OpenScreen's window.

---

# EARLIER PLAN (not the current request) — automatic sync consent

The caregiver **Data & privacy** consent screen used to say information leaves the
device "only when you tap Sync". That is false — `SyncService.start()`
(`lib/data/sync/sync_service.dart:167`) arms `Timer.periodic(CareNotice.syncInterval)`
and pushes the instant connectivity returns, started unconditionally at
`lib/app/providers.dart:309`. The copy was rewritten to say so, in all three places
it was duplicated (`lib/domain/compliance.dart` `CareNotice.points`,
`lib/presentation/auth/setup_screen.dart`, `lib/presentation/auth/privacy_consent_screen.dart`),
the interval is now one constant shared by code and words, and
`CareNotice.currentVersion` bumped to `2026-10-v3`. Pinned by new tests in
`test/governance_test.dart` (group "the notice is true of the running system") and
`test/widgets/entry_flow_test.dart`.

**One message for the viewer:** the family's record moves the moment there is
signal — and the things the family keeps for itself never move at all.

## Storyboard — launch demo, 4 beats + 1 optional, ~35 s, 1080p, 16:9

| # | Time | On screen | Action | Callout (≤6 words) |
|---|------|-----------|--------|--------------------|
| 1 | 0–6 s | `Your data, your control` consent card, whole screen, held still | nothing — let the card read | **Sync is automatic** (title, `typewriter`) |
| 2 | 6–13 s | the point *Sent automatically when there is a signal* | zoom in on it | **No button to press** (`pop`, arrow figure at the cloud icon) |
| 3 | 13–20 s | the last sentence of that same point | zoom | **Your notes stay on this phone** |
| 4 | 20–28 s | `Agree & Create Account` → family dashboard | click it, pause 1 s after the dashboard paints | **Consent, then care** |
| 5 | optional, 28–35 s | sync status pill on the dashboard draining from "pending" to synced, with `server/` on :3000 logging the accepted batch | wait for the drop | **15 minutes at the latest** |

Beat 5 only if the sync server actually runs locally; if it does not, cut it rather
than fake it. The first 2.5 s stay wide by design, so beat 1 must be held, not clicked.

## Stage (step 3 of the skill)

- Web build: `flutter build web --release`, served by `node demo/serve_static.js`,
  which prints `serving <root> at http://localhost:<port>` — take the port from that
  line instead of assuming one (see `demo/DEMO_SCRIPT.md` build notes).
- One clean window: `chrome --app=http://localhost:<port> --window-size=1600,1000
  --user-data-dir=<temp>` — a fresh profile is what makes it a fresh install, so the
  route lands on onboarding → role choice → caregiver setup → the consent screen.
  Trim that approach in editing (`addTrims`); do not show it.
- Seed data, obviously invented, no real patient anywhere: caregiver **Amina Attah**,
  Tamale Central, community **Tamale**, child **Kwesi**, born 2025-04-11. Nothing
  from a real register, no tokens, no notifications on screen.

## Recording steps

## Guardrails for whoever picks this up

- Never drive OpenScreen's window with computer-use or a mouse tool.
- Nothing posts to X, and nothing attaches to a pull request, without an explicit
  yes from the owner in that moment. `gh` is absent here anyway.
- Do not commit the exported MP4, and do not commit `.agents/skills/openscreen-demo`
  — the installer dropped it inside this repo, where it is untracked.
- The export path must be absolute; resolve `demo/` against this working directory.
