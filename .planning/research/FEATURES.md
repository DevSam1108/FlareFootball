# Feature Research

**Domain:** Android YOLO pipeline verification — on-device soccer ball detection (Flutter, ultralytics_yolo TFLite)
**Researched:** 2026-02-25
**Confidence:** HIGH (pipeline behavior), MEDIUM (Android camera AR specifics — requires empirical verification on Galaxy A32)

---

## Context and Scope

This research covers the v1.2 Android Verification milestone. The "user" is the Flare Football
engineering team evaluating whether the YOLO pipeline works on Android (Galaxy A32) at feature
parity with the verified iOS behavior. The current known failure: `onResult` does not fire on
Android across 42 seconds of footage with ball clearly visible. Camera feed renders correctly.
Root cause is at the plugin level — `ultralytics_yolo` Android TFLite path is not delivering
inference results to the Flutter layer.

**The milestone has two phases:**
1. Diagnose and fix `onResult` — get inference results flowing from TFLite to Flutter on Android.
2. Verify parity — confirm trail, badge, and coordinate accuracy match iOS behavior.

Features in this document are what "Android working correctly" looks like, expressed as observable
behaviors and the diagnostic tooling needed to verify them.

---

## Feature Landscape

### Table Stakes (Must Work for Milestone to Close)

These are the behaviors that must be observable on Galaxy A32. Missing any one means the milestone
is not complete.

| Feature | Why Required | Complexity | Dependency on Existing Code |
|---------|--------------|------------|----------------------------|
| `onResult` fires with non-empty results | Without this, no detection, no trail, no badge — the entire YOLO pipeline is inert | HIGH | Existing `onResult` wiring in `live_object_detection_screen.dart:176`; may require plugin upgrade, clean rebuild, or model re-export |
| Trail dots appear on Android when ball is in frame | Confirms the full data path: TFLite inference → `onResult` → `BallTracker.update()` → `TrailOverlay` render | MEDIUM | `BallTracker` and `TrailOverlay` exist and work on iOS; no code changes expected if `onResult` is fixed |
| Trail dots are spatially accurate (centered on ball) | Camera aspect ratio on Android is unknown — may not be 4:3 like iOS. Wrong AR causes systematic offset | MEDIUM | `YoloCoordUtils.toCanvasPixel` uses `cameraAspectRatio = 4.0/3.0` hardcoded; Android camera AR must be verified empirically |
| "Ball lost" badge appears when ball exits frame | Confirms `_tracker.isBallLost` state transitions work when `onResult` fires (miss frames increment correctly) | LOW | Badge logic in `live_object_detection_screen.dart:231`; no code changes expected once `onResult` fires |
| "Ball lost" badge clears on ball re-detection | Confirms `_tracker.reset()` / `_consecutiveMissedFrames = 0` path works on Android | LOW | Same as above |
| Detection at acceptable frame rate (>= 15 fps subjective) | Galaxy A32 (Helio G80, no dedicated ML accelerator) will be slower than iPhone 12 A14. Must confirm it is not so slow as to be useless | MEDIUM | No code change; measurement only. Galaxy A32 is a mid-range 2021 device — TFLite CPU inference at YOLO11n nano should produce 10-25 fps (LOW confidence, requires device measurement) |
| Class filter works on Android results | `_pickBestBallYolo` must receive `className == 'Soccer ball'` or `'ball'` in Android results — class name strings must match what the model embeds | LOW | Class names are embedded in the TFLite model, same binary as iOS export; should match. Verify in logs. |

### Diagnostic Features (Enable Verification, Not End-User Features)

These are temporary or toggle-controlled outputs that make the fix verifiable. Most already exist
in the codebase on the SSD/TFLite path or as commented-out debug code; the question is whether to
add them to the YOLO path for Android testing.

