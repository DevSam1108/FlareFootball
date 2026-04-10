# Phase 9 Findings: Android Inference Diagnosis

**Date:** 2026-02-25
**Device:** Samsung Galaxy A32 4G (SM-A325F, Android 12, API 31, Helio G80 / Mali-G52)
**Plugin:** ultralytics_yolo ^0.2.0
**Test content:** David Beckham free kick video displayed on a second screen, filmed by Galaxy A32 camera

## DIAG-01: Pre-flight Checks

| Check | Expected | Result |
|-------|----------|--------|
| `aaptOptions { noCompress 'tflite' }` in build.gradle | Present inside `android {}` closure | PASS (line 31, commit `9b3ccb7`) |
| Plugin version | `^0.2.0` | PASS (confirmed in pubspec.yaml) |
| Model file `yolo11n.tflite` in assets/ | Present | PASS (confirmed present on device) |

**Result:** PASS

## DIAG-02: onResult Callback Firing

**Evidence:**
```
I/flutter (  835): [DIAG-02] onResult fired — 1 detections
```

The `[DIAG-02]` log line appeared in the Flutter debug console during a live Galaxy A32 run with a soccer ball visible in frame. Detection count = 1, confirming the YOLO inference pipeline is delivering results through the EventChannel to the Flutter layer.

**Result:** PASS

## DIAG-03: Correct Class Names

**Evidence:**
```
I/flutter (  835): [DIAG-03] className=Soccer ball, conf=0.868, box=(0.422, 0.672, 0.471, 0.740)
```

**className values seen:** `Soccer ball` (confidence 0.868)

The className `Soccer ball` matches the custom YOLO11n model's embedded labels, confirming the model file loaded correctly (not a COCO-80 fallback which would show `sports ball`). The confidence of 0.868 is comparable to iOS inference quality.

**Bounding box analysis:** The normalized box `(0.422, 0.672, 0.471, 0.740)` represents a small region (width ~5%, height ~7% of frame), consistent with a soccer ball at moderate distance from the camera.

**Result:** PASS

## DIAG-04: Root Cause Identified and Fixed

**Root cause:** Missing `aaptOptions { noCompress 'tflite' }` in `android/app/build.gradle`.

**Mechanism:** Android's AAPT (Android Asset Packaging Tool) compresses all assets by default during APK packaging. A compressed `.tflite` file cannot be memory-mapped by TFLite's `FileUtil.loadMappedFile()`. The interpreter constructor throws an exception that `ultralytics_yolo` catches silently from Flutter's perspective (visible in logcat under `ObjectDetector` tag). With a null interpreter, `ObjectDetector.predict()` returns empty results. The `predictor?.let` guard in `YOLOView.onFrame()` short-circuits. The `streamCallback` is never invoked. The EventChannel delivers no data. `onResult` never fires.

**Fix applied:** Added `aaptOptions { noCompress 'tflite' }` inside the `android {}` block in `android/app/build.gradle` (Plan 01, Task 1, commit `9b3ccb7`).

**Evidence fix worked:** `[DIAG-02] onResult fired — 1 detections` appeared in the debug console. Additionally, screen recordings from both landscape-left and landscape-right orientations show:
- Orange trail dots rendering on screen adjacent to the detected ball
- Connecting lines between consecutive trail positions
- "Ball lost" badge appearing when ball exits frame and disappearing on re-detection

**Result:** PASS

## Visual Evidence from Screen Recordings

Two screen recordings were captured during the Galaxy A32 device run:
- `result/android/Android Landscape left.MOV` (18 frames extracted at 2fps, ~9 seconds)
- `result/android/Android Landscape right.MOV` (21 frames extracted at 2fps, ~10.5 seconds)

### Landscape LEFT observations:
- **Frames 1-5:** "Ball lost" badge visible (red, top-right), YOLO badge visible (top-left). No trail dots — ball not yet detected. Correct behavior.
- **Frame 8:** Single orange trail dot visible. No "Ball lost" badge — detection is active.
- **Frame 10:** Orange dot near the ball on the grass. Ball is clearly being kicked by player.
- **Frame 12:** Clear orange trail with multiple dots AND connecting lines, positioned right next to the soccer ball as it moves across the pitch. Excellent coordinate accuracy.
- **Frames 15-18:** "Ball lost" badge returns. Trail fades as expected (1.5s time window). Correct state transition behavior.

### Landscape RIGHT observations:
- **Frame 1:** "Ball lost" badge visible — correct initial state.
- **Frame 10:** Single orange trail dot visible. The coordinate correction (rotation=3, `1-x, 1-y` flip) appears to be working — dot is in a reasonable position relative to the ball.
- **Frame 12:** Orange dots with connecting lines visible adjacent to the soccer ball. Coordinate correction confirmed working for landscape-right.
- **Frame 15:** Multiple trail dots with connecting lines tracking ball movement path. Clear visual trail following the ball trajectory.
- **Frames 18-21:** "Ball lost" badge returns when ball exits frame. Correct behavior.

### Coordinate accuracy assessment:
Trail dots appear to be positioned near the actual ball location in both orientations. No systematic X or Y offset was observed at this level of inspection. The 4:3 camera aspect ratio assumption and FILL_CENTER crop correction appear to be working acceptably on Android. A more precise measurement (Phase 10 PRTY-01/PRTY-03) would require frame-by-frame pixel analysis, but initial visual evidence is positive.

## Open Questions Resolution

From 9-RESEARCH.md open questions:

1. **Does the custom yolo11n.tflite have appended ZIP metadata?**
   YES — confirmed. `className=Soccer ball` appeared in DIAG-03, which means the TFLite model file contains the custom label metadata. COCO fallback would show `sports ball`. The custom training embedded the class names correctly.

2. **Is configurations.all { exclude } causing runtime failures?**
   NO — this was not the issue. The aaptOptions fix alone resolved the problem. The `configurations.all` block in build.gradle is unrelated to the TFLite loading failure.

3. **Does the Galaxy A32 Helio G80 support GPU delegate?**
   Not directly observed in this test (logcat was not running with GPU delegate tag filter). However, inference IS running successfully, meaning either the GPU delegate works on Mali-G52 or the plugin fell back to CPU delegate automatically. FPS measurement in Phase 10 (PRTY-04) will provide indirect evidence of which delegate is active.

## Phase 9 Overall Result

**Status:** PASS

All four DIAG requirements confirmed:
- DIAG-01: Pre-flight checks pass
- DIAG-02: onResult fires with detection data
- DIAG-03: Custom model class names confirmed (`Soccer ball`, conf 0.868)
- DIAG-04: Root cause (compressed TFLite asset) identified, fixed, and verified

**Handoff to Phase 10:** The Android YOLO pipeline is confirmed working. Phase 10 should verify:
- PRTY-01: Trail coordinate accuracy (precise pixel-level analysis)
- PRTY-02: Badge state transitions (systematic test: ball in/out repeatedly)
- PRTY-03: Camera aspect ratio (log actual Android camera resolution to confirm 4:3)
- PRTY-04: FPS measurement (count DIAG-02 lines per second from log output)

**Bonus findings for Phase 10:** Visual evidence from the screen recordings already shows trail dots, connecting lines, and "Ball lost" badge all functioning in both landscape orientations. This is a strong preview of Phase 10 PRTY-01 and PRTY-02 passing. The coordinate correction via MethodChannel (rotation=3 flip) appears to be working correctly for landscape-right.

---
*Phase: 09-android-inference-diagnosis-and-fix*
*Completed: 2026-02-25*
