---
phase: 06-overlay-foundation
plan: 01
subsystem: ui
tags: [flutter, yolo, tflite, custom-painter, overlay, debug]

# Dependency graph
requires:
  - phase: 05 (or prior baseline)
    provides: live_object_detection_screen.dart with YOLO and SSD pipelines

provides:
  - DebugDotPainter CustomPainter class shared by both YOLO and SSD pipelines
  - _debugDotPosition state field (normalized Offset?) in live detection screen
  - _pickBestBallYolo and _pickBestBallSsd helpers for coordinate extraction
  - showOverlays: false on YOLOView suppressing native bounding boxes
  - mounted guard on YOLO onResult callback preventing setState-after-dispose

affects:
  - 06-02 (on-device verification plan — tests the dot visually on real hardware)
  - 07-trail-accumulation (uses _debugDotPosition as input for ball trail history)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - RepaintBoundary wrapping CustomPaint for efficient overlay repaints
    - Normalized Offset (0.0-1.0) as the canonical coordinate format between pipelines
    - Zero-size guard on ScreenParams.screenPreviewSize before normalization

key-files:
  created:
    - lib/screens/live_object_detection/widgets/debug_dot_overlay.dart
  modified:
    - lib/screens/live_object_detection/live_object_detection_screen.dart

key-decisions:
  - "DebugDotPainter is public (not file-private) since it lives in a separate file from the screen"
  - "RepaintBoundary wraps CustomPaint — not the other way around — for correct repaint isolation"
  - "showOverlays: false disables both native platform bounding boxes AND the internal Flutter YOLOOverlay widget"
  - "SSD _debugDotPosition update is placed inside the existing mounted-guarded setState to avoid a second rebuild"
  - "_debugDotPosition is shared between YOLO and SSD — only one pipeline runs at a time so there is no conflict"

patterns-established:
  - "RepaintBoundary > CustomPaint(size: Size.infinite) > DebugDotPainter pattern for camera overlay layers"
  - "Normalized Offset? (null = no detection) as the standard coordinate type flowing from detection callbacks into overlay painters"

requirements-completed: [OVLY-01, OVLY-02, OVLY-03, OVLY-04]

# Metrics
duration: 3min
completed: 2026-02-23
---

# Phase 6 Plan 01: Overlay Foundation — Debug Dot Summary

**DebugDotPainter CustomPainter with normalized-coordinate extraction from both YOLO (normalizedBox.center) and SSD (renderLocation.center / screenPreviewSize) pipelines, with native YOLO overlay suppression via showOverlays: false**

## Performance

- **Duration:** ~3 min
- **Started:** 2026-02-23T17:06:09Z
- **Completed:** 2026-02-23T17:08:24Z
- **Tasks:** 2 (both implemented atomically in same file; committed together)
- **Files modified:** 2

## Accomplishments

- Created `DebugDotPainter` CustomPainter in `debug_dot_overlay.dart` — renders a filled red circle (radius 8, alpha 0.9) with a white stroke outline at a normalized Offset position, drawing nothing when null
- Integrated YOLO path: `showOverlays: false` suppresses native bounding boxes (OVLY-03), `if (!mounted) return` guard in `onResult` (OVLY-04), `normalizedBox.center` extracted into `_debugDotPosition` (OVLY-01), `RepaintBoundary > CustomPaint > DebugDotPainter` in YOLO Stack
- Integrated SSD path: `_pickBestBallSsd` helper with zero-size guard, `_debugDotPosition` updated inside the existing `if (mounted) setState` block (OVLY-02), same `RepaintBoundary > CustomPaint > DebugDotPainter` pattern in SSD Stack
- Added diagnostic coordinate text overlay (`dot: (x, y)`) in both Stacks to aid on-device verification
- Full project `flutter analyze` passes with no issues

## Task Commits

Both tasks were implemented in the same atomic commit (both require modifying `live_object_detection_screen.dart` — impossible to stage separately):

1. **Task 1: Create DebugDotPainter and integrate YOLO path debug dot** - `1a2dfca` (feat)
2. **Task 2: Integrate SSD path debug dot with coordinate normalization** - `1a2dfca` (feat — same commit)

## Files Created/Modified

- `lib/screens/live_object_detection/widgets/debug_dot_overlay.dart` — New DebugDotPainter CustomPainter class used by both YOLO and SSD detection pipelines
- `lib/screens/live_object_detection/live_object_detection_screen.dart` — Added _debugDotPosition state field, _pickBestBallYolo and _pickBestBallSsd helpers, showOverlays: false on YOLOView, mounted guard in onResult, RepaintBoundary > CustomPaint layers in both YOLO and SSD Stacks, diagnostic coordinate text widgets

## Decisions Made

- `DebugDotPainter` is public (not `_DebugDotPainter`) because it lives in a separate file — file-private prefix would not actually restrict access and makes the API confusing
- `RepaintBoundary` wraps `CustomPaint` (not inside it) as required for correct repaint isolation — the `RepaintBoundary` creates a separate compositing layer so only the dot redraws on each detection frame
- `showOverlays: false` on `YOLOView` disables both the native platform-rendered bounding boxes AND the internal Flutter `YOLOOverlay` widget — confirmed by reviewing yolo_view.dart source
- SSD `_debugDotPosition` update placed inside the pre-existing `if (mounted) setState(...)` block rather than a second `setState` call, preventing a double rebuild per detection frame
- `_debugDotPosition` is a single shared field used by both pipelines — no conflict because only one backend runs at a time based on `DetectorConfig.backend`

## Deviations from Plan

None — plan executed exactly as written. The diagnostic coordinate text widget (marked "Claude's discretion" in the plan) was added to both Stacks as it aids on-device testing.

## Issues Encountered

None. The `showOverlays` parameter exists in `ultralytics_yolo ^0.2.0` (confirmed by reading the package source at `~/.pub-cache/hosted/pub.dev/ultralytics_yolo-0.2.0/lib/yolo_view.dart`). The STATE.md blocker concern was pre-emptive — no recovery path was needed.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Both detection pipelines now have a debug dot overlay ready for on-device verification
- Plan 06-02 can proceed immediately: load the app on iPhone 12 and Galaxy A32, point at a ball, verify the red dot tracks it accurately
- Phase 7 (trail accumulation) can use `_debugDotPosition` directly as the input for ball position history

---
*Phase: 06-overlay-foundation*
*Completed: 2026-02-23*
