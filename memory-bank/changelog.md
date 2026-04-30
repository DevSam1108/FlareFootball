# Changelog

> **⚠️ CRITICAL: NEVER run `git commit`, `git push`, `git init`, or any git write commands. This project has NO git repository. It is local-only by explicit developer decision. This rule is ABSOLUTE and has been violated in the past — do NOT repeat.**

## Diagnostic Logging Infrastructure Overhaul (2026-04-30)

### Summary
Investment session focused on analysis tooling rather than behavior fixes. Three coordinated changes shipped: (1) every single-line `DIAG-*` print routed through a new `diagLog()` wrapper at [lib/utils/diag_log.dart](../lib/utils/diag_log.dart) that prepends `[HH:MM:SS.mmm]` per line; (2) all three multi-line boxed blocks (CALIBRATION DIAGNOSTICS, PIPELINE START, IMPACT DECISION) now carry timestamps as first inner line — PIPELINE START gets one transitively via embedded calibration block; (3) on-device per-session `.log` text file written via Zone interceptor in [lib/main.dart](../lib/main.dart) feeding new `DiagLogFile` singleton at [lib/services/diag_log_file.dart](../lib/services/diag_log_file.dart). Files named `diag_<YYYY-MM-DD>_<HH-MM-SS>.log`, lifecycle bound to detection-screen `initState`/`dispose`, 500 ms flush cadence. iOS `Info.plist` enabled `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` — Documents folder now visible in Finder (Mac, plugged in) and iOS Files app (on-device). Existing CSV `DiagnosticLogger` unplugged via single-line comment-out at [live_object_detection_screen.dart:834](../lib/screens/live_object_detection/live_object_detection_screen.dart:834); CSV-related code preserved as dead code per user's "let later refactor remove cleanly" stance. "Share Log CSV" button hides itself automatically (its `if (filePath != null)` guard fails). Field-verified end-to-end on iPhone 12.

### Code changes applied this session
- **New file: [lib/utils/diag_log.dart](../lib/utils/diag_log.dart)** — `diagLog(String msg)` wrapper. Prepends `[HH:MM:SS.mmm]` and calls `print()`. Single source of truth for the timestamp format used by all single-line diagnostic prints.
- **New file: [lib/services/diag_log_file.dart](../lib/services/diag_log_file.dart)** — `DiagLogFile` singleton with in-memory buffer + 500 ms flush timer + `start()`/`stop()`/`append()` API. Files named `diag_<YYYY-MM-DD>_<HH-MM-SS>.log` in `getApplicationDocumentsDirectory()`. `_active` flag set true synchronously inside `start()` so `append` accepts lines immediately while async file open completes; first periodic flush after sink is ready drains the early buffer. Force-flush on `stop()` only (no app-pause / no after-decision flushes — accepted ~500 ms hard-crash data-loss window).
- **[lib/main.dart](../lib/main.dart)** — `runApp()` wrapped in `runZonedGuarded()` with `ZoneSpecification.print` override forwarding to `parent.print()` (terminal) AND `DiagLogFile.instance.append(line)` (on-device file). Result: every `print()` in the app — DIAG-*, multi-line blocks, AUDIO-STUB, framework prints — gets captured in the file. True 1:1 replica of debug-mode terminal output.
- **[lib/screens/live_object_detection/live_object_detection_screen.dart](../lib/screens/live_object_detection/live_object_detection_screen.dart):**
  - Imported `DiagLogFile`. Added `DiagLogFile.instance.start()` in `initState` and `DiagLogFile.instance.stop()` in `dispose`.
  - Single-line comment-out: `// DiagnosticLogger.instance.start();` at line 834 with multi-line rationale comment. Master-switch unplug — every other `DiagnosticLogger.instance.*` call site becomes a natural no-op.
  - Renamed `AUDIO-DIAG` → `DIAG-AUDIO` (1 occurrence). Migrated 12 single-line DIAG-* prints to `diagLog()`.
  - Added `final ts = DateTime.now().toIso8601String().substring(11, 23);` at top of `_logCalibrationDiagnostics()` and inserted `print('│ timestamp=$ts');` as first inner line of the CALIBRATION DIAGNOSTICS block.
  - Removed PIPELINE START's `print('│ timestamp=${DateTime.now().toIso8601String()}');` line (now redundant given the calibration block's own timestamp).
- **[lib/services/audio_service.dart](../lib/services/audio_service.dart)** — renamed `AUDIO-DIAG` → `DIAG-AUDIO` (5 occurrences) and migrated all to `diagLog()`. Imported `diag_log.dart`.
- **[lib/services/ball_identifier.dart](../lib/services/ball_identifier.dart)** — migrated 7 `DIAG-BALLID` prints to `diagLog()`. Imported `diag_log.dart`.
- **[lib/services/bytetrack_tracker.dart](../lib/services/bytetrack_tracker.dart)** — migrated 1 `DIAG-MATCH` print to `diagLog()`. Imported `diag_log.dart`.
- **[lib/services/impact_detector.dart](../lib/services/impact_detector.dart)** — renamed `AUDIO-DIAG` → `DIAG-AUDIO` (1 comment reference). Migrated 3 `DIAG-IMPACT` prints to `diagLog()`. Imported `diag_log.dart`. Moved IMPACT DECISION block's header `($ts)` to first inner line: `print('┌─── IMPACT DECISION ───');` followed by `print('│ timestamp=$ts');`.
- **[ios/Runner/Info.plist](../ios/Runner/Info.plist)** — added `<key>UIFileSharingEnabled</key><true/>` and `<key>LSSupportsOpeningDocumentsInPlace</key><true/>` adjacent to existing `LSRequiresIPhoneOS`.

### Memory-bank updates this session
- `CLAUDE.md` — Key File Map gains two new entries (`lib/utils/diag_log.dart`, `lib/services/diag_log_file.dart`); "Pending Code-Health Work" gains a new section for `DiagnosticLogger` full removal candidate; Path B validation rule updated stale `AUDIO-DIAG` reference to `DIAG-AUDIO`.
- `memory-bank/decisionLog.md` — three new ADRs: ADR-088 (timestamp standardisation), ADR-089 (on-device `.log` file via Zone interceptor), ADR-090 (DiagnosticLogger unplugged as dead code).
- `memory-bank/activeContext.md` — comprehensive Session 2026-04-30 record covering the 14 design decisions made during the discussion-led implementation.
- `memory-bank/progress.md` — new Session 2026-04-30 section at top.

### Verification
- `flutter analyze` — 77 issues found, all info-level (avoid_print on intentional diagnostic prints + pre-existing test/style lints in `bytetrack_tracker.dart` and `test/`). **0 errors.** 1 pre-existing dead-code warning at `live_object_detection_screen.dart:1011` (the `if (false)` guard for ADR-087 multi-object nudge — unchanged from prior session).
- `flutter test` — **177/177 passing** (unchanged from prior session — the diagnostic infrastructure is invisible to existing tests).
- Field validation (iPhone 12, 2026-04-30):
  - File created on Start Detection → closed on back-out → re-created on next Start Detection. ✅
  - File visible on iPhone via Files app → On My iPhone → app folder. ✅
  - File transferable to Mac via Finder + USB. Opens cleanly in any text editor. ✅
  - All single-line `DIAG-*` lines prefixed with `[HH:MM:SS.mmm]`. ✅
  - Multi-line blocks each carry one `│ timestamp=...` line as first inner line. ✅
  - "Share Log CSV" button no longer renders in the detection screen UI. ✅

### Open after this session
- DiagnosticLogger full code removal — tracked in CLAUDE.md "Pending Code-Health Work" as a future focused refactor pass (delete the service file, remove all call sites, audit `share_plus` usage). Current state: dead but non-disruptive.
- Android verification of all 2026-04-30 logging changes pending. Specifically: Android's `getApplicationDocumentsDirectory()` may not be browsable from Android Files apps without MediaStore wiring — flag for the Android verification round.
- Carry-over bugs from session 2026-04-29 still open (ISSUE-035, ISSUE-036, ISSUE-037, ISSUE-038, audio kick-gate refractory acceptance) — designed but not applied. User prioritised analysis tooling first; behaviour fixes come next.

---

## Phantom-Decision Suppression + Multi-Object Nudge + Architectural Findings (2026-04-29)

### Summary
Long extended-analysis session. Started with diagnosing pure stationary-ball jitter producing phantom IMPACT DECISION blocks during idle. Applied **Piece A** (kickState idle-gate at `_makeDecision` in `impact_detector.dart`) — field-validated for the original idle-jitter scenario, then immediately found to eat real kicks in a race-condition edge case (ISSUE-035). User accepted Piece A as net win for the common case; widening deferred. Added **multi-object cleanup audio nudge** (ADR-087) when user observed a physical cone at the kick spot being dual-classed by YOLO; disabled via single-line `if (false)` guard later in the session after user suspected it of dropping kicks in field test. Two new field logs surfaced larger architectural findings: **ISSUE-037** (foot/non-ball locked as ball cascade — same root class as ISSUE-028 player head) and **ISSUE-038** (ImpactDetector trigger gap — only fires negatively, decisions land late and with wrong zone after bounce-back overwrites `_lastDirectZone`). Several open-issue table entries in `CLAUDE.md` formally closed against Phase 3 mitigations (bounce-back FP, player-head FP during waiting, ball-identifier false re-acquisition during idle, ISSUE-030 stuck-lock).

### Code changes applied this session
- **Piece A — `lib/services/impact_detector.dart`** (ADR-086):
  - Added `import 'package:tensorflow_demo/services/kick_detector.dart' show KickState;`
  - New member `_currentKickState` (defaults to `KickState.confirming` for backward-compat with existing tests).
  - New optional parameter `kickState` on `processFrame` — captured into `_currentKickState` at top of method.
  - Gate at top of `_makeDecision`: `if (_currentKickState == KickState.idle) { print('DIAG-IMPACT [PHANTOM SUPPRESSED] ...'); _reset(); return; }`
- **Piece A — `lib/screens/live_object_detection/live_object_detection_screen.dart`**:
  - `processFrame` call site (line ~1061) now passes `kickState: _kickDetector.state`.
- **Piece A — `test/impact_detector_test.dart`**:
  - Added `import` for `KickState`.
  - New test "phantom decision suppressed when kickState=idle" — drives the exact idle-jitter scenario from the field log; asserts phase resets to ready, no result emitted.
  - New test "decision still fires when kickState=confirming (gate is permissive)" — same shape with confirming; asserts decision fires normally.
- **Multi-object nudge — `lib/services/audio_service.dart`** (ADR-087):
  - Added `playMultipleObjects()` method, mirroring `playBallInPosition()` exactly; prints `AUDIO-DIAG: multiple_objects fired`.
- **Multi-object nudge — `lib/screens/live_object_detection/live_object_detection_screen.dart`**:
  - Added `_lastMultipleObjectsAudio` field next to `_lastBallInPositionAudio`.
  - Replaced lines 958–972 with a priority-gated combined audio block (priority 1: multi-object check; priority 2: byte-identical existing ball-in-position incl. ISSUE-036 buggy `else`).
  - Added timestamp resets at re-calibration (line ~437) and dispose (line ~1675).
- **Multi-object nudge — `assets/audio/multiple_objects.m4a`**:
  - Generated via `say -o multiple_objects.m4a --data-format=aac "Multiple objects detected. Keep only the soccer ball."` (~46 KB AAC-LC, matches existing `ball_in_position.m4a` format).
- **Multi-object nudge — DISABLED later same session**:
  - Single-line edit: priority-1 condition `if (_anchorFilterActive && _anchorRectNorm != null && detections.length > 1)` replaced with `if (false /* ... */)` and original condition preserved as inline comment.
  - Field, method, audio file, and reset lines all stay as harmless dead code. Else branch (byte-identical original ball-in-position) always runs.

