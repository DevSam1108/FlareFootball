---
phase: 09-android-inference-diagnosis-and-fix
plan: 01
subsystem: android-ml
tags: [android, gradle, tflite, yolo, ultralytics_yolo, diagnostics, flutter]

# Dependency graph
requires:
  - phase: 08-polish
    provides: ball tracking and trail overlay on iOS confirmed working
provides:
  - aaptOptions noCompress block preventing TFLite asset compression on Android
  - DIAG-02/DIAG-03 log calls in YOLO onResult for Android debug console visibility
affects:
  - 09-02-PLAN (physical Galaxy A32 device run to confirm onResult fires)
  - 10-android-camera-ar-verification

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "aaptOptions { noCompress 'tflite' } inside android {} closure in build.gradle prevents AAPT from GZip-compressing TFLite assets, enabling FileUtil.loadMappedFile() to succeed"
    - "dart:developer log() with tagged prefixes [DIAG-XX] for unambiguous VS Code debug console tracing"

key-files:
  created: []
  modified:
    - android/app/build.gradle
    - lib/screens/live_object_detection/live_object_detection_screen.dart

key-decisions:
  - "aaptOptions block placed inside android {} closure (not at top level) — Gradle scoping requirement"
  - "DIAG log calls placed before if (!mounted) guard so they fire even when widget is unmounting"
  - "DIAG-03 logs all raw detections before _pickBestBallYolo filter so className values from the model can be confirmed (Soccer ball / ball vs COCO sports ball)"

patterns-established:
  - "Diagnostic tags follow [DIAG-0N] convention for grep-ability across logcat and VS Code debug console"

requirements-completed: [DIAG-01, DIAG-02, DIAG-03, DIAG-04]

# Metrics
duration: 2min
completed: 2026-02-25
---

# Phase 9 Plan 01: Android Inference Diagnosis and Fix Summary

**aaptOptions noCompress fix for compressed TFLite asset and DIAG-02/DIAG-03 dart:developer log calls inside YOLO onResult for Android callback pipeline visibility**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-02-25T17:38:18Z
- **Completed:** 2026-02-25T17:40:07Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Added `aaptOptions { noCompress 'tflite' }` to `android/app/build.gradle` — root-cause fix preventing AAPT from compressing the TFLite asset, which caused `FileUtil.loadMappedFile()` to throw silently, leaving `predictor` null and `onResult` permanently silent on Android
- Added `[DIAG-02]` log line confirming `onResult` fires and logging the detection count per frame
- Added `[DIAG-03]` per-detection loop logging `className`, `confidence`, and normalized bounding box coordinates before the `_pickBestBallYolo` filter — makes it observable in the VS Code debug console whether the custom model classes (`Soccer ball`, `ball`) or COCO fallback strings arrive
- `flutter clean && flutter pub get` verified exit 0, Gradle syntax valid
- `flutter analyze` on modified screen file reports `No issues found!`

## Task Commits

Each task was committed atomically:

1. **Task 1: Add aaptOptions noCompress block to android/app/build.gradle** - `9b3ccb7` (chore)
2. **Task 2: Add diagnostic log() calls inside the YOLO onResult callback** - `61380bf` (feat)

**Plan metadata:** (docs commit below)

## Files Created/Modified

- `android/app/build.gradle` — Added `aaptOptions { noCompress 'tflite' }` block inside the `android {}` closure, immediately after `ndkVersion flutter.ndkVersion` and before `configurations.all`
- `lib/screens/live_object_detection/live_object_detection_screen.dart` — Added DIAG-02 and DIAG-03 `log()` calls at the top of the `onResult` callback body, before the existing `if (!mounted) return` guard and `_pickBestBallYolo` call

## Root Cause Documented

**Problem:** Android's AAPT asset packager compresses all files by default, including `.tflite` assets. TensorFlow Lite's `FileUtil.loadMappedFile()` requires uncompressed assets to memory-map them directly. When the file is compressed, the function throws an exception that `ultralytics_yolo` catches silently — `predictor` remains null, and `onResult` is never invoked. This means zero detection data reaches the Flutter layer regardless of model correctness.

**Fix:** `aaptOptions { noCompress 'tflite' }` inside the `android {}` Gradle closure instructs AAPT to store `.tflite` files without compression. The file is then accessible via `loadMappedFile()`, the interpreter initializes successfully, and `onResult` should begin firing.

**Verification state:** The fix is applied and the build is clean. Confirmation that `onResult` now fires requires a physical Galaxy A32 device run (Plan 02 — DIAG-02 and DIAG-03 will be visible in the VS Code debug console).

## Grep Output — aaptOptions Presence

```
31:        noCompress 'tflite'
```
File: `android/app/build.gradle` — inside `android {}` block at line 31.

## flutter analyze Result

```
Analyzing live_object_detection_screen.dart...
No issues found! (ran in 1.4s)
```

## Decisions Made

- `aaptOptions` block positioned inside the `android {}` closure (after `ndkVersion`, before `configurations.all`) — Gradle requires this scoping; a top-level `aaptOptions` block would fail
- DIAG log calls placed before `if (!mounted) return` so they fire even when the widget is unmounting — ensures we get evidence of the callback arriving regardless of widget state
- DIAG-03 logs raw detections before the `_pickBestBallYolo` priority filter so `className` values from the custom model can be confirmed directly (`Soccer ball`, `ball`, `tennis-ball` vs COCO's `sports ball`)
- No changes to `_pickBestBallYolo`, `setState`, `_tracker.update`, `_tracker.markOccluded`, or any other existing logic

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None — no external service configuration required. The next step is running on a physical Galaxy A32 (Plan 02).

## Next Phase Readiness

- `android/app/build.gradle` has `aaptOptions { noCompress 'tflite' }` — build is ready for physical device deployment
- `onResult` callback emits `[DIAG-02]` and `[DIAG-03]` log lines — VS Code debug console will show callback arrival and className values without needing logcat
- Plan 02 can proceed: `flutter run --dart-define=DETECTOR_BACKEND=yolo` on Galaxy A32, observe debug console for DIAG-02 lines
- If DIAG-02 lines appear, `onResult` is firing — Phase 9 blocker is resolved
- If DIAG-02 lines do not appear, further investigation (plugin version, model file presence, logcat) is needed per the 7-step callback chain in 9-RESEARCH.md

## Self-Check: PASSED

- FOUND: android/app/build.gradle (noCompress line at L31)
- FOUND: live_object_detection_screen.dart (DIAG-02 at L178, DIAG-03 at L181)
- FOUND: 09-01-SUMMARY.md
- FOUND: commit 9b3ccb7 (chore - aaptOptions)
- FOUND: commit 61380bf (feat - DIAG log calls)

---
*Phase: 09-android-inference-diagnosis-and-fix*
*Completed: 2026-02-25*
