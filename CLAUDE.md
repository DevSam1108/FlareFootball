# CLAUDE.md -- Flare Football Object Detection POC

## Session Start Instructions

When beginning a new session on this project, do the following **before touching any code**:

1. Read `memory-bank/activeContext.md` -- this is the ground truth for what is currently in progress, what is known to be broken, and what decisions are pending.
2. Read `memory-bank/progress.md` -- understand what is complete, what is incomplete, and the open evaluation checklist.
3. Confirm the model files are in place before doing anything YOLO-related:
   - Android: `android/app/src/main/assets/yolo11n.tflite` (must be manually placed)
   - iOS: `ios/yolo11n.mlpackage` (must be manually placed and confirmed in Xcode)
4. Run `flutter pub get` if packages appear out of date.

---

## Session End Instructions

Before ending a session, update the memory-bank to preserve state:

1. **`memory-bank/activeContext.md`** -- update "Current Focus", "What Is Partially Done", and "Immediate Next Steps".
2. **`memory-bank/progress.md`** -- tick off anything completed; add new incomplete items.
3. **`memory-bank/systemPatterns.md`** -- update if any new architectural patterns were introduced.
4. **Never run `git commit` or `git push`** -- this project has no git repository. It is local-only by developer decision.

---

## Project Overview

**Name:** Flare Football -- On-Device Object Detection (Feasibility POC)

**Status:** PRODUCTION-BOUND — no longer a throwaway POC. Core feasibility proven. Codebase is being carefully built toward production quality.

**Purpose:** This project builds the on-device soccer ball detection and zone tracking feature for the Flare Football product. It uses YOLO11n for real-time ball detection on mobile devices. The codebase will be reviewed, refactored, and cleaned once 100% zone accuracy is achieved — then it moves to the next stage. All solutions must be production-grade, not short-term workarounds.

**Core Research Questions (All Answered YES):**
- Can YOLO11n (nano) run in real-time on mobile without unacceptable latency or battery impact?
- Is the custom-trained model accurate enough to reliably detect soccer balls in pitch/game conditions?
- Does the Flutter + `ultralytics_yolo` integration work on both Android (TFLite) and iOS (Core ML) with acceptable performance parity?
- Is landscape-mode camera orientation suitable for the detection use case?

**Target Test Devices:**
- iOS: iPhone 12 (A14 Bionic, iOS 17.1.2)
- Android: Realme 9 Pro+ (Snapdragon 695) — replaced Galaxy A32 (SM-A325F)

**Dev Environment:**
- MacBook Pro (Apple M5, 16GB RAM, macOS Tahoe 26.0)
- Flutter 3.38.9 / Dart 3.10.8
- Xcode 26.2 / CocoaPods 1.16.2
- VS Code 1.109.1 / Android SDK 36.1.0

---

## Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter (Dart) -- SDK `>=3.2.3 <4.0.0` |
| ML Backend | YOLO11n via `ultralytics_yolo: ^0.2.0` |
| Android model format | TensorFlow Lite (`.tflite`) |
| iOS model format | Apple Core ML (`.mlpackage`) |
| Audio | `audioplayers: ^6.1.0` (zone callouts + miss buzzer) |
| Sensors | `sensors_plus: ^6.1.0` (rotate-to-landscape overlay) |
| Permissions | `permission_handler: ^11.3.1` (camera permission request) |
| File access | `path_provider: ^2.1.3` (Documents directory for DiagnosticLogger CSV) |
| Sharing | `share_plus: ^10.0.0` (Share Log CSV export via system share sheet) |
| Navigation | `NavigationService` singleton wrapping Navigator |

---

## Architecture Rules

### 1. YOLO-Only Detection Pipeline

The app uses a single YOLO detection pipeline. The `DETECTOR_BACKEND` environment variable infrastructure is preserved for future extensibility but currently only `yolo` is implemented.

```
DETECTOR_BACKEND=yolo  -> YOLOView widget (ultralytics_yolo) -- only backend
```

Backend selection flows through `lib/config/detector_config.dart`. The `DetectorBackend` enum currently has only `yolo`. To add a new backend in the future, extend the enum and add cases to the switch statements in `detector_config.dart` and `main.dart`.

