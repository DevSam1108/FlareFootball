# Progress

> **⚠️ CRITICAL: NEVER run `git commit`, `git push`, `git init`, or any git write commands. This project has NO git repository. It is local-only by explicit developer decision. This rule is ABSOLUTE and has been violated in the past — do NOT repeat.**

## What Has Been Built and Works

### Core Infrastructure
- ✅ Flutter project scaffolded with multi-platform support (iOS, Android, macOS, Windows, Linux, Web)
- ✅ `DETECTOR_BACKEND` environment variable system for build-time backend switching (currently YOLO-only; extensible for future backends)
- ✅ Two-screen navigation structure (Home -> Live Camera)
- ✅ Singleton service pattern for navigation and snackbar services
- ✅ `CLAUDE.md` in repo -- comprehensive session instructions, build commands, architecture rules
- ✅ `/update-memory` slash command in `.claude/commands/`
- ✅ 6 specialist Claude agents in `.claude/agents/` (untracked)
- ✅ GSD planning infrastructure: `.planning/` with `ROADMAP.md`, `REQUIREMENTS.md`, `MILESTONES.md`, `STATE.md`, `PROJECT.md`

### Code Quality
- ✅ `flutter analyze` -- 0 errors, 0 warnings, 85 infos (2026-04-19 after full /update-memory verification run; infos are all pre-existing style lints in services/tests plus the intentional `print` stub in `audio_service.playTapPrompt`)
- ✅ `flutter test` -- 175/175 passing (2026-04-19; was 176, net −1 from rewriting 4 obsolete `BallIdentifier.setReferenceTrack` auto-pick-largest tests into 3 new contract tests for the new `setReferenceTrack(TrackedObject)` API introduced in Anchor Rectangle Phase 1)
- ✅ `withOpacity()` replaced with `withValues(alpha:)` (deprecated API migration)
- ✅ DIAG-02/03/04/05 temporary diagnostic print statements removed (2026-03-09)
- ✅ Diagnostic `print()` statements in `ImpactDetector._makeDecision()` intentionally retained for real-world testing analysis

### YOLO11n Integration
- ✅ `ultralytics_yolo: ^0.2.0` package integrated as sole ML dependency
- ✅ `YOLOView` widget in `LiveObjectDetectionScreen` -- YOLO-only (no SSD branch)
- ✅ Platform-aware model path: `'yolo11n'` (iOS) vs `'yolo11n.tflite'` (Android)
- ✅ `YOLOTask.detect` configured correctly for bounding box detection
- ✅ `onResult` callback wired with `mounted` guard and `_pickBestBallYolo` helper
- ✅ **`onResult` confirmed firing on BOTH platforms** -- iOS (iPhone 12) and Android (Galaxy A32)
- ✅ `showOverlays: false` confirmed working -- suppresses native bounding boxes
- ✅ Xcode project file updated with `yolo11n.mlpackage` resource reference
- ✅ Landscape-only orientation enforced for YOLO mode in `initState`
- ✅ Orientation properly restored on screen `dispose` (with `_tracker.reset()` call)
- ✅ ~~Backend label indicator overlay ("YOLO" text badge top-left)~~ Replaced with back button badge (2026-03-11)

### Ball Trail (Phase 7)
- ✅ **`TrackedPosition`** (`lib/models/tracked_position.dart`) -- immutable value type
- ✅ **`YoloCoordUtils`** (`lib/utils/yolo_coord_utils.dart`) -- shared FILL_CENTER crop offset math; camera AR = 4:3
- ✅ **`BallTracker`** (`lib/services/ball_tracker.dart`) -- bounded 1.5s `ListQueue`, occlusion sentinels, 30-frame auto-reset, min-distance dedup
- ✅ **`TrailOverlay`** (`lib/screens/live_object_detection/widgets/trail_overlay.dart`) -- fading orange dots, connecting lines, occlusion gap skipping
- ✅ **Class priority filtering** -- `{'Soccer ball': 0, 'ball': 1, 'tennis-ball': 2}`, accepts all three ball classes
- ✅ **Nearest-neighbor tiebreaker** -- uses `_tracker.lastKnownPosition` for multi-detection frames
- ✅ **Device-verified** on iPhone 12 (4 test recordings, 42 frames). **Visually confirmed** on Galaxy A32 (2 recordings, 39 frames).

### "Ball lost" Badge (Phase 8)
- ✅ **`BallTracker.isBallLost`** -- threshold: 3 consecutive missed frames (approx 100 ms at 30 fps)
- ✅ **Badge widget** -- `Positioned(top: 12, right: 12)`, red background, white bold "Ball lost" text
- ✅ **Device-verified** on iPhone 12 and **visually confirmed** on Galaxy A32 -- appears when ball exits frame, clears on re-detection

### v1.1 Milestone Archived
- ✅ All 3 phases complete: Phase 6, Phase 7, Phase 8
- ✅ Milestone archived with commit `26445b0`

### Android Inference Diagnosis (Phase 9) -- COMPLETE
- ✅ **Root cause identified:** Missing `aaptOptions { noCompress 'tflite' }` caused AAPT compression of model
- ✅ **Fix applied:** `aaptOptions { noCompress 'tflite' }` in `android/app/build.gradle`
- ✅ **Android coordinate correction:** `MainActivity.kt` MethodChannel + `_pollDisplayRotation()` + `(1-x, 1-y)` flip for rotation=3
- ✅ **Screen recordings captured:** `result/android/` (39 frames, 2 MOV files)

### SSD MobileNet Removal -- COMPLETE (2026-03-05)
- ✅ All SSD/TFLite Dart files deleted, dependencies removed, routes simplified
- ✅ App verified working on both platforms after full cleanup

### Unsplash/API Layer Removal -- COMPLETE (2026-03-09)
- ✅ All API, MobX, data model files removed. Home screen rewritten. Dependencies slimmed.

### DIAG Cleanup -- COMPLETE (2026-03-09)
- ✅ All 5 DIAG print statements removed. `flutter analyze` fully clean.

### Rotate-to-Landscape Overlay -- COMPLETE (2026-03-10)
- ✅ **`RotateDeviceOverlay`** (`lib/screens/live_object_detection/widgets/rotate_device_overlay.dart`, ~160 lines) -- self-contained StatefulWidget
- ✅ **`sensors_plus: ^6.1.0`** added to `pubspec.yaml`
- ✅ Accelerometer-based detection at 10Hz (`x.abs() > y.abs()` = landscape)
- ✅ 500ms debounce before dismissal, 300ms fade-out animation
- ✅ Immediate dismiss if device already in landscape on first reading
- ✅ `Transform.rotate(-pi/2)` so icon+text read upright in portrait (initial +pi/2 was upside down -- fixed)
- ✅ Widget fully removed from tree after dismissal (zero ongoing cost)
- ✅ Integrated as topmost Stack child in `live_object_detection_screen.dart` (lines 598-605)
- ✅ `_showRotateOverlay` bool with `mounted` guard on callback
- ✅ **Device-verified on iPhone 12**

### Camera Permission Handling -- COMPLETE (2026-03-11)
- ✅ **`permission_handler: ^11.3.1`** added to `pubspec.yaml`
- ✅ **iOS Podfile** configured with `PERMISSION_CAMERA=1` preprocessor macro
- ✅ **`_requestCameraPermission()`** in `initState` -- requests camera permission before `YOLOView` renders
- ✅ **`_cameraReady` flag** gates `YOLOView` rendering (shows loading spinner until granted)
- ✅ Handles denied permission by showing snackbar and popping back to home
- ✅ Fixes silent camera failure on fresh installs (root cause: `ultralytics_yolo` v0.2.0 checks but never requests camera permission on iOS)