| Feature | What It Shows | Complexity | Notes |
|---------|---------------|------------|-------|
| Frame counter badge (overlay) | Shows "N results this frame" or "0 results" — directly confirms whether `onResult` fires and what count it delivers | LOW | Add a `_resultCount` state variable; display as `Text` in the Stack next to the YOLO label badge. Remove or toggle with `kDebugMode` before final evaluation recording. |
| `log()` output for `onResult` first fire | Confirms the callback is invoked at all; timestamps help measure fps from the callback side | LOW | Add `log('onResult: ${results.length} results')` in `onResult`, gated by a `_firstResultLogged` bool to avoid logcat spam. Already partially exists in `_initializeCamera()` style. |
| Coordinate dump overlay (normalized x, y) | Shows the raw `normalizedBox.center` values the model is reporting; confirms the values are in sane [0,1] range before `YoloCoordUtils` transforms them | LOW | Reuse the existing coordinate text overlay from the SSD path (`live_object_detection_screen.dart:289-310`). Wire to `_tracker.lastKnownPosition` in YOLO mode. |
| Camera AR probe log | Android camera resolution from `YOLOView` is unknown — log the widget render size at first frame to determine which AR branch `YoloCoordUtils` takes | LOW | Add `log('canvas size: $size')` inside `TrailOverlay.paint()` for the first paint call. Alternatively observe from `MediaQuery` in `build()`. |
| FPS counter from `onResult` timestamps | Measures inference throughput on Android; needed to document Galaxy A32 performance finding | LOW | Record `DateTime.now()` on each `onResult` call; compute rolling 10-frame average interval. Display as `Text` in top-right alongside YOLO label badge. |

### Anti-Features (Do Not Build for This Milestone)

| Feature | Why Requested | Why Not Now | What to Do Instead |
|---------|---------------|-------------|-------------------|
| Automatic camera AR detection | "The AR shouldn't be hardcoded" | The AR assumption is already verified correct for iOS (4:3). If Android uses a different AR, the right fix is a one-time empirical measurement and a platform branch, not a runtime detection system. Runtime AR detection adds complexity with no research value. | Measure Android AR empirically via the camera AR probe log; hardcode a second constant or a `Platform.isAndroid` branch if different |
| Plugin upgrade to 0.2.0 as first step | v0.2.0 was released Jan 14 2026 and fixes EventChannel subscription timing; may fix `onResult` | May introduce other breaking changes; `pubspec.yaml` pin is at `^0.2.0` so it is already tracking the latest 0.2.x. The actual installed version must be verified with `flutter pub deps`. If already on 0.2.0, upgrade is not the fix. If on 0.1.x, upgrade is low-risk and should be tried first. | Run `flutter pub deps | grep ultralytics_yolo` to confirm installed version before changing anything |
| New detection pipeline (replace ultralytics_yolo) | "If the plugin is broken, switch to a different TFLite integration" | Switching Flutter ML libraries mid-POC invalidates all prior evaluation data and is weeks of work. The plugin has known fixes for Android in 0.1.37+ and 0.2.0. Try those first. | Exhaust plugin debug options (clean rebuild, plugin version, model path, permissions) before considering a library switch |
| Kalman filter or EMA smoothing | "Android might be jankier so add smoothing" | Smoothing masks the real performance data. The POC needs to capture raw detection quality on the A32, not polished output. | Record raw behavior; note jitter in evaluation findings |
| "Ball lost" badge timing tuning for Android fps | "Android fps might be lower so 3-frame threshold is too aggressive" | `ballLostThreshold = 3` frames at ~15fps = ~200ms on Android vs ~100ms on iOS. This is acceptable and actually more forgiving. Do not change the threshold; document the behavior. | Note in evaluation findings that badge timing scales with inference fps |

---

## Feature Dependencies

```
[Android onResult Fires]
    └──required by──> [Trail Dots Appear on Android]
                          └──required by──> [Trail Spatial Accuracy Verified]
                          └──required by──> [Ball Lost Badge State Transitions Verified]
                          └──required by──> [Android FPS Measured]

[Trail Spatial Accuracy Verified]
    └──requires──> [Camera AR Probe Log]
                       └──informs──> [YoloCoordUtils cameraAspectRatio value for Android]

[Frame Counter Badge]
    └──enhances──> [Android onResult Fires] (makes it visually confirmable without logcat)

[Coordinate Dump Overlay]
    └──enhances──> [Trail Spatial Accuracy Verified] (shows raw values before transform)
```

### Dependency Notes

- **Trail dots require `onResult` to fire:** `BallTracker.update()` is only called from inside `onResult`. If `onResult` never fires, `_tracker.trail` is always empty and `TrailOverlay` draws nothing. No code change to `TrailOverlay` or `BallTracker` will fix zero trail dots if the callback is silent.
- **Trail spatial accuracy requires camera AR measurement:** `YoloCoordUtils.toCanvasPixel` branches on whether the widget AR is wider or narrower than `cameraAspectRatio`. iOS uses 4:3. Android CameraX default is device-dependent — Galaxy A32 likely captures at 16:9 (1920x1080) or 4:3 depending on camera2 session configuration. Wrong assumption causes a systematic offset in the same direction as the iOS 16:9 bug that was fixed in v1.1. This MUST be measured before declaring trail accuracy verified on Android.
- **Badge state verification depends on `onResult` firing correctly AND consistently:** The badge appears after 3 consecutive missed frames. This requires `onResult` to fire on frames where no ball is present (empty results list), not only on frames where a ball is found. If the Android plugin only fires `onResult` when detections exist, `_consecutiveMissedFrames` will never increment and the badge will never show. This behavior difference must be tested explicitly.

