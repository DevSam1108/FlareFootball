# Decision Log (Architecture Decision Records)

> **Purpose:** Evidence-based record of every significant technical decision made in this project. Each entry documents what was chosen, what was rejected, and why. Use this as the single source of truth when someone asks "why did you do it this way?"

> **Format:** ADR-NNN entries grouped by project phase, ordered chronologically within each group.

---

## v1.0 — Detection Feasibility (2026-02)

### ADR-001: YOLO11n (Nano) Over Larger YOLO Variants

- **Date:** 2026-02 (project inception)
- **Context:** Needed to choose a YOLO model size for the on-device feasibility POC. YOLO11 comes in 5 sizes: nano (n), small (s), medium (m), large (l), extra-large (x). Larger models are more accurate but slower and heavier.
- **Options Considered:**
  1. **YOLO11n (nano)** — smallest, fastest, ~6MB, lowest accuracy
  2. **YOLO11s (small)** — ~22MB, moderate speed/accuracy
  3. **YOLO11m/l/x** — 50-100MB+, highest accuracy, slowest
- **Decision:** YOLO11n (nano)
- **Rationale:** The POC's primary question is "can this run in real-time on a phone?" Speed and on-device compatibility matter more than maximum accuracy for feasibility. Nano is the only variant that can comfortably run at 25-30fps on iPhone 12 and 10-20fps on Galaxy A32. Larger variants would fail the real-time requirement on mid-range Android.
- **Trade-offs Accepted:** Lower detection accuracy than larger models. Acceptable for POC; production could upgrade to YOLO11s if nano proves too inaccurate.
- **Status:** Accepted. Validated — Soccer ball detected at 0.868 confidence on Galaxy A32.

---

### ADR-002: Flutter as the Application Framework

- **Date:** 2026-02 (project inception)
- **Context:** Needed a cross-platform mobile framework for the POC that supports both iOS and Android from a single codebase.
- **Options Considered:**
  1. **Flutter (Dart)** — cross-platform, single codebase, strong plugin ecosystem for ML
  2. **React Native** — cross-platform, JavaScript, less mature ML plugin ecosystem
  3. **Native (Swift + Kotlin)** — maximum performance, double the development effort
- **Decision:** Flutter
- **Rationale:** Single codebase evaluates both platforms simultaneously. The `ultralytics_yolo` Flutter package provides a ready-made YOLO integration. Dart is performant enough for the overlay rendering and math (Kalman filter, homography). Native would double development effort for a feasibility study that doesn't need platform-specific optimizations.
- **Trade-offs Accepted:** Slightly lower ML performance than fully native. Platform-specific camera quirks must be handled through the plugin layer rather than directly.
- **Status:** Accepted

---

### ADR-003: `ultralytics_yolo` Package for YOLO Integration

- **Date:** 2026-02 (project inception)
- **Context:** Needed a Flutter package to run YOLO11n inference on-device. The package must handle camera management, model loading, and inference across both iOS (Core ML) and Android (TFLite).
- **Options Considered:**
  1. **`ultralytics_yolo: ^0.2.0`** — official Ultralytics Flutter package, wraps Core ML and TFLite natively, provides `YOLOView` widget with camera + inference
  2. **`tflite_flutter` + manual camera** — lower-level TFLite access, requires managing camera separately, no iOS Core ML support
  3. **`google_mlkit_object_detection`** — Google ML Kit, limited to their models, no custom YOLO support
- **Decision:** `ultralytics_yolo: ^0.2.0`
- **Rationale:** Only package that provides a complete YOLO pipeline (camera + inference + results) as a single widget. Handles platform-specific model formats automatically. Maintained by Ultralytics (the YOLO creators). Despite some known Android bugs (EventChannel issues, GPU delegate failures), the plugin is the path of least resistance for a POC.
- **Trade-offs Accepted:** Plugin bugs required workarounds (aaptOptions, MethodChannel rotation). Plugin internals are opaque — debugging requires reading plugin source in pub-cache. Locked at `^0.2.0` to avoid breaking changes.
- **Status:** Accepted

---

### ADR-004: Platform-Native Model Formats (TFLite + Core ML)

- **Date:** 2026-02
- **Context:** YOLO11n can be exported to multiple inference formats. Each mobile platform has an optimized runtime.
- **Options Considered:**
  1. **TFLite for Android + Core ML (.mlpackage) for iOS** — platform-native, best performance per platform
  2. **TFLite for both** — simpler (one format), but suboptimal on iOS
  3. **ONNX for both** — universal format, but requires ONNX Runtime on both platforms (heavier)
- **Decision:** TFLite for Android, Core ML for iOS
- **Rationale:** Each platform's native ML runtime is the most optimized path. Core ML leverages Apple's Neural Engine on A14+. TFLite leverages Android's ML delegate system. Using native formats means the `ultralytics_yolo` plugin handles loading automatically without extra runtime dependencies.
- **Trade-offs Accepted:** Must maintain two model files. Model must be re-exported if YOLO training changes.
- **Status:** Accepted

---

### ADR-005: On-Device Inference Only (No Cloud)

- **Date:** 2026-02
- **Context:** The POC evaluates real-time ball detection. Inference could run on-device or via cloud API.
- **Options Considered:**
  1. **On-device only** — fully offline, zero latency from network, privacy-preserving
  2. **Cloud inference** — more powerful hardware, higher accuracy models possible
  3. **Hybrid** — on-device for real-time, cloud for post-processing
- **Decision:** On-device only
- **Rationale:** The core research question is "can on-device ML work well enough?" Cloud inference defeats the purpose. Real-time ball tracking requires sub-frame latency (~33ms at 30fps) — network round-trips add 50-200ms minimum. The POC must prove the device's own hardware is sufficient.
- **Trade-offs Accepted:** Limited to models that fit on-device. Cannot leverage larger, more accurate server-side models.
- **Status:** Accepted. All 4 core research questions answered positively.

---

### ADR-006: Landscape-Only Orientation for Detection Screen

- **Date:** 2026-02
- **Context:** The live camera detection screen needs a fixed orientation for consistent coordinate mapping and user experience.
- **Options Considered:**
  1. **Landscape-only** — matches how a phone on a tripod films a pitch/goal
  2. **Portrait-only** — natural phone holding position, but narrow field of view for a goal
  3. **Auto-rotate** — flexible, but coordinate mapping becomes complex and UX is inconsistent
- **Decision:** Landscape-only (forced via `SystemChrome.setPreferredOrientations` in `initState`, restored in `dispose`)
- **Rationale:** The target use case is phone on tripod behind the kicker, filming a goal with a target sheet. Landscape provides the widest field of view for the goal. All coordinate math (FILL_CENTER crop, homography calibration) assumes a fixed landscape frame. Auto-rotate would require dynamic recalculation of all coordinate transforms.
- **Trade-offs Accepted:** Requires careful orientation lock/restore pair (matched `initState`/`dispose`). Android has a timing race where the first 2-3 frames may still be in portrait (see Pitfall 4 in planning research).
- **Status:** Accepted

---

### ADR-007: Model Files Gitignored (Manual Placement)

- **Date:** 2026-02
- **Context:** The YOLO model files (`yolo11n.tflite` ~6MB, `yolo11n.mlpackage` ~12MB) need to be available on the dev machine but shouldn't bloat the codebase.
- **Options Considered:**
  1. **Gitignore + manual placement** — developer copies files to correct platform directories
  2. **Check into repo** — simple, always available, but large binary bloat
  3. **Git LFS** — handles large files in git, but adds infrastructure complexity
- **Decision:** Gitignore + manual placement
- **Rationale:** Project has no git repository (local-only by developer decision). Even if it did, large binary ML models don't belong in source control. Manual placement is documented in CLAUDE.md with exact paths. The files are stable (same model throughout the POC).
- **Trade-offs Accepted:** New developer setup requires manual file copy. Risk of missing files causing silent inference failure (mitigated by documentation and issueLog ISSUE-001).
- **Status:** Accepted

---

### ADR-008: `showOverlays: false` to Suppress Native YOLO Bounding Boxes

- **Date:** 2026-02
- **Context:** `YOLOView` can render native bounding boxes over detected objects. The app draws its own custom trail overlay instead.
- **Options Considered:**
  1. **`showOverlays: false`** — suppress native boxes, render custom overlay
  2. **`showOverlays: true`** — use native boxes alongside custom overlay
  3. **`showOverlays: true` only** — use native rendering, no custom overlay
- **Decision:** `showOverlays: false`
- **Rationale:** The custom `TrailOverlay` provides a more informative visualization (fading trail, connecting lines, occlusion handling) than the plugin's basic bounding boxes. Double-rendering would be visually noisy. Native overlays are useful only as a diagnostic canary to confirm inference is running.
- **Trade-offs Accepted:** Lose quick visual confirmation of inference. Addressed by using `showOverlays: true` temporarily during Android debugging.
- **Status:** Accepted

---

### ADR-009: Singleton Pattern for Services

- **Date:** 2026-02
- **Context:** Services like `NavigationService`, `SnackBarService`, and later `AudioService` need to be accessible from multiple parts of the app without dependency injection overhead.
- **Options Considered:**
  1. **Singleton with private named constructor** — `ClassName._(); static final instance = ClassName._();`
  2. **Provider/InheritedWidget DI** — Flutter's built-in DI, but heavier setup
  3. **GetIt service locator** — popular DI package, but adds a dependency
