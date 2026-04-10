# Architecture Research

**Domain:** Flutter on-device ML — Android YOLO verification and camera AR investigation
**Researched:** 2026-02-25
**Confidence:** HIGH (native plugin source read directly from pub-cache; all key Kotlin and Dart files verified)

---

## Standard Architecture

### System Overview — Android YOLO Data Flow (v1.2 Focus)

The complete path from camera pixel to Flutter `onResult` callback on Android:

```
[CameraX Hardware]
      |
      | ImageProxy (YUV_420_888, 4:3, back camera)
      v
YOLOView.onFrame()         [cameraExecutor thread — single-threaded pool]
      |
      | ImageUtils.toBitmap()
      v
[Bitmap — ARGB_8888]
      |
      | ObjectDetector.predict(bitmap, w, h, rotateForCamera=true, isLandscape)
      v  [same cameraExecutor thread]
ObjectDetector.predict()
      |
      | imageProcessorCameraLandscape  (landscape: no rotation)
      |   OR imageProcessorCameraPortrait (portrait: Rot90Op(3) = 270-deg)
      v
[TensorImage → inputBuffer ByteBuffer]
      |
      | interpreter.run(inputBuffer, rawOutput)    [TFLite thread pool, GPU delegate]
      v
[rawOutput Array<Array<FloatArray>>  shape: [1, numClasses+4, anchors]]
      |
      | postprocess() via JNI ("ultralytics" .so)
      v
[resultBoxes Array<FloatArray>  [x, y, w, h, conf, classIdx]]
      |
      | Build List<Box> with xywh (pixel) + xywhn (normalized 0-1)
      v
YOLOResult(origShape, boxes, speed, fps, names)
      |
      | inferenceCallback?.invoke(resultWithOriginalImage)   [still cameraExecutor thread]
      |
      | streamCallback?.let { ... }   [if shouldProcessFrame() passes throttle check]
      |       |
      |       | sendStreamData(streamData)
      |       v
      |   retryHandler.post { sink.success(streamData) }   [marshalled to MAIN thread]
      |       |
      |       v
      |   EventChannel.EventSink.success()
      |       |
      v       v
 [NATIVE OverlayView.invalidate() → post to main]
      |
      v
[Dart EventChannel stream — "com.ultralytics.yolo/detectionResults_{viewId}"]
      |
      | _YOLOViewState._handleEvent(event)
      | → _handleDetectionResults(event) → _parseDetectionResults()
      v
widget.onResult!(List<YOLOResult>)   [Dart UI thread]
      |
      v
_pickBestBallYolo() → BallTracker.update/markOccluded() → setState()
      |
      v
TrailOverlay.paint() + "Ball lost" badge conditional render
```

---

### Component Responsibilities

| Component | Responsibility | New vs Existing |
|-----------|---------------|-----------------|
| `YOLOPlatformViewFactory` (Kotlin) | Creates `YOLOPlatformView` + wires EventChannel + MethodChannel per view instance | Existing in plugin |
| `YOLOPlatformView` (Kotlin) | Flutter PlatformView bridge; wires stream callback from `YOLOView` → `CustomStreamHandler` → EventSink | Existing in plugin |
| `YOLOView` (Kotlin) | CameraX setup (4:3 aspect ratio), `onFrame()` inference loop, `setStreamConfig()`, `setStreamCallback()` | Existing in plugin |
| `ObjectDetector` (Kotlin) | TFLite interpreter, label loading, three `ImageProcessor` variants (portrait/portrait-front/landscape), JNI NMS postprocessing | Existing in plugin |
| `YOLOFileUtils` (Kotlin) | Loads labels from appended ZIP metadata in `.tflite` file; falls back to 80 COCO classes | Existing in plugin |
| `YOLOUtils` (Kotlin) | `loadModelFile()`: tries absolute path first, then `FileUtil.loadMappedFile()` from assets | Existing in plugin |
| `CustomStreamHandler` (Kotlin) | Holds `EventChannel.EventSink`, marshals inference results to main thread | Existing in plugin |
| `_YOLOViewState` (Dart) | Subscribes to EventChannel, parses `detections` map, calls `widget.onResult` | Existing in plugin |
| `LiveObjectDetectionScreen` (Dart) | `onResult` → `_pickBestBallYolo()` → `BallTracker.update/markOccluded()` → `setState` | Existing in app — unchanged for v1.2 diagnostic pass |
| `BallTracker` (Dart) | Trail history, occlusion sentinels, 30-frame auto-reset | Existing in app |
| `TrailOverlay` (Dart) | Fading dot trail CustomPainter with FILL_CENTER crop correction | Existing in app |
| `YoloCoordUtils` (Dart) | FILL_CENTER offset math; camera AR = 4:3 by default | Existing in app — **camera AR value is Android-unverified** |

---

## Android-Specific Data Flow — Detailed Pipeline

### Phase 1: PlatformView Creation and Channel Wiring

