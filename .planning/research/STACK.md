# Stack Research

**Domain:** Android YOLO TFLite inference callback debugging — `ultralytics_yolo ^0.2.0` on Galaxy A32
**Researched:** 2026-02-25
**Confidence:** HIGH (based on direct plugin source inspection) / MEDIUM (for root cause diagnosis)

---

## Scope

This document covers ONLY the stack knowledge needed to diagnose and fix the Android `onResult` silence issue for milestone v1.2. It documents the Android-side callback mechanism, the known failure points in `ultralytics_yolo 0.2.0`, and the diagnostic/fix approach.

It does NOT re-research: Flutter SDK, iOS path, MobX, trail rendering, `BallTracker`, or `tflite_flutter`. Those are validated and frozen.

---

## The Android Callback Chain (Source-Verified)

Understanding this chain is the diagnostic foundation. Here is the exact path a detection result takes from the TFLite model to the Dart `onResult` callback.

### Complete Chain (7 steps)

```
1. CameraX ImageAnalysis (background thread)
         ↓ imageProxy
2. YOLOView.onFrame() [YOLOView.kt]
         ↓ Bitmap (converted via ImageUtils.toBitmap)
3. ObjectDetector.predict() [ObjectDetector.kt]
         ↓ TFLite interpreter.run() → postprocess() JNI → List<Box>
4. YOLOView.onFrame() resumes
         ↓ convertResultToStreamData() → Map<String,Any>
5. streamCallback.invoke(streamData) [YOLOView.kt line ~732]
         ↓
6. YOLOPlatformView.sendStreamDataWithRetry() → sendStreamData()
         ↓ EventChannel.EventSink.success(streamData)
7. Flutter EventChannel → _YOLOViewState._handleEvent()
         ↓ _handleDetectionResults() → widget.onResult!(results)
```

### Key Files Involved

| File | Role |
|------|------|
| `YOLOView.kt` | Camera setup, `onFrame()` inference loop, `convertResultToStreamData()` |
| `ObjectDetector.kt` | TFLite model inference, JNI `postprocess()`, returns `YOLOResult` |
| `YOLOPlatformView.kt` | Bridges `streamCallback` to `EventChannel.EventSink` |
| `YOLOPlatformViewFactory.kt` | Creates `CustomStreamHandler`, names the event channel |
| `yolo_view.dart` | Dart side — subscribes `EventChannel`, calls `onResult` |
| `channel_config.dart` | Channel naming: `com.ultralytics.yolo/detectionResults_{viewId}` |

---

## Recommended Stack (Diagnostic Tools)

### Core Technologies (All Pre-Existing)

| Technology | Version | Purpose | Why Relevant |
|------------|---------|---------|--------------|
| `ultralytics_yolo` | `0.2.0` (locked) | Primary ML pipeline | The bug lives inside this package's Android native layer |
| CameraX (`camera-core`, `camera-camera2`, `camera-lifecycle`) | `1.2.3` (plugin-internal) | Android camera pipeline inside `YOLOView.kt` | Camera permission failure or lifecycle binding failure silently prevents `onFrame()` from running |
| LiteRT (formerly TensorFlow Lite) | `1.4.0` (plugin-internal) | TFLite inference in `ObjectDetector.kt` | Model load failure (wrong path, missing file, JNI crash) silently drops to `predictor = null` → no inference → no callbacks |
| Android Logcat | N/A | Primary diagnostic tool | Plugin emits `Log.d/e` on all critical paths; tag filters: `YOLOView`, `YOLOPlatformView`, `YOLOPlatformViewFactory`, `CustomStreamHandler`, `ObjectDetector`, `YOLOFileUtils📁📁` |
| `flutter run` with verbose logging | Flutter CLI | Dart-side event channel subscription errors surface here | `MissingPluginException` would appear in Flutter console if event channel not registered |

