# Issue Log

Recurring issues, root causes, and verified solutions. Check here before researching online.

---

## ISSUE-028: 2-Layer False Positive Filter Broke Ball Re-acquisition (REVERTED)

**Date:** 2026-04-13
**Platform:** iOS (iPhone 12)
**Symptom:** After implementing DetectionFilter (pre-ByteTrack AR + size reject) + TrackQualityGate (post-ByteTrack init delay + rolling median) + Mahalanobis rescue validation, ball tracking became severely unstable. Track IDs cycled from 1 to 15 in one session. BallIdentifier locked onto a poster on the wall (id:6, ar:0.8, c:0.99) and player's head (id:14, ar:0.9, c:0.98). Real ball detections were stuck at [INIT 2] and never reached BallIdentifier.

**Root Cause:** TrackQualityGate's initialization delay (4 frames) blocked new tracks from reaching BallIdentifier. When the original ball lock was lost (player walked in front), the real ball reappeared as a new ByteTrack track but was held at [INIT] for 4 frames. During that window, BallIdentifier re-acquired to whatever was already available — poster, head, etc. Additionally, DetectionFilter may have intermittently rejected the real ball on borderline frames, causing ByteTrack to lose and recreate tracks (explaining the id churn).

**Evidence:** 6 screenshots from device testing:
1. Ball correctly locked (id:1) — baseline good
2. Real ball (id:2) stuck at [INIT 2], locked track (id:1) drifted to ar:0.3
3. Ball lock lost entirely, player head (id:3) passed all filters
4. Poster locked as ball (id:6, ar:0.8, c:0.99) — total identity corruption
5. id:11 with AR 3.8 passed Layer 1 (should have been rejected at AR > 2.5 threshold)
6. Player head (id:14, ar:0.9, c:0.98) passed all filters as yellow candidate

**Fix:** Fully reverted all changes. 4 modified files restored via `git checkout`, 4 new files deleted. 176/176 tests passing.

**Lessons:**
1. **Never block tracks from BallIdentifier** — init delay starves re-acquisition. Any post-ByteTrack filter must pass ALL tracks through; can tag/score but must not remove from candidate pool.
2. **Player head (ar:0.9) is unfilterable with geometry** — needs second-stage classifier or motion channel.
3. **Implement ONE filter at a time** — test on device before adding the next. Multi-layer simultaneous changes make it impossible to isolate which filter caused which problem.
4. **Mahalanobis rescue validation (size + velocity) is the safest first step** — it only restricts rescue matching inside ByteTrack, doesn't touch pipeline flow or BallIdentifier at all.

**Status:** ✅ REVERTED (2026-04-13). Codebase clean. 176/176 tests passing.

---

## ISSUE-027: isStatic Flag Never Clears on Existing ByteTrack Tracks

**Date:** 2026-04-09
**Platform:** iOS (iPhone 12)
**Symptom:** When the ball is kicked, the locked track (original trackId from calibration) retains `isStatic=true` even though the ball is in motion. KickDetector reaches `confirming` but may drop back to `idle` before the decision fires, blocking announcements. Only NEW tracks born during motion get `isStatic=false`. Additionally, `isStatic` never re-triggers on subsequent stationary periods — once `false`, stays `false` forever because `_cumulativeDisplacement` retains displacement from previous movement.

**Root Cause:** Two bugs in `_STrack.evaluateStatic()`: (1) `isStatic` was a one-way flag — `if (!isStatic && ...)` only set to `true`, never cleared. (2) `_cumulativeDisplacement` was a lifetime accumulator that only grew — after any movement, the total exceeded `maxDisp` forever, preventing re-classification as static.

**Evidence:** Debug bbox overlay showed `S` (isStatic) label on locked ball track during flight. Test 1 Kick 1: `kick=confirming` coexisted with `isStatic=true`, `kickState` dropped to `idle` by decision time. New trackIds born in flight had `isStatic=false` and reached `kickState=active` normally.

**Solution:** Replaced lifetime `_cumulativeDisplacement` accumulator with sliding window `ListQueue<double>` (capacity = 30 frames). `evaluateStatic()` now sums only the recent window and sets `isStatic` based on whether total < threshold, making it fully two-way. Approach inspired by Frigate NVR's production static object detection. Research confirmed no standard tracker (ByteTrack/SORT/DeepSORT/OC-SORT/Norfair) has static classification.

**Status:** ✅ FIXED (2026-04-13). Device-verified on iPhone 12. 3 new unit tests added. 176/176 passing.

---

## ISSUE-026: Mahalanobis Rescue Hijacks Ball Identity (CRITICAL)

