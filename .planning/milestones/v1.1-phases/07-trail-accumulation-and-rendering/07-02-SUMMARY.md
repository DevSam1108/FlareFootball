---
phase: 07-trail-accumulation-and-rendering
plan: 02
subsystem: rendering
tags: [dart, flutter, custom-painter, trail-overlay, ball-tracking, fill-center, yolo]

# Dependency graph
requires:
  - phase: 07-01
    provides: TrackedPosition, YoloCoordUtils.toCanvasPixel, BallTracker
  - phase: 06-overlay-foundation
    provides: DebugDotPainter with verified FILL_CENTER crop math on iPhone 12
provides:
  - TrailOverlay CustomPainter with fading dots, connecting lines, gap skipping, FILL_CENTER correction
  - YOLO screen wired with BallTracker (_tracker), upgraded _pickBestBallYolo (class priority + nearest-neighbor tiebreaker), TrailOverlay replacing DebugDotPainter on YOLO path
affects:
  - Phase 8 (evaluation — trail is now the primary visual output for assessment)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "TrailOverlay always returns shouldRepaint=true; performance isolation delegated to RepaintBoundary wrapper"
    - "RepaintBoundary > IgnorePointer > CustomPaint > TrailOverlay stack ensures touch pass-through and repaint isolation"
    - "Age-based opacity: (1.0 - elapsed/windowMs).clamp(0, 1); dot radius tapers: 5.0*opacity+2.0 (7px newest, 2px oldest)"
    - "Class priority map {'Soccer ball': 0, 'ball': 1} — tennis-ball excluded entirely from YOLO detection path"
    - "Nearest-neighbor tiebreaker via _squaredDist + _tracker.lastKnownPosition for multi-detection frames (TRAK-04)"

key-files:
  created:
    - lib/screens/live_object_detection/widgets/trail_overlay.dart
  modified:
    - lib/screens/live_object_detection/live_object_detection_screen.dart

key-decisions:
  - "Remove tracked_position.dart import from screen: TrackedPosition is consumed entirely inside BallTracker; direct import in screen would be unused and cause flutter analyze warning"
  - "shouldRepaint always returns true: BallTracker.trail returns List.unmodifiable() creating a new wrapper each call, making reference equality unreliable; RepaintBoundary is the real performance guard"
  - "IgnorePointer added around trail CustomPaint: prevents overlay from intercepting touch events intended for YOLOView camera layer"

patterns-established:
  - "Trail painter delegates ALL coordinate math to YoloCoordUtils.toCanvasPixel — no inline crop logic"
  - "Occlusion sentinel check in line loop: if (prev.isOccluded || curr.isOccluded) continue — either endpoint breaks the polyline"

requirements-completed: [TRAK-03, TRAK-04, RNDR-01, RNDR-02, RNDR-03, RNDR-04, RNDR-05]

# Metrics
duration: 3min
completed: 2026-02-23
---

# Phase 7 Plan 02: Trail Accumulation and Rendering — Trail Painter and Screen Integration Summary

**TrailOverlay CustomPainter with fading orange dots and connecting lines; YOLO screen upgraded with class-priority ball selection, nearest-neighbor tiebreaker, and BallTracker replacing _debugDotPosition**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-23T18:40:50Z
- **Completed:** 2026-02-23T18:43:25Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- `TrailOverlay` CustomPainter: fading orange dot trail with age-based opacity + radius, connecting line segments (strokeWidth 2.5, StrokeCap.round), occlusion sentinel gap skipping, FILL_CENTER crop correction via shared `YoloCoordUtils.toCanvasPixel` (RNDR-01 through RNDR-05)
- `_pickBestBallYolo` upgraded: class priority map `{'Soccer ball': 0, 'ball': 1}` rejects tennis-ball (TRAK-03); `_squaredDist` nearest-neighbor tiebreaker uses `_tracker.lastKnownPosition` when multiple same-priority detections arrive (TRAK-04)
- YOLO screen integration: `BallTracker _tracker` field added; `onResult` calls `_tracker.update/markOccluded`; stack uses `RepaintBoundary > IgnorePointer > CustomPaint > TrailOverlay`; `_tracker.reset()` called first in `dispose()`
- Diagnostic coordinate text `Positioned` block and `log('YOLO results:')` removed from YOLO path — trail overlay is the sole visual output
- SSD path completely untouched: `DebugDotPainter`, `_debugDotPosition`, and `_pickBestBallSsd` unchanged

## Task Commits

Each task was committed atomically:

1. **Task 1: Create TrailOverlay CustomPainter with fading dots and connecting lines** - `de68901` (feat)
2. **Task 2: Wire BallTracker and TrailOverlay into YOLO screen, upgrade _pickBestBallYolo, remove DebugDotPainter** - `b1266cc` (feat)

**Plan metadata:** (docs commit follows)

## Files Created/Modified

- `lib/screens/live_object_detection/widgets/trail_overlay.dart` — TrailOverlay CustomPainter: age-based fading dots + connecting lines, occlusion gap skipping, FILL_CENTER crop correction via YoloCoordUtils; shouldRepaint always true
- `lib/screens/live_object_detection/live_object_detection_screen.dart` — BallTracker field added; _pickBestBallYolo upgraded with class priority + nearest-neighbor tiebreaker; TrailOverlay replaces DebugDotPainter in YOLO Stack; SSD path frozen

## Decisions Made

- `TrackedPosition` import removed from screen file: the type is consumed entirely inside `BallTracker` and `TrailOverlay` — no direct usage in the screen itself. Keeping it would cause an `unused_import` warning that fails `flutter analyze`.
- `shouldRepaint` returns `true` unconditionally in `TrailOverlay`: `BallTracker.trail` returns `List.unmodifiable()` which wraps the underlying `ListQueue` in a new object on each call, making reference equality (`old.trail != trail`) unreliable as a paint guard. `RepaintBoundary` provides the actual isolation; `setState` only fires at detection frame rate, not every vsync tick.
- `IgnorePointer` added wrapping the trail `CustomPaint`: prevents the overlay layer from consuming touch/gesture events that should pass through to the `YOLOView` camera widget beneath it.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Warning] Removed unused `tracked_position.dart` import from screen**
- **Found during:** Task 2 verification (`flutter analyze`)
- **Issue:** Plan 02 Task 2 instructions said to add `import 'package:tensorflow_demo/models/tracked_position.dart'` to the screen, but `TrackedPosition` is never directly referenced in `live_object_detection_screen.dart` — it is consumed inside `BallTracker` and `TrailOverlay` only.
- **Fix:** Import was added per plan instructions then removed after `flutter analyze` reported `unused_import` warning. The three imports actually needed (`tracked_position.dart` was NOT one of them) are: `trail_overlay.dart` and `ball_tracker.dart`.
- **Files modified:** `lib/screens/live_object_detection/live_object_detection_screen.dart`
- **Commit:** `b1266cc` (combined with other Task 2 changes)

## Issues Encountered

None beyond the auto-fixed unused import deviation above.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Phase 7 is complete: data layer (Plan 01) + rendering layer (Plan 02) both done
- Phase 8 (evaluation) can proceed: run `flutter run --dart-define=DETECTOR_BACKEND=yolo` on iPhone 12 to observe the fading orange dot trail in action
- No blocking concerns for Phase 8

---
*Phase: 07-trail-accumulation-and-rendering*
*Completed: 2026-02-23*
