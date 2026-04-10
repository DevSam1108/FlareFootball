# Milestones

## v1.0 — Detection Feasibility POC

**Goal:** Evaluate whether YOLO11n can run real-time, on-device soccer ball detection on mobile devices at acceptable speed and accuracy.

**Shipped:**
- YOLO11n real-time detection on Android (TFLite) and iOS (Core ML)
- SSD MobileNet fallback with background Dart isolate inference
- Build-time backend switching via `DETECTOR_BACKEND` env var
- Landscape-only orientation for YOLO detection screen
- Bounding box rendering on SSD MobileNet path (custom `BoxWidget`)
- Three-screen navigation: Home, Live Camera, Photo Analysis
- Evaluation evidence captured (screenshots + recordings, both platforms, multiple scenarios)

**Phases:** 1-5 (informal — predates GSD workflow)

**Outcome:** Detection feasibility confirmed. Both pipelines run on target devices. Architecture is clean and suitable to carry forward.

---
*Archived: 2026-02-23*

## v1.1 — Ball Tracking

**Goal:** Prove that frame-to-frame ball tracking with a fading visual trail is technically feasible on-device at acceptable performance on the YOLO pipeline.

**Shipped:**
- Debug dot overlay with FILL_CENTER coordinate mapping, verified on iPhone 12
- BallTracker service with time-windowed ListQueue, occlusion sentinels, and 30-frame auto-reset
- TrailOverlay CustomPainter with fading dots, connecting lines, and occlusion gap skipping
- Camera aspect ratio corrected from 16:9 to 4:3 for accurate Y-axis positioning
- "Ball lost" badge overlay — appears within ~100ms of losing ball, disappears on re-detection
- All features device-verified on iPhone 12 in both landscape orientations

**Phases:** 6-8 (3 phases, 6 plans)
**Scope change:** SSD/TFLite path dropped — YOLO only on both platforms.
**Timeline:** 2026-02-23 -> 2026-02-24

**Outcome:** Ball tracking feasibility confirmed. Trail rendering, occlusion handling, and status badge all work at acceptable performance on iPhone 12. Galaxy A32 Android testing deferred (Android SDK not configured on dev Mac).

---
*Archived: 2026-02-24*

## v1.2 — Android Verification (Complete)

**Goal:** Diagnose and fix the Android YOLO pipeline so detection, ball tracking, trail rendering, and the "Ball lost" badge all work on Galaxy A32 — achieving feature parity with the verified iOS behavior.

**Context:** Recording analysis (2026-02-25) confirmed `onResult` callback is NOT firing on Android across 42 seconds of footage with ball clearly visible. Camera feed renders correctly. Root cause candidates: GPU delegate failure on Mali-G52, EventChannel subscription dropping after `setState`, or `aaptOptions` misconfiguration.

**Shipped:**
- Root cause identified: missing `aaptOptions { noCompress 'tflite' }` in build.gradle
- Android coordinate correction via MethodChannel rotation polling
- Trail dots, connecting lines, and "Ball lost" badge verified on Galaxy A32
- Full feature parity with iOS achieved

**Phases:** 9-10 (2 phases, 4 plans)
**Timeline:** 2026-02-25 -> 2026-03-09

**Outcome:** Android feature parity confirmed. All tracking features work on both platforms.

---
*Archived: 2026-03-09*

## v1.3 — Target Zone Impact Detection (In Progress)

**Goal:** Detect which numbered zone (1-9) on a target sheet a kicked soccer ball hits, using trajectory prediction and multi-signal impact detection — extending the existing YOLO detection pipeline with pure Dart math.

**Prerequisites (already complete):**
- Calibration mode — tap 4 corners to register target position
- 8-parameter DLT homography transform (pure Dart)
- Zone mapper with pointToZone, grid geometry, zone centers
- Green wireframe grid overlay with zone numbers 1-9
- Inverse coordinate transform for touch-to-normalized conversion
- 25 unit tests passing, device-verified on both platforms

**Phases:** 11-14 (4 phases)
- Phase 11: Kalman Filter and Trajectory Tracking (TRAJ-01 through TRAJ-04)
- Phase 12: Impact Detection, Zone Mapping, and Visual Feedback (IMPACT-01 through IMPACT-06, VISUAL-01 through VISUAL-05)
- Phase 13: Audio Feedback (AUDIO-01 through AUDIO-03)
- Phase 14: Depth Estimation (DEPTH-01 through DEPTH-03)

**Requirements:** 18 total (4 trajectory, 6 impact, 5 visual, 3 audio, 3 depth)
**Started:** 2026-03-09
