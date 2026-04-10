# Pitfalls Research

**Domain:** Flutter on-device ML — Android YOLO verification, `onResult` debugging, camera AR cross-platform, diagnostic overlay integration
**Researched:** 2026-02-25
**Confidence:** HIGH (source code inspection of installed plugin `ultralytics_yolo-0.2.0` Kotlin + Dart; official GitHub issues confirmed; existing codebase analysed)

---

## Critical Pitfalls

### Pitfall 1: EventChannel Subscription Races with `setState` Rebuild — `onResult` Silently Stops

**What goes wrong:**
`onResult` fires correctly at app start, then stops completely after the first `setState` call in the parent widget. Zero callbacks delivered from that point on. Camera feed continues rendering. No exception is thrown. The symptom exactly matches the reported Galaxy A32 failure: 42 seconds of footage, camera working, zero trail dots, zero badge.

**Why it happens:**
`_YOLOViewState._subscribeToResults()` subscribes to `_resultEventChannel.receiveBroadcastStream()`. When the parent widget calls `setState`, Flutter calls `didUpdateWidget` on `_YOLOViewState`. In `didUpdateWidget`, the plugin checks `callbacksChanged` — defined as whether `onResult` went from null to non-null (or vice versa). Since the callback reference itself does not change, `callbacksChanged` is false and the subscription is not recreated. However, the `AndroidView` platform view may have been re-embedded during the rebuild, causing the native EventChannel sink to be invalidated. The Android-side `sendStreamData` then finds `streamHandler.sink == null`, logs a warning, and schedules a retry. If the retry also finds a null sink, it calls `methodChannel?.invokeMethod("reconnectEventChannel", ...)` back to Flutter, which triggers `recreateEventChannel` in `_handleMethodCall`. This recreates the subscription — but only if the `mounted` check passes and `_resultSubscription == null` at that point. If the timer fires while a subscription is still technically alive (but producing nothing), the whole reconnect loop silently does nothing.

Source: `yolo_view.dart` lines 207-250 (`didUpdateWidget`), `YOLOPlatformView.kt` lines 193-288 (`sendStreamDataWithRetry`, `scheduleRetry`), changelog v0.1.33.

**How to avoid:**
1. Add a diagnostic log statement in `onResult` that prints to the Flutter debug console before processing any results. Confirm the callback fires at all on Android before assuming the issue is in processing logic.
2. To force-verify the EventChannel is live: temporarily add `onStreamingData: (data) => log('raw: $data')` alongside `onResult`. If `onStreamingData` fires but `onResult` doesn't, the parsing layer is the problem. If neither fires, the EventChannel is dead.
3. Do not call `setState` from inside `onResult` in a way that causes `YOLOView` itself to rebuild. Keep `YOLOView` in a widget that has stable state — it should never be removed and re-added to the tree. Wrapping `YOLOView` in a `RepaintBoundary` or separating it into its own `StatefulWidget` (separate from the overlay state) prevents cascading rebuilds.
4. If EventChannel is confirmed dead: invoke `controller.reconnectStream()` via a `YOLOViewController` after detecting a timeout (no callbacks for > 2 seconds).

**Warning signs:**
Camera renders. No trail dots appear at all. No "Ball lost" badge appears even when there is no ball in frame. Adding a `log()` call to `onResult` shows no output in the debug console. `flutter logs` on the Android device shows "Event sink is null, will retry" messages in logcat.

**Phase to address:**
Phase 1 of v1.2 — this is the root-cause investigation. Must be confirmed before any other work.

---

### Pitfall 2: GPU Delegate Failure on Galaxy A32 Causes Silent Model Load Failure, No Inference

**What goes wrong:**
`ObjectDetector` tries to add a `GpuDelegate()` during interpreter initialization (`useGpu: true` is the default). On the Galaxy A32 (MediaTek Helio G80), the GPU delegate may fail with "Can not open OpenCL library on this device" or an ADD/CAST operator version mismatch. The failure is caught by a `try/catch` in `interpreterOptions` setup — the GPU delegate is silently dropped and the interpreter falls back to CPU. However, if the failure occurs deeper in `Interpreter()` initialization (not just the delegate), the entire `setModel` call throws. The `setOnModelLoadCallback { success -> }` then fires with `success = false`, `initialized = true`, `startStreaming()` is called (so the EventChannel sends a "Streaming started" test message), but `predictor` remains null. With `predictor == null`, `onFrame` returns early for every frame without running inference. No `streamCallback` is ever called. `onResult` never fires.