```
Flutter build() → AndroidView(
    viewType: 'com.ultralytics.yolo/YOLOPlatformView',
    creationParams: {
        modelPath: 'yolo11n.tflite',
        task: 'detect',
        confidenceThreshold: 0.5,
        iouThreshold: 0.45,
        showOverlays: false,
        viewId: '<UUID string>',        ← _viewId = UniqueKey().toString()
        useGpu: true,
        lensFacing: 'back'
        // NOTE: no 'streamingConfig' key — Flutter app does NOT pass one
    }
)
    |
    v
YOLOPlatformViewFactory.create(context, platformIntViewId, creationParams)
    |
    ├── EventChannel("com.ultralytics.yolo/detectionResults_<UUID>")
    │       setStreamHandler(CustomStreamHandler)
    │       → sink becomes non-null when Dart calls receiveBroadcastStream()
    │
    ├── MethodChannel("com.ultralytics.yolo/controlChannel_<UUID>")
    │
    └── YOLOPlatformView(context, platformIntViewId, creationParams, handler, methodChannel, factory)
            |
            ├── setupYOLOViewStreaming(creationParams)
            │       streamingConfig param absent → creates DEFAULT YOLOStreamConfig
            │       (includeDetections=true, includeClassifications=true, etc.)
            │       yoloView.setStreamConfig(defaultConfig)
            │       yoloView.setStreamCallback { sendStreamDataWithRetry(it) }
            │
            ├── yoloView.onLifecycleOwnerAvailable(context)   ← IF context is LifecycleOwner
            ├── yoloView.initCamera()
            │
            └── yoloView.setModel('yolo11n.tflite', YOLOTask.DETECT, useGpu=true)
```

**Critical sequence observation:** `setStreamCallback` is wired in `setupYOLOViewStreaming()` BEFORE model loading begins. The EventChannel sink becomes valid only when Dart calls `_subscribeToResults()` → `_resultEventChannel.receiveBroadcastStream()`. That call happens in `_onPlatformViewCreated()` which fires after the native view is created. There is a race window here: inference callbacks can fire before the Dart side has subscribed.

### Phase 2: Model Loading (Background Thread)

```
yoloView.setModel('yolo11n.tflite', DETECT, useGpu=true)
    |
    Executors.newSingleThreadExecutor().execute {
        |
        ├── YOLOFileUtils.loadLabelsFromAppendedZip(context, 'yolo11n.tflite')
        │       Opens asset: 'yolo11n.tflite'
        │       Scans tail for PK header (appended ZIP)
        │       Reads 'TFLITE_ULTRALYTICS_METADATA.json' → { "names": {0: "Soccer ball", ...} }
        │       Returns ["Soccer ball", "ball", "tennis-ball"]    ← custom model labels
        │
        ├── YOLOUtils.loadModelFile(context, 'yolo11n.tflite')
        │       Not absolute path → FileUtil.loadMappedFile(context, 'yolo11n.tflite')
        │       Reads from android/app/src/main/assets/yolo11n.tflite
        │       Returns MappedByteBuffer
        │
        ├── Interpreter(modelBuffer, interpreterOptions)
        │       GpuDelegate added if useGpu=true
        │       allocateTensors()
        │
        ├── Reads input tensor shape: [1, H, W, 3]  (likely 640x640 for yolo11n)
        ├── Reads output tensor shape: [1, numClasses+4, anchors]
        │
        └── post {   ← runs on main thread after background work completes
                predictor = newPredictor
                modelLoadCallback?.invoke(true)
                if (allPermissionsGranted() && lifecycleOwner != null)
                    startCamera()
            }
    }
```

**Failure point A — Model file missing:** `FileUtil.loadMappedFile()` throws `IOException` if `android/app/src/main/assets/yolo11n.tflite` is absent. The `catch (e: Exception)` in `setModel()` sets `predictor = null` and calls `modelLoadCallback(false)`. Camera still starts but `onFrame()` skips inference because `predictor?.let { ... }` never executes. Camera preview visible, zero callbacks to Flutter.

**Failure point B — Label loading:** If the appended ZIP is malformed or metadata key is unexpected, labels fall back to 80 COCO classes. The custom class names "Soccer ball", "ball", "tennis-ball" are absent. Inference runs but `box.cls` returns COCO names — `_pickBestBallYolo()` finds no matches (priority map has no COCO name keys), returns null every frame. Trail never draws.

**Failure point C — GPU delegate crash:** On Galaxy A32 (Adreno 610 GPU), `GpuDelegate()` may throw or silently fail. If it throws during `Interpreter.Options.addDelegate()`, the entire `setModel()` block fails and `predictor` is never set. Workaround: set `useGpu: false` on the `YOLOView` widget to force CPU-only inference.

### Phase 3: Camera Initialization and Frame Delivery