**Date:** 2026-04-09
**Platform:** iOS (iPhone 12)
**Symptom:** Locked ball track jumps from real soccer ball to false positives (video player controls, wall marks, kicker's body) via Mahalanobis distance matching. Real ball becomes orphaned and untracked. Subsequent kicks produce noResult or total tracking failure.

**Root Cause:** Mahalanobis rescue is too lenient — accepts matches with mahal²=0.10-0.33+ allowing locked track to jump to distant false detections. `lockedTrackId` restricts WHICH TRACK gets rescued but not WHAT DETECTION it matches to.

**Evidence:** Debug bbox overlay confirmed: (1) Green [LOCKED] box on video player controls while real ball had yellow box, (2) Green box jumping from ball to zone 6 false positive and back, creating false trail dots, (3) After corruption, BallIdentifier stayed locked on wrong track for 100+ frames.

**Solution:** Pending. Options: (a) bbox size validation (reject >3x reference), (b) aspect ratio validation (reject ar >1.5), (c) max Mahalanobis threshold (cap mahal²), (d) position continuity check.

**Status:** Identified. CRITICAL priority — causes total tracking failure.

---

## ISSUE-025: Kick-State Gate Broke Grounded Kick Detection (REVERTED)

**Date:** 2026-04-08
**Platform:** iOS (iPhone 12)
**Symptom:** After adding kick-state gate (ImpactDetector/WallPredictor only run when `KickDetector.state == confirming || active`), 3 out of 5 kicks went undetected — specifically grounded/low-velocity shots.

**Root Cause:** KickDetector's `jerkThreshold = 0.01` requires an explosive velocity spike to transition from idle → confirming. Grounded shots have lower velocity onset and less abrupt acceleration than aerial kicks. The jerk threshold never fires, so `kickEngaged` stays `false`, ImpactDetector never receives frames, and the pipeline is completely silent for those kicks.

**Fix:** Fully reverted the kick-state gate. ImpactDetector and WallPredictor now run unconditionally every frame (same as pre-experiment baseline). KickDetector only controls whether the result is announced (audio gate), not whether the pipeline processes frames.

**Lesson:** Gating pipeline INPUT on KickDetector state is too aggressive. KickDetector should only gate pipeline OUTPUT (result acceptance). The phantom decisions during idle that motivated the gate are log pollution, not functional bugs — the app correctly never announced them.

**Verified:** ✅ Reverted and confirmed 172/172 tests passing.

---

## ISSUE-024: Trail Dot Gating on kickEngaged Killed All Visualization (REVERTED)

**Date:** 2026-04-08
**Platform:** iOS (iPhone 12)
**Symptom:** After adding `kickEngaged` parameter to `BallIdentifier.updateFromTracks()`, zero trail dots appeared during any kicks. Complete loss of visual ball tracking.

**Root Cause:** Two compounding issues:
1. `_ballId.updateFromTracks(tracks, kickEngaged: ...)` was called BEFORE `_kickDetector.processFrame()`, so it read the previous frame's kick state (1-frame lag).
2. Kick windows are very short (3-5 frames for video-on-monitor testing), and with the 1-frame lag, the effective window was even shorter.
3. The underlying goal (preventing false dots on non-ball objects) was misdiagnosed — the root cause is BallIdentifier re-acquiring to wrong tracks (player body, poster), not trail timing.

**Fix:** Fully reverted `kickEngaged` parameter. Trail dots always added when ball is tracked, regardless of kick state.

**Verified:** ✅ Reverted and confirmed 172/172 tests passing.

---

## ISSUE-023: Ball Track Lost During Fast Kick Flight (ByteTrack IoU Failure)

**Date:** 2026-04-06
**Platform:** iOS (iPhone 12)
**Symptom:** After implementing ByteTrack, the ball is tracked correctly when stationary or moving slowly (player retrieving ball), but the track is LOST during fast kick flight. No orange trail dots appear during the kick. Every kick produces `noResult` because `directZone` is always null — the ball's tracked position never enters the calibrated grid.

**Root Cause:** ByteTrack's 8-state Kalman filter predicts near-zero velocity when the ball is stationary before a kick. When the ball suddenly accelerates (kick), it moves ~0.12 normalized units in 1 frame — roughly 2x the ball's bbox width (~0.06). The predicted bbox is still at the kicking spot, so IoU between predicted and actual detection is ZERO. ByteTrack cannot match the detection to the existing track, creates a new track with a new ID, and the original ball track goes to `lost` then `removed`. BallIdentifier re-acquires to a new trackId, but by then the ball may be mid-flight with a small bbox, or already bouncing back.

**Evidence:**
- Terminal log shows `trackId` jumping from 1 → 26 → 28 → 29 → 39 → 52 across one session
- CSV shows `directZone=null` for ALL tracking frames across 3 kicks
- Screenshots show trail dots only at kicking spot (stationary ball) and during slow ball retrieval, NOT during fast flight
- Ball IS visible in the camera frame during flight (screenshots prove YOLO detects it)

**Why slow movement works:** Player retrieving ball moves ~0.01 per frame vs bbox ~0.06. IoU stays ~0.7+. ByteTrack matches perfectly.

**Potential Solutions:**
1. Fall back to centroid-distance matching when IoU=0 for the locked ball track
2. Temporarily boost Kalman process noise on KickDetector jerk signal (lets velocity prediction catch up)
3. Widen IoU search radius during kick phase
4. Hybrid matching: IoU when available, centroid distance as fallback for fast motion

**Fix Iteration 1 (Mahalanobis merged with IoU):** Added `mahalanobisDistSq()` to Kalman, used as dual gate (`mahalOk || iouOk`) in `_greedyMatch`. Ball track maintained through kicks. BUT circle tracks also got Mahalanobis-rescued — wide covariance gate allowed circles to match to wrong circle detections, creating scattered false dots.

**Fix Iteration 2 (Mahalanobis restricted to locked track):** Changed to two-stage matching: Stage 1 pure IoU (all tracks), Stage 2 Mahalanobis (ONLY `lockedTrackId`). Added `lockedTrackId` parameter threaded through `update()` → `_greedyMatch()`. Live screen passes `_ballId.currentBallTrackId`. Circle tracks can only match via IoU — if IoU fails they go to `lost` state.

**Status:** Fix iteration 2 implemented. Pending device test.

---

## ISSUE-022: Target Circle False Positives — YOLO Detects Banner Circles as Soccer Balls (CRITICAL BLOCKER)

**Date:** 2026-04-04
**Platform:** iOS (iPhone 12) — likely affects Android too
**Symptom:** Orange trail dots appear on the target banner's red LED-ringed circles even when no real ball is in flight. During kicks, trail dots scatter between the real ball and circle false positives. Zone announcements fire prematurely with wrong zones. Shaking the camera toward the target creates false trails hopping between circles, triggering zone announcements with no ball kicked.

**Root Cause:** The 9 red LED-ringed circles (~20-25cm diameter) on the Flare Player target banner are round shapes that YOLO detects as `Soccer ball` or `ball` at confidence ≥0.25. These detections:
1. Compete with the real ball in `_pickBestBallYolo` — especially when the real ball approaches the target area, circle detections are spatially closer to the last known position
2. Are INSIDE the calibrated grid area — `_applyPhaseFilter()` spatial gating cannot distinguish them from the real ball arriving at the target
3. Appear ON the wall surface (depth ratio ~1.0), INSIDE a zone (directZone not null), and stationary — identical to "ball has impacted the target" for the pipeline
4. Corrupt BallTracker, Kalman filter, WallPlanePredictor, and ImpactDetector with false position data

**Evidence:** 41 screenshots in `/Users/shashank/Documents/app behaviour images/False positive on goal post/`. Field test: Phase 1 = 7/18 (38.9%) accuracy with zone 6 bias, Phase 2 = 1/9 (11.1%) accuracy with zone 1/2 bias. Bias changes with camera height — proves detections are on target circles, not real ball trajectories.

**Solution:** Pending design. Possible approaches: geometric exclusion zone (reject detections inside calibrated grid when ball is not near target), bbox size filtering (circles have stable size vs moving ball), motion-based filtering (circles are stationary vs moving ball), confidence threshold increase, or model retraining.

**Status:** Identified. #1 BLOCKER for zone accuracy. Solution not yet designed or approved.

---

## ISSUE-021: Bounce-Back False Detection (Ball Detected on Rebound, Not Initial Impact)

**Date:** 2026-04-01
**Platform:** iOS (iPhone 12)
**Symptom:** Ball hits zone 6 on the wall but YOLO misses the initial impact (ball too fast/small at the wall). After the ball bounces back toward the camera (getting larger, moving downward in frame), YOLO re-detects it and the pipeline reports zone 2 instead of zone 6.

**Root Cause:** YOLO loses the ball near the wall (small bbox, motion blur). The ball bounces back and is re-detected closer to the camera. The WallPlanePredictor accumulates observations from the rebound (depth decreasing = ball coming back), which fails the `_isDepthIncreasing()` check. However, the ImpactDetector may still have stale `_lastWallPredictedZone` from before the loss, or the rebound trajectory enters the grid from the bottom.

**Solution:** Pending. Options: (a) reject detections where depth trend reverses after a period of increasing depth, (b) use velocity-drop detection at point of wall contact, (c) time-box the prediction window so decisions can't be made from rebound data.

**Status:** Identified, not yet fixed.

---

## ISSUE-020: False Positive YOLO Detections on Non-Ball Objects (Kicker Body/Head)

**Date:** 2026-04-01
**Platform:** iOS (iPhone 12)
**Symptom:** Orange trail dots appear on the kicker's body, hands, head, and random wall patterns during Ready and Tracking phases. Creates visual noise and can confuse the tracking pipeline.

**Root Cause:** `confidenceThreshold: 0.25` in YOLOView accepts marginal detections. At low confidence, YOLO misclassifies round-ish shapes (head, hands, clothing folds) as `Soccer ball` or `ball`.

**Solution:** Added `_applyPhaseFilter()` in `_pickBestBallYolo`. Phase-aware filtering:
- Ready phase: confidence floor 0.50 + spatial gate (10% of frame radius from last known position)
- Tracking phase: confidence floor 0.25 + spatial gate (15% of frame radius from Kalman-predicted position)
- No prior position: confidence floor 0.50, no spatial gate

**Status:** FIXED — verified in Session 3 field test (no false dots observed).

---

## ISSUE-019: Zone Accuracy Bug 3 Root Cause — Perspective Error in Mid-Flight Mapping

**Date:** 2026-04-01
**Platform:** iOS (iPhone 12)
**Symptom:** Ball hitting upper zones (6, 7, 8) consistently reported as bottom zones (1, 2). Session 1: 1/5 correct (20%). Every high-zone kick mapped to zone 1 or 2.

**Root Cause:** The 2D homography maps image points to the wall plane, but only correctly for points ACTUALLY ON the wall. The ball is detected mid-flight, NOT at the wall. Due to perspective, a ball heading toward zone 8 at mid-flight appears LOWER in the camera frame than zone 8's actual position on the wall. The homography maps this lower position to zone 1 or 2.

Both `directZone` (maps raw position through homography) and the old `TrajectoryExtrapolator` (projects 2D camera velocity) suffer from this: `directZone` captures the grid-entry position (bottom), and the extrapolator under-predicts vertical displacement because 2D velocity decelerates due to perspective foreshortening.

**Solution:** `WallPlanePredictor` service (3 iterations):
- v1: Estimated wall depth from hardcoded `wallDepthRatio=0.25`. Fixed Y-axis error but fragile.
- v2: Computed wallDepthRatio from physical dimensions. Still hardcoded physical assumptions.
- v3 (current): Zero hardcoded parameters. Iterative forward projection — extrapolates pseudo-3D trajectory one frame at a time, projects back to 2D, checks `pointToZone()`. Wall discovered implicitly when projected point enters the grid.

**Status:** LARGELY FIXED. Session 3: 3/5 exact correct (60%), 4/5 within 1 zone (80%). Remaining: boundary precision and bounce-back detection (separate issues).

---

## ISSUE-001: Android `onResult` Never Fires (Silent YOLO Inference Failure)

**Date:** 2026-02-25
**Platform:** Android (Galaxy A32)
**Symptom:** `YOLOView` renders but `onResult` callback never fires. No errors in logcat. Camera preview works fine.

**Root Cause:** Gradle's AAPT compresses `.tflite` files by default. The compressed model cannot be memory-mapped by TFLite, so inference silently fails.

**Solution:** Add to `android/app/build.gradle`:
```groovy
android {
    aaptOptions {
        noCompress 'tflite'
    }
}
```

**Why it's easy to miss:** No error is thrown. The camera preview works. Only the inference callback is silent.

---

## ISSUE-002: iOS "Unable to Verify App" After ~7 Days

**Date:** 2026-03-11
**Platform:** iOS (iPhone 12)
**Symptom:** App icon tap shows "Unable to Verify" dialog. Tapping "Verify App" in Settings fails with network error even when WiFi is connected.

**Root Cause:** Free Apple Developer account provisioning profiles expire after **7 days**. Once expired, iOS cannot verify the signing certificate and blocks app launch. The network error is misleading — the profile is expired, not unreachable.

**Solution:**
1. Delete the app from the iPhone (long-press icon -> Remove App -> Delete App)
2. Re-run `flutter run` from Mac with iPhone connected via USB
3. This generates a fresh 7-day provisioning profile

**Prevention:** Re-deploy via `flutter run` at least once every 7 days. A paid Apple Developer account ($99/year) extends profiles to 1 year.

**What does NOT work:**
- Restarting the iPhone
- Toggling WiFi
- Tapping "Verify App" repeatedly in Settings

---

## ISSUE-003: iOS Camera Not Working After App Reinstall (No Permission Dialog)

**Date:** 2026-03-11
**Platform:** iOS (iPhone 12)
**Symptom:** Camera screen shows blank/pink background. Terminal logs: `Camera permission not determined. Please request permission first.` followed by `Failed to set up camera - permission may be denied or camera unavailable.` No permission dialog appears on the phone.

**Root Cause (multi-factor):**
1. Deleting an app from iOS **wipes its camera permission** from the TCC database, resetting to `.notDetermined`
2. The `ultralytics_yolo` plugin (v0.2.0) does **NOT** request camera permission on iOS — it only checks the status and silently fails if `.notDetermined` (see `VideoCapture.swift` lines 86-95)
3. The Android side of the same plugin DOES request permissions internally — this is a platform asymmetry bug in the plugin
4. Previously, permission was granted on the very first install and persisted across all subsequent `flutter run` deploys — until the app was deleted

**Solution:** Add explicit camera permission request using `permission_handler`:

1. Add dependency in `pubspec.yaml`:
   ```yaml
   permission_handler: ^11.3.1
   ```

2. Add iOS Podfile macro (required for `permission_handler` to compile camera permission code):
   ```ruby
   # In post_install block:
   target.build_configurations.each do |config|
     config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
       '$(inherited)',
       'PERMISSION_CAMERA=1',
     ]
   end
   ```

3. Request permission before rendering `YOLOView`:
   ```dart
   import 'package:permission_handler/permission_handler.dart';

   bool _cameraReady = false;

   Future<void> _requestCameraPermission() async {
     final status = await Permission.camera.request();
     if (!mounted) return;
     if (status.isGranted) {
       setState(() => _cameraReady = true);
     }
   }
   ```

4. Gate `YOLOView` on `_cameraReady` flag to prevent rendering before permission is granted.

5. Run `pod install` in `ios/` directory after adding the dependency.

**Why it worked before without this fix:** Permission was granted once on the original install and iOS remembered it across every `flutter run`. Deleting the app broke this chain.

---

## ISSUE-004: CocoaPods `pod install` Fails with UTF-8 Encoding Error

**Date:** 2026-03-11
**Platform:** macOS (Apple M5)
**Symptom:** `pod install` crashes with `Encoding::CompatibilityError: Unicode Normalization not appropriate for ASCII-8BIT`

**Root Cause:** Terminal session locale is not set to UTF-8. Ruby 4.0 / CocoaPods 1.16.2 requires UTF-8 encoding.

**Solution:** Set locale before running pod install:
```bash
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
pod install
```

**Prevention:** Add to `~/.zshrc`:
```bash
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
```

---

## ISSUE-005: Android Trail Coordinates Mirrored/Offset in Landscape

**Date:** 2026-02-25
**Platform:** Android (Galaxy A32)
**Symptom:** Ball trail dots appear at wrong positions — mirrored or offset from actual ball location in landscape mode.

**Root Cause:** `ultralytics_yolo` returns `normalizedBox` coordinates without accounting for Android display rotation. In landscape-left (rotation=1) coordinates are correct, but in landscape-right (rotation=3) they need `(1-x, 1-y)` flip.

**Solution:** MethodChannel polling of `Surface.ROTATION_*` from `MainActivity.kt` + coordinate flip:
```dart
// In MainActivity.kt: MethodChannel returns Display.rotation
// In Dart:
if (_androidDisplayRotation == 3) {
  dx = 1.0 - dx;
  dy = 1.0 - dy;
}
```

**Note:** iOS handles rotation in the plugin layer — this fix is Android-only.

---

## ISSUE-006: Camera Aspect Ratio Mismatch (~10% Y-Offset on iOS)

**Date:** 2026-02-23
**Platform:** iOS (iPhone 12)
**Symptom:** Trail dots consistently offset by ~10% vertically from actual ball position.

**Root Cause:** Code assumed 16:9 camera aspect ratio, but `ultralytics_yolo` uses `.photo` session preset on iOS which outputs 4032x3024 (4:3).

**Solution:** Changed `YoloCoordUtils` camera aspect ratio from 16:9 to 4:3. All FILL_CENTER crop calculations updated accordingly.

---

## ISSUE-007: Stale Extrapolation Causes False HIT Results

**Date:** 2026-03-09
**Platform:** Both
**Symptom:** Ball on the left side of the goal (far from calibrated target on the right) still produces a false HIT at zone 3.

**Root Cause:** `ImpactDetector._onBallDetected()` had `if (extrapolation != null) _bestExtrapolation = extrapolation;` — only updated when non-null. A stale extrapolation from an earlier frame (when the ball briefly headed toward the target) persisted after the ball changed direction.

**Solution:** Changed to `_bestExtrapolation = extrapolation;` (always use latest, including null). When trajectory no longer intersects the target, the stale value is cleared.

---

## ISSUE-008: Audio "MISS" Not Playing / Playing Wrong Zone

**Date:** 2026-03-09
**Platform:** Both
**Symptom:** MISS audio sometimes doesn't play, or plays the previous zone's audio instead of "miss".

**Root Cause:** `AudioPlayer` retains its previous source state. Calling `play()` with a new source while the previous source is still loaded can cause race conditions.

**Solution:** Call `stop()` before `play()` in `AudioService` to ensure clean player state when switching between different audio sources.

---

## ISSUE-010: Back Button Blocked During Reference Capture Sub-Phase

**Date:** 2026-03-13
**Platform:** Both (iOS and Android)
**Symptom:** After tapping all 4 calibration corners, the back button (top-left arrow) stops responding. User cannot go back to home screen until the full calibration is completed (ball detection + confirm).

**Root Cause:** The full-screen `GestureDetector` for calibration corner taps (`LayoutBuilder` + `GestureDetector` + `SizedBox.expand()`) was conditionally shown with `if (_calibrationMode)`. After 4 corners are placed, `_calibrationMode` is still `true` (it only becomes `false` after confirming reference capture). This full-screen touch handler sits above the back button in the Stack z-order, intercepting all taps.

**Solution:** Narrowed the condition to `if (_calibrationMode && !_awaitingReferenceCapture)`. The full-screen tap handler is now only present while corners are actively being collected (0-3 corners). Once all 4 corners are placed and the reference capture sub-phase begins, the tap handler is removed from the widget tree, allowing the back button to receive taps again.

**Verified:** 81/81 tests passing. Back button works in all states: before calibration, during reference capture, after calibration, during tracking/results.

---

## ISSUE-012: Impact Detection Fails on 9/10 Real Soccer Ball Kicks

**Date:** 2026-03-17
**Platform:** Both (iOS iPhone 12, Android Realme 9 Pro+)
**Symptom:** Only 1 out of 10 real soccer ball kicks correctly detected as HIT. Remaining 9 showed "No result" or "reset". Trail dots and extrapolation visually showed correct ball path, but decision pipeline rejected.

**Root Causes (3 compounding issues identified via terminal diagnostic logs):**

1. **`minTrackingFrames = 8` too high (60% of failures):** Fast kicks complete flight in 6-9 frames at 30fps. Ball tracked for only 1-7 frames → rejected as "insufficient frames". Literature consensus (Hawk-Eye, TrackNet, Kamble survey of 50+ papers): minimum should be 3 frames for Kalman velocity convergence.

2. **Depth ratio filter blocks valid hits (20% of failures):** `minDepthRatio = 0.3` rejected ratios of 0.2735 and 0.1886 — balls that reached the wall depth but appeared smaller due to motion blur reducing bbox size. No published single-camera ball tracking system uses bbox area ratio as a depth gate. Already covered by trajectory extrapolation.

3. **`_bestExtrapolation` overwritten with null (10% of failures):** Despite 159 tracking frames and valid depth ratio, extrapolation was null because line 187 overwrites unconditionally. Valid prediction from frame 100 destroyed when frame 159 returned null. Additionally, extrapolation not recomputed during occlusion using Kalman state.

4. **Gravity overshoot in extrapolator (wrong zone):** `gravity = 0.001` with `t = 30` frames adds 0.45 to Y — nearly half frame height. Caused zone 4 hit to be reported as zone 3.

**Solution:** ADR-047 — 4 evidence-backed fixes. See `activeContext.md` for full research citations.

**Fixes implemented (2026-03-17):**
- ✅ Fix 1: `minTrackingFrames` 8→3 in `impact_detector.dart`
- ✅ Fix 2: Depth ratio filter disabled in `impact_detector.dart` (diagnostic logging preserved)
- ✅ Fix 3: Extrapolation retained during occlusion in `impact_detector.dart` + recomputed from Kalman state in `live_object_detection_screen.dart`
- ⏳ Fix 4: Gravity/maxFrames in `trajectory_extrapolator.dart` — DEFERRED

**Post-fix results:** iOS indoor test: 4/6 correct HITs (67%), up from 1/10 (10%). Fix 2 directly saved 2 detections. 2 remaining failures had only 1 tracking frame.

**Additional fix already applied:** `confidenceThreshold: 0.25` added to `YOLOView` (was plugin default 0.5). Plugin source verified: Dart layer at `yolo_controller.dart:12` overrides native iOS default of 0.25.

---

## ISSUE-009: Rotate Overlay Text Appears Upside Down in Portrait

**Date:** 2026-03-10
**Platform:** iOS (iPhone 12)
**Symptom:** The "Rotate your device" overlay text and icon appear upside down when holding phone in portrait.

**Root Cause:** Used `Transform.rotate(pi/2)` but the UI is locked to landscape, so content needs to be rotated the opposite direction to read upright in portrait.

**Solution:** Changed to `Transform.rotate(-pi/2)`. Device-verified.

---

## ISSUE-011: iOS Draggable Corners Not Working (Hit Radius Too Small)

**Date:** 2026-03-14
**Platform:** iOS (iPhone 12)
**Symptom:** Draggable calibration corners worked perfectly on Android but not on iOS. Only 1 of 4 corners could occasionally be dragged, and only after multiple attempts. Not smooth.

**Initial Misdiagnosis:** iOS `UiKitView` platform view gesture recognizers competing with Flutter's `PanGestureRecognizer` during the `kTouchSlop` ambiguity window. Research revealed Flutter issue #57931 (PlatformView pan interruption) was fixed in Flutter engine v1.21+, and the project uses Flutter 3.38 — so this was NOT the root cause.

**Diagnostic Approach:** Added temporary DIAG-DRAG prints to `onPanStart` to log:
1. Whether the callback fires at all
2. The touch position (local + normalized) and corner positions
3. Hit-test result (nearest index + distances to each corner)

**Diagnostic Findings:**
- `onPanStart` fires EVERY TIME on iOS — no gesture arena competition
- `_findNearestCorner()` returns `null` every time because all distances exceed the `0.04` threshold
- Closest attempt was distance `0.0408` (just `0.0008` over the `0.04` threshold)
- Distances ranged from `0.0408` to `0.0851`

**Root Cause:** `_dragHitRadius = 0.04` was too small. Flutter's `kTouchSlop` (~18px) shifts the reported `onPanStart` position ~0.05-0.08 away from where the user intended to touch. On iOS with a 4:3 camera feed, this shift in normalized space consistently exceeded the 0.04 threshold. Android was less affected because its `kTouchSlop` behavior differed slightly (or the user's finger was incidentally closer to corners during testing).