- **Decision:** Singleton with private named constructor
- **Rationale:** For a POC with 2 screens and 3-4 services, full DI is over-engineering. The singleton pattern is simple, testable (tests can create mock instances), and has zero dependencies. MobX and Provider were removed during cleanup, so there's no existing DI framework to hook into.
- **Trade-offs Accepted:** Less flexible than proper DI. Harder to swap implementations in tests (but unit tests don't need to for this POC scope).
- **Status:** Accepted

---

### ADR-010: Build-Time Backend Switching via Environment Variable

- **Date:** 2026-02
- **Context:** Initially, the app had two ML backends (SSD MobileNet + YOLO). A mechanism was needed to select the active backend at build time.
- **Options Considered:**
  1. **`DETECTOR_BACKEND` Dart env var** — `--dart-define=DETECTOR_BACKEND=yolo` at build time
  2. **Runtime toggle in UI** — user-selectable in the app
  3. **Compile-time flag** — `#ifdef` style conditional compilation
- **Decision:** `DETECTOR_BACKEND` Dart environment variable with `DetectorBackend` enum
- **Rationale:** Build-time selection means unused backend code is tree-shaken. No runtime overhead. Clean separation via enum switch statements in `detector_config.dart` and `main.dart`. After SSD removal (ADR-020), only `yolo` exists, but the infrastructure is preserved for future extensibility.
- **Trade-offs Accepted:** Can't switch backends without rebuilding. After SSD removal, the infrastructure is slightly over-engineered for a single backend — but removing it would lose the future extensibility pattern.
- **Status:** Accepted. Currently YOLO-only.

---

## v1.1 — Ball Tracking (2026-02-23 to 2026-02-24)

### ADR-011: Camera Aspect Ratio = 4:3 (Not 16:9)

- **Date:** 2026-02-23
- **Context:** The ball trail dots showed a consistent ~10% Y-axis offset from the actual ball position on iOS. Root cause investigation needed.
- **Options Considered:**
  1. **Assume 16:9** — standard video aspect ratio
  2. **Assume 4:3** — photo session preset aspect ratio
  3. **Runtime detection** — read actual camera frame dimensions
- **Decision:** 4:3, hardcoded in `YoloCoordUtils`
- **Rationale:** `ultralytics_yolo` uses `.photo` session preset on iOS (4032x3024 = 4:3). On Android, CameraX explicitly targets `AspectRatio.RATIO_4_3`. Source-verified in plugin code (`YOLOView.swift` and `YOLOView.kt`). Using 16:9 caused ~10% Y-offset because the FILL_CENTER crop calculation was based on the wrong frame geometry. Device-verified fix on iPhone 12.
- **Trade-offs Accepted:** Hardcoded rather than runtime-detected. If a future device delivers a different AR, the constant needs updating. Acceptable for POC with known test devices.
- **Status:** Accepted. Empirically verified on both iPhone 12 and Galaxy A32.

---

### ADR-012: CustomPainter + Stack for Trail Rendering

- **Date:** 2026-02-23
- **Context:** Need to render a ball trail overlay on top of the `YOLOView` camera preview.
- **Options Considered:**
  1. **`CustomPainter` in a `Stack`** — full control over drawing, layered above YOLOView
  2. **Native overlay via plugin** — modify plugin to draw trail natively
  3. **Positioned widgets per dot** — Flutter widgets for each trail point
- **Decision:** `CustomPainter` in a `Stack`, wrapped in `RepaintBoundary` and `IgnorePointer`
- **Rationale:** `CustomPainter` gives pixel-level control for fading dots, connecting lines, and occlusion gap skipping. `RepaintBoundary` isolates repaint to the overlay only (prevents `YOLOView` from being repainted on every detection). `IgnorePointer` prevents the overlay from consuming touch events. Native plugin modification would require forking. Positioned widgets would be too expensive at 30fps with 45+ trail points.
- **Trade-offs Accepted:** `shouldRepaint` always returns `true` (list identity is unreliable for comparison). Minor overhead but negligible on both test devices.
- **Status:** Accepted

---

### ADR-013: BallTracker Design — Bounded ListQueue with Occlusion Sentinels

- **Date:** 2026-02-23
- **Context:** Need a service to accumulate ball positions over time for trail rendering, with handling for frames where the ball is not detected.
- **Options Considered:**
  1. **Bounded 1.5s ListQueue with occlusion sentinels and 30-frame auto-reset** — time-windowed, handles gaps
  2. **Simple list with fixed max length** — simpler but no occlusion handling
  3. **Ring buffer** — memory-efficient but harder to iterate for rendering
- **Decision:** Bounded 1.5s `ListQueue` with:
  - Occlusion sentinels (null-position entries marking detection gaps)
  - 30-frame auto-reset (clears trail after ~1s of no detection)
  - Min-distance dedup (`_minDistSq = 0.000025`, ~0.5% of frame) to prevent dot clustering at 30fps
- **Rationale:** Time-based window ensures trail length scales with display time, not frame count. Occlusion sentinels let `TrailOverlay` skip connecting lines across gaps. Auto-reset prevents stale trails from lingering. Min-distance dedup prevents dot clustering when ball is stationary.
- **Trade-offs Accepted:** More complex than a simple list. Sentinel-based gap detection requires special handling in the painter.
- **Status:** Accepted

---

### ADR-014: Class Priority Filtering for Multi-Detection Frames

- **Date:** 2026-02-23
- **Context:** The YOLO model detects 3 classes: `Soccer ball`, `ball`, `tennis-ball`. Multiple detections can fire in the same frame. Need a strategy to pick the best one.
- **Options Considered:**
  1. **Priority-based selection** — `Soccer ball` (0) > `ball` (1) > `tennis-ball` (2), then confidence, then nearest-neighbor
  2. **Confidence-only** — pick highest confidence regardless of class
  3. **Filter to `Soccer ball` only** — reject all other classes
- **Decision:** Priority-based: class priority first, then confidence within same class, then nearest-neighbor tiebreaker using `_tracker.lastKnownPosition`
- **Rationale:** `Soccer ball` is the primary target and should always be preferred. `ball` is a valid fallback (often fires on the same soccer ball). `tennis-ball` is incidental but harmless to accept at lowest priority. Nearest-neighbor tiebreaker prevents trail from jumping between two detections of the same class at different positions.
- **Trade-offs Accepted:** `tennis-ball` is accepted when no better detection is available. This was a diagnostic concession from Phase 9 that turned out unnecessary.
- **Status:** Accepted

---

### ADR-015: `ballLostThreshold = 3` Frames

- **Date:** 2026-02-24
- **Context:** The "Ball lost" badge needs a threshold for how many consecutive missed frames before declaring the ball lost.
- **Options Considered:**
  1. **3 frames** — ~100ms at 30fps, responsive but risks flicker
  2. **5 frames** — ~170ms, more stable but delayed
  3. **10 frames** — ~330ms, very stable but sluggish response
- **Decision:** 3 frames (~100ms at 30fps)
- **Rationale:** 100ms is fast enough that the badge appears promptly when the ball leaves frame, but long enough to avoid single-frame false positives from detection jitter. On Android at lower FPS (~10fps), 3 frames = ~300ms — still acceptable. Tested on both devices and confirmed the timing feels right.
- **Trade-offs Accepted:** At very low Android FPS, badge latency is proportionally longer (600ms at 5fps). Documented as expected behavior, not tuned per-platform.
- **Status:** Accepted

---

## v1.2 — Android Verification (2026-02-25 to 2026-03-09)

### ADR-016: aaptOptions Fix for TFLite Model Integrity

- **Date:** 2026-02-25
- **Context:** Android `onResult` callback never fired. Camera preview worked fine. 42 seconds of footage, zero detections. Root cause investigation.
- **Options Considered:**
  1. **Add `aaptOptions { noCompress 'tflite' }` to `build.gradle`** — prevent Gradle from compressing the model
  2. **Rename model extension** — use `.bin` or other non-compressed extension
  3. **Use `assets/` directory in Flutter** — let Flutter asset system manage the file
- **Decision:** `aaptOptions { noCompress 'tflite' }` in `android/app/build.gradle`
- **Rationale:** Root cause was Gradle's AAPT compressing `.tflite` files by default. TFLite requires memory-mapped file access, which fails on compressed files. The fix is one line in `build.gradle` and is the standard solution documented in TFLite and Ultralytics issue trackers (#393). Renaming would break the plugin's internal path resolution. Flutter's asset system would require plugin modifications.
- **Trade-offs Accepted:** None. This is the correct, standard fix. Removing this line would silently break Android inference.
- **Status:** Accepted. Root cause verified and documented in issueLog ISSUE-001.

---

### ADR-017: Android Coordinate Correction via MethodChannel

- **Date:** 2026-02-25
- **Context:** After fixing `onResult`, trail dots appeared at mirrored positions in landscape-right orientation on Android. `ultralytics_yolo` doesn't distinguish landscape-left from landscape-right on Android.
- **Options Considered:**
  1. **MethodChannel polling** — `MainActivity.kt` exposes `Surface.ROTATION_*` via a platform channel, Dart polls every 500ms and flips coordinates when rotation=3
  2. **Plugin modification** — fork the plugin to handle rotation internally
  3. **Sensor-based detection** — use accelerometer to detect orientation
  4. **Accept the bug** — document that one landscape direction has mirrored coordinates
- **Decision:** MethodChannel polling with `(1-x, 1-y)` flip for rotation=3
- **Rationale:** Minimal platform code (10 lines of Kotlin in `MainActivity.kt`). 500ms polling interval is sufficient since orientation doesn't change rapidly during detection. Plugin forking is heavy for a POC. Sensor-based would add complexity and a dependency. Accepting the bug would make half the landscape orientations unusable.
- **Trade-offs Accepted:** 500ms polling introduces slight lag on orientation change (negligible in practice). Added platform-specific Kotlin code (the only non-Dart platform code in the project besides model files).
- **Status:** Accepted. Device-verified on Galaxy A32.

---

### ADR-018: Logcat-First Diagnostic Methodology

- **Date:** 2026-02-25
- **Context:** Android `onResult` was silent. Multiple possible root causes existed across a 7-step callback chain. Needed a systematic approach.
- **Options Considered:**
  1. **Logcat-first diagnosis** — read plugin logs before changing any code, identify which chain step fails
  2. **Code-changes-first** — guess likely cause and apply fixes
  3. **Plugin upgrade** — bump to latest version hoping it fixes the issue
- **Decision:** Logcat-first diagnosis following a strict 7-step protocol
- **Rationale:** Without logcat, there's no evidence for which of 7 chain steps (CameraX → ObjectDetector → EventChannel → Dart) is failing. Guessing wastes effort and can mask the actual bug (see Pitfall 7 — diagnostic widgets that accidentally trigger EventChannel reconnect). The strict protocol: (1) verify model file, (2) read logcat, (3) canary test with `showOverlays: true`, (4) test `useGpu: false`, (5) check EventChannel, (6) verify coordinates, (7) verify badge behavior.
- **Trade-offs Accepted:** Slower initial progress than guessing, but eliminates false leads.
- **Status:** Accepted. Protocol successfully identified aaptOptions as root cause on first pass.

---

### ADR-019: Android Performance Accepted As-Is

- **Date:** 2026-03-05
- **Context:** Galaxy A32 runs inference at ~10-15fps compared to iPhone 12's ~30fps. Should this be optimized?
- **Options Considered:**
  1. **Accept and document** — record FPS as a finding, don't optimize
  2. **Enable GPU delegate** — potentially faster but Mali-G52 has compatibility issues
  3. **Reduce model input resolution** — faster inference but lower accuracy
  4. **Add frame skipping** — reduce inference load
- **Decision:** Accept and document
- **Rationale:** This is a feasibility POC. The question is "does it work?" not "is it fast enough for production?" Galaxy A32 is a mid-range 2021 device with no dedicated NPU (Helio G80, Mali-G52). 10-15fps is the expected performance ceiling for YOLO11n on this hardware. Optimizing would mask the real-world performance data the POC needs to capture. Production can target better hardware or use GPU delegates on compatible devices.
- **Trade-offs Accepted:** Trail has fewer dots per second. "Ball lost" badge latency is proportionally longer. Documented as expected behavior differences.
- **Status:** Accepted

---

## Codebase Cleanup (2026-03-05 to 2026-03-09)

### ADR-020: SSD/MobileNet Path Fully Removed

- **Date:** 2026-03-05
- **Context:** The original repo had an SSD MobileNet v1 detection path alongside YOLO. After confirming YOLO works on both platforms, the SSD path was unused legacy code.
- **Options Considered:**
  1. **Remove entirely** — delete all SSD files, dependencies, routes
  2. **Keep but disable** — leave code in place, just don't route to it
  3. **Keep as fallback** — maintain for devices where YOLO doesn't work
- **Decision:** Remove entirely
- **Rationale:** SSD path was never evaluated on the target devices. It used `tflite_flutter` which conflicted with `ultralytics_yolo`'s LiteRT dependency (required a `configurations.all { exclude }` block in `build.gradle`). Dead code increases maintenance burden. The `DETECTOR_BACKEND` infrastructure is preserved for future backends — SSD could be re-added if needed. Removed: all SSD Dart files, `tflite_flutter` dependency, `image` dependency, `camera` dependency, `image_picker` dependency, photo analysis screen, related routes.
- **Trade-offs Accepted:** No SSD fallback. If YOLO fails on a device, there's no backup. Acceptable for POC — YOLO is confirmed working on both target devices.
- **Status:** Accepted

---

### ADR-021: No Git / No GitHub (Local-Only Project)

- **Date:** 2026-03-05
- **Context:** Developer decision about version control for the POC.
- **Options Considered:**
  1. **No VCS** — local-only, memory-bank files serve as institutional memory
  2. **Git + GitHub** — standard VCS, remote backup, history
  3. **Git local-only** — local history without remote
- **Decision:** No VCS, local-only
- **Rationale:** Developer's explicit choice. The POC is a personal feasibility study, not a team project. Memory-bank files provide session-to-session continuity. CLAUDE.md instructions preserve architectural knowledge. The project is not meant to be shared or collaborated on. No risk of accidental force-push or merge conflicts.
- **Trade-offs Accepted:** No rollback capability. No history. No remote backup. Risk of data loss if local disk fails.
- **Status:** Accepted. Rule is absolute — git write commands must never be run.

---

### ADR-022: Unsplash/API Layer Fully Removed

- **Date:** 2026-03-09
- **Context:** The original repo scaffolding included an Unsplash image API integration (Retrofit, Dio, MobX, data models) for a demo home screen. This was never used by the POC.
- **Options Considered:**
  1. **Remove entirely** — delete all API, MobX, Retrofit, Dio, data model files
  2. **Keep as demo** — maintain the Unsplash grid for visual appeal
  3. **Replace with mock data** — remove API calls but keep the grid UI with local images
- **Decision:** Remove entirely
- **Rationale:** 11 dependencies removed (Dio, Retrofit, MobX, Provider, json_annotation, flutter_svg, and 5 dev dependencies for code generation). Home screen rewritten to a minimal launcher with just a soccer icon, title, and "Start Detection" button. No code generation needed (`build_runner` removed). The API layer had nothing to do with the POC's purpose and added build time, complexity, and attack surface.
- **Trade-offs Accepted:** Less visually impressive home screen. Acceptable — this is an engineering feasibility tool, not a consumer app.
- **Status:** Accepted

---

## v1.3 — Target Zone Impact Detection (2026-03-09 onward)

### ADR-023: Manual Calibration Approach for Target Registration

- **Date:** 2026-03-09
- **Context:** The target zone feature needs to know where the physical target sheet is located in the camera frame. Four approaches were evaluated.
- **Options Considered:**
  1. **Manual calibration (tap 4 corners)** — user taps the 4 corners of the target on screen, homography maps screen coordinates to physical zones
  2. **Retrained YOLO with zone classes** — train YOLO to detect individual zones directly
  3. **Automatic CV detection (opencv_dart)** — use computer vision to automatically detect the target sheet
  4. **ArUco markers + opencv_dart** — place ArUco markers on the target for automatic detection
- **Decision:** Manual calibration (tap 4 corners) + 8-parameter DLT homography transform
- **Rationale:**
  - ~85-90% of code is pure Dart (cross-platform)
  - Zero new platform-specific code needed
  - Zero new dependencies (homography is pure math)
  - Zero per-frame performance cost for zone mapping (computed once at calibration)
  - Works on Galaxy A32 (no additional GPU load)
  - Mathematically precise zone mapping from known geometry
  - **vs. Retrained YOLO:** Training data burden, catastrophic forgetting risk, bounding box overlap imprecise for zone boundaries
  - **vs. opencv_dart auto-detection:** Adds ~50MB dependency, lighting-sensitive, complex integration. Good upgrade path for production.
  - **vs. ArUco markers:** Requires opencv_dart AND modifying the physical target sheet. Good upgrade path for production.
- **Trade-offs Accepted:** Requires user to tap 4 corners manually on each session. If camera moves, re-calibration is needed. Acceptable for POC with tripod setup.
- **Status:** Accepted. Device-verified on iPhone 12 and Galaxy A32.

---

### ADR-024: Multi-Signal Impact Detection Over Naive Last-Position

- **Date:** 2026-03-09
- **Context:** Need to detect when a kicked ball hits the target. The naive approach of "where the ball was last seen = impact point" fails when the ball flies past the target without hitting it.
- **Options Considered:**
  1. **Multi-signal decision logic** — combine trajectory extrapolation + depth estimation + frame-edge exit filter + velocity change
  2. **Naive last-position** — last detected position is the impact point
  3. **Frame differencing** — compare pixel changes in the target region before/after impact
- **Decision:** Multi-signal with 4 active signals:
  - **Signal 1: Trajectory extrapolation (primary)** — Kalman filter + parabolic extrapolation to target plane intersection
  - **Signal 2: Depth estimation (filter)** — ball bbox area compared to reference, must be within `minDepthRatio=0.3` to `maxDepthRatio=2.5`
  - **Signal 3: Frame-edge exit (filter)** — last detection within 8% of frame edge → MISS
  - **Signal 4: Velocity change (confirmation)** — sudden deceleration = real hit
  - **Signal 5: Frame differencing** — DEFERRED (requires raw frame access, platform-specific)
- **Rationale:** Naive last-position produces false positives whenever the ball flies past the target (common in practice). The multi-signal approach achieves ~88-92% accuracy by combining multiple independent signals. Each signal addresses a different failure mode. Expected accuracy: clean hits ~95%, edge hits ~50% (inherently ambiguous), misses ~95%.
- **Trade-offs Accepted:** More complex implementation (~300 lines). Requires calibration for depth reference. Frame differencing deferred (would improve edge cases but requires platform camera frame access).
- **Status:** Accepted. All 5 phases implemented and device-verified.
- **References:** myKicks (5-7% error), CVPR 2025 "Where Is The Ball" (87.21% landing accuracy from monocular 2D tracking), cricket smartphone tracking (91.8% detection accuracy).

---

### ADR-025: Start with 30fps, Defer 60fps Camera

- **Date:** 2026-03-09
- **Context:** Higher frame rate means more data points for trajectory tracking, potentially improving accuracy. But 60fps requires platform-specific camera code.
- **Options Considered:**
  1. **30fps (plugin default)** — zero platform code, works on both platforms
  2. **60fps** — requires Swift/AVFoundation on iOS + Kotlin/Camera2 on Android
- **Decision:** 30fps
- **Rationale:** 30fps provides ~13 frames of ball tracking during a typical kick approach (~400ms). This is sufficient for Kalman filter smoothing and parabolic extrapolation. 60fps would double the data points but requires platform-specific camera code (Swift + Kotlin), which contradicts the "pure Dart" architecture goal. 30fps is the minimum viable frame rate — upgrade to 60fps later if accuracy is insufficient.
- **Trade-offs Accepted:** Fewer data points for trajectory. Kalman filter must handle larger inter-frame position jumps. Acceptable for POC.
- **Status:** Accepted

---

### ADR-026: Skip Frame Differencing in v1

- **Date:** 2026-03-09
- **Context:** Frame differencing (comparing pixel changes in the target region before/after impact) would be Signal 5 in the multi-signal impact detection.
- **Options Considered:**
  1. **Defer to later** — skip for v1, add if trajectory + depth + velocity signals are insufficient
  2. **Implement now** — requires raw camera frame access (platform-specific code)
- **Decision:** Defer
- **Rationale:** Frame differencing requires raw camera frame access, which means platform-specific Swift/Kotlin code for extracting pixels from the camera pipeline. This contradicts the "pure Dart" architecture goal. The 4 active signals (trajectory + depth + edge-filter + velocity) are expected to achieve ~88-92% accuracy, which is sufficient for the POC. Frame differencing can be added in production alongside opencv_dart if needed.
- **Trade-offs Accepted:** Slightly lower accuracy on edge cases where the ball barely grazes the target. Acceptable for POC scope.
- **Status:** Accepted (deferred to production)

---

### ADR-027: Calibration-Based Focal Length Derivation (Not Camera Intrinsics API)

- **Date:** 2026-03-09
- **Context:** Depth estimation needs a focal length value to convert ball bounding box size to physical distance. Focal length can come from camera hardware APIs or be derived from calibration geometry.
- **Options Considered:**
  1. **Calibration-based derivation** — derive focal length from tapped corners + known target physical size (1760mm x 1120mm)
  2. **Camera intrinsics API** — query iOS `AVCaptureDevice` / Android `CameraCharacteristics` for focal length
  3. **Hardcoded focal length** — use typical phone camera focal length (~4mm)
- **Decision:** Calibration-based derivation (pure Dart)
- **Rationale:** Camera intrinsics APIs are platform-specific (Swift for iOS, Kotlin for Android) — adding them contradicts the pure Dart architecture. Hardcoded focal length varies significantly between devices. Calibration-based derivation uses the tapped 4 corners + known target size to compute an effective focal length that accounts for the specific camera, zoom level, and distance — no platform code needed.
- **Trade-offs Accepted:** Accuracy depends on calibration quality (how precisely the user taps corners). Acceptable given the manual calibration approach.
- **Status:** Accepted. Later replaced by reference ball capture approach (ADR-031) which is even simpler.

---

### ADR-028: `audioplayers` Package for Audio Feedback

- **Date:** 2026-03-09
- **Context:** Need to play zone number callouts (1-9) and a miss buzzer sound on impact detection events.
- **Options Considered:**
  1. **`audioplayers: ^6.1.0`** — lightweight, simple API, mature, cross-platform
  2. **`just_audio`** — more features (streaming, caching), heavier
  3. **`flutter_soloud`** — newer, low-latency, less tested
  4. **Platform TTS** — `flutter_tts` to speak numbers in real-time
- **Decision:** `audioplayers: ^6.1.0` with pre-recorded M4A audio assets
- **Rationale:** Lightest option that works on both platforms. Simple API: `play(AssetSource('audio/zone_1.m4a'))`. Pre-recorded clips are faster and more consistent than real-time TTS (eliminates TTS engine startup latency). `just_audio` has more features than needed and heavier dependency tree. `flutter_soloud` is too new for a POC that needs reliability.
- **Trade-offs Accepted:** 10 audio files to manage (zone 1-9 + miss). Audio quality limited to what was generated (macOS TTS, not professional recordings). Acceptable for POC.
- **Status:** Accepted. Device-verified on both platforms.

---

### ADR-029: Lazy AudioPlayer Creation

- **Date:** 2026-03-09
- **Context:** `AudioService` singleton needs an `AudioPlayer` instance, but creating it at singleton init time triggers platform channel calls.
- **Options Considered:**
  1. **Lazy creation** — create `AudioPlayer` on first `play()` call
  2. **Eager creation** — create in singleton constructor
  3. **Create per call** — new player each time
- **Decision:** Lazy creation (`_player ??= AudioPlayer()` on first playback)
- **Rationale:** Avoids triggering `audioplayers` platform channels at app startup (before the engine is ready). Simplifies unit testing — tests that don't call playback never touch platform channels. Creating per call would accumulate player instances and leak resources.
- **Trade-offs Accepted:** Tiny latency on first-ever audio playback (player initialization). Imperceptible in practice.
- **Status:** Accepted

---

### ADR-030: macOS TTS for Audio Asset Generation

- **Date:** 2026-03-09
- **Context:** Need 10 audio files: zone callouts "ONE" through "NINE" plus a "Miss" buzzer.
- **Options Considered:**
  1. **macOS `say` command + `afconvert` to M4A** — free, fast, automated via shell script
  2. **Professional voice recording** — higher quality, costly, slow
  3. **Online TTS API** — cloud-based, requires API key, potential latency
  4. **In-app TTS at runtime** — `flutter_tts` package, no files needed
- **Decision:** macOS `say -v Samantha` + `afconvert` to M4A
- **Rationale:** Instant generation on the dev machine. Good enough quality for a POC (Samantha voice is clear and natural). Zero cost. Files are small (~5KB each). In-app TTS was rejected because TTS engine startup latency varies by device and would delay audio feedback.
- **Trade-offs Accepted:** Not professional-grade audio. Fixed to English. Replace with recorded audio for production. Initial generation had a zsh 1-based array indexing bug that shifted zone content by one — fixed by regenerating.
- **Status:** Accepted

---

### ADR-031: Reference Ball Capture for Depth Estimation

- **Date:** 2026-03-09
- **Context:** Depth estimation (Phase 5) needs to know how big the ball appears at the target distance to filter false impacts. Options for establishing this reference size.
- **Options Considered:**
  1. **Reference ball capture during calibration** — user places ball on target, YOLO captures bbox area as reference
  2. **Known ball diameter + focal length calculation** — compute from 22cm soccer ball diameter and derived focal length
  3. **Hardcoded reference bbox area** — use a fixed value based on typical camera distance
- **Decision:** Reference ball capture during calibration
- **Rationale:** Zero hardcoding — works with any ball size, any camera distance, any device. After the 4-corner calibration, a sub-phase asks the user to place the ball on the target. YOLO auto-detects the ball and captures `normalizedBox.width * normalizedBox.height` as the reference. Runtime ratio `lastBboxArea / referenceBboxArea` filters impacts: must be within `minDepthRatio=0.3` to `maxDepthRatio=2.5`. Simpler and more accurate than the focal length approach (ADR-027) which was the original plan.
- **Trade-offs Accepted:** Adds one extra calibration step. User must have the ball available at calibration time. Reference persists across kicks but clears on re-calibration.
- **Status:** Accepted. Supersedes ADR-027's focal length approach for depth estimation.

---

### ADR-032: Last Bbox Area (Not Peak) for Depth Ratio

- **Date:** 2026-03-09
- **Context:** When tracking ball bbox area across frames for depth estimation, should the system use the peak (maximum) area or the last-seen area?
- **Options Considered:**
  1. **Last-seen bbox area** — area at the moment detection is lost
  2. **Peak (maximum) bbox area** — largest area seen during the entire tracking sequence
  3. **Average bbox area** — mean over all tracked frames
- **Decision:** Last-seen bbox area
- **Rationale:** Camera is positioned **behind the kicker**, pointing at the goal. As the ball flies toward the target, it moves **away from the camera** — meaning it **shrinks** in the frame. The last-seen bbox area represents the ball closest to the target (smallest, furthest from camera). Peak bbox area would capture the ball when nearest to the camera (largest), which is the **opposite** of what we want for depth comparison. Initial implementation incorrectly used peak; changed to last-seen after device testing revealed the geometric error.
- **Trade-offs Accepted:** Last-seen may be affected by partial occlusion at frame edge. Mitigated by the edge-exit filter (if within 8% of edge → MISS, not depth-checked).
- **Status:** Accepted. Bugfix from peak to last-seen was device-verified.

---

### ADR-033: Phase-Transition Trigger for Audio

- **Date:** 2026-03-09
- **Context:** Audio needs to play exactly once when an impact is detected, not repeatedly during the 3-second result display.
- **Options Considered:**
  1. **Phase-transition detection** — capture `prevPhase` before `processFrame()`, fire audio when phase changes to `result`
  2. **Boolean flag** — `_audioPlayed` flag set after first play, reset on cooldown
  3. **Timer-based** — play audio then ignore for 3 seconds
- **Decision:** Phase-transition detection
- **Rationale:** Cleanest approach — no additional state variables needed. Compare phase before and after `processFrame()` call. If `prevPhase != result && currentPhase == result`, fire audio. Naturally prevents duplicate plays because the transition only happens once per impact. Boolean flags can get out of sync. Timer-based adds unnecessary complexity.
- **Trade-offs Accepted:** Tightly coupled to the `ImpactDetector`'s phase model. Acceptable since audio is inherently tied to impact events.
- **Status:** Accepted

---

### ADR-034: Always-Latest Extrapolation in ImpactDetector (Stale Extrapolation Fix)

- **Date:** 2026-03-09
- **Context:** Discovered a false HIT bug: ball on the left side of the goal (far from the calibrated grid on the right) still produced a false HIT at zone 3.
- **Options Considered:**
  1. **Always use latest extrapolation (including null)** — `_bestExtrapolation = extrapolation;`
  2. **Keep non-null guard** — `if (extrapolation != null) _bestExtrapolation = extrapolation;` (original, buggy)
  3. **Clear extrapolation on direction change** — detect when trajectory angle changes significantly
- **Decision:** Always use latest extrapolation: `_bestExtrapolation = extrapolation;` (unconditional assignment)
- **Rationale:** The original code only updated `_bestExtrapolation` when the new value was non-null. This meant a stale extrapolation from an earlier frame (when the ball briefly headed toward the target) persisted even after the ball changed direction. By always assigning (including null), when the ball's trajectory no longer intersects the target, the stale value is cleared. Direction-change detection would be more complex and error-prone.
- **Trade-offs Accepted:** If trajectory briefly doesn't intersect target between two frames that do intersect, the extrapolation is momentarily null. Not an issue in practice because the decision is made when the ball is lost (5+ frames), not per-frame.
- **Status:** Accepted. Device-verified. 1 new unit test added.

---

### ADR-035: Impact Decision Signal Priority Order

- **Date:** 2026-03-09
- **Context:** When multiple signals disagree (e.g., trajectory says HIT but ball is at frame edge), which signal wins?
- **Options Considered:**
  1. **Edge exit (MISS) > Depth filter (noResult) > Trajectory extrapolation (HIT)** — frame-edge exit always wins
  2. **Trajectory first** — always trust the math
  3. **Weighted combination** — score each signal and combine
- **Decision:** Edge exit > Depth filter > Trajectory
- **Rationale:** A ball that exits near the frame edge almost certainly flew past the target — the edge-exit filter is the most reliable signal. Depth filter catches cases where trajectory says HIT but the ball never physically reached the target (too far or too close). Trajectory is the primary positive signal but can be wrong when the ball curves after the last tracked frames. Weighted combination would be over-engineering for a POC.
- **Trade-offs Accepted:** A ball that legitimately hits the target corner near the frame edge might be falsely called a MISS. Edge zone hits are inherently ambiguous (~50% accuracy expected).
- **Status:** Accepted

---

## UI/UX Decisions (2026-03-10 to 2026-03-11)

### ADR-036: `sensors_plus` for Rotate-to-Landscape Overlay

- **Date:** 2026-03-10
- **Context:** The detection screen forces landscape orientation. Users who open it while holding the phone in portrait see a sideways camera view. Need a visual prompt to rotate.
- **Options Considered:**
  1. **`sensors_plus` accelerometer** — detect physical device orientation via accelerometer
  2. **`MediaQuery.of(context).orientation`** — query Flutter's orientation
  3. **Timer-based auto-dismiss** — show overlay for 3 seconds regardless
- **Decision:** `sensors_plus: ^6.1.0` accelerometer at 10Hz
- **Rationale:** `MediaQuery.orientation` is useless when the UI orientation is locked via `SystemChrome` — it always reports landscape. The accelerometer detects the **physical** device orientation regardless of the UI lock. 10Hz sampling with 500ms debounce is responsive but not jittery. Widget is fully removed from the tree after dismissal (zero ongoing cost).
- **Trade-offs Accepted:** Adds a dependency (`sensors_plus`). Accelerometer-based detection has a brief detection delay (500ms debounce).
- **Status:** Accepted. Device-verified on iPhone 12.

---

### ADR-037: `Transform.rotate(-pi/2)` for Overlay Text in Portrait

- **Date:** 2026-03-10
- **Context:** The rotate-to-landscape overlay shows an icon and text. Since the UI is locked to landscape, content appears sideways when the user holds the phone in portrait. Need to rotate the overlay content so it reads upright.
- **Options Considered:**
  1. **`-pi/2` rotation** — counter-clockwise 90 degrees
  2. **`+pi/2` rotation** — clockwise 90 degrees
- **Decision:** `-pi/2`
- **Rationale:** Initial implementation used `+pi/2` which rendered the text upside down (device-verified on iPhone 12). The UI is locked to landscape-left orientation. When the user holds the phone in portrait, the display is rotated 90 degrees clockwise from their perspective. To make content read upright, it must be rotated counter-clockwise: `-pi/2`.
- **Trade-offs Accepted:** None. This is simply the correct rotation direction.
- **Status:** Accepted. Bugfix from `+pi/2` to `-pi/2`.

---

### ADR-038: `permission_handler` for Explicit Camera Permission

- **Date:** 2026-03-11
- **Context:** After deleting and reinstalling the app on iOS, the camera showed a blank/pink screen. No permission dialog appeared. Root cause: `ultralytics_yolo` v0.2.0 checks but never requests camera permission on iOS.
- **Options Considered:**
  1. **`permission_handler: ^11.3.1`** — explicit `Permission.camera.request()` before rendering `YOLOView`
  2. **Fork plugin to fix** — modify `VideoCapture.swift` to request permission
  3. **Document as known issue** — tell users to grant permission manually in Settings
- **Decision:** `permission_handler: ^11.3.1` with `PERMISSION_CAMERA=1` Podfile macro
- **Rationale:** The plugin has a platform asymmetry bug: Android side requests permissions, iOS side only checks. Forking the plugin is heavy maintenance for a one-line fix. Documenting as a known issue provides bad UX. `permission_handler` is a well-maintained, standard package that handles permission requests cross-platform. The `_cameraReady` flag gates `YOLOView` rendering until permission is granted.
- **Trade-offs Accepted:** Adds a dependency. iOS Podfile needs `PERMISSION_CAMERA=1` preprocessor macro in `GCC_PREPROCESSOR_DEFINITIONS` (required for `permission_handler` to compile camera permission code). Removing this macro causes `Permission.camera.request()` to silently return `.denied`.
- **Status:** Accepted. Root cause documented in issueLog ISSUE-003.

---

### ADR-039: AppBar Removed from Detection Screen

- **Date:** 2026-03-11
- **Context:** The detection screen had a standard Flutter AppBar with a title. In landscape mode, this wastes ~56px of vertical screen height.
- **Options Considered:**
  1. **Remove AppBar entirely** — camera fills full screen
  2. **Transparent AppBar** — overlay style, preserves back navigation
  3. **Keep AppBar** — standard navigation pattern
- **Decision:** Remove AppBar entirely, replace with floating back button badge
- **Rationale:** In landscape mode, every pixel of vertical height matters for the camera view. The title bar added no value (the user knows they're on the detection screen). Navigation back to home is handled by a circular back arrow icon button positioned at top-left, matching the style of other badge overlays.
- **Trade-offs Accepted:** Non-standard navigation pattern (no AppBar). Mitigated by universally recognized back arrow icon.
- **Status:** Accepted. Device-verified on both platforms.

---

### ADR-040: Back Button Badge Replaces YOLO Text Badge

- **Date:** 2026-03-11
- **Context:** The top-left position had a text badge showing "YOLO" (the active backend label). After SSD removal, YOLO is the only backend — the label is redundant.
- **Options Considered:**
  1. **Back arrow icon button** — circular 40x40, `Colors.black54`, `BorderRadius.circular(20)`
  2. **Keep YOLO badge** — informational but redundant
  3. **Remove badge entirely** — no top-left element
- **Decision:** Circular back arrow icon button
- **Rationale:** The badge slot at top-left is valuable real estate. A back button provides navigation utility. The YOLO label was only useful when multiple backends existed. Removing entirely wastes the position and loses the back navigation (especially important without AppBar). The circular style matches other badge overlays ("Ball lost", status text).
- **Trade-offs Accepted:** `DetectorConfig` import removed from live screen (no longer referenced). Class and tests still exist for future backend extensibility.
- **Status:** Accepted. Device-verified on both platforms.

---

### ADR-041: Issue Log in Memory-Bank

- **Date:** 2026-03-11
- **Context:** Over the course of the project, 9 significant issues were encountered, diagnosed, and resolved. The root causes and solutions were scattered across conversation history.
- **Options Considered:**
  1. **Dedicated `issueLog.md`** — structured log with symptom, root cause, solution per issue
  2. **Append to `activeContext.md`** — keep everything in one file
  3. **Don't persist** — rely on memory and re-diagnosis
- **Decision:** Dedicated `memory-bank/issueLog.md`
- **Rationale:** Issues like the aaptOptions fix (ISSUE-001) and camera permission bug (ISSUE-003) are easy to encounter again after a clean install or device change. Having a searchable log with root causes and verified solutions prevents re-researching known issues. Separate file keeps `activeContext.md` focused on current state rather than historical debugging.
- **Trade-offs Accepted:** Another file to maintain. Mitigated by only recording issues with non-obvious root causes.
- **Status:** Accepted. 9 issues documented.

---

## Approach Evaluations (Research-Level Decisions)

### ADR-042: Diagnostic Protocol for Android onResult Silence

- **Date:** 2026-02-25
- **Context:** The Android YOLO pipeline had a 7-step callback chain from CameraX to Dart `onResult`. Needed to identify which step was failing.
- **Full Diagnostic Chain Investigated:**
  1. CameraX → `YOLOView.onFrame()` → `ObjectDetector.predict()` → JNI `postprocess()` → `convertResultToStreamData()` → EventChannel → Dart `_handleDetectionResults()` → `widget.onResult()`
- **12 Failure Points Catalogued:**
  - A: Model file missing → `predictor = null`
  - B: Label loading fails → COCO fallback → class names don't match
  - C: GPU delegate crash → `predictor = null`
  - D: No LifecycleOwner → camera never binds
  - E: Camera permissions not granted
  - F: Orientation detection wrong during transition
  - G: `streamCallback` never set
  - H: `shouldProcessFrame()` throttle too aggressive
  - I: EventSink null at inference time
  - J: Channel name mismatch
  - K: Missing `detections` key in stream data
  - L: `YOLOResult` parsing fails silently
- **Resolution:** Root cause was Failure Point A variant — model file was present but AAPT-compressed (ADR-016). Identified on first diagnostic pass via logcat.
- **Status:** Resolved. Protocol documented in `.planning/research/` for future reference.

---

### ADR-043: Target Zone Approaches — Full Evaluation

- **Date:** 2026-03-09
- **Context:** Evaluated 4 approaches for target zone detection before selecting manual calibration (ADR-023). Full evaluation preserved here.
- **Approach 1: Retrained YOLO with Zone Classes**
  - Pros: Single model, no calibration needed
  - Cons: Training data burden (need thousands of labeled images of numbered zones), catastrophic forgetting risk (model might forget soccer ball detection), bounding box overlap is imprecise for zone boundaries (zones share edges)
  - Verdict: REJECTED — training cost and forgetting risk too high for POC
- **Approach 2: Manual Calibration + Trajectory Prediction**
  - Pros: Pure Dart (~85-90%), zero dependencies, zero per-frame cost, mathematically precise
  - Cons: Requires user to tap 4 corners manually each session
  - Verdict: SELECTED (ADR-023)
- **Approach 3: Automatic CV Detection (opencv_dart)**
  - Pros: No manual calibration needed, could detect target automatically
  - Cons: ~50MB dependency, lighting-sensitive, complex integration, not needed for POC
  - Verdict: REJECTED for v1 — good upgrade path for production
- **Approach 4: ArUco Markers + opencv_dart**
  - Pros: Precise, automatic, robust
  - Cons: Requires opencv_dart (50MB), requires modifying the physical target sheet with printed markers
  - Verdict: REJECTED for v1 — good upgrade path for production
- **Status:** Approach 2 selected and implemented.

---

### ADR-044: Comparable Product Research Findings

- **Date:** 2026-03-09
- **Context:** Researched existing products and academic papers to validate the feasibility of single-phone-camera ball tracking and zone detection.
- **Key Findings:**
  - **myKicks (iOS):** Phone on tripod behind kicker, ARKit+CoreML, 5-7% error. Validates: single-phone setup works.
  - **HomeCourt (basketball):** Single phone + CoreML, detects shots through hoop. Validates: trajectory analysis from single camera is commercially viable.
  - **CVPR 2025 "Where Is The Ball":** 87.21% landing accuracy from monocular 2D tracking. Validates: our ~88-92% accuracy target is realistic.
  - **Cricket smartphone tracking:** 91.8% detection accuracy on single smartphone camera. Validates: ball tracking on phone cameras works across sports.
  - **Shooting target scoring systems:** 97-99% zone classification using homography + image subtraction. Validates: homography-based zone mapping is the right approach.
  - **Kalman filter for ball trajectory:** 0.0165cm max error in controlled settings. Validates: Kalman smoothing is appropriate for this use case.
- **Impact on Decisions:** Confirmed manual calibration + trajectory prediction approach (ADR-023). Confirmed 30fps is sufficient starting point (ADR-025). Confirmed homography is the right mathematical tool for zone mapping.
- **Status:** Research complete. Findings integrated into ADR-023 and ADR-024 rationale.

---

## UX Improvements — Calibration Refinement (2026-03)

### ADR-045: Back Button Enabled During Reference Capture Sub-Phase

- **Date:** 2026-03-13
- **Context:** During device testing, the developer noticed that after tapping the 4 calibration corners, the back button (top-left arrow) stopped responding. The user had to complete the entire calibration flow (including the ball detection confirm step) before they could go back to the home screen. This felt restrictive — users should always be able to leave the screen, especially if they made a mistake during calibration.
- **Options Considered:**
  1. **Narrow the full-screen GestureDetector scope** — only show the full-screen tap handler while corners are still being collected (not during the reference capture step). This removes the tap-blocking layer once 4 corners are placed, so the back button becomes tappable again.
  2. **Raise the back button above the GestureDetector in the Stack** — move the back button widget to a higher position in the Stack so it sits on top of the calibration tap handler and receives taps first.
  3. **Leave as-is** — the user must finish the entire calibration flow before going back. Simpler, but frustrating.
- **Decision:** Option 1 — narrow the GestureDetector scope by adding `!_awaitingReferenceCapture` to its condition.
- **Rationale:** This is the smallest and cleanest change. The full-screen GestureDetector only needs to be active while the user is tapping corners. Once all 4 corners are placed, the GestureDetector's own handler already ignores taps (it checks `_cornerPoints.length >= 4`), so keeping it in the widget tree during reference capture was serving no purpose — it was only blocking the back button unnecessarily. Option 2 would work but changes the Stack ordering which could have side effects on other overlays. Option 3 was rejected because users should always be able to leave.
- **Trade-offs Accepted:** During the corner-tapping phase itself (before all 4 corners are placed), the back button is still blocked by the full-screen GestureDetector. This is acceptable because the user is actively interacting with the screen during that brief step.
- **Status:** Accepted. Implemented and verified — 81/81 tests passing.

---

### ADR-046: Draggable Calibration Corners (GestureDetector Pan Pattern)

- **Date:** 2026-03-13
- **Context:** During real device testing, the developer observed that tapping the 4 calibration corners on a phone screen is never perfectly precise. A finger tap can be a few pixels off from the intended position, which makes the resulting green grid slightly crooked or tilted. Since the camera is placed at a side angle to the target (to avoid the kicker blocking the ball), the target appears as a perspective-distorted shape on screen — not a perfect rectangle. The user needs a way to fine-tune the corner positions after the initial taps, similar to how document scanner apps let you adjust the crop area.
- **Options Considered:**
  1. **Draggable corners via GestureDetector `onPanStart`/`onPanUpdate`** — after the 4 corners are placed, the user can drag any corner dot to adjust its position. Based on a simple open-source pattern from a Flutter Gist. Zero new dependencies, ~30-40 lines of new code, all in one file (`live_object_detection_screen.dart`). Each corner moves independently, so any quadrilateral shape is possible — not limited to rectangles.
  2. **`box_transform` / `flutter_box_transform` package** — a full-featured library for draggable and resizable boxes with corner handles. Well-maintained (83 GitHub stars, Apache 2.0 license). However, it only supports rectangular shapes — all 4 corners are constrained to form a perfect rectangle. Since the camera is at a side angle, the target on screen is a perspective-distorted quadrilateral (one side appears larger than the other). This package cannot represent that shape, making it unsuitable for this use case.
  3. **Magnified view while tapping** — show a zoomed-in circle near the finger (like the iOS text selection magnifier) so the user can place corners more precisely on the first try. This would require capturing a zoomed portion of the camera feed in Flutter, which is difficult with the YOLO plugin's `YOLOView` widget since it does not expose raw camera frames. Estimated 50+ lines of complex code with uncertain feasibility.
  4. **Smart rectangle correction** — since the real target is a known rectangle (1760mm x 1120mm), mathematically find the closest perspective projection of that rectangle that fits the 4 tapped points. Pure math, no UI changes needed. However, the optimization math (finding the best homography-consistent rectangle from 4 noisy points) is non-trivial to implement and hard to debug.
- **Decision:** Option 1 — draggable corners using GestureDetector `onPanStart`/`onPanUpdate`.
- **Rationale:** This approach is the best fit because: (a) it requires the fewest code changes — roughly 30-40 lines, all in one file; (b) it adds zero new package dependencies; (c) it supports any quadrilateral shape, which is essential since the camera angle means the target never looks like a perfect rectangle on screen; (d) the pattern is well-understood from document scanner apps, so users already know how it works; (e) it was evaluated against the other 3 options and scored best on simplicity, feasibility, and compatibility with the existing calibration flow. Options 2-4 were rejected for the reasons described above. Reference implementation: [Flutter GestureDetector draggable example Gist](https://gist.github.com/graphicbeacon/eb7e2ca7b3ff1d674819403789744173). **Why not use the Gist's approach directly (drag a single rectangle, then form the grid inside it)?** The Gist drags a single rectangular container with fixed width/height — it always produces a perfect rectangle. In our real-world use case, the camera views the goal at an angle, so the goal appears as a perspective-distorted quadrilateral (trapezoid), not a rectangle. A draggable rectangle cannot represent this shape, which means ball-to-zone mapping would be inaccurate. Our approach uses 4 independently positioned corners specifically so that any quadrilateral can be formed, and the homography transform then corrects the perspective distortion to map ball positions to the correct zone.
- **Trade-offs Accepted:** The user must still do the initial 4 taps to rough-place the corners, then drag to refine. This is a two-step process rather than single precise placement. Also, there is no "snap to edge" intelligence — the user must visually judge correct placement. Both are acceptable for a POC; production could add edge detection (via `opencv_dart`) for automatic snapping.
- **Status:** Accepted. Implemented and device-verified on iPhone 12 and Galaxy A32 (2026-03-14). Initial `_dragHitRadius = 0.04` was too small on iOS; tuned to `0.09` (see ADR-047).

---

### ADR-047: Drag Hit Radius Tuned from 0.04 to 0.09

- **Date:** 2026-03-14
- **Context:** After implementing draggable calibration corners (ADR-046), device testing revealed that drag worked on Android but not consistently on iOS. Only 1 of 4 corners could occasionally be dragged on iPhone 12. Root cause investigation was needed.
- **Options Considered:**
  1. **Increase `_dragHitRadius` from 0.04 to 0.09** — wider touch target, covers kTouchSlop offset observed in diagnostic data (distances 0.0408-0.0851)
  2. **Switch from `GestureDetector` to `Listener`** — raw pointer events bypass Flutter's gesture arena and kTouchSlop, reporting exact touch-down position. Would eliminate the offset entirely.
  3. **Platform-specific radius** — use 0.04 on Android (where it works) and 0.09 on iOS. Different thresholds per platform.
- **Decision:** Increase `_dragHitRadius` from `0.04` to `0.09` (single value, both platforms)
- **Rationale:** Diagnostic prints (DIAG-DRAG) conclusively showed `onPanStart` fires every time on iOS — there is no gesture arena competition. The issue was purely that `kTouchSlop` (~18px) shifts the reported `onPanStart` position ~0.05-0.08 from the intended touch point in normalized coordinate space. All observed distances (0.0408-0.0851) fall within a 0.09 radius. A single radius works on both platforms and keeps the code simple. `Listener` would work but is an unnecessary refactor when a tuning change solves the problem. Platform-specific radii add complexity for no benefit since 0.09 works well on both.
- **Trade-offs Accepted:** Larger hit radius means the touch target for each corner is wider (~9% of frame vs ~4%). If two corners are very close together (unlikely in normal calibration geometry), the user might grab the wrong one. Acceptable for this use case — corners are spaced far apart on a goal-sized target.
- **Status:** Accepted. Device-verified on iPhone 12 and Galaxy A32.

---

### ADR-048: Offset Cursor + Crosshair + Hollow Rings for Finger Occlusion

- **Date:** 2026-03-19
- **Context:** Real-world field testing revealed that draggable calibration corners (ADR-046) suffered from finger occlusion — the user's fingertip covers the exact corner point during drag, making precise alignment with goalpost corners impossible. Two specific problems: (1) the initial 60px offset cursor caused the corner to jump far from its position on tap, making bottom corners unreachable due to limited screen space below, (2) the solid green filled circle hid the crosshair intersection point.
- **Options Considered:**
  1. **Flutter built-in `Magnifier`/`RawMagnifier`** — Uses `BackdropFilter` which cannot capture platform view (camera) content. Would show blank area where camera feed is.
  2. **`flutter_quad_annotator` package** — Closest match (4-corner annotation + magnifier). But requires a static `ui.Image` — uses `canvas.drawImageRect()`, cannot overlay on live camera.
  3. **`flutter_magnifier_lens` package** — Uses Fragment Shaders + `RepaintBoundary`. Requires Flutter 3.41+ (project uses 3.38.9). Still can't capture platform views.
  4. **`flutter_magnifier` package** — BackdropFilter-based, same platform view limitation.
  5. **`flutter_image_perspective_crop` package** — Works on static `Uint8List` only.
  6. **Offset cursor (30px) + crosshair lines + hollow ring markers** — Pure Dart, zero dependencies, works over any content including platform views.
- **Decision:** Option 6 — Offset cursor + crosshair + hollow rings
- **Rationale:** Exhaustive research (8 parallel agents, 22 pub.dev keyword searches, 4 packages source-code inspected) confirmed that **no Flutter package can magnify camera platform view content**. The fundamental limitation is that platform views render outside Flutter's compositing pipeline — `BackdropFilter`, `RepaintBoundary.toImage()`, and Fragment Shaders all operate only on Flutter-rendered content. The offset cursor + crosshair pattern is the standard solution used by Adobe Scan, CamScanner, and document scanning apps. Implementation required ~4 lines of code changes: remove solid fill, reduce offset constant, hollow ring already smaller. Crosshair lines were already implemented from prior session.
- **Trade-offs Accepted:** No magnification of the actual camera feed under the corner. Crosshair lines provide alignment guidance but not pixel-level zoom. 30px offset is a subtle shift — enough to peek the ring above the fingertip but not enough for large-fingered users. Can be tuned via single constant if needed.
- **Status:** Accepted. Device-verified on iPhone 12 and Realme 9 Pro+ (2026-03-19).

---

### ADR-049: Pipeline Gating via `_pipelineLive` Boolean

- **Date:** 2026-03-19
- **Context:** Detection pipeline (tracker, trail dots, "Ball lost" badge, impact detection, audio) ran immediately on camera open, before calibration. This caused false MISS/noResult announcements and orange dots during setup. User reported the problem during real-world testing.
- **Options Considered:**
  1. **Multiple per-feature gates** — Check `_zoneMapper != null && !_calibrationMode` separately for each feature (tracker, impact, audio). More granular but scattered conditions across the callback.
  2. **Single `_pipelineLive` boolean** — One flag set `true` only when full calibration completes (4 corners + reference ball confirm). Gates entire pipeline in one condition.
- **Decision:** Option 2 — Single `_pipelineLive` boolean
- **Rationale:** Simpler, less error-prone, enforces clear stage boundaries (Preview → Calibration → Reference Capture → Live). All features should activate together — there's no use case where tracker should run but impact detection shouldn't (or vice versa). Single gate is easier to reason about and modify.
- **Trade-offs Accepted:** Less granular control — can't selectively enable trail dots without impact detection. Not needed for this POC.
- **Status:** Accepted. Device-verified on iPhone 12 and Realme 9 Pro+ (2026-03-19).

---

### ADR-050: Celebratory HIT Audio — Pre-Composited TTS + Crowd Cheer SFX

- **Date:** 2026-03-19
- **Context:** Manager requested that HIT audio include a celebratory element — something like "You hit 7!" followed by a cheer sound — to give players positive feedback. Total audio should be short enough (~2-5s) that the player can quickly set up for the next kick.
- **Options Considered:**
  1. **Pre-composited audio files** — Bake TTS speech + cheer SFX into a single M4A per zone. Drop-in replacement of existing `zone_N.m4a` files. Zero code changes.
  2. **Play two clips sequentially in code** — `AudioService` plays speech first, then cheer. Requires code changes to `AudioService` (sequential playback logic, timing management).
  3. **Pre-recorded professional audio** — Source or commission human-recorded celebratory clips. Higher quality but requires external resources and budget.
- **Decision:** Option 1 — Pre-composited files
- **Rationale:** Simplest approach with zero code changes. `AudioService` already plays a single file per event — keeping this unchanged avoids introducing playback sequencing complexity. Compositing with ffmpeg is straightforward and reproducible. The POC doesn't need professional-grade audio.
- **Audio generation pipeline:** macOS TTS (`say -v Samantha -r 170 "You hit [number]!"`) + Pixabay "Crowd Cheer and Applause" SFX (trimmed 3.8s, fade-out 0.8s) + 0.15s silence gap, concatenated via `ffmpeg -filter_complex concat`. Total ~4.7s per zone.
- **Cheer SFX source:** Pixabay Content License — free for commercial use, no attribution required, irrevocable and worldwide.
- **Trade-offs Accepted:** TTS voice quality is functional but not polished. All 9 zones use the same cheer clip (no variety). Replace with professional recordings for production. zsh 1-based array indexing caught and fixed (recurring project issue).
- **Status:** Accepted. Device-verified on iPhone 12 and Realme 9 Pro+ (2026-03-19).

---

### ADR-051: Depth-Verified Direct Zone Mapping Over Pure Trajectory Extrapolation

- **Date:** 2026-03-20
- **Context:** Real-world outdoor testing revealed trajectory extrapolation gives wrong zone numbers. iOS: extrapolation predicted zone 8 but ball hit zone 5 (repeated for most kicks). Android: completely unable to detect any hits. The fundamental problem: small angular errors in Kalman velocity during mid-flight are amplified over 30+ frames of parabolic extrapolation, shifting predicted impact by 200+ mm (more than half a zone width). Four parallel research agents confirmed no commercial single-camera ball tracking system (myKicks, HomeCourt, Hawk-Eye, TrackNet, any of 50+ papers in Kamble 2019 survey) uses long-range trajectory extrapolation for precise zone/position determination.
- **Options Considered:**
  1. **Last detected position mapped through homography** — Use `zoneMapper.pointToZone(rawPosition)` for the ball's last detected position. Simplest, but fails when ball passes through grid region mid-flight (at a different depth from the wall).
  2. **Depth-verified direct zone mapping** — Same as option 1, but only trust the position when depth ratio confirms ball is near the wall depth. Depth ratio ≈ 1.0 means ball is at reference depth (ON the wall). Mid-flight ball has ratio >> 1 (closer to camera = bigger bbox).
  3. **Multi-frame zone convergence** — Track mapped zone across last 3-5 frames, use last or majority vote. More complex, similar end result.
  4. **Parallax correction using bbox depth** — Scale ball position outward from image center by D/d ratio. More accurate but adds complexity.
  5. **Post-impact rebound detection** — Detect ball bouncing back after impact. Unreliable at 30fps, adds state machine complexity.
- **Decision:** Option 2 — Depth-verified direct zone mapping with extrapolation as fallback
- **Rationale:** Cleanly separates two questions: (1) "Will it hit?" → trajectory extrapolation (good for directional binary questions), (2) "WHERE did it hit?" → direct position mapping when verified by depth (most accurate near the wall). Re-uses existing infrastructure (`_referenceBboxArea`, `pointToZone()`, `_lastBboxArea`) with minimal code changes (~10 lines across 2 files). The depth ratio, previously disabled as a hard gate (ADR-047 Fix 2), works well as a trust qualifier because its failure mode (motion blur shrinking bbox) only blocks — it doesn't cause false positives. `maxDepthRatio` tightened from 2.5 to 1.5 to exclude mid-flight detections more aggressively.
- **Trade-offs Accepted:** If YOLO never detects the ball when it's both inside the grid region AND at wall depth (e.g., ball too blurry at impact), falls back to extrapolation (same as before). Depth ratio is still noisy from motion blur — may not always qualify valid at-wall detections. Thresholds may need tuning after outdoor testing.
- **Status:** Accepted. 81/81 tests passing. Pending outdoor device verification (2026-03-20).

---

## v1.3 — KickDetector + DiagnosticLogger (2026-03-23)

### ADR-052: KickDetector as Explicit Gate for ImpactDetector

- **Date:** 2026-03-23
- **Context:** ImpactDetector was receiving every YOLO frame when `_pipelineLive=true`, including frames where the ball is just rolling, dribbling, or being held. This caused false impact triggers on non-kick movements. A dedicated kick-detection layer was needed.
- **Options Considered:**
  1. **Simple velocity threshold gate** — Only pass frames to ImpactDetector when ball speed > threshold. Simple, but would trigger on any fast movement (throw, pass, fast roll). No temporal pattern validation.
  2. **KickDetector 4-signal state machine** — Explicitly detect kicks using jerk onset (explosive acceleration), sustained speed, directional movement toward the target, and a refractory period. Plain Dart class, fully unit-testable.
  3. **Train YOLO to detect kicks** — Model-level kick classification. Heavy: requires training data, model retraining, higher inference cost.
  4. **Post-hoc filtering in ImpactDetector** — Keep current architecture but add more aggressive filters inside ImpactDetector. Complicates single-responsibility.
- **Decision:** Option 2 — KickDetector 4-signal state machine
- **Rationale:** Soccer kicks have a highly characteristic physics signature: velocity goes from near-zero to maximum in 1-2 frames (explosive jerk). This cannot be mimicked by rolling or dribbling. A pure-Dart state machine is testable in isolation, has zero platform dependencies, and can be tuned independently of detection thresholds.
- **Trade-offs Accepted:** Direction filter requires calibrated `_goalCenter` (`_homography!.inverseTransform(Offset(0.5, 0.5))`). If homography is inaccurate or the kick trajectory is oblique, direction filter may reject valid kicks. Jerk threshold may need tuning for different ball weights / surfaces.
- **Status:** Accepted. 13/13 tests passing. Field-tested (2026-03-23) — partial confirmation.

---

### ADR-053: tickResultTimeout() Method for Result Expiry Outside Kick Gate

- **Date:** 2026-03-23
- **Context:** After KickDetector integration, `ImpactDetector.processFrame()` was gated behind `isKickActive`. The 3-second result display timeout was inside `processFrame()`. After a kick completed, `isKickActive` became false, and the timeout was never checked → result overlay stuck permanently.
- **Options Considered:**
  1. **Move timeout check to a separate `tickResultTimeout()` method** — Clean separation: `processFrame()` for detection logic, `tickResultTimeout()` for display lifecycle. Called unconditionally every frame.
  2. **Move timeout check into the kick gate block using `onKickComplete()`** — Start a timer when kick completes; callback resets ImpactDetector. More complex, timer lifecycle to manage.
  3. **Reset ImpactDetector immediately on `onKickComplete()`** — No delay, instant clear. Loses the 3-second result display duration the user expects.
  4. **Add a separate UI timer managed by the screen** — `Timer(resultDisplayDuration, _resetImpactDetector)`. Works but duplicates the duration constant between screen and ImpactDetector.
- **Decision:** Option 1 — `tickResultTimeout()` called outside kick gate
- **Rationale:** Minimal change. Single new method on ImpactDetector, single new call site in the screen. The result display duration stays encapsulated inside ImpactDetector. Clean separation: detection logic is gated, lifecycle management is not.
- **Trade-offs Accepted:** Caller must remember to call both `tickResultTimeout()` and the gated `processFrame()`. Slight coupling in the screen's callback structure. Worth it for simplicity.
- **Status:** Accepted. Fixed ISSUE-016.

---

### ADR-054: GlobalKey-Based sharePositionOrigin (Not Hardcoded Rect)

- **Date:** 2026-03-23
- **Context:** iOS 26.3.1 started enforcing that `Share.shareXFiles` must receive a non-zero `sharePositionOrigin: Rect` in landscape mode. The call passed nothing (defaulted to `Rect.zero`) and crashed with `PlatformException`. A hardcoded `Rect.fromLTWH(12, 60, 90, 28)` was proposed first and rejected by the developer: "this app needs to run in multiple devices."
- **Options Considered:**
  1. **Hardcoded Rect** — `Rect.fromLTWH(12, 60, 90, 28)` based on observed button position on iPhone 12 landscape. Rejected: breaks on different screen sizes, resolutions, and orientations.
  2. **GlobalKey + RenderBox** — Attach `GlobalKey` to share button widget. In `_shareLog()`, call `findRenderObject()` as `RenderBox`, use `localToGlobal(Offset.zero) & size` to get exact `Rect`. Device-agnostic, reads actual position at tap time.
  3. **MediaQuery-computed Rect** — Compute expected button position using `MediaQuery.of(context).size`. Still fragile — any layout change breaks it. Same category as hardcoded.
  4. **Fallback to `Rect.zero` with try/catch** — Swallow the error. Breaks on iOS 26.3.1+, not forward-compatible.
- **Decision:** Option 2 — GlobalKey + RenderBox
- **Rationale:** This is the Flutter-idiomatic solution and the approach documented in `share_plus` package docs for popover anchoring. It reads the actual rendered position at tap time — immune to screen size, device type, orientation, or future layout changes. One `GlobalKey` field + three lines in `_shareLog()`.
- **Trade-offs Accepted:** If `currentContext` is null at tap time (widget not in tree), falls back to `Rect.zero` — same behavior as before the fix, but a silent failure rather than a crash. In practice this cannot happen since the button is only visible when the logger is running.
- **Status:** Accepted. Fixed ISSUE-017.

---

---

## Zone Accuracy Fix — WallPlanePredictor (2026-04-01)

### ADR-055: WallPlanePredictor — Perspective-Corrected 3D Trajectory for Zone Mapping

- **Date:** 2026-04-01
- **Context:** Zone accuracy was 20% (1/5 correct). Upper zones (6,7,8) consistently reported as bottom zones (1,2). Root cause: the 2D homography only maps correctly for points ON the wall plane, but the ball is detected mid-flight where perspective distortion causes it to appear lower than its actual wall impact point. Both `directZone` and `TrajectoryExtrapolator` work in 2D camera space and suffer the same error.
- **Options Considered:**
  1. **SAM2-t segmentation layer** — add a second model for pixel-level ball segmentation. Would improve detection precision but NOT fix the perspective mapping error (the ball's image position is correct; the problem is mapping off-plane points through the homography).
  2. **Post-bounce detection** — detect the ball after it bounces off the wall. Ball would be near the wall plane for correct homography mapping. But timing is unreliable.
  3. **Perspective-corrected 3D trajectory** — use depth ratios (bbox area changes) to estimate 3D position, extrapolate to wall plane, project back to 2D. Fixes the root cause.
  4. **Better calibration** — auto-detect target corners to reduce calibration error. Wouldn't fix the mid-flight perspective issue.
- **Decision:** Option 3 — WallPlanePredictor with perspective-corrected 3D trajectory.
- **Rationale:** Directly addresses the root cause (off-plane perspective distortion). Uses data the app already has (bbox area per frame + calibration geometry). No new model or dependency needed. Pure Dart math, unit-testable.
- **Trade-offs Accepted:** Depends on bbox area for depth estimation, which is noisy due to motion blur. Predictions are sparse (only a few frames per kick have sufficient data).
- **Status:** Accepted. Field-tested — eliminates systematic Y-axis error.

---

### ADR-056: Observation-Driven Parameters — Zero Hardcoded Physical Dimensions

- **Date:** 2026-04-01
- **Context:** WallPlanePredictor v1 used hardcoded `wallDepthRatio=0.25`. v2 computed it from hardcoded physical dimensions (`_targetWidthMm=1760`, `_targetHeightMm=1120`, `_ballDiameterMm=220`). User identified that ANY hardcoded physical dimension is an assumption that breaks when the setup changes (different target sheet, different ball, different camera distance).
- **Options Considered:**
  1. **Hardcoded wallDepthRatio** — simple but breaks per-setup. Rejected by user.
  2. **Computed from physical dimensions** — better but still assumes specific target/ball sizes. Rejected by user.
  3. **Iterative projection with implicit wall discovery** — extrapolate 3D trajectory forward, check `pointToZone()` at each step. Wall is found when projected point enters the grid. Zero physical dimensions needed. The homography itself defines the wall plane.
- **Decision:** Option 3 — iterative projection with implicit wall discovery.
- **Rationale:** Completely eliminates physical dimension assumptions. Works with any target size, any ball size, any camera distance. The homography (calibrated from user taps) is the only geometric input. Aligns with absolute project rule: never hardcode parameters that can be observed or derived from runtime data.
- **Trade-offs Accepted:** Iterative loop (up to 30 steps per prediction) is slightly more compute than a closed-form formula, but negligible at 30fps.
- **Status:** Accepted. Field-tested in Session 3 — 60% exact, 80% within 1 zone.

---

### ADR-057: Phase-Aware Detection Filtering in _pickBestBallYolo

- **Date:** 2026-04-01
- **Context:** YOLO `confidenceThreshold: 0.25` was set globally to catch fast-moving balls during tracking. But during Ready phase, this accepted marginal detections on the kicker's body, hands, head, and wall patterns — producing false orange trail dots.
- **Options Considered:**
  1. **Raise global confidence threshold** — would miss fast-moving balls during tracking. Rejected.
  2. **Two separate YOLOView widgets** — one per phase with different thresholds. Overly complex, breaks the single-widget architecture.
  3. **Post-detection phase-aware filtering in `_pickBestBallYolo`** — keep YOLO at 0.25 to get all candidates, then filter in Dart based on pipeline state: confidence floor (0.50 Ready, 0.25 Tracking) + spatial gating (proximity to Kalman prediction or last-known position).
- **Decision:** Option 3 — `_applyPhaseFilter()` in `_pickBestBallYolo`.
- **Rationale:** Uses pipeline state (phase, Kalman prediction) to dynamically define what's plausible. No platform changes needed. Confidence floor and search radius derived from runtime state, not hardcoded per-setup. Kicker's body/head rejected not by confidence alone but by being spatially far from where the ball should be.
- **Trade-offs Accepted:** Tight spatial gate during tracking could miss detections if Kalman prediction diverges significantly from actual ball position. 15% radius provides margin.
- **Status:** Accepted. Verified in Session 3 — no false dots on kicker observed.

---

## Architecture Rebuild — ByteTrack Pipeline (2026-04-05)

### ADR-058: Replace Fragmented Pipeline with ByteTrack Object Tracker

- **Date:** 2026-04-05
- **Context:** Field testing (2026-04-04) revealed that YOLO detects the 9 red LED-ringed circles on the Flare Player target banner as soccer balls (ISSUE-022). This poisoned the entire detection pipeline — wrong zones, premature announcements, 38.9% and 11.1% accuracy across two test phases. Deep analysis revealed the root cause was not just the false positives but a fundamental architectural flaw: the pipeline had no concept of object identity. Every frame, `_pickBestBallYolo` selected from scratch, allowing false positives to contaminate tracking, velocity estimation, depth estimation, and impact detection. The pipeline was built by bolting on partial solutions from different concepts (centroid from bbox, 4-state Kalman, WallPlanePredictor for missing depth, phase filters for false positives) — each solving part of a problem that wouldn't exist with a complete, proper tracking architecture.
- **Options Considered:**
  1. **Band-aid filters** — Static detection map, geometric exclusion zones, persistence filtering, velocity gating. Would address ISSUE-022 specifically but not the architectural fragmentation. Each filter is another partial solution added on top.
  2. **Model retraining** — Train YOLO to not detect the target circles. Permanent fix for THIS target design but fragile (new target = retrain), requires training infrastructure, and doesn't fix the lack of object identity.
  3. **Pure Dart IoU tracker (centroid-based)** — Add persistent track IDs via centroid-distance matching. Research showed centroid-only IoU fails for fast-moving small balls (IoU drops to 0.06 mid-flight when ball displacement exceeds bbox width).
  4. **Complete ByteTrack implementation (pure Dart)** — Full algorithm: 8-state Kalman filter per track (cx, cy, w, h, vx, vy, vw, vh), two-pass IoU matching (high-confidence then low-confidence), track state categories (tracked/lost/removed), BallIdentifier service for automatic ball re-acquisition between kicks.
  5. **Switch to `google_mlkit_object_detection`** — Has built-in tracking IDs. But requires ML Kit's model format (incompatible with custom YOLO model), replaces entire detection pipeline, loses all calibration/coordinate work.
  6. **Fork `ultralytics_yolo` plugin to add native tracking** — "Right" long-term solution but requires native iOS (Swift) + Android (Kotlin) code, weeks of effort, plugin maintenance burden. Ultralytics themselves haven't implemented it (Issue #285, July 2025).
- **Decision:** Option 4 — Complete ByteTrack in pure Dart
- **Rationale:**
  - Solves ISSUE-022 and ALL future false positive problems (any non-ball object gets a separate track ID)
  - 8-state Kalman tracks full bounding box including size change rates — IoU matching works for fast balls because both position and size are predicted
  - Bounding box as primary data through the pipeline (not centroid-only) gives richer discrimination signal
  - Replaces ~800-1000 lines of fragmented code with ~450-500 lines of clean, well-understood algorithm
  - Pure Dart, no native code, no new dependencies, no plugin changes
  - BallIdentifier enables "set up once, play forever" — automatic ball re-acquisition between kicks
  - Well-documented algorithm (Zhang et al., 2022 ECCV, 80.3 MOTA on MOT17)
  - Also eliminates need for WallPlanePredictor (depth tracked in Kalman state) and TrajectoryExtrapolator (subsumed by Kalman prediction)
- **Trade-offs Accepted:**
  - Significant code change — replaces multiple existing services
  - Must re-test thoroughly on both platforms after implementation
  - 8-state Kalman is more complex than the existing 4-state, but well-understood mathematically
  - ByteTrack's two-pass matching adds ~30 lines over basic SORT — minimal additional complexity for meaningful benefit (recovers low-confidence ball detections during fast flight)
- **Status:** Accepted. Execution plan pending.

### ADR-059: Full Bounding Box as Primary Tracking Data (Not Centroid-Only)

- **Date:** 2026-04-05
- **Context:** The existing pipeline extracted only `normalizedBox.center` (2 values: cx, cy) from YOLO detections and discarded bbox width and height. The bbox area was computed separately as a side calculation for depth estimation. This architectural choice limited the pipeline in multiple ways: the 4-state Kalman filter had no size prediction, IoU matching couldn't work (no size to compute overlap), and object discrimination relied solely on position proximity.
- **Options Considered:**
  1. **Continue with centroid-only + side-calculated bbox area** — minimal change, but perpetuates the limitation
  2. **Track full bounding box (4 values) in a 6-state Kalman** — cx, cy, w, h, vx, vy
  3. **Track full bounding box + size change rates in an 8-state Kalman** — cx, cy, w, h, vx, vy, vw, vh (ByteTrack's approach)
- **Decision:** Option 3 — 8-state Kalman with full bbox + rate of change
- **Rationale:** The bounding box carries 4 values (position + size) vs centroid's 2 values (position only). The extra 2 values (w, h) provide: (a) depth information built into the tracking state rather than computed separately, (b) size prediction for IoU matching — the Kalman predicts next frame's bbox size, making IoU viable even for fast-shrinking balls, (c) discrimination signal — a ball changing size during flight is distinguishable from a static circle with constant size, (d) rate of change of size (vw, vh) gives acceleration of depth change — useful for detecting impact (ball suddenly stops shrinking). Using 8 states rather than 6 adds the size change rates, which ByteTrack uses and which cost minimal computation while enabling richer predictions.
- **Trade-offs Accepted:** 8x8 Kalman matrices instead of 4x4. Negligible computational difference on mobile (microseconds per frame). Slightly more complex Kalman implementation (~30 more lines than 4-state).
- **Status:** Accepted. Part of ByteTrack implementation.

### ADR-060: Two-Stage Matching with Locked-Track Mahalanobis Fallback

- **Date:** 2026-04-06
- **Context:** ByteTrack's IoU matching failed for fast-kicked soccer balls (ISSUE-023) — ball displacement exceeds bbox width in 1 frame, IoU drops to zero. Adding Mahalanobis distance as a universal fallback (Fix Iteration 1) caused circle tracks to match wrong detections because the wide Kalman covariance created an overly permissive gate.
- **Options Considered:**
  1. **Centroid-distance fallback with hardcoded radius** — Simple but requires magic numbers (0.20 radius). Violates no-hardcoding rule.
  2. **Mahalanobis as dual gate for ALL tracks** — Uses Kalman covariance (no hardcoding), but circle tracks with high velocity uncertainty match wrong detections across the target.
  3. **Two-stage: IoU first, Mahalanobis ONLY for locked ball track** — Stage 1 pure IoU keeps circles locked to their positions. Stage 2 Mahalanobis rescues only the ball during fast kicks. `lockedTrackId` parameter restricts which track gets the fallback.
- **Decision:** Option 3 — Two-stage with locked-track-only Mahalanobis
- **Rationale:** IoU matching works perfectly for static objects (circles IoU ≈ 1.0 with themselves). The only object that needs Mahalanobis rescue is the kicked ball — it's the only object with explosive acceleration from standstill. By restricting Stage 2 to the locked ball track, circles never get the wide Mahalanobis gate. The chi-squared threshold (9.488 for 4 DOF at 95%) is a statistical constant, not a tuning parameter.
- **Trade-offs Accepted:** If the locked ball track is lost before the kick (e.g., ball goes out of frame), the Mahalanobis rescue won't apply to the re-acquired track until BallIdentifier updates the lock. This is acceptable since re-acquisition happens within 1-2 frames.
- **Status:** Accepted. Pending device verification.

### ADR-061: Kick-State Gate on ImpactDetector — REVERTED

- **Date:** 2026-04-08
- **Context:** ImpactDetector fired phantom HIT/MISS decisions during kick=idle (e.g., on stationary objects or player movement). These decisions were correctly blocked from audio by KickDetector's result gate, but they polluted diagnostic logs and raised concerns about pipeline reliability.
- **Options Considered:**
  1. **Gate ImpactDetector input on KickDetector state** — Only call `processFrame()` when `kickEngaged` (confirming/active). Prevents phantom decisions entirely.
  2. **Leave ImpactDetector unconditional, gate only output** — Let ImpactDetector run every frame but only announce results when KickDetector confirms a real kick. Accept log pollution.
  3. **Lower ImpactDetector sensitivity** — Increase `minTrackingFrames` or add velocity floor. Reduces phantom decisions without gating.
- **Decision:** Option 1 was implemented, then **REVERTED to Option 2**.
- **Rationale:** Option 1 broke grounded kick detection. KickDetector's jerk threshold (0.01) doesn't fire reliably for low-velocity ground shots — the explosive onset that triggers idle→confirming requires high acceleration that grounded shots don't produce. 3/5 kicks went undetected. The phantom decisions being prevented were log pollution only — the app never announced them. The cure was worse than the disease.
- **Trade-offs Accepted:** Phantom HIT/MISS decisions appear in diagnostic logs during idle. This is noise, not a functional bug.
- **Status:** Reverted. ImpactDetector runs unconditionally every frame.

### ADR-062: Trail Dot Gating on Kick State — REVERTED

- **Date:** 2026-04-08
- **Context:** False orange trail dots appeared on player body, poster, and other non-ball objects when BallIdentifier re-acquired to wrong tracks during kick=idle. Proposed fix: only add trail entries when `kickEngaged=true`.
- **Options Considered:**
  1. **Gate trail entries on kickEngaged** — Trail dots only drawn during confirmed kicks. Eliminates all idle-phase false dots.
  2. **Improve BallIdentifier track discrimination** — Add bbox size filtering, CNN features, or other heuristics to prevent re-acquisition to non-ball objects. Treats root cause.
  3. **Leave trail ungated** — Accept false dots on non-ball objects as a known issue until BallIdentifier is improved.
- **Decision:** Option 1 was implemented, then **REVERTED to Option 3**.
- **Rationale:** Option 1 killed ALL trail visualization because: (a) `updateFromTracks()` was called before `KickDetector.processFrame()`, reading previous frame's state (1-frame lag); (b) kick windows are very short (3-5 frames on video); (c) the real cause is wrong track identity, not trail timing. Gating trail on kick state treats the symptom while hiding valid trail data.
- **Trade-offs Accepted:** False dots on non-ball objects remain visible. Root cause (BallIdentifier track identity) needs to be addressed separately.
- **Status:** Reverted. Trail entries always added when ball is tracked.

### ADR-063: directZone as Primary (and Only) Decision Signal

- **Date:** 2026-04-09
- **Context:** Video test analysis of 5 kicks revealed that `directZone` (ball's actual position mapped through homography via `pointToZone()`) was correct 5/5 times. The existing decision cascade (WallPlanePredictor → depth-verified zone → extrapolation fallback) had multiple failure modes: WallPlanePredictor only fired on 2/5 kicks, the `minTrackingFrames` gate rejected 3/5 kicks, and extrapolation overshot the grid on fast kicks. The one-row-down bias (Bug 3) in WallPlanePredictor was the original motivator for investigating alternatives.
- **Options Considered:**
  1. **Fix WallPlanePredictor perspective correction** — Add gravity term or improve depth estimation. Complex, uncertain improvement.
  2. **Add +1 row correction** — Hardcoded offset to compensate for systematic bias. Violates no-hardcoding rule. Fixes top/middle rows but breaks bottom row (already correct).
  3. **"Last observed directZone" as primary signal** — Use the last non-null `pointToZone()` result during tracking. No prediction, no extrapolation. Ball must actually enter the grid.
  4. **directZone only — no fallback** — If ball never enters grid, produce noResult instead of falling through to unreliable prediction signals.
- **Decision:** Option 4 — directZone only, no fallback to other signals.
- **Rationale:** directZone was correct 5/5 times in testing. It's the simplest signal — just "where was the ball when it was last seen inside the grid." No prediction models, no depth estimation, no perspective correction needed. The condition "directZone must be non-null" is self-validating: if the ball never entered the grid, we genuinely don't know where it hit. The other signals (WallPlanePredictor, extrapolation) made predictions that were often wrong. Better to say "no result" than announce a wrong zone.
- **Trade-offs Accepted:** If YOLO loses tracking before the ball enters the grid (e.g., very fast kick, occlusion), no zone will be announced even if the ball hit the target. This is acceptable — a missed announcement is better than a wrong announcement. WallPlanePredictor still runs and logs for diagnostic comparison but doesn't influence decisions.
- **Status:** Accepted. Pending field test validation.

### ADR-064: Accept `confirming` State in KickDetector Result Gate

- **Date:** 2026-04-09
- **Context:** KickDetector requires 3 sustained high-speed frames to transition from `confirming` → `active`. Fast kicks often have fewer tracked frames before the ball enters the grid and the decision fires. In video testing, 3/5 kicks never reached `active` — they stayed in `confirming` (jerk spike detected but not enough sustained frames). Combined with the new directZone requirement, `confirming` is sufficient to identify a real kick.
- **Options Considered:**
  1. **Keep `active` only** — Strict gate, prevents false announcements but misses real kicks (3/5 missed in test).
  2. **Accept `confirming` or `active`** — Looser gate, relies on directZone to prevent false announcements (ball must actually enter grid).
  3. **Lower KickDetector thresholds** — Reduce `sustainFrames` from 3 to 1 or `jerkThreshold` from 0.01 to lower. Risk: more false positives from dribbling/walking.
- **Decision:** Option 2 — accept `confirming` or `active`.
- **Rationale:** `confirming` means a jerk spike was detected — explosive onset happened. Combined with directZone (ball must have entered grid), this is a strong double-gate: no phantom announcements can occur because they always have `directZone=null`. The false decision between kick 1 and 2 in the video test had `directZone=null` across all frames — naturally filtered out.
- **Trade-offs Accepted:** Slightly more permissive gate. If a non-kick event (e.g., camera bump) triggers a jerk spike AND the ball happens to be in the grid, a false announcement could occur. This is a very unlikely combination.
- **Status:** Accepted. Pending field test validation.

---

### ADR-065: Calibration Geometry Diagnostics for Cross-Session Comparison

- **Date:** 2026-04-09
- **Context:** Same video on same monitor produced 5/5 correct results (Session 0) and 0/5 correct results (Session 1) with the only change being manual 4-corner calibration taps. Needed diagnostic data to understand WHY different calibrations produce different results.
- **Options Considered:**
  1. **Log raw corner positions only** — minimal, but insufficient for analysis
  2. **Log comprehensive derived geometry** — corner positions + 15 derived parameters (edge lengths, aspect ratio, perspective ratios, centroid, coverage, corner angles, homography matrix, zone centers in camera space)
  3. **Log + auto-validate against ideal ranges** — comprehensive logging plus real-time quality checks
- **Decision:** Option 2 — comprehensive derived geometry logging
- **Rationale:** Raw corners alone don't reveal the geometric relationship causing accuracy differences. Derived parameters directly explain WHY a calibration maps mid-flight positions differently. Auto-validation (option 3) requires knowing the "correct" ranges first — we need the data to discover them.
- **Trade-offs Accepted:** Verbose logging output. Acceptable for diagnostic phase.
- **Status:** Accepted

---

### ADR-066: Debug Bounding Box Overlay for Visual Ball Identity Debugging

- **Date:** 2026-04-09
- **Context:** Log-based analysis of ball tracking failures was insufficient — logs show trackId and position but don't reveal WHAT object the trackId is attached to. Multiple analysis sessions attributed wrong root causes because the analyst assumed a trackId was the ball when it was on a different object.
- **Options Considered:**
  1. **Enhanced text logging only** — add bbox dimensions and aspect ratio to BYTETRACK logs
  2. **Visual debug overlay (CustomPainter)** — draw colored bounding boxes on screen with metadata labels
  3. **Enable native YOLO overlays (`showOverlays: true`)** — uses ultralytics_yolo's built-in bbox rendering
- **Decision:** Option 2 — custom visual debug overlay
- **Rationale:** Text logging still requires the analyst to imagine where objects are — the tester can't see which object is tracked without visual feedback. Native YOLO overlays show ALL detections regardless of class, don't show trackId or locked status. Custom overlay shows only ball-class detections with BallIdentifier's perspective: green=locked, yellow=candidate, red=lost. Togglable via single const boolean.
- **Trade-offs Accepted:** Additional CustomPainter in render Stack. Minor visual clutter during debug. Zero cost when disabled.
- **Status:** Accepted

### ADR-067: Sliding Window Displacement for Two-Way isStatic Classification

- **Date:** 2026-04-13
- **Context:** ISSUE-027 — ByteTrack's `isStatic` flag was permanently one-way (once `true`, never cleared). Additionally, the lifetime `_cumulativeDisplacement` accumulator prevented re-classification as static after movement. BallIdentifier uses `isStatic` to filter re-acquisition candidates, so a stuck flag made the real ball invisible to the system. Research into standard trackers (ByteTrack, SORT, DeepSORT, OC-SORT, Norfair) confirmed none have static classification — this is a custom addition. Frigate NVR was the only production system found with static object detection.
- **Options Considered:**
  1. **Velocity-based clearing** — clear `isStatic` when velocity > threshold for N consecutive frames. Fixes `true→false` but not `false→true`.
  2. **Reset on KickDetector transition** — clear flag on `confirming`. Couples ByteTrack to KickDetector. Fixes `true→false` only.
  3. **Cumulative displacement reset** — reset accumulator on velocity spike. Fragile threshold, still lifetime-based.
  4. **Two-way in evaluateStatic()** — add `else if` branch. Fixes `true→false` but accumulator still prevents `false→true`.
  5. **Sliding window displacement (Frigate-inspired)** — replace lifetime accumulator with `ListQueue<double>` of last N frame displacements. Sum only recent window. Both transitions automatic.
- **Decision:** Option 5 — sliding window displacement
- **Rationale:** Only approach that fixes BOTH directions (`true→false` and `false→true`). Consistent with Frigate NVR's production pattern. No coupling to other services. Same parameters (`staticMinFrames`, `staticMaxDisplacement`) work unchanged. Self-correcting — no explicit reset logic needed.
- **Trade-offs Accepted:** `ListQueue` per `_STrack` (~30 doubles = ~240 bytes per track). Negligible memory impact. Window size determines response latency — 30 frames means ~1 second delay before classification changes.
- **Status:** Accepted. Device-verified on iPhone 12.

### ADR-068: Pre-ByteTrack AR Upper Bound Filter (AR > 1.8 Only)

- **Date:** 2026-04-13
- **Context:** YOLO false positives on kicker torso/limbs (AR 2.4-3.6, confidence 0.95+) were entering ByteTrack, creating ephemeral tracks that burned through track IDs (observed trackId=55 in one session). Each unmatched false positive detection creates a new `_STrack` with `_nextId++`. Need to filter these before ByteTrack without breaking real ball detection.
- **Options Considered:**
  1. **Upper + lower AR bounds (>1.8 and <0.55)** — catches both wide (torso) and tall (unknown) false positives. Risk: lower bound may intermittently reject real ball on frames where YOLO bbox is vertically elongated.
  2. **Upper bound only (>1.8)** — catches torso/limb false positives. No risk to real ball (observed max AR ~1.5). No tall-narrow false positives have been observed.
  3. **Higher threshold (>2.5)** — more conservative, only catches extreme torsos. Misses borderline cases.
  4. **NMS dedup in `_toDetections()`** — suppress overlapping detections from different classes (Soccer ball + ball on same object). Fixes dual-detection churn but not torso false positives.
- **Decision:** Option 2 — upper bound only (AR > 1.8)
- **Rationale:** Real ball AR observed max ~1.5; threshold at 1.8 gives margin. No false positives have been observed with tall-narrow bboxes, so lower bound adds risk without benefit. Lower bound was initially implemented and removed after device testing suggested it may have been intermittently rejecting real ball detections (isStatic stopped triggering, possibly due to detection gaps breaking the 30-frame sliding window). Simplest possible filter — 2 lines of code, no new classes, no pipeline changes.
- **Trade-offs Accepted:** Player head (AR 0.9) passes this filter — geometrically identical to ball. Needs separate solution (second-stage classifier or motion channel). Torso bboxes at AR 1.8-2.4 (if they exist) would also pass.
- **Status:** Accepted. Monitor-tested, pending field test.

### ADR-069: Session Lock to Prevent False Positive Re-acquisition During Kicks

- **Date:** 2026-04-15
- **Context:** After implementing ByteTrack and BallIdentifier, false positive trail dots appeared on player's body/head between kicks. Root cause: when locked ball track is lost for a few frames, BallIdentifier re-acquires to whatever moves (player head, poster edge) via Priority 2 or 3. Manager suggested: once ball trackID is locked and kick is in progress, reject all other trackIDs until decision is made.
- **Options Considered:**
  1. **Detection-level filtering** — filter false positives before ByteTrack. Previously attempted and reverted (ISSUE-028). Starves ByteTrack of detections, breaks re-acquisition.
  2. **Session lock at BallIdentifier level** — block Priority 2/3 during active kicks. ByteTrack runs unmodified on all detections. No information loss.
  3. **Tie lock to calibration/setup** — activate lock from reference capture, not kick detection. Simpler but means lock is always on, making re-acquisition impossible.
- **Decision:** Option 2 — session lock in BallIdentifier, activated by KickDetector `active` state, deactivated on decision.
- **Rationale:** Works at the right layer (BallIdentifier, not detection pipeline). No starvation risk. Scoped to kick-to-decision window. Combined with protected track (60-frame survival in ByteTrack) to keep locked trackID alive during flight.
- **Trade-offs Accepted:** If KickDetector misses a kick, session lock never activates — app behaves as before (no benefit, but no regression). Session lock can get stuck if locked track is lost without a decision (ISSUE-030 — needs safety timeout).
- **Status:** Accepted. Monitor-tested. Needs safety timeout fix.

### ADR-070: Trail Suppression During Kick=Idle

- **Date:** 2026-04-15
- **Context:** Even with session lock preventing re-acquisition during kicks, false positive dots appeared during idle periods (player positioning ball, walking around). Trail dots are only useful during actual ball flight.
- **Options Considered:**
  1. **Keep session lock ON permanently after decision** — no re-acquisition between kicks. Problem: no way to unlock for next kick without tying to KickDetector (which isn't 100% reliable).
  2. **Trail suppression based on kick state** — always collect trail data in BallIdentifier, but only display dots when kick state is confirming/active/refractory. Simple, no pipeline changes.
  3. **Clear trail on decision** — wipe trail data after decision. Problem: new false positive dots would immediately appear from re-acquisition to player body.
- **Decision:** Option 2 — TrailOverlay receives empty list when `kickState == idle`, real trail otherwise.
- **Rationale:** One line change. Cleanly separates data collection (always running) from visual display (only during kicks). No side effects on pipeline, logging, or decision-making. Eliminates all idle-period false dots.
- **Trade-offs Accepted:** Ball on ground before kick is not visually tracked (no dots during idle). Acceptable — user doesn't need to see the stationary ball.
- **Status:** Accepted. Monitor-tested. Working as expected.

### ADR-071: Bbox Area Ratio Check on Mahalanobis Rescue (NEEDS TUNING)

- **Date:** 2026-04-15
- **Context:** Mahalanobis rescue (ISSUE-026) hijacks locked ball track to false positives (player head, poster) when Kalman covariance grows large during stationary periods. Statistical distance passes even for distant detections. Need a physical constraint to prevent size-mismatched rescues.
- **Options Considered:**
  1. **Lower chi-squared threshold** — reduce from 9.488 to a smaller value. Too blunt — would also block legitimate fast-moving ball rescues.
  2. **Bbox area ratio check** — compare detection area to track's predicted area. Reject if >2x or <0.5x. Physical constraint: ball can't change size dramatically between frames.
  3. **Last measured area comparison** — compare against last real detection area instead of Kalman predicted. More stable during prediction-only frames.
- **Decision:** Option 2 initially (with threshold 2.0/0.5). Monitor testing showed it blocks legitimate tracking during fast kicks (Kalman predicted area diverges during pure predictions). Option 3 identified as the better approach but not yet implemented.
- **Rationale:** Area ratio is the right constraint. The threshold and comparison basis need adjustment. Hijack cases had ratios of 3.8x-9x, so there's room between legitimate variation (~0.8-1.2x frame-to-frame) and hijack jumps.
- **Trade-offs Accepted:** Current 2.0 threshold causes 2/5 kicks to go silent. Must be tuned before field testing.
- **Status:** Accepted but NEEDS TUNING (ISSUE-029). Next step: compare against last measured area instead of Kalman predicted, or relax threshold to 3.0-3.5.

---

*Decision log created: 2026-03-13*
*Backfilled from: activeContext.md, progress.md, systemPatterns.md, techContext.md, productContext.md, issueLog.md, changelog.md, projectbrief.md, CLAUDE.md, .planning/research/*, .planning/ROADMAP.md, .planning/REQUIREMENTS.md*