```
YOLOView.startCamera()
    |
    ProcessCameraProvider.getInstance(context).addListener {
        |
        Preview.Builder()
            .setTargetAspectRatio(AspectRatio.RATIO_4_3)     ← matches iOS .photo preset
            .build()
        |
        ImageAnalysis.Builder()
            .setBackpressureStrategy(STRATEGY_KEEP_ONLY_LATEST)
            .setTargetAspectRatio(AspectRatio.RATIO_4_3)     ← 4:3 frames for inference
            .build()
        |
        imageAnalysisUseCase.setAnalyzer(cameraExecutor) { imageProxy ->
            onFrame(imageProxy)
        }
        |
        cameraProvider.bindToLifecycle(owner, cameraSelector, previewUseCase, imageAnalysisUseCase)
    }
```

**Failure point D — No LifecycleOwner:** `YOLOPlatformViewFactory.create()` uses `activity ?: context` as the effective context. If `activity` is null at factory creation time (e.g., engine attached before activity), `context` may not implement `LifecycleOwner`. The check `if (context is LifecycleOwner)` in `YOLOPlatformView.init()` then fails silently and `initCamera()` is called instead. `initCamera()` calls `startCamera()` only if `lifecycleOwner != null` — but `lifecycleOwner` was never set. Camera never binds. Preview is blank, zero frames, zero callbacks.

**Failure point E — Camera permissions not granted:** `allPermissionsGranted()` returns false → camera initialization deferred to `onRequestPermissionsResult()`. If permission was granted at a previous app launch (which is the expected state after first install), this should be fine. But the flow depends on `onRequestPermissionsResult` propagating from `YOLOPlugin.onRequestPermissionsResult()` → `YOLOPlatformView.yoloViewInstance.onRequestPermissionsResult()`. If this chain breaks, camera never starts.

### Phase 4: Per-Frame Inference and Result Delivery

```
onFrame(imageProxy)          [cameraExecutor thread]
    |
    ├── if (isStopped) → close and return
    ├── ImageUtils.toBitmap(imageProxy) → Bitmap (ARGB_8888)
    ├── if (isStopped) → return
    |
    predictor?.let { p ->
        |
        ├── if (!shouldRunInference()) → close and return   ← throttle check
        |
        ├── val isLandscape = orientation == ORIENTATION_LANDSCAPE
        │       ← reads context.resources.configuration.orientation
        │       ← on Galaxy A32 in landscape: isLandscape = true
        |
        ├── result = p.predict(bitmap, w, h, rotateForCamera=true, isLandscape=isLandscape)
        │       |
        │       └── if isLandscape: imageProcessorCameraLandscape (no rotation)
        │               else: imageProcessorCameraPortrait (Rot90Op(3))
        |
        ├── inferenceCallback?.invoke(result)
        │       [currently wired to empty lambda in YOLOPlatformView — does nothing]
        |
        └── streamCallback?.let { callback ->
                if (shouldProcessFrame()) {
                    updateLastInferenceTime()
                    val streamData = convertResultToStreamData(result)
                    // adds timestamp and frameNumber
                    callback.invoke(enhancedStreamData)
                }
            }
    }
    |
    imageProxy.close()
```

**Failure point F — Orientation detection:** `context.resources.configuration.orientation` reads the ACTIVITY orientation. In the Flutter app, landscape is forced via `SystemChrome.setPreferredOrientations()` in Dart. The underlying Activity orientation responds to this. However there is a timing window: if `onFrame()` fires during the orientation transition, `orientation` may read portrait even when the app is landscape. This causes `imageProcessorCameraPortrait` (270-degree rotation) to be applied instead of `imageProcessorCameraLandscape` (no rotation). Boxes will be systematically misplaced even if inference detects correctly.

**Failure point G — Stream callback null:** If `streamCallback` is null (was never set, or was cleared in `stop()`), the `streamCallback?.let` block never executes. `inferenceCallback` is wired to an empty lambda so it also does nothing. Zero data reaches Flutter even if inference is producing results. This would happen if `setupYOLOViewStreaming()` failed or `YOLOView.stop()` was called prematurely.

**Failure point H — shouldProcessFrame() throttles everything:** If `streamConfig.maxFPS` or `streamConfig.throttleIntervalMs` was set too aggressively, `shouldProcessFrame()` keeps returning false. The default `YOLOStreamConfig` created in `setupYOLOViewStreaming()` has `maxFPS=null` and `throttleIntervalMs=null`, so this should not be the issue for the default path. But worth confirming in logcat.

### Phase 5: EventChannel Delivery to Dart

```
sendStreamDataWithRetry(streamData)           [called from cameraExecutor thread]
    |
    sendStreamData(streamData)
        |
        sink = streamHandler.sink
        |
        ├── if (sink == null) → scheduleRetry() [500ms later]
        |
        └── if not on main thread:
                retryHandler.post {
                    sink.success(streamData)    [main thread]
                }
                latch.await(100ms)
```