**Solution:** Increased `_dragHitRadius` from `0.04` to `0.09` (~9% of frame in normalized space). This covers all observed distances with margin. Removed DIAG-DRAG diagnostic prints after diagnosis.

**Lesson:** When platform-specific touch behavior differs, add diagnostic instrumentation before assuming gesture system bugs. The `kTouchSlop` offset is a known Flutter behavior that affects all `GestureDetector` pan callbacks, but its impact in normalized coordinate space depends on screen resolution and camera aspect ratio.

---

## ISSUE-013: Finger Occlusion Makes Corner Dragging Imprecise on Both Platforms

**Date:** 2026-03-19
**Platform:** Both (iOS iPhone 12, Android Realme 9 Pro+)
**Symptom:** During real-world field testing, user cannot precisely align calibration corners with goalpost corners because: (1) 60px offset cursor causes corner to jump far from its position on initial tap — bottom corners become unreachable due to limited screen space, (2) solid green filled circle hides the crosshair intersection point where precise alignment is needed.

**Root Cause (two sub-issues):**
1. `_dragVerticalOffsetPx = 60.0` is too large — on a phone in landscape, 60px is a significant portion of the screen height. When tapping a bottom corner, the corner jumps up 60px, and the user must drag downward to bring it back, but there's almost no screen space below the finger.
2. `CalibrationOverlay._paintCornerMarkers()` draws a solid filled circle (radius 8px) on top of the crosshair intersection, completely obscuring the precision alignment point.