### Supporting Libraries (For Diagnostics)

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Android Studio Logcat | N/A | Real-time log filtering by tag | Use during device run to trace which step of the callback chain fails |
| `adb logcat` | ADB CLI | Headless log capture without Android Studio | `adb logcat -s YOLOView:D YOLOPlatformView:D CustomStreamHandler:D ObjectDetector:D YOLOFileUtils:D` |
| Flutter DevTools | SDK built-in | Event channel subscription state inspection | Confirm `_resultSubscription` is non-null after `_onPlatformViewCreated` |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| `adb logcat` | Real-time native Android log capture | Required diagnostic — most failures produce log output that is invisible without logcat |
| Android Studio | Full breakpoint debugging of Kotlin native code | Optional but powerful for deeper bugs |

---

## Installation

No new dependencies. Diagnosis uses existing build + ADB tooling.

```bash
# Build and run on Android device with logcat attached
flutter run --dart-define=DETECTOR_BACKEND=yolo

# In a separate terminal: filter Android logs to plugin tags
adb logcat -s YOLOView:D YOLOPlatformView:D CustomStreamHandler:D ObjectDetector:D YOLOPlugin:D YOLOFileUtils:D
```

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Logcat-first diagnosis (confirm which step fails) | Code changes first (guess and fix) | Never — without logcat, there is no evidence for which of 7 chain steps is failing |
| Test `showOverlays: true` first as canary | Test `showOverlays: false` immediately | Use `showOverlays: true` as a smoke test. If native boxes appear, inference is working and the bug is in the EventChannel/Dart path only |
| Verify model file presence first | Assume model file is present | The model file is gitignored and must be manually placed. A missing file causes silent `predictor = null` — inference never runs |

---

## What NOT to Do

| Avoid | Why | Do Instead |
|-------|-----|------------|
| Upgrading `ultralytics_yolo` beyond `^0.2.0` without explicit testing | Minor version bumps have broken this pipeline before (CLAUDE.md constraint). `0.2.0` is the locked version | Stay on `0.2.0`. If upgrade is needed, test on both platforms before committing |
| Removing the TFLite exclude block from `app/build.gradle` | `configurations.all { exclude group: "org.tensorflow", ... }` was explicitly added to prevent conflicts between the app's `tflite_flutter 0.11.0` and the plugin's LiteRT 1.4.0 dependencies. Removing it will cause duplicate class errors at build time | Leave the exclude block in place |
| Adding `android.permission.CAMERA` to the app's manifest manually | The plugin handles camera permission via `ActivityCompat.requestPermissions` internally. Double-declaring can confuse the permission flow | Do not modify `AndroidManifest.xml` unless the permission is genuinely absent |
| Assuming the bug is in Dart | Zero overlays in 42 seconds with camera feed rendering = the failure is in the native Android layer or at the EventChannel boundary, not in `_pickBestBallYolo` or `BallTracker` | Diagnose native layer first |

---

## Known Failure Modes in `ultralytics_yolo 0.2.0` Android (Source + Release Notes)

These are the failure modes identified from direct plugin source inspection and the official release history.

### Failure Mode 1: Model File Not Found → `predictor = null`

**Where it fails:** `YOLOView.setModel()` (line ~405), `ObjectDetector` constructor
**Mechanism:** If `YOLOUtils.loadModelFile(context, "yolo11n.tflite")` throws, the `catch` block sets `this.predictor = null` and calls `modelLoadCallback?.invoke(false)`. With `predictor == null`, `onFrame()` silently skips inference (`predictor?.let { ... }` — the `let` block never executes).
**Logcat signal:** `W/YOLOView: Failed to load model: yolo11n.tflite. Camera will run without inference.`
**File to verify:** `android/app/src/main/assets/yolo11n.tflite` must be physically present.

### Failure Mode 2: GPU Delegate Crash → Inference Silently Fails

