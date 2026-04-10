# Roadmap: Flare Football Object Detection POC

## Milestones

- ✅ **v1.0 Detection Feasibility** — Phases 1-5 (shipped 2026-02-23)
- ✅ **v1.1 Ball Tracking** — Phases 6-8 (shipped 2026-02-24)
- ✅ **v1.2 Android Verification** — Phases 9-10 (shipped 2026-03-09)
- 🚧 **v1.3 Target Zone Impact Detection** — Phases 11-14 (in progress)

## Phases

<details>
<summary>✅ v1.0 Detection Feasibility (Phases 1-5) — SHIPPED 2026-02-23</summary>

Phases 1-5 predate the GSD workflow and are archived here for continuity.
Delivered: YOLO11n real-time detection on Android and iOS, SSD MobileNet fallback,
build-time backend switching, landscape orientation lock, bounding box rendering,
three-screen navigation, and evaluation evidence capture.

</details>

<details>
<summary>✅ v1.1 Ball Tracking (Phases 6-8) — SHIPPED 2026-02-24</summary>

Delivered: Debug dot overlay with FILL_CENTER coordinate mapping, BallTracker service
with time-windowed trail and occlusion handling, TrailOverlay CustomPainter with fading
dots and connecting lines, camera AR fix (4:3), "Ball lost" badge overlay.
All features device-verified on iPhone 12. See `.planning/milestones/v1.1-ROADMAP.md`.

</details>

<details>
<summary>✅ v1.2 Android Verification (Phases 9-10) — SHIPPED 2026-03-09</summary>

Delivered: aaptOptions fix for TFLite model loading, MethodChannel rotation polling
for Android coordinate correction, full feature parity with iOS on Galaxy A32.
Trail dots, connecting lines, and "Ball lost" badge verified on Android.

### Phase 9: Android Inference Diagnosis and Fix
**Goal**: The YOLO `onResult` callback delivers detection results to Flutter on the Galaxy A32 with the correct class name strings, and the root cause of its prior silence is identified, fixed, and documented.
**Depends on**: Phase 8 (v1.1 complete)
**Requirements**: DIAG-01, DIAG-02, DIAG-03, DIAG-04
**Plans**: 2 plans

Plans:
- [x] 09-01-PLAN.md — Apply aaptOptions fix to build.gradle and add DIAG-02/03 diagnostic log() calls to onResult callback
- [x] 09-02-PLAN.md — Run app on Galaxy A32, human-verify onResult fires with correct classNames, write 09-FINDINGS.md

### Phase 10: Android Feature Parity Verification
**Goal**: Trail dots, connecting lines, and the "Ball lost" badge all behave on the Galaxy A32 as they do on iPhone 12 — with coordinate accuracy empirically verified — and Android inference FPS is measured and documented.
**Depends on**: Phase 9
**Requirements**: PRTY-01, PRTY-02, PRTY-03, PRTY-04
**Plans**: 2 plans

Plans:
- [x] 10-01: Camera AR probe and coordinate accuracy verification
- [x] 10-02: Badge state verification and FPS measurement

</details>

### 🚧 v1.3 Target Zone Impact Detection (In Progress)

**Milestone Goal:** Detect which numbered zone (1-9) on a target sheet a kicked soccer ball hits, using trajectory prediction and multi-signal impact detection — extending the existing YOLO detection pipeline with pure Dart math.

**Prerequisites already complete:** Calibration mode (tap 4 corners), 8-parameter DLT homography transform, zone mapper with grid geometry, green wireframe grid overlay with zone numbers 1-9, inverse coordinate transform. All device-verified. 25 unit tests passing.

- [ ] **Phase 11: Kalman Filter and Trajectory Tracking** - Smooth YOLO detections and predict ball trajectory through missed frames
- [ ] **Phase 12: Impact Detection, Zone Mapping, and Visual Feedback** - Detect target impacts, map to zones 1-9, and display results with state machine
- [ ] **Phase 13: Audio Feedback** - Play zone number callouts and miss buzzer on impact events
- [ ] **Phase 14: Depth Estimation** - Filter false impacts using ball apparent size to estimate distance

## Phase Details

### Phase 11: Kalman Filter and Trajectory Tracking
**Goal**: Ball positions are smoothed by a Kalman filter that also predicts through brief occlusions, and per-frame velocity plus parabolic trajectory extrapolation are available to downstream consumers
**Depends on**: Phase 10 (v1.2 complete) + v1.3 Phase 1 calibration (already built)
**Requirements**: TRAJ-01, TRAJ-02, TRAJ-03, TRAJ-04
**Success Criteria** (what must be TRUE):
  1. When the ball moves across the screen, the trail path is visibly smoother than raw YOLO detections — less jitter frame-to-frame
  2. When the ball is briefly occluded (up to ~5 frames / ~170ms at 30fps), the predicted position continues along the ball's last trajectory rather than showing a gap
  3. Ball velocity (vx, vy in normalized units per frame) is computed each frame and accessible via the tracker API
  4. Given a sequence of tracked positions approaching the calibrated target plane, the system can extrapolate the trajectory to compute a predicted intersection point
