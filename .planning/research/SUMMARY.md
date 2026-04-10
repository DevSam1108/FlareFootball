# Project Research Summary

**Project:** Flare Football — Android YOLO Pipeline Verification (v1.2 Milestone)
**Domain:** Flutter on-device ML — cross-platform `ultralytics_yolo` TFLite debugging and Android inference verification
**Researched:** 2026-02-25
**Confidence:** HIGH

## Executive Summary

This research covers a tightly scoped engineering milestone: diagnosing and fixing the Android `onResult` silence bug in the YOLO pipeline on the Galaxy A32, then verifying feature parity with the already-confirmed iOS build. The failure mode is well-understood — the camera feed renders, but inference callbacks never reach Flutter. Research from direct plugin source inspection and official GitHub issues identifies a deterministic 7-step callback chain between the Android TFLite interpreter and the Dart `onResult` closure. The chain has 12 catalogued failure points, each with distinct logcat signatures that allow methodical elimination.

The recommended approach is diagnostic-first: do not change any code before running logcat. The overwhelming majority of reported Android `onResult` silences trace to one of three root causes — the model binary absent from `android/app/src/main/assets/`, the GPU delegate crashing on the Galaxy A32's Mali-G52/Helio G80 chipset, or a post-`setState` EventChannel subscription that the plugin drops and does not reliably reattach. Each of these has a low-cost fix (copy model file, add `useGpu: false`, or isolate `YOLOView` into its own `StatefulWidget`). Attempting code changes before confirming which step in the chain has failed wastes effort and can mask the actual bug.

