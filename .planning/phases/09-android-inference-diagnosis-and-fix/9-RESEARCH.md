# Phase 9: Android Inference Diagnosis and Fix - Research

**Researched:** 2026-02-25
**Domain:** ultralytics_yolo Android TFLite callback pipeline / Android asset loading
**Confidence:** HIGH

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| DIAG-01 | Pre-flight checks pass — `aaptOptions { noCompress 'tflite' }` confirmed in `build.gradle`, plugin version confirmed `0.2.0`, model file confirmed present in `android/app/src/main/assets/` | Missing `aaptOptions` identified as critical gap; model file is physically present but must be verified at runtime; plugin version confirmed via pubspec.yaml |
| DIAG-02 | YOLO `onResult` callback delivers detection results to Flutter on Galaxy A32, confirmed via `log()` output showing detection data | Full 7-step callback chain mapped; specific log checkpoints identified at each step; `onResult` relies on EventChannel stream subscription initiated in `_onPlatformViewCreated` |
| DIAG-03 | Android TFLite model returns correct class name strings (`Soccer ball`, `ball`) matching iOS Core ML model, confirmed via logged `className` values | Label loading path traced — `YOLOFileUtils.loadLabelsFromAppendedZip` reads appended ZIP in `.tflite` file; if it fails, COCO 80-class fallback activates (would produce `sports ball`, not `Soccer ball`); noCompress is prerequisite for this to work |
| DIAG-04 | Root cause of `onResult` silence identified with logcat/log evidence, fix applied, and finding documented | Five plausible root causes ranked; each has specific logcat signatures to confirm or rule out |
</phase_requirements>

---

## Summary

Phase 9 must diagnose why the `ultralytics_yolo` `onResult` callback produces zero results on the Galaxy A32 across 42 seconds of recorded footage with a ball clearly visible. The camera feed renders correctly, which rules out the camera layer. The silence is in the inference pipeline or the EventChannel bridge from Android to Flutter.

The codebase has been read in full, including the plugin's Android Kotlin source (`YOLOView.kt`, `YOLOPlatformView.kt`, `ObjectDetector.kt`, `YOLOFileUtils.kt`, `Utils.kt`) and the Dart-side wiring (`yolo_view.dart`). Five root causes have been ranked by probability. The most likely cause is that `aaptOptions { noCompress 'tflite' }` is absent from the app's `build.gradle`, which causes Android's asset compression to corrupt the `.tflite` file at installation time, making `FileUtil.loadMappedFile()` fail silently — leading to a null predictor, no inference, and an empty `onResult`.

**Primary recommendation:** Add `aaptOptions { noCompress 'tflite' }` to `android/app/build.gradle`, verify on device with logcat, and confirm `onResult` fires with `Soccer ball`/`ball` className strings.

---

## Standard Stack

### Core (already in place)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `ultralytics_yolo` | `^0.2.0` | Flutter plugin wrapping YOLOView PlatformView | The project's primary ML integration; do not upgrade |
| Android `aaptOptions` | N/A (Gradle config) | Prevents asset compression of binary files | TFLite models must be memory-mapped; compression breaks `FileUtil.loadMappedFile()` |
| `FileUtil.loadMappedFile()` | LiteRT 1.4.0 | Maps TFLite model from Android assets into native memory | Standard TFLite Android loading pattern; requires uncompressed asset |
| Android logcat / `adb logcat` | Android SDK | Real-time log stream from connected device | Primary diagnostic tool for Android-side callback chain |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `dart:developer` `log()` | SDK | Flutter-side diagnostic logging visible in VS Code debug console | All Dart-side checkpoint logging |
| Android `Log.d(TAG, ...)` | Android SDK | Android-side logging from Kotlin plugin code | Already present throughout plugin; read via logcat |
| ProGuard / R8 rules | AGP 8.x | Prevents shrinking of TFLite runtime classes in release builds | Only relevant for release builds; debug builds are not minified |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `aaptOptions` | Copy model to `filesDir` at runtime | More complex; `aaptOptions` is the canonical, zero-code solution |
| Logcat via `adb` | Flutter `--verbose` flag | `--verbose` shows Flutter engine logs but not deep Android Kotlin logs; logcat is required to see plugin-level failures |