### 2. Singleton Pattern for Services

`NavigationService` and `SnackBarService` are singletons using a private named constructor pattern. New services should follow the same pattern.

### 3. Platform-Aware Model Path for YOLO

The YOLO model path is always resolved as:
```dart
modelPath: Platform.isIOS ? 'yolo11n' : 'yolo11n.tflite'
```
iOS loads from the Xcode bundle (Core ML). Android loads from `android/app/src/main/assets/`. Do not change this pattern without understanding the platform constraints.

### 4. Landscape Orientation Lock for YOLO Screen

The `LiveObjectDetectionScreen` forces landscape orientation in `initState` and must restore portrait+landscape in `dispose`. Never remove the restore call -- it will lock the whole app to landscape permanently. `_tracker.reset()` is called in `dispose` before orientation restore.

---

## Key File Map

| Concern | File |
|---|---|
| Entry point + backend init | `lib/main.dart` |
| Backend enum + config | `lib/config/detector_config.dart` |
| Route definitions | `lib/values/app_routes.dart`, `lib/routes.dart` |
| App root | `lib/app.dart` |
| YOLO live screen | `lib/screens/live_object_detection/live_object_detection_screen.dart` |
| Ball trail painter | `lib/screens/live_object_detection/widgets/trail_overlay.dart` |
| Calibration overlay | `lib/screens/live_object_detection/widgets/calibration_overlay.dart` |
| Rotate-to-landscape overlay | `lib/screens/live_object_detection/widgets/rotate_device_overlay.dart` |
| **ByteTrack tracker (NEW)** | `lib/services/bytetrack_tracker.dart` |
| **Ball identifier (NEW)** | `lib/services/ball_identifier.dart` |
| Trail position model | `lib/models/tracked_position.dart` |
| YOLO coordinate utilities | `lib/utils/yolo_coord_utils.dart` |
| Homography transform (DLT) | `lib/services/homography_transform.dart` |
| Target zone mapper (1-9) | `lib/services/target_zone_mapper.dart` |
| Impact detector (state machine) | `lib/services/impact_detector.dart` |
| Impact event model | `lib/models/impact_event.dart` |
| Kick detector (4-state gate) | `lib/services/kick_detector.dart` |
| ~~Ball tracker service~~ (SUPERSEDED) | `lib/services/ball_tracker.dart` — replaced by ByteTrack, pending deletion |
| ~~Kalman filter (4-state)~~ (SUPERSEDED) | `lib/services/kalman_filter.dart` — replaced by 8-state Kalman in ByteTrack |
| ~~Trajectory extrapolator~~ (SUPERSEDED) | `lib/services/trajectory_extrapolator.dart` — subsumed by Kalman prediction |
| ~~Wall-plane 3D predictor~~ (SUPERSEDED) | `lib/services/wall_plane_predictor.dart` — depth tracked in ByteTrack Kalman |
| Diagnostic CSV logger | `lib/services/diagnostic_logger.dart` |
| Audio feedback service | `lib/services/audio_service.dart` |
| Audio assets (TTS + cheer) | `assets/audio/zone_1-9.m4a`, `assets/audio/miss.m4a` |
| Audio originals backup | `assets/audio/originals/zone_1-9.m4a` (plain number callouts) |
| Home screen (launch page) | `lib/screens/home/home_screen.dart` |
| Navigation service | `lib/services/navigation_service.dart` |
| Snackbar service | `lib/services/snackbar_service.dart` |
| Android rotation channel | `android/app/.../MainActivity.kt` |
| Issue log | `memory-bank/issueLog.md` |
| Decision log (ADRs) | `memory-bank/decisionLog.md` |
| Field test analysis (2026-04-04) | `memory-bank/field-test-analysis-2026-04-04.md` |
| **Anchor Rectangle feature plan (NEW 2026-04-17)** | `memory-bank/anchor-rectangle-feature-plan.md` — full 5-phase design doc; Phases 1–3 + 5 implemented (Phase 4 skipped). Phase 5 = audio announcements (tap-prompt + "Ball in position") + 2 follow-up bug fixes (ISSUE-032, ISSUE-033). All four Phase 5 commits iOS-verified on iPhone 12. Android pending. |
| Pre-change code snapshots | `memory-bank/snapshots/` (backup copies before risky edits) |
| **Debug bbox overlay** | `lib/screens/live_object_detection/widgets/debug_bbox_overlay.dart` |
| **Dashed line helper (NEW 2026-04-20)** | `lib/utils/canvas_dash_utils.dart` — shared `drawDashedLine` used by calibration center crosshair and anchor rectangle overlay |
| **Anchor rectangle painter (NEW 2026-04-20)** | `_AnchorRectanglePainter` (private class inside `lib/screens/live_object_detection/live_object_detection_screen.dart`) — magenta dashed 2 px stroke, no fill; paints `_anchorRectNorm` after lock |