**Where it fails:** `ObjectDetector` constructor (`GpuDelegate()` instantiation)
**Mechanism:** `useGpu = true` by default. On some devices (Galaxy A32 has a Mali-G57 GPU), the GPU delegate may throw during `addDelegate()`. The `catch` logs the error but inference continues on CPU — this is usually not the silent failure cause, but worth verifying.
**Logcat signal:** `E/ObjectDetector: GPU delegate error: ...`
**Fix if encountered:** Pass `useGpu: false` to `YOLOView`.

### Failure Mode 3: EventChannel Sink Null → Results Produced but Not Delivered to Dart

**Where it fails:** `YOLOPlatformView.sendStreamData()` (line ~219)
**Mechanism:** `streamHandler.sink` is set in `CustomStreamHandler.onListen()`. If Flutter's event channel subscription (`_subscribeToResults()` in `yolo_view.dart`) has not yet fired when the first detection results arrive, `sink` is null and `sendStreamData()` returns `false`. The retry handler (`scheduleRetry()`) fires 500ms later. If this race condition persists, results are dropped.
**Logcat signal:** `W/YOLOPlatformView: Event sink is null, will retry`
**Root cause:** `_subscribeToResults()` is called in `_onPlatformViewCreated()` — this fires after the platform view is created and the method channel is initialized. A timing issue where inference starts before the event channel is subscribed could cause initial result drops. This was a known bug fixed in v0.1.38 (subscribed at `_onPlatformViewCreated` instead of `initState`), but the retry logic in v0.2.0 should mitigate any remaining race.

### Failure Mode 4: `streamCallback` Never Set → Results Produced but Never Streamed

**Where it fails:** `YOLOPlatformView.setupYOLOViewStreaming()` (init block)
**Mechanism:** `yoloView.setStreamCallback { streamData -> ... }` is set during init. The `streamCallback` being null causes `YOLOView.onFrame()` to compute inference but skip the entire streaming path (`streamCallback?.let { ... }`). This would only occur if `setupYOLOViewStreaming` was not called or threw early.
**Logcat signal:** `D/YOLOView: Streaming callback set: false`
**Note:** The logcat line at `YOLOView.setStreamCallback` (`"Streaming callback set: ${callback != null}"`) is a direct diagnostic for this.

### Failure Mode 5: `onResult` Not Empty, But `detections` Key Missing From Stream Data

**Where it fails:** `YOLOView._handleDetectionResults()` in Dart
**Mechanism:** If `streamConfig` is null (returns `emptyMap()` from `convertResultToStreamData()`), the `detections` key is absent. Dart's `_handleDetectionResults` checks `event.containsKey('detections')` — if missing, silently returns. This was reported as a regression in some pre-`0.2.0` versions. In `YOLOPlatformView.setupYOLOViewStreaming()`, the code creates a default `YOLOStreamConfig` with `includeDetections = true` even when no `streamingConfig` param is passed — so this should be fixed in `0.2.0`, but worth verifying in logcat output.
**Logcat signal:** `D/YOLOView: ✅ Total detections in stream: 0 (boxes: 0, obb: 0)` (inference ran but produced zero detections — different from not running at all)

### Failure Mode 6: `LifecycleOwner` Not Available → Camera Never Starts

**Where it fails:** `YOLOPlatformView.init {}` — `yoloView.initCamera()`
**Mechanism:** `startCamera()` requires a `LifecycleOwner`. If `context is LifecycleOwner` evaluates to false (context is a wrapper, not the activity), camera fails to bind. The logcat message `"Context is not a LifecycleOwner, camera may not start"` would indicate this. The `YOLOPlatformViewFactory.create()` uses `activity ?: context` — if `setActivity()` was not called by the time `create()` runs, the fallback context may not be a `LifecycleOwner`.
**Logcat signal:** `W/YOLOPlatformView: Context is not a LifecycleOwner, camera may not start`
**Note:** `YOLOPlugin.onAttachedToActivity` sets the activity on the factory; if this lifecycle callback fires after the first view is created (possible on some Android versions), camera binds to a non-lifecycle context.