**Solution:**
1. Reduced `_dragVerticalOffsetPx` from 60.0 to 30.0 (user tested 15px first — too subtle; 30px confirmed good on both platforms)
2. Removed `fillPaint` and `canvas.drawCircle(pixel, 8.0, fillPaint)` — corners are now hollow green rings (stroke only, radius 10px) always, not just during drag

**Verified:** 81/81 tests passing. Device-verified on iPhone 12 and Realme 9 Pro+.

---

## ISSUE-016: Result Overlay Stuck on Screen Forever After KickDetector Integration

**Date:** 2026-03-23
**Platform:** iOS (iPhone 12)
**Symptom:** After a kick result is shown (zone number or MISS), the overlay never clears. It stays on screen indefinitely and the app never returns to "Ready — waiting for kick".

**Root Cause:** `ImpactDetector`'s 3-second result display timeout lived inside `processFrame()`. After KickDetector integration, `processFrame()` was gated behind `_kickDetector.isKickActive`. Once a result fires, the kick completes → `isKickActive=false` → `processFrame()` never called again → timeout never checked → overlay stuck forever.

**Solution:** Added `tickResultTimeout()` method to `ImpactDetector`:
```dart
void tickResultTimeout() {
  if (_phase != DetectionPhase.result) return;
  if (_resultTimestamp != null &&
      DateTime.now().difference(_resultTimestamp!) >= resultDisplayDuration) {
    _reset();
  }
}
```
Called every frame in `live_object_detection_screen.dart` outside the kick gate:
```dart
_impactDetector.tickResultTimeout(); // Always — outside kick gate
if (_kickDetector.isKickActive) { ... }
```