---

## Build Commands

### Run (YOLO -- default and only backend)
```bash
flutter run --dart-define=DETECTOR_BACKEND=yolo
# or simply:
flutter run
```

### Get dependencies
```bash
flutter pub get
```

### Run linter
```bash
flutter analyze
```

### Run tests
```bash
flutter test
```

### Build iOS (release)
```bash
flutter build ios --dart-define=DETECTOR_BACKEND=yolo
```

### Build Android (release)
```bash
flutter build apk --dart-define=DETECTOR_BACKEND=yolo
```

---

## Model File Setup (Required -- Must Be Placed Manually)

These binary files must be placed manually on the developer machine.

**Android:**
```bash
mkdir -p android/app/src/main/assets
cp /path/to/yolo11n.tflite android/app/src/main/assets/
```

**iOS:**
1. Copy `yolo11n.mlpackage` into the `ios/` directory.
2. Open `ios/Runner.xcworkspace` in Xcode.
3. Confirm `yolo11n.mlpackage` appears under Runner -> Build Phases -> Copy Bundle Resources.
   (Xcode reference `9883D8872F43899800AEC4E1` already exists -- you are confirming the file is physically present, not re-adding the reference.)

---

## What Never to Touch Without Asking

The following require explicit discussion before changes are made:

1. **`lib/config/detector_config.dart`** -- Changes here affect the backend-switching system. Altering the enum or environment variable key breaks the pipeline.

2. **`ios/Runner.xcodeproj/project.pbxproj`** -- The Xcode project file. Manual edits here frequently corrupt the project. Only modify via Xcode UI.

3. **`android/app/src/main/AndroidManifest.xml`** -- `hardwareAccelerated="true"` and `launchMode="singleTop"` are set deliberately. Do not remove them.

4. **Orientation logic in `live_object_detection_screen.dart`** -- The `SystemChrome.setPreferredOrientations` calls in `initState` and `dispose` are a matched pair. Removing or reordering them locks the whole app to a single orientation permanently.

5. **`pubspec.yaml` dependency versions** -- `ultralytics_yolo` is at `^0.2.0`. Do not upgrade without testing on both platforms.

6. **`ios/yolo11n.mlpackage` and `android/app/src/main/assets/yolo11n.tflite`** -- These are custom-trained models specific to this project (3 classes: `Soccer ball`, `ball`, `tennis-ball`). Do not replace with a generic COCO model without flagging the change -- all evaluation data would be invalidated.

7. **`android/app/build.gradle` -- `aaptOptions { noCompress 'tflite' }`** -- Removing this causes Gradle to compress the TFLite model, breaking inference on Android. This was the root cause of `onResult` silence on Android.

8. **`memory-bank/` directory** -- These files are the project's institutional memory. Do not delete, rename, or restructure without explicit instruction.

9. **`ios/Podfile` -- `PERMISSION_CAMERA=1` macro** -- Required by `permission_handler` to compile camera permission code on iOS. Removing this causes `Permission.camera.request()` to silently return `.denied` without showing a dialog. The camera will not work on fresh installs.

---

## Known Issues and Technical Debt