### UI Cleanup: AppBar Removal + Back Button Badge -- COMPLETE (2026-03-11)
- ✅ **AppBar removed** from Scaffold -- camera preview fills full screen height in landscape (~56px reclaimed)
- ✅ **YOLO text badge replaced** with circular back arrow icon button (40x40, `Colors.black54`, `BorderRadius.circular(20)`)
- ✅ **`GestureDetector`** with `Navigator.of(context).pop()` for navigation
- ✅ **`DetectorConfig` import removed** from live screen (unused after badge removal; class still exists and tested in `widget_test.dart`)
- ✅ **Device-verified** on iPhone 12 and Galaxy A32

### Issue Log -- CREATED (2026-03-11)
- ✅ **`memory-bank/issueLog.md`** -- 9 historical issues with root causes and verified solutions

### Back Button Fix During Calibration -- COMPLETE (2026-03-13)
- ✅ **Back button now works during reference capture sub-phase** — full-screen calibration GestureDetector narrowed to only show while collecting corner taps (not during ball detection confirm step)
- ✅ Change: `if (_calibrationMode)` → `if (_calibrationMode && !_awaitingReferenceCapture)` on the LayoutBuilder/GestureDetector
- ✅ Back button still works before calibration, after calibration, and during tracking/results
- ✅ 81/81 tests passing

### Evaluation Documentation
- ✅ `docs/` and `result/android/` contain evidence from both platforms

---

## Target Zone Impact Detection

### Phase 1: Calibration + Grid Overlay
✅ **Status:** COMPLETE — device-verified on iPhone 12 and Galaxy A32 (2026-03-09).
- Tap 4 corners to register target position
- 8-parameter DLT homography transform (pure Dart, `lib/services/homography_transform.dart`)
- Zone mapper with pointToZone, grid geometry, zone centers (`lib/services/target_zone_mapper.dart`)
- Green wireframe grid overlay with zone numbers 1-9 (`lib/screens/live_object_detection/widgets/calibration_overlay.dart`)
- Inverse coordinate transform `YoloCoordUtils.fromCanvasPixel()` for touch-to-normalized conversion
- Calibration UI: "Calibrate"/"Re-calibrate" button, instruction text, corner markers
- GestureDetector with LayoutBuilder for canvas-size-aware tap handling
- 25 tests passing (8 homography, 8 zone mapper, 4 coord utils, 3 existing + 2 more)

### Phase 2: Kalman Filter + Trajectory Tracking
✅ **Status:** COMPLETE (2026-03-09). 56/56 tests passing.
- **`BallKalmanFilter`** (`lib/services/kalman_filter.dart`, 412 lines) -- Pure Dart 4-state Kalman filter (px, py, vx, vy) with constant-velocity model, configurable process/measurement noise, inline matrix math
- **`BallTracker` Kalman integration** (`lib/services/ball_tracker.dart`) -- update() routes through Kalman for smoothing, markOccluded() predicts through up to 5 frames, velocity/smoothedPosition getters exposed
- **`TrackedPosition` extended** (`lib/models/tracked_position.dart`) -- added vx, vy, isPredicted fields (backward-compatible)
- **`TrajectoryExtrapolator`** (`lib/services/trajectory_extrapolator.dart`, 95 lines) -- Parabolic extrapolation (x: constant-velocity, y: gravity) to target plane intersection, returns ExtrapolationResult with zone number
- **Live screen wired** -- `_extrapolator` and `_lastExtrapolation` field ready for Phase 3 consumption
- 16 Kalman filter unit tests, 8 BallTracker integration tests, 7 trajectory extrapolator tests
- 1 expected lint warning: `_lastExtrapolation` unused (consumed by Phase 3)

### Phase 3: Impact Detection + Zone Mapping + Result Display
✅ **Status:** COMPLETE & DEVICE-VERIFIED (2026-03-09). 70/70 tests passing. Tested on iPhone 12 and Galaxy A32.
- **`ImpactEvent`** (`lib/models/impact_event.dart`) -- Immutable value type: ImpactResult enum (hit/miss/noResult), zone number, camera/target points
- **`ImpactDetector`** (`lib/services/impact_detector.dart`) -- State machine (Ready -> Tracking -> Result -> Ready), multi-signal decision logic:
  - Signal 1: Trajectory extrapolation (primary) -- uses `TrajectoryExtrapolator` to predict target intersection
  - Signal 2: Frame-edge exit filter -- ball within 8% of frame edge -> MISS
  - Velocity history accumulated for Phase 5 integration
  - Configurable result display duration (default 3s)
  - `minTrackingFrames = 3` (~100ms at 30fps, lowered from 8 per ADR-047), `lostFrameThreshold = 5` (~167ms)
- **`TargetZoneMapper.zoneCorners()`** -- Returns 4 corner points of any zone in camera-space for highlight rendering
- **`CalibrationOverlay.highlightZone`** -- Yellow semi-transparent fill on the hit zone during result display
- **Live screen integration** -- Impact detector fed every frame via `processFrame()`, large zone number/MISS overlay (centered, 72px font), status text badge (**bottom-right**), "Ball lost" badge hidden during result phase
- **Edge filter priority** -- Edge exit takes priority over trajectory extrapolation (prevents false hits near frame edge)
- **UI refinement** -- Status text and calibration instruction labels moved from bottom-center to **bottom-right** (`Positioned bottom:16, right:16`) to avoid blocking camera view. Confirmed comfortable on both devices.
- 12 impact detector unit tests covering: state transitions, edge detection on all 4 edges, extrapolation hit, cooldown expiry, force reset, ball reappearance, priority ordering
- **Device testing** -- Tested using penalty shoot video on laptop screen. Confirmed: MISS labels appear for edge exits, zone numbers display for hits, yellow highlight shows on correct zone, 3-second cooldown with auto-reset, "Ball lost" badge hidden during result display. Real soccer ball testing planned next.

### Phase 4: Audio Feedback
✅ **Status:** COMPLETE & DEVICE-VERIFIED (2026-03-09, audio upgraded 2026-03-19). 74/74 tests passing. Tested on iPhone 12, Galaxy A32, and Realme 9 Pro+.
- **`AudioService`** (`lib/services/audio_service.dart`) — Singleton with lazy `AudioPlayer`, plays zone callouts (1-9) on hits, "Miss" on misses, silent for `noResult`
- **Audio assets** — 10 M4A files: `assets/audio/zone_1.m4a` through `zone_9.m4a` + `miss.m4a`
- **Audio upgrade (2026-03-19):** HIT audio changed from plain number callouts ("Seven") to celebratory "You hit seven!" + crowd cheer (~4.7s each). Generated via macOS TTS (Samantha, rate 170) + Pixabay crowd cheer SFX (3.8s, fade-out), composited with ffmpeg. Drop-in replacement, zero code changes. MISS audio unchanged. Originals backed up at `assets/audio/originals/`.
- **`audioplayers: ^6.1.0`** added to `pubspec.yaml`, assets registered under `flutter.assets`
- **Phase-transition trigger** — `live_object_detection_screen.dart` captures `prevPhase` before `processFrame()`, fires audio exactly once when phase transitions to `result`
- **Dispose** — `_audioService.dispose()` called in screen `dispose()`
- **MISS audio fix** — Added `stop()` before `play()` in AudioService to ensure clean player state when switching between different audio sources
- 3 unit tests: singleton identity, noResult no-op, hit-without-zone no-op

### Post-Phase-4 Bugfix: Stale Extrapolation False Positive
✅ **Status:** FIXED & DEVICE-VERIFIED (2026-03-09).
- **Root cause:** `ImpactDetector._onBallDetected()` had `if (extrapolation != null) _bestExtrapolation = extrapolation;` — only updated when non-null, so a stale extrapolation from an earlier frame (when the ball briefly headed toward the target) persisted even after the ball changed direction
- **Symptom:** Ball on the left side of the goal (far from the calibrated grid on the right) still produced a false HIT at zone 3
- **Fix:** Changed to `_bestExtrapolation = extrapolation;` (always use latest value, including null). When the ball's trajectory no longer intersects the target, the stale extrapolation is cleared
- 1 new unit test: `stale extrapolation cleared when trajectory changes` (13 impact detector tests total)

