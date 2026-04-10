# Phase 5: Depth Estimation via Ball Reference Capture (Approach B)

## Objective
Filter false-positive HITs where the ball's trajectory extrapolates to the target but the ball never actually reached the target's depth. Uses a calibration-time reference capture — no hardcoded ball size.

## Approach
After the user taps 4 corners, add a "ball reference" step: user places the ball on the target, YOLO auto-detects it, and we capture the bounding box area at that distance. During tracking, compare the ball's current bbox area to the reference. If the ball is still much smaller than the reference when detection is lost, it didn't reach the target — downgrade HIT to MISS.

---

## Files to Modify

### 1. `lib/models/tracked_position.dart`
- Add optional `double? bboxArea` field to `TrackedPosition`
- Add to constructor with default `null` (backward-compatible)

### 2. `lib/services/ball_tracker.dart`
- Add `bboxArea` parameter to `update()` method
- Pass through to `TrackedPosition` entries
- Add `double? get lastBboxArea` getter — returns bbox area of the most recent non-occluded entry

### 3. `lib/services/impact_detector.dart`
- Add `double? _referenceBboxArea` field + `set referenceBboxArea(double? value)` setter
- Add `bboxArea` optional parameter to `processFrame()`
- Accumulate bbox area history during tracking (like `_velocityHistory`)
- Add depth filter in `_makeDecision()`:
  - Only applies when `_referenceBboxArea != null` and `_bboxAreaHistory` is non-empty
  - Compute `maxRecentBboxArea` from last 5 entries in `_bboxAreaHistory`
  - `ratio = maxRecentBboxArea / _referenceBboxArea`
  - If `ratio < depthRatioThreshold` (0.4) → ball didn't reach target → downgrade HIT to MISS
  - Threshold 0.4 means the ball must appear at least ~40% the size it was at the target (roughly 60% of the way there). Conservative to avoid false negatives.
- Priority order in `_makeDecision()` stays: insufficient frames → edge exit → **depth filter** → trajectory hit → noResult
- Clear `_bboxAreaHistory` in `_reset()`

### 4. `lib/screens/live_object_detection/live_object_detection_screen.dart`
**A. Extract bbox area from YOLO result:**
- After `_pickBestBallYolo()`, compute `bboxArea = ball.normalizedBox.width * ball.normalizedBox.height`
- Pass to `_tracker.update(rawPosition, bboxArea: bboxArea)`
- Pass to `_impactDetector.processFrame(bboxArea: _tracker.lastBboxArea)`

**B. Reference capture calibration step:**
- Add state: `bool _ballReferenceMode = false`, `double? _referenceBboxArea`
- After 4th corner tap: set `_ballReferenceMode = true` instead of `_calibrationMode = false`
- During `_ballReferenceMode`: if YOLO detects a ball AND `_zoneMapper!.pointToZone(center)` returns a valid zone (ball is inside the grid):
  - Capture `_referenceBboxArea = bboxArea`
  - Set `_impactDetector.referenceBboxArea = _referenceBboxArea`
  - Set `_ballReferenceMode = false`
  - Show brief "Ball size captured!" status
- Instruction text during reference mode: "Place ball on target — waiting for detection..."
- If user taps "Re-calibrate", clear `_referenceBboxArea` and restart full flow

**C. UI changes:**
- During `_ballReferenceMode`, show instruction bottom-right: "Place ball on target"
- Calibrate button disabled during both `_calibrationMode` and `_ballReferenceMode`
- Brief confirmation text when reference captured (auto-clears after ~1.5s or on first tracking frame)

### 5. `test/impact_detector_test.dart`
Add tests:
- `depth filter downgrades HIT to MISS when ball is too small` — set referenceBboxArea, track with small bboxArea, extrapolation says HIT → result should be MISS
- `depth filter allows HIT when ball is large enough` — track with bboxArea near reference → HIT stands
- `depth filter inactive when no reference set` — no referenceBboxArea → existing behavior unchanged
- `depth filter inactive when no bbox history` — bboxArea never passed → existing behavior unchanged

### 6. `test/ball_tracker_kalman_test.dart`
Add tests:
- `update stores bboxArea in trail entries`
- `lastBboxArea returns most recent non-occluded bbox area`

---

## Calibration Flow (Before vs After)

**Before (Phases 1-4):**
1. Tap "Calibrate"
2. Tap 4 corners → grid appears → done

**After (Phase 5):**
1. Tap "Calibrate"
2. Tap 4 corners → grid appears
3. Instruction: "Place ball on target"
4. YOLO auto-detects ball inside grid → capture reference → "Ball size captured!"
5. Done — depth filter now active

---

## Decision Priority in `_makeDecision()` (Updated)

```
1. Insufficient tracking frames  → reset (no result)
2. Edge exit filter              → MISS
3. Depth filter (NEW)            → MISS (downgrades would-be HIT)
4. Trajectory extrapolation      → HIT at predicted zone
5. No signal                     → noResult
```

The depth filter sits between edge-exit and trajectory-hit. It only fires when trajectory would say HIT but the ball's apparent size says it never reached the target.

---

## Constants

| Constant | Value | Rationale |
|---|---|---|
| `depthRatioThreshold` | 0.4 | Ball must appear ≥40% of reference size. Conservative — avoids rejecting legitimate hits where the ball was slightly far. Tunable after device testing. |
| `bboxAreaHistorySize` | 5 | Use max of last 5 bbox areas (not average) to be generous — if the ball was ever close enough, allow it. |

---

## What This Does NOT Change
- No new dependencies
- No new files (all changes in existing files)
- No changes to homography, zone mapper, Kalman filter, trajectory extrapolator, audio service, or trail overlay
- Calibration overlay widget unchanged (grid rendering stays the same)
- `flutter analyze` must remain at 0 issues
- All existing 74 tests must continue passing