| Issue | Status | Notes |
|---|---|---|
| **Target circle false positives (ISSUE-022)** | **🟢 MITIGATED BY PHASE 3 (2026-04-22)** | **Anchor Rectangle Phase 3 spatial filter drops target-circle FPs at `_toDetections` before ByteTrack — confirmed in iPhone 12 field test on every frame. Physical removal no longer required. ISSUE-022 remains open formally until Android-verified and accuracy re-measured without upstream noise.** |
| **Zone accuracy: one-row-down bias (Bug 3)** | **🟢 PATH A APPLIED 2026-04-28 — partially validated** | **Two firing mechanisms diagnosed (velocity-drop + state-flip lost-frame, see ISSUE-034). Path A: disabled velocity-drop trigger (ADR-083) and made `_onBallMissing` also update zone/position/bbox state (ADR-084). One state-flip kick (1→6→7, hit zone 7) field-validated post-fix on iPhone 12 — pre-fix announced zone 1, post-fix announces zone 7. Velocity-drop scenario validation still owed.** |
| **Premature announcements** | **🟢 PATH A APPLIED 2026-04-28 — partially validated** | **Same bug as zone accuracy above; same fix. Velocity-drop trigger that fired at trackFrames=4–5 with `depthRatio≈0.45` is now disabled. Decisions fire only via edge-exit, lost-frame trigger, or maxTrackingDuration (3 s). Original code preserved for reversibility.** |
| iOS `NSCameraUsageDescription` placeholder | Minor | `"your usage description here"` in `Info.plist`. Must update before any external build. |
| `tennis-ball` priority 2 in class filter | Minor | Diagnostic concession from Phase 9. `Soccer ball` detects correctly; `tennis-ball` filter is unnecessary but harmless. |
| Free Apple Dev cert expires every 7 days | Known | Re-run `flutter run` to re-sign. If "Unable to Verify" appears, delete app and reinstall. See `memory-bank/issueLog.md` ISSUE-002. |
| Off-by-one: `maxActiveMissedFrames=5` == `lostFrameThreshold=5` | Bug 2 — less critical | KickDetector closes gate on same frame ImpactDetector would trigger from ball loss. Less impactful now that result gate accepts `confirming` state. |
| False positive YOLO detections on non-ball objects (kicker body) | **🟢 MITIGATED BY PHASE 3 (2026-04-22)** | **Phase-aware `_applyPhaseFilter()` (2026-04-01) + pre-ByteTrack AR > 1.8 filter (2026-04-13, ADR-068) eliminated torso (AR 2.4-3.6). Player head (AR 0.9, geometrically identical to ball) was the residual gap — now spatially filtered during waiting state by the Phase 3 anchor-rectangle filter (any detection outside `_anchorRectNorm` is dropped before ByteTrack). Residual exposure only during kick flight (filter OFF), which is a much narrower window. Re-evaluate after Android parity verification.** |
| Bounce-back false detection | **🟢 MITIGATED BY PHASE 3 (2026-04-22)** | YOLO detects ball on rebound after a decision. Phase 3 re-arms `_anchorFilterActive = true` on the same frame the IMPACT DECISION block fires (both accept and reject branches, `live_object_detection_screen.dart:1091` and `:1134`). The bounce-back ball is flying away from the wall — its bbox center is nowhere near the anchor rectangle — so its detections are dropped at `_toDetections` and never reach ByteTrack / KickDetector. WallPredictor is reset on the same line. Re-evaluate after Android parity verification. |
| Ball identifier false re-acquisition | **🟢 MITIGATED BY PHASE 3 (2026-04-22)** | Phase 3 spatial filter is ON during all waiting states; only detections whose bbox center is inside `_anchorRectNorm` reach ByteTrack. Player walking outside the rect, target circles at fixed banner positions, posters etc. can no longer feed BallIdentifier during idle. Same mechanism as the bounce-back row above. Re-evaluate after Android parity verification. |
| Kick-state gate on ImpactDetector — REVERTED | REVERTED (2026-04-08) | Attempted gating ImpactDetector/WallPredictor behind KickDetector. Broke grounded kicks (3/5 undetected). KickDetector's jerk threshold too aggressive for low-velocity shots. See ISSUE-025, ADR-061. |
| Trail dots on non-ball objects | **🟡 PARTIALLY FIXED (2026-04-15)** | **Session lock + trail suppression eliminates idle-period false dots. Dots only shown during confirming/active/refractory. Previous trail-gating attempt (ISSUE-024, ADR-062) killed ALL visualization; new approach preserves kick visualization. See ADR-069, ADR-070.** |
| Phantom impact decisions during idle | Log pollution | ImpactDetector fires decisions during kick=idle. NOT announced (KickDetector result gate works). Diagnostic log noise only. Kick-state gate attempted and reverted. |
| **Mahalanobis rescue identity hijacking (ISSUE-026)** | **🟡 PARTIALLY FIXED (2026-04-16)** | **Bbox area ratio check using last-measured-area with 2.0/0.3 threshold (ADR-072). Blocks hijacking (3.8x-9x jumps) while allowing ball shrinking during flight. 5/5 kicks tracked across 3 test runs. False positive dots during active kicks still appear.** |
| **~~isStatic flag never clears (ISSUE-027)~~** | **✅ FIXED (2026-04-13)** | **Replaced lifetime cumulative displacement with sliding window (last 30 frames). `isStatic` now two-way. Device-verified.** |
| **directZone unreliable for non-bottom zones** | **🟢 PATH A APPLIED 2026-04-28** | **Resolved by ADR-084 (`_onBallMissing` now updates `_lastDirectZone` from Kalman-predicted positions). Pre-fix `_lastDirectZone` froze at the entry zone; post-fix it tracks the ball's actual progression through the grid. State-flip kick verified zone 7 announcement post-fix.** |
| **2-layer false positive filter (ISSUE-028)** | **❌ REVERTED (2026-04-13)** | **DetectionFilter + TrackQualityGate + Mahalanobis rescue validation. Init delay broke BallIdentifier re-acquisition. Player head (ar:0.9) unfilterable with geometry. Must implement ONE filter at a time. Start with Mahalanobis rescue validation only.** |
| **~~Bbox area ratio check too aggressive (ISSUE-029)~~** | **✅ FIXED (2026-04-16)** | **Last-measured-area with 2.0/0.3 threshold. Uses real measurement instead of drifting Kalman predicted area. 5/5 kicks across 3 test runs. See ADR-072.** |
| **Session lock stuck ON (ISSUE-030)** | **🟢 MITIGATED BY PHASE 3 (2026-04-22) — verification owed** | **Phase 3 added two recovery paths for the stuck-lock scenario: (a) idle-edge `else if` at `live_object_detection_screen.dart:1013` — when a flickered/false kick returns to `KickState.idle` without firing a decision, `_anchorFilterActive` is re-armed and `_ballId.deactivateSessionLock()` is called; (b) 2 s safety timer at `:1008` — if no decision fires within 2 s of the OFF-trigger, `_onSafetyTimeout` clears the lock. Path A (2026-04-28) may also have closed the residual case (genuine kick that never fires a decision) by ensuring `_lastDirectZone` stays fresh through state-flip frames, so lost-frame trigger can fire reliably. One verification log of the original bounce-back scenario still owed to formally close.** |
| **~~Back button unreachable during calibration / awaiting reference capture (ISSUE-031)~~** | **✅ FIXED (2026-04-19)** | **Z-order bug: back-button `Positioned` block rendered BEFORE two full-screen `GestureDetector`s, so the arena claimed taps on the button. Fixed by moving the `Positioned` block to render AFTER both detectors (before rotate overlay). iOS-verified on iPhone 12. See ADR-074, ISSUE-031.** |
| **~~Tap-prompt audio stuck silent after State 3→2 transition (ISSUE-032)~~** | **✅ FIXED (2026-04-24)** | **Audio nudge timer was keyed on candidate-presence transitions only; tap+flicker scenario silently cleared selection (Decision B-i) but `hadCandidates == hasCandidates` so no restart fired. Fixed by adding a third mutually-exclusive `else if` branch covering the State 3→2 transition. iOS-verified on iPhone 12. See ADR-081, ISSUE-032.** |
| **~~"Ball in position" audio fires on rolling ball (ISSUE-033)~~** | **✅ FIXED (2026-04-24)** | **Phase 5 trigger condition was purely geometric, fired on the brief frames a rolling ball's center crossed the rect. Fixed by adding `&& ball.isStatic` (ByteTrack's sliding-30-frame staticness flag) as a fourth clause to the `inPosition` conjunction. ~1 s warm-up delay accepted. See ADR-082, ISSUE-033.** |
| **Piece A eating real kicks (ISSUE-035)** | **🟠 OPEN — accepted as-is for now (user decision 2026-04-29)** | **`_makeDecision` gates on instantaneous `_currentKickState == KickState.idle` and resets. Field log 2026-04-29 showed a real zone-6 kick suppressed: KickDetector transitioned `confirming → idle` one frame before ImpactDetector's lost-frame trigger fired (race with Phase 3 idle-edge recovery). Gate could be widened to track historical "kickConfirmedDuringTracking" flag — designed, NOT applied. **User accepted Piece A as net win for the common case** (idle-jitter phantoms reliably suppressed); the edge-case kick-drop is rare. Widening = future work. See ADR-086, ISSUE-035.** |
| **"Ball in position" audio cadence broken (ISSUE-036)** | **🟠 OPEN — root-caused 2026-04-29, fix designed not applied** | **`else` branch (now at lines ~982-983 inside priority-2 fall-through after multi-object combined-block restructure) resets `_lastBallInPositionAudio = null` on any `inPosition=false` frame, including single-frame YOLO misses. 10-second cadence almost never holds in practice; user heard double-fires within 4 s. Fix: delete the `else` AND add `_lastBallInPositionAudio = null` inside the filter OFF block at line ~1006 (only resets cadence on real kick attempts, not on transient flickers). See ISSUE-036.** |
| **Foot/non-ball locked as ball cascade (ISSUE-037)** | **🟠 OPEN — root-caused 2026-04-29, fix discussed not applied** | **BallIdentifier's `nearest_non_static` re-acquisition has no shape gate for elongated-vertical objects. AR < 0.6 (foot/shoe) and AR ≈ 0.9 (player head, see ISSUE-028) pass through. Lock onto a foot triggers a full false-kick cascade: KickDetector confirms → ImpactDetector stuck for 60 frames (no zone, no edge-exit, no missed frames) → safety-timeout race fires repeatedly → `ball_in_position` audio for what's actually a foot. Cone at kick spot is a separate decoy that contributes during waiting state (dual-classed as Soccer ball + tennis-ball). Fix: tighten shape gate to reject `ar < 0.6 || ar > 1.5` during `nearest_non_static`. See ISSUE-037.** |
| **ImpactDetector trigger gap — only fires on lost-frame or edge-exit, never positively at impact (ISSUE-038)** | **🟠 OPEN — architectural finding 2026-04-29** | **No positive trigger for "ball reached the wall and stopped." All current triggers are negative (something must STOP — ball lost, ball off-screen). If ball stays in `[DETECTED]` continuously, decision fires very late and with WRONG zone (overwritten during bounce-back as ball traverses zones on its way down). Real-world physics usually saves the system (motion blur near impact + flying off-screen produces missed frames at impact), but slow grounded kicks and FP-stuck-tracker scenarios both fail. Proposed fix: add positive trigger `directZone != null && ball.isStatic && trackFrames > N` during tracking phase. NOT applied. See ISSUE-038.** |
| **Audio kick gate too narrow — rejects refractory** | **🟠 OPEN — fix designed not applied** | **Gate at `live_object_detection_screen.dart:1133–1134` accepts only `confirming || isKickActive`. Refractory rejected → reject branch calls `_impactDetector.forceReset()` → result wiped before UI rebuild. Real kicks landing decisions during refractory (FP-stuck-tracker scenarios — see ISSUE-038) are eaten. Phase 3 already prevents bounce-back, so the original justification for the narrow gate is partially redundant. One-line fix: add `\|\| state == KickState.refractory` to the accept condition. NOT applied.** |
| **Multi-object cleanup audio nudge (ADR-087)** | **🟡 IMPLEMENTED BUT DISABLED 2026-04-29** | **`playMultipleObjects()` method, `_lastMultipleObjectsAudio` field, priority-gated combined audio block, audio asset all in place. After applying, user suspected the new code was dropping kicks during field test; disabled via single-line `if (false)` guard at the priority-1 condition. Original condition preserved as inline comment. Field/method/asset/resets stay as harmless dead code while disabled. To re-enable: restore the original condition (one-line edit). See ADR-087.** |