**Failure point I — EventSink null at inference time:** The EventSink (`streamHandler.sink`) is set when Dart calls `_resultEventChannel.receiveBroadcastStream().listen(...)`. This happens in `_onPlatformViewCreated()`. `_onPlatformViewCreated` fires after the AndroidView is mounted. Model loading and first inference frames can occur before Dart subscribes. The retry logic (scheduleRetry every 500ms) should recover eventually, but there is a brief window at startup where frames are dropped silently.

**Failure point J — Channel name mismatch:** The EventChannel name is `"com.ultralytics.yolo/detectionResults_{viewId}"` where `viewId` is the UUID string (`UniqueKey().toString()`) passed in `creationParams["viewId"]`. Both Dart (`ChannelConfig.createDetectionResultsChannel(_viewId)`) and native (`resultChannelName = "com.ultralytics.yolo/detectionResults_$viewUniqueId"`) must use the same UUID. The factory extracts `dartViewIdParam = creationParams?.get("viewId")` and falls back to platform int if null. If the UUID is not correctly passed or parsed, channel names diverge and no events arrive.

### Phase 6: Dart-Side Parsing

```
_handleEvent(dynamic event)
    |
    if event is! Map → return silently        ← common silent failure point
    |
    _handleDetectionResults(event)
        |
        if !event.containsKey('detections') → return silently
        |
        _parseDetectionResults(event)
            |
            for each detection in event['detections']:
                validates: classIndex, className, confidence, boundingBox, normalizedBox all present and non-null
                → YOLOResult.fromMap(detection)
        |
        widget.onResult!(results)
    |
    → _pickBestBallYolo(results)
    → BallTracker.update / markOccluded
    → setState
```

**Failure point K — Missing 'detections' key:** If `convertResultToStreamData()` produces a map without a `"detections"` key (e.g., `streamConfig.includeDetections = false`), `_handleDetectionResults()` returns silently. The default `YOLOStreamConfig` has `includeDetections=true`, so this should be fine. But if an older config snapshot persists in memory, it could silently suppress results.

**Failure point L — YOLOResult parsing fails:** If `detection['normalizedBox']` exists but its `left/top/right/bottom` values are not the expected numeric types, `YOLOResult.fromMap()` throws and is caught by the outer `catch (e)` with only a `logInfo()` — no error propagates to the app. This is a silent parsing failure.

---

## Diagnostic Integration Points

These are the exact locations where Android-specific log statements should be added to diagnose the failure.

### Log Point 1: Model Load Entry — YOLOView.setModel()

**Location:** `YOLOView.kt` line ~403, inside `Executors.newSingleThreadExecutor().execute {`
**What to log:** Start of load, the `modelPath` received, success/failure outcome, predictor type created
**Already present:** `Log.w(TAG, "Failed to load model")` on failure — check logcat for `TAG=YOLOView`
**Without modifying plugin:** Filter logcat for `YOLOView` and `ObjectDetector` tags

```
adb logcat -s YOLOView:V ObjectDetector:V YOLOFileUtils:V
```

### Log Point 2: Model File Access — YOLOUtils.loadModelFile()

**Location:** `Utils.kt` line ~64
**What to log:** Which path is attempted, whether it's absolute or asset, success/failure
**Already present:** `Log.d(TAG, "Loading model from path: $finalModelPath")` and error logs
**Filter:** `adb logcat -s YOLOUtils:V`

### Log Point 3: onFrame() Execution — YOLOView

**Location:** `YOLOView.kt` line ~645
**What to log:** Frame counter, predictor null status, orientation value, bitmap dimensions
**Already present:** `Log.d(TAG, "onFrame: View is stopped")` on early returns
**Without plugin modification:** `adb logcat -s YOLOView:V` — look for absence of frame logs as evidence predictor is null or camera never started

### Log Point 4: Inference Result — ObjectDetector.predict()

**Location:** `ObjectDetector.kt` line ~312
**What to log:** `inferenceTimeMs`, number of boxes found, first box coordinates
**Already present:** `Log.d("TFLite", "Output shape: ...")` and `Log.d(TAG, "Postprocess result - Box $index: ...")` on each result
**Filter:** `adb logcat -s ObjectDetector:V TAG:V TFLite:V`

### Log Point 5: Stream Delivery — YOLOPlatformView

**Location:** `YOLOPlatformView.kt` line ~219 `sendStreamData()`
**What to log:** Whether `sink` is null, whether main thread dispatch succeeded
**Already present:** `Log.w(TAG, "Event sink is null, will retry")`
**Filter:** `adb logcat -s YOLOPlatformView:V CustomStreamHandler:V`

### Log Point 6: Camera Initialization — YOLOView.startCamera()

**Location:** `YOLOView.kt` line ~518
**What to log:** LifecycleOwner availability, camera binding success, use case binding failure
**Already present:** `Log.d(TAG, "Camera setup completed successfully")` and `Log.e(TAG, "Use case binding failed", e)`
**Filter:** `adb logcat -s YOLOView:V`

### Log Point 7: EventChannel Subscription — Dart side