### Memory-bank updates this session
- `CLAUDE.md` issue table — 4 stale rows updated to Phase 3-mitigated status (bounce-back FP, player-head FP during waiting, ball-identifier false re-acquisition, ISSUE-030 stuck-lock); 5 new rows added (ISSUE-035, ISSUE-036, ISSUE-037, ISSUE-038, audio kick-gate too narrow, ADR-087 disabled status).
- `memory-bank/issueLog.md` — ISSUE-021 (bounce-back FP) flipped to ✅ FIXED BY PHASE 3 with full code-trace explanation; ISSUE-030 (stuck-lock) flipped to 🟢 MITIGATED BY PHASE 3 + Path A; new entries ISSUE-035, ISSUE-036, ISSUE-037, ISSUE-038.
- `memory-bank/decisionLog.md` — new ADR-086 (Piece A — kickState idle gate) and ADR-087 (multi-object cleanup nudge added then disabled).
- `memory-bank/activeContext.md` — comprehensive scenario log (Scenarios 1–9) covering every analysis discussed this session, with evidence/analysis/proposed-fix/status for each. Updated Current Focus, What Is Partially Done, Immediate Next Steps.
- `memory-bank/progress.md` — new Session 2026-04-29 section at top with applied code, designed-not-applied fixes, investigations owed.

### Verification
- `flutter analyze` — 102 issues found, all info-level (avoid_print on intentional diagnostic prints + pre-existing prefer_const / unnecessary_import in tests). No errors, no warnings.
- `flutter test` — **177/177 passing** (was 175 before Piece A; +2 new gate tests added with ADR-086).
- Field validation:
  - Piece A original case (idle-jitter phantom) — ✅ FIELD-VALIDATED on iPhone 12; produces `DIAG-IMPACT [PHANTOM SUPPRESSED]` line replacing the entire IMPACT DECISION block + AUDIO-DIAG REJECTED line.
  - Piece A real-kick case — ❌ FIELD-FAILED (ISSUE-035) on a zone-6 kick; race condition between KickDetector internal transition + Phase 3 idle-edge recovery + Piece A's instantaneous-state gate.
  - Multi-object nudge — disabled before any field validation could complete; user testing pending.