The main risk for this milestone is timeline drift caused by working on the wrong layer. Android inference performance on the Helio G80 is expected to be 5-20fps (well below iPhone 12's ~30fps), and this difference is not a bug — it is a finding to document. Coordinate accuracy, badge state transitions, and trail rendering are all expected to work correctly once `onResult` fires, because the `BallTracker` and `TrailOverlay` logic is platform-agnostic and was already validated on iOS. The one genuine uncertainty is whether the FILL_CENTER camera AR calculation requires an Android-specific constant — the plugin targets 4:3 on Android via CameraX `RATIO_4_3`, matching iOS, but the actual delivered resolution on the Galaxy A32 has not yet been device-verified.

## Key Findings

### Recommended Stack

The entire stack for this milestone is pre-existing and frozen. No new dependencies are introduced. The diagnostic tooling is `adb logcat` filtered to seven plugin log tags (`YOLOView`, `YOLOPlatformView`, `YOLOPlatformViewFactory`, `CustomStreamHandler`, `ObjectDetector`, `YOLOFileUtils`, `YOLOPlugin`) plus Flutter debug console output. Android Studio or Android NDK debugging are optional but not required — the plugin's existing log statements are sufficient to identify which of the 7 chain steps is failing.

**Core technologies (all pre-existing):**
- `ultralytics_yolo 0.2.0` (locked): Primary ML pipeline — the bug lives in its Android native layer; direct plugin source has been read and all failure paths catalogued
- CameraX `1.2.3` (plugin-internal): Camera pipeline in `YOLOView.kt`; explicitly targets 4:3 aspect ratio via `AspectRatio.RATIO_4_3` — this matches the iOS 4:3 assumption in `YoloCoordUtils`
- LiteRT `1.4.0` (plugin-internal): TFLite inference in `ObjectDetector.kt`; GPU delegate may fail silently on Mali-G52; `useGpu: false` is the safe fallback
- `adb logcat`: Primary diagnostic tool — all critical failure paths produce distinct log signatures; tag filters documented in STACK.md
- `tflite_flutter 0.11.0` (pinned): SSD MobileNet fallback path — must not be bumped; the `app/build.gradle` TFLite exclude block prevents conflict with LiteRT 1.4.0 and must not be removed

### Expected Features

This milestone does not add features — it verifies existing feature parity on Android. The feature set is defined by what "Android working correctly" looks like.

**Must have (table stakes — v1.2 milestone blockers):**
- `onResult` fires on Galaxy A32 with YOLO backend — confirmed via logcat or debug log; this is the gateway to all other verification
- Trail dots appear on Android when ball is in frame — depends entirely on `onResult` firing; no code change to `TrailOverlay` or `BallTracker` is expected
- Trail dots are spatially accurate (no systematic Y-offset) — requires camera AR verification; 4:3 is expected but not yet device-confirmed
- "Ball lost" badge appears when ball exits frame and clears on re-entry — state transition logic is platform-agnostic; depends on `onResult` firing on frames with empty results
- FPS measured and documented (even if result is "too slow") — Galaxy A32 Helio G80 CPU-only inference expected at 5-12fps; this is a finding, not a bug

**Should have (diagnostic tooling — useful but not blockers):**
- Frame counter badge overlay — shows "N results this frame" without logcat; only add if logcat-based confirmation is insufficient for evaluation recordings
- Coordinate dump overlay — shows raw `normalizedBox.center` values; only add if trail accuracy is ambiguous after primary diagnosis
- Camera AR probe log — log `imageProxy.width x imageProxy.height` on first Android frame to confirm 4:3 assumption

**Defer (out of scope for this milestone):**
- EMA smoothing or Kalman filter — masks raw performance data that the POC needs to capture
- Automatic camera AR detection at runtime — one-time empirical measurement plus a constant is sufficient
- Confidence threshold tuning for Android — lower TFLite confidence scores (0.8-0.9 vs Core ML's >0.99) are expected; the class filter already handles this correctly

### Architecture Approach

The Android data flow is a linear 7-step chain from CameraX `ImageProxy` to the Dart `onResult` closure. Each step has been source-verified and all failure points catalogued. The chain is: `CameraX → YOLOView.onFrame() → ObjectDetector.predict() → JNI postprocess() → convertResultToStreamData() → EventChannel.EventSink → Dart _handleDetectionResults() → widget.onResult()`. The Dart-side trail rendering (`_pickBestBallYolo() → BallTracker.update() → TrailOverlay.paint()`) is downstream of `onResult` and requires no changes. The only permanent fix candidates are: placing the model binary, adding `useGpu: false`, fixing the misleading camera AR comment in `yolo_coord_utils.dart`, and potentially adding a `Platform.isAndroid` branch to the `cameraAR` constant in `TrailOverlay` if empirical measurement shows the Galaxy A32 delivers different AR geometry.

**Major components and responsibilities:**

1. `YOLOPlatformViewFactory` (Kotlin) — creates the platform view per Flutter `AndroidView`, wires the EventChannel and MethodChannel; failure here produces a blank camera, not just zero callbacks
2. `ObjectDetector` (Kotlin) — TFLite interpreter, GPU delegate, JNI NMS postprocessing; `predictor = null` on any load failure causes silent no-op in every subsequent `onFrame()` call
3. `CustomStreamHandler` (Kotlin) — holds the `EventSink`; sink becomes non-null only after Dart calls `receiveBroadcastStream().listen()`; a race window at startup can drop early frames (mitigated by 500ms retry)
4. `_YOLOViewState` (Dart) — subscribes to EventChannel, parses `detections` map, calls `widget.onResult`; a `setState`-triggered rebuild can cause `didUpdateWidget` to evaluate `callbacksChanged`, potentially killing the subscription if reconnect logic is in an inconsistent state
5. `LiveObjectDetectionScreen` (Dart) — `onResult` callback, `_pickBestBallYolo()`, `BallTracker.update()/markOccluded()`, `setState`; no changes expected here unless class name strings differ between Android TFLite model metadata and iOS Core ML model metadata

### Critical Pitfalls

1. **EventChannel drops after `setState` rebuild (Pitfall 1)** — `_YOLOViewState.didUpdateWidget` evaluates `callbacksChanged`; if the parent widget rebuilds frequently (which it does on every `onResult` detection), the plugin's internal reconnect logic can enter an inconsistent state where `_resultSubscription` is non-null but delivering nothing. Avoid by isolating `YOLOView` in its own `StatefulWidget` separate from the detection state; diagnose with `log()` only, never with stateful counter widgets (which can accidentally trigger the reconnect logic and mask the bug).

2. **GPU delegate silently fails on Galaxy A32, leaving `predictor = null` (Pitfall 2)** — YOLO11n TFLite models use TFLite ops (INT64 CAST, ADD v4) not supported by the Mali-G52 GPU delegate. The `catch` in `ObjectDetector` drops the delegate silently; if the failure is deeper (whole `setModel` throws), `predictor` is null and every `onFrame()` is a no-op. Camera renders normally. Zero callbacks to Flutter. Fix: add `useGpu: false` to `YOLOView` as the first diagnostic step.

3. **Model binary absent or compressed in APK (Pitfall 5)** — `yolo11n.tflite` is gitignored and must be manually placed in `android/app/src/main/assets/`. Additionally, `aaptOptions { noCompress 'tflite' }` must be present in `android/app/build.gradle` — without it, the Android Gradle Plugin may compress the binary in the APK, causing `AssetManager` to return corrupted data and model load to fail silently. This is the single most likely root cause and must be verified first.

4. **Diagnostic logging via stateful widgets masks the EventChannel bug (Pitfall 7)** — adding a visible frame counter widget that calls `setState` can accidentally trigger the EventChannel reconnect retry, making `onResult` appear to work only when the diagnostic widget is present. All diagnosis must use `log()` from `dart:developer` only, not new stateful widgets.

5. **`normalizedBox` coordinates transposed on Android when orientation flag is wrong (Pitfall 6)** — `ObjectDetector.predict()` is called with `(bitmap, w, h, ...)` in landscape and `(bitmap, h, w, ...)` in portrait. If `Configuration.ORIENTATION_LANDSCAPE` resolves incorrectly during the 1-2 frame window after `setPreferredOrientations`, `origShape` is transposed and `xywhn` values are relative to a transposed coordinate space. Trail dots appear on the wrong axis. Not a persistent bug — it affects only the first 2-3 frames. Note during trail accuracy verification; do not use those frames as evidence of a systematic offset.

## Implications for Roadmap

Based on research, the milestone decomposes into two sequential phases with a clear dependency: Phase 2 cannot start until Phase 1's blocker (`onResult` firing) is resolved.

### Phase 1: Android Inference Pipeline Diagnosis and Fix

**Rationale:** All other verification work is blocked on `onResult` firing. There is no point measuring coordinate accuracy, badge timing, or FPS until callbacks are confirmed flowing. The diagnostic order is strictly sequenced: model file → logcat → `showOverlays: true` canary → `useGpu: false` → EventChannel isolation. Each step either closes the investigation or narrows the failure to one remaining layer.

**Delivers:** Android YOLO inference results flowing to Flutter `onResult` callback on Galaxy A32; root cause identified and fixed; logcat evidence captured.

**Addresses:**
- P1 feature: `onResult` fires on Android (confirmed via `log()` in debug console)
- P1 feature: Class name strings verified (log `results.map((r) => r.className)` in `onResult`)

**Avoids:**
- Pitfall 5: Verify `aaptOptions { noCompress 'tflite' }` in `build.gradle` before any other step
- Pitfall 2: Add `useGpu: false` as first attempted fix if logcat shows no "ObjectDetector initialized"
- Pitfall 7: Use `log()` only; no stateful diagnostic widgets during this phase
- Pitfall 1: Isolate `YOLOView` in its own `StatefulWidget` if EventChannel is confirmed dropping after `setState`

**Pre-flight checklist (must complete before writing any code):**
1. Confirm `android/app/src/main/assets/yolo11n.tflite` is physically present
2. Confirm `aaptOptions { noCompress 'tflite' }` is in `android/app/build.gradle`
3. Run `flutter clean && flutter pub get` and confirm plugin version is `0.2.0` via `flutter pub deps`
4. Attach `adb logcat` filter before launching the app

**Research flags:** Standard patterns — this phase follows the documented 7-step diagnostic protocol from STACK.md. No additional research needed.

### Phase 2: Android Feature Parity Verification

**Rationale:** Once `onResult` fires, the trail and badge logic is expected to work without code changes — `BallTracker` and `TrailOverlay` are platform-agnostic. This phase focuses on empirical verification: camera AR, coordinate accuracy, badge state transitions, and FPS measurement. These are evaluation findings, not engineering tasks. The only code change likely needed is fixing the misleading 16:9 comment in `yolo_coord_utils.dart` and possibly updating the `cameraAR` constant if empirical measurement shows the A32 delivers AR geometry different from 4:3.

**Delivers:** Documented evaluation data for Android: trail accuracy (with ball, screen recording), badge behavior (screen recording), FPS measurement (logged timestamps), camera AR finding (logged `imageProxy` dimensions), comparison to iOS baseline.

**Addresses:**
- P1 feature: Trail dots appear and are spatially accurate
- P1 feature: "Ball lost" badge appears and clears correctly
- P1 feature: FPS documented
- P1 diagnostic: Camera AR probe log

**Avoids:**
- Pitfall 3: Verify Android camera AR is 4:3 (expected from plugin source) before accepting trail accuracy as correct; fix misleading comment in `yolo_coord_utils.dart`
- Pitfall 4: Discard first 2-3 frames after screen entry from coordinate accuracy assessment (orientation lock race)
- Pitfall 6: Log first valid `normalizedBox` and verify center values are approximately (0.5, 0.5) for ball at frame center

**Research flags:** Standard patterns — camera AR math is documented; all verification steps are observable on device. If AR discrepancy is found (actual Android AR differs from 4:3), ARCHITECTURE.md documents the exact `YoloCoordUtils` change needed (one constant or a `Platform.isAndroid` branch).

### Phase Ordering Rationale

- Phase 1 must precede Phase 2 because `onResult` is a hard dependency for all other observable behaviors — trail, badge, FPS, and coordinate accuracy are all downstream of the callback
- Within Phase 1, the diagnostic steps are ordered by likelihood (model file missing is the most common cause) and by isolation value (`showOverlays: true` canary confirms native inference before investigating the Dart EventChannel path)
- Within Phase 2, camera AR probe must precede trail accuracy sign-off; logging raw `normalizedBox` values must precede concluding that any observed dot offset is an AR problem vs a coordinate transposition problem (Pitfall 6)
- No phase requires new Dart or Kotlin code beyond minor diagnostic additions (all temporary) and one possible constant change in `yolo_coord_utils.dart`
- The `ballLostThreshold = 3 frames` value may warrant documentation of its perceptual timing at Android FPS (at 5fps, 3 frames = 600ms badge latency vs ~100ms on iOS); do not change the value, document the behavior

### Research Flags

Phases with standard patterns (skip additional research-phase):
- **Phase 1:** All failure modes and their logcat signatures are fully documented from direct plugin source inspection. The diagnostic protocol is sequenced and complete. No unknowns remain in the tooling layer.
- **Phase 2:** Camera AR math is source-verified (CameraX `RATIO_4_3` confirmed in `YOLOView.kt` line 529). The FILL_CENTER correction is already implemented and verified on iOS. Empirical device measurement is the only remaining step.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All relevant plugin source files read directly from pub-cache (`YOLOView.kt`, `ObjectDetector.kt`, `YOLOPlatformView.kt`, `YOLOPlatformViewFactory.kt`, `yolo_view.dart`). No inference — direct source reading. |
| Features | HIGH | Feature set is defined by existing iOS-verified behavior. Android differences are catalogued from plugin source and confirmed GitHub issues. FPS estimate (5-20fps) is LOW confidence pending device measurement. |
| Architecture | HIGH | Complete 7-step callback chain traced from CameraX `ImageProxy` to Dart `onResult`. All 12 failure points identified with logcat signatures. Component boundaries and responsibilities verified against actual source. |
| Pitfalls | HIGH | All 7 pitfalls sourced from: direct plugin source inspection, official CHANGELOG.md entries, and confirmed GitHub issues (#121, #292, #344, #393, #18522, #20302). One pitfall (misleading AR comment) sourced from existing codebase analysis. |

**Overall confidence:** HIGH

### Gaps to Address

- **Galaxy A32 actual inference FPS:** Research estimates 5-20fps based on Helio G80 CPU specs and YOLO11n model complexity. Actual device measurement is required. FPS directly affects `ballLostThreshold` perceived timing — at 5fps, 3-frame threshold = 600ms badge latency (versus ~100ms on iOS). Consider whether threshold needs an Android-specific value, but document raw behavior first before making any change.

- **Camera AR on Galaxy A32 empirically:** Plugin source confirms CameraX targets 4:3. Actual delivered resolution depends on hardware sensor support. Log `imageProxy.width x imageProxy.height` on first frame and compare. If delivered AR is not 4:3, one constant change is needed in `YoloCoordUtils`.

- **`onResult` firing on empty frames (no ball):** Badge logic depends on `onResult` firing with an empty results list when no ball is in frame, not just when a ball is found. Research could not confirm whether Android `onResult` fires for zero-detection frames — this must be verified empirically. If it does not fire on empty frames, `_consecutiveMissedFrames` never increments and the "Ball lost" badge never shows.

- **Class name strings from Android TFLite model metadata:** Custom model labels ("Soccer ball", "ball", "tennis-ball") are embedded as appended ZIP metadata in the `.tflite` file. `YOLOFileUtils.loadLabelsFromAppendedZip` should extract them. If metadata extraction fails, COCO 80 classes are used as fallback and `_pickBestBallYolo()` finds no matches. Verify by logging `results.map((r) => r.className)` on first `onResult` call.

## Sources

### Primary (HIGH confidence — direct source inspection)
- `/Users/shashank/.pub-cache/hosted/pub.dev/ultralytics_yolo-0.2.0/android/src/main/kotlin/com/ultralytics/yolo/YOLOView.kt` — complete `onFrame()` loop, `startCamera()`, `setTargetAspectRatio(RATIO_4_3)` confirmed
- `/Users/shashank/.pub-cache/hosted/pub.dev/ultralytics_yolo-0.2.0/android/src/main/kotlin/com/ultralytics/yolo/ObjectDetector.kt` — GPU delegate setup, silent `predictor = null` failure path
- `/Users/shashank/.pub-cache/hosted/pub.dev/ultralytics_yolo-0.2.0/android/src/main/kotlin/com/ultralytics/yolo/YOLOPlatformView.kt` — `sendStreamDataWithRetry`, sink null handling, EventChannel retry logic
- `/Users/shashank/.pub-cache/hosted/pub.dev/ultralytics_yolo-0.2.0/android/src/main/kotlin/com/ultralytics/yolo/YOLOPlatformViewFactory.kt` — `CustomStreamHandler`, channel naming, `activeViews` map
- `/Users/shashank/.pub-cache/hosted/pub.dev/ultralytics_yolo-0.2.0/lib/yolo_view.dart` — `didUpdateWidget` EventChannel reconnect path, `_handleDetectionResults`, `_parseDetectionResults`
- Project codebase: `lib/screens/live_object_detection/live_object_detection_screen.dart`, `lib/utils/yolo_coord_utils.dart`, `lib/screens/live_object_detection/widgets/trail_overlay.dart`, `memory-bank/progress.md`, `memory-bank/activeContext.md`

### Secondary (MEDIUM confidence — official changelogs and confirmed issues)
- [ultralytics/yolo-flutter-app GitHub Releases](https://github.com/ultralytics/yolo-flutter-app/releases) — v0.1.37 EventChannel subscription fix, v0.1.38 race condition fix, v0.1.46 SIGSEGV dispose fix, v0.2.0 release notes
- [CHANGELOG.md v0.1.33](https://github.com/ultralytics/yolo-flutter-app/blob/main/CHANGELOG.md) — "onResult and onStreamingData callbacks would stop working after setState calls" — directly describes Pitfall 1
- [Issue #344](https://github.com/ultralytics/yolo-flutter-app/issues/344) — silent model load failure; iOS vs Android path differences; platform confidence score differences
- [Issue #393](https://github.com/ultralytics/yolo-flutter-app/issues/393) — `ModelLoadingException`; `build.gradle` `aaptOptions` requirement; `WidgetsFlutterBinding` ordering
- [Issue #121](https://github.com/ultralytics/yolo-flutter-app/issues/121) — EventChannel `MissingPluginException` on Android; confirmed fixed in plugin updates
- [Issue #18522](https://github.com/ultralytics/ultralytics/issues/18522) — YOLO11 TFLite crashes on Android GPU delegate

### Tertiary (LOW confidence — estimates pending device measurement)
- Galaxy A32 inference FPS estimate (5-20fps): derived from Helio G80 CPU specs and YOLO11n model complexity; requires empirical measurement on device
- [DeepWiki: ultralytics/yolo-flutter-app](https://deepwiki.com/ultralytics/yolo-flutter-app) — AI-generated summary of Android vs iOS platform differences; treated as directional only

---
*Research completed: 2026-02-25*
*Ready for roadmap: yes*