**Location:** `yolo_view.dart` `_subscribeToResults()` and `_handleEvent()`
**Without plugin modification:** Add temporary `debugPrint()` in `LiveObjectDetectionScreen.onResult` callback
**Strategy:** The `onResult` callback already calls `setState` — if trail never draws, `onResult` is never called. Add `log('onResult called: ${results.length} results', name: 'Android')` at the top of the callback.

---

## Camera Aspect Ratio — Android vs iOS Investigation

### iOS (Verified)

The iOS path uses `.photo` session preset → camera captures at 4032×3024 (4:3 AR). `YOLOView.swift` hardcodes this. `YoloCoordUtils` uses `cameraAR = 4/3` for FILL_CENTER math. Trail dots are accurate.

### Android (Unverified)

The Android path uses `ImageAnalysis.Builder().setTargetAspectRatio(AspectRatio.RATIO_4_3)`. The actual delivered frame dimensions depend on the camera hardware of the Galaxy A32. **The 4:3 AR target may not be exactly honored** — CameraX selects the closest supported resolution. On Samsung Galaxy A32, typical CameraX 4:3 resolutions are 640×480, 1280×960, 1920×1440, or 2448×1836. All are 4:3, so `YoloCoordUtils.cameraAR = 4/3` should remain correct.

**However, the `origWidth` and `origHeight` passed to `predict()` and stored in `YOLOResult.origShape` differ between portrait and landscape:**

```kotlin
// In YOLOView.onFrame():
val w = imageProxy.width   // raw frame width from CameraX
val h = imageProxy.height  // raw frame height from CameraX

val result = if (isLandscape) {
    p.predict(bitmap, w, h, rotateForCamera = true, isLandscape = isLandscape)
} else {
    // Portrait: NOTE the swap — (h, w) not (w, h)
    p.predict(bitmap, h, w, rotateForCamera = true, isLandscape = isLandscape)
}
```

In portrait mode, `origWidth` and `origHeight` are swapped. In landscape mode, they are the raw CameraX frame dimensions (e.g., 1280×960). The `xywhn` normalized coordinates in the resulting `Box` objects are computed relative to these dimensions. If the orientation reading is wrong at inference time, the normalized box coordinates will be systematically transposed.

**Android FILL_CENTER crop math (from YoloCoordUtils):**

The `TrailOverlay` / `YoloCoordUtils` performs a FILL_CENTER offset correction assuming camera frames are 4:3. On Android the actual CameraX `PreviewView` uses `ScaleType.FILL_CENTER` (explicitly set in `YOLOView.init()`), matching the iOS behavior. The crop math should be the same. But this has not been device-verified on A32.

**Investigation approach:**
1. Enable native `showOverlays: true` temporarily (override in `live_object_detection_screen.dart`: `showOverlays: false` → `true`)
2. Observe native bounding boxes vs actual ball position
3. If boxes appear in wrong location → orientation or AR issue confirmed
4. Revert `showOverlays: false` after investigation

---

## Component Boundaries — What to Modify vs. What to Leave Alone

### Diagnostic Changes (temporary — revert after diagnosis)

| Location | Change | Purpose |
|----------|--------|---------|
| `LiveObjectDetectionScreen.onResult` callback | Add `log('ANDROID_DIAG: onResult fired, ${results.length} results', name: 'YOLO')` at top | Confirm whether Dart callback fires at all |
| `YOLOView` widget in `build()` | Temporarily change `showOverlays: false` to `showOverlays: true` | Confirm whether native inference is producing results visually |
| `YOLOView` widget in `build()` | Temporarily add `useGpu: false` | Isolate GPU delegate as cause of silent failure |
| Logcat filter on device | `adb logcat -s YOLOView:V ObjectDetector:V YOLOPlatformView:V CustomStreamHandler:V YOLOFileUtils:V` | Map complete failure chain |

### Fix Changes (permanent)

| Likely Fix | Location | Change Type |
|------------|----------|-------------|
| Model file absent | Manual device setup | Copy `yolo11n.tflite` to `android/app/src/main/assets/` |
| GPU delegate crash | `live_object_detection_screen.dart` `YOLOView` params | Add `useGpu: false` to `YOLOView()` constructor call |
| Camera AR correction (if needed) | `lib/utils/yolo_coord_utils.dart` | Update `cameraAR` constant after empirical measurement |
| Android-specific AR constant | `lib/utils/yolo_coord_utils.dart` | Add `Platform.isAndroid ? androidAR : 4/3` branching |

### Never Modify Without Discussion

- Plugin source in `~/.pub-cache/` — those are read-only runtime copies; any patch would require a local override or fork
- `pubspec.yaml` `ultralytics_yolo` version pin — was deliberately set at `^0.2.0`
- `lib/config/detector_config.dart` — backend switching affects both pipelines
- Orientation lock logic in `live_object_detection_screen.dart` `initState`/`dispose` pair

---

## Architectural Patterns

### Pattern 1: EventChannel Sink Resilience