Source: `ObjectDetector.kt` lines 77-92 (GPU delegate setup), `YOLOView.kt` lines 670-746 (`onFrame`: `predictor?.let { p -> ... }`), `YOLOPlatformView.kt` lines 112-128 (model load callback).

**Why it happens:**
YOLO11n TFLite models use advanced TFLite operations (INT64 CAST, ADD v4) that the GPU delegate on mid-range MediaTek devices does not support. The Android TFLite GPU delegate support matrix is device/chipset specific and is not documented per-model by Ultralytics. The Helio G80 uses a Mali-G52 GPU — OpenCL support is partial. Known failures on similar chipsets are documented in GitHub issues #17837, #18522, #20302.

**How to avoid:**
1. Add `useGpu: false` to the `YOLOView` constructor as the first diagnostic step. This forces CPU-only inference and bypasses the GPU delegate entirely.
2. Confirm model loads on CPU by checking logcat for "TFLite model loaded: yolo11n.tflite, tensors allocated" and "ObjectDetector initialized." log lines.
3. Once CPU inference is confirmed working, test with GPU enabled to determine if the device supports it. Never assume GPU works on mid-range Android devices.
4. If GPU fails silently, accept CPU-only for the Galaxy A32 POC evaluation. Document the performance difference.

**Warning signs:**
Logcat shows no "ObjectDetector initialized" message, or shows "GPU delegate error" followed by no further model loading logs. `onResult` never fires even after EventChannel connectivity is confirmed. Camera renders normally (camera startup is independent of model load).

**Phase to address:**
Phase 1 of v1.2 — diagnose in the same pass as Pitfall 1. Add `useGpu: false` as the first attempted fix after confirming EventChannel works.

---

### Pitfall 3: Android Camera Aspect Ratio is 4:3 But `YoloCoordUtils` Default Was Incorrectly Documented as 16:9

**What goes wrong:**
The `YoloCoordUtils.dart` source comment (line 29) says: "Defaults to 16/9, which covers iPhone 12 and Galaxy A32 standard video." This is wrong for both platforms. `YOLOView.kt` line 529 explicitly sets `setTargetAspectRatio(AspectRatio.RATIO_4_3)` for `previewUseCase` on Android. iOS uses `.photo` session preset (4032×3024 = 4:3), confirmed in Phase 7. Both platforms use 4:3.

However, the `cameraAspectRatio` parameter in `TrailOverlay` already defaults to `4.0 / 3.0` — this is correct. The discrepancy is only in the code comment. The actual rendering math is correct.

**The real risk:** If a future developer reads the comment and changes the parameter to `16.0 / 9.0`, trail dots will show a ~10% Y-axis offset on Android (in landscape, where the widget is wider than the 4:3 frame, so Y is the cropped axis). This is the same bug that was fixed in Phase 7 on iOS.

**Why it happens:**
The comment was written before the 4:3 Android confirmation. The code was correct but the comment was wrong. Android's standard `video` preset often defaults to 16:9 on many devices, which may have been assumed. The Ultralytics plugin overrides this explicitly.

**How to avoid:**
1. When running on Android for the first time, add a temporary diagnostic: log `imageProxy.width` x `imageProxy.height` inside `onFrame` in `YOLOView.kt`. For 4:3 with landscape mode and a 4:3 sensor, expect approximately 1440×1080 or 640×480.
2. Verify trail dot accuracy empirically: point camera at a stationary ball and check that dots center on it, not above or below it.
3. Fix the misleading comment in `yolo_coord_utils.dart` to say "4:3 on both iOS and Android (confirmed from plugin source)".
4. Do not change the `cameraAspectRatio` default from `4.0 / 3.0`.