---

## MVP Definition

### Launch With (v1.2 — what closes this milestone)

Minimum needed to answer: "Does the Android YOLO pipeline work at feature parity with iOS?"

- [ ] `onResult` fires on Galaxy A32 with YOLO path — confirmed via logcat or frame counter badge
- [ ] Trail dots appear on Galaxy A32 when soccer ball is in frame
- [ ] Trail dots are spatially accurate — centered on ball, no systematic offset
- [ ] "Ball lost" badge appears when ball exits frame, clears on re-entry
- [ ] FPS measurement documented (even if subjectively low is the finding)
- [ ] Evaluation recordings captured: Android trail behavior, Android badge behavior, Android FPS
- [ ] Camera AR finding documented (confirmed 4:3 or discovered different value)
- [ ] Class name behavior documented (confirms `className` strings from Android TFLite match class filter)

### Add After Core Pipeline Works (if time permits in v1.2)

- [ ] Frame counter badge — only add if logcat-based confirmation is insufficient for evaluation recordings
- [ ] Coordinate dump overlay — only add if trail accuracy is ambiguous and raw values are needed

### Out of Scope for This Milestone

- [ ] EMA smoothing or jitter reduction — POC records raw behavior
- [ ] Kalman filter — out of scope per PROJECT.md
- [ ] Multi-ball tracking — single-ball only
- [ ] Performance optimization for Galaxy A32 — measure and document only; no optimization

---

## Feature Prioritization Matrix

| Feature | Evaluator Value | Implementation Cost | Priority |
|---------|-----------------|---------------------|----------|
| `onResult` firing on Android | HIGH | HIGH (root cause unknown) | P1 |
| Trail dots appear on Android | HIGH | LOW (if onResult fixed) | P1 |
| Trail spatial accuracy (correct AR) | HIGH | LOW (measurement + possible 1-line constant change) | P1 |
| "Ball lost" badge state transitions | HIGH | LOW (if onResult fixed) | P1 |
| FPS measurement documented | MEDIUM | LOW (log timestamps) | P1 |
| Frame counter diagnostic badge | MEDIUM | LOW | P2 |
| Coordinate dump overlay | MEDIUM | LOW | P2 |
| Camera AR probe log | HIGH | LOW | P1 (diagnostic prerequisite for AR accuracy) |
| Class name verification via logcat | MEDIUM | LOW | P1 (must confirm strings match before writing off class filter as cause) |

**Priority key:**
- P1: Must have for v1.2 to close
- P2: Should have if P1 items are working and time remains
- P3: Future consideration

---

## Android-Specific Technical Behaviors

These are findings from research that directly affect what "working correctly" looks like on Android.

### What the Plugin Does Differently on Android vs iOS

| Concern | iOS Behavior | Android Behavior | Impact on This Project |
|---------|-------------|------------------|----------------------|
| Model format | `.mlpackage` via Xcode bundle | `.tflite` from `android/app/src/main/assets/` | Already handled: `Platform.isIOS ? 'yolo11n' : 'yolo11n.tflite'` |
| Model path syntax | Basename only: `'yolo11n'` | Full filename: `'yolo11n.tflite'` | Already correct |
| Camera API | AVFoundation, `.photo` session preset → 4:3 (4032x3024) | CameraX / Camera2 — default AR is device-dependent | **UNKNOWN for Galaxy A32.** Must probe. Likely 16:9 (1920x1080) which would mean `TrailOverlay.cameraAspectRatio` must switch to `16.0/9.0` on Android |
| ML execution | Core ML (Neural Engine on A14) — fast, hardware-accelerated | TFLite CPU inference (Helio G80, no dedicated NPU in Galaxy A32) — slower | Expected fps difference: iOS ~25-30fps, Android ~10-20fps |
| `onResult` callback timing | Confirmed working; fires every frame | Not firing (confirmed bug, v1.2 root cause) | Core investigation target |
| EventChannel subscription | Native view ready → subscription starts | Known bug fixed in v0.1.37: subscription must happen after native view ready | Check installed plugin version; if below 0.1.37 this is likely the root cause |
| Confidence scores | Typically >0.99 (Core ML precision) | Typically 0.8-0.9 (TFLite quantization) | Class filter `_pickBestBallYolo` selects by priority + confidence; lower confidence on Android is expected and acceptable |
| SIGSEGV on dispose | Rare | Fixed in v0.1.46 (TFLite interpreter disposal race condition) | Relevant if Android testing shows crash on screen exit |