---

## Architecture Patterns

### The 7-Step Callback Chain

Understanding where the chain breaks is the diagnostic goal. Each step has a logcat signature.

```
Step 1: Flutter Dart — YOLOView widget builds → AndroidView created
        → Dart: _onPlatformViewCreated() called → _subscribeToResults() called

Step 2: Android Kotlin — YOLOPlatformView.init() runs
        → resolveModelPath() called (passes model name through unchanged)
        → yoloView.setModel("yolo11n.tflite", DETECT, useGpu=true) called on background thread

Step 3: Android Kotlin — YOLOView.setModel() runs on Executors.newSingleThreadExecutor()
        → loadLabels("yolo11n.tflite") → YOLOFileUtils.loadLabelsFromAppendedZip()
        → YOLOUtils.loadModelFile(context, "yolo11n.tflite") → FileUtil.loadMappedFile()
        → ObjectDetector(context, modelPath, labels, useGpu) constructed
        → interpreter = Interpreter(modelBuffer, interpreterOptions)

Step 4: Android Kotlin — ObjectDetector.init() completes
        → modelLoadCallback?.invoke(true) posted to main thread
        → YOLOPlatformView: startStreaming() called, yoloView.startCamera() called

Step 5: Android Kotlin — Camera starts, frames arrive in onFrame()
        → predictor?.let { p -> ... } — predictor must be non-null for inference to run
        → p.predict(bitmap, w, h, rotateForCamera=true, isLandscape=true) called
        → inferenceCallback?.invoke(resultWithOriginalImage)
        → streamCallback?.let { callback -> ... sendStreamDataWithRetry() }

Step 6: Android Kotlin — YOLOPlatformView.sendStreamData()
        → streamHandler.sink?.success(streamData) — sink must be non-null

Step 7: Dart — EventChannel stream receives data
        → _handleEvent() → _handleDetectionResults() → widget.onResult!(results)
```

### Diagnostic Pattern: Log Checkpoint Method

For each step, confirm passage via logcat tag. Plugin already logs extensively with `TAG = "YOLOView"` and `TAG = "YOLOPlatformView"`.

Key log tags to filter in logcat:
- `YOLOView` — camera start, model load, per-frame inference
- `YOLOPlatformView` — platform view init, streaming start, sink status
- `ObjectDetector` — model load, inference timing
- `YOLOFileUtils📁📁` — label loading from appended ZIP
- `YOLOUtils` — model file path resolution

### Diagnostic Pattern: Dart-Side Checkpoint

In `live_object_detection_screen.dart`, add `log()` calls to confirm `onResult` receives data:

```dart
onResult: (results) {
  log('[DIAG] onResult fired — ${results.length} results');
  if (results.isNotEmpty) {
    log('[DIAG] first className: ${results.first.className}, conf: ${results.first.confidence}');
  }
  if (!mounted) return;
  // ... existing code
},
```

### Anti-Patterns to Avoid
- **Relying on Flutter debug console alone:** Android Kotlin exceptions in the plugin layer do NOT surface in the Flutter debug console. They appear only in `adb logcat`. Skipping logcat means missing the root cause.
- **Rebuilding the app without clearing cache after build.gradle changes:** After adding `aaptOptions`, run `flutter clean && flutter pub get` before rebuilding to ensure the asset is re-packaged uncompressed.
- **Assuming the model file is valid because it exists:** The `.tflite` file in `android/app/src/main/assets/yolo11n.tflite` is physically present, but if it was installed compressed, `FileUtil.loadMappedFile()` will silently return a corrupted buffer that crashes the interpreter constructor — the crash appears in logcat, not Flutter.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Model loading from assets | Custom byte-copy loader | `FileUtil.loadMappedFile()` (already used by plugin) | Memory-mapped loading is the TFLite standard; hand-rolling risks off-by-one in file offsets |
| Logcat filtering | Custom log parser | `adb logcat -s YOLOView:D YOLOPlatformView:D ObjectDetector:D YOLOFileUtils:D` | Simple shell filter; no tooling needed |
| Label verification | External label file | Read `className` values from logged `onResult` data | Labels are embedded in model; the logged className is the ground truth |