**Warning signs:**
Trail dots consistently appear above or below the ball on Android but correctly on iOS. The offset is proportional to ball Y-position (near the top → small offset, near the bottom → large offset). This indicates the wrong AR is being used in the FILL_CENTER crop calculation.

**Phase to address:**
Phase 2 of v1.2 — verify after getting `onResult` to fire. Camera AR is likely already correct; verification is the task.

---

### Pitfall 4: Landscape Orientation Lock Race Condition on Android vs iOS

**What goes wrong:**
On iOS, `SystemChrome.setPreferredOrientations([landscapeLeft, landscapeRight])` in `initState` takes effect synchronously before the first frame renders. On Android, the orientation change is asynchronous and may take one or two frames to apply. During those frames, `YOLOView` renders in portrait orientation. The `onFrame` callback uses `context.resources.configuration.orientation` to detect landscape mode. If `onFrame` fires before the orientation has actually changed, it uses portrait mode processing (`p.predict(bitmap, h, w, ...)` instead of `p.predict(bitmap, w, h, ...)`). This swaps width and height for the inference call, producing incorrect bounding box coordinates for those initial frames.

**Why it happens:**
`SystemChrome.setPreferredOrientations` is a Flutter-level hint that translates to `setRequestedOrientation` on Android. The Activity must go through a configuration change cycle for the orientation to fully take effect. This is unavoidably asynchronous on Android. The `Configuration.ORIENTATION_LANDSCAPE` check in `YOLOView.kt` line 656 reads the current system configuration at frame time, not the requested orientation.