> **Full issue history:** See `memory-bank/issueLog.md` for all issues with root causes and verified solutions.

### Active feature branch — Anchor Rectangle (2026-04-17 onwards)
Phase 1 (Tap-to-Lock Interaction) implemented 2026-04-19. Phase 2 (Rectangle Computation & Display) implemented 2026-04-20. **Phase 3 (Rectangle Filter During Waiting State) implemented 2026-04-22** — spatial filter now drops outside-rect detections at `_toDetections` before ByteTrack, with ON/OFF state machine tied to KickDetector state and a 2 s safety timeout for stuck-decision recovery. **Phase 3 polish landed same day (2026-04-22):** (a) `else if` idle-edge recovery re-arms filter when kick flickers to idle without a decision (closes the 2 s dead window on false-alarm flickers), (b) the orange "flickering dot" on the resting ball is re-enabled — now only during idle + ball inside rect + filter armed, so no FP dots on player bodies, (c) `DIAG-ANCHOR-FILTER` logs passed/dropped detections with bbox size every frame the filter is ON, not just on drops. **Phase 4 (Return-to-Anchor) evaluated and SKIPPED as a standalone phase (2026-04-22)** — its mechanics are already implicit in Phase 3 + Mahalanobis rescue; only genuinely-new deliverable (audio nudge "ball far, bring closer") folded into Phase 5. **Phase 5 (Audio Announcements) implemented 2026-04-23 → 2026-04-24** in four atomic commits — tap-prompt asset wiring, `playBallInPosition()` + screen inline trigger via timestamp-in-loop pattern (ADR-080, no Timers), State 3→2 audio nudge restart bug fix (ADR-081 / ISSUE-032), and `isStatic` gate on "Ball in position" so a ball rolling through the rect doesn't trigger (ADR-082 / ISSUE-033). User tuned cadence to 10 s and shortened the audio phrase to just "Ball in position" on 2026-04-24. **Phase 5 audio scope reduced from three prompts to two** — the "Ball far, bring closer" nudge is deferred pending field evidence it's needed (ADR-079). All four Phase 5 commits iOS-verified on iPhone 12. Android (Realme 9 Pro+) pending across all phases. See `memory-bank/anchor-rectangle-feature-plan.md`, `memory-bank/decisionLog.md` ADR-073 (Phase 1) + ADR-076 (Phase 2) + ADR-077 (Phase 3) + ADR-078 (Phase 3 polish + Phase 4 skip) + **ADR-079 / ADR-080 / ADR-081 / ADR-082 (Phase 5)**.