**Key insight:** The entire diagnostic toolchain already exists — logcat, Dart `log()`, and the plugin's own extensive logging. No new tools are needed.

---

## Common Pitfalls

### Pitfall 1: Missing `aaptOptions { noCompress 'tflite' }` — Most Likely Root Cause
**What goes wrong:** Android's AAPT (Asset Packaging Tool) compresses all assets by default. A compressed `.tflite` file cannot be memory-mapped. `FileUtil.loadMappedFile()` either throws `IOException` or returns a buffer the interpreter cannot parse. The interpreter constructor throws, predictor stays null, `onFrame()` skips inference via `predictor?.let`, and `onResult` never fires.

**Why it happens:** The `aaptOptions` block is documented in TFLite Android quickstarts but is not automatically added by Flutter's Android scaffolding. This codebase's `android/app/build.gradle` does NOT have this block.

**How to avoid:** Add to `android/app/build.gradle` inside the `android {}` block:
```gradle
android {
    // ... existing config ...
    aaptOptions {
        noCompress 'tflite'
    }
}
```

**Warning signs:** Logcat shows `YOLOUtils: Loading model from assets: yolo11n.tflite` followed by `ObjectDetector: Failed to extract metadata` or an IOException, and then `YOLOView: Failed to load model: yolo11n.tflite. Camera will run without inference.`

**Confidence:** HIGH — this is the canonical Android TFLite gotcha. The build.gradle was read and confirmed: `aaptOptions` is absent.

---

### Pitfall 2: `configurations.all { exclude }` Conflicting With Plugin TFLite
**What goes wrong:** `android/app/build.gradle` has an aggressive `configurations.all` block that excludes `org.tensorflow:tensorflow-lite*` groups. The plugin uses `com.google.ai.edge.litert:litert:1.4.0` (the rebranded TFLite), which is a different group and should not be excluded. However, if there are transitive dependencies that bridge the two namespaces, this exclusion could cause runtime `NoClassDefFoundError` for TFLite classes.

**Why it happens:** The exclusion was added to resolve a conflict with `tflite_flutter: 0.11.0`. It is correct to exclude `org.tensorflow` from the app-level, since the SSD path uses `tflite_flutter` which bundles its own TFLite. But if the plugin's LiteRT 1.4.0 has any transitive dependency on the old `org.tensorflow` namespace, that dependency would be dropped.

**How to avoid:** Check logcat for `java.lang.NoClassDefFoundError` or `ClassNotFoundException` containing `tensorflow` or `litert`. If present, scope the exclusion more narrowly or move it into the `tflite_flutter` dependency configuration.

**Warning signs:** Logcat shows `E/AndroidRuntime: FATAL EXCEPTION` with a stack trace in `ObjectDetector.<init>` referencing a missing TFLite class.

**Confidence:** MEDIUM — the exclusion is targeting `org.tensorflow`, not `com.google.ai.edge.litert`. These are different Maven groups. Likely not the issue, but worth checking if aaptOptions fix doesn't resolve it.

---

### Pitfall 3: GPU Delegate Crash on Helio G80
**What goes wrong:** The Galaxy A32 uses a MediaTek Helio G80 SoC with a Mali-G52 GPU. TFLite GPU delegate support on Mali GPUs is inconsistent. `ObjectDetector` tries `addDelegate(GpuDelegate())` and catches the exception, but a crash at delegate initialization can leave the interpreter in an invalid state despite the catch block.

**Why it happens:** `GpuDelegate()` with default options may fail on certain Mali GPU drivers. The `catch (e: Exception)` in `ObjectDetector` logs the error but continues, but the interpreter may still be in an unusable state if GPU initialization partially succeeded before failing.

**How to avoid:** Check logcat for `ObjectDetector: GPU delegate error:`. If present, the predictor is running CPU-only. This is fine — it doesn't silence `onResult`. But if the exception is more severe (e.g., the interpreter constructor itself throws), `predictor` stays null.

**Warning signs:** Logcat shows `GPU delegate error:` followed by the inference still not running.

