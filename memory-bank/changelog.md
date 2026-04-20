# Changelog

> **⚠️ CRITICAL: NEVER run `git commit`, `git push`, `git init`, or any git write commands. This project has NO git repository. It is local-only by explicit developer decision. This rule is ABSOLUTE and has been violated in the past — do NOT repeat.**

## Anchor Rectangle Phase 1 — Tap-to-Lock + Back-Button Z-Order Fix + Audio Counter (2026-04-19)

### Summary
Implemented Phase 1 of the Anchor Rectangle feature — replaced the auto-pick-largest reference-capture heuristic with explicit player tap-to-select. Two-step UX retained (tap a red bbox → turns green → Confirm commits). All 12 design decisions agreed up front via the brainstorming skill and recorded in `memory-bank/anchor-rectangle-feature-plan.md`. Fixed two back-button z-order bugs discovered during review (one pre-existing in calibration mode, one Phase 1 regression in awaiting-reference-capture) with a single `Positioned` widget move. Added a per-episode counter + timestamp to the audio nudge stub so the 30 s grace + 10 s repeat cadence is verifiable from device logs alone while the real audio asset is deferred to Phase 5. iOS (iPhone 12) device verification passed end-to-end; Android (Realme 9 Pro+) pending.

### Modified Files
- **`lib/services/ball_identifier.dart`** — `setReferenceTrack(List<TrackedObject>)` → `setReferenceTrack(TrackedObject)`. Removed in-method filter/sort/take-largest block. Caller (screen) is now responsible for filtering and selecting the tapped track. Doc comment updated.
- **`lib/services/audio_service.dart`** — Added `_tapPromptCallCount` field, `resetTapPromptCounter()` method, and `playTapPrompt()` stub that prints `AUDIO-STUB #N: Tap the ball to continue (HH:MM:SS.mmm)`. Real audio asset is deferred to Phase 5.
- **`lib/screens/live_object_detection/live_object_detection_screen.dart`** —
  - New state: `_ballCandidates` (list of `(trackId, bbox)`), `_selectedTrackId` (int?), `_audioNudgeTimer` (Timer?).
  - `_ReferenceBboxPainter` refactored from single-bbox to multi-bbox with per-item red/green colour.
  - `onResult`: collects ALL ball-class tracked candidates, runs aliveness check on `_selectedTrackId`, drives State 1↔2 audio-timer transitions, `_referenceCandidateBboxArea` now mirrors the SELECTED track.
  - New `_findNearestBall` (mirrors `_findNearestCorner`) + `_handleBallTap` (Tap-2 rule, last-tap-wins).
  - New `_startAudioNudgeTimer` / `_cancelAudioNudgeTimer` (30 s grace + 10 s repeat, resets AudioService counter on start).
  - `onTapUp` added to existing GestureDetector alongside `onPanStart/Update/End` (Gesture-1: trust the gesture arena).
  - Prompt text extended to 3-state ternary (S1-a / "Tap the ball you want to use" / "Tap Confirm to proceed with selected ball").
  - `_confirmReferenceCapture` resolves `_selectedTrackId` → `TrackedObject` before calling the new `setReferenceTrack(track)` API. Bails safely on race-window disappearance.
  - `_startCalibration` (Recal-1): clears tap selection + cancels nudge timer. `dispose`: cancels nudge timer.
  - **Back button `Positioned` block moved** from early Stack position (line ~1015) to just before the rotate overlay. Z-order change only; visually identical. Closes ISSUE-031 (calibration-mode + awaiting-reference-capture back-button unreachability).
  - **Drive-by cleanup:** removed unused legacy field `_referenceCandidateBbox` (1 declaration + 2 dead `= null` writes).
- **`test/ball_identifier_test.dart`** — Rewrote 4 obsolete auto-pick-largest tests as 3 new contract tests for the new `setReferenceTrack(TrackedObject)` signature. Updated 14 other call sites from `[_track(...)]` to `_track(...)`. 18/18 tests in this file pass.
- **`memory-bank/anchor-rectangle-feature-plan.md`** — Phase 1 section rewritten with 12-row Resolved Decisions table, 4-state Player Flow walkthrough, corrected change-summary table, resolved open-questions section, design notes subsection.

### Verification
```
$ flutter analyze  -- 0 errors, 0 warnings, 85 infos
$ flutter test     -- 175/175 passing
```
Net test count −1 from 176: 4 obsolete auto-pick tests rewritten as 3 new contract tests.

### Device Test Results
- **iOS (iPhone 12) — PASSED 2026-04-19:** Phase 1 tap-to-lock flow end-to-end. Back button works in calibration mode, awaiting reference capture, and live pipeline.
- **Android (Realme 9 Pro+) — pending.**

### Related Artifacts
- **ISSUE-031** added to `issueLog.md` — back-button z-order bugs + fix
- **ADR-073** added to `decisionLog.md` — Phase 1 Anchor Rectangle tap-to-lock design (covers 12 design choices)
- **ADR-074** added to `decisionLog.md` — Back-button z-order via Stack re-ordering
- **ADR-075** added to `decisionLog.md` — Audio nudge stub with per-episode counter + timestamp for log-based verification

---

## Mahalanobis Area Ratio Fix + UI Refinements (2026-04-16)

### Summary
Fixed silent kicks caused by over-aggressive Mahalanobis rescue area ratio check (ISSUE-029). Three iterations tested: (1) relaxed Kalman threshold 3.5/0.3 — 4/5 kicks but false positive dots returned, (2) last-measured-area with tight 2.0/0.5 — 3/5 kicks (lower bound too tight), (3) last-measured-area with 2.0/0.3 — 5/5 kicks across 3 test runs. Also updated center crosshair to purple at 1.5 strokeWidth for visibility, repositioned calibrate button above tilt indicator, and re-enabled large result overlay.