### KickDetector Service (2026-03-23)
✅ **Status:** IMPLEMENTED & UNIT-TESTED. 94/94 tests passing. Field-tested (partial — bugs identified).
- **`KickDetector`** (`lib/services/kick_detector.dart`) — 4-state machine: idle → confirming → active → refractory
- **4 signal layers:** jerk gate (`jerkThreshold=0.01`), energy sustain (`sustainThreshold=0.005`, 3 frames), direction toward goal (dot product with calibrated `_goalCenter`), refractory period (20 frames)
- **Integrated** into `live_object_detection_screen.dart` as **result gate only**. ImpactDetector runs unconditionally every frame. KickDetector controls whether results are announced (audio plays only when `isKickActive=true`). `tickResultTimeout()` called outside gate so result overlay always clears.
- **Kick-state gate on pipeline input: ATTEMPTED AND REVERTED (2026-04-08)** — Gating ImpactDetector/WallPredictor behind `kickEngaged` broke grounded kick detection (ISSUE-025, ADR-061). Reverted to unconditional processing.
- **`_goalCenter` getter** — `_homography!.inverseTransform(Offset(0.5, 0.5))` maps target center back to camera space for direction filter
- **13 unit tests** in `test/kick_detector_test.dart`

### DiagnosticLogger Service (2026-03-23)
✅ **Status:** IMPLEMENTED.
- **`DiagnosticLogger`** (`lib/services/diagnostic_logger.dart`) — Singleton CSV logger. Per-frame rows (`FRAME`) + per-decision rows (`DECISION`). Writes to app Documents directory (`flare_diag_YYYYMMDD_HHMMSS.csv`).
- **CSV columns:** `event_type, timestamp_ms, ball_detected, raw_x, raw_y, bbox_area, depth_ratio, smoothed_x, smoothed_y, vel_x, vel_y, vel_mag, phase, direct_zone, extrap_zone, kick_confirmed, kick_state, result, zone, reason`
- **Share Log button** in live screen — `Share.shareXFiles` with `sharePositionOrigin` derived dynamically from `GlobalKey` + `RenderBox`
- **iOS 26.3.1 fix** — `sharePositionOrigin` now uses `_shareButtonKey.currentContext?.findRenderObject() as RenderBox?` — works on all device sizes and orientations
- **Dependencies added:** `path_provider: ^2.1.3`, `share_plus: ^10.0.0`

### Calibration Geometry Diagnostics (2026-04-09)
✅ **Status:** IMPLEMENTED.
- **`_logCalibrationDiagnostics()`** method in `live_object_detection_screen.dart` (~100 lines) — computes and logs 15+ geometric parameters from 4 calibration corners
- **Parameters logged:** corner positions, edge lengths, avg width/height, aspect ratio (vs ideal 1.5714), perspective ratios (top/bottom, left/right), centroid, center offset, quadrilateral area, coverage %, diagonal lengths/ratio, edge angles, corner angles, homography matrix, zone centers in camera space (all 9 zones)
- **Triggers:** called on every `_recomputeHomography()` (4th corner tap + every corner drag) and at `_confirmReferenceCapture()` (pipeline start)
- **PIPELINE START block** logs full calibration + refBboxArea + lockedTrackId + timestamp

### Debug Bounding Box Overlay (2026-04-09)
✅ **Status:** IMPLEMENTED. Togglable via `_debugBboxOverlay` const.
- **`DebugBboxOverlay`** (`lib/screens/live_object_detection/widgets/debug_bbox_overlay.dart`, ~110 lines) — CustomPainter rendering colored bounding boxes for all ball-class detections
- **Color coding:** Green = locked track, Yellow = other ball-class candidates, Red = locked track in lost state
- **Labels:** trackId, bbox WxH, aspect ratio, confidence, isStatic flag (S), [LOCKED] status
- **Toggle:** `static const _debugBboxOverlay = true;` — set to `false` to disable completely

### Enhanced BallIdentifier Logging (2026-04-09)
✅ **Status:** IMPLEMENTED.
- **Lost events:** log all candidate ball-class tracks with bbox WxH, aspect ratio, velocity, isStatic, state, confidence
- **Re-acquisition events:** log old→new trackId, bbox shape, position, velocity/distance, reason (single_moving_track or nearest_non_static)
- **Rejection events:** log specific reason ("no moving tracks", "ambiguous — multiple moving tracks")

### tickResultTimeout() Fix — Stuck Overlay (Bug 1, 2026-03-23)
✅ **Status:** FIXED.
- `ImpactDetector.tickResultTimeout()` added — called every frame in live screen's `if (_pipelineLive)` block, **outside** the kick gate
- Fixes: result overlay was never clearing because the 3-second timeout was inside `processFrame()` which was gated behind `isKickActive`

### Phase 5: Depth Estimation (Evolved: Trust Qualifier for Direct Zone Mapping)
✅ **Status:** COMPLETE & RE-ENABLED AS TRUST QUALIFIER (2026-03-20). 81/81 tests passing.
- **Reference Ball Capture** -- After 4-corner calibration, user places ball on target and taps "Confirm". YOLO auto-detects ball and captures `normalizedBox.width * normalizedBox.height` as reference bbox area. Zero hardcoding, works with any ball size.
- **Depth ratio evolution:**
  - **v1 (2026-03-09):** Hard gate blocking hits outside `[0.3, 2.5]` range → `noResult`. Signal priority: Edge > Depth gate > Extrapolation.
  - **v2 (2026-03-17, ADR-047 Fix 2):** Disabled entirely. Motion blur caused false rejections.
  - **v3 (2026-03-20, ADR-051):** Re-enabled as **trust qualifier** for direct zone mapping. `minDepthRatio=0.3`, `maxDepthRatio=1.5`. When ball's position maps to a zone via `pointToZone()` AND depth ratio is in range → `_lastDepthVerifiedZone` stored. At decision time, preferred over trajectory extrapolation. Signal priority: Edge (MISS) > Depth-verified direct zone (HIT) > Extrapolation fallback (HIT) > noResult.
- **Why this works:** Depth ratio distinguishes "ball at wall depth, position is accurate" from "ball mid-flight passing through grid region in camera-space, position is misleading". Extrapolation amplifies mid-flight angular errors; direct mapping near the wall doesn't.
- **`directZone` parameter** added to `processFrame()`. Live screen passes `zoneMapper.pointToZone(rawPosition)` every frame.
- **Last bbox (not peak)** -- Uses last-seen bbox area, not maximum. In behind-kicker camera position, ball SHRINKS as it approaches the target.
- **Calibration sub-phase UI** -- After 4 corners: "Place ball on target — point camera at ball" instruction. Ball detected → green "Ball detected — tap Confirm" text + enabled Confirm button.
- **Reference persists across kicks** -- `_referenceBboxArea` cleared only on re-calibration, not on per-kick reset.

---

## Real-World Testing & Pipeline Fixes (2026-03-17)

### Confidence Threshold Lowered
✅ **Status:** COMPLETE (2026-03-17).
- `confidenceThreshold: 0.25` added to `YOLOView` constructor in `live_object_detection_screen.dart`
- Plugin default was 0.5 (Dart layer overrides native default of 0.25 via `_applyThresholds()`)
- Recovers small/marginal ball detections during mid-flight that were silently discarded

### Real-World Testing Results
📝 **Status:** TESTED (2026-03-17). Results: 1/10 correct HITs on iOS. Similar results on Android (Realme 9 Pro+).
- Diagnostic `print()` statements added to `ImpactDetector._makeDecision()`
- Terminal log captured and analyzed: 10 impact decisions, 1 success
- Three distinct failure modes identified in the decision pipeline
- Evidence-backed fixes designed (ADR-047)