**Confidence:** LOW-MEDIUM — the catch block should handle this gracefully. CPU fallback should work. Worth checking but unlikely to be the root cause on its own.

---

### Pitfall 4: EventChannel Sink Is Null When First Frame Arrives
**What goes wrong:** The EventChannel sink (`streamHandler.sink`) is set when the Dart side calls `receiveBroadcastStream().listen()`. There is a race condition: if the first inference frames arrive before the Dart-side subscription is established, `sendStreamData()` logs `"Event sink is null, will retry"` and schedules a 500ms retry. If the model loads extremely fast, this race can cause the first few seconds of frames to be dropped — but eventually the sink connects and frames flow. However, if the Dart subscription never establishes (due to `_subscribeToResults()` returning early), all frames are silently dropped.

**Why it happens:** `_subscribeToResults()` in `yolo_view.dart` returns early if `widget.onResult == null && widget.onPerformanceMetrics == null && widget.onStreamingData == null`. The `onResult` callback IS provided in this app, so this early return should not trigger. But the timing of `_onPlatformViewCreated` vs. model load is worth verifying.

**How to avoid:** Add `log('[DIAG] _subscribeToResults called')` before the subscribe call and `log('[DIAG] EventChannel subscription active')` after it. Check if these logs appear.

**Warning signs:** Logcat shows repeated `"Event sink is null, will retry"` messages from `YOLOPlatformView` with no eventual `sink.success()` call.

**Confidence:** LOW — the retry logic in `YOLOPlatformView` is designed specifically to handle this race. The retry handler fires every 500ms until the sink connects. A permanent sink-null situation would require the Dart subscription to never establish, which would only happen if `onResult` was null (it is not).

---

### Pitfall 5: Label Loading Fallback Producing Wrong Class Names
**What goes wrong:** If `YOLOFileUtils.loadLabelsFromAppendedZip()` fails (which it will if the file is compressed — the `openFd` call will succeed but the ZIP metadata scan will find no PK header in the corrupted buffer), the code falls back to 80 COCO classes. The class name for a ball in COCO is `sports ball`, not `Soccer ball` or `ball`. The `_pickBestBallYolo` filter rejects all 80 COCO classes, so `onResult` fires but with empty results that pass the filter — producing no trail dots even when inference is technically running.

**Why this matters:** This is distinct from Pitfall 1. If the model loads successfully but labels fail to load from the appended ZIP (due to compression), inference runs but all detections have COCO class names. DIAG-03 requires confirming `className` values are `Soccer ball`/`ball`, not COCO fallback strings.

**How to avoid:** Log the className of every raw detection (before the priority filter) to confirm labels are correctly embedded. If you see `sports ball` in logcat, the ZIP label extraction failed.

**Warning signs:** `onResult` fires, logcat shows inference timing, but all `className` values are COCO strings (`person`, `sports ball`, etc.).

**Confidence:** HIGH — this is a direct consequence of the same `aaptOptions` issue. If aaptOptions is added, both label loading and model loading will be fixed simultaneously.

---

## Code Examples

### Fix 1: Add `aaptOptions` to `android/app/build.gradle`

The current `build.gradle` is missing this block entirely. It must be added inside the `android {}` closure.

```gradle
// File: android/app/build.gradle
android {
    namespace "com.example.tensorflow_demo"
    compileSdkVersion 36
    ndkVersion flutter.ndkVersion

    // ADD THIS BLOCK:
    aaptOptions {
        noCompress 'tflite'
    }

    configurations.all {
        exclude group: "org.tensorflow", module: "tensorflow-lite"
        exclude group: "org.tensorflow", module: "tensorflow-lite-api"
        exclude group: "org.tensorflow", module: "tensorflow-lite-gpu"
        exclude group: "org.tensorflow", module: "tensorflow-lite-support"
    }
    // ... rest unchanged
}
```

After adding, run:
```bash
flutter clean
flutter pub get
flutter run --dart-define=DETECTOR_BACKEND=yolo
```

---

### Fix 2: Dart-Side Diagnostic Logging in `onResult`