### Failure Mode 7: Camera Permission Not Granted → `initCamera()` Requests Permissions, Camera Doesn't Start

**Where it fails:** `YOLOView.initCamera()` → `ActivityCompat.requestPermissions()`
**Mechanism:** If the user has not granted camera permission, `initCamera()` triggers the system permission dialog. The camera only starts in `onRequestPermissionsResult()` after the user grants. If the Android 12 permission dialog appears and the user taps "Allow" but the permission result isn't properly routed back (via `YOLOPlugin.onRequestPermissionsResult` → `YOLOView.onRequestPermissionsResult`), the camera never starts.
**Logcat signal:** `D/YOLOPlugin: onRequestPermissionsResult called in YoloPlugin. requestCode: 10, activeViews: N`
**Note:** On Galaxy A32 running Android 12, the camera permission dialog timing can interfere with the plugin's lifecycle if the activity is in a particular state during startup.

---

## Diagnostic Protocol (Ordered Steps)

Execute in this order. Each step rules out a class of failures.

### Step 1: Verify Model File Presence (Most Likely Root Cause)

The `.tflite` model file is gitignored. If it was not manually placed on the Galaxy A32's build machine, `predictor` is null and no inference runs — this matches the observed symptom perfectly.

```bash
# Check file exists in the project
ls -la "android/app/src/main/assets/yolo11n.tflite"

# Verify it is bundled in the APK (after build)
unzip -l build/app/outputs/flutter-apk/app-debug.apk | grep tflite
```

Expected: `yolo11n.tflite` appears in APK under `assets/`. If absent: copy the file and rebuild.

### Step 2: Read Logcat During App Execution

Attach device and run with logcat. Look for the critical log sequence:

```bash
adb logcat -s YOLOView:D YOLOPlatformView:D CustomStreamHandler:D ObjectDetector:D YOLOPlugin:D YOLOFileUtils:D *:E
```

**Expected healthy sequence on startup:**
```
D/YOLOPlugin: YOLOPlugin attached to engine
D/YOLOPlugin: YOLOPlugin attached to activity: MainActivity
D/YOLOPlatformViewFactory: Creating YOLOPlatformView ... viewId: 0
D/CustomStreamHandler: Event channel for view 0 started listening
D/CustomStreamHandler: Sink set on main thread ...
D/YOLOPlatformView: Initializing with model: yolo11n.tflite, task: DETECT
D/YOLOPlatformView: Streaming callback set: true          ← CRITICAL
D/YOLOView: Camera setup completed successfully
D/ObjectDetector: TFLite model loaded: yolo11n.tflite, tensors allocated
D/YOLOPlatformView: Model loaded successfully (via setOnModelLoadCallback)
D/YOLOView: ✅ Total detections in stream: N (boxes: N, obb: 0)    ← per-frame
```

**If `D/YOLOView: ✅ Total detections` never appears:** Inference is not running → investigate Steps 3-5.
**If `detections in stream: 0` appears every frame:** Inference runs but model produces no results → investigate confidence threshold or model/label mismatch.
**If `W/YOLOPlatformView: Event sink is null` appears:** EventChannel race condition → investigate Step 6.

### Step 3: Verify Camera Permission