### Camera Aspect Ratio Investigation Required

The iOS camera AR assumption (4:3) was determined by reading `YOLOView.swift` source code and confirmed empirically on iPhone 12. The Android equivalent — what AR `YOLOView` selects on Android via CameraX — has NOT been verified.

**Why this matters:** `YoloCoordUtils.toCanvasPixel` branches on `widgetAR > cameraAspectRatio`:
- Galaxy A32 in landscape: widget AR is approximately `16:9 = 1.78`
- If `cameraAspectRatio = 4/3 = 1.33`: the branch `widgetAR > cameraAspectRatio` is TRUE → "scaled by width, height cropped" formula
- If actual Android camera AR is `16:9 = 1.78` and widget AR is also `1.78`: the two are equal, no crop offset, coordinate maps correctly with either branch
- If actual Android camera AR is `16:9` but formula uses `4/3`: slight over-correction cropY that shifts dots upward

**Probe method:** Log `canvas size` inside `TrailOverlay.paint()` on first call. Compare to known screen resolution of Galaxy A32 (`720x1600` logical pixels in portrait → `1600x720` in landscape). Then log raw `normalizedBox.center` values to verify they appear in expected quadrants when ball is held at known screen positions.

### Confidence Score Behavior on Android

Research confirms Android TFLite models produce lower confidence scores than Core ML (0.8-0.9 vs >0.99). The existing `_pickBestBallYolo` filter selects by class priority (`Soccer ball: 0, ball: 1`) and then by confidence within the same class. It does NOT filter by minimum confidence threshold. This means lower Android confidence scores should not block detection — the filter will still pick the highest-confidence result among valid classes.

**Verify:** If `onResult` fires but `_pickBestBallYolo` returns null, the class name strings from the Android model must be checked. The model was trained with classes `Soccer ball`, `ball`, `tennis-ball`. If the TFLite export changed case or spacing, the string comparison fails silently.

---

## What "Fixed and Verified" Looks Like (Acceptance Criteria)

This section describes the observable end state — what a screen recording of the fixed Android build should show.

### Minimum Acceptance (must be present)

1. **Recording shows trail dots appearing** over a soccer ball held in front of the camera on Galaxy A32 in landscape mode, with YOLO backend active
2. **Trail dots are approximately centered on the ball** — no systematic vertical offset that was characteristic of the 16:9 bug on iOS
3. **Trail fades and auto-clears** — dots visibly fade from bright to dim as ball moves; trail disappears after ~1.5 seconds of ball being stationary, and clears entirely after ball is hidden for ~1 second
4. **"Ball lost" badge appears** within a few frames of ball exiting frame; badge disappears when ball returns
5. **No crash on screen entry or exit** on Galaxy A32
6. **Logcat or frame counter confirms** `onResult` is firing with non-zero results

### Acceptable Differences from iOS (not bugs)

- **Lower fps** — Galaxy A32 Helio G80 has no dedicated NPU. 10-20fps is acceptable. Document the number.
- **Lower confidence scores** — 0.8-0.9 range is expected from TFLite quantization. Not a bug.
- **Slightly different trail density** — fewer dots per second if fps is lower. This is expected and should be noted in the evaluation report.
- **Camera AR may differ** — if Android uses 16:9 instead of 4:3, updating `cameraAspectRatio` in `TrailOverlay` for the Android path is a one-line change, not a feature.

### Not Acceptable

- `onResult` silently not firing
- Zero trail dots with ball visibly in frame
- "Ball lost" badge permanently showing (stuck in lost state)
- Trail dots with systematic offset (ball center vs. dot center misaligned by >10% of screen dimension)
- Crash on screen entry

---

## Root Cause Investigation Map

Based on research, these are the ordered candidates to investigate when `onResult` does not fire on Android. Listed from most-likely (based on known plugin bugs) to least-likely.