### Modified Files
- **`lib/services/bytetrack_tracker.dart`** — `update()` and `_greedyMatch()` accept `lastMeasuredBallArea` optional parameter. Area ratio check uses last measured area (with Kalman fallback). Threshold: 2.0/0.3. All 3 `_greedyMatch` call sites updated.
- **`lib/screens/live_object_detection/live_object_detection_screen.dart`** — `_byteTracker.update()` passes `_ballId.lastBallBboxArea`. Calibrate button `bottom:16` → `bottom:48`. Large result overlay re-enabled.
- **`lib/screens/live_object_detection/widgets/calibration_overlay.dart`** — Center crosshair: white → purple, strokeWidth 0.5 → 1.5. Center circle: white → purple, strokeWidth 1.0 → 1.5.

### Verification
```
$ flutter analyze -- 0 errors, 0 warnings, 84 infos
$ flutter test -- 176/176 passing
```

### Monitor Test Results
- 5/5 kicks detected across 3 test runs ✅
- False positive dots still appearing during active kicks ❌ (open issue)
- Ground testing scheduled for 2026-04-17

---

## Session Lock + Protected Track + Trail Suppression + Mahalanobis Area Ratio (2026-04-15)

### Summary
Implemented manager's suggestions to eliminate false positive trail dots. Added session lock in BallIdentifier (blocks re-acquisition during kicks), protected track in ByteTrackTracker (60-frame survival for locked ball), bbox area ratio check on Mahalanobis rescue (rejects size-mismatched candidates >2x or <0.5x), and trail suppression during kick=idle. Monitor+video testing confirmed zero false positive dots but revealed 2/5 kicks going silent due to area ratio check being too aggressive during fast flight. Root cause: Kalman predicted area diverges during pure predictions, blocking legitimate rescues.

### Modified Files
- **`lib/services/ball_identifier.dart`** — Added `_sessionLocked` flag, `activateSessionLock()`, `deactivateSessionLock()`, `isSessionLocked` getter. Priority 2 and 3 wrapped with `!_sessionLocked` guard. New log message for locked re-acquisition skip. Reset clears lock.
- **`lib/services/bytetrack_tracker.dart`** — Added `protectedMaxLostFrames = 60`, `_protectedTrackId`, `setProtectedTrackId()`, `_effectiveMaxLost()`. Track removal uses `_effectiveMaxLost(t)` instead of `maxLostFrames`. Added bbox area ratio check (4 lines) before Mahalanobis rescue acceptance. Reset clears protected ID.
- **`lib/screens/live_object_detection/live_object_detection_screen.dart`** — Session lock activation after `_kickDetector.processFrame()`. Deactivation in both ACCEPT and REJECT decision paths. Trail visibility gated on `_kickDetector.state != KickState.idle`.

### Verification
```
$ flutter analyze -- 0 errors, 0 warnings, 84 infos
$ flutter test -- 176/176 passing
```

### Monitor Test Results
- 0 false positive dots (previously the main problem) ✅
- 2/5 kicks silent (area ratio too aggressive) ❌
- Session lock stuck permanently on bounce-back false kicks ❌

---

## Pre-ByteTrack AR Filter for False Positive Reduction (2026-04-13)

### Summary
Added a pre-ByteTrack aspect ratio filter to reject elongated YOLO false positives (torso/limb bboxes) before they enter the tracker. Detections with AR > 1.8 are rejected in `_toDetections()`. Also attempted and reverted Mahalanobis rescue validation (size ratio + velocity direction checks) — keeping one-change-at-a-time discipline. Debug bbox overlay disabled by developer for cleaner visual output.

### Modified Files
- **`lib/screens/live_object_detection/live_object_detection_screen.dart`** — Added AR > 1.8 reject in `_toDetections()` (2 lines). Debug overlay `_debugBboxOverlay` set to `false` by developer.
- **`lib/services/bytetrack_tracker.dart`** — Mahalanobis rescue validation added then reverted (net: no change from session start).

### Verification
```
$ flutter analyze -- 0 errors, 0 warnings, 81 infos
$ flutter test -- 176/176 passing
```

---

## ISSUE-027 Fix: Two-Way isStatic Classification via Sliding Window (2026-04-13)

### Summary
Fixed the one-way `isStatic` flag bug in ByteTrack's `_STrack` class. The flag was permanently set to `true` after 30 frames of low displacement and never cleared — causing BallIdentifier to reject the real ball track during re-acquisition after kicks. Also discovered a second bug: `isStatic` never re-triggered on subsequent stationary periods because the lifetime `_cumulativeDisplacement` accumulator retained displacement from previous movement. Both bugs fixed by replacing the accumulator with a sliding window (`ListQueue<double>`, capacity=30 frames). Research into ByteTrack/SORT/DeepSORT/OC-SORT/Norfair/Frigate NVR confirmed the approach is consistent with Frigate's production static object detection (the only tracker with static classification). Device-verified on iPhone 12.

### Modified Files
- **`lib/services/bytetrack_tracker.dart`** — Added `import 'dart:collection'`. Replaced `_cumulativeDisplacement` (double) with `_recentDisplacements` (`ListQueue<double>`). Added `_displacementWindowSize` field. `update()` pushes per-frame displacement to buffer with FIFO eviction. `evaluateStatic()` now two-way: sums window, sets `isStatic = recentTotal < maxDisp` when window is full.
- **`test/bytetrack_tracker_test.dart`** — Renamed `'static flag is permanent once set'` → `'static flag stays true with minor jitter'`. Added 3 new tests: `static → dynamic` transition, `dynamic → static` transition, `full cycle: static → kicked → lands → static again`.

### Verification
```
$ flutter analyze -- 0 errors, 0 warnings, 81 infos
$ flutter test -- 176/176 passing
```

---

## Calibration Diagnostics + Debug Bbox Overlay + Enhanced BallIdentifier Logging (2026-04-09)

### Summary
Added three diagnostic tools to identify root cause of inconsistent zone detection across calibrations. (1) Calibration geometry diagnostics log 15+ geometric parameters (corner positions, edge lengths, aspect ratio, perspective ratios, centroid, coverage, corner angles, homography matrix, zone centers in camera space) at every calibration event and pipeline start. (2) Debug bounding box overlay renders colored bboxes for all ball-class detections on screen (green=locked, yellow=candidate, red=lost) with trackId, bbox WxH, aspect ratio, confidence, isStatic flag. (3) Enhanced BallIdentifier logging shows all candidate tracks with full diagnostic info on re-acquisition/loss events. Debug overlay revealed three critical bugs: Mahalanobis rescue identity hijacking (ISSUE-026), isStatic one-way flag (ISSUE-027), and YOLO false positives on kicker body at high confidence.

