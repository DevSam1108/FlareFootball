---
phase: 09-android-inference-diagnosis-and-fix
plan: 02
subsystem: android-ml
tags: [android, tflite, yolo, device-verification, galaxy-a32]

# Dependency graph
requires:
  - phase: 09-01
    provides: aaptOptions fix and DIAG log calls
provides:
  - Confirmed onResult firing on Galaxy A32 with correct class names
  - Root cause documented with visual and log evidence
  - Phase 10 unblocked
affects:
  - 10-android-feature-parity-verification

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "aaptOptions fix confirmed sufficient to restore Android YOLO inference pipeline"
    - "MethodChannel coordinate correction (rotation=3 flip) visually confirmed working in both landscape orientations"

key-files:
  created:
    - .planning/phases/09-android-inference-diagnosis-and-fix/09-FINDINGS.md
    - result/android/Android Landscape left.MOV
    - result/android/Android Landscape right.MOV
    - result/android/frames_left/ (18 extracted frames)
    - result/android/frames_right/ (21 extracted frames)
  modified: []

key-decisions:
  - "Phase 9 PASS — all four DIAG requirements confirmed with evidence"
  - "tennis-ball priority 2 acceptance was not needed — Soccer ball class detected at 0.868 confidence"
  - "4:3 camera AR assumption appears correct on Android based on visual trail accuracy (precise measurement deferred to Phase 10)"

requirements-completed: [DIAG-01, DIAG-02, DIAG-03, DIAG-04]

# Metrics
duration: device-run + analysis
completed: 2026-02-25
---

# Phase 9 Plan 02: Galaxy A32 Device Run and Findings Documentation

**Physical device verification of onResult fix and documentation of root cause with log and visual evidence**

## Performance

- **Duration:** Device run by developer + frame analysis by Claude
- **Started:** 2026-02-25
- **Completed:** 2026-02-25
- **Evidence captured:** 2 screen recordings (landscape-left + landscape-right), 39 extracted frames, Flutter debug console log

## Accomplishments

- Developer ran `flutter run --dart-define=DETECTOR_BACKEND=yolo` on Galaxy A32
- **DIAG-02 CONFIRMED:** `[DIAG-02] onResult fired — 1 detections` appeared in Flutter debug console
- **DIAG-03 CONFIRMED:** `[DIAG-03] className=Soccer ball, conf=0.868, box=(0.422, 0.672, 0.471, 0.740)` — custom model labels loading correctly, NOT COCO fallback
- **Visual evidence captured:** Screen recordings show trail dots, connecting lines, and "Ball lost" badge all functioning in both landscape orientations
- **09-FINDINGS.md written** with complete root cause analysis, evidence, and open question resolution
- **Phase 10 unblocked** — Android YOLO pipeline confirmed working

## Key Evidence

### Log output:
```
I/flutter (  835): [DIAG-02] onResult fired — 1 detections
I/flutter (  835): [DIAG-03] className=Soccer ball, conf=0.868, box=(0.422, 0.672, 0.471, 0.740)
```

### Visual evidence (39 frames analyzed):
- **Landscape LEFT:** Trail dots + connecting lines visible near ball (frame 12). "Ball lost" badge transitions correctly.
- **Landscape RIGHT:** Trail dots + connecting lines visible near ball (frames 12, 15). Coordinate correction (rotation=3 flip) confirmed working. "Ball lost" badge transitions correctly.

## Root Cause Summary

Missing `aaptOptions { noCompress 'tflite' }` caused Android's AAPT to compress the model during APK packaging. TFLite's `FileUtil.loadMappedFile()` failed silently on the compressed file, leaving the interpreter null. All downstream detection was silently disabled.

Fix: Single line in `build.gradle` inside the `android {}` closure. Applied in Plan 01 (commit `9b3ccb7`).

## Files Created

- `.planning/phases/09-android-inference-diagnosis-and-fix/09-FINDINGS.md` — Complete Phase 9 findings document
- `result/android/Android Landscape left.MOV` — Screen recording, landscape-left orientation
- `result/android/Android Landscape right.MOV` — Screen recording, landscape-right orientation
- `result/android/frames_left/` — 18 extracted frames at 2fps
- `result/android/frames_right/` — 21 extracted frames at 2fps

## Phase 9 Overall Result

**PASS** — All four DIAG requirements confirmed with evidence.

## Handoff to Phase 10

Phase 10 (Android Feature Parity Verification) is now unblocked. Visual evidence from this device run already provides strong preview:
- PRTY-01 (trail accuracy): Trail dots appear correctly positioned in both orientations
- PRTY-02 (badge behavior): "Ball lost" badge appears/disappears with correct state transitions
- PRTY-03 (camera AR): 4:3 assumption appears correct but needs precise measurement
- PRTY-04 (FPS): Not measured yet — count DIAG-02 lines per second from a longer log capture

## Self-Check: PASSED

- FOUND: 09-FINDINGS.md with all four DIAG sections populated
- FOUND: Root cause mechanism description in DIAG-04
- FOUND: Phase 9 Overall Result = PASS
- FOUND: Visual evidence in result/android/ (2 recordings, 39 frames)
- FOUND: Log evidence confirming DIAG-02 and DIAG-03

---
*Phase: 09-android-inference-diagnosis-and-fix*
*Completed: 2026-02-25*