The plugin implements retry logic for the case where `sendStreamData()` is called before the Dart side has subscribed (`sink == null`). A `retryHandler.postDelayed(retryRunnable, 500)` loop runs until the sink becomes available. This is architectural resilience for the startup race condition.

**Implication for diagnosis:** If inference is running but the Dart callback never fires, the retry mechanism should eventually deliver at least one frame. If after 2-3 seconds of video the callback still never fires, the failure is upstream — either inference is not running or `streamCallback` was never set.

### Pattern 2: Default Stream Config When No Config Passed

When `YOLOView` is constructed without a `streamingConfig` parameter (which is the case in the existing `LiveObjectDetectionScreen`), `setupYOLOViewStreaming()` creates a default `YOLOStreamConfig` with `includeDetections=true`. This is important: the `convertResultToStreamData()` function only populates the `"detections"` key if `config.includeDetections == true`, and `_handleDetectionResults()` on the Dart side only processes the event if the `"detections"` key exists. The default config ensures this path is active.

### Pattern 3: Orientation-Conditional Image Processor Selection

`ObjectDetector` pre-builds three `ImageProcessor` instances at initialization time (portrait, portrait-front, landscape). The correct one is selected per frame based on `isLandscape` and `isFrontCamera`. This avoids per-frame allocations. The app locks to landscape (`SystemChrome.setPreferredOrientations([landscapeLeft, landscapeRight])`), so in steady state, `imageProcessorCameraLandscape` (no rotation) is always selected. This is correct and efficient.

### Pattern 4: JNI NMS Postprocessing

`postprocess()` is a JNI call into `libltralytics.so`. It performs NMS and confidence filtering. The function signature takes the raw `rawOutput[0]` (shape `[numClasses+4, anchors]`), not the transposed form. This is different from standard TFLite postprocessing patterns. The commented-out transpose code in `ObjectDetector.predict()` suggests the postprocessing library was updated to accept the non-transposed form directly.

---

## Data Flow — Failure Branch vs Success Branch

### Success Branch (inference running, callback firing)

```
model loaded OK
    → predictor non-null
    → camera bound to lifecycle
    → onFrame() called ~30/sec
    → p.predict() returns List<Box> with correct labels
    → convertResultToStreamData() includes "detections" key
    → streamCallback fires
    → sink.success(map)
    → Dart _handleEvent(map)
    → contains 'detections' key → onResult(results)
    → results contains "Soccer ball" or "ball" className
    → _pickBestBallYolo returns non-null
    → _tracker.update() called
    → TrailOverlay paints
```

### Failure Branch A — Model File Missing

```
yolo11n.tflite absent from assets/
    → FileUtil.loadMappedFile() throws IOException
    → catch block: predictor = null, modelLoadCallback(false)
    → camera still starts (startCamera called from loadCallback's post{})
    → onFrame() fires but predictor?.let {} = no-op
    → zero streamCallback invocations
    → zero onResult callbacks
    → camera preview visible, trail blank
```

**Symptom:** Camera feed visible, no trail, no "Ball lost" badge, logcat shows `Failed to load model: yolo11n.tflite`

### Failure Branch B — Label Mismatch (COCO Fallback)

```
labels load fails (ZIP metadata not found or malformed)
    → labels = 80 COCO classes (no "Soccer ball", "ball", "tennis-ball")
    → inference runs, produces results
    → box.cls = COCO class name (e.g. "sports ball")
    → convertResultToStreamData includes detections with className="sports ball"
    → onResult fires with results
    → _pickBestBallYolo: priority map has no "sports ball" → returns null every frame
    → _tracker.markOccluded() every frame
    → "Ball lost" badge always shown, no trail dots
```

**Symptom:** "Ball lost" badge permanently visible, trail never draws, `onResult` is called (camera+inference working), logcat shows `Using COCO classes as fallback`

### Failure Branch C — GPU Delegate Crash

```
GpuDelegate() constructor throws
    → setModel() catch block fires: predictor = null
    → camera starts but onFrame() = no-op
    → identical to Failure Branch A symptoms
```

**Symptom:** Same as A. Logcat shows `GPU delegate error:` in `ObjectDetector` tag

### Failure Branch D — No LifecycleOwner

```
context is not LifecycleOwner (or activity null at factory creation)
    → yoloView.onLifecycleOwnerAvailable() not called
    → lifecycleOwner = null
    → startCamera() checks: if (lifecycleOwner != null) — fails
    → camera never binds
    → onFrame() never called
    → zero inference, zero callbacks
```

**Symptom:** Camera preview blank (not just trail — the camera itself shows black). Logcat: `No LifecycleOwner available. Call onLifecycleOwnerAvailable() first.`

### Failure Branch E — Channel Name Mismatch

```
creationParams["viewId"] = "<UUID>"
    → factory reads it as viewUniqueId = "<UUID>"
    → EventChannel: "com.ultralytics.yolo/detectionResults_<UUID>"
    |
    Dart _viewId = UniqueKey().toString() = "<UUID>"
    → _resultEventChannel = EventChannel("com.ultralytics.yolo/detectionResults_<UUID>")
```