Add to `live_object_detection_screen.dart` `onResult` callback, replacing the silent existing handler temporarily during diagnosis:

```dart
onResult: (results) {
  // DIAG-02: Confirm onResult fires and log className values (DIAG-03)
  log('[DIAG-02] onResult fired — ${results.length} detections');
  for (final r in results) {
    log('[DIAG-03] className=${r.className}, conf=${r.confidence.toStringAsFixed(3)}, '
        'box=(${r.normalizedBox.left.toStringAsFixed(3)}, '
        '${r.normalizedBox.top.toStringAsFixed(3)}, '
        '${r.normalizedBox.right.toStringAsFixed(3)}, '
        '${r.normalizedBox.bottom.toStringAsFixed(3)})');
  }
  if (!mounted) return;
  final ball = _pickBestBallYolo(results);
  setState(() {
    if (ball != null) {
      _tracker.update(Offset(
        ball.normalizedBox.center.dx,
        ball.normalizedBox.center.dy,
      ));
    } else {
      _tracker.markOccluded();
    }
  });
},
```

Remove the diagnostic `log()` calls once DIAG-02 and DIAG-03 are confirmed.

---

### Logcat Command for Android Diagnosis

```bash
adb logcat -s YOLOView:D YOLOPlatformView:D ObjectDetector:D "YOLOFileUtils📁📁":D YOLOUtils:D
```

Key log sequence to look for on a successful run:
1. `YOLOUtils: Loading model from assets: yolo11n.tflite`
2. `YOLOFileUtils📁📁: Labels loaded (Appended ZIP): 3` ← 3 classes confirm custom model
3. `ObjectDetector: TFLite model loaded: yolo11n.tflite, tensors allocated`
4. `YOLOView: Camera setup completed successfully`
5. `YOLOPlatformView: Started streaming for view 0`
6. `ObjectDetector: Predict Total time: XX ms` ← per-frame inference timing

---

### Pre-Flight Checks: Commands and Expected Results

**Check 1: aaptOptions (DIAG-01)**
```bash
grep -n "noCompress" /Users/shashank/Desktop/Flare-Football\ Feasibility/object_detection/android/app/build.gradle
```
Expected after fix: line containing `noCompress 'tflite'`
Current state: no output (absent)

**Check 2: Plugin version (DIAG-01)**
```bash
grep "ultralytics_yolo" /Users/shashank/Desktop/Flare-Football\ Feasibility/object_detection/pubspec.yaml
```
Expected: `ultralytics_yolo: ^0.2.0` — confirmed present

**Check 3: Model file presence (DIAG-01)**
```bash
ls -lh /Users/shashank/Desktop/Flare-Football\ Feasibility/object_detection/android/app/src/main/assets/yolo11n.tflite
```
Expected: file exists with non-zero size — confirmed present (multiple `.tflite` files visible in asset listing)

---

## State of the Art

| Old Approach | Current Approach | Impact |
|--------------|-----------------|--------|
| `org.tensorflow:tensorflow-lite` Maven group | `com.google.ai.edge.litert:litert:1.4.0` | TFLite was rebranded; `configurations.all { exclude group: "org.tensorflow" }` correctly targets the old name and should not affect LiteRT |
| Manual `MappedByteBuffer` loading | `FileUtil.loadMappedFile()` | Standard pattern; requires `aaptOptions noCompress` |
| Direct callback via `inferenceCallback` | EventChannel stream (`streamCallback` → `sendStreamDataWithRetry`) | Plugin v0.2.0 uses EventChannel for `onResult` delivery — the `inferenceCallback` set in `YOLOPlatformView` is a no-op stub (`{ }`) and is NOT how `onResult` data reaches Flutter |

**Important clarification about the callback architecture:**
`YOLOPlatformView.init()` sets `yoloView.setOnInferenceCallback { result -> /* Callback for compatibility */ }` — this is an empty lambda. The actual data path to Flutter's `onResult` is:
`onFrame()` → `streamCallback?.invoke(streamData)` → `sendStreamDataWithRetry()` → `sink.success(streamData)` → EventChannel → Dart `_handleEvent()` → `widget.onResult!(results)`

