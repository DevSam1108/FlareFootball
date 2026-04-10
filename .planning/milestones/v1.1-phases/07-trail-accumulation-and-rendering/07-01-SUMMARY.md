---
phase: 07-trail-accumulation-and-rendering
plan: 01
subsystem: tracking
tags: [dart, ball-tracking, trail, coordinate-mapping, fill-center, listqueue]

# Dependency graph
requires:
  - phase: 06-overlay-foundation
    provides: DebugDotPainter with verified FILL_CENTER crop math on iPhone 12
provides:
  - TrackedPosition immutable value type for trail history entries
  - YoloCoordUtils.toCanvasPixel shared FILL_CENTER coordinate utility
  - BallTracker service with time-windowed ListQueue, occlusion sentinels, and auto-reset
affects:
  - 07-02 (trail painter and screen integration — consumes all three artifacts)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Pure-Dart data/service layer: TrackedPosition and BallTracker have no Flutter widget imports — unit-testable in isolation"
    - "ListQueue for O(1) bounded queue: removeFirst/addLast without list shifting"
    - "Occlusion sentinel pattern: single isOccluded=true TrackedPosition marks a detection gap without stacking"
    - "Anti-stacking guard: markOccluded checks _history.last.isOccluded before inserting sentinel"

key-files:
  created:
    - lib/models/tracked_position.dart
    - lib/utils/yolo_coord_utils.dart
    - lib/services/ball_tracker.dart
  modified: []

key-decisions:
  - "YoloCoordUtils crop math extracted verbatim from DebugDotPainter — no modifications, same formula verified on iPhone 12"
  - "BallTracker._prune() must NOT reset _consecutiveMissedFrames — that counter tracks frame-level continuity independent of time-based pruning"
  - "TrackedPosition uses dart:ui Offset only (not flutter/painting.dart) to keep the model free of Flutter framework dependency"

patterns-established:
  - "Occlusion sentinel: single TrackedPosition with isOccluded=true at last-known position to signal trail line break"
  - "autoResetThreshold=30 consecutive missed frames clears trail — prevents stale ghost trails after ball leaves frame"

requirements-completed: [TRAK-01, TRAK-02, TRAK-05]

# Metrics
duration: 2min
completed: 2026-02-23
---

# Phase 7 Plan 01: Trail Accumulation and Rendering — Data and Service Layer Summary

**Pure-Dart TrackedPosition value type, YoloCoordUtils FILL_CENTER coordinate extractor, and BallTracker with 1.5s ListQueue, occlusion sentinels (anti-stacking), and 30-frame auto-reset**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-23T18:36:48Z
- **Completed:** 2026-02-23T18:38:27Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- `TrackedPosition` immutable value type: `normalizedCenter`, `timestamp`, `isOccluded` — no Flutter widget imports, safe for unit testing
- `YoloCoordUtils.toCanvasPixel` static utility: FILL_CENTER crop math extracted verbatim from `DebugDotPainter` (Phase 6 verified formula)
- `BallTracker` service: 1.5s sliding window via `ListQueue`, single occlusion sentinel per gap (anti-stacking guard), 30-frame auto-reset, `lastKnownPosition` getter for TRAK-04 nearest-neighbour tiebreaker

## Task Commits

Each task was committed atomically:

1. **Task 1: Create TrackedPosition value type and YoloCoordUtils shared utility** - `c6ce212` (feat)
2. **Task 2: Create BallTracker service with bounded ListQueue and auto-reset** - `e9ae9cf` (feat)

**Plan metadata:** (docs commit follows)

## Files Created/Modified

- `lib/models/tracked_position.dart` — Immutable value type for trail history; holds normalizedCenter (Offset), timestamp (DateTime), isOccluded (bool)
- `lib/utils/yolo_coord_utils.dart` — Static utility with FILL_CENTER crop math; extracted verbatim from DebugDotPainter to avoid duplication in trail painter
- `lib/services/ball_tracker.dart` — Service managing trail history via ListQueue; implements TRAK-01 (time window), TRAK-02 (occlusion sentinel), TRAK-05 (auto-reset)

## Decisions Made

- `YoloCoordUtils` crop math copied exactly from `DebugDotPainter.paint()` with no arithmetic changes — the formula was verified on iPhone 12 in Phase 6 and must not be modified without re-validation on device
- `BallTracker._prune()` is strictly time-based and must never touch `_consecutiveMissedFrames` — that counter tracks frame-level detection continuity, not queue membership. Resetting it inside `_prune()` would silently suppress the TRAK-05 auto-reset (research Pitfall 3)
- `TrackedPosition` imports `dart:ui` not `package:flutter/painting.dart` for `Offset` — keeps the model class free of the Flutter widget framework, enabling pure-Dart unit tests

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- All three data/service layer artifacts are complete and `flutter analyze` clean
- Plan 02 can now import `TrackedPosition`, `YoloCoordUtils`, and `BallTracker` directly — the trail painter and screen integration have no pending data-layer blockers
- No blocking concerns

---
*Phase: 07-trail-accumulation-and-rendering*
*Completed: 2026-02-23*