**Phase 3 implementation policy (important for future feature work):** additive-only edits to working code. New fields, new blocks adjacent to existing ones, new private methods — but never modify working lines unrelated to the feature's purpose (e.g., no drive-by refactors, no DRY-ing duplicated conditions). Accept small duplication; clean up as a separate single-purpose change later. Codified in user memory as `feedback_no_refactor_bundling.md`.

Key API change from Phase 1: `BallIdentifier.setReferenceTrack(List<TrackedObject>)` → `setReferenceTrack(TrackedObject)`. The caller (screen) now filters and selects; `BallIdentifier` just locks onto whatever track it receives. If adding new call sites, pass a single `TrackedObject`, not a list.

Phase 2 notes: the anchor rectangle is purely visual this phase — no detection filtering. Size is bbox-relative (`3× bbox.width × 1.5× bbox.height` of the locked ball), **not** a cm-based conversion. The earlier "60×30 cm" plan wording was superseded because it implicitly assumed a fixed ball diameter, which violates the project-wide "ball size is not fixed" rule. Center is frozen at lock; screen-axis-aligned; magenta dashed. State lives on the screen as `Rect? _anchorRectNorm`. If extending in Phase 3+, reuse this state and the existing `drawDashedLine` helper in `lib/utils/canvas_dash_utils.dart`.