**How to avoid:**
1. Add a short `await Future.delayed(const Duration(milliseconds: 100))` after `SystemChrome.setPreferredOrientations` in `initState` before any detection-dependent UI is shown. This reduces (but doesn't eliminate) the race.
2. More robustly: add an orientation-change listener in Flutter. Only start evaluating `onResult` data after the orientation has settled.
3. For the POC evaluation, this race only affects the first few frames — it is not a persistent bug. Document it in the evaluation notes.
4. Do not use this as a root-cause explanation for `onResult` never firing — this race produces wrong coordinates for a few frames, not zero callbacks.

**Warning signs:**
First 2-3 trail dots after entering the YOLO screen appear in incorrect positions, then subsequent dots are correct. This is only visible if `onResult` is firing at all — it is a secondary concern.

**Phase to address:**
Phase 2 of v1.2 — note during trail accuracy verification. Not a blocker for Phase 1 diagnosis.

---

### Pitfall 5: Model File Not Found via AssetManager — `yolo11n.tflite` Path Resolution Failure

**What goes wrong:**
`YOLOPlatformView.kt` receives `modelPath = "yolo11n.tflite"` from Flutter. The `resolveModelPath` function (lines 493-502) checks whether the path starts with `/` (absolute) or `internal://` (app files dir). If neither, it passes the path through unchanged. `YOLOUtils.loadModelFile(context, "yolo11n.tflite")` then tries to open `yolo11n.tflite` from the Android AssetManager. This works only if the file is present in `android/app/src/main/assets/` AND the `flutter build apk` step has packaged it correctly.

If the file was placed in `assets/` but `pubspec.yaml` does not list the `android/app/src/main/assets/` path as a Flutter asset (it does not — this is a raw Android asset, not a Flutter asset), the file must be present directly in the `android/app/src/main/assets/` directory and must NOT be compressed by the APK build. Large binary files in Android assets are sometimes compressed by the APK packager, which causes `AssetManager.open()` to return corrupted data or fail.

**Why it happens:**
Android's `AssetManager` compresses files with certain extensions unless explicitly excluded. `.tflite` is not in the default exclusion list in older versions of the Android Gradle Plugin. `aaptOptions.noCompress` must include `tflite` in `android/app/build.gradle` to prevent this.

**How to avoid:**
Confirm `android/app/build.gradle` includes:
```groovy
android {
    aaptOptions {
        noCompress 'tflite'
    }
}
```
If this line is missing, add it. Without it, TFLite model files may be compressed in the APK, causing `MappedByteBuffer` loading to fail silently or produce a corrupt interpreter.

Verify the file is present before building:
```bash
ls -la android/app/src/main/assets/yolo11n.tflite
```

**Warning signs:**
Logcat shows `FileNotFoundException: yolo11n.tflite` or model loading fails with a corrupt buffer error. No "ObjectDetector initialized" log line appears. `setOnModelLoadCallback { success -> }` fires with `success = false`. Camera renders but inference never starts.

**Phase to address:**
Phase 1 of v1.2 — verify file placement and `aaptOptions` before any other diagnosis.

---

### Pitfall 6: `normalizedBox.center` Coordinate Semantics Differ Between Android and iOS

**What goes wrong:**
On iOS, `normalizedBox` values from `YOLOResult` are normalized relative to the full camera frame (0.0–1.0 in both axes). The FILL_CENTER crop correction in `YoloCoordUtils` accounts for the portion of the frame that is cropped when the camera preview fills the widget in landscape.

On Android, the `convertResultToStreamData` function in `YOLOView.kt` populates `normalizedBox` from `box.xywhn` (lines 1600-1604), which is normalized relative to `result.origShape` — the original image dimensions passed to the predictor. In landscape mode, `onFrame` calls `p.predict(bitmap, w, h, ...)`. The `origShape` is then `(w, h)` of the rotated bitmap. If the orientation detection is correct (landscape), `origShape` should match the camera frame dimensions. However, if the `isLandscape` flag was wrong for any frame (see Pitfall 4), `origShape` may be `(h, w)` — transposed — making `xywhn` relative to a transposed frame, which produces mirrored/swapped coordinates in the normalized box.

**Why it happens:**
`origShape` in `YOLOResult` is set from the bitmap dimensions passed to `predict()`. The `isLandscape` flag controls whether `predict(bitmap, w, h, ...)` or `predict(bitmap, h, w, ...)` is used. Getting this wrong produces a transposed coordinate space that is not corrected by the standard FILL_CENTER crop calculation.

**How to avoid:**
1. Log the first valid `normalizedBox` received on Android: `log('normalizedBox: ${ball.normalizedBox}')`. Verify that for a ball in the center of the frame, the values are approximately `(0.4, 0.4, 0.6, 0.6)`.
2. If `normalizedBox.left > normalizedBox.right` or values are outside 0–1, the coordinate space is inverted or transposed.
3. Confirm the device reports `ORIENTATION_LANDSCAPE` at inference time by adding a temporary logcat statement in `YOLOView.kt`'s `onFrame`.

**Warning signs:**
Trail dots appear on the wrong side of the frame (ball on left → dot on right, or ball at top → dot at bottom). Coordinate values in the diagnostic log are outside 0–1 range. Dots appear correct in landscape-left but mirror in landscape-right.

**Phase to address:**
Phase 2 of v1.2 — coordinate accuracy verification after `onResult` is firing.

---

### Pitfall 7: Adding Diagnostic Logging to `onResult` That Changes Rebuild Behavior

**What goes wrong:**
When diagnosing Android issues, a common approach is to add a `log()` call inside `onResult` to confirm the callback fires. If the `log()` is added inside `setState(() { ... })`, it does not change behavior. However, if the developer adds a visible diagnostic widget (e.g., a frame counter badge that updates on every callback), this adds another `setState` call path, which causes `_YOLOViewState` to rebuild. Rebuilding `_YOLOViewState` re-evaluates `didUpdateWidget`, which can trigger the EventChannel reconnect logic described in Pitfall 1. The diagnostic widget then appears to "fix" the issue (by repeatedly forcing EventChannel reconnection) without identifying the actual root cause.

**Why it happens:**
The act of observation changes the behavior because `setState` triggers `didUpdateWidget`, and the reconnect logic in `didUpdateWidget` / `_handleMethodCall` has a timer-based retry that can accidentally re-establish a dropped EventChannel. The result is an intermittently working callback that only fires when the diagnostic widget forces a rebuild cycle.

**How to avoid:**
1. Add diagnostic logging ONLY via `log()` from `dart:developer` inside the existing `onResult` callback — never add a new stateful widget to count detections during diagnosis.
2. To count frames without triggering rebuilds, use a simple `int` counter that is incremented in `onResult` and printed to the console, without calling `setState`.
3. When a fix is confirmed, remove all diagnostic code before evaluating detection accuracy — diagnostic rebuilds at 30fps have measurable performance impact on the Galaxy A32.

**Warning signs:**
`onResult` fires only when the screen has a diagnostic `StatefulWidget` overlaid on it. Removing the diagnostic widget makes `onResult` stop firing. This is the diagnostic itself masking the bug.

**Phase to address:**
Phase 1 of v1.2 — establish clean diagnostic methodology before any code changes.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| `useGpu: true` (default) without device capability check | No code change needed | Silent model load failure on unsupported Android GPU chipsets; `onResult` never fires | Never — always verify GPU support on target device |
| Assuming iOS-verified behavior transfers to Android | Saves testing time | Camera AR, coordinate systems, lifecycle management, and EventChannel reconnect all differ | Never for production; documented assumption is acceptable for POC if noted |
| Leaving misleading comment in `yolo_coord_utils.dart` ("16/9 for Galaxy A32") | No change needed | Future developer changes default to 16:9, reintroducing the ~10% offset bug | Never — fix the comment in the first v1.2 phase |
| Diagnosing with screen-visible counters that force rebuilds | Easy visual feedback | Masks EventChannel reconnect bugs; diagnostic behavior differs from production behavior | Never during root-cause investigation |
| Skipping `aaptOptions.noCompress 'tflite'` check | Faster setup | TFLite model silently compressed in APK on some Android Gradle Plugin versions; model fails to load | Never — check this first on every new Android project |
| Treating "camera renders" as proof that inference will work | Satisfying early confirmation | Camera and inference are independent pipelines in the plugin; camera-only mode runs when predictor is null | POC only with explicit documentation |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| `YOLOView` `onResult` on Android | Assume it works as soon as camera renders | Confirm callback fires with `log()` before building any dependent logic; EventChannel and camera are independent subsystems |
| TFLite GPU delegate on mid-range Android | Default `useGpu: true` works everywhere | Test `useGpu: false` first on Galaxy A32 (Mali-G52 GPU); GPU delegate fails on MediaTek Helio G80 for some YOLO11 ops |
| `android/app/src/main/assets/` model file | Copy file and assume APK includes it correctly | Verify `aaptOptions.noCompress 'tflite'` in `build.gradle`; missing this entry silently compresses the model binary |
| Android landscape orientation + `onFrame` | Assume orientation is settled when `initState` runs | `Configuration.ORIENTATION_LANDSCAPE` in `YOLOView.kt` reads live system state; may be portrait for first 1-2 frames after `setPreferredOrientations` |
| `normalizedBox` coordinates cross-platform | Treat as identical between iOS and Android | Verify empirically on each platform; on Android, `origShape` depends on `isLandscape` flag at inference time; incorrect flag produces transposed coordinates |
| EventChannel reconnect after `setState` | Assume reconnect logic handles all cases silently | The retry uses a 500ms timer and may not reconnect if `_resultSubscription` is non-null but dead; add explicit timeout detection and manual reconnect |
| `YOLOView` within a `setState`-heavy parent | Natural approach for single-screen app | Isolate `YOLOView` in a dedicated `StatefulWidget` to prevent `didUpdateWidget` from being called on every detection frame rebuild |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| CPU-only TFLite inference on Galaxy A32 (Helio G80, 8 cores) | Inference takes 80-200ms per frame; effective 5-12fps; trail has large gaps between dots | Accept this for POC evaluation; document measured latency; do not attempt to optimize CPU inference path | Immediately at 30fps target; but acceptable for feasibility POC |
| `setState` in `onResult` rebuilding the entire YOLO screen | 15-30 full widget tree rebuilds per second on A32; visible jank | Already addressed in v1.1 with `RepaintBoundary`; but adding any new stateful widget above `YOLOView` without isolation breaks this | At first frame, always — but visible only on constrained devices |
| Android `ImageAnalysis` frame backpressure with `STRATEGY_KEEP_ONLY_LATEST` | Dropped inference frames, trail gaps | Already set in plugin (`YOLOView.kt` line 533); do not change. This is intentional on slow devices | At inference latency > 1 frame period — intentional behavior |
| Memory pressure from unprocessed frame queue on A32 (2GB RAM) | App killed by Android OS during sustained detection session | Keep detection session under 5 minutes for POC testing; do not stream `includeOriginalImage: true` | At sustained 15+ minutes continuous inference |

---

## "Looks Done But Isn't" Checklist

- [ ] **`onResult` confirmed firing on Android:** Add `log('onResult: ${results.length} results')` and verify it prints in the Flutter debug console — not just that the screen shows a camera feed
- [ ] **Model loaded successfully on Android:** Logcat shows "ObjectDetector initialized" and "TFLite model loaded: yolo11n.tflite, tensors allocated" — not just that `YOLOPlatformView` init ran
- [ ] **`aaptOptions.noCompress 'tflite'` present in `build.gradle`:** Open `android/app/build.gradle` and confirm — not assumed
- [ ] **GPU delegate confirmed or explicitly disabled:** Logcat shows either "GPU delegate is used" or `useGpu: false` is set — not left as default without verification
- [ ] **Camera AR verified on Android:** First valid `normalizedBox` logged; center of a ball in frame center shows ~(0.5, 0.5) — not assumed to match iOS
- [ ] **Trail coordinate accuracy verified:** Trail dots visually center on ball in landscape orientation — not just that dots appear somewhere on screen
- [ ] **"Ball lost" badge fires and clears on Android:** Badge appears with ball out of frame and disappears on re-detection — not assumed to work because it works on iOS
- [ ] **Orientation is settled before evaluating trail positions:** First 2-3 frames after entering the YOLO screen are discarded from coordinate accuracy assessment — not used as evidence of systematic offset

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| EventChannel dead after `setState` | LOW | Add `YOLOViewController` with explicit `reconnectStream()` call; or isolate `YOLOView` into its own `StatefulWidget` to prevent parent rebuilds reaching it |
| GPU delegate failure causing predictor null | LOW | Add `useGpu: false` to `YOLOView` constructor; rebuild APK; no other code changes needed |
| Model file compressed in APK | LOW | Add `aaptOptions { noCompress 'tflite' }` to `android/app/build.gradle`; clean and rebuild APK (`flutter clean && flutter build apk`) |
| Wrong camera AR on Android causing dot offset | LOW | AR is already correct in `TrailOverlay` (`4.0 / 3.0`); only the code comment needs fixing; no functional change needed |
| Orientation race causing wrong coordinates on first frames | LOW | Add `await Future.delayed(Duration(milliseconds: 150))` in `initState` after `setPreferredOrientations`; POC-acceptable workaround |
| `normalizedBox` coordinates transposed on Android | MEDIUM | Add temporary `log()` to dump first valid normalizedBox; compare to expected center; if transposed, verify `isLandscape` flag in `YOLOView.kt` `onFrame` path |
| Diagnostic widget masking EventChannel bug | LOW | Remove diagnostic widget; confirm the underlying EventChannel issue then fix with controller reconnect |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|-----------------|--------------|
| EventChannel stops after `setState` (Pitfall 1) | Phase 1: Root-cause diagnosis | `log()` in `onResult` prints to debug console on Android at consistent rate; no reconnect messages in logcat |
| GPU delegate failure, predictor null (Pitfall 2) | Phase 1: Root-cause diagnosis | Logcat shows "ObjectDetector initialized"; `onResult` fires with `useGpu: false` |
| Camera AR comment wrong (Pitfall 3) | Phase 1: Code cleanup | Comment in `yolo_coord_utils.dart` corrected; no functional change |
| Orientation lock race on Android (Pitfall 4) | Phase 2: Coordinate verification | First 3 trail dots after screen entry discarded from assessment; subsequent dots accurate |
| Model file not found / compressed in APK (Pitfall 5) | Phase 1: Pre-flight checks | Logcat shows model loaded; `aaptOptions` confirmed in `build.gradle` |
| `normalizedBox` coordinate semantics differ (Pitfall 6) | Phase 2: Coordinate verification | First valid normalizedBox logged and verified against visual position |
| Diagnostic widget changes rebuild behavior (Pitfall 7) | Phase 1: Diagnostic methodology | All diagnosis uses `log()` only; no new stateful widgets during root-cause phase |

---

## Sources

- `ultralytics_yolo 0.2.0` Android source: `/Users/shashank/.pub-cache/hosted/pub.dev/ultralytics_yolo-0.2.0/example/android/ultralytics_yolo_plugin/src/main/kotlin/com/ultralytics/yolo/YOLOView.kt` — camera setup `startCamera()` line 529: `setTargetAspectRatio(AspectRatio.RATIO_4_3)` (VERIFIED: Android uses 4:3)
- `ultralytics_yolo 0.2.0` Dart source: `/Users/shashank/.pub-cache/hosted/pub.dev/ultralytics_yolo-0.2.0/lib/yolo_view.dart` — `didUpdateWidget` EventChannel reconnect logic lines 207-250 (VERIFIED: setState-triggered rebuild path exists)
- `ultralytics_yolo 0.2.0` Android source: `YOLOPlatformView.kt` lines 193-288 — `sendStreamDataWithRetry` / `scheduleRetry` (VERIFIED: sink-null path triggers reconnect attempt)
- `ultralytics_yolo 0.2.0` Android source: `ObjectDetector.kt` lines 77-92 — GPU delegate setup with silent catch (VERIFIED: GPU failure does not propagate to Flutter)
- ultralytics/yolo-flutter-app GitHub Issue #121 — "MissingPluginException: EventChannel not implemented for detectionResults stream on Android": [https://github.com/ultralytics/yolo-flutter-app/issues/121](https://github.com/ultralytics/yolo-flutter-app/issues/121)
- ultralytics/yolo-flutter-app CHANGELOG.md — v0.1.33 fix: "onResult and onStreamingData callbacks would stop working after setState calls": [https://github.com/ultralytics/yolo-flutter-app/blob/main/CHANGELOG.md](https://github.com/ultralytics/yolo-flutter-app/blob/main/CHANGELOG.md)
- ultralytics/yolo-flutter-app CHANGELOG.md — v0.1.24: "separate image processors for portrait/landscape modes" and landscape aspect ratio fix
- ultralytics/yolo-flutter-app CHANGELOG.md — v0.1.46: SIGSEGV crash fix during TFLite inference (race condition)
- ultralytics/yolo-flutter-app GitHub Issue #292 — "Question about switching between cameras, aspect ratio and resolution" (Android uses 16:9 stretch by default in older versions): [https://github.com/ultralytics/yolo-flutter-app/issues/292](https://github.com/ultralytics/yolo-flutter-app/issues/292)
- ultralytics/ultralytics GitHub Issue #20302 — "Internal error: Failed to apply delegate" (GPU delegate failures on Android): [https://github.com/ultralytics/ultralytics/issues/20302](https://github.com/ultralytics/ultralytics/issues/20302)
- ultralytics/ultralytics GitHub Issue #18522 — "exported YOLO11 tflite model crashes in Android (GPU)": [https://github.com/ultralytics/ultralytics/issues/18522](https://github.com/ultralytics/ultralytics/issues/18522)
- ultralytics/yolo-flutter-app GitHub Issue #160 — "Example application keeps crashing" (GPU delegate `NoClassDefFoundError`, model file not found): [https://github.com/ultralytics/yolo-flutter-app/issues/160](https://github.com/ultralytics/yolo-flutter-app/issues/160)
- ultralytics/yolo-flutter-app GitHub Issue #393 — "ModelLoadingException: Failed to load model" (MissingPluginException, build.gradle setup): [https://github.com/ultralytics/yolo-flutter-app/issues/393](https://github.com/ultralytics/yolo-flutter-app/issues/393)
- Existing codebase: `lib/utils/yolo_coord_utils.dart`, `lib/screens/live_object_detection/live_object_detection_screen.dart`, `lib/screens/live_object_detection/widgets/trail_overlay.dart`
- Memory bank: `memory-bank/progress.md` — confirmed v1.2 known gap: "onResult callback is NOT firing on Android Galaxy A32"

---
*Pitfalls research for: Android YOLO verification — diagnosing and fixing `onResult` callback failure on Galaxy A32 (v1.2 milestone)*
*Researched: 2026-02-25*