**Verified:** Fixed in code (2026-03-23). Awaiting device re-test.

---

## ISSUE-017: Share Log Broken on iOS 26.3.1 (sharePositionOrigin Enforcement)

**Date:** 2026-03-23
**Platform:** iOS (iPhone 12, iOS 26.3.1)
**Symptom:** Tapping "Share Log" button crashes with:
```
PlatformException(error, sharePositionOrigin: argument must be set,
{{0,0},{0,0}} must be non-zero and within coordinate space of source view: {{0,0},{844,390}}, null, null)
```

**Root Cause:** iOS 26.3.1 now enforces `sharePositionOrigin` must be a non-zero `Rect` within screen bounds when calling `Share.shareXFiles` in landscape mode. The existing `_shareLog()` call passed no `sharePositionOrigin`, which defaults to `Rect.zero`. iOS 26.3.1 started rejecting this.

**Note:** Hardcoding coordinates (e.g., `Rect.fromLTWH(12, 60, 90, 28)`) was considered and rejected — breaks on different screen sizes and orientations.

**Solution:** Used `GlobalKey` + `RenderBox` to derive the button's actual position at tap time:
```dart
final _shareButtonKey = GlobalKey(); // field on state class

// In _shareLog():
final box = _shareButtonKey.currentContext?.findRenderObject() as RenderBox?;
final origin = box != null ? box.localToGlobal(Offset.zero) & box.size : Rect.zero;
await Share.shareXFiles([XFile(path)], subject: 'Flare Diagnostic Log',
    sharePositionOrigin: origin);
```
`key: _shareButtonKey` attached to the share button's `Container` widget. Works on any screen size, orientation, and device.