This should always match since `_viewId` is passed in `creationParams`. If the Dart UUID and the native-extracted UUID differ, events go to an unclaimed channel. Check logcat for `"Using platform int viewId"` warning in `YOLOPlatformViewFactory` — that means the UUID was not received correctly.

---

## Build Order for Diagnostic and Fix Implementation

Dependencies flow one direction. Execute in this order:

```
Step 1: Verify model file presence on device
    Check: adb shell ls /data/app/.../assets/ for yolo11n.tflite
    Or deploy and observe logcat for "Failed to load model"
    Fix: Rebuild with model in android/app/src/main/assets/

Step 2: Enable logcat monitoring during app run
    Filter: adb logcat -s YOLOView ObjectDetector YOLOPlatformView CustomStreamHandler YOLOFileUtils
    Look for: camera start logs, model load logs, inference timing logs, sink null warnings

Step 3: Temporarily set showOverlays: true in YOLOView widget
    File: live_object_detection_screen.dart line ~175
    Purpose: Confirm native inference is running independently of Flutter callback chain
    Revert after: Confirmed working or confirmed not working

Step 4: If inference runs but onResult never fires
    Add diagnostic log in LiveObjectDetectionScreen.onResult callback
    Check logcat for Dart-side log
    If Dart log never appears → EventChannel sink/channel name issue

Step 5: If onResult fires but trail never draws
    Check: log results.map((r) => r.className).toList() in onResult
    If all classNames are COCO names → label loading failed → GPU or label extraction issue

Step 6: If trail draws but dots are offset
    Measure actual offset direction and magnitude on device
    Compare with YoloCoordUtils FILL_CENTER math
    Determine if camera AR is 4:3 or differs on A32
    Update YoloCoordUtils.cameraAR if needed

Step 7: Verify "Ball lost" badge behavior
    Once trail draws, test ball-out-of-frame scenario
    Badge should appear within 3 frames (~100ms at 30fps)
    A32 may run at lower FPS — badge latency will be proportionally longer
```

---

## Anti-Patterns

### Anti-Pattern 1: Patching Plugin Source in Pub Cache

**What people do:** Edit files in `~/.pub-cache/hosted/pub.dev/ultralytics_yolo-0.2.0/` to add logging or fix bugs.
**Why it's wrong:** Pub cache is shared across all Flutter projects on the machine. Changes affect every project using that package. They are also wiped on `flutter pub cache repair` or a fresh machine setup.
**Do this instead:** For non-invasive investigation, use `adb logcat` to read existing plugin logs. For a persistent fix, add a `dependency_overrides:` pointing to a local fork of the plugin (complex but safe for a POC).

### Anti-Pattern 2: Assuming iOS Camera AR = Android Camera AR Without Verification

**What people do:** Apply the confirmed iOS 4:3 AR constant to Android without verifying on device.
**Why it's wrong:** CameraX `RATIO_4_3` is a *hint*, not a guarantee. The Galaxy A32 camera hardware may not support 4:3 natively and CameraX may select the nearest supported resolution. The actual delivered frame dimensions must be read from `imageProxy.width` and `imageProxy.height` at runtime.
**Do this instead:** Log `imageProxy.width x imageProxy.height` from native side (already in logcat via existing `YOLOView` logs), or measure empirically by placing a known-geometry object in frame and observing dot offset direction.

### Anti-Pattern 3: Concluding "Plugin is Broken" Without Checking Model File

**What people do:** See zero trail/badge output, immediately assume the plugin's Android path has a code bug.
**Why it's wrong:** The most likely cause of zero inference output is a missing model file — `yolo11n.tflite` is gitignored and must be manually placed. The silent failure path is: `FileUtil.loadMappedFile()` throws → `predictor = null` → every `onFrame()` is a no-op → camera preview works fine → zero callbacks.
**Do this instead:** Check model file first (Step 1 in build order). Only escalate to code investigation if the model is present and logcat confirms model loaded successfully.

### Anti-Pattern 4: Using showOverlays: true as a Fix Rather Than a Diagnostic

**What people do:** See that native overlays appear with `showOverlays: true` and ship with it, assuming the custom trail will work the same way.
**Why it's wrong:** Native overlays are rendered by `OverlayView.onDraw()` using `result.xywh` (absolute pixel coordinates scaled to view size). The `TrailOverlay` CustomPainter uses `result.xywhn` (normalized) via `YoloCoordUtils` FILL_CENTER math. These coordinate systems are different. A box appearing correctly in the native overlay does not guarantee the trail dot appears in the same position — the FILL_CENTER correction may still need Android-specific tuning.
**Do this instead:** Use `showOverlays: true` only as a diagnostic to confirm inference is running. Revert to `showOverlays: false` and verify trail dot placement separately.