### Open after this session
- ISSUE-035 (Piece A widening): designed, deferred per user decision.
- ISSUE-036 (audio cadence double-fire): designed, NOT applied.
- ISSUE-037 (foot-locked-as-ball): discussed, NOT applied.
- ISSUE-038 (ImpactDetector trigger gap): architectural finding, NOT applied.
- Audio kick-gate widening (accept refractory): one-line fix designed, NOT applied.
- KickDetector premature `confirming → idle` transition: investigation owed.
- Path A mechanism A field validation: still owed (separate from this session's work).
- Multi-object nudge re-enable decision: pending user field-test confirmation that kick-drops are unaffected.

---

## ImpactDetector Accuracy Fix — Path A (2026-04-27 → 2026-04-28)

### Summary
Two-day structured diagnosis-and-fix session for the long-standing "directZone stuck at zone 1 / decision fires too early" bug. The bug was the project's #1 blocker since 2026-04-22 (zone accuracy effectively unusable on lobbed kicks). Two days of log-driven analysis identified two distinct firing mechanisms producing the same wrong-zone symptom; minimal additive fix applied (Path A); deeper restructure (Path B) deliberately deferred and documented in `CLAUDE.md` for a future cleanup phase. One state-flip kick field-validated post-fix (ball trajectory 1→6→7, hit zone 7, app correctly announced zone 7 — pre-fix it was announcing zone 1). Velocity-drop scenario validation still owed.

### What was diagnosed
- **Mechanism A (velocity-drop trigger):** `velMagSq < 0.4 × peak` at line 271–277 of `impact_detector.dart` was firing in normal mid-flight, not at wall impact. Peak gets set in frames 2–3 (ball accelerating from rest); apparent screen velocity then naturally drops below 40% as the ball recedes from the camera (perspective foreshortening + Kalman smoothing). Trigger fires while `_lastDirectZone` is still 1 (the entry zone).
- **Mechanism B (state-flip → lost-frame trigger):** When ByteTrack's track flips to `lost` mid-flight (fast motion, Mahalanobis below threshold), screen passes `ballDetected=false` to ImpactDetector. `_onBallMissing` was incrementing only `_lostFrameCount`, never updating `_lastDirectZone`. Screen still computed `directZone` from the (Kalman-predicted) position every frame, but those updates never reached ImpactDetector. After 5 missed frames the lost-frame trigger fired with stale zone (1).
- **Audio sync proven not at fault:** `AUDIO-DIAG` timestamps showed audio fires within 2 ms of the `IMPACT DECISION` block on every kick. Whatever the speaker says is exactly what the detector decided.
- **Dead signals at decision time:** `_lastWallPredictedZone`, `_bestExtrapolation`, `_lastDepthVerifiedZone`, `_velocityHistory` are all computed every frame but never consulted by `_makeDecision()`. Depth-verified zone is structurally null (depth thresholds 0.7–1.3 don't match behind-kicker geometry; ball-at-wall depthRatio ≈ 0.3–0.45 in field data).

### Modified Files

**`lib/services/audio_service.dart`** — added `AUDIO-DIAG` print at the top of `playImpactResult()` for all three result branches (hit / miss / noResult). Each line includes HH:MM:SS.mmm timestamp from `DateTime.now()`. Allows pairing audio-fire moments against the IMPACT DECISION block to measure decision→audio lag.

**`lib/services/impact_detector.dart`** — five additive changes:
1. **Timestamp on `IMPACT DECISION` block** — appended `($ts)` to the existing `┌─── IMPACT DECISION ───` print line at the top of `_makeDecision()`. Enables direct pairing with `AUDIO-DIAG` timestamps.
2. **`DIAG-IMPACT [DETECTED]` per-frame trace** — new print inside the `case DetectionPhase.tracking:` branch of `_onBallDetected`, before the trigger check. Logs phase, trackFrames, directZone (with just-set `_lastDirectZone`), velMagSq, peakVelSq, velRatio. Fires every frame the detected branch runs.
3. **`DIAG-IMPACT [MISSING ]` per-frame trace** — new print inside `_onBallMissing` after the state updates. Logs phase, trackFrames (frozen), lostFrames/threshold, current `_lastDirectZone`, current `_lastBboxArea`. After Path A Change 1 + Option A extension, all printed values are kept fresh in this branch — the cosmetic "(NOT updated)" parentheticals from the initial draft were removed in the same session.
4. **Path A Change 1 + Option A extension — zone state in `_onBallMissing`:** added `directZone`, `rawPosition`, `bboxArea` parameters to `_onBallMissing`; `processFrame` passes all three through; inside `_onBallMissing`, each updates its corresponding `_last*` field with the same null-safety rule used by `_onBallDetected` (transient null does NOT overwrite last good value). User pushed back on initial "Option B / leave it stale" recommendation, correctly identifying that stale state restricts the design palette for future hit-detection iterations — Option A was applied to keep all decision-context variables fresh.
5. **Path A Change 2 — velocity-drop trigger disabled:** original block at lines 271–277 commented out with detailed inline rationale referencing field evidence (kicks 2 & 4 of 2026-04-27, both fired at trackFrames=5 with depthRatio≈0.45). Decisions now fire only via edge-exit (in `_makeDecision`), lost-frame trigger (in `_onBallMissing`, 5 missed frames), or `maxTrackingDuration` (3 s safety net). Original code preserved for reversibility.

**`lib/screens/live_object_detection/live_object_detection_screen.dart`** — one additive change:
- **`AUDIO-DIAG: impact REJECTED` print** on the reject branch of the result gate (the `else` of the `if (_kickDetector.isKickActive || ... confirming)` block). Logs when `_makeDecision()` produced a result but the kick gate suppressed it (e.g., decision fired during `kick=idle`). Closes the previously-opaque "decision fired but no audio" case in the log.

**`CLAUDE.md`** — new "Pending Code-Health Work" section ahead of "What Is Out of Scope". Documents Path A as the surgical fix and Path B as the deferred cleanup option (restructure of `_onBallDetected`/`_onBallMissing` two-branch split, OR at minimum delete the dead signals listed above). Coordinates with the existing "pending deletion" services (`wall_plane_predictor.dart`, `trajectory_extrapolator.dart`, `kalman_filter.dart`, `ball_tracker.dart`). Locks in the validation rule that any future `ImpactDetector` refactor must capture pre/post traces using the diagnostic harness shipped this session.

### Field Verification (iPhone 12)
**One state-flip kick captured post-fix (2026-04-28, 12:16:16):**
- Ball physically traversed zones 1 → 6 → 7, hit zone 7.
- Trace: F2–F4 [DETECTED] (`_lastDirectZone` updated 1) → F5–F8 [MISSING ] (`_lastDirectZone` updated 6 → 6 → 7 → 7 — null doesn't overwrite at F8) → F9 [MISSING ] lost-frame trigger fires.
- `IMPACT DECISION`: `lastDirectZone: 7`. `AUDIO-DIAG: impact result=hit zone=7 (12:16:16.725)`.
- **Same scenario pre-fix announced zone 1 every time.** Mechanism B confirmed fixed.

**Velocity-drop scenario validation: pending.** User attempted but captured an idle-ball-jitter trace (kick=idle throughout). The idle-ball log incidentally showed Change 2 is at least passively working (no decision fires under noise that pre-fix would have fired velocity-drop), but a real flat-kick log is still owed.

### Tests
- No new tests. Existing suite **175/175 passing**. The fix is small and isolated; targeted unit tests would require refactoring ImpactDetector for testability (which falls under Path B's deferred cleanup, not this fix).

### Verification
- `flutter analyze` — 0 errors, 0 warnings, 99 infos (up from 93 due to today's new diagnostic prints; all `avoid_print` on intentional `DIAG-*` and `AUDIO-DIAG` lines).
- `flutter test` — 175/175 passing.

### Documentation
- Added **ADR-083** (disable velocity-drop trigger; Path A Change 2).
- Added **ADR-084** (pass directZone/rawPosition/bboxArea to `_onBallMissing`; Path A Change 1 + Option A extension).
- Added **ADR-085** (defer Path B refactor; apply minimal Path A first; lock in validation rule for any future ImpactDetector refactor).
- Added **ISSUE-034** (ImpactDetector premature firing — two mechanisms diagnosed and fixed).
- Updated `CLAUDE.md` with Pending Code-Health Work section.

### Android (Realme 9 Pro+)
Verification pending for Path A. Specifically watch that the new `DIAG-IMPACT` prints fire at the same state transitions on Android as on iOS, and that the rotation-correction in `_toDetections` doesn't interact differently with the unchanged anchor filter.

---

## Anchor Rectangle Phase 5 — Audio Announcements (4 Commits, 2 Bug Fixes) (2026-04-23 → 2026-04-24)

### Summary
Phase 5 delivered the audio layer for the Anchor Rectangle feature: two prompts (State 2 tap-prompt already scaffolded in Phase 1; new "Ball in position" return-to-anchor announcement) wired to Samantha-TTS assets. Scope reduced from three prompts to two during design; the "Ball far, bring closer" nudge was deferred pending field evidence it's needed. Four atomic commits landed over two days; the last two close flow-gap bugs surfaced during iPhone 12 field testing. User also made two small tuning tweaks (5 s → 10 s cadence on "Ball in position"; phrase shortened from "Ball in position, you can kick the ball" to just "Ball in position") and the audio assets and docs were refreshed to match.

### Modified Files
- **`lib/services/audio_service.dart`**
  - `playTapPrompt()`: replaced the Phase 1 `print`-stub with a real `AssetSource('audio/tap_to_continue.m4a')` playback after the retained per-episode counter + timestamp `print`. Docstring updated to reflect wiring (was "will be replaced in Phase 5").
  - New method `playBallInPosition()`: plays `audio/ball_in_position.m4a`; includes a minimal `print('AUDIO-DIAG: ball_in_position fired ($ts)')` for log visibility (audio playback cannot be verified from screen recordings). Docstring updated on 2026-04-24 to reflect 10 s cadence and `isStatic` gate.
- **`lib/screens/live_object_detection/live_object_detection_screen.dart`**
  - New state field `DateTime? _lastBallInPositionAudio` adjacent to existing Phase 3 fields.
  - New inline trigger block inside the existing `onResult` `if (_pipelineLive)` branch (~20 lines including docstring). Fires `playBallInPosition()` when the locked ball is tracked, inside `_anchorRectNorm`, and `isStatic` (ADR-082) — with a 10 s re-fire cadence via timestamp elapsed check. No Timer.
  - Null-reset of `_lastBallInPositionAudio` added in `_startCalibration()` (Recal-1) and `dispose()` adjacent to existing Phase 3 resets.
  - `_awaitingReferenceCapture` block: added `final hadSelection = _selectedTrackId != null;` capture at top, plus a third mutually-exclusive `else if (hadSelection && _selectedTrackId == null && hasCandidates)` branch at the end of the existing timer-transition chain. Restores the 30 s / 10 s nudge when a tap selection is silently cleared by the aliveness check (ADR-081 / ISSUE-032).

### New Files
- **`assets/audio/tap_to_continue.m4a`** — Samantha TTS, rate 170, ~1.4 s, 20 KB. No crowd-cheer layer (instructional prompt, not celebratory).
- **`assets/audio/ball_in_position.m4a`** — Samantha TTS, rate 170. Initial version "Ball in position, you can kick the ball" (~2.3 s); replaced 2026-04-24 with shortened "Ball in position" (~1 s, 15 KB) per user request.

### Documentation
- Added **ADR-079** (Phase 5 scope reduction + asset wiring policy + retained diagnostic print).
- Added **ADR-080** (timestamp-in-loop cadence pattern — no dedicated Timers).
- Added **ADR-081** (State 3→2 audio nudge restart on aliveness-cleared selection).
- Added **ADR-082** (`isStatic` gate on "Ball in position" audio).
- Added user-memory entry `feedback_reuse_existing_first.md` codifying "prefer existing loops/state over new Timers/helpers".
- Added **ISSUE-032** (silent State 3→2 — tap-prompt audio stuck cancelled after tap+flicker).
- Added **ISSUE-033** ("Ball in position" fires on a ball rolling through the rect without stopping).

### Field Verification (iPhone 12)
- **2026-04-23 session:** Commits 1 and 2 on-device verified. Log analysis captured 4 `AUDIO-DIAG: ball_in_position fired` events across ~20 s of gameplay at expected edges (lock, cadence on steady ball, return-to-anchor after each kick). Cadence measured at 5.021 s between first two fires (before the 10 s tuning), within one frame of spec. Target-circle FPs at (0.492, 0.452) continued to be dropped silently by the Phase 3 spatial filter throughout.
- **2026-04-24 session:** Commits 3 and 4 implemented after two bugs surfaced in the same field test. Both commits field-verified on-device the same day. Commit 3: flicker-triggered aliveness clear, audio nudge resumed on 30 s / 10 s cadence until re-tap. Commit 4: rolling-ball-through-rect scenario produced no audio (correct — ball never `isStatic`); genuinely-settled ball produced audio after ~1 s warm-up (correct).

### Tests
- No new tests. Existing suite **175/175 passing** (unchanged across all four commits). Phase 5 trigger logic lives inline in `onResult`; adding tests for it would require refactoring the screen for testability, which violates `feedback_no_refactor_bundling.md`.

### Verification
- `flutter analyze` — 0 errors, 0 warnings, 93 infos (all pre-existing or intentional `avoid_print` on diagnostic prints).
- `flutter test` — 175/175 passing.

### Android (Realme 9 Pro+)
Verification pending for all four commits.

---

## Anchor Rectangle Phase 3 Polish — False-Alarm Recovery + Resting-Ball Trail Dot + Enriched Log (2026-04-22, follow-up)

### Summary
Three small additive refinements to the Phase 3 anchor filter after the main implementation landed earlier the same day. All edits confined to `lib/screens/live_object_detection/live_object_detection_screen.dart`. Zero refactors of working code, zero new files, zero new tests. Motivated by an evening session where the user ran consecutive-hit field tests, spotted that (a) a false-alarm kick flicker could lock the filter OFF for 2 s, (b) the "resting-ball orange dot" from pre-2026-04-15 builds was missing, and (c) the `DIAG-ANCHOR-FILTER` log couldn't explain `passed=0 while ball visible` frames without more detail.

### Modified Files
- **`lib/screens/live_object_detection/live_object_detection_screen.dart`** —
  - **OFF-trigger block** (immediately after existing session-lock activation): added `else if` branch `!_anchorFilterActive && _safetyTimeoutTimer != null && _kickDetector.state == KickState.idle`. Body: `_anchorFilterActive = true; _safetyTimeoutTimer?.cancel(); _safetyTimeoutTimer = null; _ballId.deactivateSessionLock(); _byteTracker.setProtectedTrackId(null); print('DIAG-ANCHOR-FILTER: ON (kick returned to idle — false-alarm recovery)');`. Same release-semantics as the decision-accept path. Purpose: close the dead 2 s window between a false-alarm kick flicker and the safety timer.
  - **`_toDetections` diagnostic log upgrade:**
    - Added `final anchorPassedDetails = <String>[];` alongside the existing `anchorDroppedDetails`.
    - Drop entry now includes `size=(${bbox.width.toStringAsFixed(3)}x${bbox.height.toStringAsFixed(3)})`. Same format added to a new passed-entry branch inside the existing `if (anchorActive) { anchorPassed++; ... }` block.
    - Log gate changed from `if (anchorDropped > 0)` to `if (anchorActive)` so the log fires every frame the filter is ON — including zero-detection frames (`passed=0 dropped=0`). This is what disambiguates "YOLO missed the ball" from "filter dropped the ball".
    - Label rename: `dropped: [...]` → `dropped (outside rect): [...]`, new `passed (inside rect): [...]` line prepended.
  - **`TrailOverlay` trail gate** (Stack, where `trail:` is passed): changed from `_kickDetector.state == KickState.idle ? const [] : _ballId.trail` to `_kickDetector.state == KickState.idle && !(_anchorFilterActive && _anchorRectNorm != null && _ballId.currentBallTrack != null && _anchorRectNorm!.contains(_ballId.currentBallTrack!.center)) ? const [] : _ballId.trail`. Effect: during idle, trail stays suppressed unless the ball is visibly inside the rect with the filter armed — then the trail's overlapping dots on a stationary ball render as the flickering orange dot the user remembered.

### New Files
None.

### Tests
- No new tests. Existing suite **175/175 passing** (unchanged).

### Verification
- **`flutter analyze`** — 92 infos (+1 from prior 91; the delta is the new `DIAG-ANCHOR-FILTER: ON (kick returned to idle — …)` `print` call, consistent with the existing diagnostic-print pattern). Zero errors, zero warnings.
- **`flutter test`** — 175/175 passing.
- **iOS (iPhone 12, same session):** two field runs captured.
  - **Run 1** — explicitly exercised the new `else if` idle-edge recovery. Log shows the full sequence: re-acquisition into rect (`trackId=1 → trackId=5`), brief confirming-flicker (`OFF — 2s safety timer armed`), then back to idle, which fired the new branch: **`DIAG-ANCHOR-FILTER: ON (kick returned to idle — false-alarm recovery)`**. Filter re-armed immediately without waiting for the 2 s safety timer. **`else if` is field-proven.**
  - **Run 2 (consecutive-hit)** — two complete kick cycles. Real ball consistently passed when YOLO emitted it, target-circle FPs consistently dropped, ball-return re-acquisition via Mahalanobis rescue from trackId=1 → trackId=2 clean at rect boundary. No flicker in this run. Zone decisions themselves were wrong in both kicks (`HIT zone 1` where ball actually crossed 1 → 6 → 7), but that is the pre-existing "first zone entered + premature fire" bug in `ImpactDetector`, orthogonal to all anchor-rectangle work.
- **Android (Realme 9 Pro+):** pending.

### Design Decisions (discussed this session)
- **One `else if` instead of a new top-level `if`.** User pushed back on the initial "new block" proposal; folding into the existing OFF-trigger's `if`/`else if` chain is tighter and makes the state machine's symmetry obvious.
- **`_safetyTimeoutTimer != null` as the "we're in the dead window" marker.** Chose this over introducing a new `_pendingRecovery` bool — the timer's own presence is a naturally-right signal, requires no new state field.
- **Release session lock + clear protected track on idle-edge recovery.** Mirrors the decision-accept path exactly. Leaving session lock on would leave BallIdentifier locked to a trackId that may no longer be present.
- **Trail gate: idle-rect exception, not full re-enable.** During idle but OUTSIDE the rect, trail stays suppressed (preserves the ADR-069/070 FP-protection intent). Only the rect-confirmed "real ball" case opts back in.
- **Log fires every frame filter-ON, not only on drops.** Several discussion turns on cost (~30 lines/sec sustained) vs diagnostic value; chose visibility over quietness because the whole point of the change was "I can't see what's happening on no-drop frames". A throttle is easy to add later if needed.
- **Phase 4 skipped as standalone phase.** Reviewed spec line-by-line; all its mechanics already work implicitly via Phase 3 + BallIdentifier rescue. Only genuinely-new deliverable is an audio nudge, which belongs in Phase 5.
- Full rationale in ADR-078.

---

## Anchor Rectangle Phase 3 — Rectangle Filter During Waiting State (2026-04-22)

### Summary
Implemented Phase 3 of the Anchor Rectangle feature — the first **spatial** filter in the detection pipeline. Raw YOLO detections whose (Android-rotation-corrected) bbox **center** lies outside `_anchorRectNorm` are dropped inside `_toDetections` **before reaching ByteTrack**. The gate is state-driven: ON at lock → OFF at `KickState.confirming`/`active` with a 2 s safety timer → ON at decision fired (accept or reject path) OR 2 s safety-timeout (re-arms filter, releases session lock, clears protected track). Additive to every existing FP defense (class filter, AR > 1.8, Mahalanobis rescue, isStatic, session lock); touches zero working behavior. Six iOS smoke tests passed; **target circle false positives (ISSUE-022, the #1 field-test blocker) confirmed silently dropped at their fixed banner positions on every frame.** CSV diagnostics deferred as optional follow-up.

### Modified Files
- **`lib/screens/live_object_detection/live_object_detection_screen.dart`** —
  - New state fields near `_anchorRectNorm`: `bool _anchorFilterActive = false;` and `Timer? _safetyTimeoutTimer;`. No other state surface touched.
  - `_confirmReferenceCapture()`: added three lines alongside the existing `_anchorRectNorm = anchorRect;` — sets `_anchorFilterActive = anchorRect != null;` and emits `DIAG-ANCHOR-FILTER: ON (locked — …)` with rect bounds.
  - New adjacent block in the `onResult` pipeline immediately after the existing session-lock activation block (untouched): fires on `KickState.confirming || isKickActive`, guarded by the filter flag itself as an edge detector. Sets `_anchorFilterActive = false;`, cancels any prior timer, starts `Timer(Duration(seconds: 2), _onSafetyTimeout)`, emits `DIAG-ANCHOR-FILTER: OFF (kick state=…) — 2s safety timer armed`.
  - New private method `_onSafetyTimeout()` placed next to `_cancelAudioNudgeTimer` (sibling-timer locality). Re-arms filter if rect still present, releases session lock, clears protected track, logs `SAFETY TIMEOUT`.
  - Result gate (accept path): added `_safetyTimeoutTimer?.cancel(); _safetyTimeoutTimer = null; if (_anchorRectNorm != null) { _anchorFilterActive = true; print('ON (decision fired — accepted)'); }` immediately after the existing `_ballId.deactivateSessionLock(); _byteTracker.setProtectedTrackId(null);` pair. Reject path: same block with `'rejected'` log.
  - `_startCalibration` reset block (Recal-1): added `_anchorFilterActive = false; _safetyTimeoutTimer?.cancel(); _safetyTimeoutTimer = null;` next to the existing `_anchorRectNorm = null` line.
  - `dispose`: added timer cancellation mirroring the `_cancelAudioNudgeTimer` pattern.
  - `_toDetections`: new counters `anchorDropped` / `anchorPassed` + `anchorDroppedDetails` list and a precomputed `anchorActive` flag. Added `if (anchorActive && !_anchorRectNorm!.contains(bbox.center)) { anchorDropped++; anchorDroppedDetails.add('${r.className}@(…) conf=…'); continue; }` between the Android rotation-correction and the `detections.add(...)` call. After the loop: a single summary `print` with rect bounds + per-detection detail, emitted only when drops > 0.
  - Zero refactors of working code anywhere in the file. Class filter, AR > 1.8 reject, rotation correction, session lock block, Mahalanobis rescue, result gate conditions — all untouched.

### User Memory
- Added `feedback_no_refactor_bundling.md` to `/Users/shashank/.claude/projects/.../memory/` after the user flagged (mid-session) that mixing refactors with feature work violates their trust. The rule: during feature work, only touch new code or make additive changes to existing blocks; accept small duplication now, clean it up as a separate single-purpose change later. Applied retroactively in this session: a proposed `isKickInProgress` getter refactor was dropped in favour of an inlined condition.

### Tests
- No new unit tests added — all six smoke tests are on-device behavioural tests tied to live detection + timer behaviour, which existing unit scaffolding does not exercise cleanly.
- Existing test suite: **175/175 passing** (unchanged from prior session).

### Verification
- **`flutter analyze`** — 91 issues, all `info`-level (+6 from prior 85; the delta is the newly-added `DIAG-ANCHOR-FILTER` `print` calls, same intentional-print pattern already used across the diagnostic pipeline). Zero errors, zero warnings.
- **iOS (iPhone 12)** — six on-device smoke tests passed: (1) ON at lock with log, (2) filter drops outside-rect decoys with enriched per-detection log, (3b) kick-not-caught scenario handled cleanly + target-circle FPs confirmed dropped, (3) full `ON → OFF → ON` cycle through a real kick with safety timer armed-but-not-fired and reject path also exercised, (5) re-calibration resets all Phase 3 state, (6) screen dispose cancels the safety timer. Test 4 (safety timeout actually firing) deferred to opportunistic observation during normal play — cannot be reliably reproduced on demand.
- **Android (Realme 9 Pro+)** — pending.

### Design Decisions (in discussion this session)
- **Filter placement: pre-ByteTrack vs post-ByteTrack.** Chose pre-ByteTrack (inside `_toDetections`) per the plan's original spec. Post-ByteTrack was rejected because it leaves outside-rect noise visible to ByteTrack, to the diagnostic logs, and to the protected-track logic — pre-ByteTrack cleans the pipeline at the source. The feared "locked-ball nudge pushes it out of rect → ByteTrack starves" risk does not materialise in practice because the 3×/1.5× rect margin is generous and the OFF trigger fires the instant the ball's kick-onset is detected.
- **Hit test: center-in-rect.** Rejected "full bbox inside" (too strict — bbox jitter causes spurious drops) and "any overlap" (too loose — half-in-frame FPs pass). Center-in-rect is the clean middle ground.
- **OFF-trigger timing: `confirming` OR `active`, not just `active`.** The existing session-lock block fires at `isKickActive`; filter OFF needs to fire one state earlier (at `confirming`) so that in-flight detections are not dropped once the ball leaves the rect. Chose a new adjacent block over extending the existing condition to avoid changing the session-lock's own activation timing (a known-working path).
- **Re-arm timing: on internal decision fire, not on audio start or audio end.** Bounce-back FPs appear within 100–300 ms of impact; re-arming at internal decision fire cuts them before they can enter ByteTrack.
- **Safety timeout: 2 s from `confirming`.** Discussed 3 s and 2 s; chose 2 s as generous enough that no real kick (< 1.5 s flight) trips it, short enough that a stuck-lock scenario recovers quickly. When it fires, it also releases session lock (rejecting option "just re-arm filter" as incomplete: BallIdentifier would remain locked out).
- **Edge detector for OFF: use the filter flag itself, not a `_prevKickState` field.** User question ("won't this miss kicks?") prompted simplification. Because the filter flag is `true` exactly once between lock and kick, it acts as its own edge detector. Simpler and robust to `confirming → idle → confirming` re-entries.
- **Additive-only edits to working code.** User-flagged mid-session (see memory entry). Dropped a proposed `KickDetector.isKickInProgress` getter refactor that would have touched two working call sites; inlined the condition in the new Phase 3 block instead.
- **Enriched drop log.** User asked how to verify *which* detection was dropped vs passed from logs alone. Added per-detection class / center / confidence to the drop log (passed detections are traceable downstream via `DIAG-BYTETRACK`).
- Full rationale and rejected options in ADR-077.

### Scenario Behavior (field-verified)
- **Normal kick → decision.** Filter OFF during flight; re-armed on decision fire (accept path). Post-decision bounce-back / noise dropped immediately.
- **Kick not caught by KickDetector.** Filter stays ON throughout; ball's flight detections (outside rect) dropped; locked track dies cleanly; on ball's return into rect, BallIdentifier re-acquires via `nearest_non_static` and cycle resumes. Ball resting outside rect is invisible until returned — consistent with Phase 4's planned "return to anchor" semantics.
- **Kick confirmed but no decision (ISSUE-030 pattern).** After 2 s the safety timer re-arms filter and releases session lock; pipeline returns to clean waiting state without operator intervention.

### Field Observations (non-blocking, tracked as future polish)
- **Rect is tight for small balls.** Observed ball center drifting 0–14 millinormalized-units outside the right edge of a ~0.091-wide rect for brief periods. Mahalanobis rescue consistently recovered the locked track when the ball drifted back into rect. Multipliers `3×/1.5×` may be bumped to `4×/2×` if this recurs.
- **Drop log verbosity.** ~30 lines/sec during sustained drops (e.g., three target circles + real ball out-of-rect). QoL throttling deferred.
- **Reject-path log wording.** `DIAG-ANCHOR-FILTER: ON (decision fired — rejected)` is emitted even when filter was already ON (kick never reached `confirming`). Cosmetic; not a bug.
- **KickDetector sensitivity and depthRatio < 0.7.** Both observed during soft kicks in the field test session; out of scope for Phase 3 (tracked separately).

---

## Anchor Rectangle Phase 2 — Rectangle Computation & Display (2026-04-20)

### Summary
Implemented Phase 2 of the Anchor Rectangle feature — the magenta dashed anchor rectangle now draws at the locked ball's position after the Confirm tap, sized **3× bbox width × 1.5× bbox height** of the locked ball and **frozen** at lock-time bbox center. Screen-axis-aligned (long side horizontal), magenta `0xFFFF00FF`, 2 px stroke, dashed, no fill. Visual only — detection is still global (filtering is Phase 3). All four Phase 2 open questions resolved in a discussion-only session and recorded in ADR-076; original "60×30 cm via ball-bbox scaling" plan language replaced because it implicitly assumed a fixed ball diameter, which violates the "ball size is not fixed" architecture rule. iOS (iPhone 12) device verification confirmed via screenshot.

### Modified Files
- **`lib/utils/canvas_dash_utils.dart` (new file)** — Top-level `drawDashedLine(canvas, start, end, paint, {dashLength = 8, gapLength = 6})` helper. Lifted byte-for-byte from `calibration_overlay.dart`'s private `_drawDashedLine`. Direction-agnostic (works for any two endpoints). Single source of truth for dashed-line rendering in the app.
- **`lib/screens/live_object_detection/widgets/calibration_overlay.dart`** — Removed private `_drawDashedLine` (lines 253–277). Added import of the new shared util. Two call sites in `_paintCenterCrosshair` updated to the new top-level name (rename-only; signature and defaults identical). Crosshair behavior unchanged.
- **`lib/screens/live_object_detection/live_object_detection_screen.dart`** —
  - New import: `package:tensorflow_demo/utils/canvas_dash_utils.dart`.
  - New state: `Rect? _anchorRectNorm` — anchor rectangle in normalized [0,1] coords. Null before lock and after recalibration.
  - `_resetAllState()`: adds `_anchorRectNorm = null` alongside existing Phase 1 Recal-1 clears.
  - `_confirmReferenceCapture()`: before the `setState`, looks up the selected candidate in `_ballCandidates` by `trackId`, computes `Rect.fromCenter(center: bbox.center, width: bbox.width * 3.0, height: bbox.height * 1.5)`, and assigns into `_anchorRectNorm` inside the same `setState`.
  - Stack: new `if (_anchorRectNorm != null) LayoutBuilder → IgnorePointer → CustomPaint(painter: _AnchorRectanglePainter(...))` block, positioned before the Confirm button. Visible post-lock regardless of other state. `IgnorePointer` ensures taps flow through to underlying handlers.
  - New private class `_AnchorRectanglePainter extends CustomPainter` — magenta stroke, 2 px, `PaintingStyle.stroke`. Paints 4 dashed edges via `drawDashedLine` using `YoloCoordUtils.toCanvasPixel` for normalized → canvas conversion (same transform every other overlay uses). `shouldRepaint` compares `rectNorm` + `cameraAspectRatio`.

### New Files
- `lib/utils/canvas_dash_utils.dart` — shared dashed-line helper.

### Tests
- No unit tests added — change is visual-only and has no extractable business logic. Existing 175/175 test suite remains passing (no behavior changes outside the painter).

### Verification
- **`flutter analyze`** — no new warnings; only pre-existing `avoid_print` and `no_leading_underscores_for_local_identifiers` infos.
- **iOS (iPhone 12)** — user-provided device screenshot confirms: magenta dashed rectangle renders around the locked soccer ball, sized wider than tall (3:1.5 ratio), long side horizontal, centered on the ball; calibration grid renders normally; center crosshair unchanged after the shared-util refactor.
- **Android (Realme 9 Pro+)** — pending.

### Design Decisions
- **Rectangle size = bbox-relative multipliers, not cm.** Earlier plan draft said "60×30 cm via ball-bbox scaling," which implicitly assumed a fixed ball diameter. The project architecture never assumes a ball size (see `memory/project_no_fixed_ball_size.md`). Bbox-relative multipliers give correct perspective scaling automatically because the ball's bbox encodes its depth, without a cm reference.
- **Frozen center.** Rectangle does not follow the ball after lock. "Anchor" is meaningful only as a fixed region; a rectangle that follows the ball cannot filter the ball leaving its area (Phase 3) or serve as a return target (Phase 4).
- **Screen-axis-aligned.** Covers the same filtering region as a target-aligned rect; keeps Phase 3 point-in-rect test trivially axis-aligned.
- **Magenta dashed.** Distinct from every color currently used on the screen (red = ball bbox, green = calibration/confirm, yellow = unlocked track, orange = trail, purple = calibration debug). Dashed stroke encodes the semantic difference between "detection" and "region."
- **Shared `drawDashedLine` util.** Chose shared extraction (option 2) over copy-paste (option 1) to honour the "production-bound POC, DRY" principle. Refactor is byte-identical, de-risked by on-device verification of the calibration crosshair.
- Full rationale and rejected options in ADR-076.

### Why the plan's "60×30 cm" language changed
The 60×30 cm intent was a placeholder. The real requirement is "a region around the ball big enough to tolerate jitter but tight enough to exclude target circles and the kicker." Multipliers express that goal directly. Final multipliers will be field-tuned once Phase 3 turns on filtering and we can see the behavior in context.

### Out of Scope (deferred to later phases)
- Detection filter during waiting state (Phase 3).
- Return-to-anchor cycle after decision (Phase 4).
- Real audio asset + edge cases (Phase 5).
- Android device verification.

---

## Anchor Rectangle Phase 1 — Tap-to-Lock + Back-Button Z-Order Fix + Audio Counter (2026-04-19)

### Summary
Implemented Phase 1 of the Anchor Rectangle feature — replaced the auto-pick-largest reference-capture heuristic with explicit player tap-to-select. Two-step UX retained (tap a red bbox → turns green → Confirm commits). All 12 design decisions agreed up front via the brainstorming skill and recorded in `memory-bank/anchor-rectangle-feature-plan.md`. Fixed two back-button z-order bugs discovered during review (one pre-existing in calibration mode, one Phase 1 regression in awaiting-reference-capture) with a single `Positioned` widget move. Added a per-episode counter + timestamp to the audio nudge stub so the 30 s grace + 10 s repeat cadence is verifiable from device logs alone while the real audio asset is deferred to Phase 5. iOS (iPhone 12) device verification passed end-to-end; Android (Realme 9 Pro+) pending.

### Modified Files
- **`lib/services/ball_identifier.dart`** — `setReferenceTrack(List<TrackedObject>)` → `setReferenceTrack(TrackedObject)`. Removed in-method filter/sort/take-largest block. Caller (screen) is now responsible for filtering and selecting the tapped track. Doc comment updated.
- **`lib/services/audio_service.dart`** — Added `_tapPromptCallCount` field, `resetTapPromptCounter()` method, and `playTapPrompt()` stub that prints `AUDIO-STUB #N: Tap the ball to continue (HH:MM:SS.mmm)`. Real audio asset is deferred to Phase 5.
- **`lib/screens/live_object_detection/live_object_detection_screen.dart`** —
  - New state: `_ballCandidates` (list of `(trackId, bbox)`), `_selectedTrackId` (int?), `_audioNudgeTimer` (Timer?).
  - `_ReferenceBboxPainter` refactored from single-bbox to multi-bbox with per-item red/green colour.
  - `onResult`: collects ALL ball-class tracked candidates, runs aliveness check on `_selectedTrackId`, drives State 1↔2 audio-timer transitions, `_referenceCandidateBboxArea` now mirrors the SELECTED track.
  - New `_findNearestBall` (mirrors `_findNearestCorner`) + `_handleBallTap` (Tap-2 rule, last-tap-wins).
  - New `_startAudioNudgeTimer` / `_cancelAudioNudgeTimer` (30 s grace + 10 s repeat, resets AudioService counter on start).
  - `onTapUp` added to existing GestureDetector alongside `onPanStart/Update/End` (Gesture-1: trust the gesture arena).
  - Prompt text extended to 3-state ternary (S1-a / "Tap the ball you want to use" / "Tap Confirm to proceed with selected ball").
  - `_confirmReferenceCapture` resolves `_selectedTrackId` → `TrackedObject` before calling the new `setReferenceTrack(track)` API. Bails safely on race-window disappearance.
  - `_startCalibration` (Recal-1): clears tap selection + cancels nudge timer. `dispose`: cancels nudge timer.
  - **Back button `Positioned` block moved** from early Stack position (line ~1015) to just before the rotate overlay. Z-order change only; visually identical. Closes ISSUE-031 (calibration-mode + awaiting-reference-capture back-button unreachability).
  - **Drive-by cleanup:** removed unused legacy field `_referenceCandidateBbox` (1 declaration + 2 dead `= null` writes).
- **`test/ball_identifier_test.dart`** — Rewrote 4 obsolete auto-pick-largest tests as 3 new contract tests for the new `setReferenceTrack(TrackedObject)` signature. Updated 14 other call sites from `[_track(...)]` to `_track(...)`. 18/18 tests in this file pass.
- **`memory-bank/anchor-rectangle-feature-plan.md`** — Phase 1 section rewritten with 12-row Resolved Decisions table, 4-state Player Flow walkthrough, corrected change-summary table, resolved open-questions section, design notes subsection.

### Verification
```
$ flutter analyze  -- 0 errors, 0 warnings, 85 infos
$ flutter test     -- 175/175 passing
```
Net test count −1 from 176: 4 obsolete auto-pick tests rewritten as 3 new contract tests.

### Device Test Results
- **iOS (iPhone 12) — PASSED 2026-04-19:** Phase 1 tap-to-lock flow end-to-end. Back button works in calibration mode, awaiting reference capture, and live pipeline.
- **Android (Realme 9 Pro+) — pending.**

### Related Artifacts
- **ISSUE-031** added to `issueLog.md` — back-button z-order bugs + fix
- **ADR-073** added to `decisionLog.md` — Phase 1 Anchor Rectangle tap-to-lock design (covers 12 design choices)
- **ADR-074** added to `decisionLog.md` — Back-button z-order via Stack re-ordering
- **ADR-075** added to `decisionLog.md` — Audio nudge stub with per-episode counter + timestamp for log-based verification

---

## Mahalanobis Area Ratio Fix + UI Refinements (2026-04-16)

### Summary
Fixed silent kicks caused by over-aggressive Mahalanobis rescue area ratio check (ISSUE-029). Three iterations tested: (1) relaxed Kalman threshold 3.5/0.3 — 4/5 kicks but false positive dots returned, (2) last-measured-area with tight 2.0/0.5 — 3/5 kicks (lower bound too tight), (3) last-measured-area with 2.0/0.3 — 5/5 kicks across 3 test runs. Also updated center crosshair to purple at 1.5 strokeWidth for visibility, repositioned calibrate button above tilt indicator, and re-enabled large result overlay.

### Modified Files
- **`lib/services/bytetrack_tracker.dart`** — `update()` and `_greedyMatch()` accept `lastMeasuredBallArea` optional parameter. Area ratio check uses last measured area (with Kalman fallback). Threshold: 2.0/0.3. All 3 `_greedyMatch` call sites updated.
- **`lib/screens/live_object_detection/live_object_detection_screen.dart`** — `_byteTracker.update()` passes `_ballId.lastBallBboxArea`. Calibrate button `bottom:16` → `bottom:48`. Large result overlay re-enabled.
- **`lib/screens/live_object_detection/widgets/calibration_overlay.dart`** — Center crosshair: white → purple, strokeWidth 0.5 → 1.5. Center circle: white → purple, strokeWidth 1.0 → 1.5.

### Verification
```
$ flutter analyze -- 0 errors, 0 warnings, 84 infos
$ flutter test -- 176/176 passing
```

### Monitor Test Results
- 5/5 kicks detected across 3 test runs ✅
- False positive dots still appearing during active kicks ❌ (open issue)
- Ground testing scheduled for 2026-04-17

---

## Session Lock + Protected Track + Trail Suppression + Mahalanobis Area Ratio (2026-04-15)

### Summary
Implemented manager's suggestions to eliminate false positive trail dots. Added session lock in BallIdentifier (blocks re-acquisition during kicks), protected track in ByteTrackTracker (60-frame survival for locked ball), bbox area ratio check on Mahalanobis rescue (rejects size-mismatched candidates >2x or <0.5x), and trail suppression during kick=idle. Monitor+video testing confirmed zero false positive dots but revealed 2/5 kicks going silent due to area ratio check being too aggressive during fast flight. Root cause: Kalman predicted area diverges during pure predictions, blocking legitimate rescues.

### Modified Files
- **`lib/services/ball_identifier.dart`** — Added `_sessionLocked` flag, `activateSessionLock()`, `deactivateSessionLock()`, `isSessionLocked` getter. Priority 2 and 3 wrapped with `!_sessionLocked` guard. New log message for locked re-acquisition skip. Reset clears lock.
- **`lib/services/bytetrack_tracker.dart`** — Added `protectedMaxLostFrames = 60`, `_protectedTrackId`, `setProtectedTrackId()`, `_effectiveMaxLost()`. Track removal uses `_effectiveMaxLost(t)` instead of `maxLostFrames`. Added bbox area ratio check (4 lines) before Mahalanobis rescue acceptance. Reset clears protected ID.
- **`lib/screens/live_object_detection/live_object_detection_screen.dart`** — Session lock activation after `_kickDetector.processFrame()`. Deactivation in both ACCEPT and REJECT decision paths. Trail visibility gated on `_kickDetector.state != KickState.idle`.

### Verification
```
$ flutter analyze -- 0 errors, 0 warnings, 84 infos
$ flutter test -- 176/176 passing
```

### Monitor Test Results
- 0 false positive dots (previously the main problem) ✅
- 2/5 kicks silent (area ratio too aggressive) ❌
- Session lock stuck permanently on bounce-back false kicks ❌

---

## Pre-ByteTrack AR Filter for False Positive Reduction (2026-04-13)

### Summary
Added a pre-ByteTrack aspect ratio filter to reject elongated YOLO false positives (torso/limb bboxes) before they enter the tracker. Detections with AR > 1.8 are rejected in `_toDetections()`. Also attempted and reverted Mahalanobis rescue validation (size ratio + velocity direction checks) — keeping one-change-at-a-time discipline. Debug bbox overlay disabled by developer for cleaner visual output.

### Modified Files
- **`lib/screens/live_object_detection/live_object_detection_screen.dart`** — Added AR > 1.8 reject in `_toDetections()` (2 lines). Debug overlay `_debugBboxOverlay` set to `false` by developer.
- **`lib/services/bytetrack_tracker.dart`** — Mahalanobis rescue validation added then reverted (net: no change from session start).

### Verification
```
$ flutter analyze -- 0 errors, 0 warnings, 81 infos
$ flutter test -- 176/176 passing
```

---

## ISSUE-027 Fix: Two-Way isStatic Classification via Sliding Window (2026-04-13)

### Summary
Fixed the one-way `isStatic` flag bug in ByteTrack's `_STrack` class. The flag was permanently set to `true` after 30 frames of low displacement and never cleared — causing BallIdentifier to reject the real ball track during re-acquisition after kicks. Also discovered a second bug: `isStatic` never re-triggered on subsequent stationary periods because the lifetime `_cumulativeDisplacement` accumulator retained displacement from previous movement. Both bugs fixed by replacing the accumulator with a sliding window (`ListQueue<double>`, capacity=30 frames). Research into ByteTrack/SORT/DeepSORT/OC-SORT/Norfair/Frigate NVR confirmed the approach is consistent with Frigate's production static object detection (the only tracker with static classification). Device-verified on iPhone 12.

### Modified Files
- **`lib/services/bytetrack_tracker.dart`** — Added `import 'dart:collection'`. Replaced `_cumulativeDisplacement` (double) with `_recentDisplacements` (`ListQueue<double>`). Added `_displacementWindowSize` field. `update()` pushes per-frame displacement to buffer with FIFO eviction. `evaluateStatic()` now two-way: sums window, sets `isStatic = recentTotal < maxDisp` when window is full.
- **`test/bytetrack_tracker_test.dart`** — Renamed `'static flag is permanent once set'` → `'static flag stays true with minor jitter'`. Added 3 new tests: `static → dynamic` transition, `dynamic → static` transition, `full cycle: static → kicked → lands → static again`.

### Verification
```
$ flutter analyze -- 0 errors, 0 warnings, 81 infos
$ flutter test -- 176/176 passing
```

---

## Calibration Diagnostics + Debug Bbox Overlay + Enhanced BallIdentifier Logging (2026-04-09)

### Summary
Added three diagnostic tools to identify root cause of inconsistent zone detection across calibrations. (1) Calibration geometry diagnostics log 15+ geometric parameters (corner positions, edge lengths, aspect ratio, perspective ratios, centroid, coverage, corner angles, homography matrix, zone centers in camera space) at every calibration event and pipeline start. (2) Debug bounding box overlay renders colored bboxes for all ball-class detections on screen (green=locked, yellow=candidate, red=lost) with trackId, bbox WxH, aspect ratio, confidence, isStatic flag. (3) Enhanced BallIdentifier logging shows all candidate tracks with full diagnostic info on re-acquisition/loss events. Debug overlay revealed three critical bugs: Mahalanobis rescue identity hijacking (ISSUE-026), isStatic one-way flag (ISSUE-027), and YOLO false positives on kicker body at high confidence.

### New Files
- **`lib/screens/live_object_detection/widgets/debug_bbox_overlay.dart`** (~110 lines) — CustomPainter rendering colored bounding boxes. Green=locked, Yellow=candidate, Red=lost. Shows trackId, bbox WxH, aspect ratio, confidence, isStatic, [LOCKED] label.

### Modified Files
- **`lib/screens/live_object_detection/live_object_detection_screen.dart`** — Added `_logCalibrationDiagnostics()` (~100 lines), `_debugBboxOverlay` toggle, `_debugBallClassTracks` state, DebugBboxOverlay widget in Stack, PIPELINE START diagnostic block at confirm. Import added for debug_bbox_overlay.dart.
- **`lib/services/ball_identifier.dart`** — Enhanced DIAG-BALLID logging: lost events show all candidates with bbox WxH, aspect ratio, velocity, static, state, confidence. Re-acquisition logs old→new trackId, bbox shape, reason. Rejection reason logging added.

### Verification
```
$ flutter analyze -- 0 errors, 0 warnings, 78 infos
$ flutter test -- 173/173 passing
```

---

## directZone Decision Logic + Diagnostic Improvements (2026-04-09)

### Summary
Overhauled ImpactDetector decision logic based on kick-by-kick video test analysis. Replaced WallPlanePredictor → depth-verified → extrapolation decision cascade with a single signal: last observed `directZone` (ball's actual position mapped through homography). Video test showed directZone correct 5/5 times while old cascade only announced 2/5. Also loosened KickDetector result gate to accept `confirming` (was `active` only), added `kickState` and `ballConfidence` to IMPACT DECISION diagnostic block, and surfaced YOLO `confidence` on `TrackedObject`.

### Modified Files
- **`lib/services/impact_detector.dart`** — Added `_lastDirectZone` field. Decision priority changed to: edge exit → last directZone → noResult. Removed WallPlanePredictor, depth-verified, and extrapolation from decision cascade. Removed `minTrackingFrames` gate (directZone is self-validating). Added `lastDirectZone` to DIAG print block. Velocity-drop trigger now also checks `_lastDirectZone`.
- **`lib/services/kick_detector.dart`** — `onKickComplete()` now accepts `confirming` state in addition to `active`.
- **`lib/screens/live_object_detection/live_object_detection_screen.dart`** — Result gate accepts `confirming` OR `active` (was `active` only). Added `kickState` and `ballConfidence` prints after IMPACT DECISION block fires.
- **`lib/services/bytetrack_tracker.dart`** — Added `confidence` field to `TrackedObject` class, passed through in `toPublic()`.
- **`test/impact_detector_test.dart`** — Rewrote all decision tests to use `directZone` instead of extrapolation. Added new test for "last directZone wins over earlier directZone" and "directZone cleared on reset". 22 tests (was 22, some renamed/restructured).
- **`test/ball_identifier_test.dart`** — Added `confidence` default to test helper.

### New Snapshot Files
- `memory-bank/snapshots/impact_detector_2026-04-09_pre_directzone.dart.bak`
- `memory-bank/snapshots/live_object_detection_screen_2026-04-09_pre_directzone.dart.bak`
- `memory-bank/snapshots/impact_detector_test_2026-04-09_pre_directzone.dart.bak`

### Verification
```
$ flutter analyze -- 0 errors, 0 warnings, 56 infos
$ flutter test -- 173/173 passing
```

---

## Camera Alignment Aids + Kick-State Gate Experiment (REVERTED) (2026-04-08)

### Summary
Added camera alignment aids (crosshair, tilt indicator, shape validation) to CalibrationOverlay — device-verified on iPhone 12. Attempted to gate ImpactDetector/WallPredictor behind KickDetector state to prevent phantom impact decisions during idle. This broke grounded kick detection (3/5 kicks undetected) and was fully reverted. Also attempted to gate trail dot addition on kick state (`kickEngaged` parameter on `BallIdentifier.updateFromTracks()`) to prevent false dots on non-ball objects — this killed all trail visualization and was also fully reverted. Both files restored to pre-experiment state. Code snapshots directory created at `memory-bank/snapshots/` for future pre-change backups.

### Modified Files
- **`lib/screens/live_object_detection/widgets/calibration_overlay.dart`** — Added `showCenterCrosshair` and `tiltY` parameters. Added `_paintCenterCrosshair()` (dashed white lines + center circle), `_drawDashedLine()` helper, `_paintTiltIndicator()` (spirit-level bubble), `_paintOffsetFeedback()` (shape validation with edge ratios + corner symmetry).
- **`lib/screens/live_object_detection/live_object_detection_screen.dart`** — Added accelerometer subscription (`sensors_plus`) at 10Hz for tilt indicator. CalibrationOverlay always rendered with `showCenterCrosshair` and `tiltY` params. **Kick-state gate on ImpactDetector/WallPredictor: ADDED THEN REVERTED.** ImpactDetector and WallPredictor run unconditionally every frame.
- **`lib/services/ball_identifier.dart`** — **`kickEngaged` parameter: ADDED THEN REVERTED.** Trail dots always added when ball is tracked. Restored original combined position+trail update structure.
- **`test/ball_identifier_test.dart`** — **`kickEngaged: true` args: ADDED THEN REVERTED.** Tests restored to original calls.

### New Files
- **`memory-bank/snapshots/`** — Directory for pre-change file backups. Contains snapshots of `ball_identifier.dart`, `live_object_detection_screen.dart`, `ball_identifier_test.dart` from mid-session.

### Verification
```
$ flutter analyze -- 0 errors, 0 warnings, 58 infos
$ flutter test -- 172/172 passing
```

### Lessons Learned
- Gating pipeline input on KickDetector state is too aggressive — KickDetector's jerk threshold doesn't fire for grounded shots. KickDetector should only gate result acceptance (audio), not pipeline processing.
- Trail gating on kick state treats the symptom (false dots) not the cause (wrong track identity). Root cause is BallIdentifier re-acquiring to non-ball objects.
- Without git, reverts are memory reconstructions that introduce new bugs. Code snapshots directory created as mitigation.

---

## Mahalanobis Matching + Device Testing Fixes (2026-04-06)

### Summary
Three rounds of device testing on iPhone 12 drove iterative fixes to the ByteTrack matching logic. Round 1: IoU-only matching lost ball during fast kicks (ISSUE-023). Round 2: Added Mahalanobis distance fallback using Kalman covariance — ball tracked through kicks and `directZone` populated for first time, BUT circle tracks also got Mahalanobis-rescued creating scattered false dots. Round 3: Restricted Mahalanobis to locked ball track only via `lockedTrackId` parameter. Also fixed `setReferenceTrack` rejecting stationary ball (was flagged static), added red bounding box overlay for reference capture confirmation, and added DIAG prints throughout.

### Modified Files
- **`lib/services/bytetrack_tracker.dart`** — Added `mahalanobisDistSq()` to `_Kalman8` (Mahalanobis distance using innovation covariance S). Replaced `_greedyMatch` with two-stage: Stage 1 pure IoU (unchanged), Stage 2 Mahalanobis restricted to `lockedTrackId` only. Added `lockedTrackId` parameter to `update()` and `_greedyMatch()`. Chi-squared threshold 9.488 (4 DOF, 95% confidence — statistical constant). DIAG-MATCH prints on Mahalanobis rescues.
- **`lib/services/ball_identifier.dart`** — Fixed `setReferenceTrack` to accept static tracks (ball stationary during calibration was flagged `isStatic=true`). Added DIAG-BALLID prints for track loss and re-acquisition events.
- **`lib/screens/live_object_detection/live_object_detection_screen.dart`** — Pass `lockedTrackId: _ballId.currentBallTrackId` to `_byteTracker.update()`. Added `_referenceCandidateBbox` field + `_ReferenceBboxPainter` CustomPainter for red bounding box during reference capture. Updated `_confirmReferenceCapture` and `_startCalibration` to manage bbox state.
- **`test/ball_identifier_test.dart`** — Updated `setReferenceTrack` test to expect static tracks accepted.

### Verification
```
$ flutter analyze -- 0 errors, 0 warnings, 58 infos
$ flutter test -- 172/172 passing
```

### Device Test Results (iPhone 12, 2026-04-06)
- **Round 1 (IoU only):** Shake test PASS (no circle dots). Kick test FAIL — 0/3 detected, ball track lost mid-flight.
- **Round 2 (Mahalanobis + IoU merged):** Ball tracked through kicks, `directZone` populated (zones 1-9 visible). BUT circle tracks also Mahalanobis-rescued → scattered dots on circles during kicks.
- **Round 3 (Mahalanobis locked-track-only):** Pending device test.

---

## ByteTrack Pipeline Implementation — Phases 1-3 (2026-04-05)

### Summary
Replaced the fragmented detection/tracking pipeline with a complete ByteTrack multi-object tracker (ADR-058). Field testing (2026-04-04) revealed that YOLO detects target circles as soccer balls (ISSUE-022), causing 38.9%/11.1% zone accuracy. Root cause: no object identity — every frame re-selected detections from scratch. Solution: ByteTrack with 8-state Kalman (cx,cy,w,h,vx,vy,vw,vh), two-pass IoU matching, BallIdentifier for automatic ball re-acquisition. Phases 1-3 complete (new services + integration). Phases 4-7 pending (cleanup, ImpactDetector simplification, DiagnosticLogger update, field testing).

### New Files
- **`lib/services/bytetrack_tracker.dart`** (~530 lines) — Complete ByteTrack algorithm. 8-state Kalman per track, two-pass IoU matching (high ≥0.5, low 0.25-0.5), track lifecycle (tracked/lost/removed), static track detection, greedy assignment. Pure Dart, no external dependencies.
- **`lib/services/ball_identifier.dart`** (~210 lines) — Identifies which ByteTrack track is the soccer ball. Lock-on during reference capture (largest bbox), automatic re-acquisition by motion (only moving ball-class track) or proximity to last known position. Manages trail history (ListQueue) with same data contract as old BallTracker for TrailOverlay compatibility.
- **`test/bytetrack_tracker_test.dart`** — 26 unit tests: IoU computation, single/multi-object tracking, two-pass matching, track lifecycle, static detection, Kalman prediction, reset, 9-circles-plus-ball scenario.
- **`test/ball_identifier_test.dart`** — 19 unit tests: reference capture, track following, re-acquisition, ball lost badge, trail format, velocity/smoothedPosition, reset.

### Modified Files
- **`lib/screens/live_object_detection/live_object_detection_screen.dart`** — Major rewrite of detection pipeline. Removed imports: `ball_tracker.dart`, `trajectory_extrapolator.dart`, `wall_plane_predictor.dart`. Added imports: `bytetrack_tracker.dart`, `ball_identifier.dart`. Replaced state fields: `_tracker`, `_extrapolator`, `_lastExtrapolation`, `_wallPredictor` → `_byteTracker`, `_ballId`, `_ballClassNames`. Replaced `_pickBestBallYolo()`, `_applyPhaseFilter()`, `_squaredDist()` with `_toDetections()` (class filter + Android coord correction on full bbox). Rewrote entire `onResult` callback: YOLO results → ByteTrack update → BallIdentifier → KickDetector/ImpactDetector. Updated `_startCalibration()`, `_confirmReferenceCapture()`, `dispose()`, trail overlay reference, ball lost badge reference.

### Files NOT YET Removed (Phase 4 pending)
- `lib/services/ball_tracker.dart` — no longer imported by live screen
- `lib/services/kalman_filter.dart` — no longer imported
- `lib/services/wall_plane_predictor.dart` — no longer imported
- `lib/services/trajectory_extrapolator.dart` — no longer imported
- Old test files still exist and pass independently

### Verification
```
$ flutter analyze -- 0 errors, 0 warnings, 55 infos
$ flutter test -- 172/172 passing
```

---

## WallPlanePredictor + Phase-Aware Filtering + Bug 3 Fix (2026-04-01)

### Summary
Root cause of zone accuracy Bug 3 identified: 2D homography only maps correctly for points ON the wall plane; mid-flight ball positions appear lower in the camera frame due to perspective, causing upper zones (6,7,8) to be reported as bottom zones (1,2). Built WallPlanePredictor service through 3 iterations (v1: hardcoded wallDepthRatio → v2: physical dimensions → v3: zero hardcoded params with iterative projection). Also added phase-aware detection filtering to suppress false YOLO detections on kicker body/head/wall patterns. Three field test sessions conducted: accuracy improved from 20% to 60% exact (80% within 1 zone).

### New Files
- **`lib/services/wall_plane_predictor.dart`** — Observation-driven 3D trajectory prediction. Accumulates per-frame (2D position, depth ratio) observations, converts to pseudo-3D, iteratively projects forward checking `pointToZone()` at each step. Wall discovered implicitly — zero physical dimensions assumed. Constructor takes only `opticalCenter` (calibration corner centroid).
- **`test/wall_plane_predictor_test.dart`** — 12 unit tests: insufficient observations, stationary ball, ball toward camera, ball approaching wall, 2-observation prediction, reset, depth estimation, zero-area rejection, perspective correction (zone shift upward), noisy depth tolerance, frame-exit trajectory, no-hardcoded-params verification.

### Modified Files
- **`lib/services/impact_detector.dart`** — Added `wallPredictedZone` optional param to `processFrame()` and `_onBallDetected()`. Added `_lastWallPredictedZone` field. Wall-predicted zone is highest-priority decision signal (above depth-verified, above extrapolation). Velocity-drop detection checks both `_lastWallPredictedZone` and `_lastDepthVerifiedZone`. DIAG print block includes `lastWallPredictedZone`. Reset clears `_lastWallPredictedZone`.
- **`lib/services/diagnostic_logger.dart`** — CSV header and `logFrame()` updated with 3 new columns: `wall_pred_zone`, `est_depth`, `frames_to_wall`. DECISION row padded to match.
- **`lib/screens/live_object_detection/live_object_detection_screen.dart`** — Import `wall_plane_predictor.dart`. Added `_wallPredictor` field. Initialized in `_confirmReferenceCapture()` with optical center from corner centroid. `addObservation()` called every detected frame during pipeline-live. `predictWallZone()` result passed to `_impactDetector.processFrame()` as `wallPredictedZone`. Predictor reset on calibration start, kick accept, and kick reject. Added `_applyPhaseFilter()` method: Ready phase confidence 0.50 + 10% spatial gate, Tracking phase confidence 0.25 + 15% spatial gate from Kalman prediction. DIAG-WALL per-frame prints during tracking. DIAG-WALL init print at calibration.

### Verification
```
$ flutter analyze -- 0 errors, 0 warnings, 28 infos (all avoid_print)
$ flutter test -- 106/106 passing
```

### Field Test Results (iPhone 12, 2026-04-01)
| Session | Exact Correct | Within 1 Zone | Massive Y Error |
|---------|--------------|----------------|-----------------|
| 1 (no WallPlanePredictor) | 1/5 (20%) | 1/5 (20%) | 3/5 |
| 2 (v1 hardcoded) | ~1/5 (20%) | ~2/5 (40%) | 0 |
| 3 (v3 zero hardcoded) | 3/5 (60%) | 4/5 (80%) | 0 |

---

## KickDetector + DiagnosticLogger + Bug Fixes (2026-03-23)

### Summary
Implemented the KickDetector 4-signal kick gate to prevent false ImpactDetector triggers from non-kick ball movement (dribbling, rolling). Added DiagnosticLogger for per-frame/per-decision CSV logging with Share Log export. Fixed Bug 1 (stuck overlay) via `tickResultTimeout()` outside the kick gate. Fixed Share Log broken on iOS 26.3.1 via `GlobalKey`-based dynamic `sharePositionOrigin`. First field test conducted on iPhone 12 (iOS 26.3.1) — 4/5 kicks partially working; Bug 2 (off-by-one) and Bug 3 (zone accuracy) identified for next session.

### New Files
- **`lib/services/kick_detector.dart`** — 4-state kick gate (idle/confirming/active/refractory). 4 signals: jerk gate, energy sustain, direction toward goal, refractory period. Plain Dart, no Flutter deps.
- **`test/kick_detector_test.dart`** — 13 unit tests: idle start, real kick detection, slow dribble, moderate dribble, kick away from goal, direction check skipped without goalCenter, speed drop, ball lost during confirming, onKickComplete→refractory, refractory ignores movement, full refractory period, ball lost in active, reset.
- **`lib/services/diagnostic_logger.dart`** — Per-frame + per-decision CSV logger. Singleton. Writes to app Documents directory. `start()` / `logFrame()` / `logDecision()` / `stop()` API.

### Modified Files
- **`lib/services/impact_detector.dart`** — Added `tickResultTimeout()` public method. Checks result display expiry every frame. Solves stuck overlay when called outside kick gate.
- **`lib/services/diagnostic_logger.dart`** — Added `kick_confirmed` (1/0) and `kick_state` (idle/confirming/active/refractory) columns to CSV header and `logFrame()` signature.
- **`lib/screens/live_object_detection/live_object_detection_screen.dart`** — Added `_kickDetector = KickDetector()`, `_shareButtonKey = GlobalKey()`, `_goalCenter` getter (`_homography!.inverseTransform(Offset(0.5, 0.5))`). ImpactDetector gated behind `_kickDetector.isKickActive`. `tickResultTimeout()` called every frame outside gate. `onKickComplete()` called when ImpactDetector transitions to result. `_shareLog()` now passes `sharePositionOrigin: box.localToGlobal(Offset.zero) & box.size`. DiagnosticLogger `logFrame()` call updated with `kick_confirmed` and `kick_state` params.
- **`pubspec.yaml`** — Added `path_provider: ^2.1.3`, `share_plus: ^10.0.0`.

### Verification
```
$ flutter analyze -- 0 errors, 0 warnings, 21 infos (all avoid_print)
$ flutter test -- 94/94 passing
```

---

## Depth-Verified Direct Zone Mapping — ADR-051 (2026-03-20)

### Summary
Real-world outdoor testing showed trajectory extrapolation gives wrong zone numbers (e.g., predicts zone 8, ball hits zone 5) because mid-flight angular errors are amplified over 30+ frames. Android couldn't detect any hits at all. Four parallel research agents confirmed no commercial single-camera system uses long-range trajectory extrapolation for zone determination. Solution: re-enabled depth ratio as a "trust qualifier" — when ball's camera position maps to a zone AND depth ratio confirms near-wall depth, that zone takes priority over extrapolation. Extrapolation remains as fallback.

### Changes
- **`impact_detector.dart`**: Added `_lastDepthVerifiedZone` field, `directZone` parameter on `processFrame()` and `_onBallDetected()`. In `_onBallDetected`: when `directZone != null` AND depth ratio within `[0.3, 1.5]`, stores zone. In `_makeDecision()`: depth-verified zone preferred over extrapolation. Cleared in `_reset()`. `maxDepthRatio` changed from 2.5 to 1.5.
- **`live_object_detection_screen.dart`**: Added `directZone: _zoneMapper!.pointToZone(rawPosition)` to `processFrame()` call.
- **Decision priority**: Edge exit (MISS) → Depth-verified direct zone (HIT) → Extrapolation fallback (HIT) → noResult.
- **Research**: 4 parallel agents searched academic papers, GitHub, patents, app implementations. All converged: "last detected position near target" > "trajectory extrapolation" for zone accuracy.

### Verification
```
$ flutter analyze -- 0 errors, 0 warnings, 20 infos (all avoid_print)
$ flutter test -- 81/81 passing
```

---

## Audio Upgrade — Celebratory HIT Audio with Crowd Cheer (2026-03-19)

### Summary
Upgraded HIT audio from plain number callouts ("Seven") to celebratory announcements ("You hit seven!" + crowd cheer, ~4.7s each). Manager requested celebratory audio so players get immediate positive feedback on hits. Generated via macOS TTS (Samantha voice, rate 170) + Pixabay crowd cheer SFX (3.8s trim with 0.8s fade-out), composited with ffmpeg `filter_complex` concatenation. Drop-in replacement of `zone_1.m4a` through `zone_9.m4a` — zero code changes to `AudioService` or any other file. MISS audio (`miss.m4a`) unchanged. Original audio files backed up to `assets/audio/originals/`.

### Changes
- **9 audio files replaced** (`assets/audio/zone_1.m4a` through `zone_9.m4a`) — each contains TTS speech + 0.15s silence + crowd cheer with fade-out
- **TTS generation:** `say -v "Samantha" -r 170 "You hit [number]!"` — natural Samantha voice at slightly slower rate
- **Cheer SFX:** Pixabay "Crowd Cheer and Applause" (free commercial license, no attribution required), trimmed to 3.8s with `afade=t=out:st=3.0:d=0.8`
- **Compositing:** `ffmpeg -filter_complex "[0:a][1:a][2:a]concat=n=3:v=0:a=1[out]"` — speech + silence + cheer concatenated
- **zsh 1-based array fix:** Initial generation had off-by-one error (zone_1 said "You hit" with no number, zone_2 said "You hit one"). Fixed by using zsh native 1-based indexing (`${names[$i]}` instead of `${numbers[$i-1]}`)
- **Originals backed up** to `assets/audio/originals/` for potential revert

### Verification
```
$ flutter analyze -- 0 errors, 0 warnings, 18 infos (all avoid_print)
$ flutter test -- 81/81 passing
Device-verified on iPhone 12 and Realme 9 Pro+
```

---

## Pipeline Gating Fix — `_pipelineLive` Boolean (2026-03-19)

### Summary
Fixed premature pipeline activation where the detection pipeline (tracker, trail dots, "Ball lost" badge, impact detection, audio) ran immediately on camera open, before calibration. This caused false MISS/noResult announcements and unwanted orange dots during setup. Added a single `_pipelineLive` boolean gate enforcing 4 clear stages: Preview (silent) → Calibration (silent) → Reference Capture (bbox only) → Live (full pipeline).

### Changes
- **Added `_pipelineLive` boolean** (`live_object_detection_screen.dart:103`) — defaults to `false`, set `true` only in `_confirmReferenceCapture()`, reset to `false` in `_startCalibration()`
- **Gated tracker + extrapolation** — `_tracker.update()`, `_tracker.markOccluded()`, and extrapolation wrapped in `if (_pipelineLive)`
- **Gated impact detector** — `if (_zoneMapper != null)` changed to `if (_pipelineLive)`
- **Added `_tracker.reset()`** in `_startCalibration()` to clear trail dots on re-calibrate

### Verification
```
$ flutter analyze -- 0 errors, 0 warnings, 18 infos (all avoid_print)
$ flutter test -- 81/81 passing
Device-verified on iPhone 12 and Realme 9 Pro+
```

---

## Finger Occlusion Fix for Calibration Corner Dragging (2026-03-19)

### Summary
Fixed finger occlusion problem during calibration corner dragging. Real-world field testing revealed two issues: (1) 60px offset cursor caused excessive jump on tap, making bottom corners unreachable, (2) solid green dot hid crosshair intersection point. Exhaustive research (8 agents, 22 pub.dev keyword searches, 4 packages inspected) confirmed no existing Flutter package solves finger occlusion over camera platform views. Implemented offset cursor (30px) + hollow ring markers + crosshair lines.

### Changes
- **Corner markers changed to hollow green rings** (`calibration_overlay.dart`) — Removed `fillPaint` + `drawCircle(pixel, 8.0, fillPaint)`. Kept only stroked ring at radius 10px. Applied everywhere, not conditional on drag state.
- **Drag offset reduced from 60px to 30px** (`live_object_detection_screen.dart:96`) — User tested: 60px too jarring (bottom corners unreachable), 15px too subtle, 30px correct. Single constant: `_dragVerticalOffsetPx = 30.0`.
- **Crosshair lines** — Already existed from prior session. White 0.7 opacity, 0.5px strokeWidth, full screen width/height through active corner. Drawn in `CalibrationOverlay._paintCrosshair()`.

### Research Conducted
- 8 parallel research agents investigated: Flutter built-in Magnifier/RawMagnifier, Draggable/LongPressDraggable/InteractiveViewer, iOS/Android native occlusion patterns
- 22 pub.dev keyword searches across all relevant terms
- 4 packages source-code inspected: `flutter_quad_annotator` (requires static ui.Image), `flutter_magnifier_lens` (Fragment Shaders, Flutter 3.41+ incompatible), `flutter_magnifier` (BackdropFilter), `flutter_image_perspective_crop` (static Uint8List)
- All rejected: platform views (camera preview) are invisible to Flutter's compositing pipeline

### Verification
```
$ flutter analyze -- 0 errors, 0 warnings, 18 infos (all avoid_print)
$ flutter test -- 81/81 passing
Device-verified on iPhone 12 and Realme 9 Pro+
```

---

## ADR-047 Impact Detection Pipeline Fixes 1-3 (2026-03-17)

### Summary
Implemented three evidence-backed fixes to the impact detection pipeline (ADR-047). Real-world iOS testing improved hit detection rate from 1/10 (10%) to 4/6 (67%). Fix 4 (gravity/maxFrames in trajectory extrapolator) deferred for separate discussion. Outdoor real-world test on both devices scheduled for 2026-03-18.

### Changes
- **Fix 1: `minTrackingFrames` 8→3** (`impact_detector.dart`) — Single constant change. Research basis: Kalman filter velocity converges after 3-4 measurements (Bar-Shalom 2001). Fast kicks complete flight in 6-9 frames; old threshold of 8 rejected 60% of valid kicks.
- **Fix 2: Depth ratio filter disabled** (`impact_detector.dart`) — Depth ratio gate no longer blocks decisions. Diagnostic logging preserved. No published single-camera ball tracking system uses bbox area ratio as a depth gate.
- **Fix 3: Extrapolation retained during occlusion** (`impact_detector.dart` + `live_object_detection_screen.dart`) — `_onBallMissing()` now accepts and retains extrapolation during occlusion. Live screen recomputes extrapolation during ball-lost frames using Kalman-predicted state.
- **3 unit tests updated** — `minTrackingFrames` threshold test reduced from 5 to 2 frames; 2 depth filter tests updated to expect `hit` instead of `noResult`.
- **iOS indoor test (shoot-out video):** 4/6 correct HITs. Fix 2 directly saved 2 detections that would have been BLOCKED. 2 remaining failures: both had only 1 tracking frame (very fast kicks, YOLO caught ball once).

### Verification
```
$ flutter analyze -- 0 errors, 0 warnings, 17 infos (all avoid_print from diagnostic statements)
$ flutter test -- 81/81 passing
```

---

## Draggable Calibration Corners Implementation + iOS Hit Radius Fix (2026-03-14)

### Summary
Implemented the draggable calibration corners feature (ADR-046) and resolved an iOS-specific hit radius issue where `_dragHitRadius = 0.04` was too small due to `kTouchSlop` offset. Diagnosed via DIAG-DRAG prints, confirmed `onPanStart` fires on iOS but `_findNearestCorner` returned null because touch distances (0.0408-0.0851) exceeded the 0.04 threshold. Increased to `_dragHitRadius = 0.09`. Device-verified on both iPhone 12 and Galaxy A32.

### Changes
- **Draggable corners implemented** -- Added `_draggingCornerIndex` state, `_dragHitRadius = 0.09`, `_recomputeHomography()` helper (extracted from `_handleCalibrationTap`), `_findNearestCorner()` hit-test method, and `GestureDetector` with `onPanStart`/`onPanUpdate`/`onPanEnd` during `_awaitingReferenceCapture`. ~35 lines added to `live_object_detection_screen.dart`.
- **iOS hit radius fix** -- Initial `_dragHitRadius = 0.04` was too small on iOS. Diagnostic prints confirmed `onPanStart` fires every time but nearest corner distances (0.0408-0.0851) exceeded the threshold. Root cause: `kTouchSlop` (~18px) shifts the reported `onPanStart` position ~0.05-0.08 from where the user intended to touch. Increased radius from 0.04 to 0.09. DIAG prints removed after diagnosis.
- **ADR-047** -- Documents the hit radius tuning decision.
- **ISSUE-011** -- Documents the iOS drag hit radius too small issue.

### Verification
```
$ flutter analyze -- 0 errors, 0 warnings, 0 infos
$ flutter test -- 81/81 passing
Device-verified on iPhone 12 and Galaxy A32
```

---

## Back Button Fix During Calibration + Draggable Corners Decision (2026-03-13)

### Summary
Fixed a bug where the back button was unresponsive during the reference capture sub-phase of calibration (after tapping 4 corners, before confirming ball detection). Also discussed and decided the approach for draggable calibration corners (not yet implemented). Two new ADRs added (ADR-045, ADR-046).

### Changes
- **Back button fix** -- The full-screen GestureDetector for calibration corner taps was blocking the back button even after all 4 corners were placed. Changed condition from `if (_calibrationMode)` to `if (_calibrationMode && !_awaitingReferenceCapture)` so the tap handler is only active while corners are being collected. Back button now works during the ball detection confirm step.
- **ADR-045** -- Documents the back button fix decision.
- **ADR-046** -- Documents the draggable calibration corners approach decision. Evaluated 4 options: (1) GestureDetector `onPanStart`/`onPanUpdate`, (2) `box_transform` package, (3) magnified view, (4) smart rectangle correction. Option 1 chosen for simplicity, zero dependencies, and ability to handle perspective-distorted quadrilaterals. Not yet implemented.

### Verification
```
$ flutter analyze -- 0 errors, 0 warnings, 0 infos
$ flutter test -- 81/81 passing
```

---

## UI Cleanup + Camera Permission Fix (2026-03-11)

### Summary
Removed AppBar from detection screen, replaced YOLO text badge with circular back button, and added explicit camera permission handling via `permission_handler`. Created `issueLog.md` with 9 historical issues. Device-verified on both iPhone 12 and Galaxy A32. 81/81 tests passing.

### Changes
- **AppBar removed** -- Scaffold no longer has `appBar`. Camera preview fills full screen height in landscape (~56px reclaimed).
- **Back button badge** -- Circular back arrow icon (40x40, `Colors.black54`, `BorderRadius.circular(20)`) at `Positioned(top:12, left:12)`. `GestureDetector` + `Navigator.of(context).pop()`. Replaces YOLO text badge (redundant since YOLO is the only backend).
- **`DetectorConfig` import removed** from `live_object_detection_screen.dart` (unused after badge removal; class and tests still exist).
- **`permission_handler: ^11.3.1`** added to `pubspec.yaml`. `_requestCameraPermission()` in `initState` explicitly requests camera permission before `YOLOView` renders. `_cameraReady` flag gates rendering.
- **iOS Podfile** -- `PERMISSION_CAMERA=1` macro added to `GCC_PREPROCESSOR_DEFINITIONS` (required by `permission_handler`).
- **`memory-bank/issueLog.md`** created -- 9 issues with root causes and verified solutions (AAPT compression, cert expiry, camera permission, UTF-8, coordinate mirroring, aspect ratio, stale extrapolation, audio state, rotate overlay).

### Root Cause Investigation
- iOS "Unable to Verify" error: Free Apple Developer certificates expire every 7 days (timing coincidence with code change).
- Camera not working after reinstall: `ultralytics_yolo` v0.2.0 checks but never requests camera permission on iOS (`VideoCapture.swift` lines 86-95). Deleting app wipes permission state. Android side of plugin does request permissions — platform asymmetry bug.

### Verification
```
$ flutter analyze -- 0 errors, 0 warnings, 0 infos
$ flutter test -- 81/81 passing
Device-verified on iPhone 12 and Galaxy A32
```

---

## Phase 3: Impact Detection + Zone Mapping + Result Display (2026-03-09)

### Summary
Implemented the full impact detection state machine with multi-signal decision logic, zone mapping, and visual result display. Device-verified on both iPhone 12 and Galaxy A32. UI labels repositioned to bottom-right per user feedback. 70/70 tests passing.

### New Files
- **`lib/models/impact_event.dart`** -- Immutable value type with `ImpactResult` enum (hit/miss/noResult), zone number, camera/target points, timestamp
- **`lib/services/impact_detector.dart`** -- State machine (Ready -> Tracking -> Result -> Ready), multi-signal decision (trajectory extrapolation + frame-edge exit filter), configurable cooldown (default 3s)
- **`test/impact_detector_test.dart`** -- 12 unit tests covering all state transitions, edge detection, priority ordering, cooldown, force reset

### Modified Files
- **`lib/services/target_zone_mapper.dart`** -- Added `zoneCorners(int zone)` method returning 4 corner Offsets in camera-space
- **`lib/screens/live_object_detection/widgets/calibration_overlay.dart`** -- Added `highlightZone` parameter + `_paintZoneHighlight()` for yellow semi-transparent zone fill
- **`lib/screens/live_object_detection/live_object_detection_screen.dart`** -- Wired `ImpactDetector`, added: large centered result overlay (72px zone number or "MISS"), status text badge (bottom-right), zone highlight via `CalibrationOverlay`, "Ball lost" badge suppression during result phase, `forceReset()` on calibration and dispose

### UI Refinement
- Moved status text badge from bottom-center to **bottom-right** (`Positioned bottom:16, right:16`)
- Moved calibration instruction text from bottom-center to **bottom-right** (`Positioned bottom:16, right:16`)
- Reason: bottom-center labels were blocking the camera view during active use

### Device Testing
- Tested on iPhone 12 and Galaxy A32 using penalty shoot video on laptop
- All features confirmed: MISS labels, zone hit numbers, yellow highlight, tracking status, 3-second auto-reset
- Bottom-right label positioning confirmed comfortable on both devices

### Verification
```
$ flutter analyze -- 0 errors, 0 warnings, 0 infos
$ flutter test -- 70/70 passing
```

---

## Code Quality Cleanup (2026-02-23)

## Summary

Resolved all 7 `flutter analyze` issues (0 remaining) and 1 failing test (now 3 passing).

## Changes by File

### lib/main.dart
- **Removed iOS diagnostic probe** (lines 23–34) — temporary `try/catch` block that attempted to load `yolo11n.tflite` from Flutter assets on iOS. This was documented technical debt in `activeContext.md`; it always failed by design and produced noisy logs. The real iOS model loads via the Xcode bundle separately.
- **Replaced `print()` with `log()`** (line 21) — `print('DETECTOR_BACKEND = $backend')` changed to `log(...)` from `dart:developer` to satisfy `avoid_print` lint.
- **Removed unused imports** — `dart:io` and `package:tflite_flutter/tflite_flutter.dart` were only used by the diagnostic probe.

### lib/screens/home/home_screen_store.dart
- **Added lint suppression** — `// ignore_for_file: library_private_types_in_public_api` at file top. This is the standard MobX code-gen pattern (`class HomeScreenStore = _HomeScreenStore with _$HomeScreenStore`) and cannot be restructured without breaking the MobX mixin.

### lib/screens/live_object_detection/live_object_detection_screen.dart
- **Replaced deprecated `withOpacity()`** (lines 187, 210) — `Colors.white.withOpacity(0.3)` changed to `Colors.white.withValues(alpha: 0.3)` on both the gallery and flip-camera buttons. The `withOpacity` API was deprecated in favour of `withValues` to avoid precision loss.
- **Replaced `print()` with `log()`** (line 291) — camera preview size debug output changed from `print` to `dart:developer` `log()` to satisfy `avoid_print` lint.

### test/widget_test.dart
- **Replaced stale counter app test** with meaningful `DetectorConfig` unit tests:
  1. Verifies default backend is `tflite` when no `DETECTOR_BACKEND` env var is set
  2. Verifies label returns `'TFLite'` for the default backend
  3. Verifies the `DetectorBackend` enum contains all expected values (`tflite`, `yolo`, `mlkit`)
- The previous test pumped `MyApp` and asserted counter widget text that doesn't exist in this app. The new tests verify actual project logic without triggering HTTP calls or native plugin dependencies.

## Verification

```
$ flutter analyze
Analyzing object_detection...
No issues found! (ran in 2.2s)

$ flutter test
00:02 +3: All tests passed!
```