| # | Candidate | Evidence | How to Confirm | Fix |
|---|-----------|----------|----------------|-----|
| 1 | Plugin version below 0.1.37 — EventChannel subscription timing bug | v0.1.37 release notes explicitly fix "onResult callback returns empty results without streamingConfig" | `flutter pub deps \| grep ultralytics_yolo` — compare to 0.2.0 | Run `flutter pub upgrade ultralytics_yolo` if below 0.1.37; verify `pubspec.lock` |
| 2 | Stale build artifacts — old plugin Kotlin/Java still running | Android plugin native code is compiled into the APK; a clean rebuild is required after plugin changes | N/A — always try first | `flutter clean && flutter pub get`, uninstall app from device, rebuild and reinstall |
| 3 | Model file not found at runtime — `yolo11n.tflite` absent or misplaced | Issue #344 confirms this manifests as silent failure (no crash, just no results) | Add `log()` to the first `onResult` call; if never fires, check `android/app/src/main/assets/yolo11n.tflite` exists and the path in code matches exactly | Confirm file is at `android/app/src/main/assets/yolo11n.tflite`; confirm `modelPath: 'yolo11n.tflite'` in `YOLOView` |
| 4 | `WidgetsFlutterBinding.ensureInitialized()` missing or called too late | Issue #393 notes this as cause of plugin channel not registering | Check `lib/main.dart` for binding initialization order | `WidgetsFlutterBinding.ensureInitialized()` must be the first call in `main()` |
| 5 | Camera permission not granted on Android | Android requires runtime camera permission; if not granted, `YOLOView` may show camera feed (partial initialization) but TFLite never starts | Check Android permissions dialog on first launch; check logcat for permission-related errors | `AndroidManifest.xml` must have `CAMERA` permission; confirm runtime grant |
| 6 | TFLite GPU delegate crash — model runs on CPU but result delivery fails | v0.1.46 fixed SIGSEGV during disposal; some devices have TFLite GPU delegate compatibility issues | Check logcat for `SIGSEGV`, `TFLite`, or `GPU delegate` messages | Disable GPU delegate in plugin config if available; fall back to CPU-only |
| 7 | `onResult` fires but `_pickBestBallYolo` returns null due to class name mismatch | Class names in TFLite model metadata might differ (case, spacing, special characters) | Add `log()` inside `onResult` to print all `results.map((r) => r.className)` | Update class name strings in `_pickBestBallYolo` priority map to match actual TFLite model output |

---

## Sources

- [ultralytics_yolo — pub.dev](https://pub.dev/packages/ultralytics_yolo) — current version 0.2.0, API signatures
- [ultralytics/yolo-flutter-app — GitHub Releases](https://github.com/ultralytics/yolo-flutter-app/releases) — v0.1.37 (EventChannel subscription fix), v0.1.46 (SIGSEGV dispose fix), v0.2.0 (YOLO26 support, numItemsThreshold) — HIGH confidence
- [Issue #344: Unable to load model from local asset](https://github.com/ultralytics/yolo-flutter-app/issues/344) — confirms silent failure when model not found; iOS vs Android path differences; confidence score differences between platforms — HIGH confidence
- [Issue #393: ModelLoadingException](https://github.com/ultralytics/yolo-flutter-app/issues/393) — `WidgetsFlutterBinding.ensureInitialized()` ordering; clean build requirement; Android assets directory placement — HIGH confidence
- [Issue #292: Camera aspect ratio and switching](https://github.com/ultralytics/yolo-flutter-app/issues/292) — letterbox preprocessing discussion; bilinear vs letterbox; 4:3 vs 16:9 model training input — MEDIUM confidence (resolved as "COMPLETED" but letterbox not confirmed implemented)
- [DeepWiki: ultralytics/yolo-flutter-app](https://deepwiki.com/ultralytics/yolo-flutter-app) — Android vs iOS platform differences; EventChannel architecture — MEDIUM confidence (AI-generated summary, not official)
- [CLAUDE.md and memory-bank/ (project codebase)](../../../CLAUDE.md) — confirmed existing code patterns, iOS 4:3 AR fix rationale, `_pickBestBallYolo` class filter, model class names — HIGH confidence
- Galaxy A32 hardware: Helio G80 CPU, no dedicated NPU — inference performance expectations are LOW confidence estimates pending device measurement

---

*Feature research for: Android YOLO pipeline verification (v1.2 milestone)*
*Researched: 2026-02-25*