**Verified:** Fixed in code (2026-03-23). Awaiting device re-test.

---

## ISSUE-018: Off-by-One Between KickDetector and ImpactDetector (Ball-Loss Path Never Fires)

**Date:** 2026-03-23
**Platform:** Both
**Symptom:** When a kick completes with ball loss (ball disappears into the target zone), ImpactDetector never makes a decision. The kick gate closes on the same frame ImpactDetector would have triggered.

**Root Cause:** `KickDetector.maxActiveMissedFrames = 5` equals `ImpactDetector.lostFrameThreshold = 5`. On the 5th consecutive missed frame:
1. `KickDetector.processFrame()` calls `onKickComplete()` → `isKickActive = false`
2. Screen's `if (_kickDetector.isKickActive)` check is now false
3. `ImpactDetector.processFrame()` is NOT called for the 5th frame
4. `ImpactDetector._lostFrameCount` reaches only 4 (not 5), so `_makeDecision()` never fires

**Effect:** Kick 3 in field test (ball hit around zone 7 intersection) was completely missed — the ball disappeared into the target and the app never triggered.

**Proposed Fix:** Change `maxActiveMissedFrames` from 5 to 8 in `kick_detector.dart`. This gives ImpactDetector enough frames to hit its own threshold before the kick gate closes. The extra 3 frames (100ms at 30fps) of tolerance does not cause meaningful false detections since the refractory period follows immediately.