---

## Detection Classes (Custom YOLO11n Model)

| Class | Notes |
|---|---|
| `Soccer ball` | Primary target |
| `ball` | General ball; also fires on soccer balls |
| `tennis-ball` | Incidental; accepted at lowest priority |

Labels are **embedded in the model** -- there is no external label file for the YOLO path.

---

## Pending Code-Health Work (NOT in this phase, but track here so it isn't forgotten)

### `lib/services/impact_detector.dart` — simplification candidate (logged 2026-04-28)

The `ImpactDetector` class has accumulated complexity from multiple architecture revisions (raw-YOLO era → ByteTrack era → anchor-rectangle era). The current shape — `processFrame` branches on `ballDetected` into two paths (`_onBallDetected` / `_onBallMissing`) that update different state and have different trigger conditions — was meaningful when there was no tracker between YOLO and the impact detector ("missing" = ball gone). With ByteTrack now always returning either a real match or a Kalman-predicted position, the binary `ballDetected` flag mostly reflects ByteTrack's internal state-machine detail (`tracked` vs `lost`) rather than anything about the ball's actual presence — which made today's accuracy bug (kicks 1 & 3, 2026-04-27 evening test) hard to reason about.

**Path A bug fix (applied 2026-04-28)** kept the two-branch structure and just made `_onBallMissing` also update `_lastDirectZone`, `_lastRawPosition`, and `_lastBboxArea` from passed-through values (Change 1 + Option A extension), plus disabled the velocity-drop trigger (Change 2). Surgical, easy to validate, easy to revert. Does NOT clean up the underlying complexity. One state-flip kick field-validated post-fix on iPhone 12 (1→6→7 trajectory now correctly announces zone 7); velocity-drop scenario validation pending. See ADR-083, ADR-084, ADR-085.