### ADR-047 Impact Detection Fixes
✅ **Fixes 1-3 IMPLEMENTED** (2026-03-17). Fix 4 DEFERRED.
- ✅ Fix 1: `minTrackingFrames` 8→3 in `impact_detector.dart` — single constant change
- ✅ Fix 2: Depth ratio filter disabled as hard gate (ADR-047) → **re-enabled as trust qualifier for direct zone mapping (ADR-051, 2026-03-20)** — `maxDepthRatio` tightened from 2.5 to 1.5
- ✅ Fix 3: Extrapolation retained during occlusion in `impact_detector.dart` + recomputed from Kalman state in `live_object_detection_screen.dart`
- ⏳ Fix 4: Cap extrapolation maxFrames or reduce gravity — DEFERRED for separate discussion
- 3 unit tests updated (minTrackingFrames threshold, 2 depth filter expectations)
- iOS indoor test (shoot-out video): **4/6 correct HITs (67%)**, up from 1/10 (10%)
- Fix 2 directly saved 2 detections that would have been BLOCKED by depth filter
- 2 remaining failures: both had only 1 tracking frame (very fast kicks)
- **Outdoor test (2026-03-20):** iOS showed wrong zones (extrapolation predicted zone 8, ball hit zone 5). Android couldn't detect any hits at all. Led to ADR-051 (depth-verified direct zone mapping).
- **Next: real-world outdoor test on both devices with depth-verified direct zone mapping**

---

## Anchor Rectangle Feature (designed 2026-04-17)

### Phase 1 — Tap-to-Lock Interaction
✅ **Status:** CODE COMPLETE + iOS DEVICE-VERIFIED (2026-04-19). Tested on iPhone 12 — tap-to-lock flow + back button fix both working. Android (Realme 9 Pro+) verification still pending. 175/175 tests passing. `flutter analyze` 0 errors.

- **Replaces:** Auto-pick-largest reference capture with explicit player tap-to-select. Two-step UX retained (tap → green box → Confirm commits).
- **Files touched:** `live_object_detection_screen.dart`, `services/ball_identifier.dart`, `services/audio_service.dart`, `test/ball_identifier_test.dart`. No new files.
- **Key changes:**
  - `BallIdentifier.setReferenceTrack(List<TrackedObject>)` → `setReferenceTrack(TrackedObject)`. Caller is now responsible for filtering & selection.
  - Multi-bbox painter (`_ReferenceBboxPainter`) — every ball-class tracked candidate gets a red bbox; the player-selected one is green.
  - `_findNearestBall` + `_handleBallTap` — Tap-2 rule (inside-bbox direct hit always wins; else nearest-by-center within `_dragHitRadius = 0.09`).
  - `onTapUp` added to existing GestureDetector alongside `onPanStart/Update/End` (Gesture-1: trust the gesture arena).
  - Audio nudge timer (`Audio-2`: 30s grace, 10s repeat, State 2 only). Stub `AudioService.playTapPrompt` prints `AUDIO-STUB:` until Phase 5 records the asset.
  - Prompt text now 3-state: S1-a → "Tap the ball you want to use" → "Tap Confirm to proceed with selected ball" (greenAccent in State 3).
  - `_startCalibration` (Recal-1) clears tap selection + cancels nudge timer; `dispose` cancels nudge timer.
- **What is NOT yet done:** Anchor rectangle drawing (Phase 2), filter (Phase 3), return-to-anchor cycle (Phase 4), real audio asset (Phase 5).
- **On-device verification checklist:** see `memory-bank/activeContext.md` "Verification still required (on-device)" subsection.

#### Audio nudge counter + timestamp (2026-04-19, follow-up to Phase 1)
- Made the audio nudge stub self-verifying so on-device testing of the 30 s grace + 10 s repeat cadence can be confirmed from the device log alone (no wrist watch needed) while real audio remains Phase 5.
- `AudioService` gained `_tapPromptCallCount` field + `resetTapPromptCounter()` method. `playTapPrompt()` now prints `AUDIO-STUB #N: Tap the ball to continue (HH:MM:SS.mmm)` instead of a repeating identical line.
- `_startAudioNudgeTimer` calls `resetTapPromptCounter()` so every new State 2 episode visibly restarts the counter at `#1`.
- 175/175 tests still passing; analyzer clean.