**Status:** Identified. Pending user approval. Not yet fixed.

---

## ISSUE-015: Trajectory Extrapolation Predicts Wrong Zone Numbers

**Date:** 2026-03-20
**Platform:** Both (iOS iPhone 12, Android Realme 9 Pro+)
**Symptom:** iOS: Extrapolation consistently predicts wrong zones (e.g., predicts zone 8, ball actually hits zone 5). The extrapolation dots form correctly showing the predicted trajectory, but the prediction diverges from actual ball path. Android: Completely unable to detect any hits at all.

**Root Cause (iOS — wrong zones):** Trajectory extrapolation amplifies small angular errors in the Kalman velocity estimate quadratically over 30+ frames. A 2-degree error at mid-flight, extrapolated over 30 frames at 6m distance, shifts the predicted impact by ~210mm — more than half a zone width (196mm per third). The gravity term (`0.5 * 0.001 * t²`) compounds this by adding up to 0.45 to Y over 30 frames.

**Root Cause (Android — no detections):** TFLite inference on Snapdragon 695 is ~4-8x slower than CoreML on A14 Bionic (~50ms vs ~6ms per frame). The `ultralytics_yolo` plugin uses `STRATEGY_KEEP_ONLY_LATEST` backpressure on Android, dropping 50-70% of camera frames. During a 250ms kick, Android gets only 1-2 detection frames (vs 6-8 on iOS), often below `minTrackingFrames=3`.