**Path B (deferred — do this when there's room for a focused refactor):**
- Consider replacing the two-branch split with a single unconditional state-update path: every frame, update `_lastDirectZone`, `_lastBboxArea`, `_lastRawPosition` from whatever the screen passed (with the existing null-checks), then evaluate "kick is over" predicates (edge exit, lost-frame threshold, max tracking duration, ball-came-to-rest). No artificial `_onBallDetected` / `_onBallMissing` branching. Closer to ~40–60 lines net change in `impact_detector.dart`.
- At minimum, even without a full refactor: delete or comment out the dead/superseded fields and signals that are still computed and stored every frame but never consulted at decision time — `_lastWallPredictedZone`, `_lastDepthVerifiedZone`, `_bestExtrapolation`, the `_velocityHistory` accumulator. Also revisit the depth-verified zone logic (depth thresholds 0.7–1.3 don't match behind-kicker geometry — `depthRatio` is structurally always < 0.5 at the wall, so the verified-zone path never activates).
- Coordinate with the broader "pending deletion" work flagged in the Key File Map for `wall_plane_predictor.dart`, `trajectory_extrapolator.dart`, `kalman_filter.dart`, `ball_tracker.dart` — those services feed the dead signals above, so removing them together is the natural unit.

**Validation rule for Path B (or any future refactor of `ImpactDetector`):** before merging, capture ≥5 monitor-video kicks with the existing `DIAG-IMPACT [DETECTED]` / `[MISSING]` per-frame trace + `IMPACT DECISION` block + `AUDIO-DIAG`. Compare pre/post traces frame-by-frame. Pass criterion: `_lastDirectZone` at decision time matches the visually observed impact zone for every kick, and the trigger fires after the ball has actually transited the grid (not at trackFrames=4–5). Same protocol that proved Path A.

---

## What Is Out of Scope (Current Phase)

Do not introduce these unless explicitly instructed:

- User authentication, accounts, or sessions
- Uploading or persisting detection results to a server
- Server-side / cloud inference
- Video recording or playback
- Screens beyond what the current flow requires