Check logcat for `requestCode: 10` (the plugin's camera permission request code). Confirm `"Camera setup completed successfully"` appears.

If the permission dialog is never shown on a fresh install and the camera feed IS visible, permissions are granted. Camera feed rendering (camera IS working visually) + zero detections = model or inference problem, not camera problem.

### Step 4: Canary Test — Enable Native Overlays

Temporarily change `showOverlays: false` to `showOverlays: true` in `live_object_detection_screen.dart`. If native bounding boxes appear on the Android screen, the entire pipeline is working: model loaded, inference running, EventChannel delivering, Dart receiving — and the bug is only in the Dart-side `_handleDetectionResults` parsing or `_pickBestBallYolo` filter. If no native boxes appear with `showOverlays: true`, the failure is native-side (steps 1-3).

### Step 5: Verify `streamingConfig` Is Not Blocking Detection Serialization

In `YOLOView._handleEvent()`, data only reaches `_handleDetectionResults()` if `widget.onStreamingData == null`. Our usage sets `onResult` but NOT `onStreamingData` — so this path is correct. No code change needed here.

However, verify in logcat that `D/YOLOView: ✅ Total detections in stream: N` appears (meaning `convertResultToStreamData` ran and included the `detections` key). If that log line never appears, `streamCallback` may be null.

### Step 6: If EventChannel Sink is Null

The `CustomStreamHandler.onListen()` sends a test message on attach. Check Flutter console for `Event channel active` message arriving on the Dart side. If not received, the event channel name mismatch is the problem.

The event channel name is built from `_viewId = UniqueKey().toString()` in Dart (e.g. `[#abc12]`) and must match exactly what the Android factory uses. This should be deterministic since both sides use `creationParams['viewId']` — but verify the Dart `_viewId` string and the Android `viewUniqueId` match in logcat.

---

## Critical Build Configuration Notes

### The TFLite Exclude Block (Must Remain)

The `app/build.gradle` contains:
```groovy
configurations.all {
    exclude group: "org.tensorflow", module: "tensorflow-lite"
    exclude group: "org.tensorflow", module: "tensorflow-lite-api"
    exclude group: "org.tensorflow", module: "tensorflow-lite-gpu"
    exclude group: "org.tensorflow", module: "tensorflow-lite-support"
}
```

This is intentional. The app has two TFLite consumers:
- `tflite_flutter: 0.11.0` (SSD MobileNet path, frozen)
- `ultralytics_yolo: 0.2.0` (YOLO path, uses LiteRT 1.4.0)

The exclude block prevents `org.tensorflow:tensorflow-lite` (older namespace) from conflicting with `com.google.ai.edge.litert:litert:1.4.0` (new namespace, used by the plugin). Removing this block causes duplicate class linker errors.

**Do not remove or modify this block.**

### Camera Permission in AndroidManifest

The `AndroidManifest.xml` does NOT declare `<uses-permission android:name="android.permission.CAMERA" />`. The `ultralytics_yolo` plugin's own manifest (in the plugin's `src/main/AndroidManifest.xml`, which is merged at build time) declares the permission. Verify the plugin manifest merge is not being suppressed.

```bash
# Check the merged manifest after build
cat android/app/build/intermediates/merged_manifest/debug/AndroidManifest.xml | grep CAMERA
```

If `android.permission.CAMERA` is absent from the merged manifest, the OS never grants the permission and the camera never starts.

---

## Version Compatibility

| Component | Version | Compatible With | Notes |
|-----------|---------|-----------------|-------|
| `ultralytics_yolo` | `0.2.0` | Flutter 3.38.9, Dart 3.10.8 | Locked. Minor bumps have broken the pipeline before |
| LiteRT (TFLite) | `1.4.0` | Galaxy A32, Android 12 | Plugin-internal. GPU delegate may fail on Mali-G57; `useGpu: false` fallback available |
| `tflite_flutter` | `0.11.0` | Must be excluded at app level to avoid conflict with LiteRT 1.4.0 | Do not bump |
| CameraX | `1.2.3` | Android 12 (API 31), minSdk 26 | Plugin-internal. Galaxy A32 is API 31 — within supported range |
| Android NDK | `28.2.13676358` (plugin) | Must match or be compatible with host app's NDK | Plugin requires NDK 27.2+ for 16KB page size support (Android 15+). Not critical for Galaxy A32 on Android 12 |
| minSdkVersion | `26` (app) vs `21` (plugin) | App's `26` is higher than plugin's `21` — no conflict | Galaxy A32 (API 31) is above both |

---

## Stack Patterns by Failure Category

**If model file is missing:**
- Place `yolo11n.tflite` in `android/app/src/main/assets/`
- Confirm with `unzip -l` that it appears in the built APK
- Rebuild and redeploy