**Plans**: 3 plans

Plans:
- [x] 11-01-PLAN.md — TDD: 4-state Kalman filter service (px, py, vx, vy) with unit tests
- [ ] 11-02-PLAN.md — Integrate Kalman into BallTracker for smoothing, occlusion prediction, and velocity API
- [ ] 11-03-PLAN.md — Parabolic trajectory extrapolation to target plane + wiring into live detection screen

### Phase 12: Impact Detection, Zone Mapping, and Visual Feedback
**Goal**: The app detects when a kicked ball hits the calibrated target, maps the impact to zone 1-9, displays the result with zone highlighting and a large number overlay, and cycles through a Ready/Tracking/Result/Cooldown state machine — or correctly identifies a miss
**Depends on**: Phase 11 (needs velocity data and trajectory extrapolation)
**Requirements**: IMPACT-01, IMPACT-02, IMPACT-03, IMPACT-04, IMPACT-05, IMPACT-06, VISUAL-01, VISUAL-02, VISUAL-03, VISUAL-04, VISUAL-05
**Success Criteria** (what must be TRUE):
  1. When a ball is kicked at the calibrated target and hits it, the app detects the impact and displays the correct zone number (1-9) as a large overlay within ~100ms of impact
  2. The hit zone cell highlights yellow on the green wireframe grid overlay, making it visually obvious which zone was struck
  3. When a ball misses the target (exits frame edge or trajectory does not intersect target area), "MISS" is displayed in red — and last detections within 8% of frame edge are not falsely reported as hits
  4. The screen shows the current state — "Ready" when waiting for a kick, "Tracking" when ball motion is detected, the zone result on impact — and auto-resets to Ready after a 3-second cooldown
  5. The state machine cycles correctly through multiple consecutive kicks without getting stuck: Ready -> Tracking -> Result -> Cooldown -> Ready
**Plans**: TBD

### Phase 13: Audio Feedback
**Goal**: Impact and miss events produce immediate audio feedback — a spoken zone number (1-9) on hit, a buzzer on miss — on both iOS and Android
**Depends on**: Phase 12 (needs impact events to trigger audio)
**Requirements**: AUDIO-01, AUDIO-02, AUDIO-03
**Success Criteria** (what must be TRUE):
  1. When a zone hit is detected, the corresponding number (e.g., "seven") is spoken aloud within ~200ms of the visual result appearing
  2. When a miss is detected, a distinct buzzer sound plays instead of a number
  3. Audio playback works on both iPhone 12 (iOS) and Galaxy A32 (Android) without crashes or silence
**Plans**: TBD

### Phase 14: Depth Estimation
**Goal**: Ball distance from the camera is estimated using apparent bounding box size, and impacts are rejected as false positives when the ball has not actually reached the target's physical distance
**Depends on**: Phase 11 (needs bounding box area tracking), Phase 12 (refines impact detection logic)
**Requirements**: DEPTH-01, DEPTH-02, DEPTH-03
**Success Criteria** (what must be TRUE):
  1. The app tracks ball bounding box area across frames, and the value increases as the ball approaches the target (observable in debug output or logs)
  2. Distance-to-ball is estimated in meters using the known soccer ball diameter (22cm) and calibration-derived focal length, and the estimate is within reasonable accuracy (logged per frame)
  3. An impact event is suppressed (not reported as a hit) when the estimated ball depth indicates it has not yet reached the target distance — preventing false positives from trajectory-only detection
**Plans**: TBD

## Progress

**Execution Order:** 11 -> 12 -> 13 -> 14

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1-5. Detection Feasibility | v1.0 | — | Complete | 2026-02-23 |
| 6. Overlay Foundation | v1.1 | 2/2 | Complete | 2026-02-23 |
| 7. Trail Accumulation and Rendering | v1.1 | 3/3 | Complete | 2026-02-23 |
| 8. Polish | v1.1 | 1/1 | Complete | 2026-02-24 |
| 9. Android Inference Diagnosis and Fix | v1.2 | 2/2 | Complete | 2026-02-25 |
| 10. Android Feature Parity Verification | v1.2 | 2/2 | Complete | 2026-03-09 |
| 11. Kalman Filter and Trajectory Tracking | v1.3 | 1/3 | In progress | - |
| 12. Impact Detection, Zone Mapping, and Visual Feedback | v1.3 | 0/? | Not started | - |
| 13. Audio Feedback | v1.3 | 0/? | Not started | - |
| 14. Depth Estimation | v1.3 | 0/? | Not started | - |
