---
phase: 08-polish
plan: 01
subsystem: ui
tags: [flutter, dart, ball-tracking, overlay, yolo, mobile]

# Dependency graph
requires:
  - phase: 07-trail-accumulation-and-rendering
    provides: BallTracker service with _consecutiveMissedFrames counter and trail overlay Stack structure
provides:
  - BallTracker.isBallLost public boolean getter backed by ballLostThreshold = 3
  - Conditional "Ball lost" red badge at top-right of YOLO live detection screen (PLSH-01)
  - Device-verified on iPhone 12: badge appears within ~100ms, disappears on re-detection
affects: [evaluation, device-verification, polish]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "In a Flutter Stack, Positioned must be a direct child — IgnorePointer goes INSIDE Positioned, not outside"
    - "Badge visibility driven by direct getter read in build() — no timers, streams, or MobX"
    - "Threshold constant defined on service (BallTracker) not in widget — single source of truth"

key-files:
  created: []
  modified:
    - lib/services/ball_tracker.dart
    - lib/screens/live_object_detection/live_object_detection_screen.dart

key-decisions:
  - "ballLostThreshold = 3 frames (3 < autoResetThreshold 30; 3 frames ≈ 100ms at 30fps satisfies PLSH-01)"
  - "isBallLost returns boolean only — screen does not need to know the raw miss count"
  - "Badge piggybacks on existing onResult setState — no separate animation loop or state variable needed"
  - "Positioned(child: IgnorePointer(...)) — Positioned must be direct Stack child; IgnorePointer goes inside (Flutter constraint)"

patterns-established:
  - "PLSH-01 badge pattern: threshold constant on tracker, boolean getter, conditional Positioned Stack child with IgnorePointer inside"

requirements-completed: [PLSH-01]

# Metrics
duration: ~10min
completed: 2026-02-24
---

# Phase 8 Plan 01: Ball Lost Badge Summary

**Red "Ball lost" badge on YOLO live screen driven by BallTracker.isBallLost getter with 3-frame threshold (~100ms at 30fps), device-verified on iPhone 12 with bug fix for Positioned/IgnorePointer nesting order**

## Performance

- **Duration:** ~10 min (including device verification and bug fix)
- **Started:** 2026-02-24T17:57:02Z
- **Completed:** 2026-02-24T18:xx:xxZ
- **Tasks:** 3/3 complete (including device verification)
- **Files modified:** 2

## Accomplishments
- Added `static const int ballLostThreshold = 3` and `bool get isBallLost` to `BallTracker` — satisfies PLSH-01 "within a few frames" requirement (3 frames ≈ 100ms at 30fps)
- Added conditional "Ball lost" badge to YOLO Stack in `LiveObjectDetectionScreen`: red `Container` at `top: 12, right: 12`, `IgnorePointer` inside `Positioned`, visible when `_tracker.isBallLost` is true
- Badge disappears immediately on re-detection (next `onResult` `setState` rebuild reads `isBallLost` as false)
- Device-verified on iPhone 12: badge appears within ~100ms, disappears on re-detection, does not overlap backend label, touch handling preserved; user confirmed "Ball lost overlay works perfectly"

## Task Commits

Each task was committed atomically:

1. **Task 1: Add isBallLost getter and ballLostThreshold to BallTracker** - `8d061c5` (feat)
2. **Task 2: Add conditional Ball lost badge to YOLO live detection screen** - `b6a68fb` (feat)
3. **Task 3: Fix Positioned/IgnorePointer nesting (device verification bug fix)** - `b7d7ed7` (fix)

**Plan metadata:** `17fb1f8` (docs: complete plan — pre-verification), updated post-verification below.

## Files Created/Modified
- `lib/services/ball_tracker.dart` - Added `ballLostThreshold = 3` constant and `isBallLost` boolean getter
- `lib/screens/live_object_detection/live_object_detection_screen.dart` - Added conditional "Ball lost" badge as YOLO Stack child; nesting order fixed to `Positioned(child: IgnorePointer(...))` after device verification

## Decisions Made
- `ballLostThreshold = 3` satisfies PLSH-01 "within a few frames" and maps to ~100ms at 30fps; well below `autoResetThreshold = 30`
- Expose only a boolean getter (`isBallLost`) from `BallTracker` — the screen never needs the raw miss count
- Badge piggybacks on existing `onResult` `setState` rebuild cycle — no Timer, Stream, animation controller, or MobX needed
- `Positioned(child: IgnorePointer(child: Container(...)))` — Flutter requires `Positioned` to be a direct Stack child; wrapping it in `IgnorePointer` first causes an assertion error at runtime
- `Colors.red.withValues(alpha: 0.85)` — uses non-deprecated API (same as trail overlay code)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed Positioned/IgnorePointer nesting order causing camera freeze**
- **Found during:** Task 3 (device verification on iPhone 12)
- **Issue:** Plan code had `IgnorePointer(child: Positioned(...))` — Flutter's Stack widget requires `Positioned` to be a direct Stack child. Wrapping it in `IgnorePointer` first caused a Flutter assertion error when `isBallLost` became true, freezing the camera feed.
- **Fix:** Swapped nesting to `Positioned(top: 12, right: 12, child: IgnorePointer(child: Container(...)))` — `Positioned` is now a direct Stack child; `IgnorePointer` still sits above the `Container` to preserve YOLOView touch handling.
- **Files modified:** `lib/screens/live_object_detection/live_object_detection_screen.dart`
- **Verification:** Device-verified on iPhone 12 — no assertion error, badge appears and disappears correctly, touch handling preserved. User: "Ball lost overlay works perfectly."
- **Committed in:** `b7d7ed7` (fix(08-01))

---

**Total deviations:** 1 auto-fixed (Rule 1 — bug)
**Impact on plan:** Necessary correctness fix. No scope creep. The fix preserves all original intent: `IgnorePointer` still prevents touch event consumption, badge still appears at top-right, and `Positioned` is correctly placed as a direct Stack child.

## Issues Encountered
- Flutter assertion error on device when `isBallLost` first became `true`: `IgnorePointer` must not wrap `Positioned` as a Stack child — Flutter enforces `Positioned` as a direct Stack child at runtime. Fixed by swapping nesting order.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 8 (Polish) is fully complete and device-verified on iPhone 12
- Full v1.1 ball tracking milestone is complete (Phases 6, 7, 8 all device-verified)
- Remaining open items: Galaxy A32 testing (blocked on Android SDK), Unsplash API key, iOS camera usage description

---
*Phase: 08-polish*
*Completed: 2026-02-24*
