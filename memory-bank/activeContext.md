# Active Context

> **CRITICAL: NEVER run `git commit`, `git push`, `git init`, or any git write commands. This project has NO git repository. It is local-only by explicit developer decision. This rule is ABSOLUTE and has been violated in the past  do NOT repeat.**

## Current Focus
**Session Lock + Protected Track + Mahalanobis Area Ratio Filter  implemented and monitor-tested (2026-04-15).** Manager's suggestions to reduce false positive trail dots led to three new features: (1) session lock in BallIdentifier that prevents re-acquisition during kicks, (2) protected track in ByteTrack that extends locked track survival from 30 to 60 frames, (3) bbox area ratio check on Mahalanobis rescue (reject if detection area >2x or <0.5x the track's predicted area). Also added trail suppression during kick=idle. Monitor+video testing showed **zero false positive dots** but **2 out of 5 kicks went silent** (no tracking, no decision). Root cause identified: area ratio check (2.0 threshold) is too aggressive  blocks legitimate Mahalanobis rescues during fast kicks when Kalman predicted area diverges from real detection area. Fix direction: compare against last measured area instead of Kalman predicted area, or relax threshold.

### What Was Done This Session (2026-04-15)
1. **Session lock in BallIdentifier**  `_sessionLocked` flag with `activateSessionLock()` / `deactivateSessionLock()`. When active, Priority 2 (single moving track) and Priority 3 (nearest non-static) are skipped. Activated when KickDetector enters `active` state, deactivated on HIT/MISS/LOST decision.
2. **Protected track in ByteTrackTracker**  `_protectedTrackId` with `setProtectedTrackId()`. Protected track survives 60 frames (`protectedMaxLostFrames`) instead of default 30 (`maxLostFrames`). Covers typical ball flight duration.
3. **Bbox area ratio check on Mahalanobis rescue**  Before accepting a Mahalanobis rescue match, validates `detArea / trackArea` is between 0.5 and 2.0. Prevents track hijacking to player head/poster (which had ratios of 3.8x-9x in logs). **Currently too aggressive  blocks real ball tracking during fast kicks.**
4. **Trail suppression during idle**  TrailOverlay receives empty list when `_kickDetector.state == KickState.idle`. Trail dots only shown during confirming/active/refractory. Eliminates false positive visual noise between kicks.
5. **Wiring in LiveObjectDetectionScreen**  Session lock activates after `_kickDetector.processFrame()` when `isKickActive && !isSessionLocked`. Deactivates in both ACCEPT (after `onKickComplete()`) and REJECT (after `forceReset()`) paths.

### Monitor+Video Test Results (2026-04-15)
**Test with session lock + area ratio (5 kicks):**
- 3/5 kicks detected correctly with HIT decisions
- 2/5 kicks completely silent (no tracking, no dots, no decision)
- 0 false positive dots (previously the main problem)

**Silent kick #1 analysis:**
- Ball kicked to zone 7. trackId=5 tracked with only Kalman predictions during flight (no real detections matched). ImpactDetector fired premature noResult before ball reached grid. Then trackId lost, 12 new ball-class tracks appeared but BallIdentifier couldn't acquire because it was stuck on dead trackId. Ball's bounce-back was detected as a new kick and announced HIT zone 1 (false positive decision from bounce-back).

**Silent kick #2 analysis:**
- After a legitimate HIT zone 1 decision, bounce-back triggered false kick detection on trackId=31. Session lock activated for bounce-back. trackId=31 quickly lost. Session lock STUCK ON (no decision made to release it). Ball placed for next kick, kicked  completely silent because session lock blocked all re-acquisition for 200+ frames.

### Root Causes Identified
1. **Area ratio check (2.0/0.5) too aggressive**  During fast kicks, Kalman predicted area diverges from reality (shrinks due to vw/vh velocity components). Real YOLO detections get blocked because ratio exceeds threshold. Example: Kalman predicted area=0.000220, real detection area ~0.001  ratio=4.5x, blocked.
2. **Session lock has no safety timeout**  If locked track is lost and ImpactDetector never makes a decision (e.g., bounce-back triggered false kick, ball disappeared), the lock stays on forever. Need safety timeout or auto-release when locked track is removed from ByteTrack.
3. **Bounce-back triggers false kick detection**  After a real kick hits the wall, the bounce-back is detected as a new kick by KickDetector, triggering session lock on the wrong track.

### Previous Session (2026-04-14)
1. Guided Setup Flow with Auto-Zoom design discussion
2. Research on YOLO11n minimum pixel thresholds (~32px)
3. Plugin API exploration: setZoomLevel() supported
4. No code changes

### Failed Approach (2026-04-13, earlier session)  DO NOT REPEAT
2-layer filter (DetectionFilter + TrackQualityGate + Mahalanobis rescue validation). Init delay broke BallIdentifier re-acquisition. Player head (ar:0.9) unfilterable with geometry. Must implement ONE filter at a time.

### What Remains
1. **Area ratio check needs relaxation or different comparison basis**  Compare against last measured area (not Kalman predicted) or increase threshold to 3.0-3.5. Hijack cases were 3.8x-9x so there's room.
2. **Session lock needs safety timeout**  Auto-deactivate if locked track is lost for N frames without a decision. Prevents permanent lock from bounce-back false kicks.
3. **Bounce-back false kick detection**  KickDetector sees bounce-back motion as a new kick. Consider refractory period or direction check to reject bounce-backs.
4. **Mahalanobis rescue identity hijacking (ISSUE-026)**  Partially addressed by area ratio check. Needs further tuning.
5. **Player head false positives (ar:0.9, c:0.98)**  Passes AR filter. Unfilterable with geometry alone. Partially addressed by session lock (dots hidden during idle) but track corruption still occurs.

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
- **Bbox area ratio check on Mahalanobis rescue**  Implemented at 2.0/0.5 threshold. Eliminates false positives but blocks legitimate tracking during fast kicks. Needs threshold adjustment or comparison basis change.
- **Session lock safety timeout**  Not yet implemented. Lock can get stuck permanently if no decision fires.
- **directZone accuracy**  Reports first zone entered, not impact zone. 0/5 to 5/5 correct depending on calibration.
- **Bounce-back false detection**  Ball rebound triggers second decision cycle. Not addressed.

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
1. **Fix area ratio check**  Either compare detection area against last measured area (not Kalman predicted) to avoid drift, or relax threshold to 3.0-3.5 (hijack cases were 3.8x-9x). Test on device.
2. **Add session lock safety timeout**  Auto-deactivate if locked track is lost for >30 frames without a decision. Prevents permanent lock from bounce-back.
3. **Field test with fixes**  Verify both fixes together: zero false positive dots + no silent kicks.
4. **Address bounce-back false kicks**  Consider direction check in KickDetector (ball moving away from goal = not a kick) or extended refractory period after decisions.
