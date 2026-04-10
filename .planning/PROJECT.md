# Flare Football — On-Device Object Detection

## What This Is

A mobile feasibility POC evaluating whether YOLO11n can run real-time, on-device soccer ball detection and tracking on Flutter for both iOS and Android. The app detects soccer balls via camera, tracks their movement across frames, draws a visual trail showing the ball's path, and displays a "Ball lost" badge when tracking is interrupted. Built as an internal engineering study to determine whether to invest in this feature for the real Flare Football product.

## Core Value

Real-time soccer ball detection and tracking must run on-device with acceptable speed and accuracy on both iOS and Android — no cloud inference, no perceptible lag.

## Requirements

### Validated

- ✓ YOLO11n runs real-time on Android (TFLite) and iOS (Core ML) — v1.0
- ✓ SSD MobileNet fallback runs inference in background isolate — v1.0
- ✓ Backend switching via `DETECTOR_BACKEND` env var at build time — v1.0
- ✓ Landscape orientation for YOLO detection screen — v1.0
- ✓ Bounding box rendering on SSD MobileNet path — v1.0
- ✓ Three-screen navigation (Home → Live Camera, Home → Photo Analysis) — v1.0
- ✓ Evaluation evidence captured (screenshots + recordings, both platforms) — v1.0
- ✓ Native YOLOView bounding boxes disabled via `showOverlays: false` — v1.1
- ✓ `mounted` guard on all detection callbacks — v1.1
- ✓ Ball center-point extraction from YOLO normalizedBox coordinates — v1.1
- ✓ Ball position tracking in bounded time-windowed queue (~1.5s) — v1.1
- ✓ Occlusion handling with null sentinels and gap rendering — v1.1
- ✓ Class priority filter (Soccer ball > ball, rejects tennis-ball) — v1.1
- ✓ Nearest-neighbor tiebreaker for multi-detection frames — v1.1
- ✓ Trail auto-clear after 30+ consecutive missed frames — v1.1
- ✓ Fading dot trail with age-based opacity gradient — v1.1
- ✓ Connecting line segments between trail positions — v1.1
- ✓ Occlusion gap skipping in trail rendering — v1.1
- ✓ Trail CustomPainter with RepaintBoundary isolation — v1.1
- ✓ Trail renders correctly in landscape on YOLO path — v1.1
- ✓ "Ball lost" badge overlay when ball missing for 3+ frames — v1.1

- ✓ Android `onResult` fixed — root cause: missing `aaptOptions { noCompress 'tflite' }` — v1.2
- ✓ Android coordinate correction via MethodChannel rotation polling — v1.2
- ✓ Trail dots, connecting lines, and "Ball lost" badge visually confirmed on Galaxy A32 — v1.2
- ✓ Android feature parity with iOS achieved — v1.2
- ✓ Calibration mode — tap 4 corners to register target position — v1.3 Phase 1
- ✓ 8-parameter DLT homography transform (pure Dart) — v1.3 Phase 1
- ✓ Zone mapper with pointToZone, grid geometry, zone centers — v1.3 Phase 1
- ✓ Green wireframe grid overlay with zone numbers 1-9 — v1.3 Phase 1
- ✓ Inverse coordinate transform for touch-to-normalized conversion — v1.3 Phase 1

### Active

**Current Milestone: v1.3 Target Zone Impact Detection**

**Goal:** Detect which numbered zone (1-9) on a target sheet a kicked soccer ball hits, using trajectory prediction and multi-signal impact detection — extending the existing YOLO detection pipeline with pure Dart math.

**Target features:**
- Kalman filter (4-state: px, py, vx, vy) for trajectory smoothing and prediction through missed frames
- Multi-signal impact detection (trajectory extrapolation + edge-filter + velocity change)
- Homography-based zone mapping from impact point to zone 1-9
- Visual feedback: zone highlight + large number overlay + state machine (Ready → Tracking → Result → Cooldown)
- Audio feedback: pre-recorded number callouts (1-9) + miss buzzer
- Depth estimation via ball apparent size tracking to filter false impacts

### Out of Scope

- Production UI polish or design system — POC only
- User authentication, accounts, or sessions — not needed for evaluation
- Uploading or persisting detection/tracking results — POC only
- Server-side / cloud inference — on-device is the core constraint
- Video recording or playback — not evaluating this
- Multi-ball tracking — single ball is the target use case
- **SSD MobileNet / TFLite tracking** — model is old; YOLO only going forward
- Automatic CV-based target detection (opencv_dart) — deferred to production; adds ~50MB dependency
- 60fps camera mode — deferred; requires platform-specific camera code (Swift/Kotlin)
- Raw frame access for frame differencing — deferred to avoid platform complexity in v1
- ArUco markers — requires opencv_dart and modifying physical target; deferred to production

## Context