This means: if `streamCallback` is null (i.e., `setupYOLOViewStreaming()` failed), `onResult` never fires regardless of whether inference succeeds.

---

## Open Questions

1. **Does the custom `yolo11n.tflite` have the appended ZIP metadata correctly embedded?**
   - What we know: The iOS `.mlpackage` produces `Soccer ball`/`ball` class names correctly. The custom Android `.tflite` was trained with the same classes.
   - What's unclear: Whether the Android `.tflite` export included the `TFLITE_ULTRALYTICS_METADATA.json` appended ZIP. If it was exported from a standard Ultralytics workflow (`yolo export format=tflite`), it should be there. If the file was converted from another format, the metadata may be absent.
   - Recommendation: Check logcat for `"Labels loaded (Appended ZIP): 3"` after aaptOptions fix. If it shows `"Using COCO classes as fallback"` instead, the model needs to be re-exported from Ultralytics with metadata.

2. **Is the `configurations.all { exclude }` block in `build.gradle` causing any runtime failures?**
   - What we know: The exclusion targets `org.tensorflow` (old name). The plugin uses `com.google.ai.edge.litert` (new name). These are different Maven groups.
   - What's unclear: Whether LiteRT 1.4.0 has any transitive runtime dependency that was shipped under the old `org.tensorflow` namespace.
   - Recommendation: If aaptOptions fix does not resolve the issue, temporarily remove the `configurations.all` block and rebuild. Check if `tflite_flutter 0.11.0` still compiles (it may conflict with LiteRT's transitive deps, which was the original reason for the exclusion).

3. **Does the Galaxy A32 Helio G80 support GPU delegate at all?**
   - What we know: Mali-G52 GPU; TFLite GPU delegate compatibility is hit-or-miss on Mali GPUs below G71.
   - What's unclear: Whether Helio G80 / Mali-G52 supports OpenCL or OpenGL ES 3.1 (required for GPU delegate).
   - Recommendation: Check logcat for `GPU delegate error:` or `GPU delegate is used.`. If GPU delegate fails, CPU fallback should work transparently. This is a finding to document, not a blocking issue.

---

## Sources

### Primary (HIGH confidence)
- Plugin source read directly: `/Users/shashank/.pub-cache/hosted/pub.dev/ultralytics_yolo-0.2.0/android/src/main/kotlin/com/ultralytics/yolo/` — all Kotlin files read and analyzed
- Plugin Dart source read directly: `/Users/shashank/.pub-cache/hosted/pub.dev/ultralytics_yolo-0.2.0/lib/yolo_view.dart` — EventChannel subscription flow confirmed
- Project `android/app/build.gradle` read directly — `aaptOptions` absence confirmed
- Project `pubspec.yaml` read directly — plugin version `^0.2.0` confirmed
- Project `android/app/src/main/assets/` listing — `yolo11n.tflite` presence confirmed

### Secondary (MEDIUM confidence)
- TFLite Android integration documentation pattern: `aaptOptions { noCompress 'tflite' }` is universally documented for TFLite Android asset loading. Required because `FileUtil.loadMappedFile()` uses memory-mapped I/O, which is incompatible with compressed assets.
- Google LiteRT rebranding: `com.google.ai.edge.litert` is the renamed `org.tensorflow:tensorflow-lite`. The Maven group change means the project's `configurations.all { exclude group: "org.tensorflow" }` block does not affect the plugin's LiteRT dependency.

### Tertiary (LOW confidence)
- Helio G80 / Mali-G52 GPU delegate compatibility: Based on general knowledge of Mali GPU TFLite support tiers. Not verified against current LiteRT 1.4.0 release notes.

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — read directly from plugin source and project files
- Architecture (callback chain): HIGH — traced through all 7 steps in Kotlin and Dart source
- Root cause ranking: HIGH for Pitfall 1 (confirmed absent config), MEDIUM for Pitfall 2, LOW for Pitfalls 3-4
- Pitfalls: HIGH — derived from source analysis, not speculation

**Research date:** 2026-02-25
**Valid until:** 2026-03-25 (plugin pinned at ^0.2.0; stable until plugin is upgraded)