#### Back-button z-order fix (2026-04-19, follow-up to Phase 1)
- Moved back button `Positioned` block to render after both full-screen `GestureDetector`s but before the rotate overlay. Closes two bugs in one move:
  1. Pre-existing: back button unreachable during corner-tap calibration mode (corner detector won gesture arena).
  2. Phase 1 regression: back button unreachable during awaiting reference capture (Phase 1 added `onTapUp` to that detector, which competed with the back button's `onTap`).
- Side benefit: no phantom corner can be placed under the back button during calibration.
- Drive-by cleanup: deleted now-unused `_referenceCandidateBbox` field (1 declaration + 2 dead `= null` writes).
- 175/175 tests still passing; analyzer clean.

### Phase 2-5 — Pending
- Phase 2: Anchor Rectangle Computation & Display — not started
- Phase 3: Rectangle Filter During Waiting State — not started
- Phase 4: Return-to-Anchor After Decision — not started
- Phase 5: Audio Announcements & Edge Cases — not started

---

## What Is Incomplete or Needs Decisions

### Pipeline Gating (`_pipelineLive`)
✅ **Status:** COMPLETE & DEVICE-VERIFIED (2026-03-19). 81/81 tests passing. Tested on iPhone 12 and Realme 9 Pro+.
- **Problem:** Detection pipeline (tracker, trail dots, "Ball lost", impact detection) ran immediately on camera open, before calibration — causing false MISS/noResult and unwanted orange dots during setup
- **Fix:** Single `_pipelineLive` boolean gate in `live_object_detection_screen.dart`. Only set `true` when `_confirmReferenceCapture()` completes. Set `false` on `_startCalibration()` (re-calibrate). 4 touch points, ~6 lines added.
- **Stages enforced:** Preview (silent) → Calibration (silent) → Reference Capture (bbox only) → Live (full pipeline)

### Draggable Calibration Corners + Finger Occlusion Fix
✅ **Status:** COMPLETE & DEVICE-VERIFIED (2026-03-19). 81/81 tests passing. Tested on iPhone 12 and Realme 9 Pro+.
- **Drag-to-reposition** — During reference capture sub-phase, user can drag any of the 4 calibration corners to fine-tune position
- **`_findNearestCorner()`** — Hit-tests touch against all 4 corners with `_dragHitRadius = 0.09` (~9% of frame in normalized space)
- **`_recomputeHomography()`** — Extracted helper recomputes `HomographyTransform` + `TargetZoneMapper` from current corner positions; called on every drag update and reused by `_handleCalibrationTap`
- **GestureDetector** with `onPanStart`/`onPanUpdate`/`onPanEnd`, `HitTestBehavior.translucent` so Confirm button remains tappable
- **Zero new dependencies** — pure Dart addition (~35 lines)
- **Hit radius tuning** — Initial `0.04` was too small on iOS; increased to `0.09` (ADR-047)
- **Finger occlusion fix (2026-03-19, ADR-048):**
  - **Hollow green ring markers** — Removed solid `fillPaint` circle; corners are always stroked rings (radius 10px, strokeWidth 2.0). Crosshair intersection visible through center.
  - **30px vertical offset cursor** — Corner renders 30px above finger during drag. Reduced from initial 60px (too jarring, bottom corners unreachable) through 15px (too subtle) to 30px (user-tuned on device).
  - **Crosshair lines during drag** — Full-width horizontal + full-height vertical white lines (0.7 opacity, 0.5px) through active corner. Drawn as topmost layer in `CalibrationOverlay._paintCrosshair()`.
  - **Research confirmed** no Flutter package solves finger occlusion over platform views (camera). 8 agents, 22 pub.dev searches, 4 packages inspected (`flutter_quad_annotator`, `flutter_magnifier_lens`, `flutter_magnifier`, `flutter_image_perspective_crop`) — all use BackdropFilter or canvas.drawImageRect which cannot capture platform view content.

### Off-By-One Bug Between KickDetector and ImpactDetector (Bug 2)
⚠️ **Status:** Identified (2026-03-23). Pending user approval to fix.
- `KickDetector.maxActiveMissedFrames=5` == `ImpactDetector.lostFrameThreshold=5`. On the 5th missed frame, `KickDetector.onKickComplete()` sets `isKickActive=false` BEFORE the screen's `if (_kickDetector.isKickActive)` check, so ImpactDetector never receives its 5th lost frame and `_makeDecision()` is never triggered from ball loss.
- **Effect:** Ball-loss detection path (kick flies past/to target, ball disappears) never fires. Only velocity-drop path (ball bounces back into frame) can trigger a decision.
- **Proposed fix:** Change `maxActiveMissedFrames` from 5 to 8 in `kick_detector.dart`.

### Zone Accuracy (Bug 3 — Systematic One-Row-Down Error)
⚠️ **Status:** PARTIALLY FIXED. WallPlanePredictor v3 eliminates massive Y-axis errors (zone 7→1) but still has systematic one-row-down bias (zone 7→6, zone 5→2).
- **Root cause:** 2D homography only maps correctly for points ON the wall plane. WallPlanePredictor uses pseudo-3D depth from bbox area changes to correct this, but under-corrects for upper zones.
- **Field test results (2026-04-06, post-reconnection):**
  - Phase 1 (plain wall, no circles): 1/4 correct (25%). Zone 1→1 ✅, zone 7→6 ❌, zone 5→2 ❌, zone 1→missed ❌.
  - Phase 2 (Flare Player with circles): 0/3 correct. All predicted zone 6. Circles pollute observations.
  - Pattern: bottom row correct (no room to shift down), upper/middle rows shift down by exactly one row.
- **Comparison with 2026-04-01 pre-ByteTrack results:** Similar pattern. WallPlanePredictor v3 eliminated massive 2-row errors but one-row-down bias persists.
- **Next:** Fix perspective correction in WallPlanePredictor depth model.

### TrajectoryExtrapolator & WallPlanePredictor Reconnection (2026-04-06)
✅ **Status:** RECONNECTED & FIELD-TESTED. 172/172 tests passing.
- **Problem:** During ByteTrack integration, both services were disconnected — `processFrame()` called with `extrapolation: null` and `wallPredictedZone: null`. Every IMPACT DECISION was `noResult`.
- **Fix:** Reinstantiated both services in `live_object_detection_screen.dart`. Initialized after homography computation with optical center from calibration corners. Data wired from ByteTrack's `rawPosition`, `velocity`, `bboxArea`. Reset on re-calibration, kick acceptance, and kick rejection.
- **Result:** Pipeline now makes HIT/MISS decisions. WallPlanePredictor fires on every kick. TrajectoryExtrapolator also fires and often agrees with WallPlanePredictor.

### directZone Decision Logic (2026-04-09)
⚠️ **Status:** IMPLEMENTED BUT PROVEN UNRELIABLE (2026-04-09 testing). 173/173 tests passing.

**Background:** Video test analysis (5 kicks) showed `directZone` correct 5/5, but old decision cascade (WallPlanePredictor → depth-verified → extrapolation) only announced 2/5 due to `minTrackingFrames` gate and KickDetector `active` requirement.

**Changes:**
- **`ImpactDetector`** — Decision priority changed to: edge exit (MISS) → last observed `directZone` (HIT) → noResult. WallPlanePredictor, depth-verified zone, and extrapolation removed from decision cascade. `minTrackingFrames` gate removed (directZone is self-validating). `_lastDirectZone` field tracks last non-null directZone during tracking.
- **`KickDetector`** — Result gate accepts `confirming` OR `active` (was `active` only). `onKickComplete()` also transitions from `confirming` to refractory.
- **IMPACT DECISION diagnostic block** — Now includes `lastDirectZone`, `kickState`, `ballConfidence`.
- **`TrackedObject`** — `confidence` field added, surfaced from internal `_STrack`.
- **See ADR-063, ADR-064.**

### WallPlanePredictor Service (2026-04-01) — DIAGNOSTIC ONLY
✅ **Status:** v3 IMPLEMENTED. 12 unit tests. **No longer used for decisions** (replaced by directZone, ADR-063). Still runs and logs `lastWallPredictedZone` for diagnostic comparison.

**Evolution:**
- **v1:** Hardcoded `wallDepthRatio=0.25`. Fixed Y-axis perspective error but required manual tuning per setup.
- **v2:** Computed wallDepthRatio from physical dimensions (`_targetWidthMm=1760`, `_ballDiameterMm=220`). Still hardcoded — physical dimensions are assumptions.
- **v3 (current):** Zero hardcoded parameters. Iterative forward projection — extrapolates 3D trajectory one frame at a time and checks `pointToZone()`. Wall is discovered implicitly when projected point enters the grid.

**Current implementation:**
- **`WallPlanePredictor`** (`lib/services/wall_plane_predictor.dart`) — Constructor takes only `opticalCenter` (centroid of calibration corners = observed data). Uses `_isDepthIncreasing()` adaptive check (5% noise tolerance) instead of hardcoded Vz threshold. Requires minimum 2 observations.
- **`WallPrediction`** result type — cameraPoint, targetPoint, zone (1-9), framesAhead.
- **Runs every frame** but no longer influences ImpactDetector decisions. `lastWallPredictedZone` logged in IMPACT DECISION block for diagnostic comparison.
- **12 unit tests** in `test/wall_plane_predictor_test.dart`.

### Phase-Aware Detection Filtering (2026-04-01)
✅ **Status:** IMPLEMENTED & FIELD-TESTED.
- **`_applyPhaseFilter()`** in `live_object_detection_screen.dart` — filters YOLO candidates by confidence + spatial proximity before priority sorting.
- **Ready phase:** confidence floor 0.50 + spatial gate 10% radius from last known position.
- **Tracking phase:** confidence floor 0.25 + spatial gate 15% radius from Kalman-predicted position.
- **No prior:** confidence floor 0.50, no spatial gate.
- Eliminates false orange trail dots on kicker body/hands/head/wall patterns observed in Session 2.

### Field Test Results Summary (2026-04-01, pre-false-positive discovery)
| Session | Version | Exact Correct | Within 1 Zone | Massive Y Error |
|---------|---------|--------------|----------------|-----------------|
| 1 (baseline) | No WallPlanePredictor | 1/5 (20%) | 1/5 (20%) | 3/5 |
| 2 (v1) | wallDepthRatio=0.25 | ~1/5 (20%) | ~2/5 (40%) | 0 |
| 3 (v3) | Zero hardcoded params | 3/5 (60%) | 4/5 (80%) | 0 |

⚠️ **Note:** These results may also have been affected by target circle false positives. They were collected before the false positive problem was understood.

### 🔴 CRITICAL: Target Circle False Positives (ISSUE-022, 2026-04-04)
**Status:** IDENTIFIED — #1 BLOCKER. Solution not yet designed.

**Problem:** The 9 red LED-ringed circles on the Flare Player banner are detected by YOLO as soccer balls at confidence ≥0.25. This poisons the entire detection pipeline.

**Evidence (41 screenshots + 27-kick field test):**
- Orange dots appear ON target circles with NO ball in flight
- Shaking camera at target creates false trails hopping between circles, triggering zone announcements
- During kicks, `_pickBestBallYolo` alternates between real ball and circle false positives
- Circle detections are INSIDE the calibrated grid — spatial gating (`_applyPhaseFilter`) cannot filter them
- Circle detections appear stationary, ON the wall (depth ratio ~1.0), INSIDE a zone — identical to "ball has impacted target" to the pipeline

**Impact on field test accuracy:**
| Phase | Setup | Accuracy | Systematic Bias | Cause |
|-------|-------|----------|-----------------|-------|
| Phase 1 | Waist height, 11m | 7/18 (38.9%) | Zone 6 (11/18) | Zone 6 circle most detected from waist angle |
| Phase 2 | Chest height, 11m | 1/9 (11.1%) | Zone 1/2 | Bottom circles most detected from chest angle |

**Why existing phase-aware filter fails:** `_applyPhaseFilter()` uses spatial gating to reject detections far from expected ball position. Target circles are IN the target area where the ball is expected to arrive — indistinguishable from the real ball by position alone.

**Blocks evaluation of:** WallPlanePredictor accuracy, decision timing, Bug 2 impact. All pipeline components receive poisoned data.

**Full analysis:** `memory-bank/field-test-analysis-2026-04-04.md`

### Guided Setup Flow with Auto-Zoom
🔴 **Status:** FLOW AGREED (2026-04-14). Open design questions pending. Not yet implemented.

**Problem:** Camera setup geometry (distance, lateral offset) is the #1 factor in detection reliability — more impactful than any software filter. Developer's controlled testing (2026-04-14) confirmed: at correct distance/angle, false positives disappear entirely; at wrong geometry, software filters cannot compensate.

**Key discovery (2026-04-14):** `ultralytics_yolo` plugin supports `YOLOViewController.setZoomLevel()` — real camera digital zoom that affects the frame YOLO receives. Auto-zoom can compensate for distance, keeping ball above 32px at YOLO's 640 inference resolution.

**Research (2026-04-06):** Studied HomeCourt, PB Vision, SwingVision, Scanbot, Google Guided Frame, Apple Face ID, TADA app.

**Research (2026-04-14):** YOLO11n detection thresholds — COCO "small object" = <32×32px. Developer's log data: stationary ball ≈ 29px at inference (borderline), ball at target ≈ 13px (well below threshold). At 2.5× zoom, ball at target ≈ 33px (above threshold).

**Agreed flow (2026-04-14, supersedes 2026-04-06 version):** 8-step flow. Step 0: app launch + landscape. Step 1: setup instruction overlay. Step 2: quick target scan (tap on target). Step 3: auto-zoom. Step 4: tap 4 corners + Next button. Step 5: position quality validation → "Position Locked" overlay. Step 6: reference ball capture (existing). Step 7: user walks to kicking spot. Step 8: live detection. Full details in `memory-bank/activeContext.md`.

**Open design questions (2026-04-14):**
1. How does a single tap in Step 2 give enough info for zoom calculation?
2. What target coverage % to aim for after zoom?
3. Position validation threshold values

**Plugin API confirmed:**
- `YOLOViewController.setZoomLevel(double)` — iOS: `device.videoZoomFactor`, Android: CameraX `setZoomRatio()`
- Range: 1.0×-10.0× iOS, device-dependent Android
- Camera resolution unchanged (4032×3024 iOS) — zoom crops and upscales at sensor level
- `onZoomChanged` callback available
- Need to create `YOLOViewController` instance and pass to `YOLOView` via `controller` parameter

**Position quality checks (derived from 4 corner taps):**
| Check | Measurement | Ideal |
|-------|-------------|-------|
| Distance | Target coverage after zoom | TBD |
| Centering | Centroid X vs frame center | ±10% |
| Height | Centroid Y vs frame center | ±15% |
| Angle | Top edge ≈ bottom edge length | ±15% |
| Stability | Corner positions stable | 0.5s |

### Session Lock + Protected Track + Trail Suppression (2026-04-15)
✅ **Status:** IMPLEMENTED & MONITOR-TESTED. Eliminates false positive trail dots.

**Changes:**
- **BallIdentifier session lock** — `_sessionLocked` flag blocks Priority 2/3 re-acquisition during active kicks. Activated on `KickDetector.isKickActive`, deactivated on HIT/MISS/LOST decision.
- **ByteTrack protected track** — `_protectedTrackId` gets 60-frame survival (vs default 30) to maintain locked ball track during flight.
- **Trail suppression** — TrailOverlay receives empty trail when `kickState == idle`. Dots only shown during confirming/active/refractory.
- **Bbox area ratio check on Mahalanobis rescue** — Rejects rescue candidates with area >2x or <0.3x last measured ball area. Uses last real measurement instead of drifting Kalman predicted area.

**Test results (2026-04-16, after area ratio fix):**
- 5/5 kicks detected across 3 test runs
- False positive dots still appearing during active kicks (open issue)

**Known issues:**
- Session lock has no safety timeout — can get stuck permanently if locked track is lost without a decision (e.g., bounce-back triggers false kick, ball disappears).
- Bounce-back after legitimate kick triggers false kick detection.
- False positive trail dots during active kicks (not idle — idle dots fixed by trail suppression).

### Mahalanobis Area Ratio Fix — Last-Measured-Area (2026-04-16, ISSUE-029)
✅ **Status:** FIXED & MONITOR-TESTED. 5/5 kicks across 3 test runs.

**Problem:** Area ratio check (2.0/0.5) compared detection area against Kalman predicted area. During fast kicks, Kalman predictions drift → legitimate rescues blocked → silent kicks (2/5).

**Iterations tested:**
1. Relaxed Kalman threshold (3.5/0.3) → 4/5 kicks, but false positive dots returned
2. Last-measured-area with tight bounds (2.0/0.5) → 3/5 kicks (lower bound too tight, ball shrinks in flight)
3. Last-measured-area with relaxed lower bound (2.0/0.3) → **5/5 kicks** ✅

**Fix:** `ByteTrackTracker.update()` and `_greedyMatch()` accept `lastMeasuredBallArea` from `BallIdentifier.lastBallBboxArea`. Area ratio compares against real measurement with Kalman fallback. Threshold: upper 2.0 (blocks hijacking at 3.8x+), lower 0.3 (allows ball shrinking during flight).

### UI Refinements (2026-04-16)
✅ **Status:** IMPLEMENTED.
- **Center crosshair** — Color changed from white (alpha 0.3) to purple (alpha 0.5). StrokeWidth from 0.5 to 1.5 for visibility against brick walls and varied backgrounds.
- **Calibrate/Re-calibrate button** — Repositioned from `bottom:16` to `bottom:48` to sit above the tilt indicator (was overlapping).
- **Large result overlay** — Re-enabled (was commented out for testing).

### `tennis-ball` Priority 2 Concession (Minor)
⚠️ **Status:** Still in code at `live_object_detection_screen.dart:56`. Harmless.

### iOS Camera Usage Description (Minor)
📝 **Status:** Placeholder in Info.plist. Must update before external demo.

### No Version Control
⚠️ **Status:** Intentional. Project is local-only.

---

## Decisions Made

| Decision | Rationale |
|---|---|
| YOLO11n (nano) chosen over larger variants | Prioritise speed and on-device compatibility over maximum accuracy for the POC |
| Platform-native model formats (TFLite / Core ML) | Best performance per platform |
| Model files gitignored | Large binaries managed outside VCS |
| Labels embedded in model, no external label file | YOLO11n training embedded class names directly |
| Landscape-only for YOLO screen | Matches realistic phone orientation for filming a pitch |
| `showOverlays: false` on YOLOView | Confirmed working; disables native bounding boxes |
| `mounted` guard on all detection callbacks | Prevents setState-after-dispose race condition |
| **Camera aspect ratio = 4:3 (not 16:9)** | **ultralytics_yolo uses `.photo` session preset on iOS (4032x3024). 16:9 caused ~10% Y-offset.** |
| **Min-distance dedup in BallTracker** | **Prevents dot clustering at ~30fps. Threshold: `_minDistSq = 0.000025` (0.5% of frame).** |
| `IgnorePointer` wraps trail overlay | Prevents CustomPaint from consuming touch events intended for YOLOView |
| **`ballLostThreshold = 3` frames** | **approx 100 ms at 30 fps** |
| **Android coordinate correction via MethodChannel** | **Poll `Surface.ROTATION_*` to flip coords. Device-verified on Galaxy A32.** |
| **`aaptOptions { noCompress 'tflite' }` required** | **Gradle compression corrupts TFLite model loading** |
| **SSD/MobileNet path fully removed** | **Legacy code removed. YOLO is the only backend.** |
| **No git / No GitHub** | **Developer chose local-only.** |
| **Unsplash/API layer fully removed** | **Demo scaffolding removed. Dependencies slimmed to 2 packages.** |
| **DIAG print statements removed** | **Diagnostic purpose served. Removed for clean lint.** |
| **Target zone detection: Manual calibration approach** | **Zero new platform code, zero performance impact, highest zone accuracy (math), works on Galaxy A32. Evaluated and rejected: retrained YOLO (training burden), opencv_dart auto-detection (50MB, lighting-sensitive), dual YOLO (halves FPS).** |
| **Multi-signal impact detection over naive last-position** | **Naive "last position = impact" fails when ball flies past target. Multi-signal (trajectory + depth + edge-filter + velocity) achieves ~88-92% accuracy.** |
| **Start with 30fps, defer 60fps** | **30fps is minimum viable. 60fps requires platform-specific camera code. Defer until accuracy is evaluated on real devices.** |
| **Skip frame differencing in v1** | **Requires raw camera frame access (platform-specific). Trajectory + depth + velocity signals are sufficient for v1. Add later if needed.** |
| **Calibration-based focal length (not camera intrinsics API)** | **Derive focal length from tapped corners + known target size. Pure Dart, avoids platform-specific camera intrinsics APIs.** |
| **`audioplayers` for audio feedback** | **Lightweight, simple API, cross-platform. Chosen over `just_audio` (heavier) and `flutter_soloud` (newer/less tested).** |
| **Lazy AudioPlayer creation** | **Avoids platform channel calls at service init time. Player created on first playback. Simplifies unit testing.** |
| **Phase-transition trigger for audio** | **Compare phase before/after `processFrame()`. Fires audio exactly once per impact — no duplicate plays during 3s result display.** |
| **macOS TTS for audio assets** | **`say -v Samantha` + `afconvert` to M4A. Good enough for POC. Replace with professional recordings for production.** |
| **Reference Ball Capture for depth estimation** | **User places ball on target during calibration. YOLO captures bbox area as reference. Zero hardcoding, works with any ball size. Simpler and more accurate than camera intrinsics.** |
| **Last bbox area (not peak) for depth ratio** | **Behind-kicker camera: ball shrinks toward target. Last-seen bbox = closest to target. Peak bbox = closest to camera (wrong).** |
| **`sensors_plus` for rotate overlay** | **Accelerometer detects physical orientation since `MediaQuery.orientation` is useless when UI orientation is locked via SystemChrome. 10Hz sampling, 500ms debounce, zero cost after dismissal.** |
| **`Transform.rotate(-pi/2)` not `+pi/2`** | **UI locked to landscape; portrait user sees content rotated. `-pi/2` makes it upright. `+pi/2` was upside down (device-verified bugfix).** |
| **`permission_handler` for camera permission** | **`ultralytics_yolo` v0.2.0 checks but never requests camera permission on iOS. Android side does request. Adding explicit `Permission.camera.request()` fixes fresh-install failures. Cross-platform Dart code; iOS needs `PERMISSION_CAMERA=1` Podfile macro.** |
| **AppBar removed from detection screen** | **Wastes ~56px vertical height in landscape. Title adds no value. Back navigation moved to floating icon button.** |
| **Back button badge replaces YOLO badge** | **YOLO is the only backend — label is redundant. Circular back arrow (40x40) is universally recognized. Same `Colors.black54` style.** |
| **Issue log in memory-bank** | **`issueLog.md` records bugs, root causes, and verified solutions. Prevents re-researching known issues.** |
| **Back button enabled during reference capture** | **Full-screen calibration GestureDetector was blocking back button after 4 corners placed. Narrowed condition to only show during corner collection. ADR-045.** |
| **Draggable calibration corners via GestureDetector pan** | **Users can't tap corners precisely on a phone. Draggable corners let them refine positions. Chosen over `box_transform` (rectangle-only, can't handle perspective distortion) and magnified view (hard to implement). ADR-046.** |
| **Offset cursor + crosshair + hollow rings for finger occlusion** | **No Flutter package works over camera platform views (BackdropFilter/RepaintBoundary can't capture). Offset cursor (30px) + crosshair lines + hollow ring markers solve occlusion with ~4 lines changed, zero dependencies. Exhaustively researched: 8 agents, 22 pub.dev searches, 4 packages rejected. ADR-048.** |
| **Pipeline gating via `_pipelineLive` boolean** | **Single boolean gate prevents detection pipeline from running before calibration is complete. Simpler than per-feature gates, enforces clear stage boundaries. ADR-049.** |
| **Celebratory HIT audio (TTS + crowd cheer)** | **Manager requested celebratory audio on HIT. Pre-composited "You hit N!" (macOS TTS Samantha, rate 170) + Pixabay crowd cheer SFX (3.8s, fade-out) into single M4A per zone (~4.7s). Drop-in replacement, zero code changes. Pixabay license: free commercial, no attribution.** |
| **Depth-verified direct zone mapping over pure extrapolation** | **Outdoor testing showed extrapolation predicts wrong zones (mid-flight angular errors amplified over 30+ frames). Re-enabled depth ratio as "trust qualifier": when ball's position maps to a zone AND depth ratio confirms near-wall depth, use that zone directly. Extrapolation kept as fallback. 4 research agents confirmed no commercial single-camera system uses long-range extrapolation for zone determination. ADR-051.** |
| **KickDetector as explicit gate for ImpactDetector** | **False triggers from general ball movement (dribbling, rolling) caused false zone announcements. 4-signal kick gate (jerk onset, sustained speed, direction toward goal, refractory period) discriminates real kicks from noise. Plain Dart class, pure unit-testable. ADR-052.** |
| **tickResultTimeout() outside kick gate** | **Result display 3-second timeout lived inside processFrame() which was gated behind isKickActive. After a kick completes (refractory), timeout never fired, result overlay stuck permanently. Solution: separate tickResultTimeout() method called every frame outside kick gate. ADR-053.** |
| **GlobalKey-based sharePositionOrigin (not hardcoded Rect)** | **iOS 26.3.1 enforces non-zero sharePositionOrigin for Share.shareXFiles in landscape. Hardcoded Rect rejected — breaks on different screen sizes. GlobalKey + RenderBox.localToGlobal() gives exact button position at tap time, device-agnostic. ADR-054.** |
| **WallPlanePredictor for perspective-corrected zone mapping** | **2D homography only works for points ON the wall plane. Mid-flight ball positions map to wrong zones due to perspective. 3D trajectory estimation using depth ratios (bbox area) corrects this by extrapolating to wall plane intersection. Eliminates systematic Y-axis error (zones 6-8 → zones 1-2). Field-tested 2026-04-01.** |
| **Observation-driven, zero hardcoded params (v3)** | **Physical dimensions (target size, ball size) are assumptions that break when setup changes. v3 uses iterative projection — extrapolates 3D trajectory and checks pointToZone() at each step. Wall discovered implicitly. No wallDepthRatio, no physical constants. ABSOLUTE RULE: never hardcode parameters that can be observed or derived from runtime data.** |
| **Phase-aware detection filtering** | **confidenceThreshold=0.25 caused false detections on kicker body/hands/head during Ready phase. Fix: _applyPhaseFilter() in _pickBestBallYolo applies phase-dependent confidence floor (0.50 in Ready, 0.25 in Tracking) + spatial gating (proximity to Kalman-predicted or last-known position). Uses pipeline state, not hardcoded per-setup values.** |
| **directZone as primary decision signal (ADR-063)** | **Video test showed directZone correct 5/5 vs old cascade 2/5 announced. Ball's actual position via pointToZone() is simplest and most accurate signal. No prediction, no extrapolation. WallPlanePredictor/depth-verified/extrapolation removed from decisions.** |
| **Accept `confirming` in result gate (ADR-064)** | **Fast kicks don't produce 3 sustained high-speed frames needed for `active`. `confirming` (jerk spike detected) + directZone (ball in grid) is a sufficient double-gate for real kicks.** |
| **Replace fragmented pipeline with ByteTrack (ADR-058)** | **Field testing (2026-04-04) revealed ISSUE-022 (target circle false positives) and deeper architectural flaw: no object identity, centroid-only tracking, fragmented band-aid services. Decision: complete ByteTrack in pure Dart with 8-state Kalman (cx,cy,w,h,vx,vy,vw,vh), two-pass IoU matching, BallIdentifier for automatic ball re-acquisition. Evaluated 6 options: band-aid filters, model retraining, centroid-only IoU tracker (fails for fast balls), ByteTrack (chosen), ML Kit plugin switch, plugin fork. ByteTrack replaces BallTracker, KalmanFilter, WallPlanePredictor, TrajectoryExtrapolator, _pickBestBallYolo, _applyPhaseFilter. ~800-1000 lines removed, ~450-500 added.** |
| **Full bounding box as primary tracking data (ADR-059)** | **Existing pipeline extracted only bbox center (2 values), discarding width/height. This limited Kalman to 4-state (no size prediction), made IoU matching impossible, and required separate depth estimation. New approach: 8-state Kalman tracks full bbox + rates of change. Enables IoU matching for fast balls (predicted bbox accounts for motion + size change), built-in depth tracking, and richer object discrimination.** |
| **Pre-ByteTrack AR > 1.8 upper bound only (ADR-068)** | **Rejects elongated YOLO false positives (torso AR 2.4-3.6) before ByteTrack. Upper bound only — no lower bound (no tall-narrow false positives observed, lower bound risked rejecting real ball). Real ball AR max ~1.5; threshold 1.8 gives margin. 2 lines, no pipeline changes. Player head (AR 0.9) still passes — needs different approach.** |

### ⚙️ Mahalanobis Rescue Identity Hijacking (ISSUE-026) — PARTIALLY FIXED
- **Status:** Partially fixed via last-measured-area ratio check (2026-04-16, ADR-072). Hijack cases (3.8x-9x ratios) now blocked by upper bound 2.0. False positive dots still appear during active kicks (likely from non-rescue paths).
- **Original blocker:** Locked track jumps to false positives via Mahalanobis distance matching.
- **What's done:** Area ratio check using last measured ball area (not Kalman predicted). Threshold 2.0/0.3.
- **What remains:** Velocity direction check (dot product) not yet implemented. False positive dots during active kicks may come from other sources.

### ✅ isStatic Flag Never Clears (ISSUE-027) — FIXED (2026-04-13)
- **Status:** Fixed and device-verified.
- **Fix:** Replaced lifetime `_cumulativeDisplacement` accumulator in `_STrack` with sliding window `ListQueue<double>` (last 30 frames). `evaluateStatic()` now sums only the window, making `isStatic` fully two-way. Approach inspired by Frigate NVR production implementation. Research confirmed no standard tracker (ByteTrack/SORT/DeepSORT/OC-SORT/Norfair) has static classification — this is a custom addition. 3 new tests added (static→dynamic, dynamic→static, full cycle).

### ❌ 2-Layer False Positive Filter — ATTEMPTED AND REVERTED (ISSUE-028, 2026-04-13)
- **Status:** Fully reverted. Codebase clean. 176/176 tests.
- **What was tried:** DetectionFilter (pre-ByteTrack AR > 2.5 + size > 5x reject) + TrackQualityGate (post-ByteTrack init delay 4 frames + rolling median AR/size/confidence) + Mahalanobis rescue validation (size ratio + velocity direction).
- **Why it failed:** Init delay blocked BallIdentifier re-acquisition. Real ball stuck at [INIT] while BallIdentifier grabbed poster/head. Track ID churn (1→15). Player head (ar:0.9) unfilterable with geometry.
- **Key lesson:** Never block tracks from BallIdentifier. Post-ByteTrack filters must pass ALL tracks through — can tag/score but must not remove from candidate pool. Implement ONE filter at a time, device-test each.
- **Next approach:** Pre-ByteTrack AR > 1.8 filter implemented (2026-04-13, ADR-068). Monitor-tested, pending field test. Then Mahalanobis rescue validation (code ready to re-apply). One at a time.

### ⚠️ directZone Unreliable for Non-Bottom Zones
- **Status:** Identified. Needs design decision.
- **Blocker:** directZone reports first zone entered (zone 1 for upward kicks), not impact zone. Results calibration-dependent (0/5 to 3/4 correct).
- **Resolution:** Options: trajectory extrapolation to wall, WallPlanePredictor as primary, hybrid approach, or delay decision until depthRatio ~1.0.

| **Session lock to prevent false positive re-acquisition** | **Manager's suggestion: lock ball trackID during kick, reject all others. Works at BallIdentifier level without modifying ByteTrack matching (avoids pitfalls of detection-level filters).** |
| **Trail suppression during kick=idle** | **Dots only during confirming/active/refractory. Eliminates visual noise between kicks without affecting pipeline data collection.** |
| **Bbox area ratio check on Mahalanobis rescue** | **Physical constraint: ball can't change size >2x between frames. Prevents hijacking (3.8x-9x jumps). Uses last measured area (not Kalman predicted) to avoid drift. Threshold 2.0/0.3 — tight upper, relaxed lower for ball shrinking during flight.** |
| **Last-measured-area for Mahalanobis ratio (ADR-072)** | **Kalman predicted area drifts during pure predictions, blocking legitimate rescues. Last measured area is stable. Tested 3 iterations: relaxed Kalman (4/5), tight last-measured (3/5), relaxed-lower last-measured (5/5). 2.0/0.3 threshold balances hijack prevention vs ball tracking.** |

---

## POC Evaluation Checklist

| Item | Status |
|---|---|
| YOLO11n runs on Android (TFLite format) | ✅ PASS |
| YOLO11n runs on iOS (Core ML) | ✅ PASS |
| Real-time detection is smooth enough | ✅ PASS |
| Soccer ball detection accuracy acceptable | ✅ PASS |
| `showOverlays: false` disables native boxes | ✅ PASS |
| Ball trail renders correctly | ✅ PASS |
| Trail coordinates accurate (no offset) | ✅ PASS |
| "Ball lost" badge communicates tracking state | ✅ PASS |
| `flutter analyze` passes (0 issues) | ✅ PASS |
| `flutter test` passes (3/3) | ✅ PASS |
| Architecture suitable to carry forward | ✅ PASS |
| Android feature parity with iOS | ✅ PASS |
| SSD removal clean | ✅ PASS |

### Camera Alignment Aids -- COMPLETE (2026-04-08)
- ✅ **Center crosshair** — Dashed white lines (horizontal + vertical) with small circle at camera optical center. Visible during calibration, auto-hides after reference ball confirm.
- ✅ **Tilt indicator** — Spirit-level bubble in bottom-left, reuses `sensors_plus` accelerometer at 10Hz. Green/yellow/red with LEVEL/TILT UP/TILT DOWN labels.
- ✅ **Post-tap shape validation** — After 4 corners tapped, validates grid shape quality (opposite edge ratios) and corner symmetry (equidistance from camera center). Shows CENTERED (green), BAD SHAPE (red), or NOT SYMMETRIC (yellow) with specific guidance.
- ✅ **Large result overlay temporarily disabled** — Center-screen zone number overlay commented out for testing phase. Audio + bottom-right badge still work.
- ✅ **Device-verified on iPhone 12** — All three aids visible during calibration, disappear after confirm.
- ✅ `flutter analyze` — 0 errors, 0 warnings
- ✅ `flutter test` — 172/172 passing
