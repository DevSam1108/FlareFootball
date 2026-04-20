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
| **Anchor Rectangle feature plan (NEW 2026-04-17)** | `memory-bank/anchor-rectangle-feature-plan.md` — full 5-phase design doc; Phase 1 implemented 2026-04-19 |
| Pre-change code snapshots | `memory-bank/snapshots/` (backup copies before risky edits) |
| **Debug bbox overlay** | `lib/screens/live_object_detection/widgets/debug_bbox_overlay.dart` |

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
| **Target circle false positives (ISSUE-022)** | **🟡 PHYSICAL FIX** | **Remove circles from target fabric. ByteTrack Round 3 fixes tracking, but circles still pollute WallPlanePredictor observations. Phase 1 (no circles) 1/4 correct vs Phase 2 (circles) 0/3 correct — same algorithm. Physical removal eliminates problem at source.** |
| **Zone accuracy: one-row-down bias (Bug 3)** | **🟡 PARTIALLY RESOLVED** | **directZone correct 5/5 in initial video test but 0/5 to 3/4 in follow-up tests with different calibrations. directZone reports first zone entered, not impact zone. See ADR-063. Needs rethink.** |
| **Premature announcements** | **🟡 RECURRED** | **directZone-based decisions still fire mid-flight for upward kicks. Ball enters grid at zone 1, decision fires before reaching actual impact zone. depthRatio consistently 0.35-0.62 at decision time (ball not at wall).** |
| iOS `NSCameraUsageDescription` placeholder | Minor | `"your usage description here"` in `Info.plist`. Must update before any external build. |
| `tennis-ball` priority 2 in class filter | Minor | Diagnostic concession from Phase 9. `Soccer ball` detects correctly; `tennis-ball` filter is unnecessary but harmless. |
| Free Apple Dev cert expires every 7 days | Known | Re-run `flutter run` to re-sign. If "Unable to Verify" appears, delete app and reinstall. See `memory-bank/issueLog.md` ISSUE-002. |
| Off-by-one: `maxActiveMissedFrames=5` == `lostFrameThreshold=5` | Bug 2 — less critical | KickDetector closes gate on same frame ImpactDetector would trigger from ball loss. Less impactful now that result gate accepts `confirming` state. |
| False positive YOLO detections on non-ball objects (kicker body) | **🟡 PARTIALLY FIXED** | **Phase-aware `_applyPhaseFilter()` (2026-04-01) + pre-ByteTrack AR > 1.8 filter (2026-04-13, ADR-068). Torso (AR 2.4-3.6) eliminated. Player head (AR 0.9) still passes — geometrically identical to ball.** |
| Bounce-back false detection | Identified 2026-04-01 | YOLO detects ball on rebound, triggers second decision. Confirmed in Phase 1 (2026-04-06) — bounce-back produced false HIT zone 1 after real HIT zone 6. WallPlanePredictor stale data not fully cleared. |
| Ball identifier false re-acquisition | Identified 2026-04-06 | Re-acquires on player walking (motion-based) and target circles (bounce-back). Should not re-acquire during idle state. |
| Kick-state gate on ImpactDetector — REVERTED | REVERTED (2026-04-08) | Attempted gating ImpactDetector/WallPredictor behind KickDetector. Broke grounded kicks (3/5 undetected). KickDetector's jerk threshold too aggressive for low-velocity shots. See ISSUE-025, ADR-061. |
| Trail dots on non-ball objects | **🟡 PARTIALLY FIXED (2026-04-15)** | **Session lock + trail suppression eliminates idle-period false dots. Dots only shown during confirming/active/refractory. Previous trail-gating attempt (ISSUE-024, ADR-062) killed ALL visualization; new approach preserves kick visualization. See ADR-069, ADR-070.** |
| Phantom impact decisions during idle | Log pollution | ImpactDetector fires decisions during kick=idle. NOT announced (KickDetector result gate works). Diagnostic log noise only. Kick-state gate attempted and reverted. |
| **Mahalanobis rescue identity hijacking (ISSUE-026)** | **🟡 PARTIALLY FIXED (2026-04-16)** | **Bbox area ratio check using last-measured-area with 2.0/0.3 threshold (ADR-072). Blocks hijacking (3.8x-9x jumps) while allowing ball shrinking during flight. 5/5 kicks tracked across 3 test runs. False positive dots during active kicks still appear.** |
| **~~isStatic flag never clears (ISSUE-027)~~** | **✅ FIXED (2026-04-13)** | **Replaced lifetime cumulative displacement with sliding window (last 30 frames). `isStatic` now two-way. Device-verified.** |
| **directZone unreliable for non-bottom zones** | **🟡 DESIGN** | **directZone reports first zone entered (zone 1 for upward kicks), not impact zone. Calibration-sensitive. 0/5 to 3/4 correct depending on calibration. Needs rethink.** |
| **2-layer false positive filter (ISSUE-028)** | **❌ REVERTED (2026-04-13)** | **DetectionFilter + TrackQualityGate + Mahalanobis rescue validation. Init delay broke BallIdentifier re-acquisition. Player head (ar:0.9) unfilterable with geometry. Must implement ONE filter at a time. Start with Mahalanobis rescue validation only.** |
| **~~Bbox area ratio check too aggressive (ISSUE-029)~~** | **✅ FIXED (2026-04-16)** | **Last-measured-area with 2.0/0.3 threshold. Uses real measurement instead of drifting Kalman predicted area. 5/5 kicks across 3 test runs. See ADR-072.** |
| **Session lock stuck ON (ISSUE-030)** | **🔴 OPEN** | **Bounce-back triggers false kick → session lock activates → ball lost → lock never releases (no decision made). Needs safety timeout.** |
| **~~Back button unreachable during calibration / awaiting reference capture (ISSUE-031)~~** | **✅ FIXED (2026-04-19)** | **Z-order bug: back-button `Positioned` block rendered BEFORE two full-screen `GestureDetector`s, so the arena claimed taps on the button. Fixed by moving the `Positioned` block to render AFTER both detectors (before rotate overlay). iOS-verified on iPhone 12. See ADR-074, ISSUE-031.** |

> **Full issue history:** See `memory-bank/issueLog.md` for all issues with root causes and verified solutions.

### Active feature branch — Anchor Rectangle (2026-04-17 onwards)
Phase 1 (Tap-to-Lock Interaction) implemented 2026-04-19. iOS-verified. Android pending. Phases 2–5 not started. See `memory-bank/anchor-rectangle-feature-plan.md` for the full 5-phase design, `memory-bank/decisionLog.md` ADR-073 for the 12 Phase 1 design decisions.

Key API change from Phase 1: `BallIdentifier.setReferenceTrack(List<TrackedObject>)` → `setReferenceTrack(TrackedObject)`. The caller (screen) now filters and selects; `BallIdentifier` just locks onto whatever track it receives. If adding new call sites, pass a single `TrackedObject`, not a list.

---

## Detection Classes (Custom YOLO11n Model)

| Class | Notes |
|---|---|
| `Soccer ball` | Primary target |
| `ball` | General ball; also fires on soccer balls |
| `tennis-ball` | Incidental; accepted at lowest priority |

Labels are **embedded in the model** -- there is no external label file for the YOLO path.

---

## What Is Out of Scope (Current Phase)

Do not introduce these unless explicitly instructed:

- User authentication, accounts, or sessions
- Uploading or persisting detection results to a server
- Server-side / cloud inference
- Video recording or playback
- Screens beyond what the current flow requires