- **Flutter app** (49 Dart files, ~3,264 LOC) with YOLO as the primary ML pipeline: `DETECTOR_BACKEND=yolo`
- **SSD MobileNet path** exists in code for reference but is frozen — no new features
- **YOLO path** uses `ultralytics_yolo: ^0.2.0` with `YOLOView` widget. `onResult` callback fires per frame with detection results. Native bounding boxes disabled via `showOverlays: false`
- **Ball tracking** via `BallTracker` service with 1.5s time-windowed `ListQueue`, occlusion sentinels, and 30-frame auto-reset. `TrailOverlay` CustomPainter renders fading dot trail with connecting lines
- **"Ball lost" badge** appears at top-right after 3 consecutive missed frames (~100ms), disappears on re-detection
- **Custom YOLO11n model** trained on 3 classes: `Soccer ball`, `ball`, `tennis-ball`. Labels embedded in model
- **Camera aspect ratio** is 4:3 (`ultralytics_yolo` uses `.photo` session preset on iOS: 4032×3024)
- **Target devices:** iPhone 12 (A14 Bionic, iOS 17.1.2), Samsung Galaxy A32 (SM-A325F, Android 12)
- **Dev environment:** MacBook Pro (M5, 16GB), Flutter 3.38.9, Dart 3.10.8, Xcode 26.2
- **Known limitation:** Tracking quality described as "very poor" on iPhone 12 — may be a model limitation rather than code issue
- **Android onResult RESOLVED:** Root cause was missing `aaptOptions { noCompress 'tflite' }`. Fixed. `Soccer ball` detected at 0.868 confidence on Galaxy A32.
- **Calibration system built:** Phase 1 complete — 8-parameter DLT homography, zone mapper, green grid overlay, 25 unit tests passing. Device-verified on both platforms.
- **Target sheet:** 1760mm x 1120mm, 3x3 grid (zones 1-9), each zone ~587mm x 373mm. App uses tapped corners (never "sees" the target visually).
- **Shipped milestones:** v1.0 (Detection Feasibility), v1.1 (Ball Tracking), v1.2 (Android Verification)

## Constraints

- **Framework**: Flutter/Dart — existing codebase, cannot change
- **ML packages**: `ultralytics_yolo ^0.2.0` — do not upgrade without testing
- **On-device only**: No network calls for inference or tracking
- **YOLO only**: Tracking features on YOLO pipeline only (SSD path frozen)
- **Performance**: Tracking logic must not cause visible jank — inference already runs on separate thread, tracking overhead must be minimal
- **Landscape lock**: YOLO screen is landscape-only, tracking UI must respect this

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| YOLO11n nano over larger variants | Prioritise speed and on-device compatibility for POC | ✓ Good |
| Platform-native model formats (TFLite / Core ML) | Best performance per platform | ✓ Good |
| Model files gitignored | Large binaries managed outside VCS | ✓ Good |
| Landscape-only for YOLO screen | Matches realistic phone orientation for filming a pitch | ✓ Good |
| Background isolate for TFLite inference | Prevents UI jank during CPU-intensive work | ✓ Good |
| SSD/TFLite path dropped from v1.1 | Model is old; not worth investing in tracking for it | ✓ Scope reduction |
| `showOverlays: false` on YOLOView | Confirmed working; custom overlay is only rendering layer | ✓ Good |
| Camera AR = 4:3 (not 16:9) | ultralytics_yolo `.photo` session preset on iOS = 4032×3024 | ✓ Good (fixed ~10% Y-offset) |
| Time-windowed ListQueue for trail | Bounded memory, automatic eviction of old positions | ✓ Good |
| Occlusion sentinels (not separate list) | Simpler data structure, gap positions preserved in sequence | ✓ Good |
| Min-distance dedup in BallTracker | Prevents dot clustering at ~30fps during slow movement | ✓ Good |
| `Positioned` must be direct Stack child | IgnorePointer goes inside Positioned, not outside — Flutter constraint | ✓ Good (fixed runtime crash) |
| ballLostThreshold = 3 frames | ~100ms at 30fps — fast enough to feel responsive | ✓ Good |

| `onResult` not firing on Android | v1.2 recording analysis — zero overlays across 42s of footage | ✓ Fixed (aaptOptions) |
| Android coordinate correction via MethodChannel | Poll `Surface.ROTATION_*` to flip coords for rotation=3 | ✓ Good |
| Manual calibration over retrained YOLO / opencv_dart / dual models | Zero platform code, zero perf impact, mathematical precision, works on Galaxy A32 | ✓ Good |
| Multi-signal impact detection over naive last-position | Trajectory + depth + edge-filter + velocity prevents false positives | — Pending |
| Start with 30fps, defer 60fps | 30fps minimum viable; 60fps requires platform camera code | — Pending |
| Calibration-based focal length (not camera intrinsics API) | Pure Dart, avoids platform-specific APIs | — Pending |

---
*Last updated: 2026-03-09 after v1.3 milestone start*
