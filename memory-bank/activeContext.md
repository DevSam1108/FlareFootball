# Active Context

> **CRITICAL: NEVER run `git commit`, `git push`, `git init`, or any git write commands. This project has NO git repository. It is local-only by explicit developer decision. This rule is ABSOLUTE and has been violated in the past  do NOT repeat.**

## Current Focus
**Mahalanobis area ratio fix — last-measured-area approach implemented and monitor-tested (2026-04-16).** Iterative fix for silent kicks caused by over-aggressive bbox area ratio check on Mahalanobis rescue. Three approaches tested: (1) relaxed Kalman threshold 3.5/0.3 → 4/5 kicks detected but false positive dots returned, (2) last-measured-area with tight 2.0/0.5 → 3/5 (lower bound too tight, ball shrinks during flight), (3) last-measured-area with 2.0/0.3 → **5/5 kicks detected across 3 test runs**. False positive dots still appear (open issue). Ground testing scheduled for 2026-04-17.

### What Was Done This Session (2026-04-16)
1. **Area ratio fix iteration 1: relaxed threshold (3.5/0.3)** — Single line change in `bytetrack_tracker.dart:858`. Result: 4/5 kicks tracked, but false positive dots returned (threshold too loose for hijacking prevention).
2. **Area ratio fix iteration 2: last-measured-area with tight bounds (2.0/0.5)** — Passed `lastMeasuredBallArea` from `BallIdentifier.lastBallBboxArea` through `ByteTrackTracker.update()` → `_greedyMatch()` → area ratio check. Uses real measurement instead of drifting Kalman predicted area. Result: 3/5 kicks (worse — lower bound 0.5 blocks shrinking ball during flight toward target).
3. **Area ratio fix iteration 3: last-measured-area with relaxed lower bound (2.0/0.3)** — Kept last-measured-area comparison, relaxed lower bound from 0.5 → 0.3. Result: **5/5 kicks detected across 3 test runs**. Upper bound 2.0 still blocks hijacking (false positives were 3.8x-9x).

### Changes Made (2026-04-16)
- **`bytetrack_tracker.dart`** — `update()` and `_greedyMatch()` accept `lastMeasuredBallArea` optional parameter. Area ratio check uses `lastMeasuredBallArea` with Kalman predicted area as fallback. Threshold: `2.0/0.3`.
- **`live_object_detection_screen.dart`** — `_byteTracker.update()` passes `_ballId.lastBallBboxArea`. Calibrate/Re-calibrate button repositioned from `bottom:16` to `bottom:48` (above tilt indicator). Large result overlay re-enabled (was commented out for testing).
- **`calibration_overlay.dart`** — Center crosshair color changed from white to purple, strokeWidth from 0.5 to 1.5. Center circle also purple at 1.5 strokeWidth.
- **176/176 tests passing.**

### Previous Session (2026-04-15)
1. Session lock in BallIdentifier — `_sessionLocked` flag blocks Priority 2/3 re-acquisition during kicks
2. Protected track in ByteTrackTracker — locked track survives 60 frames instead of 30
3. Bbox area ratio check on Mahalanobis rescue (initial version with Kalman predicted area, 2.0/0.5)
4. Trail suppression during kick=idle
5. Monitor+video test: 3/5 kicks, 0 false positive dots, 2 silent kicks identified

### Previous Session (2026-04-14)
1. Guided Setup Flow with Auto-Zoom design discussion
2. Research on YOLO11n minimum pixel thresholds (~32px)
3. Plugin API exploration: setZoomLevel() supported
4. No code changes

### Failed Approach (2026-04-13, earlier session)  DO NOT REPEAT
2-layer filter (DetectionFilter + TrackQualityGate + Mahalanobis rescue validation). Init delay broke BallIdentifier re-acquisition. Player head (ar:0.9) unfilterable with geometry. Must implement ONE filter at a time.

### What Remains / Open Issues
1. **False positive trail dots still appearing** — Dots visible during kicks on non-ball objects. Session lock + trail suppression hides idle-period dots, but during active kicks false detections still produce dots. Open issue.
2. **Session lock needs safety timeout** — Auto-deactivate if locked track is lost for N frames without a decision. Prevents permanent lock from bounce-back false kicks.
3. **Bounce-back false kick detection** — KickDetector sees bounce-back motion as a new kick. Consider refractory period or direction check to reject bounce-backs.
4. **Player head false positives (ar:0.9, c:0.98)** — Passes AR filter. Unfilterable with geometry alone.
5. **Ground testing scheduled 2026-04-17** — First outdoor field test with all recent fixes (session lock + last-measured-area ratio + trail suppression).

## What Is Fully Working
- YOLO11n live camera detection on iOS (iPhone 12) and Android (Realme 9 Pro+)
- ByteTrack multi-object tracker with 8-state Kalman filter
- BallIdentifier with 3-priority identification and session lock
- Ball trail overlay with kick-state-based visibility (dots only during kicks)
- "Ball lost" badge after 3 consecutive missed frames
- 4-corner calibration with DLT homography transform
- 9-zone target mapping via TargetZoneMapper
- ImpactDetector (Phase 3 state machine) with directZone decision
- KickDetector (4-state gate: idle/confirming/active/refractory)
- Audio feedback (zone callouts + miss buzzer)
- DiagnosticLogger CSV export with Share Log
- Pre-ByteTrack AR > 1.8 filter (rejects torso/limb false positives)
- Session lock prevents re-acquisition during active kicks
- Protected track extends ByteTrack survival for locked ball
- Landscape orientation lock with proper restore
- Camera permission handling
- Rotate-to-landscape overlay with accelerometer

## What Is Partially Done / In Progress
- **Bbox area ratio check on Mahalanobis rescue** — ✅ Fixed. Uses last-measured-area with 2.0/0.3 threshold. 5/5 kicks tracked across 3 test runs.
- **Session lock safety timeout** — Not yet implemented. Lock can get stuck permanently if no decision fires.
- **directZone accuracy** — Reports first zone entered, not impact zone. 0/5 to 5/5 correct depending on calibration.
- **Bounce-back false detection** — Ball rebound triggers second decision cycle. Not addressed.
- **False positive trail dots** — Still appearing during active kicks. Open issue.

## Known Gaps
- iOS `NSCameraUsageDescription` has placeholder text
- `tennis-ball` priority 2 in class filter (harmless)
- Free Apple Dev cert expires every 7 days
- Phantom impact decisions during kick=idle (log noise only, not announced)

## Model Files: Developer Machine Setup Required
**Android:**
```bash
mkdir -p android/app/src/main/assets
cp /path/to/yolo11n.tflite android/app/src/main/assets/
```

**iOS:**
1. Copy `yolo11n.mlpackage` into `ios/` directory
2. Open `ios/Runner.xcworkspace` in Xcode
3. Confirm model appears under Runner  Build Phases  Copy Bundle Resources

## Active Environment Variable
```bash
flutter run --dart-define=DETECTOR_BACKEND=yolo
# or simply:
flutter run
```

## Immediate Next Steps
1. **Ground testing (2026-04-17)** — Outdoor field test with all recent fixes. Evaluate: kick detection rate, false positive dots, zone accuracy, session lock behavior.
2. **Session lock safety timeout** — Auto-deactivate if locked track is lost for >30 frames without a decision. Implement after ground test confirms area ratio fix is stable.
3. **Address false positive trail dots** — Investigate during ground test. May need additional filtering or tighter session lock behavior.
4. **Address bounce-back false kicks** — Consider direction check in KickDetector or extended refractory period after decisions.