**If GPU delegate fails on Galaxy A32:**
- Add `useGpu: false` to the `YOLOView(...)` widget in `live_object_detection_screen.dart`
- This forces CPU inference — slower but deterministic

**If EventChannel naming mismatch:**
- Add temporary `log()` call in Dart after `_onPlatformViewCreated` to print `_viewId`
- Compare against `viewUniqueId` in Android logcat
- They must match exactly

**If `predictor = null` confirmed in logcat (model load failed):**
- Check `YOLOFileUtils.loadLabelsFromAppendedZip` logs — if metadata JSON not found, labels fall back to COCO 80 classes
- Labels falling back is not fatal (inference still runs), but a load failure of the model binary itself is fatal
- Verify model format: file must be a valid TFLite flatbuffer (not CoreML `.mlpackage`, not ONNX)

**If inference runs but produces zero detections:**
- Confidence threshold default is `0.25` in `ObjectDetector.kt` (not `0.5` as in the Dart `YOLOView` default)
- The Dart default `confidenceThreshold: 0.5` is passed via `creationParams` and applied via `yoloView.setConfidenceThreshold()`
- If threshold is set too high AND the model's confidence for the custom classes is low on Android, results are filtered out entirely
- Diagnostic: lower `confidenceThreshold` to `0.1` in the `YOLOView` widget as a test

---

## Sources

- `/Users/shashank/.pub-cache/hosted/pub.dev/ultralytics_yolo-0.2.0/android/src/main/kotlin/com/ultralytics/yolo/YOLOView.kt` — full `onFrame()` inference loop, `convertResultToStreamData()`, `streamCallback` invocation (HIGH confidence, direct source)
- `/Users/shashank/.pub-cache/hosted/pub.dev/ultralytics_yolo-0.2.0/android/src/main/kotlin/com/ultralytics/yolo/YOLOPlatformView.kt` — `sendStreamData()`, `sendStreamDataWithRetry()`, EventChannel sink null handling (HIGH confidence, direct source)
- `/Users/shashank/.pub-cache/hosted/pub.dev/ultralytics_yolo-0.2.0/android/src/main/kotlin/com/ultralytics/yolo/YOLOPlatformViewFactory.kt` — `CustomStreamHandler`, event channel naming, `activeViews` map (HIGH confidence, direct source)
- `/Users/shashank/.pub-cache/hosted/pub.dev/ultralytics_yolo-0.2.0/android/src/main/kotlin/com/ultralytics/yolo/ObjectDetector.kt` — TFLite model loading, GPU delegate, JNI `postprocess()`, silent `predictor = null` on load failure (HIGH confidence, direct source)
- `/Users/shashank/.pub-cache/hosted/pub.dev/ultralytics_yolo-0.2.0/android/src/main/kotlin/com/ultralytics/yolo/Utils.kt` — `loadModelFile()` asset path resolution logic (HIGH confidence, direct source)
- `/Users/shashank/.pub-cache/hosted/pub.dev/ultralytics_yolo-0.2.0/lib/yolo_view.dart` — Dart-side event channel subscription, `_onPlatformViewCreated`, `_handleDetectionResults`, `onResult` invocation (HIGH confidence, direct source)
- [ultralytics/yolo-flutter-app GitHub Releases](https://github.com/ultralytics/yolo-flutter-app/releases) — v0.1.37 fix "onResult returns empty when no streamingConfig", v0.1.38 fix EventChannel race condition, v0.1.46 Android SIGSEGV guard (MEDIUM confidence, official changelog)
- [GitHub Issue #121 — MissingPluginException EventChannel on Android](https://github.com/ultralytics/yolo-flutter-app/issues/121) — confirmed EventChannel registration was a known Android bug; fixed in plugin updates (MEDIUM confidence, issue thread)

---

*Stack research for: Android YOLO TFLite onResult diagnosis — Flare Football Object Detection POC v1.2*
*Researched: 2026-02-25*