**Solution:** ADR-051 — Depth-verified direct zone mapping. Re-enabled depth ratio as a "trust qualifier": when ball's camera position maps to a zone AND depth ratio confirms near-wall depth (ratio within [0.3, 1.5]), that zone takes priority over trajectory extrapolation. `maxDepthRatio` tightened from 2.5 to 1.5.

**Verified:** 81/81 tests passing. Pending outdoor device verification.

---

## ISSUE-014: Detection Pipeline Fires Before Calibration (False MISS/noResult During Setup)

**Date:** 2026-03-19
**Platform:** Both (iOS iPhone 12, Android Realme 9 Pro+)
**Symptom:** Immediately after tapping "Start Detection" and entering the camera screen, orange trail dots appear for any detected ball, "Ball lost" badge flickers, and false MISS/noResult announcements fire — even though the user hasn't calibrated or confirmed the reference ball yet.

**Root Cause:** The `onResult` callback fed YOLO detections unconditionally into `BallTracker.update()` and `BallTracker.markOccluded()` from camera open. The `ImpactDetector` was gated on `_zoneMapper != null` but this became true as soon as 4 corners were tapped (before reference ball confirm), allowing impact detection during the reference capture sub-phase.

**Solution:** Added `_pipelineLive` boolean gate (defaults `false`). Set `true` only in `_confirmReferenceCapture()`, reset to `false` in `_startCalibration()`. All tracker, extrapolation, and impact detector calls wrapped in `if (_pipelineLive)`. Exception: reference capture bbox area grab remains outside the gate (needed for "Ball detected" UI during Stage 3). Also added `_tracker.reset()` in `_startCalibration()` to clear trail dots on re-calibrate.

**Verified:** 81/81 tests passing. Device-verified on iPhone 12 and Realme 9 Pro+.