### Anti-Pattern 5: Hardcoding Platform.isIOS Camera AR Without Android Branch

**What people do:** Keep `YoloCoordUtils.cameraAR = 4/3` (verified for iOS) and assume it works on Android without empirical check.
**Why it's wrong:** While CameraX targets 4:3, the actual crop ratio applied by `PreviewView.ScaleType.FILL_CENTER` depends on the preview view's screen dimensions in landscape mode. On iPhone 12 the screen is 2532×1170 (landscape: 2532×1170 → 19.3:9); on Galaxy A32 the screen is 2400×1080 (landscape: 2400×1080 → 20:9). Different screen ARs produce different amounts of vertical cropping even with the same camera AR.
**Do this instead:** After confirming inference runs on A32, measure trail dot placement accuracy empirically. If dots are offset in Y, adjust the `cameraAR` parameter in `YoloCoordUtils` for Android. Consider `Platform.isAndroid ? measuredAndroidAR : 4/3` branching.

---

## Integration Points

### Files to Modify for Diagnostics

| File | Location | Change | Impact |
|------|----------|--------|--------|
| `live_object_detection_screen.dart` | `onResult` callback, line ~176 | Add `log('onResult: ${results.length}')` | Confirms callback fires |
| `live_object_detection_screen.dart` | `YOLOView` widget params | `showOverlays: true` (temp) | Confirms native inference |
| `live_object_detection_screen.dart` | `YOLOView` widget params | `useGpu: false` (temp if GPU issue) | Isolates GPU delegate failure |

### Files to Modify for Permanent Fixes

| File | Location | Change | Impact |
|------|----------|--------|--------|
| `lib/utils/yolo_coord_utils.dart` | `cameraAR` constant | Platform-conditional value after empirical measurement | Corrects trail dot Y-offset if present |
| `android/app/src/main/assets/` | Binary file | Ensure `yolo11n.tflite` is present before each device deploy | Enables inference |

### Files Explicitly Not Modified

| File | Reason |
|------|--------|
| `lib/config/detector_config.dart` | Backend switching — changes affect both pipelines |
| `pubspec.yaml` `ultralytics_yolo` version | Pinned at `^0.2.0`; bumping risks breaking iOS path |
| Orientation lock in `live_object_detection_screen.dart` | Matched `initState`/`dispose` pair — removing one leg locks the app |
| Plugin source in `~/.pub-cache/` | Shared cache; changes are not safe |

---

## Scaling Considerations

This is a single-device POC. The relevant performance ceiling is frame rate on Galaxy A32.

| Concern | Galaxy A32 (A32 4G — Helio G80, Mali-G52 GPU) |
|---------|-----------------------------------------------|
| Inference FPS | CPU-only: ~5-10 FPS. GPU (Mali-G52): ~15-20 FPS. Both are below iPhone 12's 30fps. |
| Trail history entries | ~7-10 entries at 5fps in 1.5s window vs 45 at 30fps |
| `ballLostThreshold = 3 frames` | At 5fps this is ~600ms latency before badge appears — feels slow. May need lowering. |
| GPU delegate availability | Mali-G52 has limited TFLite GPU delegate support. GPU may be unavailable or crash. Set `useGpu: false` as first diagnostic. |

---

## Sources

- `ultralytics_yolo` plugin Android source read directly from pub cache: `/Users/shashank/.pub-cache/hosted/pub.dev/ultralytics_yolo-0.2.0/example/android/ultralytics_yolo_plugin/src/main/kotlin/com/ultralytics/yolo/`
  - `YOLOView.kt` — camera setup, `onFrame()`, `setStreamConfig()`, `setStreamCallback()`
  - `YOLOPlatformView.kt` — Flutter PlatformView bridge, stream delivery retry logic
  - `YOLOPlatformViewFactory.kt` — view factory, `CustomStreamHandler`, EventChannel setup
  - `ObjectDetector.kt` — TFLite inference, `ImageProcessor` variants, JNI postprocessing
  - `YOLOFileUtils.kt` — label loading from appended ZIP metadata
  - `Utils.kt` — model loading from assets or filesystem
  - `YOLOPlugin.kt` — Flutter plugin entry, permission handling, activity lifecycle
  - `YOLOResult.kt` — `Box.xywhn` normalized coordinates confirmed
- Dart plugin source: `/Users/shashank/.pub-cache/hosted/pub.dev/ultralytics_yolo-0.2.0/lib/`
  - `yolo_view.dart` — `_YOLOViewState`, channel setup, `_handleEvent()`, `_parseDetectionResults()`
  - `config/channel_config.dart` — channel naming constants
  - `widgets/yolo_controller.dart` — `YOLOViewController`
- App source read directly: `lib/screens/live_object_detection/live_object_detection_screen.dart`
- `memory-bank/activeContext.md`, `memory-bank/progress.md`, `.planning/PROJECT.md`

---

*Architecture research for: Android YOLO verification — data flow, failure points, diagnostic integration*
*Researched: 2026-02-25*