### New Files
- **`lib/screens/live_object_detection/widgets/debug_bbox_overlay.dart`** (~110 lines) — CustomPainter rendering colored bounding boxes. Green=locked, Yellow=candidate, Red=lost. Shows trackId, bbox WxH, aspect ratio, confidence, isStatic, [LOCKED] label.

### Modified Files
- **`lib/screens/live_object_detection/live_object_detection_screen.dart`** — Added `_logCalibrationDiagnostics()` (~100 lines), `_debugBboxOverlay` toggle, `_debugBallClassTracks` state, DebugBboxOverlay widget in Stack, PIPELINE START diagnostic block at confirm. Import added for debug_bbox_overlay.dart.
- **`lib/services/ball_identifier.dart`** — Enhanced DIAG-BALLID logging: lost events show all candidates with bbox WxH, aspect ratio, velocity, static, state, confidence. Re-acquisition logs old→new trackId, bbox shape, reason. Rejection reason logging added.

### Verification
```
$ flutter analyze -- 0 errors, 0 warnings, 78 infos
$ flutter test -- 173/173 passing
```

---

## directZone Decision Logic + Diagnostic Improvements (2026-04-09)

### Summary
Overhauled ImpactDetector decision logic based on kick-by-kick video test analysis. Replaced WallPlanePredictor → depth-verified → extrapolation decision cascade with a single signal: last observed `directZone` (ball's actual position mapped through homography). Video test showed directZone correct 5/5 times while old cascade only announced 2/5. Also loosened KickDetector result gate to accept `confirming` (was `active` only), added `kickState` and `ballConfidence` to IMPACT DECISION diagnostic block, and surfaced YOLO `confidence` on `TrackedObject`.

### Modified Files
- **`lib/services/impact_detector.dart`** — Added `_lastDirectZone` field. Decision priority changed to: edge exit → last directZone → noResult. Removed WallPlanePredictor, depth-verified, and extrapolation from decision cascade. Removed `minTrackingFrames` gate (directZone is self-validating). Added `lastDirectZone` to DIAG print block. Velocity-drop trigger now also checks `_lastDirectZone`.
- **`lib/services/kick_detector.dart`** — `onKickComplete()` now accepts `confirming` state in addition to `active`.
- **`lib/screens/live_object_detection/live_object_detection_screen.dart`** — Result gate accepts `confirming` OR `active` (was `active` only). Added `kickState` and `ballConfidence` prints after IMPACT DECISION block fires.
- **`lib/services/bytetrack_tracker.dart`** — Added `confidence` field to `TrackedObject` class, passed through in `toPublic()`.
- **`test/impact_detector_test.dart`** — Rewrote all decision tests to use `directZone` instead of extrapolation. Added new test for "last directZone wins over earlier directZone" and "directZone cleared on reset". 22 tests (was 22, some renamed/restructured).
- **`test/ball_identifier_test.dart`** — Added `confidence` default to test helper.

### New Snapshot Files
- `memory-bank/snapshots/impact_detector_2026-04-09_pre_directzone.dart.bak`
- `memory-bank/snapshots/live_object_detection_screen_2026-04-09_pre_directzone.dart.bak`
- `memory-bank/snapshots/impact_detector_test_2026-04-09_pre_directzone.dart.bak`

### Verification
```
$ flutter analyze -- 0 errors, 0 warnings, 56 infos
$ flutter test -- 173/173 passing
```

---

## Camera Alignment Aids + Kick-State Gate Experiment (REVERTED) (2026-04-08)

### Summary
Added camera alignment aids (crosshair, tilt indicator, shape validation) to CalibrationOverlay — device-verified on iPhone 12. Attempted to gate ImpactDetector/WallPredictor behind KickDetector state to prevent phantom impact decisions during idle. This broke grounded kick detection (3/5 kicks undetected) and was fully reverted. Also attempted to gate trail dot addition on kick state (`kickEngaged` parameter on `BallIdentifier.updateFromTracks()`) to prevent false dots on non-ball objects — this killed all trail visualization and was also fully reverted. Both files restored to pre-experiment state. Code snapshots directory created at `memory-bank/snapshots/` for future pre-change backups.

### Modified Files
- **`lib/screens/live_object_detection/widgets/calibration_overlay.dart`** — Added `showCenterCrosshair` and `tiltY` parameters. Added `_paintCenterCrosshair()` (dashed white lines + center circle), `_drawDashedLine()` helper, `_paintTiltIndicator()` (spirit-level bubble), `_paintOffsetFeedback()` (shape validation with edge ratios + corner symmetry).
- **`lib/screens/live_object_detection/live_object_detection_screen.dart`** — Added accelerometer subscription (`sensors_plus`) at 10Hz for tilt indicator. CalibrationOverlay always rendered with `showCenterCrosshair` and `tiltY` params. **Kick-state gate on ImpactDetector/WallPredictor: ADDED THEN REVERTED.** ImpactDetector and WallPredictor run unconditionally every frame.
- **`lib/services/ball_identifier.dart`** — **`kickEngaged` parameter: ADDED THEN REVERTED.** Trail dots always added when ball is tracked. Restored original combined position+trail update structure.
- **`test/ball_identifier_test.dart`** — **`kickEngaged: true` args: ADDED THEN REVERTED.** Tests restored to original calls.

### New Files
- **`memory-bank/snapshots/`** — Directory for pre-change file backups. Contains snapshots of `ball_identifier.dart`, `live_object_detection_screen.dart`, `ball_identifier_test.dart` from mid-session.

### Verification
```
$ flutter analyze -- 0 errors, 0 warnings, 58 infos
$ flutter test -- 172/172 passing
```

### Lessons Learned
- Gating pipeline input on KickDetector state is too aggressive — KickDetector's jerk threshold doesn't fire for grounded shots. KickDetector should only gate result acceptance (audio), not pipeline processing.
- Trail gating on kick state treats the symptom (false dots) not the cause (wrong track identity). Root cause is BallIdentifier re-acquiring to non-ball objects.
- Without git, reverts are memory reconstructions that introduce new bugs. Code snapshots directory created as mitigation.

---

## Mahalanobis Matching + Device Testing Fixes (2026-04-06)

### Summary
Three rounds of device testing on iPhone 12 drove iterative fixes to the ByteTrack matching logic. Round 1: IoU-only matching lost ball during fast kicks (ISSUE-023). Round 2: Added Mahalanobis distance fallback using Kalman covariance — ball tracked through kicks and `directZone` populated for first time, BUT circle tracks also got Mahalanobis-rescued creating scattered false dots. Round 3: Restricted Mahalanobis to locked ball track only via `lockedTrackId` parameter. Also fixed `setReferenceTrack` rejecting stationary ball (was flagged static), added red bounding box overlay for reference capture confirmation, and added DIAG prints throughout.

### Modified Files
- **`lib/services/bytetrack_tracker.dart`** — Added `mahalanobisDistSq()` to `_Kalman8` (Mahalanobis distance using innovation covariance S). Replaced `_greedyMatch` with two-stage: Stage 1 pure IoU (unchanged), Stage 2 Mahalanobis restricted to `lockedTrackId` only. Added `lockedTrackId` parameter to `update()` and `_greedyMatch()`. Chi-squared threshold 9.488 (4 DOF, 95% confidence — statistical constant). DIAG-MATCH prints on Mahalanobis rescues.
- **`lib/services/ball_identifier.dart`** — Fixed `setReferenceTrack` to accept static tracks (ball stationary during calibration was flagged `isStatic=true`). Added DIAG-BALLID prints for track loss and re-acquisition events.
- **`lib/screens/live_object_detection/live_object_detection_screen.dart`** — Pass `lockedTrackId: _ballId.currentBallTrackId` to `_byteTracker.update()`. Added `_referenceCandidateBbox` field + `_ReferenceBboxPainter` CustomPainter for red bounding box during reference capture. Updated `_confirmReferenceCapture` and `_startCalibration` to manage bbox state.
- **`test/ball_identifier_test.dart`** — Updated `setReferenceTrack` test to expect static tracks accepted.

### Verification
```
$ flutter analyze -- 0 errors, 0 warnings, 58 infos
$ flutter test -- 172/172 passing
```

### Device Test Results (iPhone 12, 2026-04-06)
- **Round 1 (IoU only):** Shake test PASS (no circle dots). Kick test FAIL — 0/3 detected, ball track lost mid-flight.
- **Round 2 (Mahalanobis + IoU merged):** Ball tracked through kicks, `directZone` populated (zones 1-9 visible). BUT circle tracks also Mahalanobis-rescued → scattered dots on circles during kicks.
- **Round 3 (Mahalanobis locked-track-only):** Pending device test.

---

## ByteTrack Pipeline Implementation — Phases 1-3 (2026-04-05)

### Summary
Replaced the fragmented detection/tracking pipeline with a complete ByteTrack multi-object tracker (ADR-058). Field testing (2026-04-04) revealed that YOLO detects target circles as soccer balls (ISSUE-022), causing 38.9%/11.1% zone accuracy. Root cause: no object identity — every frame re-selected detections from scratch. Solution: ByteTrack with 8-state Kalman (cx,cy,w,h,vx,vy,vw,vh), two-pass IoU matching, BallIdentifier for automatic ball re-acquisition. Phases 1-3 complete (new services + integration). Phases 4-7 pending (cleanup, ImpactDetector simplification, DiagnosticLogger update, field testing).

### New Files
- **`lib/services/bytetrack_tracker.dart`** (~530 lines) — Complete ByteTrack algorithm. 8-state Kalman per track, two-pass IoU matching (high ≥0.5, low 0.25-0.5), track lifecycle (tracked/lost/removed), static track detection, greedy assignment. Pure Dart, no external dependencies.
- **`lib/services/ball_identifier.dart`** (~210 lines) — Identifies which ByteTrack track is the soccer ball. Lock-on during reference capture (largest bbox), automatic re-acquisition by motion (only moving ball-class track) or proximity to last known position. Manages trail history (ListQueue) with same data contract as old BallTracker for TrailOverlay compatibility.
- **`test/bytetrack_tracker_test.dart`** — 26 unit tests: IoU computation, single/multi-object tracking, two-pass matching, track lifecycle, static detection, Kalman prediction, reset, 9-circles-plus-ball scenario.
- **`test/ball_identifier_test.dart`** — 19 unit tests: reference capture, track following, re-acquisition, ball lost badge, trail format, velocity/smoothedPosition, reset.

### Modified Files
- **`lib/screens/live_object_detection/live_object_detection_screen.dart`** — Major rewrite of detection pipeline. Removed imports: `ball_tracker.dart`, `trajectory_extrapolator.dart`, `wall_plane_predictor.dart`. Added imports: `bytetrack_tracker.dart`, `ball_identifier.dart`. Replaced state fields: `_tracker`, `_extrapolator`, `_lastExtrapolation`, `_wallPredictor` → `_byteTracker`, `_ballId`, `_ballClassNames`. Replaced `_pickBestBallYolo()`, `_applyPhaseFilter()`, `_squaredDist()` with `_toDetections()` (class filter + Android coord correction on full bbox). Rewrote entire `onResult` callback: YOLO results → ByteTrack update → BallIdentifier → KickDetector/ImpactDetector. Updated `_startCalibration()`, `_confirmReferenceCapture()`, `dispose()`, trail overlay reference, ball lost badge reference.

### Files NOT YET Removed (Phase 4 pending)
- `lib/services/ball_tracker.dart` — no longer imported by live screen
- `lib/services/kalman_filter.dart` — no longer imported
- `lib/services/wall_plane_predictor.dart` — no longer imported
- `lib/services/trajectory_extrapolator.dart` — no longer imported
- Old test files still exist and pass independently

### Verification
```
$ flutter analyze -- 0 errors, 0 warnings, 55 infos
$ flutter test -- 172/172 passing
```

---

## WallPlanePredictor + Phase-Aware Filtering + Bug 3 Fix (2026-04-01)

### Summary
Root cause of zone accuracy Bug 3 identified: 2D homography only maps correctly for points ON the wall plane; mid-flight ball positions appear lower in the camera frame due to perspective, causing upper zones (6,7,8) to be reported as bottom zones (1,2). Built WallPlanePredictor service through 3 iterations (v1: hardcoded wallDepthRatio → v2: physical dimensions → v3: zero hardcoded params with iterative projection). Also added phase-aware detection filtering to suppress false YOLO detections on kicker body/head/wall patterns. Three field test sessions conducted: accuracy improved from 20% to 60% exact (80% within 1 zone).

### New Files
- **`lib/services/wall_plane_predictor.dart`** — Observation-driven 3D trajectory prediction. Accumulates per-frame (2D position, depth ratio) observations, converts to pseudo-3D, iteratively projects forward checking `pointToZone()` at each step. Wall discovered implicitly — zero physical dimensions assumed. Constructor takes only `opticalCenter` (calibration corner centroid).
- **`test/wall_plane_predictor_test.dart`** — 12 unit tests: insufficient observations, stationary ball, ball toward camera, ball approaching wall, 2-observation prediction, reset, depth estimation, zero-area rejection, perspective correction (zone shift upward), noisy depth tolerance, frame-exit trajectory, no-hardcoded-params verification.

### Modified Files
- **`lib/services/impact_detector.dart`** — Added `wallPredictedZone` optional param to `processFrame()` and `_onBallDetected()`. Added `_lastWallPredictedZone` field. Wall-predicted zone is highest-priority decision signal (above depth-verified, above extrapolation). Velocity-drop detection checks both `_lastWallPredictedZone` and `_lastDepthVerifiedZone`. DIAG print block includes `lastWallPredictedZone`. Reset clears `_lastWallPredictedZone`.
- **`lib/services/diagnostic_logger.dart`** — CSV header and `logFrame()` updated with 3 new columns: `wall_pred_zone`, `est_depth`, `frames_to_wall`. DECISION row padded to match.
- **`lib/screens/live_object_detection/live_object_detection_screen.dart`** — Import `wall_plane_predictor.dart`. Added `_wallPredictor` field. Initialized in `_confirmReferenceCapture()` with optical center from corner centroid. `addObservation()` called every detected frame during pipeline-live. `predictWallZone()` result passed to `_impactDetector.processFrame()` as `wallPredictedZone`. Predictor reset on calibration start, kick accept, and kick reject. Added `_applyPhaseFilter()` method: Ready phase confidence 0.50 + 10% spatial gate, Tracking phase confidence 0.25 + 15% spatial gate from Kalman prediction. DIAG-WALL per-frame prints during tracking. DIAG-WALL init print at calibration.

### Verification
```
$ flutter analyze -- 0 errors, 0 warnings, 28 infos (all avoid_print)
$ flutter test -- 106/106 passing
```

### Field Test Results (iPhone 12, 2026-04-01)
| Session | Exact Correct | Within 1 Zone | Massive Y Error |
|---------|--------------|----------------|-----------------|
| 1 (no WallPlanePredictor) | 1/5 (20%) | 1/5 (20%) | 3/5 |
| 2 (v1 hardcoded) | ~1/5 (20%) | ~2/5 (40%) | 0 |
| 3 (v3 zero hardcoded) | 3/5 (60%) | 4/5 (80%) | 0 |

---

## KickDetector + DiagnosticLogger + Bug Fixes (2026-03-23)

### Summary
Implemented the KickDetector 4-signal kick gate to prevent false ImpactDetector triggers from non-kick ball movement (dribbling, rolling). Added DiagnosticLogger for per-frame/per-decision CSV logging with Share Log export. Fixed Bug 1 (stuck overlay) via `tickResultTimeout()` outside the kick gate. Fixed Share Log broken on iOS 26.3.1 via `GlobalKey`-based dynamic `sharePositionOrigin`. First field test conducted on iPhone 12 (iOS 26.3.1) — 4/5 kicks partially working; Bug 2 (off-by-one) and Bug 3 (zone accuracy) identified for next session.

### New Files
- **`lib/services/kick_detector.dart`** — 4-state kick gate (idle/confirming/active/refractory). 4 signals: jerk gate, energy sustain, direction toward goal, refractory period. Plain Dart, no Flutter deps.
- **`test/kick_detector_test.dart`** — 13 unit tests: idle start, real kick detection, slow dribble, moderate dribble, kick away from goal, direction check skipped without goalCenter, speed drop, ball lost during confirming, onKickComplete→refractory, refractory ignores movement, full refractory period, ball lost in active, reset.
- **`lib/services/diagnostic_logger.dart`** — Per-frame + per-decision CSV logger. Singleton. Writes to app Documents directory. `start()` / `logFrame()` / `logDecision()` / `stop()` API.

### Modified Files
- **`lib/services/impact_detector.dart`** — Added `tickResultTimeout()` public method. Checks result display expiry every frame. Solves stuck overlay when called outside kick gate.
- **`lib/services/diagnostic_logger.dart`** — Added `kick_confirmed` (1/0) and `kick_state` (idle/confirming/active/refractory) columns to CSV header and `logFrame()` signature.
- **`lib/screens/live_object_detection/live_object_detection_screen.dart`** — Added `_kickDetector = KickDetector()`, `_shareButtonKey = GlobalKey()`, `_goalCenter` getter (`_homography!.inverseTransform(Offset(0.5, 0.5))`). ImpactDetector gated behind `_kickDetector.isKickActive`. `tickResultTimeout()` called every frame outside gate. `onKickComplete()` called when ImpactDetector transitions to result. `_shareLog()` now passes `sharePositionOrigin: box.localToGlobal(Offset.zero) & box.size`. DiagnosticLogger `logFrame()` call updated with `kick_confirmed` and `kick_state` params.
- **`pubspec.yaml`** — Added `path_provider: ^2.1.3`, `share_plus: ^10.0.0`.

### Verification
```
$ flutter analyze -- 0 errors, 0 warnings, 21 infos (all avoid_print)
$ flutter test -- 94/94 passing
```

---

## Depth-Verified Direct Zone Mapping — ADR-051 (2026-03-20)

### Summary
Real-world outdoor testing showed trajectory extrapolation gives wrong zone numbers (e.g., predicts zone 8, ball hits zone 5) because mid-flight angular errors are amplified over 30+ frames. Android couldn't detect any hits at all. Four parallel research agents confirmed no commercial single-camera system uses long-range trajectory extrapolation for zone determination. Solution: re-enabled depth ratio as a "trust qualifier" — when ball's camera position maps to a zone AND depth ratio confirms near-wall depth, that zone takes priority over extrapolation. Extrapolation remains as fallback.

### Changes
- **`impact_detector.dart`**: Added `_lastDepthVerifiedZone` field, `directZone` parameter on `processFrame()` and `_onBallDetected()`. In `_onBallDetected`: when `directZone != null` AND depth ratio within `[0.3, 1.5]`, stores zone. In `_makeDecision()`: depth-verified zone preferred over extrapolation. Cleared in `_reset()`. `maxDepthRatio` changed from 2.5 to 1.5.
- **`live_object_detection_screen.dart`**: Added `directZone: _zoneMapper!.pointToZone(rawPosition)` to `processFrame()` call.
- **Decision priority**: Edge exit (MISS) → Depth-verified direct zone (HIT) → Extrapolation fallback (HIT) → noResult.
- **Research**: 4 parallel agents searched academic papers, GitHub, patents, app implementations. All converged: "last detected position near target" > "trajectory extrapolation" for zone accuracy.

### Verification
```
$ flutter analyze -- 0 errors, 0 warnings, 20 infos (all avoid_print)
$ flutter test -- 81/81 passing
```

---

## Audio Upgrade — Celebratory HIT Audio with Crowd Cheer (2026-03-19)

### Summary
Upgraded HIT audio from plain number callouts ("Seven") to celebratory announcements ("You hit seven!" + crowd cheer, ~4.7s each). Manager requested celebratory audio so players get immediate positive feedback on hits. Generated via macOS TTS (Samantha voice, rate 170) + Pixabay crowd cheer SFX (3.8s trim with 0.8s fade-out), composited with ffmpeg `filter_complex` concatenation. Drop-in replacement of `zone_1.m4a` through `zone_9.m4a` — zero code changes to `AudioService` or any other file. MISS audio (`miss.m4a`) unchanged. Original audio files backed up to `assets/audio/originals/`.

### Changes
- **9 audio files replaced** (`assets/audio/zone_1.m4a` through `zone_9.m4a`) — each contains TTS speech + 0.15s silence + crowd cheer with fade-out
- **TTS generation:** `say -v "Samantha" -r 170 "You hit [number]!"` — natural Samantha voice at slightly slower rate
- **Cheer SFX:** Pixabay "Crowd Cheer and Applause" (free commercial license, no attribution required), trimmed to 3.8s with `afade=t=out:st=3.0:d=0.8`
- **Compositing:** `ffmpeg -filter_complex "[0:a][1:a][2:a]concat=n=3:v=0:a=1[out]"` — speech + silence + cheer concatenated
- **zsh 1-based array fix:** Initial generation had off-by-one error (zone_1 said "You hit" with no number, zone_2 said "You hit one"). Fixed by using zsh native 1-based indexing (`${names[$i]}` instead of `${numbers[$i-1]}`)
- **Originals backed up** to `assets/audio/originals/` for potential revert

### Verification
```
$ flutter analyze -- 0 errors, 0 warnings, 18 infos (all avoid_print)
$ flutter test -- 81/81 passing
Device-verified on iPhone 12 and Realme 9 Pro+
```

---

## Pipeline Gating Fix — `_pipelineLive` Boolean (2026-03-19)

### Summary
Fixed premature pipeline activation where the detection pipeline (tracker, trail dots, "Ball lost" badge, impact detection, audio) ran immediately on camera open, before calibration. This caused false MISS/noResult announcements and unwanted orange dots during setup. Added a single `_pipelineLive` boolean gate enforcing 4 clear stages: Preview (silent) → Calibration (silent) → Reference Capture (bbox only) → Live (full pipeline).

### Changes
- **Added `_pipelineLive` boolean** (`live_object_detection_screen.dart:103`) — defaults to `false`, set `true` only in `_confirmReferenceCapture()`, reset to `false` in `_startCalibration()`
- **Gated tracker + extrapolation** — `_tracker.update()`, `_tracker.markOccluded()`, and extrapolation wrapped in `if (_pipelineLive)`
- **Gated impact detector** — `if (_zoneMapper != null)` changed to `if (_pipelineLive)`
- **Added `_tracker.reset()`** in `_startCalibration()` to clear trail dots on re-calibrate

### Verification
```
$ flutter analyze -- 0 errors, 0 warnings, 18 infos (all avoid_print)
$ flutter test -- 81/81 passing
Device-verified on iPhone 12 and Realme 9 Pro+
```

---

## Finger Occlusion Fix for Calibration Corner Dragging (2026-03-19)

### Summary
Fixed finger occlusion problem during calibration corner dragging. Real-world field testing revealed two issues: (1) 60px offset cursor caused excessive jump on tap, making bottom corners unreachable, (2) solid green dot hid crosshair intersection point. Exhaustive research (8 agents, 22 pub.dev keyword searches, 4 packages inspected) confirmed no existing Flutter package solves finger occlusion over camera platform views. Implemented offset cursor (30px) + hollow ring markers + crosshair lines.

### Changes
- **Corner markers changed to hollow green rings** (`calibration_overlay.dart`) — Removed `fillPaint` + `drawCircle(pixel, 8.0, fillPaint)`. Kept only stroked ring at radius 10px. Applied everywhere, not conditional on drag state.
- **Drag offset reduced from 60px to 30px** (`live_object_detection_screen.dart:96`) — User tested: 60px too jarring (bottom corners unreachable), 15px too subtle, 30px correct. Single constant: `_dragVerticalOffsetPx = 30.0`.
- **Crosshair lines** — Already existed from prior session. White 0.7 opacity, 0.5px strokeWidth, full screen width/height through active corner. Drawn in `CalibrationOverlay._paintCrosshair()`.

### Research Conducted
- 8 parallel research agents investigated: Flutter built-in Magnifier/RawMagnifier, Draggable/LongPressDraggable/InteractiveViewer, iOS/Android native occlusion patterns
- 22 pub.dev keyword searches across all relevant terms
- 4 packages source-code inspected: `flutter_quad_annotator` (requires static ui.Image), `flutter_magnifier_lens` (Fragment Shaders, Flutter 3.41+ incompatible), `flutter_magnifier` (BackdropFilter), `flutter_image_perspective_crop` (static Uint8List)
- All rejected: platform views (camera preview) are invisible to Flutter's compositing pipeline

### Verification
```
$ flutter analyze -- 0 errors, 0 warnings, 18 infos (all avoid_print)
$ flutter test -- 81/81 passing
Device-verified on iPhone 12 and Realme 9 Pro+
```

---

## ADR-047 Impact Detection Pipeline Fixes 1-3 (2026-03-17)

### Summary
Implemented three evidence-backed fixes to the impact detection pipeline (ADR-047). Real-world iOS testing improved hit detection rate from 1/10 (10%) to 4/6 (67%). Fix 4 (gravity/maxFrames in trajectory extrapolator) deferred for separate discussion. Outdoor real-world test on both devices scheduled for 2026-03-18.

### Changes
- **Fix 1: `minTrackingFrames` 8→3** (`impact_detector.dart`) — Single constant change. Research basis: Kalman filter velocity converges after 3-4 measurements (Bar-Shalom 2001). Fast kicks complete flight in 6-9 frames; old threshold of 8 rejected 60% of valid kicks.
- **Fix 2: Depth ratio filter disabled** (`impact_detector.dart`) — Depth ratio gate no longer blocks decisions. Diagnostic logging preserved. No published single-camera ball tracking system uses bbox area ratio as a depth gate.
- **Fix 3: Extrapolation retained during occlusion** (`impact_detector.dart` + `live_object_detection_screen.dart`) — `_onBallMissing()` now accepts and retains extrapolation during occlusion. Live screen recomputes extrapolation during ball-lost frames using Kalman-predicted state.
- **3 unit tests updated** — `minTrackingFrames` threshold test reduced from 5 to 2 frames; 2 depth filter tests updated to expect `hit` instead of `noResult`.
- **iOS indoor test (shoot-out video):** 4/6 correct HITs. Fix 2 directly saved 2 detections that would have been BLOCKED. 2 remaining failures: both had only 1 tracking frame (very fast kicks, YOLO caught ball once).

### Verification
```
$ flutter analyze -- 0 errors, 0 warnings, 17 infos (all avoid_print from diagnostic statements)
$ flutter test -- 81/81 passing
```

---

## Draggable Calibration Corners Implementation + iOS Hit Radius Fix (2026-03-14)

### Summary
Implemented the draggable calibration corners feature (ADR-046) and resolved an iOS-specific hit radius issue where `_dragHitRadius = 0.04` was too small due to `kTouchSlop` offset. Diagnosed via DIAG-DRAG prints, confirmed `onPanStart` fires on iOS but `_findNearestCorner` returned null because touch distances (0.0408-0.0851) exceeded the 0.04 threshold. Increased to `_dragHitRadius = 0.09`. Device-verified on both iPhone 12 and Galaxy A32.

### Changes
- **Draggable corners implemented** -- Added `_draggingCornerIndex` state, `_dragHitRadius = 0.09`, `_recomputeHomography()` helper (extracted from `_handleCalibrationTap`), `_findNearestCorner()` hit-test method, and `GestureDetector` with `onPanStart`/`onPanUpdate`/`onPanEnd` during `_awaitingReferenceCapture`. ~35 lines added to `live_object_detection_screen.dart`.
- **iOS hit radius fix** -- Initial `_dragHitRadius = 0.04` was too small on iOS. Diagnostic prints confirmed `onPanStart` fires every time but nearest corner distances (0.0408-0.0851) exceeded the threshold. Root cause: `kTouchSlop` (~18px) shifts the reported `onPanStart` position ~0.05-0.08 from where the user intended to touch. Increased radius from 0.04 to 0.09. DIAG prints removed after diagnosis.
- **ADR-047** -- Documents the hit radius tuning decision.
- **ISSUE-011** -- Documents the iOS drag hit radius too small issue.

### Verification
```
$ flutter analyze -- 0 errors, 0 warnings, 0 infos
$ flutter test -- 81/81 passing
Device-verified on iPhone 12 and Galaxy A32
```

---

## Back Button Fix During Calibration + Draggable Corners Decision (2026-03-13)

### Summary
Fixed a bug where the back button was unresponsive during the reference capture sub-phase of calibration (after tapping 4 corners, before confirming ball detection). Also discussed and decided the approach for draggable calibration corners (not yet implemented). Two new ADRs added (ADR-045, ADR-046).

### Changes
- **Back button fix** -- The full-screen GestureDetector for calibration corner taps was blocking the back button even after all 4 corners were placed. Changed condition from `if (_calibrationMode)` to `if (_calibrationMode && !_awaitingReferenceCapture)` so the tap handler is only active while corners are being collected. Back button now works during the ball detection confirm step.
- **ADR-045** -- Documents the back button fix decision.
- **ADR-046** -- Documents the draggable calibration corners approach decision. Evaluated 4 options: (1) GestureDetector `onPanStart`/`onPanUpdate`, (2) `box_transform` package, (3) magnified view, (4) smart rectangle correction. Option 1 chosen for simplicity, zero dependencies, and ability to handle perspective-distorted quadrilaterals. Not yet implemented.

### Verification
```
$ flutter analyze -- 0 errors, 0 warnings, 0 infos
$ flutter test -- 81/81 passing
```

---

## UI Cleanup + Camera Permission Fix (2026-03-11)

### Summary
Removed AppBar from detection screen, replaced YOLO text badge with circular back button, and added explicit camera permission handling via `permission_handler`. Created `issueLog.md` with 9 historical issues. Device-verified on both iPhone 12 and Galaxy A32. 81/81 tests passing.

### Changes
- **AppBar removed** -- Scaffold no longer has `appBar`. Camera preview fills full screen height in landscape (~56px reclaimed).
- **Back button badge** -- Circular back arrow icon (40x40, `Colors.black54`, `BorderRadius.circular(20)`) at `Positioned(top:12, left:12)`. `GestureDetector` + `Navigator.of(context).pop()`. Replaces YOLO text badge (redundant since YOLO is the only backend).
- **`DetectorConfig` import removed** from `live_object_detection_screen.dart` (unused after badge removal; class and tests still exist).
- **`permission_handler: ^11.3.1`** added to `pubspec.yaml`. `_requestCameraPermission()` in `initState` explicitly requests camera permission before `YOLOView` renders. `_cameraReady` flag gates rendering.
- **iOS Podfile** -- `PERMISSION_CAMERA=1` macro added to `GCC_PREPROCESSOR_DEFINITIONS` (required by `permission_handler`).
- **`memory-bank/issueLog.md`** created -- 9 issues with root causes and verified solutions (AAPT compression, cert expiry, camera permission, UTF-8, coordinate mirroring, aspect ratio, stale extrapolation, audio state, rotate overlay).

### Root Cause Investigation
- iOS "Unable to Verify" error: Free Apple Developer certificates expire every 7 days (timing coincidence with code change).
- Camera not working after reinstall: `ultralytics_yolo` v0.2.0 checks but never requests camera permission on iOS (`VideoCapture.swift` lines 86-95). Deleting app wipes permission state. Android side of plugin does request permissions — platform asymmetry bug.

### Verification
```
$ flutter analyze -- 0 errors, 0 warnings, 0 infos
$ flutter test -- 81/81 passing
Device-verified on iPhone 12 and Galaxy A32
```

---

## Phase 3: Impact Detection + Zone Mapping + Result Display (2026-03-09)

### Summary
Implemented the full impact detection state machine with multi-signal decision logic, zone mapping, and visual result display. Device-verified on both iPhone 12 and Galaxy A32. UI labels repositioned to bottom-right per user feedback. 70/70 tests passing.

### New Files
- **`lib/models/impact_event.dart`** -- Immutable value type with `ImpactResult` enum (hit/miss/noResult), zone number, camera/target points, timestamp
- **`lib/services/impact_detector.dart`** -- State machine (Ready -> Tracking -> Result -> Ready), multi-signal decision (trajectory extrapolation + frame-edge exit filter), configurable cooldown (default 3s)
- **`test/impact_detector_test.dart`** -- 12 unit tests covering all state transitions, edge detection, priority ordering, cooldown, force reset

### Modified Files
- **`lib/services/target_zone_mapper.dart`** -- Added `zoneCorners(int zone)` method returning 4 corner Offsets in camera-space
- **`lib/screens/live_object_detection/widgets/calibration_overlay.dart`** -- Added `highlightZone` parameter + `_paintZoneHighlight()` for yellow semi-transparent zone fill
- **`lib/screens/live_object_detection/live_object_detection_screen.dart`** -- Wired `ImpactDetector`, added: large centered result overlay (72px zone number or "MISS"), status text badge (bottom-right), zone highlight via `CalibrationOverlay`, "Ball lost" badge suppression during result phase, `forceReset()` on calibration and dispose

### UI Refinement
- Moved status text badge from bottom-center to **bottom-right** (`Positioned bottom:16, right:16`)
- Moved calibration instruction text from bottom-center to **bottom-right** (`Positioned bottom:16, right:16`)
- Reason: bottom-center labels were blocking the camera view during active use

### Device Testing
- Tested on iPhone 12 and Galaxy A32 using penalty shoot video on laptop
- All features confirmed: MISS labels, zone hit numbers, yellow highlight, tracking status, 3-second auto-reset
- Bottom-right label positioning confirmed comfortable on both devices

### Verification
```
$ flutter analyze -- 0 errors, 0 warnings, 0 infos
$ flutter test -- 70/70 passing
```

---

## Code Quality Cleanup (2026-02-23)

## Summary

Resolved all 7 `flutter analyze` issues (0 remaining) and 1 failing test (now 3 passing).

## Changes by File

### lib/main.dart
- **Removed iOS diagnostic probe** (lines 23–34) — temporary `try/catch` block that attempted to load `yolo11n.tflite` from Flutter assets on iOS. This was documented technical debt in `activeContext.md`; it always failed by design and produced noisy logs. The real iOS model loads via the Xcode bundle separately.
- **Replaced `print()` with `log()`** (line 21) — `print('DETECTOR_BACKEND = $backend')` changed to `log(...)` from `dart:developer` to satisfy `avoid_print` lint.
- **Removed unused imports** — `dart:io` and `package:tflite_flutter/tflite_flutter.dart` were only used by the diagnostic probe.

### lib/screens/home/home_screen_store.dart
- **Added lint suppression** — `// ignore_for_file: library_private_types_in_public_api` at file top. This is the standard MobX code-gen pattern (`class HomeScreenStore = _HomeScreenStore with _$HomeScreenStore`) and cannot be restructured without breaking the MobX mixin.

### lib/screens/live_object_detection/live_object_detection_screen.dart
- **Replaced deprecated `withOpacity()`** (lines 187, 210) — `Colors.white.withOpacity(0.3)` changed to `Colors.white.withValues(alpha: 0.3)` on both the gallery and flip-camera buttons. The `withOpacity` API was deprecated in favour of `withValues` to avoid precision loss.
- **Replaced `print()` with `log()`** (line 291) — camera preview size debug output changed from `print` to `dart:developer` `log()` to satisfy `avoid_print` lint.

### test/widget_test.dart
- **Replaced stale counter app test** with meaningful `DetectorConfig` unit tests:
  1. Verifies default backend is `tflite` when no `DETECTOR_BACKEND` env var is set
  2. Verifies label returns `'TFLite'` for the default backend
  3. Verifies the `DetectorBackend` enum contains all expected values (`tflite`, `yolo`, `mlkit`)
- The previous test pumped `MyApp` and asserted counter widget text that doesn't exist in this app. The new tests verify actual project logic without triggering HTTP calls or native plugin dependencies.

## Verification

```
$ flutter analyze
Analyzing object_detection...
No issues found! (ran in 2.2s)

$ flutter test
00:02 +3: All tests passed!
```
