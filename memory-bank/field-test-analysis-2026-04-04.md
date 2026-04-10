# Field Test Analysis — 2026-04-04

> **⚠️ CRITICAL: NEVER run `git commit`, `git push`, `git init`, or any git write commands. This project has NO git repository. It is local-only by explicit developer decision. This rule is ABSOLUTE and has been violated in the past — do NOT repeat.**

## Test Environment
- **Device:** iPhone 12 (iOS)
- **Target:** Flare Player banner (1760x1120mm) mounted on solid green metal fence
- **Pitch:** Artificial turf, small-sided football cage
- **Ball:** Red/white soccer ball (~220mm diameter)
- **Connection:** USB cable to MacBook (live flutter run with terminal output)

## Phase 1 Setup
- **Tripod height:** ~0.75-0.8m (waist level, tester height 5'11")
- **Tripod to target:** ~11m
- **Ball to target:** ~8m
- **Tripod to ball:** ~3m behind ball
- **Tripod position:** Centered on target
- **Ball position:** Right side of camera, slight angle (kicker doesn't occlude ball)
- **Phone orientation:** Right-sided landscape

## Phase 2 Setup
- **Same as Phase 1 EXCEPT:** Tripod height raised to ~1.2-1.3m (chest level)

## Results Summary

### Phase 1: 18 kicks
- **Accuracy: 7/18 correct (38.9%)**
- **Premature announcement: 14/18 (78%)**
- **Zone 6 reported 11/18 times — actual zone 6 hits: 0**

### Phase 2: 9 kicks
- **Accuracy: 1/9 correct (11.1%)**
- **Premature announcement: 9/9 (100%)**
- **Zone 1/2 dominated — shifted from Phase 1's zone 6 bias**

## ROOT CAUSE: Target Circle False Positives (ISSUE-022)

### Primary Problem
The 9 red LED-ringed circles on the Flare Player banner are detected by YOLO as soccer balls. At confidence threshold 0.25, these circles fire as `Soccer ball` or `ball` detections **constantly** — whether or not a real ball is present.

### Evidence (41 screenshots analyzed)
1. **Static false positives:** Orange dots appear on target circles with NO ball in flight, NO ball near target. Ball sitting on ground at kicker's feet. Multiple screenshots show single dots sitting on zone 6, zone 7, zone 5 areas of the target with no real ball anywhere near.

2. **False trails from camera shake:** Shaking the phone while pointing at the target creates orange dot trails hopping between different target circles. YOLO alternates between detecting different circles frame-to-frame, creating the illusion of ball movement. This triggers zone announcements with no ball kicked.

3. **Mid-flight contamination:** During actual kicks, `_pickBestBallYolo` alternates between real ball and target circle false positives. As the real ball approaches the target, false circle detections become spatially closer to the "expected" ball position, winning the nearest-neighbor tiebreaker. Trail dots scatter/jump between real ball and false detections.

4. **Premature decisions:** A target circle detection appears ON the wall (depth ratio ~1.0), INSIDE a zone (directZone returns a zone), and stationary — identical to "ball has impacted the target" for the pipeline. ImpactDetector triggers based on false detection data.

### Why existing phase-aware filter doesn't catch this
`_applyPhaseFilter()` uses spatial gating — accepts detections near last known position or Kalman prediction. Target circle detections are IN the target grid area, which is exactly where the ball is expected to arrive. The spatial gate cannot distinguish "real ball at the target" from "false detection on a target circle that was always there."

### Why this explains all observed symptoms
- **Zone 6 bias (Phase 1):** Zone 6 circle most consistently detected from waist-height angle
- **Zone 1/2 bias (Phase 2):** Higher camera changes which circles are most prominent
- **"Too soon" announcements:** False circle detection = "ball at target" to the pipeline
- **Correct kicks (7/18):** Real ball confidence was high enough throughout flight that _pickBestBallYolo never switched to a circle
- **Scattered trail dots:** Trail jumping between real ball and false circle detections

### Deeper Architectural Problem Identified
The false positive problem exposed a fundamental flaw: **the pipeline has no concept of object identity.** Every frame, `_pickBestBallYolo` selects from scratch with no memory of which specific object was being tracked. This was a fragmented architecture — centroid extracted from bbox (discarding size), 4-state Kalman (no depth tracking), WallPlanePredictor bolted on to compensate for missing depth, phase filters bolted on to compensate for false positives. Each was a partial solution that didn't fully solve its problem.

## SOLUTION DECIDED: ByteTrack Implementation (Pure Dart)

### Architecture Decision (2026-04-05)
Replace the fragmented detection/tracking pipeline with a **complete ByteTrack implementation** in pure Dart:

- **Full ByteTrack algorithm** (Zhang et al., 2022) — not partial SORT, not cherry-picked features
- **8-state Kalman filter per track** (cx, cy, w, h, vx, vy, vw, vh) — tracks full bounding box including rate of change of width and height
- **Two-pass IoU matching** — first pass high-confidence (≥0.5), second pass low-confidence (0.25-0.5) matched to remaining tracks
- **Track state categories** — tracked, lost, removed (ByteTrack's full lifecycle)
- **BallIdentifier service** — identifies the ball among tracks by behavior (the only moving ball-class track), not by fixed ID. Automatically re-acquires ball after each kick cycle.

### What this solves
1. **ISSUE-022 (target circle false positives)** — circles get their own static track IDs, never confused with the ball
2. **All future false positives** — any non-ball object gets its own track, automatically ignored
3. **Premature announcements** — only the real ball's velocity/position feeds decisions
4. **Depth tracking** — bbox area tracked in Kalman state, not computed as side calculation
5. **Player experience** — set up once, play forever. No re-confirmation between kicks.

### What gets removed
- `_pickBestBallYolo()`, `_applyPhaseFilter()`, `_squaredDist()` — replaced by ByteTrack matching
- `BallTracker` + `BallKalmanFilter` — replaced by ByteTrack's 8-state Kalman
- `WallPlanePredictor` — depth tracked in Kalman state
- `TrajectoryExtrapolator` — subsumed by Kalman prediction
- ~800-1000 lines of fragmented code

### What stays unchanged
- Calibration (homography, zone mapper, calibration overlay)
- KickDetector (kick gate, fed from ByteTrack velocity)
- ImpactDetector (simplified — direct zone mapping + Kalman extrapolation)
- AudioService, DiagnosticLogger, TrailOverlay, UI, navigation

## ByteTrack Device Test (2026-04-06, iPhone 12)

### What was FIXED
- **Target circle false positives (ISSUE-022): FIXED.** Shaking phone at target produces NO false dots on circles. BallIdentifier correctly locks onto soccer ball (red bbox confirmed). No false zone announcements from static circles.
- **Ball lock-on working:** `trackId=1` correctly assigned after Confirm. Red bounding box shows on correct object.
- **setReferenceTrack fix:** Initially returned `trackId=null` because stationary ball was flagged `isStatic=true`. Fixed by allowing static tracks during reference capture.

### What FAILED (ISSUE-023)
- **Ball track lost during fast kick flight.** 0/3 kicks detected. All `noResult`.
- Ball moves 2x its bbox width in 1 frame at kick onset → IoU=0 → ByteTrack fails to match → track lost
- `directZone=null` for every tracking frame — ball never registered as entering the grid
- Trail dots only visible at kicking spot (stationary) and during slow retrieval (walking with ball)
- Track IDs jump: 1→26→28→29→39→52 across one session

### Test Data
- **CSV:** `/Users/shashank/Documents/Log files/flare_diag_20260406_014309.csv` (1110 lines, 2 DECISION rows)
- **Screenshots:** `/Users/shashank/Documents/ScreenShots/ByteTrackTesting/` (7 files)
- **Screen recording (shake test):** `/Users/shashank/Documents/app behaviour images/ScreenRecording_04-06-2026*`

## Data Files (Original Pre-ByteTrack Test 2026-04-04)
- **Phase 1 CSV:** `/Users/shashank/Documents/Log files/flare_diag_20260402_135532.csv` (6179 lines, 20 DECISION rows)
- **Phase 2 CSV:** `/Users/shashank/Documents/Log files/flare_diag_20260402_140241.csv` (5080 lines, 11 DECISION rows)
- **Phase 1 terminal log:** `/Users/shashank/Documents/Terminal log/terminal-log-phase1.docx` (36 IMPACT DECISION blocks)
- **Phase 2 terminal log:** `/Users/shashank/Documents/Terminal log/terminal-log-phase2.docx`
- **Phase 1 kick screenshots:** `/Users/shashank/Documents/ScreenShots/phase1/` (19 files)
- **Phase 2 kick screenshots:** `/Users/shashank/Documents/ScreenShots/phase2/` (10 files)
- **False positive evidence:** `/Users/shashank/Documents/app behaviour images/False positive on goal post/` (41 files)
